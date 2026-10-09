"""Planning and deterministic CPU assembly for temporal continuity repair.

The module does not enqueue ComfyUI itself.  It turns a continuity-QC report
into explicit 4n+1 repair windows, prepares circular source windows, and
merges a generated VACE result back with a temporal feather.  All functions
operate on decoded Pillow frames so the orchestration layer can remain
single-GPU and persist intermediate lossless assets.
"""

from __future__ import annotations

import math
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Sequence

from PIL import Image, ImageChops


REPAIR_SCHEMA_VERSION = "studio.temporal_repair.v1"


@dataclass(frozen=True)
class RepairSettings:
    local_window_length: int = 13
    boundary_window_length: int = 17
    freeze_context_frames: int = 2
    max_local_windows: int = 2
    boundary_width: int = 4

    def __post_init__(self) -> None:
        for name in ("local_window_length", "boundary_window_length"):
            value = int(getattr(self, name))
            if value < 5 or (value - 1) % 4:
                raise ValueError(f"{name} must be 4n+1 and at least 5")
        if self.freeze_context_frames < 1:
            raise ValueError("freeze_context_frames must be positive")
        if self.freeze_context_frames * 2 >= min(self.local_window_length, self.boundary_window_length):
            raise ValueError("freeze_context_frames leaves no editable repair interval")
        if self.max_local_windows < 1 or self.boundary_width < 1:
            raise ValueError("repair window count and boundary width must be positive")


def _raised_cosine(value: float) -> float:
    t = min(1.0, max(0.0, float(value)))
    return 0.5 - 0.5 * math.cos(math.pi * t)


def temporal_feather_weights(length: int, *, freeze_context_frames: int = 2) -> list[float]:
    """Return symmetric 0..1 merge weights with frozen window endpoints."""

    if length < 5 or (length - 1) % 4:
        raise ValueError("repair length must be 4n+1 and at least 5")
    if freeze_context_frames < 1 or freeze_context_frames * 2 >= length:
        raise ValueError("freeze_context_frames leaves no editable interval")
    editable = length - 2 * freeze_context_frames
    ramp = max(1, (editable + 1) // 2)
    weights: list[float] = []
    for index in range(length):
        if index < freeze_context_frames or index >= length - freeze_context_frames:
            weights.append(0.0)
            continue
        from_start = index - freeze_context_frames + 1
        from_end = length - freeze_context_frames - index
        weights.append(_raised_cosine(min(from_start, from_end) / ramp))
    return weights


def _compatible_window_length(requested: int, frame_count: int) -> int:
    candidate = min(requested, frame_count)
    while candidate >= 5 and (candidate - 1) % 4:
        candidate -= 1
    if candidate < 5:
        raise ValueError("source clip is too short for a 4n+1 temporal repair window")
    return candidate


def repair_window_indices(
    *,
    frame_count: int,
    center_pair_index: int,
    length: int,
    circular: bool,
) -> list[int]:
    """Place the suspect pair at the center of an odd 4n+1 window."""

    if frame_count < 5:
        raise ValueError("source clip must contain at least five frames")
    if center_pair_index < 0 or center_pair_index >= frame_count:
        raise ValueError("center_pair_index is outside the source clip")
    compatible = _compatible_window_length(length, frame_count)
    pair_left_position = compatible // 2 - 1
    start = center_pair_index - pair_left_position
    if circular:
        return [(start + offset) % frame_count for offset in range(compatible)]
    start = min(max(0, start), frame_count - compatible)
    return list(range(start, start + compatible))


def _suspect_pairs(report: dict[str, Any]) -> list[dict[str, Any]]:
    threshold = float(report.get("thresholds", {}).get("max_adjacent_mean_abs", 24.0))
    suspects = []
    for pair in report.get("adjacent", {}).get("pairs", []):
        if bool(pair.get("high_outlier")) or float(pair.get("mean_abs", 0.0)) > threshold:
            suspects.append(pair)
    return suspects


def _cluster_internal_pairs(indices: Sequence[int]) -> list[list[int]]:
    clusters: list[list[int]] = []
    for index in sorted(set(int(value) for value in indices)):
        if clusters and index <= clusters[-1][-1] + 1:
            clusters[-1].append(index)
        else:
            clusters.append([index])
    return clusters


def _window_contract(
    *,
    kind: str,
    frame_count: int,
    center_pair_index: int,
    requested_length: int,
    settings: RepairSettings,
    reason: str,
) -> dict[str, Any]:
    circular = kind in {"circular_vace", "recovery_bridge"}
    indices = repair_window_indices(
        frame_count=frame_count,
        center_pair_index=center_pair_index,
        length=requested_length,
        circular=circular,
    )
    freeze = min(settings.freeze_context_frames, max(1, (len(indices) - 1) // 4))
    return {
        "id": f"repair_{kind}_{center_pair_index}",
        "kind": kind,
        "reason": reason,
        "center_pair_index": center_pair_index,
        "source_frame_indices": indices,
        "length": len(indices),
        "circular": circular,
        "freeze_context_frames": freeze,
        "temporal_weights": temporal_feather_weights(len(indices), freeze_context_frames=freeze),
        "mask_contract": {
            "format": "gray8_ffv1",
            "endpoints_zero": True,
            "threshold_after_decode": False,
        },
    }


def plan_legacy_repairs(
    report: dict[str, Any],
    *,
    settings: RepairSettings | None = None,
) -> dict[str, Any]:
    """Create a bounded repair plan from a ``studio.continuity_qc`` report."""

    options = settings or RepairSettings()
    frame_count = int(report.get("frame_count", 0))
    if frame_count < 5:
        raise ValueError("QC report does not describe a repairable video")
    pairs = report.get("adjacent", {}).get("pairs", [])
    if len(pairs) != frame_count:
        raise ValueError("QC report must contain every adjacent pair including wrap")

    suspects = _suspect_pairs(report)
    endpoint_report = report.get("anchor_endpoints", {})
    first_exact = endpoint_report.get("first_to_anchor", {}).get("exact")
    last_exact = endpoint_report.get("last_to_anchor", {}).get("exact")
    endpoints_exact = first_exact is True and last_exact is True
    boundary_suspects = [pair for pair in suspects if pair.get("region") in {"boundary", "wrap"}]
    internal_suspects = [pair for pair in suspects if pair.get("region") == "internal"]

    windows: list[dict[str, Any]] = []
    reasons: list[str] = []
    if boundary_suspects or not endpoints_exact:
        wrap_pair = next((pair for pair in pairs if pair.get("wrap")), pairs[-1])
        kind = "circular_vace" if endpoints_exact else "recovery_bridge"
        reason = (
            "boundary transition is discontinuous despite exact anchor endpoints"
            if endpoints_exact
            else "legacy endpoints do not both equal the accepted anchor"
        )
        windows.append(
            _window_contract(
                kind=kind,
                frame_count=frame_count,
                center_pair_index=int(wrap_pair["index"]),
                requested_length=options.boundary_window_length,
                settings=options,
                reason=reason,
            )
        )
        reasons.append(reason)

    clusters = _cluster_internal_pairs([int(pair["index"]) for pair in internal_suspects])
    for cluster in clusters:
        center = cluster[len(cluster) // 2]
        reason = f"internal discontinuity around pair(s) {cluster}"
        windows.append(
            _window_contract(
                kind="local_vace",
                frame_count=frame_count,
                center_pair_index=center,
                requested_length=options.local_window_length,
                settings=options,
                reason=reason,
            )
        )
        reasons.append(reason)

    missing_foreground = report.get("geometry", {}).get("summary", {}).get("missing_frame_indices", [])
    catastrophic = bool(missing_foreground) or len(windows) > options.max_local_windows
    if catastrophic:
        action = "regenerate"
        if missing_foreground:
            reasons.append(f"foreground is missing in frames {missing_foreground}")
        if len(windows) > options.max_local_windows:
            reasons.append("too many independent temporal defects for bounded local repair")
    elif windows:
        action = "repair"
    else:
        action = "none"
        reasons.append("QC found no repair candidate")

    result = {
        "schema_version": REPAIR_SCHEMA_VERSION,
        "action": action,
        "frame_count": frame_count,
        "settings": asdict(options),
        "suspect_pair_indices": [int(pair["index"]) for pair in suspects],
        "windows": [] if catastrophic else windows,
        "reasons": reasons,
    }
    return result


def extract_repair_window(frames: Sequence[Image.Image], indices: Sequence[int]) -> list[Image.Image]:
    if not frames:
        raise ValueError("cannot extract from an empty clip")
    result: list[Image.Image] = []
    for index in indices:
        if index < 0 or index >= len(frames):
            raise ValueError("repair window index is outside the source clip")
        result.append(frames[index].convert("RGBA").copy())
    return result


def merge_repair_window(
    frames: Sequence[Image.Image],
    repaired: Sequence[Image.Image],
    *,
    indices: Sequence[int],
    temporal_weights: Sequence[float] | None = None,
    spatial_masks: Sequence[Image.Image] | None = None,
) -> list[Image.Image]:
    """Feather a generated repair window back into source frames."""

    if len(repaired) != len(indices):
        raise ValueError("repaired frames and source indices must have equal length")
    if spatial_masks is not None and len(spatial_masks) != len(indices):
        raise ValueError("spatial mask count must match the repair window")
    if temporal_weights is None:
        temporal_weights = temporal_feather_weights(len(indices))
    if len(temporal_weights) != len(indices):
        raise ValueError("temporal weight count must match the repair window")
    output = [frame.convert("RGBA").copy() for frame in frames]
    if not output:
        raise ValueError("cannot merge into an empty clip")
    canvas = output[0].size
    if any(frame.size != canvas for frame in output):
        raise ValueError("source clip frame sizes do not match")

    for position, source_index in enumerate(indices):
        if source_index < 0 or source_index >= len(output):
            raise ValueError("repair window index is outside the source clip")
        candidate = repaired[position].convert("RGBA")
        if candidate.size != canvas:
            raise ValueError("repaired frame size does not match source clip")
        weight = min(1.0, max(0.0, float(temporal_weights[position])))
        if spatial_masks is None:
            mask = Image.new("L", canvas, round(255 * weight))
        else:
            source_mask = spatial_masks[position].convert("L")
            if source_mask.size != canvas:
                raise ValueError("repair mask size does not match source clip")
            mask = source_mask.point([round(value * weight) for value in range(256)], mode="L")
        output[source_index] = Image.composite(candidate, output[source_index], mask)
    return output


def feather_repair_masks(
    spatial_masks: Sequence[Image.Image],
    *,
    temporal_weights: Sequence[float] | None = None,
    freeze_context_frames: int = 2,
) -> list[Image.Image]:
    """Bake temporal weights into lossless gray8 masks for W10."""

    if not spatial_masks:
        raise ValueError("cannot feather an empty mask sequence")
    if temporal_weights is None:
        temporal_weights = temporal_feather_weights(
            len(spatial_masks),
            freeze_context_frames=freeze_context_frames,
        )
    if len(temporal_weights) != len(spatial_masks):
        raise ValueError("temporal weight count must match mask count")
    canvas = spatial_masks[0].size
    result: list[Image.Image] = []
    for source, raw_weight in zip(spatial_masks, temporal_weights):
        mask = source.convert("L")
        if mask.size != canvas:
            raise ValueError("all repair masks must share one canvas size")
        weight = min(1.0, max(0.0, float(raw_weight)))
        result.append(mask.point([round(value * weight) for value in range(256)], mode="L"))
    return result


def write_lossless_video(frames: Sequence[Image.Image], path: str | Path, *, fps: int) -> Path:
    """Write a color repair window as an FFV1 Matroska stream."""

    if not frames:
        raise ValueError("cannot write an empty repair window")
    try:
        import cv2  # type: ignore
        import numpy as np  # type: ignore
    except ImportError as exc:  # pragma: no cover - optional environment
        raise RuntimeError("OpenCV with FFmpeg is required for FFV1 repair assets") from exc
    destination = Path(path).resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    width, height = frames[0].size
    writer = cv2.VideoWriter(
        str(destination),
        cv2.VideoWriter_fourcc(*"FFV1"),
        float(fps),
        (width, height),
    )
    if not writer.isOpened():
        raise RuntimeError("OpenCV/FFmpeg does not provide the lossless FFV1 codec")
    try:
        for frame in frames:
            if frame.size != (width, height):
                raise ValueError("all repair frames must share one canvas size")
            rgb = np.asarray(frame.convert("RGB"), dtype=np.uint8)
            writer.write(cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR))
    finally:
        writer.release()
    return destination


def apply_anchor_taper(
    frames: Sequence[Image.Image],
    anchor: Image.Image,
    *,
    boundary_frames: int = 4,
) -> list[Image.Image]:
    """Make endpoints exact while distributing their correction over a band."""

    if len(frames) < 3:
        raise ValueError("anchor taper requires at least three master frames")
    if boundary_frames < 1 or boundary_frames * 2 >= len(frames):
        raise ValueError("boundary_frames leaves no unmodified action interval")
    exact_anchor = anchor.convert("RGBA")
    output: list[Image.Image] = []
    for index, source in enumerate(frames):
        frame = source.convert("RGBA")
        if frame.size != exact_anchor.size:
            raise ValueError("anchor and source frame sizes must match")
        start_weight = _raised_cosine(index / boundary_frames) if index < boundary_frames else 1.0
        distance_to_end = len(frames) - 1 - index
        end_weight = _raised_cosine(distance_to_end / boundary_frames) if distance_to_end < boundary_frames else 1.0
        output.append(Image.blend(exact_anchor, frame, min(start_weight, end_weight)))
    output[0] = exact_anchor.copy()
    output[-1] = exact_anchor.copy()
    return output


def _foreground_root(image: Image.Image, *, white_tolerance: int = 12) -> tuple[float, float] | None:
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A")
    if alpha.getextrema()[0] < 255:
        mask = alpha.point(lambda value: 255 if value > 16 else 0, mode="L")
    else:
        red, green, blue = rgba.convert("RGB").split()
        distance = ImageChops.lighter(
            ImageChops.lighter(ImageChops.invert(red), ImageChops.invert(green)),
            ImageChops.invert(blue),
        )
        mask = distance.point(lambda value: 255 if value > white_tolerance else 0, mode="L")
    bbox = mask.getbbox()
    if bbox is None:
        return None
    left, _, right, bottom = bbox
    return (left + right) / 2.0, float(bottom - 1)


def stabilize_boundary_root(
    frames: Sequence[Image.Image],
    anchor: Image.Image,
    *,
    boundary_frames: int = 4,
    max_shift_px: int = 12,
) -> tuple[list[Image.Image], list[dict[str, Any]]]:
    """Integer-align only the loop boundary band to the accepted anchor root."""

    if not frames:
        raise ValueError("cannot stabilize an empty clip")
    if boundary_frames < 1 or max_shift_px < 0:
        raise ValueError("boundary_frames must be positive and max_shift_px non-negative")
    exact_anchor = anchor.convert("RGBA")
    anchor_root = _foreground_root(exact_anchor)
    if anchor_root is None:
        raise ValueError("accepted anchor has no detectable foreground")
    output = [frame.convert("RGBA").copy() for frame in frames]
    if any(frame.size != exact_anchor.size for frame in output):
        raise ValueError("anchor and source frame sizes must match")
    selected = set(range(min(boundary_frames, len(output))))
    selected.update(range(max(0, len(output) - boundary_frames), len(output)))
    diagnostics: list[dict[str, Any]] = []
    fill = exact_anchor.getpixel((0, 0))

    for index in sorted(selected):
        root = _foreground_root(output[index])
        if root is None:
            diagnostics.append({"index": index, "applied": False, "reason": "foreground_missing"})
            continue
        raw_dx = int(round(anchor_root[0] - root[0]))
        raw_dy = int(round(anchor_root[1] - root[1]))
        dx = max(-max_shift_px, min(max_shift_px, raw_dx))
        dy = max(-max_shift_px, min(max_shift_px, raw_dy))
        shifted = Image.new("RGBA", exact_anchor.size, fill)
        shifted.paste(output[index], (dx, dy))
        output[index] = shifted
        diagnostics.append(
            {
                "index": index,
                "applied": bool(dx or dy),
                "translation_px": {"x": dx, "y": dy},
                "clamped": dx != raw_dx or dy != raw_dy,
            }
        )
    return output, diagnostics


__all__ = [
    "REPAIR_SCHEMA_VERSION",
    "RepairSettings",
    "apply_anchor_taper",
    "extract_repair_window",
    "feather_repair_masks",
    "merge_repair_window",
    "plan_legacy_repairs",
    "repair_window_indices",
    "stabilize_boundary_root",
    "temporal_feather_weights",
    "write_lossless_video",
]
