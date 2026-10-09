"""Pure geometry and validation contract for hand-held rigid prop instances.

The module intentionally performs no filesystem, ComfyUI, store, or runner IO.
Callers render the declared masks and persist the JSON-safe sidecar themselves.
"""

from __future__ import annotations

import hashlib
import json
import math
import re
from collections.abc import Mapping, Sequence
from typing import Any


RIGID_PROPS_SCHEMA = "studio.rigid-props/v1"
RIGID_MASK_SIDECAR_SCHEMA = "studio.rigid-props-masks/v1"

__all__ = [
    "RIGID_MASK_SIDECAR_SCHEMA",
    "RIGID_PROPS_SCHEMA",
    "angular_delta_degrees",
    "build_instance_trajectory",
    "build_mask_sidecar_metadata",
    "build_one_hand_trajectory",
    "build_two_hand_staff_trajectory",
    "contact_qc",
    "interpolate_transform_trajectory",
    "loadout_anchor_key",
    "loadout_anchor_metadata",
    "make_transform",
    "normalize_project_props",
    "one_hand_transform",
    "preflight_rigid_loadout",
    "project_loadout_anchor_key",
    "rigid_loadout_signature",
    "solve_two_link_ik",
    "transform_axis",
    "transform_point",
]

_HAND_SLOTS = {"left_hand": "left", "right_hand": "right"}
_ID_SAFE_RE = re.compile(r"[^a-zA-Z0-9_.-]+")


def _point(value: Any, *, name: str) -> tuple[float, float]:
    if not isinstance(value, Sequence) or isinstance(value, (str, bytes)) or len(value) != 2:
        raise ValueError(f"{name} must be a two-number point")
    try:
        point = (float(value[0]), float(value[1]))
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{name} must be a two-number point") from exc
    if not all(math.isfinite(item) for item in point):
        raise ValueError(f"{name} must contain finite numbers")
    return point


def _positive(value: Any, *, name: str) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{name} must be a positive number") from exc
    if not math.isfinite(number) or number <= 0:
        raise ValueError(f"{name} must be a positive number")
    return number


def _finite(value: Any, *, name: str) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{name} must be a finite number") from exc
    if not math.isfinite(number):
        raise ValueError(f"{name} must be a finite number")
    return number


def _distance(first: Sequence[float], second: Sequence[float]) -> float:
    return math.hypot(float(second[0]) - float(first[0]), float(second[1]) - float(first[1]))


def _lerp_point(first: Sequence[float], second: Sequence[float], amount: float) -> tuple[float, float]:
    return (
        float(first[0]) + (float(second[0]) - float(first[0])) * amount,
        float(first[1]) + (float(second[1]) - float(first[1])) * amount,
    )


def _angle(first: Sequence[float], second: Sequence[float]) -> float:
    return math.degrees(math.atan2(float(second[1]) - float(first[1]), float(second[0]) - float(first[0])))


def angular_delta_degrees(first: float, second: float) -> float:
    """Return the signed shortest turn from ``first`` to ``second``."""

    return (float(second) - float(first) + 180.0) % 360.0 - 180.0


def _unwrap_angle(angle: float, previous: float | None) -> float:
    if previous is None:
        return angle
    return previous + angular_delta_degrees(previous, angle)


def _safe_id(value: str) -> str:
    cleaned = _ID_SAFE_RE.sub("_", value).strip("._")
    return cleaned or "item"


def _issue(
    code: str,
    message: str,
    *,
    target: str | None = None,
    severity: str = "error",
    frame: int | None = None,
    value: float | None = None,
) -> dict[str, Any]:
    result: dict[str, Any] = {"code": code, "message": message, "severity": severity}
    if target is not None:
        result["target"] = target
    if frame is not None:
        result["frame"] = frame
    if value is not None:
        result["value"] = value
    return result


def _raw_asset_definitions(project: Mapping[str, Any]) -> dict[str, Mapping[str, Any]]:
    raw_assets = project.get("prop_assets", {})
    if isinstance(raw_assets, Mapping):
        return {
            str(key): value
            for key, value in raw_assets.items()
            if isinstance(value, Mapping)
        }
    if isinstance(raw_assets, Sequence) and not isinstance(raw_assets, (str, bytes)):
        return {
            str(item.get("id")): item
            for item in raw_assets
            if isinstance(item, Mapping) and item.get("id")
        }
    return {}


def _rigid_config(*sources: Mapping[str, Any] | None) -> dict[str, Any]:
    merged: dict[str, Any] = {}
    for source in sources:
        if not isinstance(source, Mapping):
            continue
        merged.update(source)
        nested = source.get("rigid")
        if isinstance(nested, Mapping):
            merged.update(nested)
    return merged


def _asset_id_for_prop(prop: Mapping[str, Any]) -> str:
    explicit = prop.get("prop_asset_id") or prop.get("asset_id")
    if explicit:
        return str(explicit)
    reference = prop.get("reference_asset_id")
    if reference:
        # Two instances may intentionally share one uploaded asset.
        return f"reference:{reference}"
    return f"instance:{prop.get('id', 'prop')}"


def _normalise_axis(config: Mapping[str, Any]) -> tuple[tuple[float, float], tuple[float, float]]:
    raw = config.get("handle_axis_local", config.get("handle_axis_uv", config.get("handle_axis")))
    if raw is None:
        return ((0.0, -0.5), (0.0, 0.5))
    if not isinstance(raw, Sequence) or isinstance(raw, (str, bytes)) or len(raw) != 2:
        raise ValueError("handle_axis must contain two points")
    axis = (_point(raw[0], name="handle_axis[0]"), _point(raw[1], name="handle_axis[1]"))
    if _distance(*axis) <= 1e-9:
        raise ValueError("handle_axis endpoints must be distinct")
    return axis


def _attachment_from_raw(
    raw: Mapping[str, Any],
    *,
    hand: str,
    axis: tuple[tuple[float, float], tuple[float, float]],
    default_t: float,
) -> dict[str, Any]:
    grip_t = float(raw.get("handle_t", raw.get("grip_t", default_t)))
    if not math.isfinite(grip_t):
        raise ValueError(f"{hand} grip parameter must be finite")
    raw_point = raw.get("grip_point_local", raw.get("grip_point_uv"))
    grip = _point(raw_point, name=f"{hand} grip point") if raw_point is not None else _lerp_point(*axis, grip_t)
    return {
        "hand": hand,
        "handle_t": grip_t,
        "grip_point": [grip[0], grip[1]],
        "palm_landmark": str(raw.get("palm_landmark", "palm_center")),
    }


def _normalise_attachments(
    prop: Mapping[str, Any],
    config: Mapping[str, Any],
    axis: tuple[tuple[float, float], tuple[float, float]],
) -> list[dict[str, Any]]:
    slot = str(prop.get("slot", "free"))
    raw_attachments = config.get("attachments")
    attachments_by_hand: dict[str, Mapping[str, Any]] = {}
    if isinstance(raw_attachments, Sequence) and not isinstance(raw_attachments, (str, bytes)):
        for item in raw_attachments:
            if isinstance(item, Mapping) and str(item.get("hand")) in {"left", "right"}:
                attachments_by_hand[str(item["hand"])] = item

    if slot in _HAND_SLOTS:
        hand = _HAND_SLOTS[slot]
        raw = attachments_by_hand.get(hand, config)
        return [_attachment_from_raw(raw, hand=hand, axis=axis, default_t=0.75)]
    if slot == "both_hands":
        grip_points = config.get("grip_points")
        fallback: dict[str, Mapping[str, Any]] = {}
        if isinstance(grip_points, Mapping):
            for hand in ("left", "right"):
                if hand in grip_points:
                    value = grip_points[hand]
                    fallback[hand] = value if isinstance(value, Mapping) else {"grip_point_local": value}
        return [
            _attachment_from_raw(
                attachments_by_hand.get("left", fallback.get("left", {})),
                hand="left",
                axis=axis,
                default_t=0.35,
            ),
            _attachment_from_raw(
                attachments_by_hand.get("right", fallback.get("right", {})),
                hand="right",
                axis=axis,
                default_t=0.65,
            ),
        ]
    return []


def normalize_project_props(project: Mapping[str, Any], loadout_id: str = "default") -> dict[str, Any]:
    """Normalise the current flat ``project.props`` list into assets and instances.

    Existing projects treat every item in ``props`` as an instance.  Shared
    ``reference_asset_id``/``prop_asset_id`` values are deduplicated only in the
    asset table; instances are never deduplicated.  Consequently two axes using
    one reference remain two independently constrained instances.

    Geometry uses prop-local coordinates.  ``nominal_scale`` converts those
    coordinates into canvas pixels when building a transform.
    """

    raw_loadouts = project.get("loadouts", [])
    if not isinstance(raw_loadouts, Sequence) or isinstance(raw_loadouts, (str, bytes)):
        raise ValueError("project.loadouts must be a list")
    loadout = next(
        (item for item in raw_loadouts if isinstance(item, Mapping) and str(item.get("id")) == loadout_id),
        None,
    )
    if loadout is None:
        raise ValueError(f"unknown loadout: {loadout_id}")
    raw_ids = loadout.get("prop_ids", [])
    if not isinstance(raw_ids, Sequence) or isinstance(raw_ids, (str, bytes)):
        raise ValueError(f"loadout {loadout_id} prop_ids must be a list")
    selected_ids = [str(item) for item in raw_ids]
    selected_set = set(selected_ids)

    raw_props = project.get("props", [])
    if not isinstance(raw_props, Sequence) or isinstance(raw_props, (str, bytes)):
        raise ValueError("project.props must be a list")
    props_by_id = {
        str(item.get("id")): item
        for item in raw_props
        if isinstance(item, Mapping) and item.get("id") is not None
    }
    unknown = [item for item in selected_ids if item not in props_by_id]
    if unknown:
        raise ValueError(f"unknown props in loadout {loadout_id}: {', '.join(unknown)}")

    definitions = _raw_asset_definitions(project)
    assets: dict[str, dict[str, Any]] = {}
    instances: list[dict[str, Any]] = []
    issues: list[dict[str, Any]] = []

    # Preserve props order for compatibility while filtering by loadout.  A
    # set is used only for membership, never to collapse instances.
    for prop in raw_props:
        if not isinstance(prop, Mapping) or str(prop.get("id")) not in selected_set:
            continue
        instance_id = str(prop["id"])
        asset_id = _asset_id_for_prop(prop)
        definition = definitions.get(asset_id, definitions.get(str(prop.get("prop_asset_id", ""))))
        config = _rigid_config(definition, prop)
        try:
            axis = _normalise_axis(config)
            nominal_scale = _positive(config.get("nominal_scale", config.get("scale", 1.0)), name="nominal_scale")
            attachments = _normalise_attachments(prop, config, axis)
            origin = _point(config.get("origin", (0.0, 0.0)), name="origin")
            rotation_offset = _finite(config.get("rotation_offset_deg", 0.0), name="rotation_offset_deg")
            mask_dilate_px = max(0, int(_finite(config.get("mask_dilate_px", 6), name="mask_dilate_px")))
            contact_radius_px = max(
                1, int(_finite(config.get("contact_radius_px", 16), name="contact_radius_px"))
            )
            min_grip_separation_ratio = _finite(
                config.get("min_grip_separation_ratio", 0.1),
                name="min_grip_separation_ratio",
            )
            if not 0.0 <= min_grip_separation_ratio <= 1.0:
                raise ValueError("min_grip_separation_ratio must be between 0 and 1")
        except ValueError as exc:
            issues.append(_issue("invalid_prop_geometry", str(exc), target=instance_id))
            axis = ((0.0, -0.5), (0.0, 0.5))
            nominal_scale = 1.0
            attachments = _normalise_attachments(prop, {}, axis)
            origin = (0.0, 0.0)
            rotation_offset = 0.0
            mask_dilate_px = 6
            contact_radius_px = 16
            min_grip_separation_ratio = 0.1

        asset = {
            "id": asset_id,
            "name": str((definition or {}).get("name", prop.get("name", instance_id))),
            "reference_asset_id": prop.get("reference_asset_id") or (definition or {}).get("reference_asset_id"),
            "coordinate_space": str(config.get("coordinate_space", "local")),
            "handle_axis": [[axis[0][0], axis[0][1]], [axis[1][0], axis[1][1]]],
            "origin": list(origin),
        }
        previous_asset = assets.get(asset_id)
        if previous_asset is not None and (
            previous_asset["handle_axis"] != asset["handle_axis"]
            or previous_asset["origin"] != asset["origin"]
        ):
            issues.append(
                _issue(
                    "shared_asset_geometry_conflict",
                    f"Instances sharing asset {asset_id} define different rigid geometry.",
                    target=instance_id,
                )
            )
        else:
            assets.setdefault(asset_id, asset)

        slot = str(prop.get("slot", "free"))
        grip_mode = str(prop.get("grip", prop.get("grip_mode", "none")))
        instances.append(
            {
                "id": instance_id,
                "name": str(prop.get("name", instance_id)),
                "asset_id": asset_id,
                "slot": slot,
                "grip_mode": grip_mode,
                "persistent": bool(prop.get("persistent", False)),
                "reference_asset_id": prop.get("reference_asset_id"),
                "attachments": attachments,
                "nominal_scale": nominal_scale,
                "rotation_offset_deg": rotation_offset,
                "scale_policy": str(config.get("scale_policy", "locked")),
                "hand_order": str(config.get("hand_order", "left_before_right")),
                "min_grip_separation_ratio": min_grip_separation_ratio,
                "z_policy": str(config.get("z_policy", "front")),
                "mask_dilate_px": mask_dilate_px,
                "contact_radius_px": contact_radius_px,
            }
        )

    return {
        "schema": RIGID_PROPS_SCHEMA,
        "loadout_id": loadout_id,
        "loadout_name": str(loadout.get("name", loadout_id)),
        "assets": list(assets.values()),
        "instances": instances,
        "issues": issues,
    }


def _asset_map(normalized: Mapping[str, Any]) -> dict[str, Mapping[str, Any]]:
    return {
        str(item.get("id")): item
        for item in normalized.get("assets", [])
        if isinstance(item, Mapping) and item.get("id") is not None
    }


def preflight_rigid_loadout(normalized: Mapping[str, Any], *, require_persistent: bool = True) -> dict[str, Any]:
    issues = [dict(item) for item in normalized.get("issues", []) if isinstance(item, Mapping)]
    assets = _asset_map(normalized)
    instances = [item for item in normalized.get("instances", []) if isinstance(item, Mapping)]
    seen: set[str] = set()
    occupied: dict[str, list[str]] = {"left": [], "right": [], "both": []}

    for instance in instances:
        instance_id = str(instance.get("id", ""))
        if not instance_id or instance_id in seen:
            issues.append(_issue("duplicate_instance_id", f"Duplicate rigid prop instance: {instance_id}", target=instance_id))
        seen.add(instance_id)
        asset = assets.get(str(instance.get("asset_id")))
        if asset is None:
            issues.append(_issue("unknown_prop_asset", f"Unknown rigid prop asset for {instance_id}.", target=instance_id))
            continue
        axis = asset.get("handle_axis")
        axis_length: float | None = None
        try:
            if not isinstance(axis, Sequence) or len(axis) != 2:
                raise ValueError
            axis_length = _distance(axis[0], axis[1])
            if axis_length <= 1e-9:
                raise ValueError
        except (TypeError, ValueError):
            issues.append(
                _issue(
                    "handle_axis_invalid",
                    f"Prop {instance_id} has an invalid handle axis.",
                    target=instance_id,
                )
            )
        if not asset.get("reference_asset_id") and not instance.get("reference_asset_id"):
            issues.append(
                _issue(
                    "prop_reference_missing",
                    f"Prop {instance_id} has no isolated reference asset.",
                    target=instance_id,
                    severity="warning",
                )
            )
        if require_persistent and not instance.get("persistent"):
            issues.append(
                _issue(
                    "dynamic_prop_anchor_required",
                    f"Prop {instance_id} needs a separate loadout anchor variant.",
                    target=instance_id,
                )
            )

        slot = str(instance.get("slot", "free"))
        grip_mode = str(instance.get("grip_mode", "none"))
        attachments = [item for item in instance.get("attachments", []) if isinstance(item, Mapping)]
        if slot in _HAND_SLOTS:
            expected_hand = _HAND_SLOTS[slot]
            occupied[expected_hand].append(instance_id)
            if (
                grip_mode != "one_handed"
                or len(attachments) != 1
                or str(attachments[0].get("hand")) != expected_hand
            ):
                issues.append(
                    _issue(
                        "one_hand_attachment_invalid",
                        f"Prop {instance_id} must have exactly one attachment and one_handed grip.",
                        target=instance_id,
                    )
                )
        elif slot == "both_hands":
            occupied["both"].append(instance_id)
            hands = {str(item.get("hand")) for item in attachments}
            if grip_mode != "two_handed" or hands != {"left", "right"} or len(attachments) != 2:
                issues.append(
                    _issue(
                        "two_hand_attachment_invalid",
                        f"Prop {instance_id} must attach once to each hand.",
                        target=instance_id,
                    )
                )
            elif _distance(attachments[0]["grip_point"], attachments[1]["grip_point"]) <= 1e-6:
                issues.append(
                    _issue(
                        "two_hand_grips_coincident",
                        f"Two-handed prop {instance_id} has coincident grip points.",
                        target=instance_id,
                    )
                )
            else:
                by_hand = {str(item["hand"]): item for item in attachments}
                left_t = float(by_hand["left"].get("handle_t", 0.0))
                right_t = float(by_hand["right"].get("handle_t", 1.0))
                order = str(instance.get("hand_order", "left_before_right"))
                wrong_order = (
                    order == "left_before_right" and left_t >= right_t
                ) or (
                    order == "right_before_left" and right_t >= left_t
                )
                if order not in {"left_before_right", "right_before_left"} or wrong_order:
                    issues.append(
                        _issue(
                            "staff_hand_order_invalid",
                            f"Two-handed prop {instance_id} has invalid left/right grip order.",
                            target=instance_id,
                        )
                    )
                separation_ratio = (
                    _distance(by_hand["left"]["grip_point"], by_hand["right"]["grip_point"])
                    / axis_length
                    if axis_length is not None
                    else 0.0
                )
                if axis_length is not None and separation_ratio < float(
                    instance.get("min_grip_separation_ratio", 0.1)
                ):
                    issues.append(
                        _issue(
                            "staff_grips_too_close",
                            f"Two-handed prop {instance_id} grip points are too close.",
                            target=instance_id,
                            value=separation_ratio,
                        )
                    )
        elif attachments:
            issues.append(
                _issue(
                    "non_hand_prop_has_attachment",
                    f"Non-hand slot {slot} cannot have hand attachments.",
                    target=instance_id,
                )
            )

        for attachment in attachments:
            handle_t = float(attachment.get("handle_t", 0.5))
            if not 0.0 <= handle_t <= 1.0:
                issues.append(
                    _issue(
                        "grip_outside_handle",
                        f"Prop {instance_id} has a grip outside its handle axis.",
                        target=instance_id,
                        value=handle_t,
                    )
                )

    for hand in ("left", "right", "both"):
        if len(occupied[hand]) > 1:
            issues.append(
                _issue(
                    "hand_slot_conflict",
                    f"Multiple instances occupy {hand}: {', '.join(occupied[hand])}.",
                    target=hand,
                )
            )
    if occupied["both"] and (occupied["left"] or occupied["right"]):
        issues.append(
            _issue(
                "two_handed_conflict",
                "A both-hands instance conflicts with one-handed instances.",
                target="both_hands",
            )
        )

    error_count = sum(item.get("severity") == "error" for item in issues)
    return {
        "ok": error_count == 0,
        "issues": issues,
        "error_count": error_count,
        "warning_count": sum(item.get("severity") == "warning" for item in issues),
        "occupied_hands": occupied,
    }


def make_transform(
    translation: Sequence[float],
    rotation_deg: float,
    scale: float = 1.0,
    *,
    frame: int | None = None,
) -> dict[str, Any]:
    tx, ty = _point(translation, name="translation")
    scale_value = _positive(scale, name="scale")
    rotation_value = float(rotation_deg)
    if not math.isfinite(rotation_value):
        raise ValueError("rotation_deg must be finite")
    radians = math.radians(rotation_value)
    cosine = math.cos(radians) * scale_value
    sine = math.sin(radians) * scale_value
    result: dict[str, Any] = {
        "translation": [tx, ty],
        "rotation_deg": rotation_value,
        "scale": scale_value,
        "matrix": [[cosine, -sine, tx], [sine, cosine, ty]],
    }
    if frame is not None:
        result["frame"] = int(frame)
    return result


def transform_point(transform: Mapping[str, Any], point: Sequence[float]) -> tuple[float, float]:
    x, y = _point(point, name="point")
    matrix = transform.get("matrix")
    if isinstance(matrix, Sequence) and len(matrix) == 2:
        try:
            return (
                float(matrix[0][0]) * x + float(matrix[0][1]) * y + float(matrix[0][2]),
                float(matrix[1][0]) * x + float(matrix[1][1]) * y + float(matrix[1][2]),
            )
        except (IndexError, TypeError, ValueError) as exc:
            raise ValueError("transform matrix must be a 2x3 affine matrix") from exc
    rebuilt = make_transform(
        transform.get("translation", (0.0, 0.0)),
        float(transform.get("rotation_deg", 0.0)),
        float(transform.get("scale", 1.0)),
    )
    return transform_point(rebuilt, point)


def transform_axis(
    transform: Mapping[str, Any], axis: Sequence[Sequence[float]]
) -> tuple[tuple[float, float], tuple[float, float]]:
    if not isinstance(axis, Sequence) or len(axis) != 2:
        raise ValueError("axis must contain two points")
    return transform_point(transform, axis[0]), transform_point(transform, axis[1])


def one_hand_transform(
    *,
    grip_point: Sequence[float],
    handle_axis: Sequence[Sequence[float]],
    palm: Sequence[float],
    wrist: Sequence[float] | None = None,
    hand_angle_deg: float | None = None,
    scale: float = 1.0,
    rotation_offset_deg: float = 0.0,
    previous_rotation_deg: float | None = None,
    frame: int | None = None,
) -> dict[str, Any]:
    """Attach a one-handed prop to the palm without moving its local grip point."""

    grip = _point(grip_point, name="grip_point")
    palm_point = _point(palm, name="palm")
    if not isinstance(handle_axis, Sequence) or len(handle_axis) != 2:
        raise ValueError("handle_axis must contain two points")
    local_axis_angle = _angle(handle_axis[0], handle_axis[1])
    if hand_angle_deg is None:
        if wrist is None:
            raise ValueError("one_hand_transform requires wrist or hand_angle_deg")
        wrist_point = _point(wrist, name="wrist")
        if _distance(wrist_point, palm_point) <= 1e-9:
            raise ValueError("wrist and palm must be distinct")
        target_angle = _angle(wrist_point, palm_point)
    else:
        target_angle = float(hand_angle_deg)
        if not math.isfinite(target_angle):
            raise ValueError("hand_angle_deg must be finite")
    rotation = target_angle + float(rotation_offset_deg) - local_axis_angle
    rotation = _unwrap_angle(rotation, previous_rotation_deg)
    transform = make_transform((0.0, 0.0), rotation, scale, frame=frame)
    mapped = transform_point(transform, grip)
    transform = make_transform(
        (palm_point[0] - mapped[0], palm_point[1] - mapped[1]),
        rotation,
        scale,
        frame=frame,
    )
    transform["grip_world"] = [palm_point[0], palm_point[1]]
    return transform


def _instance_asset(instance: Mapping[str, Any], normalized: Mapping[str, Any]) -> Mapping[str, Any]:
    asset = _asset_map(normalized).get(str(instance.get("asset_id")))
    if asset is None:
        raise ValueError(f"unknown asset for instance {instance.get('id')}")
    return asset


def build_one_hand_trajectory(
    normalized: Mapping[str, Any],
    instance_id: str,
    hand_track: Sequence[Mapping[str, Any]],
) -> dict[str, Any]:
    instance = next(
        (item for item in normalized.get("instances", []) if isinstance(item, Mapping) and item.get("id") == instance_id),
        None,
    )
    if instance is None:
        raise ValueError(f"unknown rigid prop instance: {instance_id}")
    attachments = instance.get("attachments", [])
    if instance.get("grip_mode") != "one_handed" or len(attachments) != 1:
        raise ValueError(f"instance {instance_id} is not one-handed")
    asset = _instance_asset(instance, normalized)
    attachment = attachments[0]
    hand = str(attachment["hand"])
    previous_rotation: float | None = None
    frames: list[dict[str, Any]] = []
    issues: list[dict[str, Any]] = []
    for index, raw_frame in enumerate(hand_track):
        frame_number = int(raw_frame.get("frame", index))
        try:
            transform = one_hand_transform(
                grip_point=attachment["grip_point"],
                handle_axis=asset["handle_axis"],
                palm=raw_frame["palm"],
                wrist=raw_frame.get("wrist"),
                hand_angle_deg=raw_frame.get("hand_angle_deg"),
                scale=float(raw_frame.get("scale", instance.get("nominal_scale", 1.0))),
                rotation_offset_deg=float(instance.get("rotation_offset_deg", 0.0)),
                previous_rotation_deg=previous_rotation,
                frame=frame_number,
            )
            previous_rotation = float(transform["rotation_deg"])
            frames.append(
                {
                    "frame": frame_number,
                    "transform": transform,
                    "hand_targets": {hand: list(_point(raw_frame["palm"], name="palm"))},
                }
            )
        except (KeyError, TypeError, ValueError) as exc:
            issues.append(_issue("one_hand_track_invalid", str(exc), target=instance_id, frame=frame_number))
    return {
        "instance_id": instance_id,
        "mode": "hand_driven",
        "frames": frames,
        "issues": issues,
        "ok": not issues and len(frames) == len(hand_track),
    }


def _easing(value: float, name: str) -> float:
    if name == "linear":
        return value
    if name == "smoothstep":
        return value * value * (3.0 - 2.0 * value)
    if name == "smootherstep":
        return value * value * value * (value * (value * 6.0 - 15.0) + 10.0)
    raise ValueError(f"unknown easing: {name}")


def interpolate_transform_trajectory(
    keyframes: Sequence[Mapping[str, Any]],
    frame_count: int,
    *,
    easing: str = "smoothstep",
) -> list[dict[str, Any]]:
    """Interpolate exact affine keyframes using shortest-path rotations."""

    if frame_count <= 0:
        raise ValueError("frame_count must be positive")
    if not keyframes:
        raise ValueError("at least one keyframe is required")
    prepared: list[dict[str, Any]] = []
    for raw in keyframes:
        frame = int(raw.get("frame", 0))
        if frame < 0 or frame >= frame_count:
            raise ValueError(f"keyframe {frame} is outside trajectory")
        transform = raw.get("transform", raw)
        translation = transform.get("translation", transform.get("center"))
        if translation is None:
            raise ValueError(f"keyframe {frame} has no translation/center")
        prepared.append(
            {
                "frame": frame,
                "translation": _point(translation, name="translation"),
                "rotation_deg": float(transform.get("rotation_deg", 0.0)),
                "scale": _positive(transform.get("scale", 1.0), name="scale"),
            }
        )
    prepared.sort(key=lambda item: item["frame"])
    if len({item["frame"] for item in prepared}) != len(prepared):
        raise ValueError("transform keyframe numbers must be unique")
    if prepared[0]["frame"] != 0 or prepared[-1]["frame"] != frame_count - 1:
        raise ValueError("transform trajectory requires exact first and last keyframes")

    for index in range(1, len(prepared)):
        previous = prepared[index - 1]["rotation_deg"]
        prepared[index]["rotation_deg"] = _unwrap_angle(prepared[index]["rotation_deg"], previous)

    result: list[dict[str, Any]] = []
    segment = 0
    for frame in range(frame_count):
        while segment + 1 < len(prepared) - 1 and frame > prepared[segment + 1]["frame"]:
            segment += 1
        left = prepared[segment]
        right = prepared[min(segment + 1, len(prepared) - 1)]
        span = right["frame"] - left["frame"]
        amount = 0.0 if span == 0 else (frame - left["frame"]) / span
        amount = _easing(max(0.0, min(1.0, amount)), easing)
        translation = _lerp_point(left["translation"], right["translation"], amount)
        rotation = left["rotation_deg"] + (right["rotation_deg"] - left["rotation_deg"]) * amount
        scale = left["scale"] + (right["scale"] - left["scale"]) * amount
        result.append(make_transform(translation, rotation, scale, frame=frame))
    return result


def solve_two_link_ik(
    shoulder: Sequence[float],
    target: Sequence[float],
    upper_length: float,
    forearm_length: float,
    *,
    elbow_hint: Sequence[float] | None = None,
    elbow_side: int = 1,
    tolerance: float = 1e-6,
) -> dict[str, Any]:
    """Solve planar two-link IK and report unreachable-target residual."""

    shoulder_point = _point(shoulder, name="shoulder")
    target_point = _point(target, name="target")
    upper = _positive(upper_length, name="upper_length")
    forearm = _positive(forearm_length, name="forearm_length")
    dx = target_point[0] - shoulder_point[0]
    dy = target_point[1] - shoulder_point[1]
    distance = math.hypot(dx, dy)
    minimum = abs(upper - forearm)
    maximum = upper + forearm
    residual = max(0.0, minimum - distance, distance - maximum)
    reachable_distance = min(max(distance, minimum), maximum)
    if distance <= 1e-12:
        unit = (1.0, 0.0)
    else:
        unit = (dx / distance, dy / distance)
    solved_target = (
        shoulder_point[0] + unit[0] * reachable_distance,
        shoulder_point[1] + unit[1] * reachable_distance,
    )

    if reachable_distance <= 1e-12:
        elbow_candidates = [
            (shoulder_point[0], shoulder_point[1] + upper),
            (shoulder_point[0], shoulder_point[1] - upper),
        ]
    else:
        along = (upper * upper - forearm * forearm + reachable_distance * reachable_distance) / (2.0 * reachable_distance)
        height_sq = max(0.0, upper * upper - along * along)
        height = math.sqrt(height_sq)
        base = (shoulder_point[0] + unit[0] * along, shoulder_point[1] + unit[1] * along)
        perpendicular = (-unit[1], unit[0])
        elbow_candidates = [
            (base[0] + perpendicular[0] * height, base[1] + perpendicular[1] * height),
            (base[0] - perpendicular[0] * height, base[1] - perpendicular[1] * height),
        ]
    if elbow_hint is not None:
        hint = _point(elbow_hint, name="elbow_hint")
        elbow = min(elbow_candidates, key=lambda item: _distance(item, hint))
    else:
        elbow = elbow_candidates[0 if elbow_side >= 0 else 1]
    return {
        "reachable": residual <= tolerance,
        "residual": residual,
        "shoulder": list(shoulder_point),
        "elbow": list(elbow),
        "target": list(target_point),
        "solved_target": list(solved_target),
        "upper_length": upper,
        "forearm_length": forearm,
    }


def build_two_hand_staff_trajectory(
    normalized: Mapping[str, Any],
    instance_id: str,
    staff_transforms: Sequence[Mapping[str, Any]],
    *,
    rig_frames: Sequence[Mapping[str, Any]] | None = None,
    ik_tolerance_px: float = 2.0,
    locked_scale_tolerance: float = 1e-6,
) -> dict[str, Any]:
    instance = next(
        (item for item in normalized.get("instances", []) if isinstance(item, Mapping) and item.get("id") == instance_id),
        None,
    )
    if instance is None:
        raise ValueError(f"unknown rigid prop instance: {instance_id}")
    attachments = [item for item in instance.get("attachments", []) if isinstance(item, Mapping)]
    if instance.get("grip_mode") != "two_handed" or {item.get("hand") for item in attachments} != {"left", "right"}:
        raise ValueError(f"instance {instance_id} is not a valid two-handed prop")
    if rig_frames is not None and len(rig_frames) != len(staff_transforms):
        raise ValueError("rig_frames must match staff_transforms length")

    issues: list[dict[str, Any]] = []
    frames: list[dict[str, Any]] = []
    base_scale: float | None = None
    for index, raw in enumerate(staff_transforms):
        transform = raw.get("transform", raw)
        if "matrix" not in transform:
            transform = make_transform(
                transform.get("translation", transform.get("center", (0.0, 0.0))),
                float(transform.get("rotation_deg", 0.0)),
                float(transform.get("scale", instance.get("nominal_scale", 1.0))),
                frame=int(raw.get("frame", index)),
            )
        frame_number = int(raw.get("frame", transform.get("frame", index)))
        scale = float(transform.get("scale", 1.0))
        if base_scale is None:
            base_scale = scale
        elif instance.get("scale_policy", "locked") == "locked" and abs(scale - base_scale) > locked_scale_tolerance:
            issues.append(
                _issue(
                    "staff_scale_changed",
                    f"Two-handed prop {instance_id} changed scale.",
                    target=instance_id,
                    frame=frame_number,
                    value=abs(scale - base_scale),
                )
            )

        targets = {
            str(attachment["hand"]): list(transform_point(transform, attachment["grip_point"]))
            for attachment in attachments
        }
        frame_result: dict[str, Any] = {
            "frame": frame_number,
            "transform": dict(transform),
            "hand_targets": targets,
        }
        if rig_frames is not None:
            ik: dict[str, Any] = {}
            for hand in ("left", "right"):
                rig = rig_frames[index].get(hand)
                if not isinstance(rig, Mapping):
                    issues.append(
                        _issue(
                            "staff_ik_rig_missing",
                            f"Missing {hand} arm rig for {instance_id}.",
                            target=instance_id,
                            frame=frame_number,
                        )
                    )
                    continue
                try:
                    solution = solve_two_link_ik(
                        rig["shoulder"],
                        targets[hand],
                        rig.get("upper_length", rig.get("upper_arm")),
                        rig.get("forearm_length", rig.get("forearm")),
                        elbow_hint=rig.get("elbow_hint"),
                        elbow_side=int(rig.get("elbow_side", 1 if hand == "left" else -1)),
                        tolerance=ik_tolerance_px,
                    )
                except (KeyError, TypeError, ValueError) as exc:
                    issues.append(
                        _issue("staff_ik_rig_invalid", str(exc), target=instance_id, frame=frame_number)
                    )
                    continue
                ik[hand] = solution
                if not solution["reachable"]:
                    issues.append(
                        _issue(
                            "staff_grip_unreachable",
                            f"{hand} hand cannot reach the {instance_id} grip target.",
                            target=instance_id,
                            frame=frame_number,
                            value=float(solution["residual"]),
                        )
                    )
            frame_result["ik"] = ik
        frames.append(frame_result)
    return {
        "instance_id": instance_id,
        "mode": "staff_driven",
        "frames": frames,
        "issues": issues,
        "ok": not any(item.get("severity") == "error" for item in issues),
    }


def build_instance_trajectory(
    normalized: Mapping[str, Any],
    instance_id: str,
    control_frames: Sequence[Mapping[str, Any]],
    *,
    rig_frames: Sequence[Mapping[str, Any]] | None = None,
) -> dict[str, Any]:
    instance = next(
        (item for item in normalized.get("instances", []) if isinstance(item, Mapping) and item.get("id") == instance_id),
        None,
    )
    if instance is None:
        raise ValueError(f"unknown rigid prop instance: {instance_id}")
    if instance.get("grip_mode") == "one_handed":
        return build_one_hand_trajectory(normalized, instance_id, control_frames)
    if instance.get("grip_mode") == "two_handed":
        return build_two_hand_staff_trajectory(
            normalized, instance_id, control_frames, rig_frames=rig_frames
        )
    raise ValueError(f"instance {instance_id} has no hand-driven trajectory")


def _trajectory_frames(value: Any) -> list[Mapping[str, Any]]:
    if isinstance(value, Mapping):
        value = value.get("frames", [])
    if not isinstance(value, Sequence) or isinstance(value, (str, bytes)):
        raise ValueError("trajectory must contain frame records")
    return [item for item in value if isinstance(item, Mapping)]


def build_mask_sidecar_metadata(
    normalized: Mapping[str, Any],
    trajectories: Mapping[str, Any],
    *,
    width: int,
    height: int,
    fps: float,
    mask_prefix: str = "rigid_props",
    mask_refs: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    """Build JSON-safe metadata; mask rasters/videos are produced by the caller."""

    if width <= 0 or height <= 0 or fps <= 0:
        raise ValueError("sidecar canvas and fps must be positive")
    mask_refs = mask_refs or {}
    assets = _asset_map(normalized)
    sidecar_instances: list[dict[str, Any]] = []
    frame_count: int | None = None
    for instance in normalized.get("instances", []):
        if not isinstance(instance, Mapping):
            continue
        instance_id = str(instance["id"])
        if instance_id not in trajectories:
            raise ValueError(f"missing trajectory for {instance_id}")
        records = _trajectory_frames(trajectories[instance_id])
        if frame_count is None:
            frame_count = len(records)
        elif len(records) != frame_count:
            raise ValueError("all rigid prop trajectories must have equal frame counts")
        asset = assets[str(instance["asset_id"])]
        safe_instance = _safe_id(instance_id)
        supplied = mask_refs.get(instance_id, {})
        supplied = supplied if isinstance(supplied, Mapping) else {}
        contacts = supplied.get("contacts", {})
        contacts = contacts if isinstance(contacts, Mapping) else {}
        contact_masks = {
            str(attachment["hand"]): str(
                contacts.get(
                    str(attachment["hand"]),
                    f"{mask_prefix}/contact_{safe_instance}_{attachment['hand']}.mp4",
                )
            )
            for attachment in instance.get("attachments", [])
        }
        frame_metadata: list[dict[str, Any]] = []
        for index, record in enumerate(records):
            transform = record.get("transform", record)
            grips = {
                str(attachment["hand"]): list(transform_point(transform, attachment["grip_point"]))
                for attachment in instance.get("attachments", [])
            }
            axis = transform_axis(transform, asset["handle_axis"])
            frame_metadata.append(
                {
                    "frame": int(record.get("frame", index)),
                    "transform": {
                        "translation": list(transform.get("translation", (0.0, 0.0))),
                        "rotation_deg": float(transform.get("rotation_deg", 0.0)),
                        "scale": float(transform.get("scale", 1.0)),
                        "matrix": transform.get("matrix"),
                    },
                    "handle_axis": [list(axis[0]), list(axis[1])],
                    "grips": grips,
                }
            )
        sidecar_instances.append(
            {
                "instance_id": instance_id,
                "asset_id": instance["asset_id"],
                "slot": instance["slot"],
                "grip_mode": instance["grip_mode"],
                "instance_mask": str(
                    supplied.get("instance", f"{mask_prefix}/instance_{safe_instance}.mp4")
                ),
                "contact_masks": contact_masks,
                "mask_dilate_px": int(instance.get("mask_dilate_px", 6)),
                "contact_radius_px": int(instance.get("contact_radius_px", 16)),
                "frames": frame_metadata,
            }
        )
    return {
        "schema": RIGID_MASK_SIDECAR_SCHEMA,
        "loadout_id": normalized.get("loadout_id"),
        "canvas": {"width": int(width), "height": int(height)},
        "fps": float(fps),
        "frame_count": frame_count or 0,
        "mask_semantics": {"white": "generate_or_repair", "black": "preserve_exactly"},
        "union_mask": str(mask_refs.get("union", f"{mask_prefix}/union.mp4")),
        "instances": sidecar_instances,
    }


def _track_point(track: Sequence[Any] | None, index: int) -> tuple[float, float] | None:
    if track is None or index >= len(track):
        return None
    value = track[index]
    if isinstance(value, Mapping):
        value = value.get("palm", value.get("point"))
    if value is None:
        return None
    return _point(value, name="palm track point")


def contact_qc(
    normalized: Mapping[str, Any],
    trajectories: Mapping[str, Any],
    hand_tracks: Mapping[str, Sequence[Any]],
    *,
    observations: Mapping[str, Any] | None = None,
    grip_error_px: float = 8.0,
    hard_grip_error_px: float = 14.0,
    length_drift_ratio: float = 0.03,
    orientation_step_deg: float = 20.0,
    identity_margin_px: float = 4.0,
) -> dict[str, Any]:
    """Evaluate attachment geometry; fingers still require manual acceptance."""

    observations = observations or {}
    assets = _asset_map(normalized)
    issues: list[dict[str, Any]] = []
    metrics: dict[str, Any] = {}
    for instance in normalized.get("instances", []):
        if not isinstance(instance, Mapping):
            continue
        instance_id = str(instance["id"])
        planned = trajectories.get(instance_id)
        observed = observations.get(instance_id, planned)
        if observed is None:
            issues.append(
                _issue(
                    "prop_instance_missing",
                    f"No observed trajectory for {instance_id}.",
                    target=instance_id,
                )
            )
            continue
        records = _trajectory_frames(observed)
        asset = assets.get(str(instance["asset_id"]))
        if asset is None:
            issues.append(_issue("unknown_prop_asset", f"Unknown asset for {instance_id}.", target=instance_id))
            continue
        instance_metrics: list[dict[str, Any]] = []
        baseline_length: float | None = None
        previous_orientation: float | None = None
        for index, record in enumerate(records):
            frame_number = int(record.get("frame", index))
            transform = record.get("transform", record)
            source_instance = record.get("source_instance_id", record.get("observed_instance_id"))
            if source_instance is not None and str(source_instance) != instance_id:
                issues.append(
                    _issue(
                        "prop_identity_mismatch",
                        f"Track for {instance_id} contains {source_instance}.",
                        target=instance_id,
                        frame=frame_number,
                    )
                )
            axis = transform_axis(transform, asset["handle_axis"])
            current_length = _distance(*axis)
            if baseline_length is None:
                baseline_length = current_length
            length_drift = 0.0 if baseline_length <= 1e-9 else abs(current_length / baseline_length - 1.0)
            orientation = _angle(*axis)
            orientation_step = 0.0 if previous_orientation is None else abs(
                angular_delta_degrees(previous_orientation, orientation)
            )
            previous_orientation = orientation
            if length_drift > length_drift_ratio:
                issues.append(
                    _issue(
                        "prop_length_drift",
                        f"Prop {instance_id} changed handle length.",
                        target=instance_id,
                        frame=frame_number,
                        value=length_drift,
                    )
                )
            if orientation_step > orientation_step_deg:
                issues.append(
                    _issue(
                        "prop_orientation_jump",
                        f"Prop {instance_id} has an abrupt orientation change.",
                        target=instance_id,
                        frame=frame_number,
                        value=orientation_step,
                    )
                )

            grip_metrics: dict[str, float | None] = {}
            attachment_world: dict[str, tuple[float, float]] = {}
            for attachment in instance.get("attachments", []):
                hand = str(attachment["hand"])
                world_grip = transform_point(transform, attachment["grip_point"])
                attachment_world[hand] = world_grip
                palm = _track_point(hand_tracks.get(hand), index)
                if palm is None:
                    grip_metrics[hand] = None
                    issues.append(
                        _issue(
                            "palm_track_missing",
                            f"Missing {hand} palm track for {instance_id}.",
                            target=instance_id,
                            frame=frame_number,
                        )
                    )
                    continue
                error = _distance(world_grip, palm)
                grip_metrics[hand] = error
                if error > hard_grip_error_px:
                    severity = "error"
                elif error > grip_error_px:
                    severity = "review"
                else:
                    severity = "ok"
                if severity != "ok":
                    issues.append(
                        _issue(
                            "grip_error",
                            f"{hand} grip is offset from {instance_id}.",
                            target=instance_id,
                            frame=frame_number,
                            value=error,
                            severity=severity,
                        )
                    )

                other_hand = "right" if hand == "left" else "left"
                other_palm = _track_point(hand_tracks.get(other_hand), index)
                if other_palm is not None and _distance(world_grip, other_palm) + identity_margin_px < error:
                    issues.append(
                        _issue(
                            "prop_identity_swap",
                            f"Instance {instance_id} is closer to the wrong hand.",
                            target=instance_id,
                            frame=frame_number,
                            value=error - _distance(world_grip, other_palm),
                        )
                    )

            # A two-hand object can be flipped while each tracker still has the
            # same asset identity.  Explicitly reject crossed hand assignment.
            if set(attachment_world) == {"left", "right"}:
                left_palm = _track_point(hand_tracks.get("left"), index)
                right_palm = _track_point(hand_tracks.get("right"), index)
                if left_palm is not None and right_palm is not None:
                    direct = _distance(attachment_world["left"], left_palm) + _distance(
                        attachment_world["right"], right_palm
                    )
                    crossed = _distance(attachment_world["left"], right_palm) + _distance(
                        attachment_world["right"], left_palm
                    )
                    if crossed + identity_margin_px < direct:
                        issues.append(
                            _issue(
                                "two_hand_grips_swapped",
                                f"Left/right grips are swapped for {instance_id}.",
                                target=instance_id,
                                frame=frame_number,
                                value=direct - crossed,
                            )
                        )
            instance_metrics.append(
                {
                    "frame": frame_number,
                    "grip_error_px": grip_metrics,
                    "handle_length_px": current_length,
                    "length_drift_ratio": length_drift,
                    "orientation_deg": orientation,
                    "orientation_step_deg": orientation_step,
                }
            )
        metrics[instance_id] = instance_metrics
        if instance.get("attachments"):
            issues.append(
                _issue(
                    "manual_grip_review_required",
                    f"Finger occlusion for {instance_id} requires manual review.",
                    target=instance_id,
                    severity="review",
                )
            )

    return {
        "ok": not any(item.get("severity") == "error" for item in issues),
        "needs_review": any(item.get("severity") == "review" for item in issues),
        "issues": issues,
        "metrics": metrics,
        "thresholds": {
            "grip_error_px": float(grip_error_px),
            "hard_grip_error_px": float(hard_grip_error_px),
            "length_drift_ratio": float(length_drift_ratio),
            "orientation_step_deg": float(orientation_step_deg),
            "identity_margin_px": float(identity_margin_px),
        },
    }


def rigid_loadout_signature(normalized: Mapping[str, Any]) -> str:
    """Stable signature for anchor/library invalidation."""

    assets = sorted(
        (
            {
                "id": item.get("id"),
                "reference_asset_id": item.get("reference_asset_id"),
                "handle_axis": item.get("handle_axis"),
                "origin": item.get("origin"),
            }
            for item in normalized.get("assets", [])
            if isinstance(item, Mapping)
        ),
        key=lambda item: str(item["id"]),
    )
    instances = sorted(
        (
            {
                "id": item.get("id"),
                "asset_id": item.get("asset_id"),
                "slot": item.get("slot"),
                "grip_mode": item.get("grip_mode"),
                "persistent": item.get("persistent"),
                "attachments": item.get("attachments"),
                "nominal_scale": item.get("nominal_scale"),
                "rotation_offset_deg": item.get("rotation_offset_deg"),
                "scale_policy": item.get("scale_policy"),
                "hand_order": item.get("hand_order"),
                "min_grip_separation_ratio": item.get("min_grip_separation_ratio"),
                "z_policy": item.get("z_policy"),
            }
            for item in normalized.get("instances", [])
            if isinstance(item, Mapping)
        ),
        key=lambda item: str(item["id"]),
    )
    payload = {
        "schema": RIGID_PROPS_SCHEMA,
        "loadout_id": normalized.get("loadout_id"),
        "assets": assets,
        "instances": instances,
    }
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def loadout_anchor_key(normalized: Mapping[str, Any]) -> str:
    loadout_id = _safe_id(str(normalized.get("loadout_id", "default")))
    return f"anchor_{loadout_id}_{rigid_loadout_signature(normalized)[:16]}"


def project_loadout_anchor_key(project: Mapping[str, Any], loadout_id: str = "default") -> str:
    return loadout_anchor_key(normalize_project_props(project, loadout_id))


def loadout_anchor_metadata(
    normalized: Mapping[str, Any], *, asset_id: str | None = None
) -> dict[str, Any]:
    metadata: dict[str, Any] = {
        "key": loadout_anchor_key(normalized),
        "signature": rigid_loadout_signature(normalized),
        "loadout_id": normalized.get("loadout_id"),
        "instance_ids": sorted(
            str(item["id"])
            for item in normalized.get("instances", [])
            if isinstance(item, Mapping) and item.get("id") is not None
        ),
    }
    if asset_id is not None:
        metadata["asset_id"] = asset_id
    return metadata
