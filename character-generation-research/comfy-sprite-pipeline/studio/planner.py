from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Any

from .catalog import get_motion
from .rigid_props import normalize_project_props, preflight_rigid_loadout


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _issue(code: str, message: str, *, severity: str = "error", target: str | None = None) -> dict[str, str]:
    issue = {"code": code, "message": message, "severity": severity}
    if target:
        issue["target"] = target
    return issue


def _selected_props(project: dict[str, Any], loadout_id: str) -> list[dict[str, Any]]:
    loadout = next((item for item in project.get("loadouts", []) if item.get("id") == loadout_id), None)
    if loadout is None:
        raise ValueError(f"unknown loadout: {loadout_id}")
    ids = set(loadout.get("prop_ids", []))
    return [item for item in project.get("props", []) if item.get("id") in ids]


def _loadout_anchor(project: dict[str, Any], loadout_id: str) -> dict[str, Any]:
    anchors = project.get("anchors", {})
    if isinstance(anchors, dict) and isinstance(anchors.get(loadout_id), dict):
        return anchors[loadout_id]
    if loadout_id == project.get("active_loadout_id", "default"):
        return project.get("anchor", {})
    if loadout_id == "default" and not anchors:
        return project.get("anchor", {})
    return {}


def _prop_issues(props: list[dict[str, Any]]) -> list[dict[str, str]]:
    issues: list[dict[str, str]] = []
    slots: dict[str, list[str]] = {}
    for prop in props:
        slots.setdefault(prop.get("slot", "free"), []).append(prop.get("id", "unknown"))
        if not prop.get("reference_asset_id"):
            issues.append(
                _issue(
                    "prop_reference_missing",
                    f"Для предмета «{prop.get('name', prop.get('id'))}» не загружен отдельный референс.",
                    severity="warning",
                    target=prop.get("id"),
                )
            )
    for slot in ("left_hand", "right_hand", "both_hands"):
        if len(slots.get(slot, [])) > 1:
            issues.append(
                _issue(
                    "hand_slot_conflict",
                    f"В slot {slot} назначено несколько предметов: {', '.join(slots[slot])}.",
                    target=slot,
                )
            )
    if slots.get("both_hands") and (slots.get("left_hand") or slots.get("right_hand")):
        issues.append(
            _issue(
                "two_handed_conflict",
                "Двуручный предмет нельзя одновременно использовать с отдельными предметами в левой/правой руке.",
                target="both_hands",
            )
        )
    return issues


_RIGID_ISSUE_MESSAGES = {
    "invalid_prop_geometry": "Некорректная rigid-геометрия предмета «{target}».",
    "shared_asset_geometry_conflict": "Instances общего prop asset задают разную ось или origin; исправьте rigid-геометрию «{target}».",
    "duplicate_instance_id": "Повторяется rigid instance «{target}».",
    "unknown_prop_asset": "Для rigid instance «{target}» не найден prop asset.",
    "one_hand_attachment_invalid": "Одноручный предмет «{target}» должен иметь ровно один хват назначенной рукой.",
    "two_hand_attachment_invalid": "Двуручный предмет «{target}» должен иметь отдельные хваты левой и правой рукой.",
    "two_hand_grips_coincident": "У двуручного предмета «{target}» точки хвата совпадают.",
    "staff_hand_order_invalid": "У предмета «{target}» перепутан порядок левого и правого хвата на рукояти.",
    "staff_grips_too_close": "Точки хвата предмета «{target}» расположены слишком близко друг к другу.",
    "grip_outside_handle": "Точка хвата предмета «{target}» находится за пределами оси рукояти.",
    "non_hand_prop_has_attachment": "Предмет «{target}» не находится в руке, но содержит hand attachment.",
    "handle_axis_invalid": "У предмета «{target}» отсутствует корректная ось рукояти.",
}


def _rigid_prop_issues(
    project: dict[str, Any],
    loadout_id: str,
    props: list[dict[str, Any]],
) -> tuple[list[dict[str, str]], dict[str, Any]]:
    """Run rigid preflight while leaving legacy props on their old contract."""

    configured = {str(item.get("id")) for item in props if "rigid" in item}
    try:
        normalized = normalize_project_props(project, loadout_id)
        preflight = preflight_rigid_loadout(normalized, require_persistent=False)
    except ValueError as exc:
        if not configured:
            return [], {"configured_instances": [], "instances": [], "preflight_ok": True}
        issue = _issue(
            "rigid_props_invalid",
            f"Rigid props loadout не прошёл нормализацию: {exc}",
            target=loadout_id,
        )
        return [issue], {
            "configured_instances": sorted(configured),
            "instances": [],
            "preflight_ok": False,
        }

    # These are already emitted by the legacy slot/reference checks in Russian.
    duplicate_legacy_codes = {
        "prop_reference_missing",
        "hand_slot_conflict",
        "two_handed_conflict",
        "dynamic_prop_anchor_required",
    }
    issues: list[dict[str, str]] = []
    for raw in preflight.get("issues", []):
        code = str(raw.get("code", "rigid_props_invalid"))
        target = str(raw.get("target", ""))
        if code in duplicate_legacy_codes or target not in configured:
            continue
        message_template = _RIGID_ISSUE_MESSAGES.get(
            code,
            "Rigid preflight отклонил конфигурацию предмета «{target}».",
        )
        issues.append(
            _issue(
                code,
                message_template.format(target=target),
                severity=str(raw.get("severity", "error")),
                target=target,
            )
        )
    blocking = any(item["severity"] == "error" for item in issues)
    return issues, {
        "configured_instances": sorted(configured),
        "instances": [
            str(item.get("id"))
            for item in normalized.get("instances", [])
            if isinstance(item, dict)
        ],
        "preflight_ok": not blocking,
    }


def _hand_policy_issue(motion: dict[str, Any], props: list[dict[str, Any]]) -> dict[str, str] | None:
    occupied = {item.get("slot") for item in props}
    policy = motion.get("hand_policy", "any")
    blocked = False
    if policy == "left_free":
        blocked = bool({"left_hand", "both_hands"} & occupied)
    elif policy == "right_free":
        blocked = bool({"right_hand", "both_hands"} & occupied)
    elif policy == "both_free":
        blocked = bool({"left_hand", "right_hand", "both_hands"} & occupied)
    elif policy == "left_free_or_attached":
        left = [item for item in props if item.get("slot") in {"left_hand", "both_hands"}]
        blocked = any(item.get("slot") == "both_hands" or not isinstance(item.get("rigid"), dict) for item in left)
    elif policy == "right_free_or_attached":
        right = [item for item in props if item.get("slot") in {"right_hand", "both_hands"}]
        blocked = any(item.get("slot") == "both_hands" or not isinstance(item.get("rigid"), dict) for item in right)
    elif policy == "both_free_or_attached":
        hands = [item for item in props if item.get("slot") in {"left_hand", "right_hand", "both_hands"}]
        blocked = any(item.get("slot") == "both_hands" or not isinstance(item.get("rigid"), dict) for item in hands)
    if not blocked:
        return None
    return _issue(
        "motion_prop_conflict",
        f"Движение «{motion['label']}» требует свободную руку, но текущий loadout её занимает.",
        target=motion["id"],
    )


def build_generation_plan(
    project: dict[str, Any],
    *,
    motion_ids: list[str] | None = None,
    loadout_id: str = "default",
    capabilities: dict[str, Any] | None = None,
) -> dict[str, Any]:
    capabilities = capabilities or {}
    features = capabilities.get("features", {})
    selected = motion_ids if motion_ids is not None else project.get("selected_motions", [])
    selected = list(dict.fromkeys(selected))
    issues: list[dict[str, str]] = []

    primary = project.get("references", {}).get("primary")
    if not primary:
        issues.append(_issue("primary_reference_missing", "Сначала загрузите основной full-body reference.", target="primary"))

    props = _selected_props(project, loadout_id)
    prop_issues = _prop_issues(props)
    rigid_issues, rigid_summary = _rigid_prop_issues(project, loadout_id, props)
    prop_issues.extend(rigid_issues)
    issues.extend(prop_issues)
    prop_configuration_blocked = any(item["severity"] == "error" for item in prop_issues)

    anchor = _loadout_anchor(project, loadout_id)
    anchor_ready = anchor.get("status") == "ready"
    if selected and not anchor_ready:
        issues.append(
            _issue(
                "anchor_not_ready",
                f"Сначала создайте и примите canonical anchor для loadout «{loadout_id}»; motion-задачи пока не будут поставлены в GPU-очередь.",
                severity="warning",
                target="anchor",
            )
        )
    stages: list[dict[str, Any]] = []
    stages.append(
        {
            "id": "canonicalize",
            "workflow": "w6-character-canonicalize",
            "status": (
                "blocked"
                if prop_configuration_blocked
                else "skipped"
                if anchor_ready
                else "ready"
                if primary and features.get("canonicalize", False)
                else "blocked"
            ),
            "reason": (
                "rigid prop preflight failed"
                if prop_configuration_blocked
                else "anchor already accepted"
                if anchor_ready
                else "build a canonical anchor from 1–3 references"
            ),
        }
    )
    if not anchor_ready and primary and not features.get("canonicalize", False):
        issues.append(_issue("canonicalize_unavailable", "W6 недоступен: отсутствуют нужные nodes или модели.", target="canonicalize"))

    motion_tasks: list[dict[str, Any]] = []
    for motion_id in selected:
        motion = get_motion(motion_id)
        if motion is None:
            issues.append(_issue("unknown_motion", f"Неизвестное движение: {motion_id}", target=motion_id))
            continue
        policy_issue = _hand_policy_issue(motion, props)
        if policy_issue:
            issues.append(policy_issue)

        mode = motion["generation_mode"]
        feature_name = {
            "prompt_loop": "prompt_loop",
            "pose_control": "pose_control",
            "face_layer": "face_layer",
        }.get(mode, mode)
        available = bool(features.get(feature_name, False))
        if mode == "pose_control":
            supported = set(capabilities.get("motion_support", {}).get("pose_control", []))
            available = available and motion_id in supported
        if prop_configuration_blocked:
            task_status = "blocked"
        elif not anchor_ready:
            task_status = "waiting_anchor"
        else:
            task_status = "ready" if available and policy_issue is None and not prop_configuration_blocked else "blocked"
        if not available:
            issues.append(
                _issue(
                    "generation_mode_unavailable",
                    f"Для «{motion['label']}» пока недоступен режим {mode}; понижать точность молча Studio не будет.",
                    target=motion_id,
                )
            )
        motion_tasks.append(
            {
                "id": motion_id,
                "label": motion["label"],
                "channel": motion["channel"],
                "side": motion["side"],
                "mode": mode,
                "frames": motion["frames"],
                "runtime_frames": motion["runtime_frames"],
                "fps": motion["fps"],
                "playback": motion["playback"],
                "status": task_status,
                "workflow": (
                    "w7-seamless-loop"
                    if mode == "prompt_loop"
                    else "w8-vace-pose-control"
                    if mode == "pose_control"
                    else "w11-face-layer"
                    if mode == "face_layer"
                    else f"studio-{mode}"
                ),
            }
        )

    stages.append(
        {
            "id": "motion_generation",
            "workflow": "w7-seamless-loop / pose-control variants",
            "status": (
                "blocked"
                if any(item["status"] == "blocked" for item in motion_tasks)
                else "waiting_anchor"
                if any(item["status"] == "waiting_anchor" for item in motion_tasks)
                else "ready"
            ),
            "tasks": motion_tasks,
        }
    )
    stages.append(
        {
            "id": "continuity_qc",
            "workflow": "postprocess",
            "status": "ready" if features.get("continuity_qc", False) else "planned",
            "checks": ["anchor equality", "all adjacent seams", "root drift", "scale drift", "prop/side review"],
        }
    )
    stages.append(
        {
            "id": "viseme_atlas",
            "workflow": "face layer",
            "status": "ready" if features.get("viseme_atlas", False) else "planned",
            "reason": "interactive mouth layer; offline generative lipsync is optional",
        }
    )

    blocking = [item for item in issues if item["severity"] == "error"]
    return {
        "id": f"plan_{uuid.uuid4().hex[:12]}",
        "created_at": _now(),
        "project_id": project["id"],
        "project_revision": project.get("revision", 0),
        "quality_profile": project.get("settings", {}).get("quality_profile", "local_12gb"),
        "loadout_id": loadout_id,
        "props": [item["id"] for item in props],
        "rigid_props": rigid_summary,
        "blocked": bool(blocking),
        "issues": issues,
        "stages": stages,
        "summary": {
            "motions_requested": len(selected),
            "motions_ready": sum(item["status"] == "ready" for item in motion_tasks),
            "errors": len(blocking),
            "warnings": sum(item["severity"] == "warning" for item in issues),
        },
    }
