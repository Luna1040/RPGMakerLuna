"""ComfyUI-backed SDPose and background-removal workflow clients."""
from __future__ import annotations

import json
from collections import defaultdict
from importlib import resources
from pathlib import Path
from typing import Any, Iterable

from PIL import Image

from .comfy_workflow import ConfigOverrides, ComfyAPIError, ComfyClient, _load_config_document
from .io_utils import load_json

SDPOSE_OUTPUT_NODE = "4"
BACKGROUND_OUTPUT_NODE = "5"


def workflow_path(name: str) -> Path:
    return Path(resources.files("sprite_extractor").joinpath(f"workflows/{name}.json"))


def _connected_model_inputs(name: str, output_node: str) -> dict[tuple[str, str], str]:
    graph = load_json(workflow_path(name))
    pending = [output_node]
    connected: set[str] = set()
    while pending:
        node_id = pending.pop()
        if node_id in connected:
            continue
        node = graph.get(node_id)
        if not isinstance(node, dict) or not isinstance(node.get("inputs"), dict):
            continue
        connected.add(node_id)
        for value in node["inputs"].values():
            if isinstance(value, list) and len(value) == 2 and isinstance(value[0], str):
                pending.append(value[0])
    return {
        (node_id, input_name): value
        for node_id in connected
        for input_name, value in graph[node_id]["inputs"].items()
        if isinstance(value, str) and value.endswith(".safetensors")
    }


def _configured_postprocess_models(path: Path, document: dict[str, Any]) -> dict[tuple[str, str, str], str]:
    section = document.get("postprocess_workflow_models")
    if not isinstance(section, dict):
        raise ValueError(f"{path} must contain a postprocess_workflow_models mapping")
    configured: dict[tuple[str, str, str], str] = {}
    for workflow_name, nodes in section.items():
        if not isinstance(workflow_name, str) or not isinstance(nodes, dict):
            raise ValueError(f"{path} postprocess workflow entries must map node IDs to inputs")
        for node_id, inputs in nodes.items():
            if inputs is None:
                inputs = {}
            if not isinstance(node_id, str) or not isinstance(inputs, dict):
                raise ValueError(f"{path} postprocess workflow entries must map node IDs to inputs")
            for input_name, value in inputs.items():
                if not isinstance(input_name, str) or not isinstance(value, str) or not value.endswith(".safetensors"):
                    raise ValueError(f"{path} postprocess model paths must end in .safetensors")
                configured[workflow_name, node_id, input_name] = value
    expected = {
        (workflow_name, node_id, input_name): value
        for workflow_name, output_node in (("sdpose", SDPOSE_OUTPUT_NODE), ("background-removal", BACKGROUND_OUTPUT_NODE))
        for (node_id, input_name), value in _connected_model_inputs(workflow_name, output_node).items()
    }
    if configured.keys() != expected.keys():
        missing = sorted(".".join(key) for key in expected.keys() - configured.keys())
        unknown = sorted(".".join(key) for key in configured.keys() - expected.keys())
        details = ([f"missing {', '.join(missing)}"] if missing else []) + ([f"unknown {', '.join(unknown)}"] if unknown else [])
        raise ValueError(f"{path} must configure every postprocess workflow .safetensors input ({'; '.join(details)})")
    return configured


def postprocess_settings(config_path: ConfigOverrides = None) -> dict[str, Any]:
    path, document = _load_config_document(config_path)
    section = document.get("postprocess")
    if not isinstance(section, dict):
        raise ValueError(f"{path} must contain a postprocess mapping")
    batch_size = section.get("sdpose_batch_size")
    if not isinstance(batch_size, int) or isinstance(batch_size, bool) or batch_size <= 0:
        raise ValueError(f"{path} postprocess.sdpose_batch_size must be a positive integer")
    models = _configured_postprocess_models(path, document)
    return {
        "sdpose_checkpoint": models["sdpose", "2", "ckpt_name"],
        "background_removal_model": models["background-removal", "2", "bg_removal_name"],
        "sdpose_batch_size": batch_size,
    }


def _remote_name(upload: dict[str, str]) -> str:
    subfolder = upload.get("subfolder", "").strip("/\\")
    return f"{subfolder}/{upload['name']}" if subfolder else upload["name"]


def _batched_graph(name: str, uploads: list[dict[str, str]], consumer_node: str, consumer_input: str) -> dict[str, Any]:
    if not uploads:
        raise ValueError("ComfyUI batch requires at least one image")
    graph = load_json(workflow_path(name))
    graph["1"]["inputs"]["image"] = _remote_name(uploads[0])
    previous: list[Any] = ["1", 0]
    for index, upload in enumerate(uploads[1:], 1):
        load_id = str(1000 + index * 2)
        batch_id = str(1001 + index * 2)
        graph[load_id] = {
            "inputs": {"image": _remote_name(upload)},
            "class_type": "LoadImage",
            "_meta": {"title": f"Batch Input {index + 1}"},
        }
        graph[batch_id] = {
            "inputs": {"image1": previous, "image2": [load_id, 0]},
            "class_type": "ImageBatch",
            "_meta": {"title": f"Batch Images 1-{index + 1}"},
        }
        previous = [batch_id, 0]
    graph[consumer_node]["inputs"][consumer_input] = previous
    return graph


def render_sdpose_workflow(uploads: list[dict[str, str]], settings: dict[str, Any]) -> dict[str, Any]:
    graph = _batched_graph("sdpose", uploads, "3", "image")
    graph["2"]["inputs"]["ckpt_name"] = settings["sdpose_checkpoint"]
    graph["3"]["inputs"]["batch_size"] = settings["sdpose_batch_size"]
    return graph


def render_background_workflow(uploads: list[dict[str, str]], settings: dict[str, Any]) -> dict[str, Any]:
    graph = _batched_graph("background-removal", uploads, "3", "image")
    graph["2"]["inputs"]["bg_removal_name"] = settings["background_removal_model"]
    return graph


def _group_images_by_size(paths: list[Path]) -> list[tuple[tuple[int, int], list[tuple[int, Path]]]]:
    """Group images for ImageBatch without letting ComfyUI resize unlike inputs."""
    groups: dict[tuple[int, int], list[tuple[int, Path]]] = defaultdict(list)
    for index, path in enumerate(paths):
        with Image.open(path) as image:
            groups[image.size].append((index, path))
    return list(groups.items())


def _parse_pose_output(record: dict[str, Any]) -> list[dict[str, Any]]:
    output = record.get("outputs", {}).get(SDPOSE_OUTPUT_NODE)
    values = output.get("text") if isinstance(output, dict) else None
    if not isinstance(values, list) or not values:
        raise ComfyAPIError("SDPose workflow returned no keypoint JSON")
    value: Any = values[0] if len(values) == 1 else values
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except json.JSONDecodeError as exc:
            raise ComfyAPIError("SDPose workflow returned invalid keypoint JSON") from exc
    if not isinstance(value, list) or not all(isinstance(frame, dict) for frame in value):
        raise ComfyAPIError("SDPose workflow returned an unexpected keypoint payload")
    return value


def extract_sdpose(
    client: ComfyClient,
    images: Iterable[str | Path],
    *,
    config_path: ConfigOverrides = None,
    timeout: float = 7200.0,
    poll_interval: float = 2.0,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    paths = [Path(path) for path in images]
    settings = postprocess_settings(config_path)
    uploads = [client.upload_image(path) for path in paths]
    graph = render_sdpose_workflow(uploads, settings)
    prompt_id = client.submit(graph)
    record = client.wait(prompt_id, timeout=timeout, poll_interval=poll_interval, required_nodes={SDPOSE_OUTPUT_NODE})
    frames = _parse_pose_output(record)
    if len(frames) != len(paths):
        raise ComfyAPIError(f"SDPose returned {len(frames)} frames for {len(paths)} inputs")
    return frames, {"prompt_id": prompt_id, "workflow": workflow_path("sdpose").name, **settings}


def remove_background_masks(
    client: ComfyClient,
    images: Iterable[str | Path],
    destination: str | Path,
    *,
    config_path: ConfigOverrides = None,
    timeout: float = 7200.0,
    poll_interval: float = 2.0,
) -> tuple[list[Path], dict[str, Any]]:
    paths = [Path(path) for path in images]
    if not paths:
        raise ValueError("background removal requires at least one image")
    settings = postprocess_settings(config_path)
    folder = Path(destination)
    outputs: list[Path | None] = [None] * len(paths)
    batches = []
    for dimensions, indexed_paths in _group_images_by_size(paths):
        uploads = [client.upload_image(path) for _, path in indexed_paths]
        graph = render_background_workflow(uploads, settings)
        prompt_id = client.submit(graph)
        record = client.wait(
            prompt_id,
            timeout=timeout,
            poll_interval=poll_interval,
            required_nodes={BACKGROUND_OUTPUT_NODE},
        )
        descriptors = client.output_descriptors(record, BACKGROUND_OUTPUT_NODE)
        if len(descriptors) != len(indexed_paths):
            raise ComfyAPIError(
                f"background-removal workflow returned {len(descriptors)} masks "
                f"for {len(indexed_paths)} inputs of size {dimensions[0]}x{dimensions[1]}"
            )
        for (original_index, _), descriptor in zip(indexed_paths, descriptors):
            target = folder / f"mask-{original_index:04d}.png"
            outputs[original_index] = client.download(descriptor, target)
        batches.append({"prompt_id": prompt_id, "dimensions": list(dimensions), "count": len(indexed_paths)})
    if any(path is None for path in outputs):
        raise ComfyAPIError("background-removal workflow did not return every requested mask")
    return [path for path in outputs if path is not None], {
        "workflow": workflow_path("background-removal").name,
        "background_removal_model": settings["background_removal_model"],
        "batches": batches,
    }
