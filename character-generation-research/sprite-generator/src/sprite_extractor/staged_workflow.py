"""Dependency-aware execution of the split full-animation ComfyUI workflows."""
from __future__ import annotations

import copy
import random
import uuid
from dataclasses import dataclass
from importlib import resources
from pathlib import Path
from typing import Any, Iterable

from .comfy_workflow import (
    DUMMY_NODE, INITIAL_HEIGHT_NODE, INITIAL_WIDTH_NODE, INPUT_NODE, MAX_SEED,
    SEED_NODE, STYLE_NODE, ComfyClient, ConfigOverrides, _load_model_config,
    configured_comfyui_url, configured_dummy_image_folder,
    configured_pad_top_percent, configured_seed, configured_sprite_render_size,
    dummy_top_padding_pixels, dummy_view_paths, render_dummy_reference,
)
from .generate_character import _slug, _uploaded_reference, image_inputs
from .io_utils import atomic_write_json, canonical_json, load_json, sha256_bytes, sha256_file


@dataclass(frozen=True)
class Stage:
    name: str
    dependencies: tuple[str, ...]
    dependency_inputs: tuple[tuple[str, str], ...]
    video_node: str
    pose_node: str
    pose: str
    action: str | None = None


STAGES: dict[str, Stage] = {
    "run": Stage("run", (), (), "92", "300", "run_first", "run"),
    "jump": Stage("jump", ("run",), (("359", "run_first"),), "362", "363", "jump_last", "jump"),
    "stop": Stage("stop", ("run",), (("287", "run_first"),), "309", "319", "standing"),
    "idle": Stage("idle", ("stop",), (("319", "standing"),), "341", "342", "idle_last", "idle"),
    "crouch": Stage("crouch", ("stop",), (("319", "standing"),), "379", "380", "crouch", "crouch"),
    "crouch_start": Stage("crouch_start", ("crouch",), (("380", "crouch"), ("319", "standing")), "394", "395", "crouch_walk_start"),
    "crouch_walk": Stage("crouch_walk", ("crouch_start",), (("395", "crouch_walk_start"), ("319", "standing")), "424", "425", "crouch_walk_last", "crouch_walk"),
    "walk_start": Stage("walk_start", ("stop",), (("319", "standing"),), "441", "442", "walk_start"),
    "walk": Stage("walk", ("walk_start",), (("442", "walk_start"), ("319", "standing")), "456", "457", "walk_last", "walk"),
}
ACTION_STAGES = {stage.action: name for name, stage in STAGES.items() if stage.action}
POSE_STAGES = {stage.pose: name for name, stage in STAGES.items()}
ACTION_ORDER = ("idle", "run", "jump", "crouch", "crouch_walk", "walk")
POSE_ORDER = tuple(POSE_STAGES)
STAGE_ORDER = tuple(STAGES)
STATE_VERSION = "2.0-staged"


def staged_workflow_path(stage: str) -> Path:
    if stage not in STAGES:
        raise ValueError(f"unknown stage {stage!r}")
    return Path(resources.files("sprite_extractor").joinpath(f"workflows/staged/{stage}.json"))


def parse_selection(value: str | Iterable[str] | None, allowed: Iterable[str], option: str) -> tuple[str, ...]:
    allowed_order = tuple(allowed)
    if value is None:
        return ()
    raw = value.split(",") if isinstance(value, str) else value
    requested = {str(item).strip().replace("-", "_") for item in raw if str(item).strip()}
    unknown = sorted(requested - set(allowed_order))
    if unknown:
        raise ValueError(f"{option} contains unknown names: {', '.join(unknown)}")
    return tuple(name for name in allowed_order if name in requested)


def dependency_plan(actions: Iterable[str] = (), poses: Iterable[str] = ()) -> tuple[str, ...]:
    needed = {ACTION_STAGES[name] for name in actions} | {POSE_STAGES[name] for name in poses}
    pending = list(needed)
    while pending:
        name = pending.pop()
        for dependency in STAGES[name].dependencies:
            if dependency not in needed:
                needed.add(dependency)
                pending.append(dependency)
    # Some graphs use standing for dimensions as well as their direct pose input.
    if needed & {"crouch_start", "crouch_walk", "walk"}:
        needed.add("stop")
        needed.add("run")
    return tuple(name for name in STAGE_ORDER if name in needed)


def _configured_stage_graph(stage: str, config: ConfigOverrides) -> dict[str, Any]:
    graph = load_json(staged_workflow_path(stage))
    configured = _load_model_config(config)
    leaves = {
        (node_id, input_name)
        for node_id, node in graph.items()
        for input_name, value in node.get("inputs", {}).items()
        if isinstance(value, str) and value.endswith(".safetensors")
    }
    if leaves != configured.keys():
        missing = leaves - configured.keys()
        unknown = configured.keys() - leaves
        detail = (["missing " + ", ".join(f"{a}.{b}" for a, b in sorted(missing))] if missing else []) + (["unknown " + ", ".join(f"{a}.{b}" for a, b in sorted(unknown))] if unknown else [])
        raise ValueError("configuration must exactly cover staged workflow model inputs (" + "; ".join(detail) + ")")
    for key in leaves:
        graph[key[0]]["inputs"][key[1]] = configured[key]
    return graph


def render_stage_workflow(stage: str, character_image: str, dummy_image: str, dependency_images: dict[str, str], *, width: int, height: int, neutral_idle: bool, seed: int, config: ConfigOverrides = None) -> dict[str, Any]:
    spec = STAGES[stage]
    graph = copy.deepcopy(_configured_stage_graph(stage, config))
    video_titles = {"run": "Running Animation", "jump": "Jumping animation", "stop": "Stopping animation", "idle": "Idle Animation", "crouch": "Crouch animation", "crouch_start": "Stationary crouch to crouch walk", "crouch_walk": "Crouch walk", "walk_start": "Idle to walk", "walk": "Walk loop"}
    for node, expected_class, expected_title in ((spec.video_node, "SaveVideo", video_titles[stage]), (spec.pose_node, "SaveImage", "Save Image")):
        actual = graph.get(node, {})
        if actual.get("class_type") != expected_class or actual.get("_meta", {}).get("title") != expected_title:
            raise ValueError(f"stage {stage} node {node} must be {expected_class} / {expected_title}")
    common_contracts = {
        INPUT_NODE: ("LoadImage", "Character Reference Image"),
        DUMMY_NODE: ("LoadImage", "Last Frame Pose"),
        INITIAL_WIDTH_NODE: ("JWInteger", "Integer"),
        INITIAL_HEIGHT_NODE: ("JWInteger", "Integer"),
        STYLE_NODE: ("PrimitiveBoolean", "Neutral Idle"),
        SEED_NODE: ("SeedNode", "Seed"),
    }
    for node_id, (expected_class, expected_title) in common_contracts.items():
        if node_id in graph and (graph[node_id].get("class_type"), graph[node_id].get("_meta", {}).get("title")) != (expected_class, expected_title):
            raise ValueError(f"stage {stage} node {node_id} must be {expected_class} / {expected_title}")
    for node_id, pose in spec.dependency_inputs:
        node = graph.get(node_id, {})
        if node.get("class_type") != "LoadImage" or node.get("_meta", {}).get("title") != f"Dependency: {pose}":
            raise ValueError(f"stage {stage} node {node_id} must be dependency input {pose}")
    leaves = {
        INPUT_NODE: ("image", character_image), DUMMY_NODE: ("image", dummy_image),
        INITIAL_WIDTH_NODE: ("value", width * 4), INITIAL_HEIGHT_NODE: ("value", height),
        STYLE_NODE: ("value", neutral_idle), SEED_NODE: ("seed", seed),
    }
    for node_id, (input_name, value) in leaves.items():
        if node_id in graph:
            graph[node_id]["inputs"][input_name] = value
    for node_id, pose in spec.dependency_inputs:
        if pose not in dependency_images:
            raise ValueError(f"stage {stage} requires dependency pose {pose}")
        graph[node_id]["inputs"]["image"] = dependency_images[pose]
    return graph


def plan_document(actions: Iterable[str], poses: Iterable[str], frame_counts: dict[str, int] | None = None) -> dict[str, Any]:
    actions, poses = tuple(actions), tuple(poses)
    stages = dependency_plan(actions, poses)
    return {
        "version": "1.0", "workflow": "staged", "actions": list(actions), "poses": list(poses),
        "frame_counts": {name: frame_counts[name] for name in actions if frame_counts and name in frame_counts},
        "stages": [{"name": name, "dependencies": list(STAGES[name].dependencies), "exports_action": STAGES[name].action if STAGES[name].action in actions else None, "exports_pose": STAGES[name].pose if STAGES[name].pose in poses else None} for name in stages],
    }


def generate_staged(
    image: str | Path, output: str | Path, *, actions: Iterable[str], poses: Iterable[str] = (),
    idle_style: str = "neutral", server: str | None = None, timeout: float = 7200,
    poll_interval: float = 2, sprite_render_width: int | None = None,
    sprite_render_height: int | None = None, pad_top_percent: float | None = None,
    dummy_image_folder: str | Path | None = None,
    seed: int | None = None, workflow_config: ConfigOverrides = None, dry_run: bool = False,
) -> dict[str, Any]:
    """Execute only the dependency closure and retain each completed stage."""
    if idle_style not in {"neutral", "feminine"}:
        raise ValueError("idle_style must be neutral or feminine")
    actions = parse_selection(actions, ACTION_ORDER, "actions")
    poses = parse_selection(poses, POSE_ORDER, "poses")
    if not actions and not poses:
        raise ValueError("staged workflow requires at least one action or pose")
    plan = plan_document(actions, poses)
    if dry_run:
        return plan
    sources = image_inputs(image)
    if not sources:
        raise ValueError("no recognized image files found")
    configured_width, configured_height = configured_sprite_render_size(workflow_config)
    width = configured_width if sprite_render_width is None else sprite_render_width
    base_height = configured_height if sprite_render_height is None else sprite_render_height
    padding = configured_pad_top_percent(workflow_config) if pad_top_percent is None else pad_top_percent
    resolved_dummy_folder = configured_dummy_image_folder(workflow_config) if dummy_image_folder is None else Path(dummy_image_folder).expanduser().resolve()
    height = base_height + dummy_top_padding_pixels(base_height, padding)
    requested_seed = configured_seed(workflow_config) if seed is None else seed
    if isinstance(requested_seed, bool) or not isinstance(requested_seed, int) or not -1 <= requested_seed <= MAX_SEED:
        raise ValueError(f"seed must be -1 or an integer from 0 through {MAX_SEED}")
    destination = Path(output).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    state_path = destination / "staged-generation-state.json"
    source_records = [{"name": source.stem, "source": str(source), "source_sha256": sha256_file(source)} for source in sources]
    dummy_sources = dummy_view_paths(resolved_dummy_folder)
    identity = {"idle_style": idle_style, "sprite_render_width": width, "sprite_render_height": base_height, "pad_top_percent": padding, "dummy_source_folder": str(resolved_dummy_folder) if resolved_dummy_folder is not None else None, "dummy_sources": {path.name: sha256_file(path) for path in dummy_sources}, "workflow_sha256": {name: sha256_bytes(canonical_json(_configured_stage_graph(name, workflow_config))) for name in STAGE_ORDER}}
    if state_path.exists():
        state = load_json(state_path)
        if state.get("version") != STATE_VERSION:
            raise ValueError("unsupported staged generation state")
        effective_seed = state["seed"]
        expected = [(x["source"], x["source_sha256"]) for x in source_records]
        actual = [(x["source"], x["source_sha256"]) for x in state["characters"]]
        if actual != expected or (requested_seed != -1 and requested_seed != effective_seed):
            raise ValueError("staged resume input or seed differs")
        if state.get("generation_identity") != identity:
            raise ValueError("staged resume workflow, style, or render settings differ")
    else:
        effective_seed = random.randrange(MAX_SEED + 1) if requested_seed == -1 else requested_seed
        used: set[str] = set()
        state = {"version": STATE_VERSION, "seed": effective_seed, "seed_mode": "random" if requested_seed == -1 else "fixed", "generation_identity": identity, "characters": [{**record, "name": _slug(Path(record["source"]).stem, used), "stages": {}} for record in source_records]}
    state["selection"] = {"actions": list(actions), "poses": list(poses)}
    state["generation_complete"] = False
    state["complete"] = False
    state["models_unloaded"] = False
    atomic_write_json(state_path, state)
    dummy_path = render_dummy_reference(destination / "workflow-dummy-reference.png", width, base_height, padding, resolved_dummy_folder)
    client = ComfyClient(server or configured_comfyui_url(workflow_config))
    dummy_upload = state.get("dummy_upload")
    if not dummy_upload:
        dummy_upload = client.upload_image(dummy_path); state["dummy_upload"] = dummy_upload; atomic_write_json(state_path, state)
    for character in state["characters"]:
        if not character.get("upload"):
            character["upload"] = client.upload_image(Path(character["source"])); atomic_write_json(state_path, state)
    # Submit a whole stage wave before waiting so directories of characters can
    # keep ComfyUI busy while still respecting inter-stage image dependencies.
    for stage_name in dependency_plan(actions, poses):
        spec = STAGES[stage_name]
        waiting: list[tuple[dict[str, Any], dict[str, Any], Path]] = []
        for character in state["characters"]:
            record = character["stages"].setdefault(stage_name, {})
            folder = destination / character["name"] / "generated" / "stages" / stage_name
            dependency_hashes: dict[str, str] = {}
            dependency_paths: dict[str, Path] = {}
            blocked = False
            for _node, pose in spec.dependency_inputs:
                provider = STAGES[POSE_STAGES[pose]]
                provider_stage = character["stages"].get(provider.name, {})
                if provider_stage.get("status") != "complete":
                    blocked = True; break
                provider_record = provider_stage.get("artifacts", {}).get(provider.pose)
                if not provider_record:
                    blocked = True; break
                provider_path = destination / character["name"] / "generated" / "stages" / provider.name / provider_record["path"]
                if not provider_path.is_file() or sha256_file(provider_path) != provider_record["sha256"]:
                    blocked = True; break
                dependency_paths[pose] = provider_path; dependency_hashes[pose] = provider_record["sha256"]
            if blocked:
                record["dependency_error"] = "a dependency stage is incomplete"
                if record.get("status") not in {"submitting", "submission_unknown"}:
                    record["status"] = "blocked"
                atomic_write_json(state_path, state); continue
            record.pop("dependency_error", None)
            logical_dependencies = {pose: f"dependency/{pose}-{digest}.png" for pose, digest in dependency_hashes.items()}
            logical_graph = render_stage_workflow(stage_name, f"character/{character['source_sha256']}", f"dummy/{sha256_file(dummy_path)}", logical_dependencies, width=width, height=height, neutral_idle=idle_style == "neutral", seed=effective_seed, config=workflow_config)
            request_hash = sha256_bytes(canonical_json({"graph": logical_graph, "dependencies": dependency_hashes, "source": character["source_sha256"]}))
            if record.get("request_sha256") not in (None, request_hash):
                raise ValueError(f"resume stage {stage_name} inputs differ")
            record["request_sha256"] = request_hash
            artifacts = record.get("artifacts", {})
            expected_artifacts = {"video", spec.pose}
            valid_artifacts = set(artifacts) == expected_artifacts and all((folder / item["path"]).is_file() and sha256_file(folder / item["path"]) == item["sha256"] for item in artifacts.values())
            if record.get("status") == "complete" and valid_artifacts:
                continue
            if record.get("status") in {"submitting", "submission_unknown"}:
                recovered = client.find_prompt_by_client_id(record["client_id"])
                if recovered:
                    record["prompt_id"] = recovered; record["status"] = "submitted"; atomic_write_json(state_path, state)
                else:
                    record["status"] = "submission_unknown"; record["error"] = "prior submission outcome is unknown; prompt was not resubmitted"; atomic_write_json(state_path, state)
                    continue
            if not record.get("prompt_id"):
                dependency_uploads = {pose: _uploaded_reference(client.upload_image(path)) for pose, path in dependency_paths.items()}
                graph = render_stage_workflow(stage_name, _uploaded_reference(character["upload"]), _uploaded_reference(dummy_upload), dependency_uploads, width=width, height=height, neutral_idle=idle_style == "neutral", seed=effective_seed, config=workflow_config)
                folder.mkdir(parents=True, exist_ok=True); atomic_write_json(folder / "rendered-workflow.json", graph)
                record["client_id"] = uuid.uuid4().hex; record["status"] = "submitting"; atomic_write_json(state_path, state)
                try:
                    record["prompt_id"] = client.submit(graph, client_id=record["client_id"])
                except BaseException:
                    record["status"] = "submission_unknown"; atomic_write_json(state_path, state); raise
                record["status"] = "submitted"; atomic_write_json(state_path, state)
            waiting.append((character, record, folder))
        for character, record, folder in waiting:
            try:
                history = client.wait(record["prompt_id"], timeout=timeout, poll_interval=poll_interval, required_nodes={spec.video_node, spec.pose_node})
                atomic_write_json(folder / "history.json", history)
                produced = {}
                for name, node, basename in (("video", spec.video_node, "video"), (spec.pose, spec.pose_node, spec.pose)):
                    descriptor = client.output_descriptor(history, node)
                    suffix = Path(descriptor["filename"]).suffix.lower()
                    target = folder / f"{basename}{suffix}"
                    client.download(descriptor, target)
                    produced[name] = {"path": target.name, "sha256": sha256_file(target), "node_id": node, "comfy_output": descriptor}
                record["artifacts"] = produced; record["status"] = "complete"; record.pop("error", None)
            except Exception as exc:
                record["status"] = "failed"; record["error"] = f"{type(exc).__name__}: {exc}"
            atomic_write_json(state_path, state)
    state["generation_complete"] = all(all(character["stages"].get(stage, {}).get("status") == "complete" for stage in dependency_plan(actions, poses)) for character in state["characters"])
    state["models_unloaded"] = client.free_if_idle() if client.wait_until_idle() else False
    atomic_write_json(state_path, state)
    return state


def selected_artifacts(state: dict[str, Any], output: str | Path, character: dict[str, Any], actions: Iterable[str], poses: Iterable[str]) -> tuple[dict[str, Path], dict[str, Path]]:
    root = Path(output).resolve() / character["name"] / "generated" / "stages"
    videos = {action: root / ACTION_STAGES[action] / character["stages"][ACTION_STAGES[action]]["artifacts"]["video"]["path"] for action in actions}
    images = {pose: root / POSE_STAGES[pose] / character["stages"][POSE_STAGES[pose]]["artifacts"][pose]["path"] for pose in poses}
    return videos, images


def package_staged(state: dict[str, Any], output: str | Path, *, actions: Iterable[str], poses: Iterable[str], frame_counts: dict[str, int], height: int, directions: tuple[str, ...] = ("right", "left", "back", "front"), split_algorithm: str = "blobs", server: str | None = None, config: ConfigOverrides = None, timeout: float = 7200, poll_interval: float = 2) -> dict[str, Any]:
    """Create an immutable package for one selection from cached stages."""
    from .character_animations import build_selected_character_animations
    from .comfy_postprocess import postprocess_settings

    if not state.get("generation_complete"):
        raise RuntimeError("selected generation stages are incomplete")
    if not state.get("models_unloaded"):
        raise RuntimeError("ComfyUI queue did not become idle; postprocessing was not started")
    actions, poses = tuple(actions), tuple(poses)
    models = postprocess_settings(config)
    request = {"actions": list(actions), "poses": list(poses), "frame_counts": {name: frame_counts[name] for name in actions}, "height": height, "directions": list(directions), "split_algorithm": split_algorithm, "sdpose_checkpoint": models["sdpose_checkpoint"], "background_removal_model": models["background_removal_model"]}
    selection_id = sha256_bytes(canonical_json(request))[:12]
    destination = Path(output).resolve()
    for character in state["characters"]:
        package = destination / character["name"] / "sprites" / f"selection-{selection_id}"
        try:
            videos, images = selected_artifacts(state, destination, character, actions, poses)
            manifest = build_selected_character_animations(videos, images, package, frame_counts=frame_counts, height=height, directions=directions, split_algorithm=split_algorithm, server=server, config=config, timeout=timeout, poll_interval=poll_interval)
            manifest["staged_selection"] = request
            manifest["generation_provenance"] = {"mode": "staged", "state": "../../../staged-generation-state.json", "seed": state["seed"], "seed_mode": state["seed_mode"], "stages": {name: {"request_sha256": record.get("request_sha256"), "prompt_id": record.get("prompt_id")} for name, record in character["stages"].items() if name in dependency_plan(actions, poses)}}
            atomic_write_json(package / "manifest.json", manifest)
            atomic_write_json(package / f"character-sheet-{height}h.json", manifest)
            character.setdefault("packages", {})[selection_id] = {"path": str(package.relative_to(destination / character["name"])), "request": request, "status": "complete"}
        except Exception as exc:
            character.setdefault("packages", {})[selection_id] = {"path": str(package.relative_to(destination / character["name"])), "request": request, "status": "failed", "error": f"{type(exc).__name__}: {exc}"}
        atomic_write_json(destination / "staged-generation-state.json", state)
    state["complete"] = state.get("generation_complete", False) and all(character.get("packages", {}).get(selection_id, {}).get("status") == "complete" for character in state["characters"])
    atomic_write_json(destination / "staged-generation-state.json", state)
    return state
