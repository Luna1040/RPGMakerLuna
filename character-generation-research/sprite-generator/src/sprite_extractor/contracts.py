from __future__ import annotations

from dataclasses import asdict, dataclass, field, fields, is_dataclass
from enum import Enum
from fractions import Fraction
from pathlib import Path
from typing import Any, Generic, Mapping, Sequence, TypeVar

CONTRACT_VERSION = "1.0"


class JobOutcome(str, Enum):
    READY = "ready"
    NEEDS_REVIEW = "needs_review"
    NO_USABLE_CYCLE = "no_usable_cycle"
    FAILED = "failed"
    CANCELLED = "cancelled"


@dataclass(frozen=True)
class Rational:
    numerator: int
    denominator: int

    def __post_init__(self) -> None:
        if isinstance(self.numerator, bool) or isinstance(self.denominator, bool) or not isinstance(self.numerator, int) or not isinstance(self.denominator, int): raise ValueError("rational values must be integers")
        if self.denominator <= 0: raise ValueError("rational denominator must be positive")

    @classmethod
    def parse(cls, value: str | Sequence[int] | Fraction | "Rational") -> "Rational":
        if isinstance(value, cls): return value
        if isinstance(value, Fraction): return cls(value.numerator, value.denominator)
        if isinstance(value, str):
            a, b = value.replace(":", "/").split("/", 1)
            return cls(int(a), int(b))
        return cls(int(value[0]), int(value[1]))

    def seconds(self, ticks: int) -> float:
        return ticks * self.numerator / self.denominator


@dataclass(frozen=True)
class CoordinateTransform:
    """Row-major 3x3 transform mapping source coordinates to destination."""
    source_space: str
    destination_space: str
    matrix: tuple[float, ...]

    def __post_init__(self) -> None:
        import math
        if len(self.matrix) != 9 or any(isinstance(x, bool) or not isinstance(x, (int,float)) or not math.isfinite(x) for x in self.matrix): raise ValueError("coordinate transform needs 9 finite values")


@dataclass(frozen=True)
class FrameTiming:
    frame_id: int
    pts: int
    duration: int
    keyframe: bool = False
    decode_path: str | None = None

    def __post_init__(self) -> None:
        if any(isinstance(v, bool) or not isinstance(v, int) for v in (self.frame_id,self.pts,self.duration)): raise ValueError("frame timing values must be integers")
        if self.frame_id < 0 or self.duration <= 0: raise ValueError("frame id must be nonnegative and duration positive")


@dataclass
class SourceManifest:
    content_sha256: str
    path: str
    width: int
    height: int
    time_base: Rational
    frames: list[FrameTiming]
    stream_index: int = 0
    orientation_degrees: int = 0
    pixel_aspect_ratio: Rational = field(default_factory=lambda: Rational(1, 1))
    color_metadata: dict[str, str] = field(default_factory=dict)
    decode_tool: str = "unknown"
    transforms: list[CoordinateTransform] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class BoundingBox:
    x: float
    y: float
    width: float
    height: float

    def __post_init__(self) -> None:
        import math
        if any(isinstance(v,bool) or not isinstance(v,(int,float)) or not math.isfinite(v) for v in (self.x,self.y,self.width,self.height)): raise ValueError("box values must be finite numbers")
        if self.width <= 0 or self.height <= 0: raise ValueError("box dimensions must be positive")


@dataclass(frozen=True)
class Landmark:
    name: str
    x: float
    y: float
    detector_confidence: float
    visibility: float | None = None
    anatomical_side: str | None = None
    assignment_confidence: float | None = None

    def __post_init__(self) -> None:
        import math
        if not all(isinstance(v,(int,float)) and not isinstance(v,bool) and math.isfinite(v) for v in (self.x,self.y,self.detector_confidence)): raise ValueError("landmark coordinates/confidence must be finite")
        for name,value in (("detector_confidence",self.detector_confidence),("visibility",self.visibility),("assignment_confidence",self.assignment_confidence)):
            if value is not None and not 0 <= value <= 1: raise ValueError(f"{name} must be in [0,1]")


@dataclass
class Track:
    track_id: str
    start_frame_id: int
    end_frame_id: int
    regions: dict[int, BoundingBox]
    view_label: str = "unknown"
    confidence: float | None = None
    prompts: list[dict[str, Any]] = field(default_factory=list)
    crop_transforms: list[CoordinateTransform] = field(default_factory=list)
    uncertainty_reasons: list[str] = field(default_factory=list)


@dataclass
class FrameObservation:
    frame_id: int
    pts: int
    track_id: str
    landmarks: dict[str, Landmark] = field(default_factory=dict)
    mask_path: str | None = None
    mask_confidence: float | None = None
    tracked_points: dict[str, tuple[float, float, float]] = field(default_factory=dict)
    descriptors: dict[str, float | list[float] | None] = field(default_factory=dict)
    quality: dict[str, float] = field(default_factory=dict)
    uncertainty_reasons: list[str] = field(default_factory=list)
    temporal_evidence: dict[str, dict[str, Any]] = field(default_factory=dict)


@dataclass(frozen=True)
class MaskArtifact:
    frame_id: int
    pts: int
    track_id: str
    path: str
    confidence: float | None
    full_from_mask: CoordinateTransform
    uncertainty_reasons: tuple[str, ...] = ()


@dataclass(frozen=True)
class MatteArtifact:
    frame_id: int
    pts: int
    track_id: str
    rgba_path: str
    alpha_path: str | None
    boundary_uncertainty: float | None
    settings: dict[str, Any] = field(default_factory=dict)
    correction_history: tuple[str, ...] = ()
    full_from_matte: CoordinateTransform = field(default_factory=lambda: CoordinateTransform("matte_pixels","decoded_full_pixels",(1,0,0,0,1,0,0,0,1)))


@dataclass(frozen=True)
class TrackingPointObservation:
    frame_id: int
    pts: int
    track_id: str
    point_id: str
    x: float
    y: float
    confidence: float
    visible: bool


@dataclass
class CapabilityReport:
    available: bool
    adapter: str
    implementation_version: str
    device: str | None = None
    supported_devices: list[str] = field(default_factory=list)
    checkpoint_path: str | None = None
    checkpoint_sha256: str | None = None
    checkpoint_revision: str | None = None
    license: str | None = None
    diagnostics: list[str] = field(default_factory=list)
    resource_settings: dict[str, Any] = field(default_factory=dict)


T = TypeVar("T")


@dataclass
class StageResult(Generic[T]):
    value: T | None = None
    failure: "StageFailure | None" = None
    warnings: list[str] = field(default_factory=list)
    provenance: dict[str, Any] = field(default_factory=dict)

    @property
    def ok(self) -> bool: return self.failure is None


@dataclass
class PhaseKnot:
    phase: float
    source_time: float
    confidence: float
    kind: str = "event"


@dataclass
class CycleCandidate:
    cycle_id: str
    track_id: str
    start_frame_id: int
    end_frame_id: int
    start_time: float
    end_time: float
    stride_count: int
    phase_map: list[PhaseKnot]
    confidence: float
    score_terms: dict[str, float] = field(default_factory=dict)
    hard_exclusions: list[str] = field(default_factory=list)
    explanation: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class SelectedFrame:
    output_index: int
    source_frame_id: int
    source_pts: int
    source_cycle_id: str
    target_phase: float
    duration_ms: int
    replacement: bool = False
    generated: bool = False


@dataclass
class Selection:
    track_id: str
    frames: list[SelectedFrame]
    playback_mode: str
    source_duration_ms: float
    intended_duration_ms: float
    retiming_ratio: float
    baseline_cycle_id: str
    replacement_spans: list[dict[str, Any]] = field(default_factory=list)
    diagnostics: dict[str, Any] = field(default_factory=dict)


@dataclass
class AlignmentFrame:
    output_index: int
    translate_x: float
    translate_y: float
    scale: float
    source_to_output: CoordinateTransform


@dataclass
class Alignment:
    frames: list[AlignmentFrame]
    canvas_width: int
    canvas_height: int
    pivot_x: float
    pivot_y: float
    body_scale: float
    ground_y: float | None
    mode: str
    confidence: float
    warnings: list[str] = field(default_factory=list)
    evidence: dict[str, Any] = field(default_factory=dict)


@dataclass
class StageFailure:
    stage: str
    code: str
    message: str
    recovery_choices: list[str] = field(default_factory=list)
    details: dict[str, Any] = field(default_factory=dict)


@dataclass
class StageRecord:
    name: str
    version: str
    cache_key: str
    status: str
    artifact_path: str | None = None
    artifact_sha256: str | None = None
    started_at: str | None = None
    completed_at: str | None = None
    failure: StageFailure | None = None


@dataclass
class JobManifest:
    contract_version: str
    job_id: str
    source: SourceManifest | None
    effective_config: dict[str, Any]
    stages: dict[str, StageRecord] = field(default_factory=dict)
    outcome: JobOutcome | None = None
    quality_issues: list[str] = field(default_factory=list)
    export_authorized: bool = False
    revision: int = 0


def to_jsonable(value: Any) -> Any:
    if isinstance(value, Enum): return value.value
    if isinstance(value, Path): return str(value)
    if is_dataclass(value): return {f.name: to_jsonable(getattr(value, f.name)) for f in fields(value)}
    if isinstance(value, Mapping): return {str(k): to_jsonable(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)): return [to_jsonable(v) for v in value]
    return value
