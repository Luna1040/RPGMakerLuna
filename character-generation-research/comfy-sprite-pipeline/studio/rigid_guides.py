from __future__ import annotations

import math
from copy import deepcopy
from typing import Any, Mapping, Sequence

from PIL import Image, ImageChops, ImageDraw

from .rigid_props import (
    build_mask_sidecar_metadata,
    build_one_hand_trajectory,
    build_two_hand_staff_trajectory,
    contact_qc,
    make_transform,
    normalize_project_props,
    preflight_rigid_loadout,
    transform_point,
)


_ARM = {
    "left": {"shoulder": 5, "elbow": 6, "wrist": 7, "elbow_side": 1},
    "right": {"shoulder": 2, "elbow": 3, "wrist": 4, "elbow_side": -1},
}


def _xy(points: Mapping[int, Sequence[float]], index: int) -> tuple[float, float]:
    value = points[index]
    return float(value[0]), float(value[1])


def _hand_tracks(points: Sequence[Mapping[int, Sequence[float]]]) -> dict[str, list[dict[str, Any]]]:
    result: dict[str, list[dict[str, Any]]] = {"left": [], "right": []}
    for frame, pose in enumerate(points):
        for hand, indices in _ARM.items():
            result[hand].append(
                {
                    "frame": frame,
                    # COCO-18 has no palm center.  Its wrist landmark is the
                    # stable attachment point; elbow -> wrist supplies angle.
                    "palm": list(_xy(pose, indices["wrist"])),
                    "wrist": list(_xy(pose, indices["elbow"])),
                }
            )
    return result


def _rig_frames(points: Sequence[Mapping[int, Sequence[float]]]) -> list[dict[str, Any]]:
    frames: list[dict[str, Any]] = []
    for pose in points:
        frame: dict[str, Any] = {}
        for hand, indices in _ARM.items():
            shoulder = _xy(pose, indices["shoulder"])
            elbow = _xy(pose, indices["elbow"])
            wrist = _xy(pose, indices["wrist"])
            frame[hand] = {
                "shoulder": list(shoulder),
                "upper_length": math.dist(shoulder, elbow),
                "forearm_length": math.dist(elbow, wrist),
                "elbow_hint": list(elbow),
                "elbow_side": indices["elbow_side"],
            }
        frames.append(frame)
    return frames


def _configured_subset(project: Mapping[str, Any], normalized: dict[str, Any]) -> dict[str, Any]:
    configured_ids = {
        str(item.get("id"))
        for item in project.get("props", [])
        if isinstance(item, Mapping) and isinstance(item.get("rigid"), Mapping)
    }
    instances = [item for item in normalized.get("instances", []) if item.get("id") in configured_ids]
    asset_ids = {item.get("asset_id") for item in instances}
    return {
        **deepcopy(normalized),
        "instances": deepcopy(instances),
        "assets": [deepcopy(item) for item in normalized.get("assets", []) if item.get("id") in asset_ids],
    }


def _two_hand_anchor_transform(
    instance: Mapping[str, Any],
    pose: Mapping[int, Sequence[float]],
) -> dict[str, Any]:
    attachments = {str(item["hand"]): item for item in instance.get("attachments", [])}
    local_left = attachments["left"]["grip_point"]
    local_right = attachments["right"]["grip_point"]
    world_left = _xy(pose, _ARM["left"]["wrist"])
    world_right = _xy(pose, _ARM["right"]["wrist"])
    local_distance = math.dist(local_left, local_right)
    world_distance = math.dist(world_left, world_right)
    if local_distance <= 1e-6 or world_distance <= 1e-6:
        raise ValueError(f"two-hand grips collapse for {instance.get('id')}")
    local_angle = math.atan2(local_right[1] - local_left[1], local_right[0] - local_left[0])
    world_angle = math.atan2(world_right[1] - world_left[1], world_right[0] - world_left[0])
    rotation = math.degrees(world_angle - local_angle) + float(instance.get("rotation_offset_deg", 0.0))
    scale = world_distance / local_distance
    provisional = make_transform((0.0, 0.0), rotation, scale)
    mapped_left = transform_point(provisional, local_left)
    return make_transform(
        (world_left[0] - mapped_left[0], world_left[1] - mapped_left[1]),
        rotation,
        scale,
    )


def _apply_staff_ik(
    points: list[dict[int, tuple[float, float, float]]],
    trajectory: Mapping[str, Any],
) -> None:
    for frame_index, record in enumerate(trajectory.get("frames", [])):
        solutions = record.get("ik", {})
        for hand, indices in _ARM.items():
            solution = solutions.get(hand)
            if not isinstance(solution, Mapping) or not solution.get("reachable"):
                continue
            confidence = float(points[frame_index][indices["wrist"]][2])
            elbow = solution["elbow"]
            target = solution["target"]
            points[frame_index][indices["elbow"]] = (float(elbow[0]), float(elbow[1]), confidence)
            points[frame_index][indices["wrist"]] = (float(target[0]), float(target[1]), confidence)


def _temporal_opacity(index: int, frame_count: int, corridor: int, feather: int) -> float:
    if index < corridor or index >= frame_count - corridor:
        return 0.0
    distance = min(index - corridor + 1, frame_count - corridor - index)
    value = min(1.0, distance / max(1, feather))
    return 0.5 - 0.5 * math.cos(math.pi * value)


def _asset_map(normalized: Mapping[str, Any]) -> dict[str, Mapping[str, Any]]:
    return {str(item["id"]): item for item in normalized.get("assets", [])}


def _render_instance_masks(
    normalized: Mapping[str, Any],
    trajectories: Mapping[str, Any],
    *,
    width: int,
    height: int,
    neutral_corridor_frames: int,
    temporal_feather_frames: int,
    asset_sizes: Mapping[str, tuple[int, int]],
) -> dict[str, list[Image.Image]]:
    assets = _asset_map(normalized)
    result: dict[str, list[Image.Image]] = {}
    for instance in normalized.get("instances", []):
        instance_id = str(instance["id"])
        asset = assets[str(instance["asset_id"])]
        size = asset_sizes.get(instance_id)
        frames: list[Image.Image] = []
        records = trajectories[instance_id]["frames"]
        for index, record in enumerate(records):
            mask = Image.new("L", (width, height), 0)
            draw = ImageDraw.Draw(mask)
            transform = record["transform"]
            if size:
                source_width, source_height = size
                origin = asset.get("origin", [0.0, 0.0])
                if abs(float(origin[0])) > 1e-6 or abs(float(origin[1])) > 1e-6:
                    corners = [
                        (-float(origin[0]), -float(origin[1])),
                        (source_width - float(origin[0]), -float(origin[1])),
                        (source_width - float(origin[0]), source_height - float(origin[1])),
                        (-float(origin[0]), source_height - float(origin[1])),
                    ]
                else:
                    corners = [
                        (-source_width / 2, -source_height / 2),
                        (source_width / 2, -source_height / 2),
                        (source_width / 2, source_height / 2),
                        (-source_width / 2, source_height / 2),
                    ]
                draw.polygon([transform_point(transform, point) for point in corners], fill=255)
            axis = [transform_point(transform, point) for point in asset["handle_axis"]]
            draw.line(axis, fill=255, width=max(3, int(instance.get("mask_dilate_px", 6)) * 2 + 1))
            opacity = _temporal_opacity(
                index,
                len(records),
                neutral_corridor_frames,
                temporal_feather_frames,
            )
            if opacity < 1.0:
                mask = mask.point([round(value * opacity) for value in range(256)], mode="L")
            frames.append(mask)
        result[instance_id] = frames
    return result


def _render_contact_masks(
    normalized: Mapping[str, Any],
    trajectories: Mapping[str, Any],
    *,
    width: int,
    height: int,
    neutral_corridor_frames: int,
    temporal_feather_frames: int,
) -> dict[str, dict[str, list[Image.Image]]]:
    result: dict[str, dict[str, list[Image.Image]]] = {}
    for instance in normalized.get("instances", []):
        instance_id = str(instance["id"])
        by_hand: dict[str, list[Image.Image]] = {}
        records = trajectories[instance_id]["frames"]
        radius = int(instance.get("contact_radius_px", 16))
        for attachment in instance.get("attachments", []):
            hand = str(attachment["hand"])
            masks: list[Image.Image] = []
            for index, record in enumerate(records):
                mask = Image.new("L", (width, height), 0)
                draw = ImageDraw.Draw(mask)
                x, y = transform_point(record["transform"], attachment["grip_point"])
                draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=255)
                opacity = _temporal_opacity(
                    index,
                    len(records),
                    neutral_corridor_frames,
                    temporal_feather_frames,
                )
                if opacity < 1.0:
                    mask = mask.point([round(value * opacity) for value in range(256)], mode="L")
                masks.append(mask)
            by_hand[hand] = masks
        result[instance_id] = by_hand
    return result


def prepare_rigid_pose_guides(
    project: Mapping[str, Any],
    loadout_id: str,
    pose_points: Sequence[Mapping[int, Sequence[float]]],
    *,
    width: int,
    height: int,
    fps: int,
    neutral_corridor_frames: int,
    temporal_feather_frames: int,
    asset_sizes: Mapping[str, tuple[int, int]] | None = None,
) -> dict[str, Any]:
    """Build strict per-instance transforms and masks for explicitly rigid props."""

    normalized_all = normalize_project_props(project, loadout_id)
    normalized = _configured_subset(project, normalized_all)
    if not normalized["instances"]:
        return {
            "enabled": False,
            "pose_points": [deepcopy(dict(frame)) for frame in pose_points],
            "trajectories": {},
            "instance_masks": {},
            "contact_masks": {},
            "union_masks": [],
            "sidecar": None,
            "qc": None,
        }
    preflight = preflight_rigid_loadout(normalized, require_persistent=False)
    if not preflight["ok"]:
        messages = "; ".join(str(item.get("message")) for item in preflight["issues"] if item.get("severity") == "error")
        raise ValueError(f"rigid prop preflight failed: {messages}")

    points = [
        {int(index): (float(value[0]), float(value[1]), float(value[2] if len(value) > 2 else 1.0)) for index, value in frame.items()}
        for frame in pose_points
    ]
    trajectories: dict[str, Any] = {}
    for instance in normalized["instances"]:
        if instance.get("grip_mode") != "two_handed":
            continue
        base = _two_hand_anchor_transform(instance, points[0])
        transforms = [{**deepcopy(base), "frame": index} for index in range(len(points))]
        trajectory = build_two_hand_staff_trajectory(
            normalized,
            str(instance["id"]),
            transforms,
            rig_frames=_rig_frames(points),
        )
        if not trajectory["ok"]:
            raise ValueError(f"two-hand IK failed for {instance['id']}: {trajectory['issues']}")
        trajectories[str(instance["id"])] = trajectory
        _apply_staff_ik(points, trajectory)

    hands = _hand_tracks(points)
    for instance in normalized["instances"]:
        if instance.get("grip_mode") != "one_handed":
            continue
        attachment = instance["attachments"][0]
        hand = str(attachment["hand"])
        trajectory = build_one_hand_trajectory(normalized, str(instance["id"]), hands[hand])
        if not trajectory["ok"]:
            raise ValueError(f"one-hand trajectory failed for {instance['id']}: {trajectory['issues']}")
        trajectories[str(instance["id"])] = trajectory

    hands = _hand_tracks(points)
    instance_masks = _render_instance_masks(
        normalized,
        trajectories,
        width=width,
        height=height,
        neutral_corridor_frames=neutral_corridor_frames,
        temporal_feather_frames=temporal_feather_frames,
        asset_sizes=asset_sizes or {},
    )
    contact_masks = _render_contact_masks(
        normalized,
        trajectories,
        width=width,
        height=height,
        neutral_corridor_frames=neutral_corridor_frames,
        temporal_feather_frames=temporal_feather_frames,
    )
    union_masks: list[Image.Image] = []
    for index in range(len(points)):
        union = Image.new("L", (width, height), 0)
        for masks in instance_masks.values():
            union = ImageChops.lighter(union, masks[index])
        for by_hand in contact_masks.values():
            for masks in by_hand.values():
                union = ImageChops.lighter(union, masks[index])
        union_masks.append(union)
    qc = contact_qc(normalized, trajectories, hands)
    sidecar = build_mask_sidecar_metadata(
        normalized,
        trajectories,
        width=width,
        height=height,
        fps=fps,
    )
    return {
        "enabled": True,
        "normalized": normalized,
        "pose_points": points,
        "hand_tracks": hands,
        "trajectories": trajectories,
        "instance_masks": instance_masks,
        "contact_masks": contact_masks,
        "union_masks": union_masks,
        "sidecar": sidecar,
        "qc": qc,
    }


__all__ = ["prepare_rigid_pose_guides"]
