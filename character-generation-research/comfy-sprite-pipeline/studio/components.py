from __future__ import annotations

import json
from copy import deepcopy
from typing import Any, Iterable

from .catalog import get_motion
from .runtime import build_runtime_manifest


COMPONENT_SCHEMA = "character.web-component.v1"

# Public action names are intentionally stable. Internal workflow
# ids can evolve without forcing applications embedding the Web Component to
# change their commands.
PUBLIC_ACTIONS: dict[str, dict[str, Any]] = {
    "idle": {
        "motion_id": "idle_breathing",
        "label": "Спокойное idle",
        "aliases": ["idle", "покой", "обычный idle", "стой спокойно"],
    },
    "idle_smile": {
        "motion_id": "idle_breathing",
        "overlay_id": "idle_smile",
        "label": "Idle с улыбкой",
        "aliases": ["idle_smile", "idle smile", "улыбнись", "улыбка", "стой с улыбкой"],
    },
    "walk_right": {
        "motion_id": "walk_right",
        "label": "Шаг вправо",
        "aliases": ["walk_right", "иди вправо", "шаг вправо", "вправо"],
    },
    "walk_left": {
        "motion_id": "walk_left",
        "label": "Шаг влево",
        "aliases": ["walk_left", "иди влево", "шаг влево", "влево"],
    },
    "run_right": {
        "motion_id": "run_right",
        "label": "Бег вправо",
        "aliases": ["run_right", "беги вправо", "бег вправо"],
    },
    "run_left": {
        "motion_id": "run_left",
        "label": "Бег влево",
        "aliases": ["run_left", "беги влево", "бег влево"],
    },
    "jump_start": {
        "motion_id": "jump_start",
        "label": "Отрыв",
        "playback": "once_return",
        "aliases": ["jump_start", "прыжок", "отрыв", "начать прыжок"],
    },
    "jump_up": {
        "motion_id": "jump_up",
        "label": "Прыжок вверх",
        "playback": "once_return",
        "aliases": ["jump_up", "прыжок вверх", "подъём", "вверх"],
    },
}


def _public_action(
    motion_id: str,
    label: str,
    group: str,
    *,
    default_selected: bool = False,
    loop: bool = False,
    aliases: list[str] | None = None,
) -> dict[str, Any]:
    return {
        "motion_id": motion_id,
        "label": label,
        "group": group,
        "default_selected": default_selected,
        "playback": "loop" if loop else "once_return",
        "aliases": aliases or [motion_id, label.lower()],
    }


# Every command visible in the component workbench is buildable through the
# same W1/W2/W3 pipeline. Keep ids stable: they are the public runtime API.
PUBLIC_ACTIONS.update({
    "idle_3": _public_action("idle_3", "Боевой idle", "idle", loop=True),
    "idle_4": _public_action("idle_4", "Задумчивый idle", "idle", loop=True),
    "idle_5": _public_action("idle_5", "Сердитый idle", "idle", loop=True),
    "jump_left": _public_action("jump_left", "Прыжок влево", "traversal"),
    "jump_right": _public_action("jump_right", "Прыжок вправо", "traversal"),
    "fall": _public_action("fall", "Падение", "traversal", loop=True),
    "fall_fast": _public_action("fall_fast", "Быстрое падение", "traversal", loop=True),
    "land": _public_action("land", "Приземление", "traversal"),
    "drop_down": _public_action("drop_down", "Спрыгнуть", "traversal"),
    "climb_idle": _public_action("climb_idle", "На лестнице", "traversal", loop=True),
    "climb_up": _public_action("climb_up", "Лезть вверх", "traversal", loop=True),
    "climb_down": _public_action("climb_down", "Лезть вниз", "traversal", loop=True),
    "ledge_grab": _public_action("ledge_grab", "Зацепиться", "traversal"),
    "ledge_climb": _public_action("ledge_climb", "Залезть", "traversal"),
    "vault": _public_action("vault", "Перепрыгнуть", "traversal"),
    "crouch": _public_action("crouch", "Присесть", "traversal"),
    "crawl": _public_action("crawl", "Ползти", "traversal", loop=True),
    "roll": _public_action("roll", "Кувырок", "traversal"),
    "dash": _public_action("dash", "Рывок", "traversal"),
    "swim": _public_action("swim", "Плыть", "traversal", loop=True),
    "float": _public_action("float", "На воде", "traversal", loop=True),
    "attack_1": _public_action("attack_1", "Атака 1", "combat"),
    "attack_2": _public_action("attack_2", "Атака 2", "combat"),
    "attack_heavy": _public_action("attack_heavy", "Сильная атака", "combat"),
    "attack_ranged": _public_action("attack_ranged", "Дальняя атака", "combat"),
    "block": _public_action("block", "Блок", "combat"),
    "dodge": _public_action("dodge", "Уклонение", "combat"),
    "hit": _public_action("hit", "Получить урон", "combat"),
    "knockdown": _public_action("knockdown", "Нокдаун", "combat"),
    "death": _public_action("death", "Смерть", "combat"),
    "victory": _public_action("victory", "Победа", "combat"),
    "interact": _public_action("interact", "Действие", "interaction"),
    "pickup": _public_action("pickup", "Поднять", "interaction"),
    "use": _public_action("use", "Использовать", "interaction"),
    "push": _public_action("push", "Толкать", "interaction"),
    "pull": _public_action("pull", "Тянуть", "interaction"),
    "talk": _public_action("talk", "Говорить", "interaction", loop=True),
    "spell_1": _public_action("spell_1", "Спелл 1", "spells"),
    "spell_2": _public_action("spell_2", "Спелл 2", "spells"),
    "spell_3": _public_action("spell_3", "Спелл 3", "spells"),
    "spell_4": _public_action("spell_4", "Спелл 4", "spells"),
    "spell_5": _public_action("spell_5", "Спелл 5", "spells"),
})

for _action_id, _definition in PUBLIC_ACTIONS.items():
    _definition.setdefault(
        "group",
        "idle" if _action_id.startswith("idle")
        else "locomotion" if _action_id.startswith(("walk_", "run_"))
        else "traversal",
    )
    _definition.setdefault("default_selected", _action_id in {"idle", "idle_smile"})
    _definition.setdefault(
        "playback",
        "loop" if _definition["group"] in {"idle", "locomotion"} else "once_return",
    )


def component_actions_payload() -> list[dict[str, Any]]:
    """Return the ordered public catalogue used by creation and playback UI."""

    return [
        {
            "id": action_id,
            "label": definition["label"],
            "group": definition["group"],
            "default_selected": definition["default_selected"],
            "playback": definition["playback"],
        }
        for action_id, definition in PUBLIC_ACTIONS.items()
    ]



def normalize_component_actions(values: Iterable[Any] | None) -> list[str]:
    """Validate and de-duplicate the public action catalogue."""

    raw = list(("idle", "idle_smile") if values is None else values)
    actions: list[str] = []
    for value in raw:
        action = str(value).strip().lower()
        if action not in PUBLIC_ACTIONS:
            raise ValueError(f"unsupported component action: {action or value}")
        if action not in actions:
            actions.append(action)
    if not actions:
        raise ValueError("select at least one component action")
    return actions


def component_requested_actions(
    project: dict[str, Any],
    fallback: Iterable[Any] | None = None,
) -> list[str]:
    """Return canonical selected actions instead of stale historical job inputs."""

    component = project.get("component") or {}
    requested = component.get("requested_actions")
    if requested is None:
        records = component.get("actions") or {}
        ready = [
            action_id for action_id in PUBLIC_ACTIONS
            if isinstance(records.get(action_id), dict) and records[action_id].get("status") == "ready"
        ]
        if ready:
            requested = ready
    return normalize_component_actions(fallback if requested is None else requested)


def component_motion_ids(actions: Iterable[Any] | None) -> list[str]:
    return [str(PUBLIC_ACTIONS[action]["motion_id"]) for action in normalize_component_actions(actions)]


def component_motion_id(action: Any) -> str:
    """Resolve one public action to the original pipeline pose preset."""

    return component_motion_ids([action])[0]


def component_pipeline_results(project: dict[str, Any], actions: Iterable[Any] | None) -> list[dict[str, Any]]:
    """Expose only the three visual artifacts of the public W1/W2/W3 build."""
    assets = project.get("assets", {}) if isinstance(project.get("assets"), dict) else {}
    records = (project.get("component") or {}).get("actions", {})
    results: list[dict[str, Any]] = []
    for action in normalize_component_actions(actions):
        record = records.get(action, {}) if isinstance(records, dict) else {}
        stages = record.get("stages", {}) if isinstance(record, dict) else {}
        def url(key: str) -> str | None:
            asset = assets.get(str(stages.get(key, "")))
            return str(asset.get("url")) if isinstance(asset, dict) and asset.get("url") else None
        results.append({
            "id": action,
            "label": str(PUBLIC_ACTIONS[action]["label"]),
            "status": str(record.get("status", "pending")) if isinstance(record, dict) else "pending",
            "w1": url("w1_asset_id"),
            "w2": url("w2_asset_id"),
            "w3": url("w3_asset_id"),
            "frame_count": int(record.get("frame_count", 0) or 0) if isinstance(record, dict) else 0,
            "fps": int(record.get("fps", 12) or 12) if isinstance(record, dict) else 12,
            "prompts": deepcopy(record.get("prompts", {})) if isinstance(record, dict) else {},
        })
    return results


def component_build_progress(job: dict[str, Any]) -> dict[str, Any]:
    """Translate private build logs into a stable public progress contract."""

    status = str(job.get("status", "queued"))
    if status == "succeeded":
        return {"progress": 100, "stage": "Компонент готов"}
    if status == "queued":
        return {"progress": 0, "stage": "Ожидаем запуска"}

    actions = normalize_component_actions((job.get("params") or {}).get("actions"))
    log = str(job.get("log_text", ""))
    params = job.get("params") or {}
    rerun_action = str(params.get("rerun_action", "") or "")
    start_step = str(params.get("start_step", "w1") or "w1")
    if rerun_action:
        label = str(PUBLIC_ACTIONS.get(rerun_action, {}).get("label", rerun_action))
        if "RESULT_JSON:" in log or "Published " + rerun_action in log:
            return {"progress": 98, "stage": f"Публикуем: {label}"}

        w1_done = 'STAGE_JSON: {"stage": "w1"' in log
        w2_done = 'STAGE_JSON: {"stage": "w2"' in log
        w3_started = "[PIPE/W3]" in log
        progress_lines = [line for line in log.splitlines() if line.startswith("PROGRESS_JSON:")]
        if progress_lines:
            try:
                live_events = [json.loads(line.split(":", 1)[1].strip()) for line in progress_lines]
                live = live_events[-1]
                live_stage = str(live.get("stage", ""))
                latest_progress_offset = log.rfind("PROGRESS_JSON:")
                later_stage_markers = {
                    "w1": "[PIPE/W2]",
                    "w2": "[PIPE/W3]",
                }
                later_marker = later_stage_markers.get(live_stage)
                if later_marker and log.rfind(later_marker) > latest_progress_offset:
                    live_stage = ""
                # Comfy reports 0..100 again for every retry/node. Keep the
                # displayed value monotonic while the same W step is active.
                local_percent = max(
                    (
                        float(event.get("percent", 0))
                        for event in live_events
                        if str(event.get("stage", "")) == live_stage
                    ),
                    default=0.0,
                )
                local = max(0.0, min(100.0, local_percent)) / 100.0
                ranges = {
                    "w1": (5, 30),
                    "w2": ((34 if start_step == "w1" else 8), 78),
                    "w3": (84, 96),
                }
                if live_stage in ranges:
                    lower, upper = ranges[live_stage]
                    overall = round(lower + (upper - lower) * local)
                    titles = {"w1": "Ключевой кадр", "w2": "Видео", "w3": "Удаление фона"}
                    return {
                        "progress": overall,
                        "stage": f"{live_stage.upper()} · {titles[live_stage]}: {label}",
                        "active": {"action": rerun_action, "stage": live_stage},
                    }
            except (ValueError, TypeError, json.JSONDecodeError):
                pass
        if w3_started:
            section = log[log.rfind("[PIPE/W3]"):]
            waits = section.count("...waiting for")
            return {
                "progress": min(96, 84 + waits * 6),
                "stage": f"W3 · Удаляем фон: {label}",
                "active": {"action": rerun_action, "stage": "w3"},
            }
        if w2_done:
            return {"progress": 82, "stage": f"W3 · Подготавливаем: {label}"}

        if "[PIPE/W2]" in log:
            section = log[log.find("[PIPE/W2]"):]
            waits = section.count("...waiting for")
            attempts = section.count("[PIPE/W2]")
            base = 34 if start_step == "w1" else 8
            span = 44 if start_step == "w1" else 68
            progress = base + min(span, waits * 4 + max(0, attempts - 1) * 3)
            return {
                "progress": min(78, progress),
                "stage": f"W2 · Генерируем видео: {label}",
                "active": {"action": rerun_action, "stage": "w2"},
            }
        if w1_done:
            return {"progress": 32, "stage": f"W2 · Подготавливаем: {label}"}

        if "[PIPE/W1]" in log:
            section = log[log.find("[PIPE/W1]"):]
            waits = section.count("...waiting for")
            attempts = section.count("[PIPE/W1]")
            progress = 5 + min(25, waits * 6 + max(0, attempts - 1) * 3)
            return {
                "progress": progress,
                "stage": f"W1 · Генерируем кадр: {label}",
                "active": {"action": rerun_action, "stage": "w1"},
            }
        return {"progress": 2, "stage": f"Запускаем: {label}"}

    progress = 2
    stage = "Запускаем сборку"
    active: dict[str, str] | None = None
    if "Build 1/3:" in log:
        preparation_log = log.split("Build 1/3:", 1)[1].split(
            "Character base passed structural checks",
            1,
        )[0]
        preparation_waits = preparation_log.count("Waiting for ComfyUI prompt")
        progress = min(18, 5 + preparation_waits * 3)
        stage = "Готовим персонажа по референсу"
    if "Character base passed structural checks" in log:
        progress, stage = 20, "Основа персонажа готова"

    count = max(1, len(actions))
    span = 75.0 / count
    for index, action in enumerate(actions, start=1):
        start = 20.0 + (index - 1) * span
        label = str(PUBLIC_ACTIONS[action]["label"])
        generation_marker = f"Build 2/3 ({index}/{count}):"
        export_marker = f"Build 3/3 ({index}/{count}):"
        published_marker = f"Published {action}."
        if generation_marker in log:
            generation_log = log[log.rfind(generation_marker):]
            if export_marker in generation_log:
                generation_log = generation_log.split(export_marker, 1)[0]
            generation_waits = generation_log.count("Waiting for ComfyUI prompt")
            within_generation = span * min(0.38, generation_waits * 0.38 / 24.0)
            progress = max(progress, round(start + span * 0.12 + within_generation))
            stage = f"Создаём: {label}"
            active = {"action": action, "stage": "w1"}
            progress_lines = [line for line in generation_log.splitlines() if line.startswith("PROGRESS_JSON:")]
            if progress_lines:
                try:
                    live_events = [json.loads(line.split(":", 1)[1].strip()) for line in progress_lines]
                    live = live_events[-1]
                    live_stage = str(live.get("stage", "")).lower()
                    latest_progress_offset = generation_log.rfind("PROGRESS_JSON:")
                    marker_offsets = {
                        "w1": generation_log.rfind("[PIPE/W1]"),
                        "w2": generation_log.rfind("[PIPE/W2]"),
                        "w3": generation_log.rfind("[PIPE/W3]"),
                    }
                    marker_stage, marker_offset = max(marker_offsets.items(), key=lambda item: item[1])
                    marker_is_newer = marker_offset > latest_progress_offset
                    if marker_is_newer:
                        live_stage = marker_stage
                    local = max(0.0, min(100.0, max(
                        (
                            float(event.get("percent", 0))
                            for event in live_events
                            if not marker_is_newer and str(event.get("stage", "")).lower() == live_stage
                        ),
                        default=0.0,
                    )))
                    stage_ranges = {
                        "w1": (0.12, 0.38),
                        "w2": (0.40, 0.72),
                        "w3": (0.76, 0.94),
                    }
                    if live_stage in stage_ranges:
                        lower, upper = stage_ranges[live_stage]
                        progress = max(progress, round(start + span * (lower + (upper - lower) * local / 100.0)))
                        active = {"action": action, "stage": live_stage}
                        titles = {"w1": "Ключевой кадр", "w2": "Видео", "w3": "Анимация"}
                        stage = f"{live_stage.upper()} · {titles[live_stage]}: {label}"
                except (ValueError, TypeError, json.JSONDecodeError):
                    pass
        marker_offset = log.rfind(generation_marker)
        if marker_offset >= 0 and "Continuity QC pass" in log[marker_offset:]:
            progress = max(progress, round(start + span * 0.58))
            stage = f"Проверяем: {label}"
        if export_marker in log:
            export_log = log[log.rfind(export_marker):]
            if published_marker in export_log:
                export_log = export_log.split(published_marker, 1)[0]
            export_waits = export_log.count("Waiting for ComfyUI prompt")
            within_export = span * min(0.22, export_waits * 0.22 / 6.0)
            progress = max(progress, round(start + span * 0.68 + within_export))
            stage = f"Делаем прозрачный фон: {label}"
            active = {"action": action, "stage": "w3"}
        if published_marker in log:
            progress = max(progress, round(start + span))
            stage = f"Готово: {label}"
            active = None

    if status in {"failed", "cancelled", "interrupted"}:
        stage = "Сборка остановлена"
    result: dict[str, Any] = {"progress": min(99, int(progress)), "stage": stage}
    if active and status in {"running", "cancelling"}:
        result["active"] = active
    return result


def build_component_manifest(
    project: dict[str, Any],
    loadout_id: str | None = None,
    *,
    requested_actions: Iterable[Any] | None = None,
) -> dict[str, Any]:
    """Publish a self-contained browser contract with real media URLs.

    The authoring manifest intentionally stays asset-id based.  This public
    manifest is the boundary consumed by ``<animated-character>`` and never
    exposes W6/W8/W12 or project editing state.
    """

    assets = project.get("assets", {}) if isinstance(project.get("assets"), dict) else {}
    actions = normalize_component_actions(requested_actions)
    component_actions = (project.get("component") or {}).get("actions", {})
    legacy_only = all(
        isinstance(component_actions.get(action), dict)
        and component_actions[action].get("status") == "ready"
        for action in actions
    )
    if legacy_only:
        selected = str(loadout_id or project.get("active_loadout_id", "default"))
        runtime = {"loadout_id": selected, "anchor": {"canvas": {"width": 512, "height": 512}}}
        body_clips: dict[str, Any] = {}
    else:
        runtime = build_runtime_manifest(project, loadout_id)
        selected = str(runtime["loadout_id"])
        body_clips = runtime.get("channels", {}).get("body", {}).get("clips", {})
    published: dict[str, dict[str, Any]] = {}

    for public_id in actions:
        spec = PUBLIC_ACTIONS[public_id]
        legacy = (project.get("component") or {}).get("actions", {}).get(public_id)
        if isinstance(legacy, dict) and legacy.get("status") == "ready":
            asset = assets.get(str(legacy.get("asset_id", "")))
            if not isinstance(asset, dict) or not asset.get("url"):
                raise ValueError(f"component media is missing: {public_id}")
            published[public_id] = {
                "id": public_id,
                "motion_id": public_id,
                "label": spec["label"],
                "src": str(asset["url"]),
                "frame_count": int(legacy.get("frame_count", 1)),
                "fps": int(legacy.get("fps", 12)),
                "playback": str(spec.get("playback", "loop")),
                "entry_frame": 0,
                "exit_frame": max(0, int(legacy.get("frame_count", 1)) - 1),
                "aliases": deepcopy(spec["aliases"]),
            }
            continue
        motion_id = str(spec["motion_id"])
        clip = body_clips.get(motion_id)
        if not isinstance(clip, dict):
            raise ValueError(f"component action is not runtime-ready: {public_id}")
        asset_id = str(clip.get("spritesheet_asset_id", ""))
        asset = assets.get(asset_id)
        if not isinstance(asset, dict) or not asset.get("url"):
            raise ValueError(f"component media is missing: {public_id}")
        motion = get_motion(motion_id) or {}
        action_record = {
            "id": public_id,
            "motion_id": motion_id,
            "label": spec["label"],
            "src": str(asset["url"]),
            "frame_count": int(clip["frame_count"]),
            "fps": int(motion.get("fps", 16) or 16),
            "playback": str(motion.get("playback", "loop")),
            "entry_frame": int(clip.get("entry_gate_frame", 0) or 0),
            "exit_frame": int(clip.get("exit_gate_frame", int(clip["frame_count"]) - 1)),
            "aliases": deepcopy(spec["aliases"]),
        }
        overlay_id = spec.get("overlay_id")
        if overlay_id:
            overlay = (project.get("component") or {}).get("overlays", {}).get(str(overlay_id))
            if not isinstance(overlay, dict) or overlay.get("status") != "ready":
                raise ValueError(f"component overlay is not ready: {public_id}")
            if overlay.get("anchor_asset_id") != runtime.get("anchor", {}).get("asset_id"):
                raise ValueError(f"component overlay is stale: {public_id}")
            overlay_asset = assets.get(str(overlay.get("asset_id", "")))
            if not isinstance(overlay_asset, dict) or not overlay_asset.get("url"):
                raise ValueError(f"component overlay media is missing: {public_id}")
            roi = overlay.get("roi") or {}
            action_record["overlay"] = {
                "src": str(overlay_asset["url"]),
                "x": int(roi.get("x", 0)),
                "y": int(roi.get("y", 0)),
                "width": int(roi.get("width", 0)),
                "height": int(roi.get("height", 0)),
            }
        published[public_id] = action_record

    default_action = "idle" if "idle" in published else next(iter(published))
    neutral_action = published[default_action]
    canvas = runtime.get("anchor", {}).get("canvas") or {}
    width, height = int(canvas.get("width", 0) or 0), int(canvas.get("height", 0) or 0)
    if published and all(
        isinstance((project.get("component") or {}).get("actions", {}).get(action), dict)
        for action in actions
    ):
        width = height = 512
    if width < 1 or height < 1:
        raise ValueError("component canvas is missing")
    if (width, height) != (512, 512):
        raise ValueError("public component canvas must be exactly 512x512")

    return {
        "schema": COMPONENT_SCHEMA,
        "id": str(project.get("id", "")),
        "revision": int(project.get("revision", 0) or 0),
        "loadout_id": selected,
        "canvas": {"width": width, "height": height},
        "default_action": default_action,
        "neutral": {
            "src": neutral_action["src"],
            "frame": int(neutral_action["entry_frame"]),
        },
        "actions": published,
    }
