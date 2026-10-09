"""Continuity quality control for Animation Studio master assets.

The module deliberately operates on decoded pixels.  It can therefore be
unit-tested with in-memory Pillow images and reused for horizontal sprite
sheets or videos decoded through OpenCV.  Bounding boxes use Pillow's
``(left, top, right, bottom)`` convention: right and bottom are exclusive.
"""

from __future__ import annotations

import json
import math
import statistics
import uuid
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Sequence

from PIL import Image, ImageChops, ImageFilter, ImageStat


QC_SCHEMA_VERSION = "studio.continuity_qc.v1"
_MAD_TO_SIGMA = 1.482602218505602


@dataclass(frozen=True)
class QCThresholds:
    """Thresholds for normalized 0..255 decoded pixel measurements."""

    max_adjacent_mean_abs: float = 24.0
    adjacent_outlier_sigma: float = 6.0
    adjacent_min_outlier_delta: float = 2.0
    adjacent_changed_pixel_delta: int = 8
    max_root_drift_px: float = 2.0
    max_scale_drift_pct: float = 1.0
    max_bbox_edge_drift_px: float = 3.0
    max_foreground_area_drift_pct: float = 45.0
    white_tolerance: int = 12
    alpha_background_max: int = 8
    alpha_foreground_threshold: int = 16
    root_band_ratio: float = 0.05
    require_exact_anchor_endpoints: bool = True
    outliers_are_failures: bool = True
    control_dark_value_max: int = 32
    control_dark_chroma_max: int = 12
    control_mask_threshold: int = 192
    control_mask_erode_px: int = 2
    control_mask_dilate_px: int = 4
    control_mask_min_area_fraction: float = 0.005
    control_mask_min_dark_area_fraction: float = 0.005
    control_mask_dark_fill_limit: float = 0.45
    control_mask_dark_contrast_limit: float = 0.30
    control_mask_dark_iou_limit: float = 0.35
    control_pose_support_saturation_min: int = 120
    control_pose_support_value_min: int = 80
    control_pose_rgb_delta_max: int = 40
    control_pose_anchor_delta_min: int = 32
    control_pose_match_fraction_limit: float = 0.10
    control_pose_min_match_pixels: int = 256
    control_leak_min_consecutive_frames: int = 1

    def __post_init__(self) -> None:
        if self.max_adjacent_mean_abs < 0:
            raise ValueError("max_adjacent_mean_abs must be non-negative")
        if self.adjacent_outlier_sigma < 0 or self.adjacent_min_outlier_delta < 0:
            raise ValueError("adjacent outlier thresholds must be non-negative")
        if not 0 <= self.adjacent_changed_pixel_delta <= 255:
            raise ValueError("adjacent_changed_pixel_delta must be in 0..255")
        if self.max_root_drift_px < 0 or self.max_scale_drift_pct < 0:
            raise ValueError("geometry thresholds must be non-negative")
        if self.max_bbox_edge_drift_px < 0:
            raise ValueError("max_bbox_edge_drift_px must be non-negative")
        if self.max_foreground_area_drift_pct < 0:
            raise ValueError("max_foreground_area_drift_pct must be non-negative")
        for name in ("white_tolerance", "alpha_background_max", "alpha_foreground_threshold"):
            if not 0 <= int(getattr(self, name)) <= 255:
                raise ValueError(f"{name} must be in 0..255")
        if not 0 < self.root_band_ratio <= 1:
            raise ValueError("root_band_ratio must be in (0, 1]")
        for name in (
            "control_dark_value_max",
            "control_dark_chroma_max",
            "control_mask_threshold",
            "control_pose_support_saturation_min",
            "control_pose_support_value_min",
            "control_pose_rgb_delta_max",
            "control_pose_anchor_delta_min",
        ):
            if not 0 <= int(getattr(self, name)) <= 255:
                raise ValueError(f"{name} must be in 0..255")
        for name in ("control_mask_erode_px", "control_mask_dilate_px"):
            if int(getattr(self, name)) < 0:
                raise ValueError(f"{name} must be non-negative")
        for name in (
            "control_mask_min_area_fraction",
            "control_mask_min_dark_area_fraction",
            "control_mask_dark_fill_limit",
            "control_mask_dark_contrast_limit",
            "control_mask_dark_iou_limit",
            "control_pose_match_fraction_limit",
        ):
            if not 0 <= float(getattr(self, name)) <= 1:
                raise ValueError(f"{name} must be in 0..1")
        if self.control_pose_min_match_pixels < 0:
            raise ValueError("control_pose_min_match_pixels must be non-negative")
        if self.control_leak_min_consecutive_frames < 1:
            raise ValueError("control_leak_min_consecutive_frames must be positive")


ImageInput = Image.Image | str | Path


def _round(value: float | int | None, digits: int = 6) -> float | int | None:
    if value is None or isinstance(value, int):
        return value
    return round(float(value), digits)


def _load_rgba(source: ImageInput) -> Image.Image:
    if isinstance(source, Image.Image):
        return source.convert("RGBA").copy()
    with Image.open(Path(source)) as image:
        return image.convert("RGBA").copy()


def _flatten_white(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    background = Image.new("RGBA", rgba.size, (255, 255, 255, 255))
    return Image.alpha_composite(background, rgba).convert("RGB")


def _max_channel_image(image: Image.Image) -> Image.Image:
    channels = list(image.split())
    maximum = channels[0]
    for channel in channels[1:]:
        maximum = ImageChops.lighter(maximum, channel)
    return maximum


def _min_channel_image(image: Image.Image) -> Image.Image:
    channels = list(image.split())
    minimum = channels[0]
    for channel in channels[1:]:
        minimum = ImageChops.darker(minimum, channel)
    return minimum


def _binary_count(mask: Image.Image) -> int:
    return int(mask.convert("L").histogram()[255])


def _near_neutral_dark_mask(image: Image.Image, thresholds: QCThresholds) -> Image.Image:
    rgb = _flatten_white(image)
    maximum = _max_channel_image(rgb)
    minimum = _min_channel_image(rgb)
    value_mask = maximum.point(
        lambda value: 255 if value <= thresholds.control_dark_value_max else 0,
        mode="L",
    )
    chroma = ImageChops.subtract(maximum, minimum)
    neutral_mask = chroma.point(
        lambda value: 255 if value <= thresholds.control_dark_chroma_max else 0,
        mode="L",
    )
    return ImageChops.multiply(value_mask, neutral_mask)


def _normalize_control_frames(
    frames: Sequence[Image.Image] | None,
    *,
    frame_count: int,
    canvas: tuple[int, int],
    name: str,
) -> list[Image.Image] | None:
    if frames is None:
        return None
    if len(frames) != frame_count:
        raise ValueError(f"{name} length must match the analyzed frame count")
    normalized = [frame.copy() for frame in frames]
    if any(frame.size != canvas for frame in normalized):
        raise ValueError(f"every {name} frame must match the analyzed canvas")
    return normalized


def _longest_consecutive_run(indices: Sequence[int]) -> int:
    longest = 0
    current = 0
    previous: int | None = None
    for index in sorted(set(int(value) for value in indices)):
        current = current + 1 if previous is not None and index == previous + 1 else 1
        longest = max(longest, current)
        previous = index
    return longest


def _control_guide_leak_report(
    frames: Sequence[Image.Image],
    *,
    anchor: Image.Image | None,
    pose_frames: Sequence[Image.Image] | None,
    mask_frames: Sequence[Image.Image] | None,
    thresholds: QCThresholds,
) -> dict[str, Any] | None:
    """Find guide-shaped black fills and decoded OpenPose pixels in final frames.

    A global dark-pixel or saturation check is intentionally insufficient: a
    legitimate character can have a black costume and the Lux fixture itself
    uses the same blue/gold hues as parts of the OpenPose palette.  The hard
    signal is therefore correlation with the exact control inputs consumed by
    W8, with the accepted anchor providing a per-pixel appearance baseline.
    """

    if pose_frames is None and mask_frames is None:
        return None
    pixels = frames[0].width * frames[0].height
    anchor_rgb = _flatten_white(anchor) if anchor is not None and anchor.size == frames[0].size else None
    anchor_dark = _near_neutral_dark_mask(anchor, thresholds) if anchor_rgb is not None else None
    frame_reports: list[dict[str, Any]] = []
    suspicious_indices: list[int] = []
    mask_suspicious_indices: list[int] = []
    pose_suspicious_indices: list[int] = []

    for index, frame in enumerate(frames):
        output_rgb = _flatten_white(frame)
        output_dark = _near_neutral_dark_mask(frame, thresholds)
        item: dict[str, Any] = {
            "index": index,
            "internal": 0 < index < len(frames) - 1,
            "mask": {"available": mask_frames is not None},
            "pose": {"available": pose_frames is not None},
        }
        mask_suspicious = False
        pose_suspicious = False

        if mask_frames is not None:
            raw_mask = mask_frames[index].convert("L").point(
                lambda value: 255 if value >= thresholds.control_mask_threshold else 0,
                mode="L",
            )
            if thresholds.control_mask_erode_px:
                size = int(thresholds.control_mask_erode_px) * 2 + 1
                control_mask = raw_mask.filter(ImageFilter.MinFilter(size))
            else:
                control_mask = raw_mask
            mask_pixels = _binary_count(control_mask)
            mask_area_fraction = mask_pixels / pixels if pixels else 0.0
            mask_metrics: dict[str, Any] = {
                "available": True,
                "active": mask_area_fraction >= thresholds.control_mask_min_area_fraction,
                "area_fraction": _round(mask_area_fraction),
            }
            if mask_metrics["active"] and mask_pixels:
                dark_inside_pixels = _binary_count(ImageChops.multiply(output_dark, control_mask))
                dark_fill = dark_inside_pixels / mask_pixels
                if thresholds.control_mask_dilate_px:
                    size = int(thresholds.control_mask_dilate_px) * 2 + 1
                    outside_mask = ImageChops.invert(control_mask.filter(ImageFilter.MaxFilter(size)))
                else:
                    outside_mask = ImageChops.invert(control_mask)
                outside_pixels = _binary_count(outside_mask)
                outside_dark = (
                    _binary_count(ImageChops.multiply(output_dark, outside_mask)) / outside_pixels
                    if outside_pixels
                    else 0.0
                )
                anchor_dark_fill = (
                    _binary_count(ImageChops.multiply(anchor_dark, control_mask)) / mask_pixels
                    if anchor_dark is not None
                    else 0.0
                )
                baseline = max(outside_dark, anchor_dark_fill)
                dark_contrast = dark_fill - baseline
                dark_union = _binary_count(ImageChops.lighter(output_dark, control_mask))
                dark_iou = dark_inside_pixels / dark_union if dark_union else 0.0
                dark_area_fraction = dark_inside_pixels / pixels if pixels else 0.0
                mask_suspicious = bool(
                    dark_area_fraction >= thresholds.control_mask_min_dark_area_fraction
                    and dark_fill >= thresholds.control_mask_dark_fill_limit
                    and dark_contrast >= thresholds.control_mask_dark_contrast_limit
                    and dark_iou >= thresholds.control_mask_dark_iou_limit
                )
                mask_metrics.update(
                    {
                        "dark_fill_fraction": _round(dark_fill),
                        "outside_dark_fraction": _round(outside_dark),
                        "anchor_dark_fill_fraction": _round(anchor_dark_fill),
                        "dark_contrast": _round(dark_contrast),
                        "dark_iou": _round(dark_iou),
                        "dark_area_fraction": _round(dark_area_fraction),
                        "suspicious": mask_suspicious,
                    }
                )
            else:
                mask_metrics["suspicious"] = False
            item["mask"] = mask_metrics

        if pose_frames is not None:
            pose_rgb = pose_frames[index].convert("RGB")
            _, saturation, value = pose_rgb.convert("HSV").split()
            saturation_mask = saturation.point(
                lambda pixel: 255 if pixel >= thresholds.control_pose_support_saturation_min else 0,
                mode="L",
            )
            value_mask = value.point(
                lambda pixel: 255 if pixel >= thresholds.control_pose_support_value_min else 0,
                mode="L",
            )
            pose_support = ImageChops.multiply(saturation_mask, value_mask)
            support_pixels = _binary_count(pose_support)
            guide_difference = _max_channel_image(ImageChops.difference(output_rgb, pose_rgb))
            guide_match = guide_difference.point(
                lambda pixel: 255 if pixel <= thresholds.control_pose_rgb_delta_max else 0,
                mode="L",
            )
            if anchor_rgb is not None:
                anchor_difference = _max_channel_image(ImageChops.difference(output_rgb, anchor_rgb))
                changed_from_anchor = anchor_difference.point(
                    lambda pixel: 255 if pixel >= thresholds.control_pose_anchor_delta_min else 0,
                    mode="L",
                )
            else:
                changed_from_anchor = Image.new("L", frame.size, 255)
            pose_hits = _binary_count(
                ImageChops.multiply(
                    ImageChops.multiply(pose_support, guide_match),
                    changed_from_anchor,
                )
            )
            pose_match_fraction = pose_hits / support_pixels if support_pixels else 0.0
            pose_suspicious = bool(
                pose_hits >= thresholds.control_pose_min_match_pixels
                and pose_match_fraction >= thresholds.control_pose_match_fraction_limit
            )
            item["pose"] = {
                "available": True,
                "support_pixels": support_pixels,
                "matched_pixels": pose_hits,
                "match_fraction": _round(pose_match_fraction),
                "suspicious": pose_suspicious,
            }

        item["suspicious"] = mask_suspicious or pose_suspicious
        if mask_suspicious:
            mask_suspicious_indices.append(index)
        if pose_suspicious:
            pose_suspicious_indices.append(index)
        if item["suspicious"]:
            suspicious_indices.append(index)
        frame_reports.append(item)

    longest_run = _longest_consecutive_run(suspicious_indices)
    failed = longest_run >= thresholds.control_leak_min_consecutive_frames
    return {
        "available": True,
        "pose_guide_available": pose_frames is not None,
        "mask_guide_available": mask_frames is not None,
        "frames": frame_reports,
        "summary": {
            "suspicious_frame_indices": suspicious_indices,
            "mask_suspicious_frame_indices": mask_suspicious_indices,
            "pose_suspicious_frame_indices": pose_suspicious_indices,
            "longest_consecutive_run": longest_run,
            "minimum_consecutive_frames": thresholds.control_leak_min_consecutive_frames,
            "failed": failed,
        },
    }


def _difference_metrics(
    left: Image.Image,
    right: Image.Image,
    *,
    include_alpha: bool,
    changed_pixel_delta: int,
) -> dict[str, Any]:
    if left.size != right.size:
        return {
            "size_match": False,
            "exact": False,
            "left_size": list(left.size),
            "right_size": list(right.size),
            "mean_abs": None,
            "max_channel_delta": None,
            "changed_pixels": None,
            "changed_fraction": None,
        }

    if include_alpha:
        lhs = left.convert("RGBA")
        rhs = right.convert("RGBA")
    else:
        lhs = _flatten_white(left)
        rhs = _flatten_white(right)
    difference = ImageChops.difference(lhs, rhs)
    means = ImageStat.Stat(difference).mean
    maximum = _max_channel_image(difference)
    exact_mask = maximum.point(lambda value: 255 if value else 0, mode="L")
    changed_mask = maximum.point(
        lambda value: 255 if value >= changed_pixel_delta and value else 0,
        mode="L",
    )
    exact_changed = exact_mask.histogram()[255]
    threshold_changed = changed_mask.histogram()[255]
    pixels = lhs.width * lhs.height
    extrema = difference.getextrema()
    return {
        "size_match": True,
        "exact": exact_changed == 0,
        "left_size": list(lhs.size),
        "right_size": list(rhs.size),
        "mean_abs": _round(sum(means) / len(means)),
        "max_channel_delta": max(item[1] for item in extrema),
        "changed_pixels": threshold_changed,
        "changed_fraction": _round(threshold_changed / pixels if pixels else 0.0),
        "exact_changed_pixels": exact_changed,
    }


def _foreground_mask(image: Image.Image, thresholds: QCThresholds) -> tuple[Image.Image, str]:
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A")
    minimum_alpha, _ = alpha.getextrema()
    if minimum_alpha <= thresholds.alpha_background_max:
        mask = alpha.point(
            lambda value: 255 if value > thresholds.alpha_foreground_threshold else 0,
            mode="L",
        )
        return mask, "alpha"

    red, green, blue = rgba.convert("RGB").split()
    distance = ImageChops.lighter(
        ImageChops.lighter(ImageChops.invert(red), ImageChops.invert(green)),
        ImageChops.invert(blue),
    )
    mask = distance.point(
        lambda value: 255 if value > thresholds.white_tolerance else 0,
        mode="L",
    )
    return mask, "white_background"


def _foreground_geometry(image: Image.Image, thresholds: QCThresholds) -> dict[str, Any]:
    mask, mask_source = _foreground_mask(image, thresholds)
    bbox = mask.getbbox()
    if bbox is None:
        return {
            "present": False,
            "mask_source": mask_source,
            "bbox": None,
            "root": None,
            "bbox_width": 0,
            "bbox_height": 0,
            "foreground_area": 0,
        }

    left, top, right, bottom = bbox
    bbox_width = right - left
    bbox_height = bottom - top
    band_height = max(2, int(round(bbox_height * thresholds.root_band_ratio)))
    band_top = max(top, bottom - band_height)
    pixels = mask.load()
    total_weight = 0.0
    weighted_x = 0.0
    for y in range(band_top, bottom):
        for x in range(left, right):
            weight = pixels[x, y] / 255.0
            total_weight += weight
            weighted_x += (x + 0.5) * weight
    root_x = weighted_x / total_weight if total_weight else (left + right) / 2.0
    root_y = float(bottom - 1)
    area = mask.histogram()[255]
    return {
        "present": True,
        "mask_source": mask_source,
        "bbox": [left, top, right, bottom],
        "root": {"x": _round(root_x), "y": _round(root_y)},
        "bbox_width": bbox_width,
        "bbox_height": bbox_height,
        "foreground_area": area,
    }


def _geometry_with_drift(
    geometry: dict[str, Any],
    reference: dict[str, Any] | None,
    *,
    index: int,
) -> dict[str, Any]:
    result = dict(geometry)
    result["index"] = index
    result["drift"] = None
    if not geometry.get("present") or not reference or not reference.get("present"):
        return result

    bbox = geometry["bbox"]
    reference_bbox = reference["bbox"]
    root = geometry["root"]
    reference_root = reference["root"]
    root_dx = float(root["x"]) - float(reference_root["x"])
    root_dy = float(root["y"]) - float(reference_root["y"])
    bbox_center_x = (bbox[0] + bbox[2]) / 2.0
    bbox_center_y = (bbox[1] + bbox[3]) / 2.0
    reference_center_x = (reference_bbox[0] + reference_bbox[2]) / 2.0
    reference_center_y = (reference_bbox[1] + reference_bbox[3]) / 2.0
    reference_height = max(1, int(reference["bbox_height"]))
    reference_area = max(1, int(reference["foreground_area"]))
    result["drift"] = {
        "root_dx_px": _round(root_dx),
        "root_dy_px": _round(root_dy),
        "root_distance_px": _round(math.hypot(root_dx, root_dy)),
        "bbox_edge_max_px": max(abs(int(a) - int(b)) for a, b in zip(bbox, reference_bbox)),
        "bbox_center_distance_px": _round(
            math.hypot(bbox_center_x - reference_center_x, bbox_center_y - reference_center_y)
        ),
        "scale_drift_pct": _round(abs(int(geometry["bbox_height"]) - reference_height) * 100.0 / reference_height),
        "area_drift_pct": _round(abs(int(geometry["foreground_area"]) - reference_area) * 100.0 / reference_area),
    }
    return result


def _maximum(values: Sequence[float | int | None]) -> float | int | None:
    available = [value for value in values if value is not None]
    return max(available) if available else None


def _check(
    check_id: str,
    passed: bool,
    message: str,
    *,
    details: dict[str, Any] | None = None,
    failure_status: str = "fail",
) -> dict[str, Any]:
    return {
        "id": check_id,
        "status": "pass" if passed else failure_status,
        "message": message,
        "details": details or {},
    }


def _pair_region(index: int, next_index: int, frame_count: int, boundary_width: int) -> str:
    if next_index == 0:
        return "wrap"
    if index < boundary_width or index >= frame_count - boundary_width - 1:
        return "boundary"
    return "internal"


def _pair_statistics(pairs: Sequence[dict[str, Any]]) -> dict[str, Any]:
    if not pairs:
        return {
            "count": 0,
            "median": None,
            "mad": None,
            "maximum_mean_abs": None,
            "maximum_pair_index": None,
            "pair_indices": [],
        }
    values = [float(pair["mean_abs"]) for pair in pairs]
    median = float(statistics.median(values))
    mad = float(statistics.median(abs(value - median) for value in values))
    maximum = max(pairs, key=lambda item: float(item["mean_abs"]))
    return {
        "count": len(pairs),
        "median": _round(median),
        "mad": _round(mad),
        "maximum_mean_abs": _round(float(maximum["mean_abs"])),
        "maximum_pair_index": maximum["index"],
        "pair_indices": [pair["index"] for pair in pairs],
    }


def _registered_difference_metrics(
    left: Image.Image,
    right: Image.Image,
    left_geometry: dict[str, Any],
    right_geometry: dict[str, Any],
    *,
    changed_pixel_delta: int,
) -> dict[str, Any]:
    """Measure appearance change after removing integer foreground-root drift."""

    if not left_geometry.get("present") or not right_geometry.get("present"):
        return {"available": False, "reason": "foreground_missing"}
    left_root = left_geometry["root"]
    right_root = right_geometry["root"]
    dx = int(round(float(left_root["x"]) - float(right_root["x"])))
    dy = int(round(float(left_root["y"]) - float(right_root["y"])))
    flattened = _flatten_white(right)
    aligned = Image.new("RGB", flattened.size, "white")
    aligned.paste(flattened, (dx, dy))
    metrics = _difference_metrics(
        _flatten_white(left),
        aligned,
        include_alpha=False,
        changed_pixel_delta=changed_pixel_delta,
    )
    return {
        "available": True,
        "translation_px": {"x": dx, "y": dy},
        **metrics,
    }


def _dense_flow_metrics(left: Image.Image, right: Image.Image, *, max_side: int = 192) -> dict[str, Any]:
    """Return lightweight Farneback motion and forward/back consistency signals."""

    try:
        import cv2  # type: ignore
        import numpy as np  # type: ignore
    except ImportError:  # pragma: no cover - optional dependency
        return {"available": False, "reason": "opencv_unavailable"}

    try:
        lhs = np.asarray(_flatten_white(left).convert("L"), dtype=np.uint8)
        rhs = np.asarray(_flatten_white(right).convert("L"), dtype=np.uint8)
        height, width = lhs.shape
        if min(width, height) < 8:
            return {"available": False, "reason": "canvas_too_small"}
        scale = min(1.0, max_side / max(width, height))
        if scale < 1:
            target = (max(8, round(width * scale)), max(8, round(height * scale)))
            lhs = cv2.resize(lhs, target, interpolation=cv2.INTER_AREA)
            rhs = cv2.resize(rhs, target, interpolation=cv2.INTER_AREA)
        forward = cv2.calcOpticalFlowFarneback(lhs, rhs, None, 0.5, 3, 15, 3, 5, 1.2, 0)
        backward = cv2.calcOpticalFlowFarneback(rhs, lhs, None, 0.5, 3, 15, 3, 5, 1.2, 0)
        grid_y, grid_x = np.mgrid[0 : lhs.shape[0], 0 : lhs.shape[1]].astype(np.float32)
        map_x = grid_x + forward[..., 0]
        map_y = grid_y + forward[..., 1]
        sampled_backward = cv2.remap(
            backward,
            map_x,
            map_y,
            interpolation=cv2.INTER_LINEAR,
            borderMode=cv2.BORDER_CONSTANT,
            borderValue=0,
        )
        magnitude = np.linalg.norm(forward, axis=2) / scale
        consistency = np.linalg.norm(forward + sampled_backward, axis=2) / scale
        return {
            "available": True,
            "analysis_scale": _round(scale),
            "motion_mean_px": _round(float(np.mean(magnitude))),
            "motion_p95_px": _round(float(np.percentile(magnitude, 95))),
            "forward_backward_error_mean_px": _round(float(np.mean(consistency))),
            "forward_backward_error_p95_px": _round(float(np.percentile(consistency, 95))),
        }
    except Exception:  # pragma: no cover - backend/version dependent fallback
        return {"available": False, "reason": "flow_analysis_failed"}


def _normalize_pose_frame(frame: Any) -> dict[int, tuple[float, float, float]]:
    if isinstance(frame, dict):
        items = frame.items()
    elif isinstance(frame, Sequence):
        items = enumerate(frame)
    else:
        raise ValueError("pose frames must be mappings or sequences")
    normalized: dict[int, tuple[float, float, float]] = {}
    for raw_index, value in items:
        if value is None:
            continue
        if not isinstance(value, Sequence) or len(value) < 2:
            raise ValueError("pose keypoints must contain x and y")
        index = int(raw_index)
        x, y = float(value[0]), float(value[1])
        confidence = float(value[2]) if len(value) > 2 else 1.0
        if not all(math.isfinite(item) for item in (x, y, confidence)):
            raise ValueError("pose keypoints must be finite")
        if confidence > 0:
            normalized[index] = (x, y, confidence)
    return normalized


def _normalize_pose_sequence(sequence: Sequence[Any] | None, frame_count: int) -> list[dict[int, tuple[float, float, float]]] | None:
    if sequence is None:
        return None
    if len(sequence) != frame_count:
        raise ValueError("pose sequence length must match the analyzed frame count")
    return [_normalize_pose_frame(frame) for frame in sequence]


def _pose_pair_metrics(
    expected_left: dict[int, tuple[float, float, float]] | None,
    expected_right: dict[int, tuple[float, float, float]] | None,
    observed_left: dict[int, tuple[float, float, float]] | None,
    observed_right: dict[int, tuple[float, float, float]] | None,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "expected_available": expected_left is not None and expected_right is not None,
        "observed_available": observed_left is not None and observed_right is not None,
    }

    def displacements(
        left: dict[int, tuple[float, float, float]],
        right: dict[int, tuple[float, float, float]],
    ) -> dict[int, tuple[float, float]]:
        return {
            index: (right[index][0] - left[index][0], right[index][1] - left[index][1])
            for index in left.keys() & right.keys()
        }

    expected_vectors = displacements(expected_left, expected_right) if result["expected_available"] else {}
    observed_vectors = displacements(observed_left, observed_right) if result["observed_available"] else {}
    if expected_vectors:
        magnitudes = [math.hypot(*vector) for vector in expected_vectors.values()]
        result.update(
            {
                "expected_joint_count": len(expected_vectors),
                "expected_max_velocity_px": _round(max(magnitudes)),
                "expected_rms_velocity_px": _round(math.sqrt(sum(value * value for value in magnitudes) / len(magnitudes))),
            }
        )
    if observed_vectors:
        magnitudes = [math.hypot(*vector) for vector in observed_vectors.values()]
        result.update(
            {
                "observed_joint_count": len(observed_vectors),
                "observed_max_velocity_px": _round(max(magnitudes)),
                "observed_rms_velocity_px": _round(math.sqrt(sum(value * value for value in magnitudes) / len(magnitudes))),
            }
        )
    common = expected_vectors.keys() & observed_vectors.keys()
    if common:
        errors = [
            math.hypot(
                observed_vectors[index][0] - expected_vectors[index][0],
                observed_vectors[index][1] - expected_vectors[index][1],
            )
            for index in common
        ]
        result.update(
            {
                "velocity_error_joint_count": len(errors),
                "velocity_error_max_px": _round(max(errors)),
                "velocity_error_rms_px": _round(math.sqrt(sum(value * value for value in errors) / len(errors))),
            }
        )
    return result


def analyze_frames(
    frames: Sequence[Image.Image],
    *,
    anchor: ImageInput | None,
    thresholds: QCThresholds | None = None,
    source: dict[str, Any] | str | None = None,
    geometry_gate_indices: Sequence[int] | None = None,
    boundary_width: int = 4,
    expected_keypoints: Sequence[Any] | None = None,
    observed_keypoints: Sequence[Any] | None = None,
    control_pose_frames: Sequence[Image.Image] | None = None,
    control_mask_frames: Sequence[Image.Image] | None = None,
    flow_analysis: bool = True,
) -> dict[str, Any]:
    """Analyze decoded master frames and return a JSON-compatible report.

    Every adjacent pair is measured, including the final ``last -> first``
    wrap pair.  Exact endpoint checks compare RGBA pixels without resizing or
    tolerance.  Visual adjacent differences are measured after compositing
    alpha over white. Geometry is measured for every frame, but only the
    transition-boundary frames are hard-gated by default: a wave, jump or run
    may legitimately change the action silhouette between those boundaries.
    """

    settings = thresholds or QCThresholds()
    if len(frames) < 2:
        raise ValueError("continuity QC requires at least two frames")
    if not isinstance(boundary_width, int) or isinstance(boundary_width, bool) or boundary_width < 1:
        raise ValueError("boundary_width must be a positive integer")
    rgba_frames = [frame.convert("RGBA").copy() for frame in frames]
    canvas = rgba_frames[0].size
    if any(frame.size != canvas for frame in rgba_frames[1:]):
        raise ValueError("all master frames must have the same dimensions")
    normalized_control_pose = _normalize_control_frames(
        control_pose_frames,
        frame_count=len(rgba_frames),
        canvas=canvas,
        name="control_pose_frames",
    )
    normalized_control_mask = _normalize_control_frames(
        control_mask_frames,
        frame_count=len(rgba_frames),
        canvas=canvas,
        name="control_mask_frames",
    )
    effective_boundary_width = min(boundary_width, max(1, (len(rgba_frames) - 1) // 2))
    normalized_expected = _normalize_pose_sequence(expected_keypoints, len(rgba_frames))
    normalized_observed = _normalize_pose_sequence(observed_keypoints, len(rgba_frames))

    source_info: dict[str, Any] = {"kind": "frames"}
    if isinstance(source, dict):
        source_info.update(source)
    elif source:
        source_info["path"] = str(source)

    anchor_image = _load_rgba(anchor) if anchor is not None else None
    control_guides = _control_guide_leak_report(
        rgba_frames,
        anchor=anchor_image,
        pose_frames=normalized_control_pose,
        mask_frames=normalized_control_mask,
        thresholds=settings,
    )
    endpoint_report: dict[str, Any] = {"provided": anchor_image is not None}
    if anchor_image is not None:
        endpoint_report.update(
            {
                "first_to_anchor": _difference_metrics(
                    rgba_frames[0],
                    anchor_image,
                    include_alpha=True,
                    changed_pixel_delta=1,
                ),
                "last_to_anchor": _difference_metrics(
                    rgba_frames[-1],
                    anchor_image,
                    include_alpha=True,
                    changed_pixel_delta=1,
                ),
            }
        )
    endpoint_report["first_to_last"] = _difference_metrics(
        rgba_frames[0],
        rgba_frames[-1],
        include_alpha=True,
        changed_pixel_delta=1,
    )

    adjacent_pairs: list[dict[str, Any]] = []
    for index, frame in enumerate(rgba_frames):
        next_index = (index + 1) % len(rgba_frames)
        metrics = _difference_metrics(
            frame,
            rgba_frames[next_index],
            include_alpha=False,
            changed_pixel_delta=settings.adjacent_changed_pixel_delta,
        )
        adjacent_pairs.append(
            {
                "index": index,
                "from": index,
                "to": next_index,
                "wrap": next_index == 0,
                "region": _pair_region(index, next_index, len(rgba_frames), effective_boundary_width),
                **metrics,
            }
        )

    scores = [float(pair["mean_abs"]) for pair in adjacent_pairs]
    score_median = float(statistics.median(scores))
    score_mad = float(statistics.median(abs(score - score_median) for score in scores))
    scaled_mad = score_mad * _MAD_TO_SIGMA
    outlier_cutoff = max(
        score_median + settings.adjacent_outlier_sigma * scaled_mad,
        score_median + settings.adjacent_min_outlier_delta,
    )
    outlier_indices: list[int] = []
    for pair, score in zip(adjacent_pairs, scores):
        pair["robust_z"] = _round((score - score_median) / scaled_mad) if scaled_mad > 1e-12 else None
        pair["high_outlier"] = score > outlier_cutoff
        if pair["high_outlier"]:
            outlier_indices.append(int(pair["index"]))
    max_pair = max(adjacent_pairs, key=lambda item: float(item["mean_abs"]))

    anchor_geometry = _foreground_geometry(anchor_image, settings) if anchor_image is not None else None
    anchor_geometry_usable = bool(
        anchor_geometry
        and anchor_geometry.get("present")
        and anchor_image is not None
        and anchor_image.size == canvas
    )
    raw_frame_geometry = [_foreground_geometry(frame, settings) for frame in rgba_frames]
    reference_geometry = anchor_geometry if anchor_geometry_usable else next(
        (item for item in raw_frame_geometry if item.get("present")),
        None,
    )
    reference_source = "anchor" if anchor_geometry_usable else "first_present_frame_fallback"
    frame_geometry = [
        _geometry_with_drift(item, reference_geometry, index=index)
        for index, item in enumerate(raw_frame_geometry)
    ]
    for pair in adjacent_pairs:
        left_index = int(pair["from"])
        right_index = int(pair["to"])
        pair["registered"] = _registered_difference_metrics(
            rgba_frames[left_index],
            rgba_frames[right_index],
            raw_frame_geometry[left_index],
            raw_frame_geometry[right_index],
            changed_pixel_delta=settings.adjacent_changed_pixel_delta,
        )
        pair["flow"] = (
            _dense_flow_metrics(rgba_frames[left_index], rgba_frames[right_index])
            if flow_analysis
            else {"available": False, "reason": "disabled"}
        )
        pair["pose"] = _pose_pair_metrics(
            normalized_expected[left_index] if normalized_expected is not None else None,
            normalized_expected[right_index] if normalized_expected is not None else None,
            normalized_observed[left_index] if normalized_observed is not None else None,
            normalized_observed[right_index] if normalized_observed is not None else None,
        )
        expected_velocity = pair["pose"].get("expected_max_velocity_px")
        registered_mean = pair["registered"].get("mean_abs")
        pair["motion_normalized_residual"] = (
            _round(float(registered_mean) / (1.0 + float(expected_velocity)))
            if registered_mean is not None and expected_velocity is not None
            else None
        )

    boundary_pairs = [pair for pair in adjacent_pairs if pair["region"] in {"boundary", "wrap"}]
    internal_pairs = [pair for pair in adjacent_pairs if pair["region"] == "internal"]
    wrap_pair = next(pair for pair in adjacent_pairs if pair["region"] == "wrap")
    boundary_statistics = _pair_statistics(boundary_pairs)
    internal_statistics = _pair_statistics(internal_pairs)
    if geometry_gate_indices is None:
        gate_indices = list(dict.fromkeys((0, len(rgba_frames) - 1)))
    else:
        gate_indices = []
        for value in geometry_gate_indices:
            if not isinstance(value, int) or isinstance(value, bool):
                raise ValueError("geometry_gate_indices must contain integer frame indices")
            if value < 0 or value >= len(rgba_frames):
                raise ValueError("geometry_gate_indices contains an out-of-range frame index")
            if value not in gate_indices:
                gate_indices.append(value)
        if not gate_indices:
            raise ValueError("geometry_gate_indices must not be empty")
    gated_geometry = [frame_geometry[index] for index in gate_indices]
    missing_foreground = [item["index"] for item in frame_geometry if not item.get("present")]
    root_all_max = _maximum(
        item.get("drift", {}).get("root_distance_px") if item.get("drift") else None
        for item in frame_geometry
    )
    scale_all_max = _maximum(
        item.get("drift", {}).get("scale_drift_pct") if item.get("drift") else None
        for item in frame_geometry
    )
    bbox_edge_all_max = _maximum(
        item.get("drift", {}).get("bbox_edge_max_px") if item.get("drift") else None
        for item in frame_geometry
    )
    area_drift_all_max = _maximum(
        item.get("drift", {}).get("area_drift_pct") if item.get("drift") else None
        for item in frame_geometry
    )
    root_gate_max = _maximum(
        item.get("drift", {}).get("root_distance_px") if item.get("drift") else None
        for item in gated_geometry
    )
    scale_gate_max = _maximum(
        item.get("drift", {}).get("scale_drift_pct") if item.get("drift") else None
        for item in gated_geometry
    )
    bbox_edge_gate_max = _maximum(
        item.get("drift", {}).get("bbox_edge_max_px") if item.get("drift") else None
        for item in gated_geometry
    )

    checks: list[dict[str, Any]] = []
    if anchor_image is None:
        checks.append(
            _check(
                "anchor_endpoints_exact",
                not settings.require_exact_anchor_endpoints,
                "Canonical anchor was not provided.",
                failure_status="fail" if settings.require_exact_anchor_endpoints else "warning",
            )
        )
    else:
        first_exact = bool(endpoint_report["first_to_anchor"]["exact"])
        last_exact = bool(endpoint_report["last_to_anchor"]["exact"])
        checks.append(
            _check(
                "anchor_endpoints_exact",
                first_exact and last_exact,
                "First and last master frames must exactly equal the canonical anchor.",
                details={"first_exact": first_exact, "last_exact": last_exact},
                failure_status="fail" if settings.require_exact_anchor_endpoints else "warning",
            )
        )

    maximum_adjacent = float(max_pair["mean_abs"])
    checks.append(
        _check(
            "adjacent_absolute_limit",
            maximum_adjacent <= settings.max_adjacent_mean_abs,
            "Every adjacent pair, including wrap, must remain below the absolute visual-difference limit.",
            details={
                "maximum_mean_abs": _round(maximum_adjacent),
                "maximum_pair": {"from": max_pair["from"], "to": max_pair["to"], "wrap": max_pair["wrap"]},
                "limit": settings.max_adjacent_mean_abs,
            },
        )
    )
    checks.append(
        _check(
            "adjacent_robust_outliers",
            not outlier_indices,
            "No adjacent transition may be a high median/MAD outlier.",
            details={"pair_indices": outlier_indices, "cutoff": _round(outlier_cutoff)},
            failure_status="fail" if settings.outliers_are_failures else "warning",
        )
    )
    boundary_maximum = boundary_statistics["maximum_mean_abs"]
    internal_maximum = internal_statistics["maximum_mean_abs"]
    checks.append(
        _check(
            "boundary_adjacent_absolute_limit",
            boundary_maximum is None or float(boundary_maximum) <= settings.max_adjacent_mean_abs,
            "Boundary-band and wrap transitions must remain below the visual-difference limit.",
            details={
                "boundary_width": effective_boundary_width,
                "maximum_mean_abs": boundary_maximum,
                "limit": settings.max_adjacent_mean_abs,
            },
        )
    )
    checks.append(
        _check(
            "internal_adjacent_absolute_limit",
            internal_maximum is None or float(internal_maximum) <= settings.max_adjacent_mean_abs,
            "Internal action transitions must remain below the visual-difference limit.",
            details={
                "maximum_mean_abs": internal_maximum,
                "limit": settings.max_adjacent_mean_abs,
            },
        )
    )
    reference_present = bool(reference_geometry and reference_geometry.get("present"))
    anchor_foreground_ok = anchor_image is None or bool(anchor_geometry and anchor_geometry.get("present"))
    checks.append(
        _check(
            "foreground_present",
            reference_present and anchor_foreground_ok and not missing_foreground,
            "Anchor and every master frame must contain a detectable foreground silhouette.",
            details={"missing_frame_indices": missing_foreground, "anchor_present": anchor_foreground_ok},
        )
    )
    checks.append(
        _check(
            "root_drift",
            root_gate_max is not None and float(root_gate_max) <= settings.max_root_drift_px,
            "Foreground root must match the canonical anchor at transition boundaries.",
            details={
                "gate_indices": gate_indices,
                "maximum_px": _round(root_gate_max),
                "all_frames_maximum_px": _round(root_all_max),
                "limit_px": settings.max_root_drift_px,
            },
        )
    )
    checks.append(
        _check(
            "scale_drift",
            scale_gate_max is not None and float(scale_gate_max) <= settings.max_scale_drift_pct,
            "Foreground bbox height must match canonical scale at transition boundaries.",
            details={
                "gate_indices": gate_indices,
                "maximum_pct": _round(scale_gate_max),
                "all_frames_maximum_pct": _round(scale_all_max),
                "limit_pct": settings.max_scale_drift_pct,
            },
        )
    )
    checks.append(
        _check(
            "bbox_edge_drift",
            bbox_edge_gate_max is not None and float(bbox_edge_gate_max) <= settings.max_bbox_edge_drift_px,
            "Neutral bbox edges must match the anchor at transition boundaries.",
            details={
                "gate_indices": gate_indices,
                "maximum_px": _round(bbox_edge_gate_max),
                "all_frames_maximum_px": _round(bbox_edge_all_max),
                "limit_px": settings.max_bbox_edge_drift_px,
            },
        )
    )
    checks.append(
        _check(
            "foreground_area_drift",
            area_drift_all_max is not None
            and float(area_drift_all_max) <= settings.max_foreground_area_drift_pct,
            "No internal frame may replace the character with a substantially larger or smaller silhouette.",
            details={
                "all_frames_maximum_pct": _round(area_drift_all_max),
                "limit_pct": settings.max_foreground_area_drift_pct,
            },
        )
    )
    if control_guides is not None:
        control_summary = control_guides["summary"]
        checks.append(
            _check(
                "control_guide_leak",
                not bool(control_summary["failed"]),
                "Final frames must not contain the supplied control mask or OpenPose guide pixels.",
                details={
                    **control_summary,
                    "mask_limits": {
                        "minimum_area_fraction": settings.control_mask_min_area_fraction,
                        "minimum_dark_area_fraction": settings.control_mask_min_dark_area_fraction,
                        "dark_fill": settings.control_mask_dark_fill_limit,
                        "dark_contrast": settings.control_mask_dark_contrast_limit,
                        "dark_iou": settings.control_mask_dark_iou_limit,
                    },
                    "pose_limits": {
                        "minimum_matched_pixels": settings.control_pose_min_match_pixels,
                        "match_fraction": settings.control_pose_match_fraction_limit,
                    },
                },
            )
        )

    if any(item["status"] == "fail" for item in checks):
        status = "fail"
    elif any(item["status"] == "warning" for item in checks):
        status = "review"
    else:
        status = "pass"

    report = {
        "schema_version": QC_SCHEMA_VERSION,
        "status": status,
        "passed": status == "pass",
        "source": source_info,
        "frame_count": len(rgba_frames),
        "canvas": {"width": canvas[0], "height": canvas[1]},
        "thresholds": asdict(settings),
        "anchor_endpoints": endpoint_report,
        "control_guides": control_guides,
        "adjacent": {
            "includes_wrap": True,
            "pairs": adjacent_pairs,
            "statistics": {
                "median": _round(score_median),
                "mad": _round(score_mad),
                "scaled_mad": _round(scaled_mad),
                "high_outlier_cutoff": _round(outlier_cutoff),
                "high_outlier_pair_indices": outlier_indices,
                "maximum_pair_index": max_pair["index"],
            },
        },
        "continuity_regions": {
            "boundary_width": effective_boundary_width,
            "boundary": boundary_statistics,
            "internal": internal_statistics,
            "wrap": {
                "pair_index": wrap_pair["index"],
                "mean_abs": wrap_pair["mean_abs"],
                "registered_mean_abs": wrap_pair["registered"].get("mean_abs"),
            },
        },
        "motion_signals": {
            "flow_analysis_enabled": flow_analysis,
            "flow_available_pair_indices": [
                pair["index"] for pair in adjacent_pairs if pair["flow"].get("available")
            ],
            "expected_pose_available": normalized_expected is not None,
            "observed_pose_available": normalized_observed is not None,
            "pose_pair_indices": [
                pair["index"]
                for pair in adjacent_pairs
                if pair["pose"].get("expected_available") or pair["pose"].get("observed_available")
            ],
        },
        "geometry": {
            "reference_source": reference_source,
            "gate_indices": gate_indices,
            "anchor": anchor_geometry,
            "frames": frame_geometry,
            "summary": {
                "missing_frame_indices": missing_foreground,
                "max_root_drift_px": _round(root_all_max),
                "max_scale_drift_pct": _round(scale_all_max),
                "max_bbox_edge_drift_px": _round(bbox_edge_all_max),
                "max_foreground_area_drift_pct": _round(area_drift_all_max),
                "gate_max_root_drift_px": _round(root_gate_max),
                "gate_max_scale_drift_pct": _round(scale_gate_max),
                "gate_max_bbox_edge_drift_px": _round(bbox_edge_gate_max),
            },
        },
        "checks": checks,
        "issues": [item for item in checks if item["status"] != "pass"],
    }
    # Enforce the public promise that the report can be persisted as strict JSON.
    json.dumps(report, ensure_ascii=False, allow_nan=False)
    return report


def split_spritesheet(
    source: ImageInput,
    *,
    frame_width: int | None = None,
    frame_count: int | None = None,
    axis: str = "horizontal",
) -> list[Image.Image]:
    """Split a single-row or single-column sprite sheet into RGBA frames."""

    sheet = _load_rgba(source)
    if axis not in {"horizontal", "vertical"}:
        raise ValueError("axis must be 'horizontal' or 'vertical'")
    total = sheet.width if axis == "horizontal" else sheet.height
    cross = sheet.height if axis == "horizontal" else sheet.width
    if frame_width is None:
        if frame_count is not None:
            if frame_count < 2 or total % frame_count:
                raise ValueError("sprite sheet size is not divisible by frame_count")
            frame_width = total // frame_count
        else:
            frame_width = cross
    if frame_width <= 0 or total % frame_width:
        raise ValueError("sprite sheet size is not divisible by frame_width")
    inferred_count = total // frame_width
    if frame_count is not None and frame_count != inferred_count:
        raise ValueError("frame_count and frame_width do not cover the complete sprite sheet")
    if inferred_count < 2:
        raise ValueError("continuity QC requires at least two sprite frames")

    frames: list[Image.Image] = []
    for index in range(inferred_count):
        if axis == "horizontal":
            box = (index * frame_width, 0, (index + 1) * frame_width, sheet.height)
        else:
            box = (0, index * frame_width, sheet.width, (index + 1) * frame_width)
        frames.append(sheet.crop(box))
    return frames


def analyze_spritesheet(
    path: str | Path,
    *,
    anchor: ImageInput | None,
    frame_width: int | None = None,
    frame_count: int | None = None,
    axis: str = "horizontal",
    thresholds: QCThresholds | None = None,
    geometry_gate_indices: Sequence[int] | None = None,
    boundary_width: int = 4,
    expected_keypoints: Sequence[Any] | None = None,
    observed_keypoints: Sequence[Any] | None = None,
    control_pose_frames: Sequence[Image.Image] | None = None,
    control_mask_frames: Sequence[Image.Image] | None = None,
    flow_analysis: bool = True,
) -> dict[str, Any]:
    frames = split_spritesheet(
        path,
        frame_width=frame_width,
        frame_count=frame_count,
        axis=axis,
    )
    return analyze_frames(
        frames,
        anchor=anchor,
        thresholds=thresholds,
        source={"kind": "spritesheet", "path": str(Path(path)), "axis": axis},
        geometry_gate_indices=geometry_gate_indices,
        boundary_width=boundary_width,
        expected_keypoints=expected_keypoints,
        observed_keypoints=observed_keypoints,
        control_pose_frames=control_pose_frames,
        control_mask_frames=control_mask_frames,
        flow_analysis=flow_analysis,
    )


def load_video_frames(path: str | Path) -> tuple[list[Image.Image], dict[str, Any]]:
    """Decode a video with OpenCV, imported lazily so Pillow-only users work."""

    try:
        import cv2  # type: ignore
    except ImportError as exc:  # pragma: no cover - depends on optional environment
        raise RuntimeError("OpenCV is required to analyze video files") from exc

    video_path = Path(path)
    capture = cv2.VideoCapture(str(video_path))
    if not capture.isOpened():
        capture.release()
        raise RuntimeError(f"could not open video: {video_path}")
    fps = float(capture.get(cv2.CAP_PROP_FPS) or 0.0)
    frames: list[Image.Image] = []
    try:
        while True:
            ok, decoded = capture.read()
            if not ok:
                break
            if decoded.ndim == 2:
                converted = cv2.cvtColor(decoded, cv2.COLOR_GRAY2RGBA)
            elif decoded.shape[2] == 4:
                converted = cv2.cvtColor(decoded, cv2.COLOR_BGRA2RGBA)
            else:
                converted = cv2.cvtColor(decoded, cv2.COLOR_BGR2RGBA)
            frames.append(Image.fromarray(converted, mode="RGBA"))
    finally:
        capture.release()
    if len(frames) < 2:
        raise RuntimeError(f"video contains fewer than two decoded frames: {video_path}")
    return frames, {"fps": _round(fps), "decoded_frames": len(frames)}


def analyze_video(
    path: str | Path,
    *,
    anchor: ImageInput | None,
    thresholds: QCThresholds | None = None,
    geometry_gate_indices: Sequence[int] | None = None,
    boundary_width: int = 4,
    expected_keypoints: Sequence[Any] | None = None,
    observed_keypoints: Sequence[Any] | None = None,
    control_pose_frames: Sequence[Image.Image] | None = None,
    control_mask_frames: Sequence[Image.Image] | None = None,
    flow_analysis: bool = True,
) -> dict[str, Any]:
    frames, metadata = load_video_frames(path)
    return analyze_frames(
        frames,
        anchor=anchor,
        thresholds=thresholds,
        source={"kind": "video", "path": str(Path(path)), **metadata},
        geometry_gate_indices=geometry_gate_indices,
        boundary_width=boundary_width,
        expected_keypoints=expected_keypoints,
        observed_keypoints=observed_keypoints,
        control_pose_frames=control_pose_frames,
        control_mask_frames=control_mask_frames,
        flow_analysis=flow_analysis,
    )


def report_to_json(report: dict[str, Any], *, indent: int = 2) -> str:
    return json.dumps(report, ensure_ascii=False, indent=indent, allow_nan=False) + "\n"


def write_qc_report(report: dict[str, Any], path: str | Path) -> Path:
    """Atomically persist a QC report and return its resolved destination."""

    destination = Path(path).resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(f".{destination.name}.{uuid.uuid4().hex}.tmp")
    temporary.write_text(report_to_json(report), encoding="utf-8")
    temporary.replace(destination)
    return destination


__all__ = [
    "QC_SCHEMA_VERSION",
    "QCThresholds",
    "analyze_frames",
    "analyze_spritesheet",
    "analyze_video",
    "load_video_frames",
    "report_to_json",
    "split_spritesheet",
    "write_qc_report",
]
