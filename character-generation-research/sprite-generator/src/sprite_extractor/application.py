"""Shared planning and execution service used by the CLI-facing engine and web worker."""

from __future__ import annotations
import math, random
from dataclasses import replace
from pathlib import Path
from types import MappingProxyType
from typing import Any, Callable

from .animation_definitions import AnimationRegistry, GenerationSettings, load_registry
from .comfy_workflow import MAX_SEED
from .definition_runtime import (
    generate_definitions,
    package_definitions,
    plan_definitions,
)
from .execution_lock import output_tree_lock
from .execution_hooks import execution_hooks
from .runtime_config import ResolvedConfig
from .submission_journal import use_submission_journal

Progress = Callable[[str, dict[str, Any]], None]
StopCheck = Callable[[], bool]


class CooperativeStop(RuntimeError):
    pass


def _frame_defaults(
    config: dict[str, Any], registry: AnimationRegistry
) -> dict[str, int]:
    configured = config.get("animation_frames", {})
    return {
        name: int(
            configured.get(
                name,
                registry.stages[registry.action_stages[name]].animation.selection.frames
                or 1,
            )
        )
        for name in registry.actions
    }


def registry_for_request(
    style: str, overrides: dict[str, Any] | None = None
) -> AnimationRegistry:
    registry = load_registry(style=style)
    if not overrides:
        return registry
    stages = dict(registry.stages)
    for action, values in overrides.items():
        if action not in registry.action_stages:
            raise ValueError(f"unknown animation override {action}")
        stage_name = registry.action_stages[action]
        stage = stages[stage_name]
        generation = stage.generation
        if not isinstance(values, dict) or set(values) - {"duration_seconds", "fps"}:
            raise ValueError(f"invalid animation override for {action}")
        duration = values.get("duration_seconds", generation.duration_seconds)
        fps = values.get("fps", generation.fps)
        if (
            isinstance(duration, bool)
            or not isinstance(duration, (int, float))
            or not math.isfinite(duration)
            or duration <= 0
        ):
            raise ValueError(f"{action} duration_seconds must be positive and finite")
        if (
            isinstance(fps, bool)
            or not isinstance(fps, (int, float))
            or not math.isfinite(fps)
            or fps <= 0
        ):
            raise ValueError(f"{action} fps must be positive and finite")
        stages[stage_name] = replace(
            stage,
            generation=replace(
                generation, duration_seconds=float(duration), fps=float(fps)
            ),
        )
    return replace(registry, stages=MappingProxyType(stages))


def normalize_request(
    raw: dict[str, Any],
    config: ResolvedConfig,
    *,
    resolve_random: bool = False,
    registry: AnimationRegistry | None = None,
) -> tuple[dict[str, Any], AnimationRegistry]:
    if not isinstance(raw, dict):
        raise ValueError("request must be an object")
    style = raw.get("style", "neutral")
    registry = registry or registry_for_request(style, raw.get("animation_overrides"))
    actions = registry.resolve_actions(raw.get("actions"))
    if not actions:
        raise ValueError("at least one animation must be selected")
    doc = config.as_dict()
    defaults = _frame_defaults(doc, registry)
    supplied = raw.get("frame_counts", {})
    if not isinstance(supplied, dict):
        raise ValueError("frame_counts must be an object")
    counts = {}
    for action in actions:
        policy = registry.stages[registry.action_stages[action]].animation.selection
        count = supplied.get(action, defaults[action])
        if (
            isinstance(count, bool)
            or not isinstance(count, int)
            or (policy.method == "single" and count != 1)
            or (policy.method != "single" and count < 2)
        ):
            raise ValueError(f"invalid frame count for {action}")
        counts[action] = count
    seed = raw.get("seed", {"mode": "random"})
    if not isinstance(seed, dict) or seed.get("mode") not in {"random", "fixed"}:
        raise ValueError("seed.mode must be random or fixed")
    if seed["mode"] == "fixed":
        value = seed.get("value")
        if not isinstance(value, str) or not value.isdecimal():
            raise ValueError("fixed seed must be a decimal string")
        seed_value = int(value)
        if seed_value > MAX_SEED:
            raise ValueError("fixed seed is outside the supported range")
    else:
        seed_value = random.randrange(MAX_SEED + 1) if resolve_random else -1
    generation = raw.get("generation", {})
    if not isinstance(generation, dict):
        raise ValueError("generation must be an object")
    configured_width = int(doc["sprite_render_width"])
    configured_height = int(doc["sprite_render_height"])
    width = generation.get("width", configured_width)
    height = generation.get("height", configured_height)
    padding = generation.get("pad_top_percent", doc.get("pad_top_percent", 0))
    sprite_size = raw.get("sprite_size", doc["sprite_box_height"])
    split = raw.get("split_method", "blobs")
    if any(
        isinstance(v, bool) or not isinstance(v, int) or v <= 0
        for v in (width, height, sprite_size)
    ):
        raise ValueError("sprite and generation dimensions must be positive integers")
    if (
        isinstance(padding, bool)
        or not isinstance(padding, (int, float))
        or not math.isfinite(padding)
        or padding < 0
    ):
        raise ValueError("pad_top_percent must be nonnegative and finite")
    if split not in {"blobs", "quarters"}:
        raise ValueError("split_method must be blobs or quarters")
    normalized = {
        "workspace_id": str(raw.get("workspace_id", "")),
        "actions": list(actions),
        "frame_counts": counts,
        "style": style,
        "seed": (
            {"mode": "fixed", "value": str(seed_value)}
            if resolve_random or seed["mode"] == "fixed"
            else {"mode": "random"}
        ),
        "sprite_size": sprite_size,
        "generation": {
            "width": width,
            "height": height,
            "pad_top_percent": float(padding),
        },
        "split_method": split,
        "animation_overrides": raw.get("animation_overrides", {}),
    }
    return normalized, registry


def plan_request(
    raw: dict[str, Any],
    config: ResolvedConfig,
    *,
    image: Path | None = None,
    output: Path | None = None,
) -> dict[str, Any]:
    request, registry = normalize_request(raw, config)
    g = request["generation"]
    fixed = request["seed"].get("value")
    plan_seed = int(fixed) if fixed is not None else -1
    plan = plan_definitions(
        registry,
        request["actions"],
        (),
        request["frame_counts"],
        output=output,
        image=image,
        width=g["width"],
        base_height=g["height"],
        pad_top_percent=g["pad_top_percent"],
        seed=plan_seed,
        workflow_config=config.as_dict(),
    )
    from .io_utils import canonical_json, sha256_bytes

    return {
        "request": request,
        "resolved_seed": fixed,
        "summary": {
            "animation_count": len(request["actions"]),
            "frames_per_direction": sum(request["frame_counts"].values()),
            "directions": 4,
        },
        "stages": [
            {
                "id": x["name"],
                "label": x["name"].replace("_", " ").title(),
                "reason": (
                    "selected"
                    if x["name"]
                    in {registry.action_stages[a] for a in request["actions"]}
                    else "dependency"
                ),
                "cache": x["cache"]["decision"],
                "dependencies": x["dependencies"],
                "generation": x["generation"],
            }
            for x in plan["stages"]
        ],
        "definition_snapshot": sha256_bytes(canonical_json(registry.provenance())),
        "config_snapshot": config.revision,
    }


def execute_request(
    request: dict[str, Any],
    config: ResolvedConfig,
    image: Path,
    output: Path,
    *,
    registry: AnimationRegistry | None = None,
    progress: Progress = lambda *_: None,
    should_stop: StopCheck = lambda: False,
    activity=None,
    cycle_analysis_callback=None,
) -> dict[str, Any]:
    normalized, loaded_registry = normalize_request(
        request, config, resolve_random=True, registry=registry
    )
    registry = registry or loaded_registry
    seed = int(normalized["seed"]["value"])
    g = normalized["generation"]
    with (
        output_tree_lock(output),
        use_submission_journal(output / "submission-journal.json"),
        execution_hooks(progress, should_stop, activity),
    ):
        if should_stop():
            raise CooperativeStop("stopped before generation")
        progress("preparing", {})
        preflight = plan_definitions(
            registry,
            normalized["actions"],
            (),
            normalized["frame_counts"],
            output=output,
            image=image,
            width=g["width"],
            base_height=g["height"],
            pad_top_percent=g["pad_top_percent"],
            seed=seed,
            workflow_config=config.as_dict(),
        )
        cached = sum(
            stage["cache"]["decision"] == "hit" for stage in preflight["stages"]
        )
        progress(
            "generating",
            {"total_stages": len(preflight["stages"]), "cached_stages": cached},
        )
        state = generate_definitions(
            image,
            output,
            registry,
            actions=normalized["actions"],
            seed=seed,
            idle_style=normalized["style"],
            sprite_render_width=g["width"],
            sprite_render_height=g["height"],
            pad_top_percent=g["pad_top_percent"],
            workflow_config=config.as_dict(),
            server=config.as_dict()["comfyui_url"],
            timeout=float(config.as_dict()["generation_timeout"]),
            progress=progress,
            should_stop=should_stop,
        )
        if should_stop():
            raise CooperativeStop("stopped after generation")
        progress("packaging", {})
        from .execution_hooks import set_activity_stage

        set_activity_stage(None)
        state = package_definitions(
            state,
            output,
            registry,
            actions=normalized["actions"],
            poses=(),
            frame_counts=normalized["frame_counts"],
            height=normalized["sprite_size"],
            split_algorithm=normalized["split_method"],
            server=config.as_dict()["comfyui_url"],
            config=config.as_dict(),
            timeout=float(config.as_dict()["generation_timeout"]),
            progress=progress,
            should_stop=should_stop,
            cycle_analysis_callback=cycle_analysis_callback,
        )
        if not state.get("complete"):
            failures = [
                item.get("error")
                for character in state.get("characters", [])
                for item in character.get("packages", {}).values()
                if item.get("status") == "failed" and item.get("error")
            ]
            raise RuntimeError(failures[-1] if failures else "package did not complete")
        return state
