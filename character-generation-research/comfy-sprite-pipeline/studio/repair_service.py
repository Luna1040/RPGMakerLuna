"""Network-free orchestration contract for one W10 temporal-repair window.

The service is intentionally independent from StudioRunner, StudioStore and
the persistent job queue.  A caller supplies decoded frames, the accepted
anchor and their QC report; the service produces staged lossless inputs plus a
patched API workflow.  After ComfyUI returns decoded repair-window frames, the
caller feeds them back to ``finalize`` for deterministic merge, stabilization,
anchor taper and mandatory QC revalidation.
"""

from __future__ import annotations

import json
import re
from copy import deepcopy
from dataclasses import dataclass, fields
from pathlib import Path, PurePosixPath
from typing import Any, Sequence

from PIL import Image, ImageChops, ImageFilter

from .pose_guides import write_lossless_mask_video
from .qc import QCThresholds, analyze_frames
from .temporal_repair import (
    RepairSettings,
    apply_anchor_taper,
    extract_repair_window,
    feather_repair_masks,
    merge_repair_window,
    plan_legacy_repairs,
    stabilize_boundary_root,
    write_lossless_video,
)


W10_PATH = Path(__file__).resolve().parents[1] / "workflows" / "w10-temporal-repair" / "workflow_api.json"
_SAFE_STEM = re.compile(r"[^A-Za-z0-9._-]+")


class RepairServiceError(RuntimeError):
    """Base class for safe orchestration refusal."""


class NoRepairRequired(RepairServiceError):
    def __init__(self, plan: dict[str, Any]):
        super().__init__("continuity QC does not require a W10 repair")
        self.plan = plan


class RegenerationRequired(RepairServiceError):
    def __init__(self, plan: dict[str, Any], message: str = "local W10 repair is unsafe; regenerate the clip"):
        super().__init__(message)
        self.plan = plan


@dataclass(frozen=True)
class PreparedRepair:
    plan: dict[str, Any]
    window: dict[str, Any]
    workflow: dict[str, Any]
    source_path: Path
    mask_path: Path
    anchor_path: Path
    source_frames: tuple[Image.Image, ...]
    masks: tuple[Image.Image, ...]
    canvas: tuple[int, int]
    fps: int

    @property
    def frame_indices(self) -> tuple[int, ...]:
        return tuple(int(index) for index in self.window["source_frame_indices"])


@dataclass(frozen=True)
class RepairResult:
    frames: tuple[Image.Image, ...]
    qc: dict[str, Any]
    accepted: bool
    next_action: str
    improved: bool
    previous_max_adjacent: float | None
    repaired_max_adjacent: float | None
    root_stabilization: tuple[dict[str, Any], ...]
    plan: dict[str, Any]
    window: dict[str, Any]


def _safe_relative_name(value: str, *, label: str) -> str:
    if not value or "\\" in value:
        raise ValueError(f"{label} must be a non-empty POSIX relative path")
    path = PurePosixPath(value)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        raise ValueError(f"{label} must stay inside the configured ComfyUI directory")
    return path.as_posix()


def _find_one(workflow: dict[str, Any], class_type: str, title: str | None = None) -> str:
    matches = []
    for node_id, node in workflow.items():
        if node.get("class_type") != class_type:
            continue
        if title is not None and node.get("_meta", {}).get("title") != title:
            continue
        matches.append(node_id)
    if len(matches) != 1:
        raise ValueError(f"W10 template must contain exactly one {class_type}/{title}: {matches}")
    return matches[0]


def patch_w10_workflow(
    workflow_template: dict[str, Any],
    *,
    source_file: str,
    mask_file: str,
    anchor_file: str,
    width: int,
    height: int,
    length: int,
    fps: int,
    seed: int,
    output_prefix: str,
    strength: float = 0.55,
) -> dict[str, Any]:
    """Purely patch a W10 template for one bounded 12 GB repair job."""

    if length < 5 or (length - 1) % 4:
        raise ValueError("W10 length must be 4n+1 and at least 5")
    if width <= 0 or height <= 0 or width % 16 or height % 16:
        raise ValueError("W10 width and height must be positive multiples of 16")
    if fps <= 0:
        raise ValueError("W10 fps must be positive")
    if not 0.0 <= float(strength) <= 1.0:
        raise ValueError("W10 VACE strength must be in 0..1")
    source_name = _safe_relative_name(source_file, label="source_file")
    mask_name = _safe_relative_name(mask_file, label="mask_file")
    anchor_name = _safe_relative_name(anchor_file, label="anchor_file")
    save_prefix = _safe_relative_name(output_prefix, label="output_prefix")

    workflow = deepcopy(workflow_template)
    workflow[_find_one(workflow, "LoadVideo", "Lossless source repair window")]["inputs"]["file"] = source_name
    workflow[_find_one(workflow, "LoadVideo", "Lossless temporal repair mask")]["inputs"]["file"] = mask_name
    workflow[_find_one(workflow, "LoadImage", "Accepted canonical anchor")]["inputs"]["image"] = anchor_name
    for node in workflow.values():
        if node.get("class_type") == "ImageScale":
            node["inputs"]["width"] = width
            node["inputs"]["height"] = height

    vace = workflow[_find_one(workflow, "WanVaceToVideo")]["inputs"]
    vace.update(
        {
            "width": width,
            "height": height,
            "length": length,
            "batch_size": 1,
            "strength": float(strength),
        }
    )
    sampler = workflow[_find_one(workflow, "KSampler")]["inputs"]
    sampler.update({"seed": int(seed), "steps": 4, "cfg": 1})
    tiled = workflow[_find_one(workflow, "VAEDecodeTiled")]["inputs"]
    tiled.update(
        {
            "tile_size": 256,
            "overlap": 64,
            "temporal_size": 8,
            "temporal_overlap": 4,
        }
    )
    workflow[_find_one(workflow, "CreateVideo")]["inputs"]["fps"] = float(fps)
    workflow[_find_one(workflow, "SaveVideo")]["inputs"]["filename_prefix"] = save_prefix
    return workflow


def _validate_frames(frames: Sequence[Image.Image], anchor: Image.Image, report: dict[str, Any]) -> tuple[list[Image.Image], Image.Image]:
    if len(frames) < 5:
        raise ValueError("repair service requires at least five decoded frames")
    normalized = [frame.convert("RGBA").copy() for frame in frames]
    canvas = normalized[0].size
    if any(frame.size != canvas for frame in normalized):
        raise ValueError("all decoded frames must share one canvas size")
    exact_anchor = anchor.convert("RGBA").copy()
    if exact_anchor.size != canvas:
        raise ValueError("accepted anchor size must match decoded frames")
    if int(report.get("frame_count", 0)) != len(normalized):
        raise ValueError("QC report frame count does not match decoded frames")
    report_canvas = report.get("canvas")
    if report_canvas and report_canvas != {"width": canvas[0], "height": canvas[1]}:
        raise ValueError("QC report canvas does not match decoded frames")
    return normalized, exact_anchor


def _select_masks(
    spatial_masks: Sequence[Image.Image] | None,
    *,
    source_frames: Sequence[Image.Image],
    source_frame_count: int,
    indices: Sequence[int],
    canvas: tuple[int, int],
    temporal_weights: Sequence[float],
) -> list[Image.Image]:
    if spatial_masks is None:
        selected = [_derive_foreground_mask(source_frames[index]) for index in indices]
    elif len(spatial_masks) == source_frame_count:
        selected = [spatial_masks[index].convert("L") for index in indices]
    elif len(spatial_masks) == len(indices):
        selected = [mask.convert("L") for mask in spatial_masks]
    else:
        raise ValueError("spatial masks must cover either the full clip or exactly one repair window")
    if any(mask.size != canvas for mask in selected):
        raise ValueError("repair masks must match the decoded frame canvas")
    return feather_repair_masks(selected, temporal_weights=temporal_weights)


def _derive_foreground_mask(frame: Image.Image) -> Image.Image:
    """Derive a conservative character/prop region from alpha or white matte."""

    rgba = frame.convert("RGBA")
    alpha = rgba.getchannel("A")
    if alpha.getextrema()[0] < 255:
        mask = alpha.point(lambda value: 255 if value > 16 else 0, mode="L")
    else:
        red, green, blue = rgba.convert("RGB").split()
        distance = ImageChops.lighter(
            ImageChops.lighter(ImageChops.invert(red), ImageChops.invert(green)),
            ImageChops.invert(blue),
        )
        mask = distance.point(lambda value: 255 if value > 12 else 0, mode="L")
    if mask.getbbox() is None:
        raise ValueError("cannot derive a safe repair mask from a foreground-free frame")
    # Include outline motion and hand/prop contacts without exposing the full
    # canvas.  Both operations retain grayscale output for later time feather.
    return mask.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(2.0))


def _write_anchor(anchor: Image.Image, destination: Path) -> Path:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(f".{destination.name}.tmp")
    anchor.save(temporary, format="PNG")
    temporary.replace(destination)
    return destination.resolve()


def _thresholds_from_report(report: dict[str, Any]) -> QCThresholds:
    raw = report.get("thresholds", {})
    allowed = {field.name for field in fields(QCThresholds)}
    values = {key: value for key, value in raw.items() if key in allowed}
    return QCThresholds(**values)


def _maximum_adjacent(report: dict[str, Any]) -> float | None:
    values = [
        float(pair["mean_abs"])
        for pair in report.get("adjacent", {}).get("pairs", [])
        if pair.get("mean_abs") is not None
    ]
    return max(values) if values else None


class RepairService:
    """Prepare and verify one local W10 repair without side effects elsewhere."""

    def __init__(
        self,
        *,
        workflow_template: dict[str, Any] | None = None,
        settings: RepairSettings | None = None,
    ) -> None:
        self.settings = settings or RepairSettings()
        self.workflow_template = deepcopy(workflow_template) if workflow_template is not None else json.loads(
            W10_PATH.read_text(encoding="utf-8")
        )

    def prepare(
        self,
        frames: Sequence[Image.Image],
        anchor: Image.Image,
        qc_report: dict[str, Any],
        *,
        output_dir: str | Path,
        spatial_masks: Sequence[Image.Image] | None = None,
        window_index: int = 0,
        fps: int = 16,
        seed: int = 20260715,
        prefix: str = "temporal_repair",
        output_prefix: str = "character_studio/repair/window",
        strength: float = 0.55,
    ) -> PreparedRepair:
        decoded, exact_anchor = _validate_frames(frames, anchor, qc_report)
        plan = plan_legacy_repairs(qc_report, settings=self.settings)
        if plan["action"] == "none":
            raise NoRepairRequired(plan)
        if plan["action"] != "repair" or not plan["windows"]:
            raise RegenerationRequired(plan)
        if exact_anchor.width % 16 or exact_anchor.height % 16:
            raise RegenerationRequired(plan, "decoded canvas is not divisible by 16; W10 must not resize it implicitly")
        if fps <= 0:
            raise ValueError("fps must be positive")
        if not isinstance(window_index, int) or isinstance(window_index, bool):
            raise ValueError("window_index must be an integer")
        if window_index < 0 or window_index >= len(plan["windows"]):
            raise ValueError("window_index is outside the bounded repair plan")
        window = deepcopy(plan["windows"][window_index])
        length = int(window["length"])
        if length < 5 or (length - 1) % 4:
            raise RegenerationRequired(plan, "repair planner returned a non-4n+1 window")
        indices = [int(index) for index in window["source_frame_indices"]]
        if len(indices) != length or any(index < 0 or index >= len(decoded) for index in indices):
            raise RegenerationRequired(plan, "repair planner returned invalid source indices")

        source_frames = extract_repair_window(decoded, indices)
        weights = [float(value) for value in window["temporal_weights"]]
        try:
            masks = _select_masks(
                spatial_masks,
                source_frames=decoded,
                source_frame_count=len(decoded),
                indices=indices,
                canvas=exact_anchor.size,
                temporal_weights=weights,
            )
        except ValueError as exc:
            if spatial_masks is None:
                raise RegenerationRequired(plan, str(exc)) from exc
            raise
        safe_stem = _SAFE_STEM.sub("_", prefix).strip("._") or "temporal_repair"
        root = Path(output_dir).resolve()
        root.mkdir(parents=True, exist_ok=True)
        source_path = write_lossless_video(source_frames, root / f"{safe_stem}_source_ffv1.mkv", fps=fps)
        mask_path = write_lossless_mask_video(masks, root / f"{safe_stem}_mask_ffv1.mkv", fps)
        anchor_path = _write_anchor(exact_anchor, root / f"{safe_stem}_anchor.png")
        workflow = patch_w10_workflow(
            self.workflow_template,
            source_file=source_path.name,
            mask_file=mask_path.name,
            anchor_file=anchor_path.name,
            width=exact_anchor.width,
            height=exact_anchor.height,
            length=length,
            fps=fps,
            seed=seed,
            output_prefix=output_prefix,
            strength=strength,
        )
        return PreparedRepair(
            plan=plan,
            window=window,
            workflow=workflow,
            source_path=source_path,
            mask_path=mask_path.resolve(),
            anchor_path=anchor_path,
            source_frames=tuple(source_frames),
            masks=tuple(masks),
            canvas=exact_anchor.size,
            fps=int(fps),
        )

    def finalize(
        self,
        frames: Sequence[Image.Image],
        anchor: Image.Image,
        qc_report: dict[str, Any],
        prepared: PreparedRepair,
        repaired_window: Sequence[Image.Image],
        *,
        boundary_frames: int = 4,
        max_root_shift_px: int = 12,
        expected_keypoints: Sequence[Any] | None = None,
        observed_keypoints: Sequence[Any] | None = None,
        flow_analysis: bool = True,
    ) -> RepairResult:
        decoded, exact_anchor = _validate_frames(frames, anchor, qc_report)
        if int(prepared.plan.get("frame_count", 0)) != len(decoded) or prepared.canvas != exact_anchor.size:
            raise RegenerationRequired(prepared.plan, "prepared W10 window belongs to a different source clip")
        if any(index < 0 or index >= len(decoded) for index in prepared.frame_indices):
            raise RegenerationRequired(prepared.plan, "prepared W10 window contains stale source indices")
        if len(repaired_window) != int(prepared.window["length"]):
            raise RegenerationRequired(prepared.plan, "W10 returned a different repair-window length")
        repaired = [frame.convert("RGBA").copy() for frame in repaired_window]
        if any(frame.size != exact_anchor.size for frame in repaired):
            raise RegenerationRequired(prepared.plan, "W10 returned a different repair-window canvas")
        if boundary_frames < 1 or boundary_frames * 2 >= len(decoded):
            raise ValueError("boundary_frames leaves no unmodified action interval")

        # W10 already composites through the feathered mask.  Use binary
        # activation here only to retain source pixels in frozen context frames
        # without applying the temporal weight a second time.
        activation = [0.0 if float(value) <= 0.0 else 1.0 for value in prepared.window["temporal_weights"]]
        merged = merge_repair_window(
            decoded,
            repaired,
            indices=prepared.frame_indices,
            temporal_weights=activation,
        )
        stabilized, stabilization = stabilize_boundary_root(
            merged,
            exact_anchor,
            boundary_frames=boundary_frames,
            max_shift_px=max_root_shift_px,
        )
        tapered = apply_anchor_taper(stabilized, exact_anchor, boundary_frames=boundary_frames)
        repaired_qc = analyze_frames(
            tapered,
            anchor=exact_anchor,
            thresholds=_thresholds_from_report(qc_report),
            source={
                "kind": "w10_temporal_repair",
                "window_id": prepared.window["id"],
                "window_kind": prepared.window["kind"],
            },
            boundary_width=int(
                qc_report.get("continuity_regions", {}).get("boundary_width", self.settings.boundary_width)
            ),
            expected_keypoints=expected_keypoints,
            observed_keypoints=observed_keypoints,
            flow_analysis=flow_analysis,
        )
        previous_maximum = _maximum_adjacent(qc_report)
        repaired_maximum = _maximum_adjacent(repaired_qc)
        improved = bool(
            repaired_maximum is not None
            and (previous_maximum is None or repaired_maximum < previous_maximum)
        )
        accepted = repaired_qc.get("status") == "pass"
        return RepairResult(
            frames=tuple(tapered),
            qc=repaired_qc,
            accepted=accepted,
            next_action="commit" if accepted else "regenerate",
            improved=improved,
            previous_max_adjacent=previous_maximum,
            repaired_max_adjacent=repaired_maximum,
            root_stabilization=tuple(stabilization),
            plan=prepared.plan,
            window=prepared.window,
        )


__all__ = [
    "NoRepairRequired",
    "PreparedRepair",
    "RegenerationRequired",
    "RepairResult",
    "RepairService",
    "RepairServiceError",
    "W10_PATH",
    "patch_w10_workflow",
]
