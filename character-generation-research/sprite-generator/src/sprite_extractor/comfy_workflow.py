"""Minimal, resumable client for the local ComfyUI HTTP API."""

from __future__ import annotations

import copy
import json
import math
import mimetypes
import os
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from collections.abc import Sequence
from importlib import resources
from pathlib import Path
from typing import Any, Callable, Mapping

import yaml

from .io_utils import canonical_json, load_json, sha256_bytes, sha256_file

INPUT_NODE = "114"
STYLE_NODE = "343"
DUMMY_NODE = "283"
INITIAL_WIDTH_NODE = "244"
INITIAL_HEIGHT_NODE = "245"
SEED_NODE = "124"
MAX_SEED = 9_223_372_036_854_775_807
RUN_NODE = "92"
IDLE_NODE = "341"
JUMP_NODE = "362"
CROUCH_NODE = "379"
CROUCH_WALK_NODE = "424"
WALK_NODE = "456"
ORIGINAL_OUTPUT_NODES = {"run": RUN_NODE, "idle": IDLE_NODE}
FULL_OUTPUT_NODES = {
    **ORIGINAL_OUTPUT_NODES,
    "jump": JUMP_NODE,
    "crouch": CROUCH_NODE,
    "crouch_walk": CROUCH_WALK_NODE,
    "walk": WALK_NODE,
}
OUTPUT_TITLES = {
    "run": "Running Animation",
    "idle": "Idle Animation",
    "jump": "Jumping animation",
    "crouch": "Crouch animation",
    "crouch_walk": "Crouch walk",
    "walk": "Walk loop",
}


def bundled_workflow_path() -> Path:
    """Return the installed full-animation Minimax workflow resource path."""
    return Path(
        resources.files("sprite_extractor").joinpath(
            "workflows/Minimax H3 r2v Simplified - Full Sprite Animation.json"
        )
    )


def original_workflow_path() -> Path:
    """Return the installed running-and-idle-only Minimax workflow path."""
    return Path(
        resources.files("sprite_extractor").joinpath(
            "workflows/Minimax H3 Running and Idle - 4 directions.json"
        )
    )


def bundled_dummy_reference_path() -> Path:
    """Return the dummy four-view pose image required by both workflows."""
    return Path(
        resources.files("sprite_extractor").joinpath(
            "workflows/dummy_rembg_quarters_75_888888.png"
        )
    )


def bundled_dummy_view_paths() -> tuple[Path, ...]:
    """Return the bundled right/left/back/front dummy source images."""
    root = resources.files("sprite_extractor").joinpath("workflows/dummy-views")
    return tuple(
        Path(root.joinpath(name))
        for name in ("1-right.png", "2-left.png", "3-back.png", "4-front.png")
    )


def pixel_art_dummy_view_folder() -> Path:
    """Return the bundled pixel-art alternative to the default dummy views."""
    return Path(
        resources.files("sprite_extractor").joinpath(
            "workflows/dummy-views-pixel-art"
        )
    )


def dummy_view_paths(folder: str | Path | None = None) -> tuple[Path, ...]:
    """Resolve an ordered right/left/back/front dummy-image folder."""
    if folder is None:
        return bundled_dummy_view_paths()
    root = Path(folder).expanduser().resolve()
    if not root.is_dir():
        raise FileNotFoundError(f"dummy image folder does not exist: {root}")
    names = ("1-right.png", "2-left.png", "3-back.png", "4-front.png")
    paths = tuple(root / name for name in names)
    missing = [path.name for path in paths if not path.is_file()]
    if missing:
        raise ValueError(
            f"dummy image folder {root} is missing: {', '.join(missing)}"
        )
    return paths


def dummy_top_padding_pixels(height: int, pad_top_percent: float) -> int:
    """Convert additive dummy top padding from percent to rendered pixels."""
    if isinstance(height, bool) or not isinstance(height, int) or height <= 0:
        raise ValueError("sprite render height must be a positive integer")
    if (
        isinstance(pad_top_percent, bool)
        or not isinstance(pad_top_percent, (int, float))
        or not math.isfinite(pad_top_percent)
        or pad_top_percent < 0
    ):
        raise ValueError("pad_top_percent must be a nonnegative finite number")
    return round(height * float(pad_top_percent) / 100)


def render_dummy_reference(
    destination: str | Path,
    width: int,
    height: int,
    pad_top_percent: float = 0,
    dummy_image_folder: str | Path | None = None,
) -> Path:
    """Scale and fit dummy views, join them, then add top-only padding."""
    from PIL import Image

    if any(
        isinstance(value, bool) or not isinstance(value, int) or value <= 0
        for value in (width, height)
    ):
        raise ValueError("sprite render width and height must be positive integers")
    pad_top = dummy_top_padding_pixels(height, pad_top_percent)
    views = []
    background = None
    sources = dummy_view_paths(dummy_image_folder)
    resampling = (
        Image.Resampling.LANCZOS
        if dummy_image_folder is None
        else Image.Resampling.NEAREST
    )
    for source in sources:
        with Image.open(source) as opened:
            image = opened.convert("RGB")
        if dummy_image_folder is None and image.size != (404, 640):
            raise ValueError(f"bundled dummy view must be 404x640: {source}")
        color = image.getpixel((0, 0))
        if background is None:
            background = color
        elif color != background:
            raise ValueError("bundled dummy views must share one background color")
        scaled_width = round(image.width * 512 / image.height)
        image = image.resize((scaled_width, 512), resampling)
        panel = Image.new("RGB", (width, height), background)
        source_left = max(0, (image.width - width) // 2)
        source_top = max(0, (image.height - height) // 2)
        crop = image.crop(
            (
                source_left,
                source_top,
                source_left + min(width, image.width),
                source_top + min(height, image.height),
            )
        )
        destination_left = max(0, (width - image.width) // 2)
        destination_top = max(0, (height - image.height) // 2)
        panel.paste(crop, (destination_left, destination_top))
        views.append(panel)
    combined = Image.new("RGB", (width * 4, height + pad_top), background)
    for index, view in enumerate(views):
        combined.paste(view, (index * width, pad_top))
    target = Path(destination)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + ".working")
    combined.save(temporary, format="PNG")
    temporary.replace(target)
    return target


def workflow_output_nodes(graph: dict[str, Any]) -> dict[str, str]:
    """Identify the supported output profile and validate its exported nodes."""
    required = dict(ORIGINAL_OUTPUT_NODES)
    extended_nodes = (JUMP_NODE, CROUCH_NODE, CROUCH_WALK_NODE, WALK_NODE)
    if any(node_id in graph for node_id in extended_nodes) and not all(
        node_id in graph for node_id in extended_nodes
    ):
        raise ValueError(
            "full workflow must provide jump, crouch, crouch-walk, and walk outputs"
        )
    if all(node_id in graph for node_id in extended_nodes):
        required = dict(FULL_OUTPUT_NODES)
    for action, node_id in required.items():
        node = graph.get(node_id)
        if not isinstance(node, dict) or node.get("class_type") != "SaveVideo":
            raise ValueError(f"workflow node {node_id} must be SaveVideo")
        if node.get("_meta", {}).get("title") != OUTPUT_TITLES[action]:
            raise ValueError(
                f"workflow node {node_id} must have title {OUTPUT_TITLES[action]!r}"
            )
    return required


def default_workflow_config_path() -> Path:
    """Return the committed portable defaults shipped beside this tool."""
    checkout_path = Path(__file__).resolve().parents[2] / "config.default.yaml"
    if checkout_path.is_file():
        return checkout_path
    return Path(resources.files("sprite_extractor").joinpath("config.default.yaml"))


ConfigOverrides = str | Path | Sequence[str | Path] | Mapping[str, Any] | None


def user_workflow_config_path() -> Path:
    """Return the optional ignored per-checkout configuration path."""
    return default_workflow_config_path().with_name("config.yaml")


def _deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = _deep_merge(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


def _override_paths(paths: ConfigOverrides) -> list[Path]:
    if paths is None:
        return []
    if isinstance(paths, (str, Path)):
        return [Path(paths)]
    return [Path(path) for path in paths]


def _load_config_document(paths: ConfigOverrides = None) -> tuple[Path, dict[str, Any]]:
    """Merge defaults, optional config.yaml, then explicit override files."""
    if isinstance(paths, Mapping):
        # A resolved mapping is an immutable execution boundary.  In particular,
        # do not consult the mutable checkout config after a job was enqueued.
        return Path("<resolved-config>"), copy.deepcopy(dict(paths))
    default_path = default_workflow_config_path()
    layers = [default_path]
    user_path = user_workflow_config_path()
    if user_path.is_file():
        layers.append(user_path)
    layers.extend(_override_paths(paths))
    unique_layers: list[Path] = []
    seen: set[Path] = set()
    for layer in layers:
        resolved = layer.resolve()
        if resolved not in seen:
            seen.add(resolved)
            unique_layers.append(resolved)
    document: dict[str, Any] = {}
    for config_path in unique_layers:
        if not config_path.is_file():
            raise FileNotFoundError(config_path)
        try:
            layer = yaml.safe_load(config_path.read_text(encoding="utf-8"))
        except yaml.YAMLError as exc:
            raise ValueError(f"invalid workflow config {config_path}: {exc}") from exc
        if not isinstance(layer, dict):
            raise ValueError(f"{config_path} must contain a mapping")
        document = _deep_merge(document, layer)
    return unique_layers[-1], document


def _connected_node_ids(graph: dict[str, Any]) -> set[str]:
    """Return nodes upstream of the selected animation outputs."""
    pending = list(workflow_output_nodes(graph).values())
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
            if (
                isinstance(value, list)
                and len(value) == 2
                and isinstance(value[0], str)
                and value[0] in graph
            ):
                pending.append(value[0])
    return connected


def _configured_model_inputs(graph: dict[str, Any]) -> dict[tuple[str, str], str]:
    """Return safetensors leaves that influence either exported animation."""
    return {
        (node_id, input_name): value
        for node_id, node in graph.items()
        if node_id in _connected_node_ids(graph)
        and isinstance(node, dict)
        and isinstance(node.get("inputs"), dict)
        for input_name, value in node["inputs"].items()
        if isinstance(value, str) and value.endswith(".safetensors")
    }


def _load_model_config(path: ConfigOverrides = None) -> dict[tuple[str, str], str]:
    config_path, document = _load_config_document(path)
    models = document.get("workflow_models")
    if not isinstance(models, dict):
        raise ValueError(f"{config_path} must contain a workflow_models mapping")
    result: dict[tuple[str, str], str] = {}
    for node_id, inputs in models.items():
        if not isinstance(node_id, str) or not isinstance(inputs, dict):
            raise ValueError(
                f"{config_path} workflow_models entries must map node IDs to input mappings"
            )
        for input_name, value in inputs.items():
            if (
                not isinstance(input_name, str)
                or not isinstance(value, str)
                or not value.endswith(".safetensors")
            ):
                raise ValueError(
                    f"{config_path} model values must be .safetensors filenames"
                )
            result[node_id, input_name] = value
    return result


def configured_comfyui_url(config_path: ConfigOverrides = None) -> str:
    """Return the validated ComfyUI endpoint from config.yaml."""
    path, document = _load_config_document(config_path)
    value = document.get("comfyui_url")
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{path} must contain a nonempty comfyui_url")
    return _local_base_url(value)


def configured_generation_timeout(config_path: ConfigOverrides = None) -> float:
    """Return the positive finite ComfyUI timeout in seconds."""
    path, document = _load_config_document(config_path)
    value = document.get("generation_timeout")
    if (
        isinstance(value, bool)
        or not isinstance(value, (int, float))
        or not math.isfinite(value)
        or value <= 0
    ):
        raise ValueError(
            f"{path} generation_timeout must be a positive finite number of seconds"
        )
    return float(value)


def configured_seed(config_path: ConfigOverrides = None) -> int:
    """Return -1 for per-run randomness or a valid fixed ComfyUI seed."""
    path, document = _load_config_document(config_path)
    value = document.get("seed", -1)
    if (
        isinstance(value, bool)
        or not isinstance(value, int)
        or not -1 <= value <= MAX_SEED
    ):
        raise ValueError(
            f"{path} seed must be -1 or an integer from 0 through {MAX_SEED}"
        )
    return value


def configured_sprite_box_height(config_path: ConfigOverrides = None) -> int:
    """Return the configured square sprite-box height."""
    path, document = _load_config_document(config_path)
    value = document.get("sprite_box_height", 128)
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise ValueError(f"{path} sprite_box_height must be a positive integer")
    return value


def configured_sprite_render_size(
    config_path: ConfigOverrides = None,
) -> tuple[int, int]:
    """Return the configured per-view render width and height."""
    path, document = _load_config_document(config_path)
    width = document.get("sprite_render_width", 320)
    height = document.get("sprite_render_height", 512)
    if any(
        isinstance(value, bool) or not isinstance(value, int) or value <= 0
        for value in (width, height)
    ):
        raise ValueError(
            f"{path} sprite_render_width and sprite_render_height must be positive integers"
        )
    return width, height


def configured_pad_top_percent(config_path: ConfigOverrides = None) -> float:
    """Return additive dummy-only top padding as a percent of render height."""
    path, document = _load_config_document(config_path)
    value = document.get("pad_top_percent", 0)
    if (
        isinstance(value, bool)
        or not isinstance(value, (int, float))
        or not math.isfinite(value)
        or value < 0
    ):
        raise ValueError(f"{path} pad_top_percent must be a nonnegative finite number")
    return float(value)


def configured_dummy_image_folder(
    config_path: ConfigOverrides = None,
) -> Path | None:
    """Return the optional folder containing four ordered dummy views."""
    path, document = _load_config_document(config_path)
    value = document.get("dummy_image_folder")
    if value in (None, ""):
        return None
    if not isinstance(value, str):
        raise ValueError(f"{path} dummy_image_folder must be a path string or null")
    folder = Path(value).expanduser().resolve()
    try:
        dummy_view_paths(folder)
    except (FileNotFoundError, ValueError) as exc:
        raise ValueError(f"{path} dummy_image_folder is invalid: {exc}") from exc
    return folder


def configured_animation_frame_counts(
    config_path: ConfigOverrides = None,
) -> dict[str, int]:
    """Return selected frame counts for every multi-frame animation."""
    path, document = _load_config_document(config_path)
    values = document.get("animation_frames")
    expected = {"idle", "run", "walk", "jump", "crouch_walk"}
    if not isinstance(values, dict) or set(values) != expected:
        missing = sorted(
            expected - set(values or {}) if isinstance(values, dict) else expected
        )
        unknown = sorted(
            set(values or {}) - expected if isinstance(values, dict) else set()
        )
        details = ([f"missing {', '.join(missing)}"] if missing else []) + (
            [f"unknown {', '.join(unknown)}"] if unknown else []
        )
        raise ValueError(
            f"{path} animation_frames must define idle, run, walk, jump, and crouch_walk ({'; '.join(details)})"
        )
    if any(
        isinstance(value, bool) or not isinstance(value, int) or value < 2
        for value in values.values()
    ):
        raise ValueError(
            f"{path} animation_frames values must be integers of at least 2"
        )
    return {
        name: values[name] for name in ("idle", "run", "walk", "jump", "crouch_walk")
    }


def load_configured_workflow(
    path: str | Path, *, config_path: ConfigOverrides = None
) -> dict[str, Any]:
    """Load a graph and replace every safetensors input with its configured value."""
    source = load_json(path)
    if not isinstance(source, dict) or not all(
        isinstance(v, dict) for v in source.values()
    ):
        raise ValueError("workflow must be a ComfyUI API-format node mapping")
    configured_paths = {
        bundled_workflow_path().resolve(),
        original_workflow_path().resolve(),
    }
    if config_path is None and Path(path).resolve() not in configured_paths:
        return source
    configured = _load_model_config(config_path)
    workflow_models = _configured_model_inputs(source)
    if configured.keys() != workflow_models.keys():
        missing = sorted(
            "%s.%s" % key for key in workflow_models.keys() - configured.keys()
        )
        unknown = sorted(
            "%s.%s" % key for key in configured.keys() - workflow_models.keys()
        )
        details = ([f"missing {', '.join(missing)}"] if missing else []) + (
            [f"unknown {', '.join(unknown)}"] if unknown else []
        )
        raise ValueError(
            f"configuration must cover every workflow .safetensors input ({'; '.join(details)})"
        )
    for (node_id, input_name), value in configured.items():
        source[node_id]["inputs"][input_name] = value
    return source


class ComfyAPIError(RuntimeError):
    pass


class ComfyPromptRejected(ComfyAPIError):
    """ComfyUI definitively rejected a prompt before assigning an ID."""

    pass


def _local_base_url(value: str) -> str:
    parsed = urllib.parse.urlsplit(value.rstrip("/"))
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ValueError("ComfyUI URL must be an absolute HTTP(S) URL")
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError("ComfyUI URL must not contain credentials, query, or fragment")
    return value.rstrip("/")


def load_and_render_workflow(
    path: str | Path,
    uploaded_image: str,
    *,
    uploaded_dummy: str = "dummy_rembg_quarters_75_888888.png",
    render_width: int = 320,
    render_height: int = 512,
    neutral_idle: bool,
    seed: int,
    config_path: ConfigOverrides = None,
) -> tuple[dict[str, Any], dict[str, Any]]:
    """Return (source, rendered) API graphs, changing exactly the approved leaves."""
    source = load_configured_workflow(path, config_path=config_path)
    requirements = {
        INPUT_NODE: ("LoadImage", "Character Reference Image"),
        DUMMY_NODE: ("LoadImage", "Last Frame Pose"),
        INITIAL_WIDTH_NODE: ("JWInteger", "Integer"),
        INITIAL_HEIGHT_NODE: ("JWInteger", "Integer"),
        STYLE_NODE: ("PrimitiveBoolean", "Neutral Idle"),
        SEED_NODE: ("SeedNode", "Seed"),
    }
    for node_id, (class_type, title) in requirements.items():
        node = source.get(node_id)
        if not isinstance(node, dict) or node.get("class_type") != class_type:
            raise ValueError(f"workflow node {node_id} must be {class_type}")
        if node.get("_meta", {}).get("title") != title:
            raise ValueError(f"workflow node {node_id} must have title {title!r}")
        if not isinstance(node.get("inputs"), dict):
            raise ValueError(f"workflow node {node_id} has no inputs object")
    workflow_output_nodes(source)
    if (
        not isinstance(uploaded_image, str)
        or not uploaded_image
        or not isinstance(uploaded_dummy, str)
        or not uploaded_dummy
    ):
        raise ValueError("uploaded image names must be nonempty")
    if any(
        isinstance(value, bool) or not isinstance(value, int) or value <= 0
        for value in (render_width, render_height)
    ):
        raise ValueError("sprite render width and height must be positive integers")
    if isinstance(seed, bool) or not isinstance(seed, int) or not 0 <= seed <= MAX_SEED:
        raise ValueError(f"rendered seed must be an integer from 0 through {MAX_SEED}")
    rendered = copy.deepcopy(source)
    rendered[INPUT_NODE]["inputs"]["image"] = uploaded_image
    rendered[DUMMY_NODE]["inputs"]["image"] = uploaded_dummy
    rendered[INITIAL_WIDTH_NODE]["inputs"]["value"] = render_width * 4
    rendered[INITIAL_HEIGHT_NODE]["inputs"]["value"] = render_height
    rendered[STYLE_NODE]["inputs"]["value"] = bool(neutral_idle)
    rendered[SEED_NODE]["inputs"]["seed"] = seed
    allowed = {
        (INPUT_NODE, "inputs", "image"),
        (DUMMY_NODE, "inputs", "image"),
        (INITIAL_WIDTH_NODE, "inputs", "value"),
        (INITIAL_HEIGHT_NODE, "inputs", "value"),
        (STYLE_NODE, "inputs", "value"),
        (SEED_NODE, "inputs", "seed"),
    }
    unexpected = graph_change_paths(source, rendered) - allowed
    if unexpected:
        raise AssertionError(
            f"renderer changed unapproved workflow fields: {sorted(unexpected)!r}"
        )
    return source, rendered


def graph_change_paths(
    source: dict[str, Any], rendered: dict[str, Any]
) -> set[tuple[str, ...]]:
    changed: set[tuple[str, ...]] = set()

    def walk(a: Any, b: Any, path: tuple[str, ...]) -> None:
        if type(a) is not type(b):
            changed.add(path)
            return
        if isinstance(a, dict):
            if a.keys() != b.keys():
                changed.add(path)
                return
            for key in a:
                walk(a[key], b[key], path + (str(key),))
        elif isinstance(a, list):
            if len(a) != len(b):
                changed.add(path)
                return
            for index, (left, right) in enumerate(zip(a, b)):
                walk(left, right, path + (str(index),))
        elif a != b:
            changed.add(path)

    walk(source, rendered, ())
    return changed


class ComfyClient:
    def __init__(self, base_url: str, *, request_timeout: float = 60.0):
        self.base_url = _local_base_url(base_url)
        if request_timeout <= 0:
            raise ValueError("request_timeout must be positive")
        self.request_timeout = request_timeout

    def _request(
        self,
        path: str,
        *,
        data: bytes | None = None,
        headers: dict[str, str] | None = None,
    ) -> bytes:
        request = urllib.request.Request(
            self.base_url + path, data=data, headers=headers or {}
        )
        try:
            with urllib.request.urlopen(
                request, timeout=self.request_timeout
            ) as response:
                return response.read()
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", "replace")
            if path == "/prompt" and exc.code == 400:
                try:
                    rejection = json.loads(detail)
                except json.JSONDecodeError:
                    rejection = None
                if isinstance(rejection, dict) and rejection.get("node_errors"):
                    raise ComfyPromptRejected(
                        f"prompt validation failed: {rejection['node_errors']!r}"
                    ) from exc
            raise ComfyAPIError(
                f"ComfyUI HTTP {exc.code} for {path}: {detail[:2000]}"
            ) from exc
        except (urllib.error.URLError, TimeoutError) as exc:
            raise ComfyAPIError(f"ComfyUI request failed for {path}: {exc}") from exc

    def _json(self, path: str, payload: Any | None = None) -> Any:
        data = (
            None
            if payload is None
            else json.dumps(payload, allow_nan=False).encode("utf-8")
        )
        raw = self._request(
            path,
            data=data,
            headers={"Content-Type": "application/json"} if data else None,
        )
        try:
            return json.loads(raw)
        except json.JSONDecodeError as exc:
            raise ComfyAPIError(f"ComfyUI returned invalid JSON for {path}") from exc

    def _post_allow_empty(self, path: str, payload: Any) -> Any | None:
        raw = self._request(
            path,
            data=json.dumps(payload, allow_nan=False).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )
        if not raw.strip():
            return None
        try:
            return json.loads(raw)
        except json.JSONDecodeError as exc:
            raise ComfyAPIError(f"ComfyUI returned invalid JSON for {path}") from exc

    def upload_image(self, source: str | Path) -> dict[str, str]:
        from .submission_journal import cached_upload, record_upload

        path = Path(source)
        if not path.is_file():
            raise FileNotFoundError(path)
        source_sha = sha256_file(path)
        prior = cached_upload(source_sha, self.base_url)
        if prior is not None:
            return prior
        safe = "".join(c if c.isalnum() or c in "._-" else "_" for c in path.name)
        remote = f"{sha256_file(path)[:16]}-{uuid.uuid4().hex}-{safe}"
        boundary = "----video-to-sprites-" + uuid.uuid4().hex
        mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        chunks: list[bytes] = []

        def field(name: str, value: str) -> None:
            chunks.extend(
                [
                    f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode()
                ]
            )

        field("type", "input")
        field("subfolder", "video-to-sprites")
        field("overwrite", "false")
        chunks.append(
            f'--{boundary}\r\nContent-Disposition: form-data; name="image"; filename="{remote}"\r\nContent-Type: {mime}\r\n\r\n'.encode()
        )
        chunks.append(path.read_bytes())
        chunks.append(b"\r\n")
        chunks.append(f"--{boundary}--\r\n".encode())
        response = json.loads(
            self._request(
                "/upload/image",
                data=b"".join(chunks),
                headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
            )
        )
        if not isinstance(response, dict) or not response.get("name"):
            raise ComfyAPIError(f"upload returned no image name: {response!r}")
        descriptor = {
            "name": str(response["name"]),
            "subfolder": str(response.get("subfolder", "")),
            "type": str(response.get("type", "input")),
        }
        record_upload(source_sha, self.base_url, descriptor)
        return descriptor

    def submit(self, graph: dict[str, Any], *, client_id: str | None = None) -> str:
        from .execution_hooks import (
            before_submission,
            graph_operation,
            report_activity,
            set_activity_operation,
        )

        before_submission(graph)
        operation = graph_operation(graph)
        set_activity_operation(operation)
        from .submission_journal import SubmissionRecoveryRequired, prepare, update

        identity, durable_client_id, record = prepare(
            graph, client_id, server=self.base_url
        )
        if record and record.get("prompt_id"):
            prompt_id = str(record["prompt_id"])
            report_activity(
                "queued",
                operation=operation,
                prompt_id=prompt_id,
                message="Using the recorded ComfyUI prompt",
            )
            return prompt_id
        if record and record.get("attempted"):
            recovered = self.find_prompt_by_client_id(durable_client_id)
            if recovered:
                update(identity, status="submitted", prompt_id=recovered)
                report_activity(
                    "queued",
                    operation=operation,
                    prompt_id=recovered,
                    message="Recovered the existing ComfyUI prompt",
                )
                return recovered
            update(identity, status="submission_unknown")
            report_activity(
                "unknown",
                operation=operation,
                message="The prior submission outcome is unknown",
                error={
                    "code": "submission_unknown",
                    "message": "The prior submission outcome is unknown; no duplicate was submitted",
                    "retryable": False,
                    "recovery_required": True,
                },
            )
            raise SubmissionRecoveryRequired(
                "prior ComfyUI submission outcome is unknown; refusing duplicate submission"
            )
        update(identity, status="submitting", attempted=True)
        report_activity(
            "submitting", operation=operation, message="Submitting work to ComfyUI"
        )
        try:
            response = self._json(
                "/prompt",
                {
                    "prompt": graph,
                    "client_id": durable_client_id,
                    "extra_data": {"extra_pnginfo": {"workflow": graph}},
                },
            )
        except ComfyPromptRejected as exc:
            update(
                identity,
                status="rejected",
                attempted=False,
                error="ComfyUI node validation rejected the prompt",
            )
            report_activity(
                "failed",
                operation=operation,
                message="ComfyUI rejected the work",
                error={
                    "code": "prompt_rejected",
                    "message": "ComfyUI node validation rejected the prompt",
                    "retryable": True,
                    "recovery_required": False,
                },
            )
            raise
        except BaseException as exc:
            update(identity, status="submission_unknown")
            report_activity(
                "unknown",
                operation=operation,
                message="The submission outcome is unknown",
                error={
                    "code": "submission_unknown",
                    "message": f"{type(exc).__name__}: {str(exc)[:900]}",
                    "retryable": False,
                    "recovery_required": True,
                },
            )
            raise
        if isinstance(response, dict) and response.get("prompt_id"):
            prompt_id = str(response["prompt_id"])
            update(identity, status="submitted", prompt_id=prompt_id)
            report_activity(
                "queued",
                operation=operation,
                prompt_id=prompt_id,
                message="ComfyUI accepted the work",
            )
            return prompt_id
        if isinstance(response, dict) and response.get("node_errors"):
            update(
                identity,
                status="rejected",
                attempted=False,
                error="ComfyUI node validation rejected the prompt",
            )
            report_activity(
                "failed",
                operation=operation,
                message="ComfyUI rejected the work",
                error={
                    "code": "prompt_rejected",
                    "message": "ComfyUI node validation rejected the prompt",
                    "retryable": True,
                    "recovery_required": False,
                },
            )
            raise ComfyPromptRejected(
                f"prompt validation failed: {response['node_errors']!r}"
            )
        update(
            identity, status="submission_unknown", error="ComfyUI returned no prompt ID"
        )
        report_activity(
            "unknown",
            operation=operation,
            message="ComfyUI returned no prompt ID",
            error={
                "code": "submission_unknown",
                "message": "ComfyUI returned no prompt ID; no duplicate will be submitted",
                "retryable": False,
                "recovery_required": True,
            },
        )
        raise ComfyAPIError(f"prompt submission outcome is unknown: {response!r}")

    def find_prompt_by_client_id(self, client_id: str) -> str | None:
        """Recover an ambiguously submitted prompt without resubmitting it."""

        def contains(value: Any) -> bool:
            if isinstance(value, dict):
                return value.get("client_id") == client_id or any(
                    contains(v) for v in value.values()
                )
            if isinstance(value, list):
                return any(contains(v) for v in value)
            return False

        queue = self._json("/queue")
        for item in [
            *(queue.get("queue_running", []) if isinstance(queue, dict) else []),
            *(queue.get("queue_pending", []) if isinstance(queue, dict) else []),
        ]:
            if contains(item) and isinstance(item, list) and len(item) > 1:
                return str(item[1])
        history = self._json("/history?max_items=1000")
        if isinstance(history, dict):
            for prompt_id, record in history.items():
                if contains(record):
                    return str(prompt_id)
        return None

    def history(self, prompt_id: str) -> dict[str, Any] | None:
        response = self._json("/history/" + urllib.parse.quote(prompt_id, safe=""))
        record = response.get(prompt_id) if isinstance(response, dict) else None
        return record if isinstance(record, dict) else None

    def wait(
        self,
        prompt_id: str,
        *,
        timeout: float = 3600.0,
        poll_interval: float = 2.0,
        required_nodes: set[str] | None = None,
        check_cancelled: Callable[[], None] | None = None,
    ) -> dict[str, Any]:
        from .execution_hooks import activity_enabled, report_activity

        if timeout <= 0 or poll_interval <= 0:
            raise ValueError("timeout and poll_interval must be positive")
        expected = (
            set(ORIGINAL_OUTPUT_NODES.values())
            if required_nodes is None
            else set(required_nodes)
        )
        deadline = time.monotonic() + timeout
        while True:
            if check_cancelled:
                check_cancelled()
            try:
                record = self.history(prompt_id)
            except ComfyAPIError as exc:
                report_activity(
                    "disconnected",
                    prompt_id=prompt_id,
                    message="Could not contact ComfyUI",
                    error={
                        "code": "comfy_disconnected",
                        "message": str(exc)[:1000],
                        "retryable": True,
                        "recovery_required": False,
                    },
                )
                raise
            if record is not None:
                status = record.get("status", {})
                messages = (
                    status.get("messages", []) if isinstance(status, dict) else []
                )
                terminal_errors = [
                    m
                    for m in messages
                    if isinstance(m, list)
                    and m
                    and m[0] in {"execution_error", "execution_interrupted"}
                ]
                if status.get("status_str") == "error" or terminal_errors:
                    detail = (
                        terminal_errors[-1][1]
                        if terminal_errors
                        and len(terminal_errors[-1]) > 1
                        and isinstance(terminal_errors[-1][1], dict)
                        else {}
                    )
                    parts = [
                        str(detail[key]).replace("\n", " ").replace("\r", " ")[:300]
                        for key in (
                            "node_type",
                            "node_id",
                            "exception_type",
                            "exception_message",
                        )
                        if detail.get(key) is not None
                    ]
                    public_message = ": ".join(parts) or "ComfyUI execution failed"
                    report_activity(
                        "failed",
                        prompt_id=prompt_id,
                        message="ComfyUI execution failed",
                        error={
                            "code": "execution_failed",
                            "message": public_message,
                            "retryable": False,
                            "recovery_required": False,
                        },
                    )
                    raise ComfyAPIError(
                        f"ComfyUI execution failed for {prompt_id}: {(terminal_errors[-1] if terminal_errors else status)!r}"
                    )
                outputs = record.get("outputs")
                if isinstance(outputs, dict) and expected <= set(outputs):
                    report_activity(
                        "completed",
                        prompt_id=prompt_id,
                        message="ComfyUI completed the work",
                    )
                    return record
                if status.get("completed") is True:
                    missing = sorted(expected - set(outputs or {}))
                    report_activity(
                        "failed",
                        prompt_id=prompt_id,
                        message="ComfyUI completed without required outputs",
                        error={
                            "code": "missing_outputs",
                            "message": f"Required output nodes were missing: {', '.join(missing)}",
                            "retryable": False,
                            "recovery_required": False,
                        },
                    )
                    raise ComfyAPIError(
                        f"ComfyUI prompt {prompt_id} completed without required output nodes {missing}"
                    )
            elif activity_enabled():
                try:
                    queue = self._json("/queue")
                except ComfyAPIError as exc:
                    report_activity(
                        "disconnected",
                        prompt_id=prompt_id,
                        message="Could not read the ComfyUI queue",
                        error={
                            "code": "comfy_disconnected",
                            "message": str(exc)[:1000],
                            "retryable": True,
                            "recovery_required": False,
                        },
                    )
                    raise
                running_items = (
                    queue.get("queue_running", []) if isinstance(queue, dict) else []
                )
                pending_items = (
                    queue.get("queue_pending", []) if isinstance(queue, dict) else []
                )
                running = any(
                    isinstance(item, list)
                    and len(item) > 1
                    and str(item[1]) == prompt_id
                    for item in running_items
                )
                pending = any(
                    isinstance(item, list)
                    and len(item) > 1
                    and str(item[1]) == prompt_id
                    for item in pending_items
                )
                state = "running" if running else "queued" if pending else "waiting"
                report_activity(
                    state,
                    prompt_id=prompt_id,
                    message={
                        "running": "ComfyUI is running the work",
                        "queued": "Waiting in the ComfyUI queue",
                        "waiting": "Waiting for ComfyUI history",
                    }[state],
                )
            if time.monotonic() >= deadline:
                report_activity(
                    "failed",
                    prompt_id=prompt_id,
                    message="Timed out waiting for ComfyUI",
                    error={
                        "code": "timeout",
                        "message": "Timed out waiting for ComfyUI to complete the work",
                        "retryable": True,
                        "recovery_required": False,
                    },
                )
                raise TimeoutError(f"timed out waiting for ComfyUI prompt {prompt_id}")
            time.sleep(min(poll_interval, max(0.0, deadline - time.monotonic())))

    @staticmethod
    def output_descriptors(
        record: dict[str, Any], node_id: str
    ) -> list[dict[str, str]]:
        node = record.get("outputs", {}).get(node_id)
        if not isinstance(node, dict):
            raise ComfyAPIError(f"history has no output for node {node_id}")
        candidates: list[dict[str, Any]] = []
        for value in node.values():
            if isinstance(value, list):
                candidates.extend(
                    v for v in value if isinstance(v, dict) and v.get("filename")
                )
            elif isinstance(value, dict) and value.get("filename"):
                candidates.append(value)
        return [
            {
                "filename": str(item["filename"]),
                "subfolder": str(item.get("subfolder", "")),
                "type": str(item.get("type", "output")),
            }
            for item in candidates
        ]

    @classmethod
    def output_descriptor(cls, record: dict[str, Any], node_id: str) -> dict[str, str]:
        candidates = cls.output_descriptors(record, node_id)
        if len(candidates) != 1:
            raise ComfyAPIError(
                f"node {node_id} returned {len(candidates)} downloadable artifacts; expected one"
            )
        return candidates[0]

    def download(self, descriptor: dict[str, str], destination: str | Path) -> Path:
        query = urllib.parse.urlencode(
            {key: descriptor.get(key, "") for key in ("filename", "subfolder", "type")}
        )
        target = Path(destination)
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_name(f".{target.name}.{uuid.uuid4().hex}.part")
        request = urllib.request.Request(self.base_url + "/view?" + query)
        try:
            with (
                urllib.request.urlopen(
                    request, timeout=self.request_timeout
                ) as response,
                temporary.open("xb") as handle,
            ):
                while block := response.read(1024 * 1024):
                    handle.write(block)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, target)
        except BaseException:
            temporary.unlink(missing_ok=True)
            raise
        return target

    def free_if_idle(self) -> bool:
        queue = self._json("/queue")
        if (
            not isinstance(queue, dict)
            or queue.get("queue_running")
            or queue.get("queue_pending")
        ):
            return False
        self._post_allow_empty("/free", {"unload_models": True})
        return True

    def wait_until_idle(
        self, *, timeout: float = 300.0, poll_interval: float = 2.0
    ) -> bool:
        deadline = time.monotonic() + timeout
        while True:
            queue = self._json("/queue")
            if (
                isinstance(queue, dict)
                and not queue.get("queue_running")
                and not queue.get("queue_pending")
            ):
                return True
            if time.monotonic() >= deadline:
                return False
            time.sleep(min(poll_interval, max(0.0, deadline - time.monotonic())))


def workflow_fingerprint(
    path: str | Path, *, config_path: ConfigOverrides = None
) -> str:
    """Fingerprint the effective workflow, including configured model names."""
    return sha256_bytes(
        canonical_json(load_configured_workflow(path, config_path=config_path))
    )
