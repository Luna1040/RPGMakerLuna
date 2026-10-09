from __future__ import annotations

import hashlib
import json
import math
import re
import threading
import uuid
from copy import deepcopy
from datetime import datetime, timezone
from io import BytesIO
from pathlib import Path
from typing import Any

from PIL import Image, UnidentifiedImageError

from .catalog import GRIP_TYPES, PROP_SLOTS, QUALITY_PROFILES, SCHEMA_VERSION, get_motion
from .visemes import STUDIO_VISEMES, VISEME_ATLAS_SCHEMA, VISEME_TIMELINE_SCHEMA


PROJECT_ID_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")
ASSET_ID_RE = re.compile(r"^asset_[a-f0-9]{16}$")
SIGNATURE_RE = re.compile(r"^[a-f0-9]{64}$")
PROP_ID_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")
ALLOWED_IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp"}
ALLOWED_AUDIO_EXTENSIONS = {".wav", ".mp3", ".ogg", ".flac", ".m4a"}
ALLOWED_VIDEO_EXTENSIONS = {".mp4", ".webm", ".mov"}
CONTENT_TYPES = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".wav": "audio/wav",
    ".mp3": "audio/mpeg",
    ".ogg": "audio/ogg",
    ".flac": "audio/flac",
    ".m4a": "audio/mp4",
    ".mp4": "video/mp4",
    ".webm": "video/webm",
    ".mov": "video/quicktime",
}
IMAGE_ROLES = {
    "primary", "secondary", "detail", "prop", "mouth_reference", "anchor",
    "component_overlay", "component_animation", "component_stage_image",
}
AUDIO_ROLES = {"audio"}
VIDEO_ROLES = {"clip", "component_stage_video"}
MAX_IMAGE_BYTES = 25 * 1024 * 1024
MAX_AUDIO_BYTES = 100 * 1024 * 1024
MAX_VIDEO_BYTES = 500 * 1024 * 1024
MAX_SPRITESHEET_BYTES = 200 * 1024 * 1024
MAX_QC_REPORT_BYTES = 5 * 1024 * 1024
MAX_VISEME_ATLAS_BYTES = 50 * 1024 * 1024
MAX_RIGID_PROP_BYTES = 16 * 1024

RIGID_PROP_FIELDS = {
    "handle_axis_local",
    "handle_axis_uv",
    "handle_axis",
    "nominal_scale",
    "scale",
    "attachments",
    "grip_points",
    "origin",
    "rotation_offset_deg",
    "coordinate_space",
    "scale_policy",
    "z_policy",
    "mask_dilate_px",
    "contact_radius_px",
    "hand_order",
    "min_grip_separation_ratio",
    "grip_t",
    "handle_t",
    "grip_point_local",
    "grip_point_uv",
    "palm_landmark",
}
RIGID_ATTACHMENT_FIELDS = {
    "hand",
    "handle_t",
    "grip_t",
    "grip_point_local",
    "grip_point_uv",
    "palm_landmark",
}


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _slug(value: str) -> str:
    value = value.strip().lower()
    value = re.sub(r"[^a-z0-9а-яё_-]+", "-", value, flags=re.IGNORECASE)
    value = value.encode("ascii", "ignore").decode("ascii")
    value = re.sub(r"-+", "-", value).strip("-_")
    return value[:42] or "character"


def _empty_anchor() -> dict[str, Any]:
    return {
        "revision": 0,
        "status": "missing",
        "asset_id": None,
        "canvas": None,
        "root": None,
        "ground_y": None,
        "neutral_bbox": None,
        "pose_keypoints": None,
        "mouth_roi": None,
        "eye_roi": None,
    }


def _empty_viseme_atlas() -> dict[str, Any]:
    return {
        "status": "missing",
        "atlas_asset_id": None,
        "manifest_asset_id": None,
        "tile_asset_ids": {},
        "manifest": None,
        "anchor_revision": None,
        "anchor_asset_id": None,
        "input_signature": None,
    }


def _clip_key(loadout_id: str, motion_id: str) -> str:
    """Keep the historical default keys while namespacing other loadouts."""

    return motion_id if loadout_id == "default" else f"{loadout_id}::{motion_id}"


def _inspect_runtime_rgba_spritesheet(
    data: bytes,
    *,
    frame_count: int,
    width: int,
    height: int,
) -> dict[str, Any]:
    """Decode and independently verify a W12 sheet at the persistence boundary."""

    if frame_count < 1 or width < 1 or height < 1:
        raise ValueError("W12 runtime sheet contract requires positive dimensions and frame count")
    try:
        with Image.open(BytesIO(data)) as opened:
            opened.load()
            if opened.format != "PNG" or "A" not in opened.getbands():
                raise ValueError("W12 runtime export must be a PNG with a real alpha channel")
            sheet = opened.convert("RGBA").copy()
    except (UnidentifiedImageError, OSError) as exc:
        raise ValueError("W12 runtime export is not a decodable PNG") from exc
    expected_size = (width * frame_count, height)
    if sheet.size != expected_size:
        raise ValueError(
            f"W12 runtime sheet is {sheet.width}x{sheet.height}; expected "
            f"{expected_size[0]}x{expected_size[1]}"
        )
    coverage: list[float] = []
    low_alpha_pixels = 0
    for index in range(frame_count):
        alpha = sheet.crop((index * width, 0, (index + 1) * width, height)).getchannel("A")
        histogram = alpha.histogram()
        ratio = sum(histogram[17:]) / float(width * height)
        if ratio < 0.005 or ratio > 0.95:
            raise ValueError(f"W12 alpha coverage is unsafe on frame {index}: {ratio:.4f}")
        coverage.append(ratio)
        low_alpha_pixels += sum(histogram[1:17])
    return {
        "min": min(coverage),
        "max": max(coverage),
        "mean": sum(coverage) / len(coverage),
        "low_alpha_pixels": low_alpha_pixels,
    }


def _rigid_number(
    value: Any,
    *,
    label: str,
    minimum: float | None = None,
    maximum: float | None = None,
) -> float:
    if isinstance(value, bool):
        raise ValueError(f"{label} must be a number")
    try:
        number = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{label} must be a number") from exc
    if not math.isfinite(number):
        raise ValueError(f"{label} must be finite")
    if minimum is not None and number < minimum:
        raise ValueError(f"{label} must be at least {minimum}")
    if maximum is not None and number > maximum:
        raise ValueError(f"{label} must be at most {maximum}")
    return number


def _rigid_point(value: Any, *, label: str) -> None:
    if not isinstance(value, (list, tuple)) or len(value) != 2:
        raise ValueError(f"{label} must be a two-number point")
    _rigid_number(value[0], label=f"{label}[0]")
    _rigid_number(value[1], label=f"{label}[1]")


def _validate_rigid_attachment(value: Any, *, label: str, hand_required: bool) -> None:
    if not isinstance(value, dict):
        raise ValueError(f"{label} must be an object")
    unknown = set(value) - RIGID_ATTACHMENT_FIELDS
    if unknown:
        raise ValueError(f"unsupported {label} fields: {', '.join(sorted(unknown))}")
    hand = value.get("hand")
    if hand_required and hand not in {"left", "right"}:
        raise ValueError(f"{label}.hand must be left or right")
    if hand is not None and hand not in {"left", "right"}:
        raise ValueError(f"{label}.hand must be left or right")
    for key in ("handle_t", "grip_t"):
        if key in value:
            _rigid_number(value[key], label=f"{label}.{key}", minimum=0.0, maximum=1.0)
    point_keys = [key for key in ("grip_point_local", "grip_point_uv") if key in value]
    if len(point_keys) > 1:
        raise ValueError(f"{label} must use only one grip point coordinate field")
    for key in point_keys:
        _rigid_point(value[key], label=f"{label}.{key}")
    if "palm_landmark" in value:
        landmark = value["palm_landmark"]
        if not isinstance(landmark, str) or not landmark.strip() or len(landmark) > 64:
            raise ValueError(f"{label}.palm_landmark must be a short string")


def _validate_rigid_prop(value: Any, *, prop_id: str, slot: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"prop.rigid must be an object: {prop_id}")
    unknown = set(value) - RIGID_PROP_FIELDS
    if unknown:
        raise ValueError(f"unsupported prop.rigid fields for {prop_id}: {', '.join(sorted(unknown))}")

    axis_keys = [key for key in ("handle_axis_local", "handle_axis_uv", "handle_axis") if key in value]
    if len(axis_keys) > 1:
        raise ValueError(f"prop.rigid must define only one handle axis: {prop_id}")
    for key in axis_keys:
        axis = value[key]
        if not isinstance(axis, (list, tuple)) or len(axis) != 2:
            raise ValueError(f"prop.rigid.{key} must contain two points: {prop_id}")
        _rigid_point(axis[0], label=f"prop.rigid.{key}[0]")
        _rigid_point(axis[1], label=f"prop.rigid.{key}[1]")
        if math.dist(tuple(map(float, axis[0])), tuple(map(float, axis[1]))) <= 1e-9:
            raise ValueError(f"prop.rigid handle axis endpoints must differ: {prop_id}")

    for key in ("nominal_scale", "scale"):
        if key in value:
            _rigid_number(value[key], label=f"prop.rigid.{key}", minimum=1e-6, maximum=10000.0)
    if "rotation_offset_deg" in value:
        _rigid_number(value["rotation_offset_deg"], label="prop.rigid.rotation_offset_deg")
    if "origin" in value:
        _rigid_point(value["origin"], label="prop.rigid.origin")
    for key in ("grip_t", "handle_t", "min_grip_separation_ratio"):
        if key in value:
            _rigid_number(value[key], label=f"prop.rigid.{key}", minimum=0.0, maximum=1.0)
    point_keys = [key for key in ("grip_point_local", "grip_point_uv") if key in value]
    if len(point_keys) > 1:
        raise ValueError(f"prop.rigid must use only one grip point coordinate field: {prop_id}")
    for key in point_keys:
        _rigid_point(value[key], label=f"prop.rigid.{key}")

    if "coordinate_space" in value and value["coordinate_space"] not in {"local", "uv", "pixels"}:
        raise ValueError(f"unsupported prop.rigid coordinate_space: {prop_id}")
    if "scale_policy" in value and value["scale_policy"] != "locked":
        raise ValueError(f"rigid prop scale_policy must be locked: {prop_id}")
    if "z_policy" in value and value["z_policy"] not in {"front", "behind", "mixed"}:
        raise ValueError(f"unsupported prop.rigid z_policy: {prop_id}")
    if "hand_order" in value and value["hand_order"] not in {"left_before_right", "right_before_left"}:
        raise ValueError(f"unsupported prop.rigid hand_order: {prop_id}")
    if "palm_landmark" in value:
        landmark = value["palm_landmark"]
        if not isinstance(landmark, str) or not landmark.strip() or len(landmark) > 64:
            raise ValueError(f"prop.rigid.palm_landmark must be a short string: {prop_id}")
    for key, minimum, maximum in (
        ("mask_dilate_px", 0, 128),
        ("contact_radius_px", 1, 256),
    ):
        if key in value:
            number = _rigid_number(value[key], label=f"prop.rigid.{key}", minimum=minimum, maximum=maximum)
            if not number.is_integer():
                raise ValueError(f"prop.rigid.{key} must be an integer: {prop_id}")

    attachments = value.get("attachments")
    if attachments is not None:
        if not isinstance(attachments, list) or len(attachments) > 2:
            raise ValueError(f"prop.rigid.attachments must contain at most two items: {prop_id}")
        for index, attachment in enumerate(attachments):
            _validate_rigid_attachment(
                attachment,
                label=f"prop.rigid.attachments[{index}]",
                hand_required=True,
            )
        hands = [item.get("hand") for item in attachments]
        if len(hands) != len(set(hands)):
            raise ValueError(f"prop.rigid attachments must use distinct hands: {prop_id}")
        expected_hands = {
            "left_hand": ["left"],
            "right_hand": ["right"],
            "both_hands": ["left", "right"],
        }.get(slot, [])
        if sorted(hands) != sorted(expected_hands):
            raise ValueError(f"prop.rigid attachments do not match slot {slot}: {prop_id}")

    grip_points = value.get("grip_points")
    if grip_points is not None:
        if not isinstance(grip_points, dict) or set(grip_points) - {"left", "right"}:
            raise ValueError(f"prop.rigid.grip_points must use left/right keys: {prop_id}")
        expected_grip_hands = {
            "left_hand": {"left"},
            "right_hand": {"right"},
            "both_hands": {"left", "right"},
        }.get(slot, set())
        if set(grip_points) != expected_grip_hands:
            raise ValueError(f"prop.rigid.grip_points do not match slot {slot}: {prop_id}")
        for hand, grip_point in grip_points.items():
            if isinstance(grip_point, dict):
                _validate_rigid_attachment(
                    grip_point,
                    label=f"prop.rigid.grip_points.{hand}",
                    hand_required=False,
                )
            else:
                _rigid_point(grip_point, label=f"prop.rigid.grip_points.{hand}")

    one_hand_only = {
        "grip_t",
        "handle_t",
        "grip_point_local",
        "grip_point_uv",
        "palm_landmark",
    }
    if one_hand_only & set(value) and slot not in {"left_hand", "right_hand"}:
        raise ValueError(f"top-level prop.rigid grip fields require a one-hand slot: {prop_id}")
    if {"hand_order", "min_grip_separation_ratio"} & set(value) and slot != "both_hands":
        raise ValueError(f"two-hand prop.rigid fields require slot both_hands: {prop_id}")

    try:
        encoded = json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(",", ":"))
    except (TypeError, ValueError) as exc:
        raise ValueError(f"prop.rigid must be JSON-safe: {prop_id}") from exc
    if len(encoded.encode("utf-8")) > MAX_RIGID_PROP_BYTES:
        raise ValueError(f"prop.rigid is too large: {prop_id}")
    # JSON roundtrip preserves every accepted field while normalising tuples
    # and other JSON-compatible containers into manifest-safe values.
    return json.loads(encoded)


class StudioStore:
    """Filesystem-backed project store with path and manifest validation."""

    def __init__(self, root: Path):
        self.root = root.resolve()
        self.projects_root = self.root / "projects"
        self.projects_root.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()

    @staticmethod
    def clip_key(loadout_id: str, motion_id: str) -> str:
        return _clip_key(loadout_id, motion_id)

    @staticmethod
    def anchor_for(project: dict[str, Any], loadout_id: str = "default") -> dict[str, Any]:
        anchors = project.get("anchors")
        if isinstance(anchors, dict) and isinstance(anchors.get(loadout_id), dict):
            return anchors[loadout_id]
        if loadout_id == project.get("active_loadout_id", "default"):
            return project.get("anchor", {})
        if loadout_id == "default" and not anchors:
            return project.get("anchor", {})
        return {}

    @staticmethod
    def viseme_atlas_for(project: dict[str, Any], loadout_id: str = "default") -> dict[str, Any]:
        voice = project.get("voice", {})
        atlases = voice.get("atlases")
        if isinstance(atlases, dict) and isinstance(atlases.get(loadout_id), dict):
            return atlases[loadout_id]
        if loadout_id == project.get("active_loadout_id", "default") and voice.get("atlas_asset_id"):
            return {
                "status": voice.get("atlas_status", "ready"),
                "atlas_asset_id": voice.get("atlas_asset_id"),
                "manifest_asset_id": voice.get("atlas_manifest_asset_id"),
                "tile_asset_ids": {},
                "manifest": voice.get("atlas_manifest"),
            }
        return {}

    @classmethod
    def _sync_voice_alias(cls, project: dict[str, Any]) -> None:
        voice = project.setdefault("voice", {})
        component = project.setdefault("component", {})
        component.setdefault("overlays", {})
        component.setdefault("actions", {})
        active = str(project.get("active_loadout_id", "default"))
        atlases = voice.setdefault("atlases", {})
        record = atlases.setdefault(active, _empty_viseme_atlas())
        voice["atlas_status"] = record.get("status", "missing")
        voice["atlas_asset_id"] = record.get("atlas_asset_id")
        voice["atlas_manifest_asset_id"] = record.get("manifest_asset_id")
        voice["atlas_manifest"] = deepcopy(record.get("manifest"))
        anchor = cls.anchor_for(project, active)
        voice["mouth_roi"] = deepcopy(anchor.get("mouth_roi")) if anchor else None

    @staticmethod
    def _sync_anchor_alias(project: dict[str, Any]) -> None:
        loadouts = project.get("loadouts", [])
        valid_ids = {item.get("id") for item in loadouts if isinstance(item, dict)}
        active = str(project.get("active_loadout_id", "default"))
        if active not in valid_ids:
            active = "default" if "default" in valid_ids else next(iter(valid_ids), "default")
        project["active_loadout_id"] = active
        anchors = project.setdefault("anchors", {})
        anchors.setdefault(active, _empty_anchor())
        project["anchor"] = deepcopy(anchors[active])

    @classmethod
    def _upgrade_project(cls, project: dict[str, Any]) -> dict[str, Any]:
        """Upgrade manifests in memory while preserving the v1 anchor alias."""

        if int(project.get("schema_version", 0) or 0) < SCHEMA_VERSION:
            project["schema_version"] = SCHEMA_VERSION
        project.setdefault("loadouts", [{"id": "default", "name": "Основной", "prop_ids": []}])
        active = str(project.get("active_loadout_id", "default"))
        project["active_loadout_id"] = active
        anchors = project.get("anchors")
        if not isinstance(anchors, dict):
            legacy_anchor = project.get("anchor")
            anchors = {active: deepcopy(legacy_anchor) if isinstance(legacy_anchor, dict) else _empty_anchor()}
            project["anchors"] = anchors
        for loadout in project.get("loadouts", []):
            if isinstance(loadout, dict) and loadout.get("id"):
                anchors.setdefault(str(loadout["id"]), _empty_anchor())
        voice = project.setdefault("voice", {})
        voice.setdefault("mode", "viseme_atlas")
        voice.setdefault("mouth_roi", None)
        voice.setdefault("atlas_asset_id", None)
        voice.setdefault("audio_asset_id", None)
        voice.setdefault("timeline_asset_id", None)
        voice.setdefault("timing_source", None)
        voice.setdefault("timeline", None)
        voice.setdefault("timeline_status", "missing")
        atlases = voice.get("atlases")
        if not isinstance(atlases, dict):
            atlases = {}
            legacy_asset_id = voice.get("atlas_asset_id")
            if legacy_asset_id:
                atlases[active] = {
                    **_empty_viseme_atlas(),
                    "status": voice.get("atlas_status", "ready"),
                    "atlas_asset_id": legacy_asset_id,
                    "manifest_asset_id": voice.get("atlas_manifest_asset_id"),
                    "manifest": deepcopy(voice.get("atlas_manifest")),
                }
            voice["atlases"] = atlases
        cls._sync_anchor_alias(project)
        cls._sync_voice_alias(project)
        return project

    def _project_dir(self, project_id: str) -> Path:
        if not PROJECT_ID_RE.fullmatch(project_id):
            raise ValueError("invalid project id")
        target = (self.projects_root / project_id).resolve()
        target.relative_to(self.projects_root)
        return target

    def _manifest_path(self, project_id: str) -> Path:
        return self._project_dir(project_id) / "project.json"

    def _write_manifest(self, project: dict[str, Any]) -> None:
        project_id = project["id"]
        manifest_path = self._manifest_path(project_id)
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        temporary = manifest_path.with_name(f".{manifest_path.name}.{uuid.uuid4().hex}.tmp")
        temporary.write_text(
            json.dumps(project, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        temporary.replace(manifest_path)

    def create_project(
        self,
        name: str,
        *,
        quality_profile: str = "local_12gb",
        language: str = "ru",
    ) -> dict[str, Any]:
        clean_name = " ".join(name.strip().split())
        if not clean_name:
            raise ValueError("project name is required")
        if len(clean_name) > 120:
            raise ValueError("project name is too long")
        profile_ids = {item["id"] for item in QUALITY_PROFILES}
        if quality_profile not in profile_ids:
            raise ValueError("unknown quality profile")

        with self._lock:
            project_id = f"{_slug(clean_name)}-{uuid.uuid4().hex[:8]}"
            now = _utc_now()
            project = {
                "schema_version": SCHEMA_VERSION,
                "revision": 1,
                "id": project_id,
                "name": clean_name,
                "created_at": now,
                "updated_at": now,
                "status": "draft",
                "settings": {
                    "quality_profile": quality_profile,
                    "language": language if language in {"ru", "en", "auto"} else "auto",
                    "facing": "front",
                    "background": "white",
                },
                "references": {"primary": None, "secondary": None, "detail": None},
                "assets": {},
                "props": [],
                "loadouts": [{"id": "default", "name": "Основной", "prop_ids": []}],
                "active_loadout_id": "default",
                "selected_motions": ["idle_breathing", "wave_left", "wave_right", "nod"],
                "anchors": {"default": _empty_anchor()},
                "anchor": _empty_anchor(),
                "voice": {
                    "mode": "viseme_atlas",
                    "mouth_roi": None,
                    "atlas_asset_id": None,
                    "atlas_status": "missing",
                    "atlas_manifest_asset_id": None,
                    "atlas_manifest": None,
                    "atlases": {"default": _empty_viseme_atlas()},
                    "audio_asset_id": None,
                    "timeline_asset_id": None,
                    "timing_source": None,
                    "timeline": None,
                    "timeline_status": "missing",
                },
                "clips": {},
                "component": {"overlays": {}, "actions": {}},
                "last_plan": None,
            }
            project_dir = self._project_dir(project_id)
            (project_dir / "assets").mkdir(parents=True, exist_ok=False)
            (project_dir / "runs").mkdir(parents=True, exist_ok=False)
            self._write_manifest(project)
            return deepcopy(project)

    def list_projects(self) -> list[dict[str, Any]]:
        projects: list[dict[str, Any]] = []
        with self._lock:
            for manifest in sorted(self.projects_root.glob("*/project.json")):
                try:
                    project = self._upgrade_project(json.loads(manifest.read_text(encoding="utf-8")))
                except (OSError, json.JSONDecodeError):
                    continue
                projects.append(
                    {
                        "id": project.get("id"),
                        "name": project.get("name"),
                        "status": project.get("status", "draft"),
                        "updated_at": project.get("updated_at"),
                        "revision": project.get("revision", 0),
                        "primary_asset_id": project.get("references", {}).get("primary"),
                        "anchor_status": project.get("anchor", {}).get("status", "missing"),
                        "clip_count": len(project.get("clips", {})),
                    }
                )
        projects.sort(key=lambda item: item.get("updated_at") or "", reverse=True)
        return projects

    def delete_project(self, project_id: str) -> None:
        """Permanently remove one validated project directory."""
        with self._lock:
            target = self._project_dir(project_id).resolve()
            try:
                target.relative_to(self.projects_root)
            except ValueError as exc:
                raise ValueError("project path escapes projects root") from exc
            if not target.is_dir():
                raise FileNotFoundError(project_id)
            import shutil
            shutil.rmtree(target)

    def get_project(self, project_id: str) -> dict[str, Any]:
        with self._lock:
            manifest_path = self._manifest_path(project_id)
            if not manifest_path.is_file():
                raise FileNotFoundError(project_id)
            project = self._upgrade_project(json.loads(manifest_path.read_text(encoding="utf-8")))
            return deepcopy(project)

    def update_project(
        self,
        project_id: str,
        patch: dict[str, Any],
        *,
        expected_revision: int | None = None,
    ) -> dict[str, Any]:
        if not isinstance(patch, dict):
            raise ValueError("project patch must be an object")
        allowed = {
            "name",
            "settings",
            "props",
            "loadouts",
            "active_loadout_id",
            "selected_motions",
            "voice",
            "anchor",
            "last_plan",
        }
        unknown = set(patch) - allowed
        if unknown:
            raise ValueError(f"unsupported project fields: {', '.join(sorted(unknown))}")

        with self._lock:
            project = self.get_project(project_id)
            if expected_revision is not None and project["revision"] != expected_revision:
                raise RuntimeError("project revision conflict")
            canonical_before = {
                item["id"]: self.generation_signature(
                    project,
                    "canonicalize",
                    {"loadout_id": item["id"]},
                )
                for item in project.get("loadouts", [])
            }
            motion_inputs_changed = False

            if "name" in patch:
                clean_name = " ".join(str(patch["name"]).strip().split())
                if not clean_name or len(clean_name) > 120:
                    raise ValueError("invalid project name")
                project["name"] = clean_name

            if "settings" in patch:
                settings = patch["settings"]
                if not isinstance(settings, dict):
                    raise ValueError("settings must be an object")
                allowed_settings = {"quality_profile", "language", "facing", "background"}
                if set(settings) - allowed_settings:
                    raise ValueError("unsupported settings field")
                if "quality_profile" in settings and settings["quality_profile"] not in {item["id"] for item in QUALITY_PROFILES}:
                    raise ValueError("unknown quality profile")
                if "language" in settings and settings["language"] not in {"ru", "en", "auto"}:
                    raise ValueError("unsupported language")
                if "facing" in settings and settings["facing"] not in {"front", "three_quarter_left", "three_quarter_right", "profile_left", "profile_right"}:
                    raise ValueError("unsupported facing")
                if "background" in settings and settings["background"] not in {"white", "transparent"}:
                    raise ValueError("unsupported background")
                project["settings"].update(settings)
                motion_inputs_changed = bool({"quality_profile", "facing", "background"} & set(settings))

            if "props" in patch:
                project["props"] = self._validate_props(patch["props"], project["assets"])
                motion_inputs_changed = True

            if "loadouts" in patch:
                project["loadouts"] = self._validate_loadouts(patch["loadouts"], project.get("props", []))
                for loadout in project["loadouts"]:
                    project.setdefault("anchors", {}).setdefault(loadout["id"], _empty_anchor())
                motion_inputs_changed = True
            elif "props" in patch:
                # A props-only patch must not leave manifests that reference removed ids.
                project["loadouts"] = self._validate_loadouts(project.get("loadouts", []), project["props"])

            if "active_loadout_id" in patch:
                active_loadout_id = str(patch["active_loadout_id"])
                if active_loadout_id not in {item["id"] for item in project.get("loadouts", [])}:
                    raise ValueError("unknown active loadout")
                project["active_loadout_id"] = active_loadout_id
                project["last_plan"] = None
            self._sync_anchor_alias(project)
            self._sync_voice_alias(project)

            if "selected_motions" in patch:
                values = patch["selected_motions"]
                if not isinstance(values, list) or any(not isinstance(item, str) for item in values):
                    raise ValueError("selected_motions must be a list of ids")
                project["selected_motions"] = list(dict.fromkeys(values))[:128]
                project["last_plan"] = None

            if "voice" in patch:
                voice = patch["voice"]
                if not isinstance(voice, dict):
                    raise ValueError("voice must be an object")
                allowed_voice = {
                    "mode",
                    "mouth_roi",
                    "atlas_asset_id",
                    "audio_asset_id",
                    "timeline_asset_id",
                    "timing_source",
                }
                if set(voice) - allowed_voice:
                    raise ValueError("unsupported voice field")
                for asset_field in ("atlas_asset_id", "audio_asset_id", "timeline_asset_id"):
                    asset_id = voice.get(asset_field)
                    if asset_id is not None and asset_id not in project["assets"]:
                        raise ValueError(f"unknown voice asset: {asset_id}")
                project["voice"].update(voice)

            if "anchor" in patch:
                anchor = patch["anchor"]
                if not isinstance(anchor, dict):
                    raise ValueError("anchor must be an object")
                allowed_anchor = {"root", "ground_y", "neutral_bbox", "pose_keypoints", "mouth_roi", "eye_roi"}
                if set(anchor) - allowed_anchor:
                    raise ValueError("anchor acceptance must use the dedicated accept-anchor endpoint")
                active_anchor = self.anchor_for(project, project.get("active_loadout_id", "default"))
                anchor_asset_id = anchor.get("asset_id", active_anchor.get("asset_id"))
                if anchor_asset_id is not None and anchor_asset_id not in project["assets"]:
                    raise ValueError("unknown anchor asset")
                active_anchor.update(anchor)
                self._sync_anchor_alias(project)
                self._mark_viseme_atlas_stale(project, project.get("active_loadout_id", "default"), "anchor mouth ROI changed")
                self._sync_voice_alias(project)
                motion_inputs_changed = True

            if "last_plan" in patch:
                project["last_plan"] = patch["last_plan"]

            canonical_changed = False
            for loadout in project.get("loadouts", []):
                loadout_id = loadout["id"]
                canonical_after = self.generation_signature(
                    project,
                    "canonicalize",
                    {"loadout_id": loadout_id},
                )
                if canonical_before.get(loadout_id) != canonical_after:
                    canonical_changed = True
                    self._mark_anchor_stale(project, loadout_id, "canonical inputs changed")
            if motion_inputs_changed and not canonical_changed:
                for loadout in project.get("loadouts", []):
                    self._mark_clips_stale(project, "motion inputs changed", loadout_id=loadout["id"])

            project["revision"] += 1
            project["updated_at"] = _utc_now()
            project["status"] = self._derive_status(project)
            self._write_manifest(project)
            return deepcopy(project)

    def accept_anchor(
        self,
        project_id: str,
        *,
        expected_revision: int,
        expected_asset_id: str,
        loadout_id: str = "default",
        metadata: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Accept exactly the candidate the user reviewed, never a newer one from another tab/job."""
        metadata = metadata or {}
        allowed = {"root", "ground_y", "neutral_bbox", "pose_keypoints", "mouth_roi", "eye_roi"}
        if set(metadata) - allowed:
            raise ValueError("unsupported anchor metadata")
        with self._lock:
            project = self.get_project(project_id)
            if project["revision"] != expected_revision:
                raise RuntimeError("project revision conflict")
            if loadout_id not in {item.get("id") for item in project.get("loadouts", [])}:
                raise ValueError("unknown loadout")
            anchor = self.anchor_for(project, loadout_id)
            if anchor.get("asset_id") != expected_asset_id:
                raise RuntimeError("anchor candidate changed; review the new image before accepting it")
            if anchor.get("status") not in {"review", "ready"}:
                raise ValueError("project has no reviewable anchor candidate")
            anchor.update(metadata)
            anchor["status"] = "ready"
            project["active_loadout_id"] = loadout_id
            self._sync_anchor_alias(project)
            self._sync_voice_alias(project)
            project["revision"] += 1
            project["updated_at"] = _utc_now()
            project["status"] = self._derive_status(project)
            project["last_plan"] = None
            self._write_manifest(project)
            return deepcopy(project)

    def save_plan(
        self,
        project_id: str,
        plan: dict[str, Any],
        *,
        expected_revision: int,
    ) -> dict[str, Any]:
        """Persist an observational plan without making its own revision stale."""
        with self._lock:
            project = self.get_project(project_id)
            if project["revision"] != expected_revision:
                raise RuntimeError("project changed while the plan was being built")
            project["last_plan"] = deepcopy(plan)
            project["updated_at"] = _utc_now()
            self._write_manifest(project)
            return deepcopy(project)

    @staticmethod
    def generation_signature(project: dict[str, Any], kind: str, params: dict[str, Any] | None = None) -> str:
        params = params or {}
        if kind == "component_build":
            loadout_id = str(params.get("loadout_id", "default"))
            loadout = next(
                (item for item in project.get("loadouts", []) if item.get("id") == loadout_id),
                {"id": loadout_id, "prop_ids": []},
            )
            selected_prop_ids = set(loadout.get("prop_ids", []))
            dependencies = {
                "kind": kind,
                "schema_version": project.get("schema_version"),
                "references": project.get("references", {}),
                "settings": project.get("settings", {}),
                "loadout": loadout,
                "props": sorted(
                    (item for item in project.get("props", []) if item.get("id") in selected_prop_ids),
                    key=lambda item: str(item.get("id", "")),
                ),
                "actions": list(params.get("actions", [])),
                "motion_ids": list(params.get("motion_ids", [])),
            }
        elif kind == "canonicalize":
            default_loadout = next(
                (item for item in project.get("loadouts", []) if item.get("id") == params.get("loadout_id", "default")),
                {"id": params.get("loadout_id", "default"), "prop_ids": []},
            )
            selected_prop_ids = set(default_loadout.get("prop_ids", []))
            selected_props = sorted(
                [
                    item
                    for item in project.get("props", [])
                    if item.get("id") in selected_prop_ids
                ],
                key=lambda item: str(item.get("id", "")),
            )
            dependencies = {
                "kind": kind,
                "schema_version": project.get("schema_version"),
                "references": project.get("references", {}),
                "quality_profile": project.get("settings", {}).get("quality_profile"),
                "facing": project.get("settings", {}).get("facing"),
                "background": project.get("settings", {}).get("background"),
                "loadout_id": default_loadout.get("id"),
                # Canonical anchors are loadout variants. Every selected
                # instance, including a non-persistent/dynamic one and its full
                # rigid geometry, is therefore part of the input identity.
                "props": selected_props,
            }
        elif kind == "motion":
            loadout_id = str(params.get("loadout_id", "default"))
            anchor = StudioStore.anchor_for(project, loadout_id)
            loadout = next(
                (item for item in project.get("loadouts", []) if item.get("id") == loadout_id),
                {"id": loadout_id, "prop_ids": []},
            )
            selected_prop_ids = set(loadout.get("prop_ids", []))
            selected_props = sorted(
                (item for item in project.get("props", []) if item.get("id") in selected_prop_ids),
                key=lambda item: str(item.get("id", "")),
            )
            dependencies = {
                "kind": kind,
                "motion_id": params.get("motion_id"),
                "anchor": {
                    key: anchor.get(key)
                    for key in ("revision", "status", "asset_id", "canvas", "root", "ground_y", "neutral_bbox", "pose_keypoints", "mouth_roi", "eye_roi")
                },
                "quality_profile": project.get("settings", {}).get("quality_profile"),
                "loadout_id": loadout_id,
                "props": selected_props,
                "loadout": loadout,
            }
        elif kind == "viseme_atlas":
            loadout_id = str(params.get("loadout_id", "default"))
            anchor = StudioStore.anchor_for(project, loadout_id)
            dependencies = {
                "kind": kind,
                "schema_version": project.get("schema_version"),
                "loadout_id": loadout_id,
                "quality_profile": project.get("settings", {}).get("quality_profile"),
                "anchor": {
                    key: anchor.get(key)
                    for key in ("revision", "status", "asset_id", "canvas", "mouth_roi")
                },
            }
        elif kind == "runtime_export":
            loadout_id = str(params.get("loadout_id", "default"))
            motion_id = str(params.get("motion_id", ""))
            clip = project.get("clips", {}).get(_clip_key(loadout_id, motion_id), {})
            anchor = StudioStore.anchor_for(project, loadout_id)
            dependencies = {
                "kind": kind,
                "loadout_id": loadout_id,
                "motion_id": motion_id,
                "anchor": {
                    key: anchor.get(key)
                    for key in ("revision", "status", "asset_id", "canvas")
                },
                "clip": {
                    # W12 itself advances qc_pass -> runtime_review -> ready.
                    # Normalize those lifecycle states so the source signature
                    # remains verifiable at acceptance, while stale/failed
                    # states still invalidate it.
                    "source_status": (
                        "qc_pass"
                        if clip.get("status") in {"qc_pass", "runtime_review", "ready"}
                        else clip.get("status")
                    ),
                    **{
                        key: clip.get(key)
                        for key in (
                            "master_spritesheet_asset_id",
                            "master_frame_count",
                            "runtime_frame_count",
                            "qc_report_asset_id",
                            "input_signature",
                            "anchor_asset_id",
                            "anchor_revision",
                        )
                    },
                    "qc_status": (clip.get("qc") or {}).get("status"),
                },
            }
        elif kind == "temporal_repair":
            loadout_id = str(params.get("loadout_id", "default"))
            motion_id = str(params.get("motion_id", ""))
            clip = project.get("clips", {}).get(_clip_key(loadout_id, motion_id), {})
            anchor = StudioStore.anchor_for(project, loadout_id)
            dependencies = {
                "kind": kind,
                "loadout_id": loadout_id,
                "motion_id": motion_id,
                "anchor": {
                    key: anchor.get(key)
                    for key in ("revision", "status", "asset_id", "canvas")
                },
                "clip": {
                    key: clip.get(key)
                    for key in (
                        "status",
                        "master_spritesheet_asset_id",
                        "qc_report_asset_id",
                        "master_frame_count",
                        "input_signature",
                    )
                },
            }
        else:
            raise ValueError("unsupported generation signature kind")
        encoded = json.dumps(dependencies, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
        return hashlib.sha256(encoded).hexdigest()

    def _validate_props(self, props: Any, assets: dict[str, Any]) -> list[dict[str, Any]]:
        if not isinstance(props, list) or len(props) > 64:
            raise ValueError("props must be a list with at most 64 items")
        slot_ids = {item["id"] for item in PROP_SLOTS}
        grip_ids = {item["id"] for item in GRIP_TYPES}
        seen: set[str] = set()
        validated: list[dict[str, Any]] = []
        for raw in props:
            if not isinstance(raw, dict):
                raise ValueError("each prop must be an object")
            prop_id = str(raw.get("id", ""))
            if not PROP_ID_RE.fullmatch(prop_id) or prop_id in seen:
                raise ValueError(f"invalid or duplicate prop id: {prop_id}")
            seen.add(prop_id)
            name = " ".join(str(raw.get("name", "")).strip().split())
            if not name or len(name) > 100:
                raise ValueError(f"invalid prop name: {prop_id}")
            slot = str(raw.get("slot", "free"))
            grip = str(raw.get("grip", "none"))
            if slot not in slot_ids or grip not in grip_ids:
                raise ValueError(f"invalid prop slot or grip: {prop_id}")
            expected_grip = {
                "left_hand": "one_handed",
                "right_hand": "one_handed",
                "both_hands": "two_handed",
                "back": "none",
                "attached": "none",
                "free": "none",
                "fx": "none",
            }[slot]
            if grip != expected_grip:
                raise ValueError(f"slot {slot} requires grip {expected_grip}: {prop_id}")
            asset_id = raw.get("reference_asset_id") or None
            if asset_id is not None and asset_id not in assets:
                raise ValueError(f"unknown prop asset: {asset_id}")
            if asset_id is not None and assets[asset_id].get("kind") != "image":
                raise ValueError(f"prop reference must be an image: {prop_id}")
            validated_prop = {
                "id": prop_id,
                "name": name,
                "slot": slot,
                "grip": grip,
                "persistent": bool(raw.get("persistent", False)),
                "reference_asset_id": asset_id,
                "prompt_hint": str(raw.get("prompt_hint", "")).strip()[:500],
                "mirror_safe": bool(raw.get("mirror_safe", False)),
            }
            if "rigid" in raw:
                validated_prop["rigid"] = _validate_rigid_prop(
                    raw["rigid"],
                    prop_id=prop_id,
                    slot=slot,
                )
            validated.append(validated_prop)
        return validated

    def _validate_loadouts(self, loadouts: Any, props: list[dict[str, Any]]) -> list[dict[str, Any]]:
        if not isinstance(loadouts, list) or not loadouts or len(loadouts) > 32:
            raise ValueError("loadouts must contain 1 to 32 items")
        prop_ids = {item["id"] for item in props}
        result: list[dict[str, Any]] = []
        seen: set[str] = set()
        for raw in loadouts:
            if not isinstance(raw, dict):
                raise ValueError("each loadout must be an object")
            loadout_id = str(raw.get("id", ""))
            if not PROP_ID_RE.fullmatch(loadout_id) or loadout_id in seen:
                raise ValueError(f"invalid or duplicate loadout id: {loadout_id}")
            seen.add(loadout_id)
            raw_selected = raw.get("prop_ids", [])
            if not isinstance(raw_selected, list) or any(not isinstance(item, str) for item in raw_selected):
                raise ValueError(f"prop_ids must be a list of ids: {loadout_id}")
            selected = list(dict.fromkeys(raw_selected))
            if any(item not in prop_ids for item in selected):
                raise ValueError(f"unknown prop in loadout: {loadout_id}")
            result.append(
                {
                    "id": loadout_id,
                    "name": str(raw.get("name", loadout_id)).strip()[:100] or loadout_id,
                    "prop_ids": selected,
                }
            )
        return result

    @staticmethod
    def _mark_clips_stale(project: dict[str, Any], reason: str, *, loadout_id: str | None = None) -> None:
        for clip in project.get("clips", {}).values():
            clip_loadout = str(clip.get("loadout_id", "default"))
            if loadout_id is not None and clip_loadout != loadout_id:
                continue
            clip["status"] = "stale"
            clip["stale_reason"] = reason
            clip["runtime_ready"] = False
            # W12 candidates are bound to the exact source master, anchor and
            # QC report.  Invalidation must also revoke candidates left open
            # in another browser tab.
            clip["runtime_candidate_asset_id"] = None
            clip["runtime_export_signature"] = None
            clip["alpha_status"] = "stale"
            clip["background_status"] = "stale"
            clip["updated_at"] = _utc_now()
        project["last_plan"] = None

    @classmethod
    def _mark_viseme_atlas_stale(cls, project: dict[str, Any], loadout_id: str, reason: str) -> None:
        voice = project.setdefault("voice", {})
        atlases = voice.setdefault("atlases", {})
        record = atlases.get(loadout_id)
        if isinstance(record, dict) and record.get("atlas_asset_id"):
            record["status"] = "stale"
            record["stale_reason"] = reason
        timeline = voice.get("timeline")
        timeline_loadout = timeline.get("atlas", {}).get("loadout_id") if isinstance(timeline, dict) else None
        if timeline_loadout in {None, loadout_id} and voice.get("timeline_asset_id"):
            voice["timeline_status"] = "stale"

    @classmethod
    def _mark_anchor_stale(cls, project: dict[str, Any], loadout_id: str, reason: str) -> None:
        anchor = cls.anchor_for(project, loadout_id)
        if anchor.get("asset_id"):
            anchor["status"] = "stale"
        cls._mark_clips_stale(project, reason, loadout_id=loadout_id)
        cls._mark_viseme_atlas_stale(project, loadout_id, reason)
        cls._sync_anchor_alias(project)
        cls._sync_voice_alias(project)

    def add_asset(
        self,
        project_id: str,
        *,
        filename: str,
        content_type: str,
        data: bytes,
        role: str,
        prop_id: str | None = None,
        motion_id: str | None = None,
        generated: bool = False,
        expected_generation_signature: str | None = None,
        generation_kind: str | None = None,
        generation_params: dict[str, Any] | None = None,
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        extension = Path(filename).suffix.lower()
        if role in IMAGE_ROLES:
            if extension not in ALLOWED_IMAGE_EXTENSIONS or len(data) > MAX_IMAGE_BYTES:
                raise ValueError("unsupported image type or image is larger than 25 MB")
            kind = "image"
        elif role in AUDIO_ROLES:
            if extension not in ALLOWED_AUDIO_EXTENSIONS or len(data) > MAX_AUDIO_BYTES:
                raise ValueError("unsupported audio type or audio is larger than 100 MB")
            kind = "audio"
        elif role in VIDEO_ROLES:
            if extension not in ALLOWED_VIDEO_EXTENSIONS or len(data) > MAX_VIDEO_BYTES:
                raise ValueError("unsupported video type or video is larger than 500 MB")
            kind = "video"
        else:
            raise ValueError("unsupported asset role")
        if not data:
            raise ValueError("empty upload")
        if role == "prop" and not prop_id:
            raise ValueError("prop_id is required for a prop reference")
        if role == "clip":
            if not motion_id or not PROP_ID_RE.fullmatch(motion_id):
                raise ValueError("a valid motion_id is required for a generated clip")
            if not generated or generation_kind != "motion" or not expected_generation_signature:
                raise ValueError("generated clips require their motion input signature")
            if (generation_params or {}).get("motion_id") != motion_id:
                raise ValueError("motion_id does not match generation_params")

        with self._lock:
            project = self.get_project(project_id)
            canonical_before = None
            if role in {"primary", "secondary", "detail", "prop"}:
                canonical_before = {
                    item["id"]: self.generation_signature(
                        project,
                        "canonicalize",
                        {"loadout_id": item["id"]},
                    )
                    for item in project.get("loadouts", [])
                }
            if expected_generation_signature is not None:
                if not generation_kind:
                    raise ValueError("generation kind is required with an expected signature")
                current_signature = self.generation_signature(project, generation_kind, generation_params)
                if current_signature != expected_generation_signature:
                    raise RuntimeError("project generation inputs changed while the job was running; output was not attached")
            asset_id = f"asset_{uuid.uuid4().hex[:16]}"
            stored_name = f"{asset_id}{extension}"
            asset_path = self._project_dir(project_id) / "assets" / stored_name
            asset_path.write_bytes(data)
            asset = {
                "id": asset_id,
                "kind": kind,
                "role": role,
                "original_name": Path(filename).name[:180],
                "stored_name": stored_name,
                # Never echo a multipart-provided MIME type for same-origin media.
                "content_type": CONTENT_TYPES.get(extension, "application/octet-stream"),
                "size_bytes": len(data),
                "created_at": _utc_now(),
                "generated": generated,
                "url": f"/studio-media/{project_id}/{asset_id}",
            }
            project["assets"][asset_id] = asset
            if role in {"primary", "secondary", "detail"}:
                project["references"][role] = asset_id
            elif role == "audio":
                project["voice"]["audio_asset_id"] = asset_id
                if project["voice"].get("timeline_asset_id"):
                    project["voice"]["timeline_status"] = "stale"
            elif role == "anchor":
                loadout_id = str((generation_params or {}).get("loadout_id", project.get("active_loadout_id", "default")))
                if loadout_id not in {item.get("id") for item in project.get("loadouts", [])}:
                    asset_path.unlink(missing_ok=True)
                    raise ValueError("unknown anchor loadout")
                profile_id = project.get("settings", {}).get("quality_profile", "local_12gb")
                profile = next((item for item in QUALITY_PROFILES if item["id"] == profile_id), QUALITY_PROFILES[0])
                self._mark_clips_stale(project, "anchor candidate changed", loadout_id=loadout_id)
                self._mark_viseme_atlas_stale(project, loadout_id, "anchor candidate changed")
                target_anchor = self.anchor_for(project, loadout_id)
                target_anchor.update(
                    {
                        "revision": int(target_anchor.get("revision", 0)) + 1,
                        "status": "review",
                        "asset_id": asset_id,
                        "canvas": {"width": profile["width"], "height": profile["height"]},
                    }
                )
                project["active_loadout_id"] = loadout_id
                self._sync_anchor_alias(project)
                self._sync_voice_alias(project)
            elif role == "clip":
                loadout_id = str((generation_params or {}).get("loadout_id", "default"))
                anchor = self.anchor_for(project, loadout_id)
                project["clips"][_clip_key(loadout_id, str(motion_id))] = {
                    "id": motion_id,
                    "loadout_id": loadout_id,
                    "channel": (get_motion(str(motion_id)) or {}).get("channel", "whole_body"),
                    "layer": "face" if (get_motion(str(motion_id)) or {}).get("generation_mode") == "face_layer" else "body",
                    "status": "qc_review",
                    "source_video_asset_id": asset_id,
                    "master_asset_id": None,
                    "qc": None,
                    "anchor_revision": anchor.get("revision"),
                    "anchor_asset_id": anchor.get("asset_id"),
                    "input_signature": expected_generation_signature,
                    "runtime_ready": False,
                    "alpha_status": "pending",
                    "background_status": "pending",
                    "updated_at": _utc_now(),
                }
            elif role == "prop" and prop_id:
                found = False
                for prop in project["props"]:
                    if prop["id"] == prop_id:
                        prop["reference_asset_id"] = asset_id
                        found = True
                        break
                if not found:
                    asset_path.unlink(missing_ok=True)
                    raise ValueError("unknown prop id")

            if canonical_before is not None:
                changed_loadouts: list[str] = []
                for loadout in project.get("loadouts", []):
                    loadout_id = loadout["id"]
                    canonical_after = self.generation_signature(
                        project,
                        "canonicalize",
                        {"loadout_id": loadout_id},
                    )
                    if canonical_before.get(loadout_id) != canonical_after:
                        changed_loadouts.append(loadout_id)
                for loadout_id in changed_loadouts:
                    self._mark_anchor_stale(project, loadout_id, "canonical reference asset changed")
                if role == "prop" and not changed_loadouts:
                    for loadout in project.get("loadouts", []):
                        if prop_id in loadout.get("prop_ids", []):
                            self._mark_clips_stale(
                                project,
                                "motion prop reference changed",
                                loadout_id=loadout["id"],
                            )
                project["last_plan"] = None

            project["revision"] += 1
            project["updated_at"] = _utc_now()
            project["status"] = self._derive_status(project)
            self._write_manifest(project)
            return deepcopy(project), deepcopy(asset)

    def save_component_overlay(
        self,
        project_id: str,
        *,
        action_id: str,
        filename: str,
        data: bytes,
        roi: dict[str, int],
        loadout_id: str = "default",
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        """Attach a local RGBA expression patch bound to the accepted anchor."""
        project, asset = self.add_asset(
            project_id,
            filename=filename,
            content_type="image/png",
            data=data,
            role="component_overlay",
            generated=True,
        )
        with self._lock:
            project = self.get_project(project_id)
            anchor = self.anchor_for(project, loadout_id)
            project.setdefault("component", {}).setdefault("overlays", {})[action_id] = {
                "status": "ready",
                "asset_id": asset["id"],
                "roi": {key: int(roi[key]) for key in ("x", "y", "width", "height")},
                "anchor_asset_id": anchor.get("asset_id"),
                "anchor_revision": anchor.get("revision"),
                "updated_at": _utc_now(),
            }
            project["revision"] += 1
            project["updated_at"] = _utc_now()
            self._write_manifest(project)
            return deepcopy(project), deepcopy(asset)

    def save_component_animation(
        self,
        project_id: str,
        *,
        action_id: str,
        filename: str,
        data: bytes,
        frame_count: int,
        fps: int,
        w1_filename: str | None = None,
        w1_data: bytes | None = None,
        w2_filename: str | None = None,
        w2_data: bytes | None = None,
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        """Attach a spritesheet produced by the original W1/W2/W3 pipeline."""
        w1_asset = None
        w2_asset = None
        if w1_filename and w1_data:
            _, w1_asset = self.add_asset(
                project_id,
                filename=w1_filename,
                content_type="image/png",
                data=w1_data,
                role="component_stage_image",
                generated=True,
            )
        if w2_filename and w2_data:
            _, w2_asset = self.add_asset(
                project_id,
                filename=w2_filename,
                content_type="video/mp4",
                data=w2_data,
                role="component_stage_video",
                generated=True,
            )
        project, asset = self.add_asset(
            project_id,
            filename=filename,
            content_type="image/png",
            data=data,
            role="component_animation",
            generated=True,
        )
        with self._lock:
            project = self.get_project(project_id)
            previous = project.setdefault("component", {}).setdefault("actions", {}).get(action_id, {})
            previous_stages = previous.get("stages", {}) if isinstance(previous, dict) else {}
            project.setdefault("component", {}).setdefault("actions", {})[action_id] = {
                "status": "ready",
                "pipeline": "W1/W2/W3",
                "asset_id": asset["id"],
                "frame_count": int(frame_count),
                "fps": int(fps),
                "cell_size": 512,
                "stages": {
                    "w1_asset_id": w1_asset["id"] if w1_asset else previous_stages.get("w1_asset_id"),
                    "w2_asset_id": w2_asset["id"] if w2_asset else previous_stages.get("w2_asset_id"),
                    "w3_asset_id": asset["id"],
                },
                "prompts": deepcopy(previous.get("prompts", {})) if isinstance(previous, dict) else {},
                "updated_at": _utc_now(),
            }
            project["revision"] += 1
            project["updated_at"] = _utc_now()
            self._write_manifest(project)
            return deepcopy(project), deepcopy(asset)

    def set_component_actions(self, project_id: str, action_ids: list[str]) -> dict[str, Any]:
        """Persist the canonical, de-duplicated action selection for a component."""

        selected = list(dict.fromkeys(
            str(action_id).strip() for action_id in action_ids if str(action_id).strip()
        ))
        if not selected:
            raise ValueError("component must contain at least one action")
        with self._lock:
            project = self.get_project(project_id)
            project.setdefault("component", {})["requested_actions"] = selected
            project["revision"] += 1
            project["updated_at"] = _utc_now()
            self._write_manifest(project)
            return deepcopy(project)

    def remove_component_action(self, project_id: str, action_id: str) -> dict[str, Any]:
        """Remove one component action and only the generated assets owned by it."""

        clean_action = str(action_id).strip()
        if not clean_action:
            raise ValueError("component action is required")
        with self._lock:
            project = self.get_project(project_id)
            component = project.setdefault("component", {})
            records = component.setdefault("actions", {})
            requested = component.get("requested_actions")
            selected = list(dict.fromkeys(
                str(item) for item in (requested if isinstance(requested, list) else records.keys())
            ))
            if clean_action not in selected and clean_action not in records:
                raise FileNotFoundError(clean_action)
            remaining = [item for item in selected if item != clean_action]
            if not remaining:
                raise ValueError("cannot remove the last component action")

            record = records.pop(clean_action, {})
            overlays = component.setdefault("overlays", {})
            overlay = overlays.pop(clean_action, {})
            owned_asset_ids = {
                str(asset_id)
                for asset_id in [
                    record.get("asset_id") if isinstance(record, dict) else None,
                    *((record.get("stages") or {}).values() if isinstance(record, dict) else []),
                    overlay.get("asset_id") if isinstance(overlay, dict) else None,
                ]
                if asset_id
            }
            component["requested_actions"] = remaining
            assets = project.setdefault("assets", {})
            assets_dir = (self._project_dir(project_id) / "assets").resolve()
            referenced_asset_ids: set[str] = set()
            for remaining_record in records.values():
                if not isinstance(remaining_record, dict):
                    continue
                referenced_asset_ids.update(
                    str(value) for value in [
                        remaining_record.get("asset_id"),
                        *((remaining_record.get("stages") or {}).values()),
                    ] if value
                )
            for remaining_overlay in overlays.values():
                if isinstance(remaining_overlay, dict) and remaining_overlay.get("asset_id"):
                    referenced_asset_ids.add(str(remaining_overlay["asset_id"]))

            asset_paths: list[Path] = []
            for asset_id in owned_asset_ids - referenced_asset_ids:
                asset = assets.pop(asset_id, None)
                if not isinstance(asset, dict):
                    continue
                asset_path = (assets_dir / str(asset.get("stored_name", ""))).resolve()
                try:
                    asset_path.relative_to(assets_dir)
                except ValueError as exc:
                    raise ValueError("component asset path escapes project assets") from exc
                asset_paths.append(asset_path)

            project["revision"] += 1
            project["updated_at"] = _utc_now()
            self._write_manifest(project)
            for asset_path in asset_paths:
                asset_path.unlink(missing_ok=True)
            return deepcopy(project)

    def save_component_stage(
        self,
        project_id: str,
        *,
        action_id: str,
        stage: str,
        filename: str,
        data: bytes,
        positive_prompt: str | None = None,
        negative_prompt: str | None = None,
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        """Publish W1 or W2 immediately while the rest of the chain continues."""
        if stage not in {"w1", "w2"}:
            raise ValueError("component stage must be w1 or w2")
        role = "component_stage_image" if stage == "w1" else "component_stage_video"
        content_type = "image/png" if stage == "w1" else "video/mp4"
        project, asset = self.add_asset(
            project_id,
            filename=filename,
            content_type=content_type,
            data=data,
            role=role,
            generated=True,
        )
        with self._lock:
            project = self.get_project(project_id)
            record = project.setdefault("component", {}).setdefault("actions", {}).setdefault(action_id, {})
            stages = record.setdefault("stages", {})
            # A partial rerender must not unpublish the last valid W3. Keep the
            # action runtime-ready until the replacement chain is complete.
            status = "ready" if stages.get("w3_asset_id") else "rendering"
            record.update({"status": status, "rerender_status": "rendering", "pipeline": "W1/W2/W3", "updated_at": _utc_now()})
            stages[f"{stage}_asset_id"] = asset["id"]
            if positive_prompt is not None or negative_prompt is not None:
                record.setdefault("prompts", {})[stage] = {
                    "positive": str(positive_prompt or ""),
                    "negative": str(negative_prompt or ""),
                }
            project["revision"] += 1
            project["updated_at"] = _utc_now()
            self._write_manifest(project)
            return deepcopy(project), deepcopy(asset)

    def save_component_prompts(
        self,
        project_id: str,
        *,
        action_id: str,
        stage: str,
        positive_prompt: str,
        negative_prompt: str,
    ) -> dict[str, Any]:
        if stage not in {"w1", "w2"}:
            raise ValueError("component prompts belong to w1 or w2")
        with self._lock:
            project = self.get_project(project_id)
            record = project.setdefault("component", {}).setdefault("actions", {}).setdefault(action_id, {})
            record.setdefault("prompts", {})[stage] = {
                "positive": str(positive_prompt),
                "negative": str(negative_prompt),
            }
            project["revision"] += 1
            project["updated_at"] = _utc_now()
            self._write_manifest(project)
            return deepcopy(project)

    def restore_component_action(
        self,
        project_id: str,
        *,
        action_id: str,
        record: dict[str, Any],
    ) -> dict[str, Any]:
        """Restore the last published action after a failed partial rerender."""
        with self._lock:
            project = self.get_project(project_id)
            project.setdefault("component", {}).setdefault("actions", {})[action_id] = deepcopy(record)
            project["revision"] += 1
            project["updated_at"] = _utc_now()
            self._write_manifest(project)
            return deepcopy(project)

    def save_component_w3_edit(
        self,
        project_id: str,
        *,
        action_id: str,
        data: bytes,
        frame_count: int | None = None,
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        """Replace only the published W3 sheet and preserve the rest of the action."""
        project = self.get_project(project_id)
        record = (project.get("component") or {}).get("actions", {}).get(action_id)
        if not isinstance(record, dict) or not (record.get("stages") or {}).get("w3_asset_id"):
            raise ValueError("W3 is not available for this action")
        project, asset = self.add_asset(
            project_id,
            filename=f"{action_id}_w3_edited.png",
            content_type="image/png",
            data=data,
            role="component_animation",
            generated=True,
        )
        with self._lock:
            project = self.get_project(project_id)
            record = project["component"]["actions"][action_id]
            record["asset_id"] = asset["id"]
            record.setdefault("stages", {})["w3_asset_id"] = asset["id"]
            if frame_count is not None:
                record["frame_count"] = frame_count
            record["status"] = "ready"
            record["updated_at"] = _utc_now()
            project["revision"] += 1
            project["updated_at"] = _utc_now()
            self._write_manifest(project)
            return deepcopy(project), deepcopy(asset)

    def finalize_clip(
        self,
        project_id: str,
        *,
        motion_id: str,
        source_video_filename: str,
        source_video_data: bytes,
        master_spritesheet_filename: str,
        master_spritesheet_data: bytes,
        runtime_spritesheet_filename: str,
        runtime_spritesheet_data: bytes,
        qc_report: dict[str, Any],
        expected_generation_signature: str,
        generation_params: dict[str, Any],
    ) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
        """Atomically attach one reviewed motion result to its exact generation inputs.

        The lossy generated video is retained explicitly as source material,
        never as the QC master. The lossless master sheet contains every
        decoded frame after exact endpoint replacement; the runtime candidate
        sheet omits the duplicate final anchor. Alpha/background postprocessing
        is a later gate, so this method never marks a clip runtime-ready.
        """

        if not PROP_ID_RE.fullmatch(motion_id):
            raise ValueError("invalid motion_id")
        if not SIGNATURE_RE.fullmatch(str(expected_generation_signature)):
            raise ValueError("a valid motion input signature is required")
        if not isinstance(generation_params, dict) or generation_params.get("motion_id") != motion_id:
            raise ValueError("motion_id does not match generation_params")
        if Path(source_video_filename).suffix.lower() != ".mp4":
            raise ValueError("motion source video must be an MP4")
        if not source_video_data or len(source_video_data) > MAX_VIDEO_BYTES:
            raise ValueError("empty motion source or source is larger than 500 MB")
        for label, filename, data in (
            ("master", master_spritesheet_filename, master_spritesheet_data),
            ("runtime", runtime_spritesheet_filename, runtime_spritesheet_data),
        ):
            if Path(filename).suffix.lower() != ".png":
                raise ValueError(f"{label} spritesheet must be a PNG")
            if not data or len(data) > MAX_SPRITESHEET_BYTES:
                raise ValueError(f"empty {label} spritesheet or spritesheet is larger than 200 MB")
        if not isinstance(qc_report, dict) or qc_report.get("status") not in {"pass", "review", "fail"}:
            raise ValueError("invalid QC report status")
        try:
            report_data = (
                json.dumps(qc_report, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
            ).encode("utf-8")
        except (TypeError, ValueError) as exc:
            raise ValueError("QC report is not strict JSON") from exc
        if len(report_data) > MAX_QC_REPORT_BYTES:
            raise ValueError("QC report is larger than 5 MB")

        endpoint_report = qc_report.get("anchor_endpoints", {})
        if not (
            endpoint_report.get("first_to_anchor", {}).get("exact") is True
            and endpoint_report.get("last_to_anchor", {}).get("exact") is True
        ):
            raise ValueError("QC report does not prove exact anchor endpoints")
        frame_count = qc_report.get("frame_count")
        if not isinstance(frame_count, int) or isinstance(frame_count, bool) or frame_count < 2:
            raise ValueError("QC report has an invalid master frame count")

        with self._lock:
            project = self.get_project(project_id)
            current_signature = self.generation_signature(project, "motion", generation_params)
            if current_signature != expected_generation_signature:
                raise RuntimeError("project generation inputs changed while QC was running; clip was not attached")
            loadout_id = str(generation_params.get("loadout_id", "default"))
            anchor = self.anchor_for(project, loadout_id)
            if anchor.get("status") != "ready" or not anchor.get("asset_id"):
                raise RuntimeError("the accepted anchor changed while QC was running")
            report_canvas = qc_report.get("canvas")
            if anchor.get("canvas") and report_canvas != anchor.get("canvas"):
                raise ValueError("QC canvas does not match the accepted anchor canvas")

            report_status = str(qc_report["status"])
            asset_specs = {
                "source_video": {
                    "filename": source_video_filename,
                    "data": source_video_data,
                    "kind": "video",
                    "role": "clip_source_video",
                    "content_type": "video/mp4",
                },
                "master_spritesheet": {
                    "filename": master_spritesheet_filename,
                    "data": master_spritesheet_data,
                    "kind": "image",
                    "role": "clip_master_spritesheet",
                    "content_type": "image/png",
                },
                "runtime_spritesheet": {
                    "filename": runtime_spritesheet_filename,
                    "data": runtime_spritesheet_data,
                    "kind": "image",
                    "role": "clip_runtime_spritesheet",
                    "content_type": "image/png",
                },
                "report": {
                    "filename": f"{motion_id}_qc.json",
                    "data": report_data,
                    "kind": "report",
                    "role": "clip_qc_report",
                    "content_type": "application/json",
                },
            }
            assets_dir = self._project_dir(project_id) / "assets"
            assets: dict[str, dict[str, Any]] = {}
            pending: list[tuple[Path, Path]] = []
            now = _utc_now()
            for key, spec in asset_specs.items():
                asset_id = f"asset_{uuid.uuid4().hex[:16]}"
                extension = Path(str(spec["filename"])).suffix.lower()
                stored_name = f"{asset_id}{extension}"
                final_path = assets_dir / stored_name
                temporary = assets_dir / f".{stored_name}.{uuid.uuid4().hex}.tmp"
                pending.append((temporary, final_path))
                assets[key] = {
                    "id": asset_id,
                    "kind": spec["kind"],
                    "role": spec["role"],
                    "original_name": Path(str(spec["filename"])).name[:180],
                    "stored_name": stored_name,
                    "content_type": spec["content_type"],
                    "size_bytes": len(spec["data"]),
                    "created_at": now,
                    "generated": True,
                    "url": f"/studio-media/{project_id}/{asset_id}",
                }

            written: list[Path] = []
            try:
                for (temporary, final_path), spec in zip(pending, asset_specs.values()):
                    temporary.write_bytes(spec["data"])
                    temporary.replace(final_path)
                    written.append(final_path)

                for asset in assets.values():
                    project["assets"][asset["id"]] = asset
                compact_issues = [
                    {
                        "id": str(item.get("id", "unknown"))[:100],
                        "status": str(item.get("status", "review"))[:20],
                        "message": str(item.get("message", ""))[:500],
                    }
                    for item in qc_report.get("issues", [])[:100]
                    if isinstance(item, dict)
                ]
                project["clips"][_clip_key(loadout_id, motion_id)] = {
                    "id": motion_id,
                    "loadout_id": loadout_id,
                    "channel": (get_motion(motion_id) or {}).get("channel", "whole_body"),
                    "layer": "face" if (get_motion(motion_id) or {}).get("generation_mode") == "face_layer" else "body",
                    "status": f"qc_{report_status}",
                    "source_video_asset_id": assets["source_video"]["id"],
                    "master_asset_id": assets["master_spritesheet"]["id"],
                    "master_spritesheet_asset_id": assets["master_spritesheet"]["id"],
                    "spritesheet_asset_id": assets["runtime_spritesheet"]["id"],
                    "runtime_spritesheet_asset_id": assets["runtime_spritesheet"]["id"],
                    "qc_report_asset_id": assets["report"]["id"],
                    "anchor_revision": anchor.get("revision"),
                    "anchor_asset_id": anchor.get("asset_id"),
                    "input_signature": expected_generation_signature,
                    "master_frame_count": frame_count,
                    "runtime_frame_count": frame_count - 1,
                    "neutral_corridor_frames": int(generation_params.get("neutral_corridor_frames", 0) or 0),
                    "entry_gate_frame": 0,
                    "exit_gate_frame": frame_count - 2,
                    "master_exit_anchor_frame": frame_count - 1,
                    "switch_policy": "neutral_gate",
                    "endpoint_replacement": {"first": True, "last": True},
                    "qc": {
                        "schema_version": qc_report.get("schema_version"),
                        "status": report_status,
                        "passed": qc_report.get("passed") is True,
                        "issue_count": len(qc_report.get("issues", [])),
                        "issues": compact_issues,
                        "report_asset_id": assets["report"]["id"],
                    },
                    "runtime_ready": False,
                    "alpha_status": "pending",
                    "background_status": "pending",
                    "updated_at": now,
                }
                project["revision"] += 1
                project["updated_at"] = now
                project["status"] = self._derive_status(project)
                self._write_manifest(project)
            except Exception:
                for temporary, _ in pending:
                    temporary.unlink(missing_ok=True)
                for final_path in written:
                    final_path.unlink(missing_ok=True)
                raise
            return deepcopy(project), deepcopy(assets)

    def finalize_runtime_export(
        self,
        project_id: str,
        *,
        motion_id: str,
        loadout_id: str,
        filename: str,
        data: bytes,
        frame_count: int,
        diagnostics: dict[str, Any],
        expected_generation_signature: str,
        generation_params: dict[str, Any],
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        """Attach a validated W12 RGBA candidate without making it runtime-ready."""

        if not PROP_ID_RE.fullmatch(motion_id):
            raise ValueError("invalid motion_id")
        if not PROP_ID_RE.fullmatch(loadout_id):
            raise ValueError("invalid loadout_id")
        if Path(filename).suffix.lower() != ".png":
            raise ValueError("runtime export must be a PNG spritesheet")
        if not data or len(data) > MAX_SPRITESHEET_BYTES:
            raise ValueError("empty runtime export or spritesheet is larger than 200 MB")
        if not isinstance(frame_count, int) or isinstance(frame_count, bool) or frame_count < 1:
            raise ValueError("invalid runtime export frame count")
        if not SIGNATURE_RE.fullmatch(str(expected_generation_signature)):
            raise ValueError("a valid runtime export input signature is required")
        if not isinstance(generation_params, dict):
            raise ValueError("generation_params must be an object")
        if str(generation_params.get("motion_id", "")) != motion_id:
            raise ValueError("motion_id does not match generation_params")
        if str(generation_params.get("loadout_id", "default")) != loadout_id:
            raise ValueError("loadout_id does not match generation_params")
        try:
            safe_diagnostics = json.loads(json.dumps(diagnostics, allow_nan=False))
        except (TypeError, ValueError) as exc:
            raise ValueError("runtime export diagnostics are not strict JSON") from exc

        with self._lock:
            project = self.get_project(project_id)
            current_signature = self.generation_signature(project, "runtime_export", generation_params)
            if current_signature != expected_generation_signature:
                raise RuntimeError("clip changed while W12 was running; runtime export was not attached")
            clip_key = _clip_key(loadout_id, motion_id)
            clip = project.get("clips", {}).get(clip_key)
            if not isinstance(clip, dict):
                raise ValueError("selected loadout has no such clip")
            if clip.get("status") != "qc_pass" or clip.get("qc", {}).get("status") != "pass":
                raise ValueError("W12 requires a current clip that passed continuity QC")
            anchor = self.anchor_for(project, loadout_id)
            if (
                anchor.get("status") != "ready"
                or clip.get("anchor_asset_id") != anchor.get("asset_id")
                or clip.get("anchor_revision") != anchor.get("revision")
            ):
                raise RuntimeError("clip is not bound to the current accepted anchor")
            if int(clip.get("runtime_frame_count", 0) or 0) != frame_count:
                raise ValueError("W12 frame count does not match the runtime clip contract")
            canvas = anchor.get("canvas") if isinstance(anchor.get("canvas"), dict) else {}
            width, height = int(canvas.get("width", 0) or 0), int(canvas.get("height", 0) or 0)
            if width <= 0 or height <= 0:
                raise ValueError("accepted anchor has no valid W12 canvas contract")
            verified_alpha = _inspect_runtime_rgba_spritesheet(
                data,
                frame_count=frame_count,
                width=width,
                height=height,
            )
            safe_diagnostics["alpha_coverage"] = verified_alpha

            asset_id = f"asset_{uuid.uuid4().hex[:16]}"
            stored_name = f"{asset_id}.png"
            assets_dir = self._project_dir(project_id) / "assets"
            final_path = assets_dir / stored_name
            temporary = assets_dir / f".{stored_name}.{uuid.uuid4().hex}.tmp"
            now = _utc_now()
            asset = {
                "id": asset_id,
                "kind": "image",
                "role": "clip_runtime_rgba_candidate",
                "original_name": Path(filename).name[:180],
                "stored_name": stored_name,
                "content_type": "image/png",
                "size_bytes": len(data),
                "sha256": hashlib.sha256(data).hexdigest(),
                "created_at": now,
                "generated": True,
                "url": f"/studio-media/{project_id}/{asset_id}",
            }
            try:
                temporary.write_bytes(data)
                temporary.replace(final_path)
                project["assets"][asset_id] = asset
                clip.update(
                    {
                        "status": "runtime_review",
                        "runtime_ready": False,
                        "runtime_candidate_asset_id": asset_id,
                        "runtime_export_signature": expected_generation_signature,
                        "runtime_export": safe_diagnostics,
                        "alpha_status": "review",
                        "background_status": "review",
                        "updated_at": now,
                    }
                )
                project["revision"] += 1
                project["updated_at"] = now
                project["status"] = self._derive_status(project)
                self._write_manifest(project)
            except Exception:
                temporary.unlink(missing_ok=True)
                final_path.unlink(missing_ok=True)
                raise
            return deepcopy(project), deepcopy(asset)

    def accept_runtime_export(
        self,
        project_id: str,
        *,
        motion_id: str,
        loadout_id: str,
        expected_revision: int,
        expected_asset_id: str,
    ) -> dict[str, Any]:
        """Accept silhouette/prop review and publish the W12 asset to runtime."""

        with self._lock:
            project = self.get_project(project_id)
            if project.get("revision") != expected_revision:
                raise RuntimeError("project changed while the runtime export was being reviewed")
            clip = project.get("clips", {}).get(_clip_key(loadout_id, motion_id))
            if not isinstance(clip, dict):
                raise ValueError("selected loadout has no such clip")
            if clip.get("runtime_candidate_asset_id") != expected_asset_id:
                raise RuntimeError("runtime export candidate changed while it was being reviewed")
            asset = project.get("assets", {}).get(expected_asset_id)
            if not isinstance(asset, dict) or asset.get("role") != "clip_runtime_rgba_candidate":
                raise ValueError("runtime export candidate asset is invalid")
            if clip.get("status") != "runtime_review" or clip.get("qc", {}).get("status") != "pass":
                raise ValueError("only a current QC-passed W12 review candidate can be accepted")
            anchor = self.anchor_for(project, loadout_id)
            if (
                anchor.get("status") != "ready"
                or clip.get("anchor_asset_id") != anchor.get("asset_id")
                or clip.get("anchor_revision") != anchor.get("revision")
            ):
                raise RuntimeError("accepted anchor changed after W12; regenerate the runtime export")
            current_signature = self.generation_signature(
                project,
                "runtime_export",
                {"motion_id": motion_id, "loadout_id": loadout_id},
            )
            if current_signature != clip.get("runtime_export_signature"):
                raise RuntimeError("W12 source inputs changed after the candidate was generated")
            candidate_path = self._project_dir(project_id) / "assets" / str(asset.get("stored_name", ""))
            try:
                candidate_data = candidate_path.read_bytes()
            except OSError as exc:
                raise RuntimeError("W12 candidate file is missing during acceptance") from exc
            if hashlib.sha256(candidate_data).hexdigest() != asset.get("sha256"):
                raise RuntimeError("W12 candidate file changed after review was opened")
            canvas = anchor.get("canvas") if isinstance(anchor.get("canvas"), dict) else {}
            _inspect_runtime_rgba_spritesheet(
                candidate_data,
                frame_count=int(clip.get("runtime_frame_count", 0) or 0),
                width=int(canvas.get("width", 0) or 0),
                height=int(canvas.get("height", 0) or 0),
            )
            now = _utc_now()
            asset["role"] = "clip_runtime_spritesheet"
            clip.update(
                {
                    "status": "ready",
                    "runtime_ready": True,
                    "runtime_spritesheet_asset_id": expected_asset_id,
                    "spritesheet_asset_id": expected_asset_id,
                    "runtime_candidate_asset_id": None,
                    "alpha_status": "ready",
                    "background_status": "ready",
                    "runtime_accepted_at": now,
                    "updated_at": now,
                }
            )
            project["revision"] += 1
            project["updated_at"] = now
            project["status"] = self._derive_status(project)
            self._write_manifest(project)
            return deepcopy(project)

    def reject_runtime_export(
        self,
        project_id: str,
        *,
        motion_id: str,
        loadout_id: str,
        expected_revision: int,
        expected_asset_id: str,
    ) -> dict[str, Any]:
        """Reject exactly the reviewed W12 candidate and reopen regeneration."""

        with self._lock:
            project = self.get_project(project_id)
            if project.get("revision") != expected_revision:
                raise RuntimeError("project changed while the runtime export was being reviewed")
            clip = project.get("clips", {}).get(_clip_key(loadout_id, motion_id))
            if not isinstance(clip, dict):
                raise ValueError("selected loadout has no such clip")
            if clip.get("status") != "runtime_review" or clip.get("runtime_candidate_asset_id") != expected_asset_id:
                raise RuntimeError("runtime export candidate changed while it was being reviewed")
            asset = project.get("assets", {}).get(expected_asset_id)
            if not isinstance(asset, dict) or asset.get("role") != "clip_runtime_rgba_candidate":
                raise ValueError("runtime export candidate asset is invalid")
            now = _utc_now()
            asset["role"] = "clip_runtime_rgba_rejected"
            clip.update(
                {
                    "status": "qc_pass",
                    "runtime_ready": False,
                    "runtime_candidate_asset_id": None,
                    "runtime_export_signature": None,
                    "alpha_status": "rejected",
                    "background_status": "rejected",
                    "runtime_rejected_at": now,
                    "updated_at": now,
                }
            )
            project["revision"] += 1
            project["updated_at"] = now
            project["status"] = self._derive_status(project)
            self._write_manifest(project)
            return deepcopy(project)

    def finalize_viseme_atlas(
        self,
        project_id: str,
        *,
        loadout_id: str,
        tiles: dict[str, dict[str, Any]],
        atlas_filename: str,
        atlas_data: bytes,
        manifest: dict[str, Any],
        expected_generation_signature: str,
        generation_params: dict[str, Any],
    ) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
        """Atomically attach ten lossless tiles and one review-gated W9 atlas."""

        if set(tiles) != set(STUDIO_VISEMES):
            raise ValueError("viseme atlas must contain exactly the Studio viseme set")
        if Path(atlas_filename).suffix.lower() != ".png" or not atlas_data or len(atlas_data) > MAX_VISEME_ATLAS_BYTES:
            raise ValueError("viseme atlas must be a non-empty PNG smaller than 50 MB")
        if not SIGNATURE_RE.fullmatch(str(expected_generation_signature)):
            raise ValueError("a valid viseme-atlas input signature is required")
        if manifest.get("schema_version") != VISEME_ATLAS_SCHEMA:
            raise ValueError("unsupported viseme atlas manifest schema")
        cells = manifest.get("cells")
        if not isinstance(cells, list) or {item.get("viseme") for item in cells if isinstance(item, dict)} != set(STUDIO_VISEMES):
            raise ValueError("viseme atlas manifest has an invalid cell set")
        if str(manifest.get("loadout_id")) != loadout_id:
            raise ValueError("viseme atlas manifest loadout does not match the job")
        clean_tiles: dict[str, tuple[str, bytes]] = {}
        for viseme in STUDIO_VISEMES:
            spec = tiles.get(viseme)
            if not isinstance(spec, dict):
                raise ValueError(f"missing viseme tile: {viseme}")
            filename, data = str(spec.get("filename", "")), spec.get("data")
            if Path(filename).suffix.lower() != ".png" or not isinstance(data, bytes) or not data or len(data) > MAX_IMAGE_BYTES:
                raise ValueError(f"viseme tile {viseme} must be a non-empty PNG smaller than 25 MB")
            clean_tiles[viseme] = (filename, data)
        try:
            manifest_data = (json.dumps(manifest, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")
        except (TypeError, ValueError) as exc:
            raise ValueError("viseme atlas manifest is not strict JSON") from exc
        if len(manifest_data) > MAX_QC_REPORT_BYTES:
            raise ValueError("viseme atlas manifest is larger than 5 MB")

        with self._lock:
            project = self.get_project(project_id)
            if loadout_id not in {item.get("id") for item in project.get("loadouts", [])}:
                raise ValueError("unknown viseme atlas loadout")
            current_signature = self.generation_signature(project, "viseme_atlas", generation_params)
            if current_signature != expected_generation_signature:
                raise RuntimeError("viseme-atlas inputs changed while W9 was running; output was not attached")
            anchor = self.anchor_for(project, loadout_id)
            if anchor.get("status") != "ready" or anchor.get("asset_id") != manifest.get("anchor_asset_id"):
                raise RuntimeError("accepted anchor changed while W9 was running")
            if anchor.get("revision") != manifest.get("anchor_revision"):
                raise RuntimeError("anchor revision changed while W9 was running")

            specs: list[tuple[str, str, bytes, str, str]] = [
                (f"tile:{viseme}", filename, data, "image", "viseme_tile")
                for viseme, (filename, data) in clean_tiles.items()
            ]
            specs.extend(
                [
                    ("atlas", atlas_filename, atlas_data, "image", "viseme_atlas"),
                    ("manifest", f"{loadout_id}_viseme_atlas.json", manifest_data, "report", "viseme_atlas_manifest"),
                ]
            )
            assets_dir = self._project_dir(project_id) / "assets"
            pending: list[tuple[Path, Path, bytes]] = []
            assets: dict[str, dict[str, Any]] = {}
            now = _utc_now()
            for key, filename, data, kind, role in specs:
                asset_id = f"asset_{uuid.uuid4().hex[:16]}"
                extension = Path(filename).suffix.lower()
                stored_name = f"{asset_id}{extension}"
                final_path = assets_dir / stored_name
                temporary = assets_dir / f".{stored_name}.{uuid.uuid4().hex}.tmp"
                pending.append((temporary, final_path, data))
                assets[key] = {
                    "id": asset_id,
                    "kind": kind,
                    "role": role,
                    "original_name": Path(filename).name[:180],
                    "stored_name": stored_name,
                    "content_type": "image/png" if extension == ".png" else "application/json",
                    "size_bytes": len(data),
                    "created_at": now,
                    "generated": True,
                    "url": f"/studio-media/{project_id}/{asset_id}",
                }
            written: list[Path] = []
            try:
                for temporary, final_path, data in pending:
                    temporary.write_bytes(data)
                    temporary.replace(final_path)
                    written.append(final_path)
                for item in assets.values():
                    project["assets"][item["id"]] = item
                record = {
                    "status": "review",
                    "atlas_asset_id": assets["atlas"]["id"],
                    "manifest_asset_id": assets["manifest"]["id"],
                    "tile_asset_ids": {
                        viseme: assets[f"tile:{viseme}"]["id"] for viseme in STUDIO_VISEMES
                    },
                    "manifest": deepcopy(manifest),
                    "anchor_revision": anchor.get("revision"),
                    "anchor_asset_id": anchor.get("asset_id"),
                    "input_signature": expected_generation_signature,
                    "updated_at": now,
                }
                project["voice"].setdefault("atlases", {})[loadout_id] = record
                project["voice"]["timeline_status"] = "stale" if project["voice"].get("timeline_asset_id") else "missing"
                project["active_loadout_id"] = loadout_id
                self._sync_anchor_alias(project)
                self._sync_voice_alias(project)
                project["revision"] += 1
                project["updated_at"] = now
                self._write_manifest(project)
            except Exception:
                for temporary, _, _ in pending:
                    temporary.unlink(missing_ok=True)
                for path in written:
                    path.unlink(missing_ok=True)
                raise
            return deepcopy(project), deepcopy(assets)

    def accept_viseme_atlas(
        self,
        project_id: str,
        *,
        loadout_id: str,
        expected_revision: int,
        expected_asset_id: str,
    ) -> dict[str, Any]:
        with self._lock:
            project = self.get_project(project_id)
            if project["revision"] != expected_revision:
                raise RuntimeError("project revision conflict")
            record = self.viseme_atlas_for(project, loadout_id)
            if record.get("atlas_asset_id") != expected_asset_id:
                raise RuntimeError("viseme atlas candidate changed; review the new atlas first")
            if record.get("status") not in {"review", "ready"}:
                raise ValueError("project has no reviewable viseme atlas")
            anchor = self.anchor_for(project, loadout_id)
            if anchor.get("status") != "ready" or anchor.get("revision") != record.get("anchor_revision"):
                raise RuntimeError("the anchor changed after W9; regenerate the viseme atlas")
            current_signature = self.generation_signature(project, "viseme_atlas", {"loadout_id": loadout_id})
            if current_signature != record.get("input_signature"):
                raise RuntimeError("viseme atlas inputs changed after generation")
            record["status"] = "ready"
            record["accepted_at"] = _utc_now()
            project["active_loadout_id"] = loadout_id
            self._sync_anchor_alias(project)
            self._sync_voice_alias(project)
            project["revision"] += 1
            project["updated_at"] = _utc_now()
            self._write_manifest(project)
            return deepcopy(project)

    def save_voice_timeline(
        self,
        project_id: str,
        *,
        timeline: dict[str, Any],
        timing_source: str,
        expected_revision: int,
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        if timeline.get("schema_version") != VISEME_TIMELINE_SCHEMA or timeline.get("runtime_ready") is not True:
            raise ValueError("invalid runtime viseme timeline")
        try:
            data = (json.dumps(timeline, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")
        except (TypeError, ValueError) as exc:
            raise ValueError("viseme timeline is not strict JSON") from exc
        if not data or len(data) > MAX_QC_REPORT_BYTES:
            raise ValueError("viseme timeline is empty or larger than 5 MB")
        with self._lock:
            project = self.get_project(project_id)
            if project["revision"] != expected_revision:
                raise RuntimeError("project revision conflict")
            loadout_id = str(timeline.get("atlas", {}).get("loadout_id", project.get("active_loadout_id", "default")))
            atlas = self.viseme_atlas_for(project, loadout_id)
            if atlas.get("status") != "ready" or atlas.get("atlas_asset_id") is None:
                raise RuntimeError("accepted viseme atlas changed before timeline commit")
            timeline_atlas = timeline.get("atlas") if isinstance(timeline.get("atlas"), dict) else {}
            accepted_manifest = atlas.get("manifest") if isinstance(atlas.get("manifest"), dict) else {}
            if timeline_atlas.get("atlas_asset_id") != atlas.get("atlas_asset_id"):
                raise RuntimeError("timeline is not bound to the accepted viseme atlas asset")
            for key in (
                "schema_version",
                "loadout_id",
                "anchor_asset_id",
                "anchor_revision",
                "mouth_roi",
                "width",
                "height",
                "cells",
            ):
                if timeline_atlas.get(key) != accepted_manifest.get(key):
                    raise RuntimeError("timeline atlas contract changed before commit")
            timeline_audio = timeline.get("audio") if isinstance(timeline.get("audio"), dict) else {}
            if timeline_audio.get("asset_id") != project.get("voice", {}).get("audio_asset_id"):
                raise RuntimeError("timeline is not bound to the current audio asset")
            asset_id = f"asset_{uuid.uuid4().hex[:16]}"
            stored_name = f"{asset_id}.json"
            target = self._project_dir(project_id) / "assets" / stored_name
            temporary = target.with_name(f".{stored_name}.{uuid.uuid4().hex}.tmp")
            asset = {
                "id": asset_id,
                "kind": "report",
                "role": "voice_timeline",
                "original_name": "viseme_timeline.json",
                "stored_name": stored_name,
                "content_type": "application/json",
                "size_bytes": len(data),
                "created_at": _utc_now(),
                "generated": True,
                "url": f"/studio-media/{project_id}/{asset_id}",
            }
            try:
                temporary.write_bytes(data)
                temporary.replace(target)
                project["assets"][asset_id] = asset
                project["voice"].update(
                    {
                        "timeline_asset_id": asset_id,
                        "timeline": deepcopy(timeline),
                        "timeline_status": "ready",
                        "timing_source": str(timing_source)[:40],
                    }
                )
                project["revision"] += 1
                project["updated_at"] = _utc_now()
                self._write_manifest(project)
            except Exception:
                temporary.unlink(missing_ok=True)
                target.unlink(missing_ok=True)
                raise
            return deepcopy(project), deepcopy(asset)

    def get_asset(self, project_id: str, asset_id: str) -> tuple[Path, dict[str, Any]]:
        if not ASSET_ID_RE.fullmatch(asset_id):
            raise ValueError("invalid asset id")
        project = self.get_project(project_id)
        asset = project.get("assets", {}).get(asset_id)
        if asset is None:
            raise FileNotFoundError(asset_id)
        path = (self._project_dir(project_id) / "assets" / asset["stored_name"]).resolve()
        path.relative_to(self._project_dir(project_id) / "assets")
        if not path.is_file():
            raise FileNotFoundError(asset_id)
        return path, deepcopy(asset)

    @staticmethod
    def _derive_status(project: dict[str, Any]) -> str:
        if not project.get("references", {}).get("primary"):
            return "draft"
        if project.get("anchor", {}).get("status") != "ready":
            return "references_ready"
        clips = project.get("clips", {})
        if clips and all(item.get("status") == "ready" for item in clips.values()):
            return "library_ready"
        return "anchor_ready"
