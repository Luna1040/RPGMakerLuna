"""Semantic contracts and rendering for animation workflow templates."""
from __future__ import annotations

import copy
import hashlib
import json
import math
import re
from dataclasses import dataclass
from importlib import resources
from pathlib import Path
from typing import Any, Mapping

from .animation_definitions import AnimationRegistry, DefinitionError, StageDefinition


BUILTIN_STAGES = frozenset({"run", "jump", "stop", "idle", "crouch", "crouch_start",
                            "crouch_walk", "walk_start", "walk"})
BUILTIN_VIDEO_TITLES = {"run": "Running Animation", "jump": "Jumping animation",
    "stop": "Stopping animation", "idle": "Idle Animation", "crouch": "Crouch animation",
    "crouch_start": "Stationary crouch to crouch walk", "crouch_walk": "Crouch walk",
    "walk_start": "Idle to walk", "walk": "Walk loop"}
TEMPLATE_IDS = ("initial_reference", "reference_video")


@dataclass(frozen=True)
class TemplateContract:
    template_id: str
    version: int
    required_inputs: tuple[str, ...]
    generation_fields: tuple[str, ...]
    video_class: str = "SaveVideo"


TEMPLATE_CONTRACTS = {
    name: TemplateContract(name, 1, ("character", "pose", "dimensions"),
        ("duration_seconds", "fps", "steps", "sampler", "scheduler", "denoise"))
    for name in TEMPLATE_IDS
}


def template_contract(template_id: str) -> TemplateContract:
    try:
        return TEMPLATE_CONTRACTS[template_id]
    except KeyError as exc:
        raise DefinitionError(f"unknown workflow template {template_id!r}") from exc


def template_path(template_id: str) -> Path:
    if template_id not in TEMPLATE_CONTRACTS:
        raise DefinitionError(f"unknown workflow template {template_id!r}")
    return Path(resources.files("sprite_extractor").joinpath(f"workflows/templates/{template_id}.json"))


def _load_graph(stage: StageDefinition) -> dict[str, Any]:
    path = resources.files("sprite_extractor").joinpath(f"workflows/templates/{stage.template}.json")
    return json.loads(path.read_text(encoding="utf-8"))


def _nodes(graph: Mapping[str, Any], class_type: str) -> list[tuple[str, dict[str, Any]]]:
    return [(node_id, node) for node_id, node in graph.items() if node.get("class_type") == class_type]


def _one_by_title(graph: Mapping[str, Any], class_type: str, title: str) -> tuple[str, dict[str, Any]]:
    found = [(node_id, node) for node_id, node in _nodes(graph, class_type)
             if node.get("_meta", {}).get("title") == title]
    if len(found) != 1:
        raise DefinitionError(f"template requires exactly one {class_type} / {title}")
    return found[0]


def _connected_model_leaves(graph: Mapping[str, Any]) -> set[tuple[str, str]]:
    output_ids = [node_id for node_id, _ in _nodes(graph, "SaveVideo")]
    reachable: set[str] = set()
    pending = list(output_ids)
    while pending:
        node_id = pending.pop()
        if node_id in reachable or node_id not in graph:
            continue
        reachable.add(node_id)
        for value in graph[node_id].get("inputs", {}).values():
            if isinstance(value, list) and len(value) == 2 and isinstance(value[0], str):
                pending.append(value[0])
    return {(node_id, input_name) for node_id in reachable
            for input_name, value in graph[node_id].get("inputs", {}).items()
            if isinstance(value, str) and value.endswith(".safetensors")}


def _validate_template_graph(graph: Mapping[str, Any], template_id: str) -> None:
    common = {"114": ("LoadImage", "Character Reference Image"),
              "124": ("SeedNode", "Seed")}
    if template_id == "initial_reference":
        required = {**common, "283": ("LoadImage", "Last Frame Pose"),
            "244": ("JWInteger", "Integer"), "245": ("JWInteger", "Integer"),
            "153": ("PrimitiveFloat", "Float (duration)"),
            "152": ("ComfyMathExpression", "Math Expression"),
            "254": ("ComfyMathExpression", "Math Expression"),
            "317": ("PrimitiveStringMultiline", "Text (Multiline)"),
            "242": ("MiniMaxH3ReferenceToVideo", "MiniMax H3 Reference to Video"),
            "249": ("RandomNoise", "RandomNoise"),
            "253": ("SamplerCustomAdvanced", "SamplerCustomAdvanced"),
            "251": ("KSamplerSelect", "KSamplerSelect"),
            "252": ("BasicScheduler", "BasicScheduler"),
            "151": ("CreateVideo", "Create Video"), "92": ("SaveVideo", "Running Animation")}
        links = {("242", "ref_images.ref_image_0"): ["114", 0],
                 ("242", "ref_images.ref_image_1"): ["283", 0],
                 ("242", "width"): ["244", 0], ("242", "height"): ["245", 0],
                 ("242", "prompt"): ["317", 0], ("242", "length"): ["152", 1],
                 ("252", "steps"): ["254", 1], ("249", "noise_seed"): ["124", 0],
                 ("253", "sampler"): ["251", 0], ("253", "sigmas"): ["252", 0],
                 ("151", "images"): ["146", 0], ("151", "audio"): ["145", 0],
                 ("92", "video"): ["151", 0]}
    else:
        required = {**common, "319": ("LoadImage", "Dependency: standing"),
            "380": ("LoadImage", "Dependency: crouch"),
            "382": ("PrimitiveFloat", "Float (duration)"),
            "381": ("ComfyMathExpression", "Math Expression"),
            "383": ("PrimitiveStringMultiline", "Text (Multiline)"),
            "384": ("MiniMaxH3ReferenceToVideo", "MiniMax H3 Reference to Video"),
            "387": ("RandomNoise", "RandomNoise"),
            "388": ("SamplerCustomAdvanced", "SamplerCustomAdvanced"),
            "389": ("GetImageSize", "Get Image Size"),
            "386": ("KSamplerSelect", "KSamplerSelect"),
            "297": ("BasicScheduler", "BasicScheduler"),
            "392": ("CreateVideo", "Create Video"),
            "394": ("SaveVideo", "Stationary crouch to crouch walk")}
        links = {("384", "ref_images.ref_image_0"): ["114", 0],
                 ("384", "ref_images.ref_image_1"): ["380", 0],
                 ("384", "width"): ["389", 0], ("384", "height"): ["389", 1],
                 ("384", "prompt"): ["383", 0], ("384", "length"): ["381", 1],
                 ("389", "image"): ["319", 0], ("297", "steps"): ["166", 0],
                 ("387", "noise_seed"): ["124", 0], ("388", "sampler"): ["386", 0],
                 ("388", "sigmas"): ["297", 0], ("392", "images"): ["391", 0],
                 ("392", "audio"): ["390", 0], ("394", "video"): ["392", 0]}
    for node_id, expected in required.items():
        node = graph.get(node_id)
        actual = (node.get("class_type"), node.get("_meta", {}).get("title")) if isinstance(node, dict) else None
        if actual != expected:
            raise DefinitionError(f"{template_id} node {node_id} must be {expected[0]} / {expected[1]}")
    for (node_id, input_name), expected in links.items():
        if graph[node_id].get("inputs", {}).get(input_name) != expected:
            raise DefinitionError(f"{template_id} binding {node_id}.{input_name} must be {expected}")
    duration_node = "152" if template_id == "initial_reference" else "381"
    expected_duration = "max(5, round(a * 24)) + (5 - (max(5, round(a * 24)) % 17)) % 17"
    if graph[duration_node].get("inputs", {}).get("expression") != expected_duration:
        raise DefinitionError(f"{template_id} duration expression does not match its versioned contract")
    if template_id == "initial_reference" and graph["254"].get("inputs", {}).get("expression") != "4":
        raise DefinitionError("initial_reference sampling-step expression does not match its versioned contract")


def _artifact_value(images: Mapping[Any, str], stage: StageDefinition, semantic: str) -> str:
    ref = stage.inputs[semantic]
    if ref.source == "source":
        for key in ("character", "source"):
            if key in images:
                return images[key]
    elif ref.source == "dummy":
        for key in ("dummy", "pose"):
            if key in images:
                return images[key]
    else:
        for key in ((ref.stage, ref.output), f"{ref.stage}.{ref.output}", ref.output, semantic):
            if key in images:
                return images[key]
    raise DefinitionError(f"stage {stage.name!r} requires image input {semantic!r}")


def render_stage_workflow(
    registry: AnimationRegistry,
    stage_name: str,
    *,
    character_image: str,
    dummy_image: str,
    artifact_images: Mapping[Any, str] | None = None,
    width: int,
    height: int,
    style: str | None = None,
    seed: int,
    model_config: Mapping[tuple[str, str], str] | None = None,
) -> dict[str, Any]:
    """Render only declared semantic leaves while retaining graph topology."""
    stage = registry.stages[stage_name]
    graph = copy.deepcopy(_load_graph(stage))
    _validate_template_graph(graph, stage.template)
    for node_id, node in graph.items():
        for input_name, value in node.get("inputs", {}).items():
            if isinstance(value, list) and len(value) == 2 and isinstance(value[0], str) and value[0] not in graph:
                raise DefinitionError(f"template node {node_id}.{input_name} has dangling link {value[0]}")
    images: dict[Any, str] = dict(artifact_images or {})
    images.update(character=character_image, source=character_image, dummy=dummy_image)
    _, character = _one_by_title(graph, "LoadImage", "Character Reference Image")
    character["inputs"]["image"] = character_image

    if stage.template == "initial_reference":
        _, pose_node = _one_by_title(graph, "LoadImage", "Last Frame Pose")
        pose_node["inputs"]["image"] = _artifact_value(images, stage, "pose")
        for title, value in (("Integer", width * 4),):
            candidates = [(nid, node) for nid, node in _nodes(graph, "JWInteger")
                          if node.get("_meta", {}).get("title") == title and nid in {"244"}]
            if candidates:
                candidates[0][1]["inputs"]["value"] = value
        if "245" in graph:
            graph["245"]["inputs"]["value"] = height
    else:
        pose_value = _artifact_value(images, stage, "pose")
        dimension_value = _artifact_value(images, stage, "dimensions")
        # reference_video has fixed semantic slots: 380 feeds the reference
        # image and 319 feeds GetImageSize. Their titles are descriptive only.
        pose_id, pose_node = "380", graph.get("380")
        dimension_id, dimension_node = "319", graph.get("319")
        if not isinstance(pose_node, dict) or not isinstance(dimension_node, dict):
            raise DefinitionError("reference_video template is missing semantic image bindings")
        pose_node["inputs"]["image"] = pose_value
        dimension_node["inputs"]["image"] = dimension_value
        for _, node in _nodes(graph, "GetImageSize"):
            node["inputs"]["image"] = [dimension_id, 0]

    # Prompt variants are resolved by the catalog. Updating every prompt leaf
    # also makes a single-prompt template safe for either style.
    prompt_nodes = _nodes(graph, "PrimitiveStringMultiline")
    if not prompt_nodes:
        raise DefinitionError("template has no prompt text input")
    for _, node in prompt_nodes:
        node["inputs"]["value"] = stage.prompt
    for _, node in _nodes(graph, "PrimitiveFloat"):
        if node.get("_meta", {}).get("title") == "Float (duration)":
            node["inputs"]["value"] = stage.generation.duration_seconds
    for _, node in _nodes(graph, "CreateVideo"):
        node["inputs"]["fps"] = stage.generation.fps
    for _, node in _nodes(graph, "ComfyMathExpression"):
        expression = node.get("inputs", {}).get("expression")
        if isinstance(expression, str) and "round(a *" in expression:
            fps = format(stage.generation.fps, "g")
            node["inputs"]["expression"] = f"max(5, round(a * {fps})) + (5 - (max(5, round(a * {fps})) % 17)) % 17"
    if stage.generation.steps is not None:
        for node_id, node in _nodes(graph, "JWInteger"):
            if node_id == "157" or node.get("_meta", {}).get("title") == "Sampling Steps":
                node["inputs"]["value"] = stage.generation.steps
        if stage.template == "initial_reference" and "254" in graph:
            graph["254"]["inputs"]["expression"] = str(stage.generation.steps)
    if stage.generation.sampler is not None:
        for _, node in _nodes(graph, "KSamplerSelect"):
            node["inputs"]["sampler_name"] = stage.generation.sampler
    for _, node in _nodes(graph, "BasicScheduler"):
        if stage.generation.scheduler is not None:
            node["inputs"]["scheduler"] = stage.generation.scheduler
        if stage.generation.denoise is not None:
            node["inputs"]["denoise"] = stage.generation.denoise
    if "124" in graph:
        graph["124"]["inputs"]["seed"] = seed
    selected_style = registry.style if style is None else style
    if selected_style not in {"neutral", "feminine"}:
        raise DefinitionError("style must be neutral or feminine")
    if "343" in graph:
        graph["343"]["inputs"]["value"] = selected_style == "neutral"
    video_nodes = _nodes(graph, "SaveVideo")
    if len(video_nodes) != 1:
        raise DefinitionError("template must have exactly one SaveVideo output")
    video_nodes[0][1].setdefault("_meta", {})["title"] = BUILTIN_VIDEO_TITLES.get(stage.name, stage.name)

    leaves = _connected_model_leaves(graph)
    if model_config is not None:
        supplied = set(model_config)
        if supplied != leaves:
            missing = leaves - supplied; unknown = supplied - leaves
            detail = []
            if missing: detail.append("missing " + ", ".join(f"{a}.{b}" for a, b in sorted(missing)))
            if unknown: detail.append("unknown " + ", ".join(f"{a}.{b}" for a, b in sorted(unknown)))
            raise DefinitionError("model configuration must exactly cover connected inputs (" + "; ".join(detail) + ")")
        for (node_id, input_name), value in model_config.items():
            graph[node_id]["inputs"][input_name] = value
    return graph


def output_contract(graph: Mapping[str, Any]) -> dict[str, Any]:
    videos = [node_id for node_id, _ in _nodes(graph, "SaveVideo")]
    poses = [node_id for node_id, _ in _nodes(graph, "SaveImage")]
    if len(videos) != 1:
        raise DefinitionError("rendered workflow must contain exactly one SaveVideo output")
    save_input = graph[videos[0]].get("inputs", {}).get("video")
    if not (isinstance(save_input, list) and len(save_input) == 2 and save_input[0] in graph):
        raise DefinitionError("SaveVideo must receive a connected video")
    create = graph[save_input[0]]
    image_input = create.get("inputs", {}).get("images")
    if create.get("class_type") != "CreateVideo" or not (
            isinstance(image_input, list) and len(image_input) == 2 and image_input[0] in graph):
        raise DefinitionError("SaveVideo must receive CreateVideo with connected images")
    return {"video_node": videos[0], "canonical_pose_nodes": poses,
            "decoded_image_nodes": [image_input[0]]}


def normalized_generation_document(graph: Mapping[str, Any]) -> dict[str, Any]:
    """Return a node-ID-independent expression tree for video generation."""
    video_ids = [node_id for node_id, _ in _nodes(graph, "SaveVideo")]
    if len(video_ids) != 1:
        raise DefinitionError("generation signature requires exactly one SaveVideo")
    active: set[str] = set()
    def scalar(value: Any) -> Any:
        if isinstance(value, float) and value.is_integer():
            return int(value)
        return value
    def node_expression(node_id: str, output_index: int = 0) -> Any:
        if node_id not in graph:
            raise DefinitionError(f"generation graph has dangling link to {node_id}")
        if node_id in active:
            raise DefinitionError(f"generation graph contains a cycle at {node_id}")
        active.add(node_id)
        node = graph[node_id]
        kind = node.get("class_type")
        inputs = node.get("inputs", {})
        def resolve(value: Any) -> Any:
            if isinstance(value, list) and len(value) == 2 and isinstance(value[0], str):
                return node_expression(value[0], value[1])
            return scalar(value)
        if kind in {"PrimitiveStringMultiline", "PrimitiveFloat", "PrimitiveBoolean", "JWInteger", "SeedNode"}:
            result = scalar(inputs.get("value", inputs.get("seed")))
        elif kind == "ComfySwitchNode":
            chosen = "on_true" if bool(resolve(inputs.get("switch"))) else "on_false"
            result = resolve(inputs[chosen])
        elif kind == "ComfyMathExpression":
            expression = inputs.get("expression")
            a = resolve(inputs.get("values.a")) if "values.a" in inputs else None
            if isinstance(expression, str) and expression.strip().isdigit():
                result = int(expression.strip())
            elif isinstance(expression, str) and isinstance(a, (int, float)) and (match := re.fullmatch(
                    r"max\(5, round\(a \* ([0-9]+(?:\.[0-9]+)?)\)\) \+ \(5 - \(max\(5, round\(a \* \1\)\) % 17\)\) % 17", expression)):
                fps = float(match.group(1))
                base = max(5, round(a * fps)); result = base + (5 - base % 17) % 17
            else:
                result = {"class": kind, "expression": expression,
                          "inputs": {key: resolve(value) for key, value in sorted(inputs.items()) if key != "expression"}}
        elif kind == "LoadImage":
            result = {"class": "LoadImage", "role": "character" if node.get("_meta", {}).get("title") == "Character Reference Image" else "artifact", "output": output_index}
        elif kind == "GetImageSize":
            result = {"class": kind, "role": "dimensions", "output": output_index,
                      "image": resolve(inputs.get("image"))}
        else:
            ignored = {"filename_prefix", "path", "filename", "video-preview"} if kind == "SaveVideo" else set()
            result = {"class": kind, "output": output_index,
                      "inputs": {key: resolve(value) for key, value in sorted(inputs.items()) if key not in ignored}}
        active.remove(node_id)
        return result
    return {"video": node_expression(video_ids[0])}


def normalized_generation_signature(graph: Mapping[str, Any]) -> str:
    encoded = json.dumps(normalized_generation_document(graph), sort_keys=True,
                         ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def legacy_stage_signature(stage_name: str, *, style: str = "neutral") -> str:
    if stage_name not in BUILTIN_STAGES:
        raise DefinitionError(f"unknown legacy stage {stage_name!r}")
    if style not in {"neutral", "feminine"}:
        raise DefinitionError("style must be neutral or feminine")
    graph = json.loads(resources.files("sprite_extractor").joinpath(
        f"workflows/staged/{stage_name}.json").read_text(encoding="utf-8"))
    if "343" in graph:
        graph["343"]["inputs"]["value"] = style == "neutral"
    return normalized_generation_signature(graph)


def template_identity(template_id: str) -> dict[str, Any]:
    path = template_path(template_id)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return {"template": template_id, "version": template_contract(template_id).version,
            "sha256": digest}
