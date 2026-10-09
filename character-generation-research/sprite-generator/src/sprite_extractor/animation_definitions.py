"""Versioned, portable animation-definition catalogs.

The loader is intentionally strict: catalogs are data, not a templating or
expression language.  An overlay replaces a complete stage and prompt paths
are resolved by the catalog which declared that stage.
"""
from __future__ import annotations

import hashlib
import json
import math
import re
from dataclasses import dataclass
from importlib import resources
from pathlib import Path
from types import MappingProxyType
from typing import Any, Iterable, Mapping

import yaml


IDENTIFIER = re.compile(r"^[a-z][a-z0-9_]*$")
ROOT_FIELDS = {"version", "action_order", "stages"}
STAGE_FIELDS = {"template", "inputs", "prompt", "generation", "outputs"}
INPUT_FIELDS = {"character", "pose", "dimensions"}
GENERATION_FIELDS = {"duration_seconds", "fps", "steps", "sampler", "scheduler", "denoise"}
OUTPUT_FIELDS = {"animation", "poses"}
ANIMATION_REQUIRED_FIELDS = {"name", "selection", "conceptual_loop", "webp_loop"}
ANIMATION_FIELDS = ANIMATION_REQUIRED_FIELDS | {"label", "description"}
SELECTION_FIELDS = {"method", "frames", "include_last", "frame"}
POSE_FIELDS = {"frame"}


class DefinitionError(ValueError):
    """A catalog is invalid and cannot safely be used."""


class _UniqueKeyLoader(yaml.SafeLoader):
    pass


def _construct_mapping(loader: yaml.Loader, node: yaml.MappingNode, deep: bool = False) -> dict[Any, Any]:
    result: dict[Any, Any] = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in result:
            mark = key_node.start_mark
            raise DefinitionError(f"{mark.name}:{mark.line + 1}: duplicate mapping key {key!r}")
        result[key] = loader.construct_object(value_node, deep=deep)
    return result


_UniqueKeyLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _construct_mapping)


@dataclass(frozen=True)
class ArtifactReference:
    source: str
    stage: str | None = None
    output: str | None = None
    kind: str = "image"

    def to_document(self) -> str | dict[str, str]:
        if self.source in {"source", "dummy"}:
            return self.source
        return {"stage": self.stage or "", "output": self.output or ""}


@dataclass(frozen=True)
class GenerationSettings:
    duration_seconds: float
    fps: float = 24.0
    steps: int | None = None
    sampler: str | None = None
    scheduler: str | None = None
    denoise: float | None = None

    @property
    def frame_length(self) -> int:
        base = max(5, round(self.duration_seconds * self.fps))
        return base + (5 - base % 17) % 17

    @property
    def effective_duration_seconds(self) -> float:
        return self.frame_length / self.fps

    def to_document(self) -> dict[str, Any]:
        result = {"duration_seconds": self.duration_seconds, "fps": self.fps}
        for name in ("steps", "sampler", "scheduler", "denoise"):
            value = getattr(self, name)
            if value is not None:
                result[name] = value
        return result


@dataclass(frozen=True)
class SelectionPolicy:
    method: str
    frames: int | None = None
    include_last: bool | None = None
    frame: str | int | None = None

    def to_document(self) -> dict[str, Any]:
        return {k: v for k, v in (("method", self.method), ("frames", self.frames),
                ("include_last", self.include_last), ("frame", self.frame)) if v is not None}


@dataclass(frozen=True)
class AnimationOutput:
    name: str
    selection: SelectionPolicy
    conceptual_loop: bool
    webp_loop: int | None
    label: str | None = None
    description: str | None = None

    def to_document(self) -> dict[str, Any]:
        result = {"name": self.name, "selection": self.selection.to_document(),
                  "conceptual_loop": self.conceptual_loop, "webp_loop": self.webp_loop}
        if self.label is not None:
            result["label"] = self.label
        if self.description is not None:
            result["description"] = self.description
        return result

    def identity_document(self) -> dict[str, Any]:
        """Return only fields that affect generated or packaged artifacts."""
        return {"name": self.name, "selection": self.selection.to_document(),
                "conceptual_loop": self.conceptual_loop, "webp_loop": self.webp_loop}


@dataclass(frozen=True)
class PoseOutput:
    name: str
    frame: str | int

    def to_document(self) -> dict[str, Any]:
        return {"frame": self.frame}


@dataclass(frozen=True)
class StageDefinition:
    name: str
    template: str
    inputs: Mapping[str, ArtifactReference]
    prompt: str
    prompt_variant: str | None
    generation: GenerationSettings
    animation: AnimationOutput | None
    poses: Mapping[str, PoseOutput]

    @property
    def dependencies(self) -> tuple[str, ...]:
        return tuple(dict.fromkeys(ref.stage for ref in self.inputs.values() if ref.stage))

    def to_document(self) -> dict[str, Any]:
        outputs: dict[str, Any] = {"poses": {name: pose.to_document() for name, pose in self.poses.items()}}
        if self.animation:
            outputs["animation"] = self.animation.to_document()
        return {"template": self.template,
                "inputs": {name: ref.to_document() for name, ref in self.inputs.items()},
                "prompt": {"inline": self.prompt}, "generation": self.generation.to_document(),
                "outputs": outputs}

    def identity_document(self) -> dict[str, Any]:
        document = self.to_document()
        if self.animation:
            document["outputs"]["animation"] = self.animation.identity_document()
        return document


@dataclass(frozen=True)
class AnimationRegistry:
    stages: Mapping[str, StageDefinition]
    stage_order: tuple[str, ...]
    actions: tuple[str, ...]
    poses: tuple[str, ...]
    action_stages: Mapping[str, str]
    pose_stages: Mapping[str, str]
    style: str

    @property
    def action_names(self) -> tuple[str, ...]:
        return self.actions

    @property
    def pose_names(self) -> tuple[str, ...]:
        return self.poses

    def resolve_actions(self, values: str | Iterable[str] | None) -> tuple[str, ...]:
        return _resolve_selection(values, self.actions, "actions")

    def resolve_poses(self, values: str | Iterable[str] | None) -> tuple[str, ...]:
        return _resolve_selection(values, self.poses, "poses")

    def dependency_plan(self, actions: Iterable[str] = (), poses: Iterable[str] = ()) -> tuple[str, ...]:
        wanted = {self.action_stages[name] for name in actions} | {self.pose_stages[name] for name in poses}
        pending = list(wanted)
        while pending:
            for dependency in self.stages[pending.pop()].dependencies:
                if dependency not in wanted:
                    wanted.add(dependency)
                    pending.append(dependency)
        return tuple(name for name in self.stage_order if name in wanted)

    def provenance(self) -> dict[str, Any]:
        return {"version": 1, "style": self.style, "action_order": list(self.actions),
                "stages": {name: self.stages[name].to_document() for name in self.stage_order}}

    def stage_identity(self, stage_name: str) -> str:
        document = self.stages[stage_name].identity_document()
        return hashlib.sha256(json.dumps(document, sort_keys=True, separators=(",", ":"),
            ensure_ascii=False).encode("utf-8")).hexdigest()

    def list_document(self) -> dict[str, Any]:
        return {
            "version": 1,
            "actions": [{"name": name, "stage": self.action_stages[name],
                         "label": self.stages[self.action_stages[name]].animation.label,
                         "description": self.stages[self.action_stages[name]].animation.description,
                         "selection": self.stages[self.action_stages[name]].animation.selection.to_document(),
                         "conceptual_loop": self.stages[self.action_stages[name]].animation.conceptual_loop,
                         "webp_loop": self.stages[self.action_stages[name]].animation.webp_loop}
                        for name in self.actions],
            "poses": [{"name": name, "stage": self.pose_stages[name],
                       "frame": self.stages[self.pose_stages[name]].poses[name].frame}
                      for name in self.poses],
        }


Registry = AnimationRegistry


def registry_from_snapshot(document: Mapping[str, Any]) -> AnimationRegistry:
    """Reconstruct a registry from a previously validated provenance snapshot."""
    if document.get("version") != 1 or document.get("style") not in {"neutral", "feminine"}:
        raise DefinitionError("unsupported animation definition snapshot")
    raw_stages = document.get("stages")
    if not isinstance(raw_stages, Mapping):
        raise DefinitionError("animation definition snapshot stages must be a mapping")
    style = str(document["style"])
    stages = {str(name): _parse_stage(str(name), dict(value), "definition snapshot", None, style)
              for name, value in raw_stages.items()}
    action_order = tuple(str(name) for name in document.get("action_order", ()))
    actions = {stage.animation.name: name for name, stage in stages.items() if stage.animation}
    poses = {pose: name for name, stage in stages.items() for pose in stage.poses}
    if set(action_order) != set(actions):
        raise DefinitionError("animation definition snapshot action order differs")
    return AnimationRegistry(MappingProxyType(stages), tuple(stages), action_order,
        tuple(poses), MappingProxyType(actions), MappingProxyType(poses), style)


def _fail(source: str, field: str, message: str) -> DefinitionError:
    return DefinitionError(f"{source}: {field}: {message}")


def _mapping(value: Any, source: str, field: str, allowed: set[str] | None = None) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise _fail(source, field, "must be a mapping")
    if not all(isinstance(key, str) for key in value):
        raise _fail(source, field, "mapping keys must be strings")
    if allowed is not None and (unknown := set(value) - allowed):
        raise _fail(source, field, "unknown fields: " + ", ".join(sorted(unknown)))
    return value


def _identifier(value: Any, source: str, field: str) -> str:
    if not isinstance(value, str) or not IDENTIFIER.fullmatch(value):
        raise _fail(source, field, "must match [a-z][a-z0-9_]*")
    return value


def _read_catalog(path: Path | None) -> tuple[dict[str, Any], str, Path | None]:
    if path is None:
        resource = resources.files("sprite_extractor").joinpath("animation-definitions.yaml")
        source = "built-in animation-definitions.yaml"
        text = resource.read_text(encoding="utf-8")
        base = None
    else:
        source = str(path)
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as exc:
            raise DefinitionError(f"{source}: cannot read catalog: {exc}") from exc
        base = path.parent
    try:
        value = yaml.load(text, Loader=_UniqueKeyLoader)
    except DefinitionError as exc:
        raise DefinitionError(f"{source}: {exc}") from exc
    except (OSError, yaml.YAMLError) as exc:
        raise DefinitionError(f"{source}: cannot load YAML: {exc}") from exc
    root = _mapping(value, source, "catalog", ROOT_FIELDS)
    if type(root.get("version")) is not int or root.get("version") != 1:
        raise _fail(source, "version", "only schema version 1 is supported")
    stages = _mapping(root.get("stages"), source, "stages")
    for name in stages:
        _identifier(name, source, f"stages.{name}")
    return root, source, base


def _prompt_text(value: Any, source: str, base: Path | None, field: str, style: str) -> tuple[str, str | None]:
    prompt = _mapping(value, source, field)
    if "variants" in prompt:
        if set(prompt) != {"variants"}:
            raise _fail(source, field, "variants cannot be combined with inline or file")
        variants = _mapping(prompt["variants"], source, field + ".variants")
        if set(variants) != {"neutral", "feminine"}:
            raise _fail(source, field + ".variants", "requires exactly neutral and feminine variants")
        resolved = {name: _prompt_text(variant, source, base, field + f".variants.{name}", name)[0]
                    for name, variant in variants.items()}
        text = resolved[style]
        return text, style
    if set(prompt) not in ({"inline"}, {"file"}):
        raise _fail(source, field, "must contain exactly one of inline or file")
    if "inline" in prompt:
        if not isinstance(prompt["inline"], str) or not prompt["inline"]:
            raise _fail(source, field + ".inline", "must be non-empty text")
        return prompt["inline"], None
    relative = prompt["file"]
    if not isinstance(relative, str) or not relative or Path(relative).is_absolute():
        raise _fail(source, field + ".file", "must be a non-empty relative path")
    try:
        if base is None:
            text = resources.files("sprite_extractor").joinpath(relative).read_text(encoding="utf-8")
        else:
            text = (base / relative).read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise _fail(source, field + ".file", f"cannot read {relative!r}: {exc}") from exc
    if not text:
        raise _fail(source, field + ".file", "prompt file is empty")
    return text, None


def _artifact(value: Any, source: str, field: str) -> ArtifactReference:
    if isinstance(value, str) and value in {"source", "dummy"}:
        return ArtifactReference(str(value))
    item = _mapping(value, source, field, {"stage", "output"})
    if set(item) != {"stage", "output"}:
        raise _fail(source, field, "stage references require stage and output")
    return ArtifactReference("stage", _identifier(item["stage"], source, field + ".stage"),
                             _identifier(item["output"], source, field + ".output"))


def _positive_number(value: Any, source: str, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value <= 0:
        raise _fail(source, field, "must be a positive finite number")
    return float(value)


def _parse_stage(name: str, value: Any, source: str, base: Path | None, style: str) -> StageDefinition:
    field = f"stages.{name}"
    item = _mapping(value, source, field, STAGE_FIELDS)
    if set(item) != STAGE_FIELDS:
        raise _fail(source, field, "requires template, inputs, prompt, generation, and outputs")
    template = item["template"]
    if not isinstance(template, str) or template not in {"initial_reference", "reference_video"}:
        raise _fail(source, field + ".template", "unsupported template")
    inputs_value = _mapping(item["inputs"], source, field + ".inputs", INPUT_FIELDS)
    required_inputs = {"character", "pose", "dimensions"}
    if set(inputs_value) != required_inputs:
        raise _fail(source, field + ".inputs", "requires character, pose, and dimensions")
    inputs = {key: _artifact(value, source, field + ".inputs." + key) for key, value in inputs_value.items()}
    if inputs["character"].source != "source":
        raise _fail(source, field + ".inputs.character", "must be source")
    if template == "initial_reference" and inputs["pose"].source != "dummy":
        raise _fail(source, field + ".inputs.pose", "initial_reference requires dummy")
    if template == "initial_reference" and inputs["dimensions"].source != "dummy":
        raise _fail(source, field + ".inputs.dimensions", "initial_reference requires dummy")
    prompt, variant = _prompt_text(item["prompt"], source, base, field + ".prompt", style)
    gen = _mapping(item["generation"], source, field + ".generation", GENERATION_FIELDS)
    if "duration_seconds" not in gen:
        raise _fail(source, field + ".generation", "duration_seconds is required")
    duration = _positive_number(gen["duration_seconds"], source, field + ".generation.duration_seconds")
    fps = _positive_number(gen.get("fps", 24), source, field + ".generation.fps")
    steps = gen.get("steps")
    if steps is not None and (isinstance(steps, bool) or not isinstance(steps, int) or steps <= 0):
        raise _fail(source, field + ".generation.steps", "must be a positive integer")
    for text_field in ("sampler", "scheduler"):
        if text_field in gen and (not isinstance(gen[text_field], str) or not gen[text_field]):
            raise _fail(source, field + ".generation." + text_field, "must be non-empty text")
    denoise = gen.get("denoise")
    if denoise is not None and (isinstance(denoise, bool) or not isinstance(denoise, (int, float)) or not math.isfinite(denoise) or not 0 <= denoise <= 1):
        raise _fail(source, field + ".generation.denoise", "must be between zero and one")
    generation = GenerationSettings(duration, fps, steps, gen.get("sampler"), gen.get("scheduler"), None if denoise is None else float(denoise))
    out = _mapping(item["outputs"], source, field + ".outputs", OUTPUT_FIELDS)
    animation = None
    if "animation" in out:
        anim = _mapping(out["animation"], source, field + ".outputs.animation", ANIMATION_FIELDS)
        if not ANIMATION_REQUIRED_FIELDS.issubset(anim):
            raise _fail(source, field + ".outputs.animation", "requires name, selection, conceptual_loop, and webp_loop")
        label = anim.get("label")
        if label is not None and (not isinstance(label, str) or not label.strip()):
            raise _fail(source, field + ".outputs.animation.label", "must be non-empty text")
        description = anim.get("description")
        if description is not None and not isinstance(description, str):
            raise _fail(source, field + ".outputs.animation.description", "must be text")
        selection_value = _mapping(anim["selection"], source, field + ".outputs.animation.selection", SELECTION_FIELDS)
        method = selection_value.get("method")
        if not isinstance(method, str) or method not in {"cycle", "uniform", "single"}:
            raise _fail(source, field + ".outputs.animation.selection.method", "must be cycle, uniform, or single")
        allowed = {"method", "frames"} if method == "cycle" else ({"method", "frames", "include_last"} if method == "uniform" else {"method", "frame"})
        if set(selection_value) - allowed:
            raise _fail(source, field + ".outputs.animation.selection", "fields do not match selection method")
        frames = selection_value.get("frames")
        if method != "single" and (isinstance(frames, bool) or not isinstance(frames, int) or frames < 2):
            raise _fail(source, field + ".outputs.animation.selection.frames", "must be an integer of at least two")
        include_last = selection_value.get("include_last")
        if method == "uniform" and not isinstance(include_last, bool):
            raise _fail(source, field + ".outputs.animation.selection.include_last", "must be boolean")
        frame = selection_value.get("frame")
        if method == "single" and not ((isinstance(frame, str) and frame in {"first", "last"}) or isinstance(frame, int) and not isinstance(frame, bool) and frame >= 0):
            raise _fail(source, field + ".outputs.animation.selection.frame", "must be first, last, or a non-negative integer")
        if not isinstance(anim["conceptual_loop"], bool):
            raise _fail(source, field + ".outputs.animation.conceptual_loop", "must be boolean")
        webp_loop = anim["webp_loop"]
        if webp_loop is None and method != "single":
            raise _fail(source, field + ".outputs.animation.webp_loop", "may be null only for a single-frame output")
        if webp_loop is not None and (isinstance(webp_loop, bool) or not isinstance(webp_loop, int) or not 0 <= webp_loop <= 65535):
            raise _fail(source, field + ".outputs.animation.webp_loop", "must be null or an integer from 0 through 65535")
        animation = AnimationOutput(_identifier(anim["name"], source, field + ".outputs.animation.name"),
            SelectionPolicy(method, frames, include_last, frame), anim["conceptual_loop"], webp_loop,
            label.strip() if label is not None else None, description)
    pose_values = _mapping(out.get("poses", {}), source, field + ".outputs.poses")
    poses: dict[str, PoseOutput] = {}
    for pose_name, raw_pose in pose_values.items():
        pose_name = _identifier(pose_name, source, field + ".outputs.poses")
        pose = _mapping(raw_pose, source, field + f".outputs.poses.{pose_name}", POSE_FIELDS)
        if set(pose) != {"frame"}:
            raise _fail(source, field + f".outputs.poses.{pose_name}", "frame is required")
        frame = pose["frame"]
        if not ((isinstance(frame, str) and frame in {"first", "last"}) or isinstance(frame, int) and not isinstance(frame, bool) and frame >= 0):
            raise _fail(source, field + f".outputs.poses.{pose_name}.frame", "must be first, last, or a non-negative integer")
        poses[pose_name] = PoseOutput(pose_name, frame)
    return StageDefinition(name, template, MappingProxyType(inputs), prompt, variant, generation,
                           animation, MappingProxyType(poses))


def _resolve_selection(value: str | Iterable[str] | None, allowed: tuple[str, ...], option: str) -> tuple[str, ...]:
    if value is None:
        return ()
    raw = value.split(",") if isinstance(value, str) else value
    requested = {str(item).strip().replace("-", "_") for item in raw if str(item).strip()}
    unknown = sorted(requested - set(allowed))
    if unknown:
        raise DefinitionError(f"{option} contains unknown names: {', '.join(unknown)}")
    return tuple(name for name in allowed if name in requested)


def load_registry(definition_paths: Iterable[str | Path] | None = None, *, style: str = "neutral") -> AnimationRegistry:
    if not isinstance(style, str) or style not in {"neutral", "feminine"}:
        raise DefinitionError("style must be neutral or feminine")
    layers = [_read_catalog(None)]
    layers.extend(_read_catalog(Path(path).resolve()) for path in (definition_paths or ()))
    stage_records: dict[str, tuple[Any, str, Path | None]] = {}
    action_order: list[str] = []
    action_order_source = layers[0][1]
    for root, source, base in layers:
        if "action_order" in root:
            raw_order = root["action_order"]
            if not isinstance(raw_order, list):
                raise _fail(source, "action_order", "must be a list")
            action_order = [_identifier(name, source, "action_order") for name in raw_order]
            action_order_source = source
            if len(action_order) != len(set(action_order)):
                raise _fail(source, "action_order", "contains duplicates")
        for name, value in root["stages"].items():
            stage_records[name] = (value, source, base)
    stages = {name: _parse_stage(name, value, source, base, style)
              for name, (value, source, base) in stage_records.items()}
    actions: dict[str, str] = {}
    poses: dict[str, str] = {}
    for name, stage in stages.items():
        if stage.animation:
            if stage.animation.name in actions:
                source = stage_records[name][1]
                raise _fail(source, f"stages.{name}.outputs.animation.name",
                            f"duplicate public animation {stage.animation.name!r}")
            actions[stage.animation.name] = name
        for pose in stage.poses:
            if pose in poses:
                source = stage_records[name][1]
                raise _fail(source, f"stages.{name}.outputs.poses.{pose}",
                            f"duplicate public pose {pose!r}")
            poses[pose] = name
    for name, stage in stages.items():
        for input_name, ref in stage.inputs.items():
            if ref.stage:
                if ref.stage not in stages:
                    source = stage_records[name][1]
                    raise _fail(source, f"stages.{name}.inputs.{input_name}",
                                f"stage {name!r} input {input_name!r} references unknown stage {ref.stage!r}")
                if ref.output not in stages[ref.stage].poses:
                    source = stage_records[name][1]
                    raise _fail(source, f"stages.{name}.inputs.{input_name}.output",
                                f"stage {name!r} input {input_name!r} references unknown image output {ref.stage}.{ref.output}")
    visiting: set[str] = set()
    visited: set[str] = set()
    ordered: list[str] = []
    def visit(name: str, trail: tuple[str, ...] = ()) -> None:
        if name in visiting:
            source = stage_records[name][1]
            raise _fail(source, f"stages.{name}.inputs",
                        "dependency cycle: " + " -> ".join((*trail, name)))
        if name in visited:
            return
        visiting.add(name)
        for dependency in stages[name].dependencies:
            visit(dependency, (*trail, name))
        visiting.remove(name); visited.add(name); ordered.append(name)
    for name in stages:
        visit(name)
    unknown_order = set(action_order) - set(actions)
    if unknown_order:
        raise _fail(action_order_source, "action_order",
                    "action_order contains unknown animations: " + ", ".join(sorted(unknown_order)))
    ordered_actions = tuple(action_order + sorted(set(actions) - set(action_order)))
    ordered_poses = tuple(pose for stage_name in ordered for pose in stages[stage_name].poses)
    return AnimationRegistry(MappingProxyType(stages), tuple(ordered), ordered_actions, ordered_poses,
        MappingProxyType(actions), MappingProxyType(poses), style)


load_animation_registry = load_registry
