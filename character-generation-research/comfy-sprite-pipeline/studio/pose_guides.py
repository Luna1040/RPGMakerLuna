from __future__ import annotations

import math
from copy import deepcopy
from pathlib import Path
from typing import Any, Mapping, Sequence

import cv2
import numpy as np
from PIL import Image, ImageChops, ImageDraw

from tools.render_openpose import render_pose

from .catalog import POSE_GUIDE_MOTIONS


Point = tuple[float, float, float]
PointMap = dict[int, Point]
KeypointInput = Mapping[int | str, Sequence[float]] | Sequence[Sequence[float] | None]


# COCO-18-compatible neutral template in its original 384 x 384 authoring space.
# It remains public because callers may persist it as a fallback anchor contract.
BASE_POINTS: PointMap = {
    0: (192, 75, 1),
    1: (192, 128, 1),
    2: (154, 142, 1),
    3: (143, 202, 1),
    4: (139, 265, 1),
    5: (230, 142, 1),
    6: (241, 202, 1),
    7: (245, 265, 1),
    8: (169, 238, 1),
    9: (166, 299, 1),
    10: (164, 354, 1),
    11: (215, 238, 1),
    12: (218, 299, 1),
    13: (220, 354, 1),
}

_TEMPLATE_BBOX = (
    min(point[0] for point in BASE_POINTS.values()),
    min(point[1] for point in BASE_POINTS.values()),
    max(point[0] for point in BASE_POINTS.values()),
    max(point[1] for point in BASE_POINTS.values()),
)


def _ease(t: float) -> float:
    """Closed cosine action curve: neutral with zero velocity at both ends."""

    return 0.5 - 0.5 * math.cos(2.0 * math.pi * t)


def _raised_cosine(t: float) -> float:
    value = min(1.0, max(0.0, float(t)))
    return 0.5 - 0.5 * math.cos(math.pi * value)


def _lerp(a: float, b: float, amount: float) -> float:
    return a + (b - a) * amount


def _move(points: PointMap, index: int, target: tuple[float, float], amount: float) -> None:
    x, y, confidence = points[index]
    points[index] = (_lerp(x, target[0], amount), _lerp(y, target[1], amount), confidence)


def _coerce_bbox(
    bbox: Sequence[float] | None,
    *,
    width: int,
    height: int,
) -> tuple[float, float, float, float] | None:
    if bbox is None:
        return None
    if len(bbox) != 4:
        raise ValueError("anchor_bbox must contain left, top, right, bottom")
    left, top, right, bottom = (float(value) for value in bbox)
    if not all(math.isfinite(value) for value in (left, top, right, bottom)):
        raise ValueError("anchor_bbox values must be finite")
    if right <= left or bottom <= top:
        raise ValueError("anchor_bbox must have positive width and height")
    if left < 0 or top < 0 or right > width or bottom > height:
        raise ValueError("anchor_bbox must remain inside the guide canvas")
    return left, top, right, bottom


def _iter_keypoints(keypoints: KeypointInput | None) -> list[tuple[int, Sequence[float]]]:
    if keypoints is None:
        return []
    if isinstance(keypoints, Mapping):
        items: list[tuple[int, Sequence[float]]] = []
        for raw_index, value in keypoints.items():
            try:
                index = int(raw_index)
            except (TypeError, ValueError) as exc:
                raise ValueError("anchor keypoint indices must be integers") from exc
            items.append((index, value))
        return items
    return [(index, value) for index, value in enumerate(keypoints) if value is not None]


def resolve_anchor_points(
    *,
    width: int,
    height: int,
    anchor_keypoints: KeypointInput | None = None,
    anchor_bbox: Sequence[float] | None = None,
) -> PointMap:
    """Resolve neutral guide points in output pixels.

    A supplied bounding box first maps the authored neutral template to the
    accepted character silhouette.  Valid keypoints then override individual
    fallback joints.  This makes partial DWPose/OpenPose results usable while
    keeping every required torso/limb point defined.
    """

    if width <= 0 or height <= 0:
        raise ValueError("guide width and height must be positive")
    bbox = _coerce_bbox(anchor_bbox, width=width, height=height)
    template_left, template_top, template_right, template_bottom = _TEMPLATE_BBOX
    if bbox is None:
        sx, sy = width / 384.0, height / 384.0
        fallback: PointMap = {
            index: (x * sx, y * sy, confidence)
            for index, (x, y, confidence) in BASE_POINTS.items()
        }
    else:
        left, top, right, bottom = bbox
        sx = (right - left) / (template_right - template_left)
        sy = (bottom - top) / (template_bottom - template_top)
        fallback = {
            index: (
                left + (x - template_left) * sx,
                top + (y - template_top) * sy,
                confidence,
            )
            for index, (x, y, confidence) in BASE_POINTS.items()
        }

    for index, value in _iter_keypoints(anchor_keypoints):
        if index not in BASE_POINTS:
            continue
        if not isinstance(value, Sequence) or len(value) < 2:
            raise ValueError("each anchor keypoint must contain x and y")
        x, y = float(value[0]), float(value[1])
        confidence = float(value[2]) if len(value) > 2 else 1.0
        if not all(math.isfinite(item) for item in (x, y, confidence)):
            raise ValueError("anchor keypoint values must be finite")
        if confidence <= 0:
            continue
        if x < 0 or y < 0 or x > width or y > height:
            raise ValueError("anchor keypoints must remain inside the guide canvas")
        fallback[index] = (x, y, confidence)
    return fallback


def _anchor_transform(points: PointMap) -> tuple[float, float, float, float]:
    left = min(point[0] for point in points.values())
    top = min(point[1] for point in points.values())
    right = max(point[0] for point in points.values())
    bottom = max(point[1] for point in points.values())
    template_left, template_top, template_right, template_bottom = _TEMPLATE_BBOX
    sx = max(1e-6, (right - left) / (template_right - template_left))
    sy = max(1e-6, (bottom - top) / (template_bottom - template_top))
    return left - template_left * sx, top - template_top * sy, sx, sy


def pose_at(
    motion_id: str,
    t: float,
    *,
    base_points: Mapping[int, Sequence[float]] | None = None,
) -> PointMap:
    """Return a neutral-relative pose for normalized action time ``t``."""

    if motion_id not in POSE_GUIDE_MOTIONS:
        raise ValueError(f"pose guide is not implemented for {motion_id}")
    if not math.isfinite(float(t)) or not 0.0 <= float(t) <= 1.0:
        raise ValueError("pose time must be finite and in 0..1")
    if base_points is None:
        neutral = deepcopy(BASE_POINTS)
    else:
        neutral = {}
        for index in BASE_POINTS:
            if index not in base_points or len(base_points[index]) < 2:
                raise ValueError("base_points must contain every template joint")
            value = base_points[index]
            neutral[index] = (
                float(value[0]),
                float(value[1]),
                float(value[2]) if len(value) > 2 else 1.0,
            )
    points = deepcopy(neutral)
    origin_x, origin_y, sx, sy = _anchor_transform(neutral)

    def target(x: float, y: float) -> tuple[float, float]:
        return origin_x + x * sx, origin_y + y * sy

    amount = _ease(float(t))

    if motion_id in {"idle_breathing", "idle_smile"}:
        for index, vertical in ((0, -3.0), (1, -2.0), (2, -2.0), (5, -2.0), (8, 1.0), (11, 1.0)):
            x, y, confidence = points[index]
            points[index] = (x, y + vertical * sy * amount, confidence)
    elif motion_id == "bounce":
        for index in (0, 1, 2, 3, 4, 5, 6, 7, 8, 11):
            x, y, confidence = points[index]
            points[index] = (x, y + 11 * sy * amount, confidence)
        for index, direction in ((9, -1), (12, 1)):
            x, y, confidence = points[index]
            points[index] = (x + direction * 7 * sx * amount, y + 5 * sy * amount, confidence)
    elif motion_id == "jump_vertical":
        lift = 48 * sy * amount
        for index in points:
            x, y, confidence = points[index]
            points[index] = (x, y - lift, confidence)
        for index, direction in ((9, -1), (12, 1)):
            x, y, confidence = points[index]
            points[index] = (x + direction * 9 * sx * amount, y + 8 * sy * amount, confidence)
    elif motion_id in {"walk_in_place", "run_in_place"}:
        phase = math.sin(2.0 * math.pi * float(t))
        cadence = math.sin(4.0 * math.pi * float(t))
        stride = (38 if motion_id == "run_in_place" else 26) * sx
        lift = (24 if motion_id == "run_in_place" else 14) * sy
        bob = (7 if motion_id == "run_in_place" else 3) * sy * (phase * phase)
        for index in (0, 1, 2, 5, 8, 11):
            x, y, confidence = points[index]
            points[index] = (x, y - bob, confidence)
        for hip, knee, ankle, direction in ((11, 12, 13, 1.0), (8, 9, 10, -1.0)):
            leg_phase = phase * direction
            x, y, confidence = points[knee]
            points[knee] = (x + stride * 0.45 * leg_phase, y - max(0.0, leg_phase) * lift * 0.45 - bob, confidence)
            x, y, confidence = points[ankle]
            points[ankle] = (x + stride * leg_phase, y - max(0.0, leg_phase) * lift - bob, confidence)
        arm_swing = (24 if motion_id == "run_in_place" else 15) * sy * phase
        for elbow, wrist, direction in ((6, 7, -1.0), (3, 4, 1.0)):
            x, y, confidence = points[elbow]
            points[elbow] = (x, y + arm_swing * 0.45 * direction, confidence)
            x, y, confidence = points[wrist]
            points[wrist] = (x, y + arm_swing * direction + cadence * 2 * sy, confidence)
    elif motion_id in {"wave_left", "wave_right"}:
        anatomical_left = motion_id == "wave_left"
        elbow, wrist = (6, 7) if anatomical_left else (3, 4)
        direction = 1 if anatomical_left else -1
        wave = math.sin(6.0 * math.pi * float(t)) * amount
        _move(points, elbow, target(192 + direction * 68, 125), amount)
        _move(points, wrist, target(192 + direction * (55 + 15 * wave), 72), amount)
    elif motion_id in {"point_left", "point_right", "present_left", "present_right"}:
        anatomical_left = motion_id.endswith("left")
        elbow, wrist = (6, 7) if anatomical_left else (3, 4)
        direction = 1 if anatomical_left else -1
        vertical = 153 if motion_id.startswith("point") else 170
        _move(points, elbow, target(192 + direction * 62, vertical), amount)
        _move(points, wrist, target(192 + direction * 123, vertical - 3), amount)
    elif motion_id == "shrug":
        for index, canonical in ((3, (140, 165)), (4, (104, 144)), (6, (244, 165)), (7, (280, 144))):
            _move(points, index, target(*canonical), amount)
    elif motion_id == "clap_once":
        for index, canonical in ((3, (165, 173)), (4, (187, 172)), (6, (219, 173)), (7, (197, 172))):
            _move(points, index, target(*canonical), amount)
    elif motion_id == "welcome":
        for index, canonical in ((3, (128, 146)), (4, (72, 130)), (6, (256, 146)), (7, (312, 130))):
            _move(points, index, target(*canonical), amount)
    elif motion_id in {"look_left", "look_right", "look_up", "look_down", "nod", "shake_head"}:
        x, y, confidence = points[0]
        if motion_id == "look_left":
            x += 18 * sx * amount
        elif motion_id == "look_right":
            x -= 18 * sx * amount
        elif motion_id == "look_up":
            y -= 13 * sy * amount
        elif motion_id in {"look_down", "nod"}:
            y += 14 * sy * amount
        elif motion_id == "shake_head":
            x += math.sin(4.0 * math.pi * float(t)) * 18 * sx * math.sin(math.pi * float(t))
        points[0] = (x, y, confidence)
    elif motion_id in {"lean_left", "lean_right"}:
        direction = 1 if motion_id == "lean_left" else -1
        for index in (0, 1, 2, 3, 4, 5, 6, 7):
            x, y, confidence = points[index]
            template_y = BASE_POINTS[index][1]
            vertical_weight = max(0.25, (238 - template_y) / 170)
            points[index] = (x + direction * 22 * sx * amount * vertical_weight, y, confidence)

    return points


def _scaled_points(points: PointMap) -> list[Point | None]:
    result: list[Point | None] = [None] * 18
    for index, point in points.items():
        result[index] = point
    return result


def _mask_for(
    motion_id: str,
    points: PointMap,
    neutral_points: PointMap,
    width: int,
    height: int,
    *,
    opacity: float,
) -> Image.Image:
    mask = Image.new("L", (width, height), 0)
    if opacity <= 0:
        return mask
    draw = ImageDraw.Draw(mask)

    def point(source: Mapping[int, Point], index: int) -> tuple[int, int]:
        x, y, _ = source[index]
        return round(x), round(y)

    _, _, sx, sy = _anchor_transform(neutral_points)
    arm_width = max(20, round(42 * min(sx, sy)))
    body_width = max(24, round(48 * min(sx, sy)))

    def draw_full_body(source: Mapping[int, Point]) -> None:
        head_x, head_y = point(source, 0)
        draw.ellipse(
            (
                head_x - round(54 * sx),
                head_y - round(60 * sy),
                head_x + round(54 * sx),
                head_y + round(60 * sy),
            ),
            fill=255,
        )
        draw.polygon([point(source, index) for index in (2, 5, 11, 8)], fill=255)
        for chain_indices in ((2, 3, 4), (5, 6, 7), (8, 9, 10), (11, 12, 13)):
            chain = [point(source, index) for index in chain_indices]
            draw.line(chain, fill=255, width=body_width, joint="curve")
            end_x, end_y = chain[-1]
            draw.ellipse(
                (end_x - body_width // 2, end_y - body_width // 2, end_x + body_width // 2, end_y + body_width // 2),
                fill=255,
            )

    if motion_id in {"idle_breathing", "idle_smile", "bounce", "jump_vertical", "walk_in_place", "run_in_place"}:
        draw_full_body(neutral_points)
        draw_full_body(points)
    elif motion_id.endswith("left") and motion_id.split("_")[0] in {"wave", "point", "present"}:
        indices = (5, 6, 7)
        chain = [point(points, index) for index in indices]
        neutral = [point(neutral_points, index) for index in indices]
        draw.line(neutral, fill=255, width=arm_width, joint="curve")
        draw.line(chain, fill=255, width=arm_width, joint="curve")
        draw.ellipse(
            (
                chain[-1][0] - arm_width // 2,
                chain[-1][1] - arm_width // 2,
                chain[-1][0] + arm_width // 2,
                chain[-1][1] + arm_width // 2,
            ),
            fill=255,
        )
    elif motion_id.endswith("right") and motion_id.split("_")[0] in {"wave", "point", "present"}:
        indices = (2, 3, 4)
        chain = [point(points, index) for index in indices]
        neutral = [point(neutral_points, index) for index in indices]
        draw.line(neutral, fill=255, width=arm_width, joint="curve")
        draw.line(chain, fill=255, width=arm_width, joint="curve")
        draw.ellipse(
            (
                chain[-1][0] - arm_width // 2,
                chain[-1][1] - arm_width // 2,
                chain[-1][0] + arm_width // 2,
                chain[-1][1] + arm_width // 2,
            ),
            fill=255,
        )
    elif motion_id in {"shrug", "clap_once", "welcome"}:
        for indices in ((2, 3, 4), (5, 6, 7)):
            chain = [point(points, index) for index in indices]
            neutral = [point(neutral_points, index) for index in indices]
            draw.line(neutral, fill=255, width=arm_width, joint="curve")
            draw.line(chain, fill=255, width=arm_width, joint="curve")
    elif motion_id.startswith("look_") or motion_id in {"nod", "shake_head"}:
        center_x, center_y = point(points, 0)
        rx, ry = round(58 * sx), round(66 * sy)
        draw.ellipse((center_x - rx, center_y - ry, center_x + rx, center_y + ry), fill=255)
    elif motion_id.startswith("lean_"):
        draw.polygon([point(points, index) for index in (2, 5, 11, 8)], fill=255)
        head_x, head_y = point(points, 0)
        rx, ry = round(64 * sx), round(68 * sy)
        draw.ellipse((head_x - rx, head_y - ry, head_x + rx, head_y + ry), fill=255)

    if opacity < 1:
        lut = [round(value * opacity) for value in range(256)]
        mask = mask.point(lut, mode="L")
    return mask


def _validate_timing(frames: int, neutral_corridor_frames: int, temporal_feather_frames: int) -> None:
    if frames < 5 or (frames - 1) % 4:
        raise ValueError("VACE guide frame count must be 4n+1 and at least 5")
    if not isinstance(neutral_corridor_frames, int) or isinstance(neutral_corridor_frames, bool):
        raise ValueError("neutral_corridor_frames must be an integer")
    if neutral_corridor_frames < 0 or frames - 2 * neutral_corridor_frames < 3:
        raise ValueError("neutral corridor must leave at least three action frames")
    if not isinstance(temporal_feather_frames, int) or temporal_feather_frames < 1:
        raise ValueError("temporal_feather_frames must be a positive integer")


def _action_time(index: int, frames: int, corridor: int) -> float | None:
    if index < corridor or index >= frames - corridor:
        return None
    if corridor == 0:
        return index / (frames - 1)
    return (index - corridor + 1) / (frames - 2 * corridor + 1)


def _mask_opacity(index: int, frames: int, corridor: int, feather: int) -> float:
    if index < corridor or index >= frames - corridor:
        return 0.0
    distance_from_start = index - corridor + 1
    distance_from_end = frames - corridor - index
    normalized = min(1.0, distance_from_start / feather, distance_from_end / feather)
    return _raised_cosine(normalized)


def build_pose_keypoints(
    motion_id: str,
    *,
    width: int,
    height: int,
    frames: int,
    neutral_corridor_frames: int = 4,
    temporal_feather_frames: int = 4,
    anchor_keypoints: KeypointInput | None = None,
    anchor_bbox: Sequence[float] | None = None,
) -> list[PointMap]:
    """Build the exact keypoint sequence consumed by ``build_guides``."""

    _validate_timing(frames, neutral_corridor_frames, temporal_feather_frames)
    neutral = resolve_anchor_points(
        width=width,
        height=height,
        anchor_keypoints=anchor_keypoints,
        anchor_bbox=anchor_bbox,
    )
    sequence: list[PointMap] = []
    for index in range(frames):
        action_time = _action_time(index, frames, neutral_corridor_frames)
        sequence.append(
            deepcopy(neutral)
            if action_time is None
            else pose_at(motion_id, action_time, base_points=neutral)
        )
    return sequence


def build_guides(
    motion_id: str,
    *,
    width: int,
    height: int,
    frames: int,
    neutral_corridor_frames: int = 4,
    temporal_feather_frames: int = 4,
    anchor_keypoints: KeypointInput | None = None,
    anchor_bbox: Sequence[float] | None = None,
    pose_points_override: Sequence[Mapping[int, Sequence[float]]] | None = None,
    extra_masks: Sequence[Image.Image] | None = None,
) -> tuple[list[Image.Image], list[Image.Image]]:
    """Build pose RGB frames and temporally feathered grayscale masks."""

    if pose_points_override is None:
        points_sequence = build_pose_keypoints(
            motion_id,
            width=width,
            height=height,
            frames=frames,
            neutral_corridor_frames=neutral_corridor_frames,
            temporal_feather_frames=temporal_feather_frames,
            anchor_keypoints=anchor_keypoints,
            anchor_bbox=anchor_bbox,
        )
    else:
        if len(pose_points_override) != frames:
            raise ValueError("pose_points_override must match the guide frame count")
        points_sequence = [
            {
                int(index): (
                    float(value[0]),
                    float(value[1]),
                    float(value[2] if len(value) > 2 else 1.0),
                )
                for index, value in frame.items()
            }
            for frame in pose_points_override
        ]
    if extra_masks is not None and len(extra_masks) != frames:
        raise ValueError("extra_masks must match the guide frame count")
    neutral = resolve_anchor_points(
        width=width,
        height=height,
        anchor_keypoints=anchor_keypoints,
        anchor_bbox=anchor_bbox,
    )
    poses: list[Image.Image] = []
    masks: list[Image.Image] = []
    for index, points in enumerate(points_sequence):
        opacity = _mask_opacity(
            index,
            frames,
            neutral_corridor_frames,
            temporal_feather_frames,
        )
        poses.append(render_pose(_scaled_points(points), width, height))
        mask = _mask_for(
                motion_id,
                points,
                neutral,
                width,
                height,
                opacity=opacity,
            )
        if extra_masks is not None:
            extra = extra_masks[index].convert("L")
            if extra.size != (width, height):
                raise ValueError("extra masks must match the guide canvas")
            mask = ImageChops.lighter(mask, extra)
        masks.append(mask)
    return poses, masks


def write_mp4(frames: list[Image.Image], path: Path, fps: int) -> Path:
    if not frames:
        raise ValueError("cannot write an empty guide")
    width, height = frames[0].size
    path.parent.mkdir(parents=True, exist_ok=True)
    writer = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*"mp4v"), float(fps), (width, height))
    if not writer.isOpened():
        raise RuntimeError(f"OpenCV could not create {path}")
    try:
        for frame in frames:
            if frame.size != (width, height):
                raise ValueError("all guide frames must have one canvas size")
            array = np.asarray(frame.convert("RGB"))
            writer.write(cv2.cvtColor(array, cv2.COLOR_RGB2BGR))
    finally:
        writer.release()
    return path


def write_lossless_mask_video(frames: list[Image.Image], path: Path, fps: int) -> Path:
    """Write exact 8-bit mask values to an FFV1 Matroska stream."""

    if not frames:
        raise ValueError("cannot write an empty mask guide")
    width, height = frames[0].size
    path.parent.mkdir(parents=True, exist_ok=True)
    writer = cv2.VideoWriter(
        str(path),
        cv2.VideoWriter_fourcc(*"FFV1"),
        float(fps),
        (width, height),
        False,
    )
    if not writer.isOpened():
        raise RuntimeError("OpenCV/FFmpeg does not provide the lossless FFV1 codec")
    try:
        for frame in frames:
            if frame.size != (width, height):
                raise ValueError("all mask frames must have one canvas size")
            writer.write(np.asarray(frame.convert("L"), dtype=np.uint8))
    finally:
        writer.release()
    return path


def write_pose_control_videos(
    motion_id: str,
    *,
    output_dir: Path,
    width: int,
    height: int,
    frames: int,
    fps: int,
    prefix: str | None = None,
    neutral_corridor_frames: int = 4,
    temporal_feather_frames: int = 4,
    anchor_keypoints: KeypointInput | None = None,
    anchor_bbox: Sequence[float] | None = None,
    pose_points_override: Sequence[Mapping[int, Sequence[float]]] | None = None,
    extra_masks: Sequence[Image.Image] | None = None,
) -> dict[str, Any]:
    poses, masks = build_guides(
        motion_id,
        width=width,
        height=height,
        frames=frames,
        neutral_corridor_frames=neutral_corridor_frames,
        temporal_feather_frames=temporal_feather_frames,
        anchor_keypoints=anchor_keypoints,
        anchor_bbox=anchor_bbox,
        pose_points_override=pose_points_override,
        extra_masks=extra_masks,
    )
    stem = prefix or motion_id
    pose_path = write_mp4(poses, output_dir / f"{stem}_pose.mp4", fps)
    mask_path = write_lossless_mask_video(masks, output_dir / f"{stem}_mask_ffv1.mkv", fps)
    return {
        "pose_video": pose_path,
        "mask_video": mask_path,
        "mask_codec": "ffv1",
        "mask_lossless": True,
        "mask_pixel_format": "gray8",
        "frames": frames,
        "fps": fps,
        "neutral_corridor_frames": neutral_corridor_frames,
        "temporal_feather_frames": temporal_feather_frames,
        "endpoint_masks_zero": not masks[0].getbbox() and not masks[-1].getbbox(),
    }


__all__ = [
    "BASE_POINTS",
    "build_guides",
    "build_pose_keypoints",
    "pose_at",
    "resolve_anchor_points",
    "write_lossless_mask_video",
    "write_pose_control_videos",
]
