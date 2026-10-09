"""Generate run/idle videos from character images through local ComfyUI."""
from __future__ import annotations

import hashlib
import json
import re
import random
import uuid
from pathlib import Path
from typing import Any, Iterable

from .comfy_workflow import MAX_SEED, ConfigOverrides, ComfyClient, configured_comfyui_url, configured_dummy_image_folder, configured_pad_top_percent, configured_seed, configured_sprite_render_size, dummy_top_padding_pixels, dummy_view_paths, load_and_render_workflow, load_configured_workflow, render_dummy_reference, workflow_fingerprint, workflow_output_nodes
from .io_utils import atomic_write_bytes, atomic_write_json, canonical_json, load_json, sha256_file

IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tif", ".tiff"}
STATE_VERSION = "1.0"


def image_inputs(path: str | Path) -> list[Path]:
    source = Path(path).resolve()
    if source.is_file():
        if source.suffix.lower() not in IMAGE_SUFFIXES: raise ValueError(f"unsupported image type: {source.suffix}")
        return [source]
    if not source.is_dir(): raise FileNotFoundError(source)
    return sorted((item for item in source.iterdir() if item.is_file() and item.suffix.lower() in IMAGE_SUFFIXES), key=lambda item: item.name.casefold())


def _slug(value: str, used: set[str]) -> str:
    base = re.sub(r"[^A-Za-z0-9._-]+", "-", value).strip(".-") or "character"
    name = base; index = 2
    while name.casefold() in used:
        name = f"{base}-{index}"; index += 1
    used.add(name.casefold())
    return name


def _new_state(workflow: Path, style: str, inputs: Iterable[Path], dummy_reference: dict[str, Any], seed: int, seed_mode: str, *, workflow_config: ConfigOverrides = None) -> dict[str, Any]:
    used: set[str] = set()
    return {
        "version": STATE_VERSION,
        "workflow": {"path": str(workflow), "sha256": workflow_fingerprint(workflow, config_path=workflow_config)},
        "dummy_reference": dummy_reference,
        "idle_style": style,
        "seed": seed,
        "seed_mode": seed_mode,
        "characters": [
            {"name": _slug(source.stem, used), "source": str(source), "source_sha256": sha256_file(source), "status": "pending"}
            for source in inputs
        ],
    }


def _valid_effective_seed(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and 0 <= value <= MAX_SEED


def _legacy_rendered_seed(state_path: Path, state: dict[str, Any]) -> int | None:
    """Recover the seed from pre-seed-option state when a rendered graph exists."""
    values: set[int] = set()
    for character in state.get("characters", []):
        relative = character.get("rendered_workflow_path", "generated/rendered-workflow.json")
        path = state_path.parent / str(character.get("name", "")) / relative
        if not path.is_file():
            continue
        value = load_json(path).get("124", {}).get("inputs", {}).get("seed")
        if _valid_effective_seed(value):
            values.add(value)
    if len(values) > 1:
        raise ValueError("legacy rendered workflows contain different seeds")
    return next(iter(values)) if values else None


def _load_or_create_state(state_path: Path, workflow: Path, style: str, inputs: list[Path], dummy_reference: dict[str, Any], requested_seed: int, *, workflow_config: ConfigOverrides = None) -> dict[str, Any]:
    if isinstance(requested_seed, bool) or not isinstance(requested_seed, int) or not -1 <= requested_seed <= MAX_SEED:
        raise ValueError(f"seed must be -1 or an integer from 0 through {MAX_SEED}")
    if not state_path.exists():
        effective_seed = random.randrange(MAX_SEED + 1) if requested_seed == -1 else requested_seed
        proposed = _new_state(workflow, style, inputs, dummy_reference, effective_seed, "random" if requested_seed == -1 else "fixed", workflow_config=workflow_config)
        atomic_write_json(state_path, proposed); return proposed
    state = load_json(state_path)
    if not isinstance(state, dict) or state.get("version") != STATE_VERSION: raise ValueError("unsupported generation state")
    saved_seed = state.get("seed")
    migrated = False
    if not _valid_effective_seed(saved_seed):
        legacy_seed = _legacy_rendered_seed(state_path, state)
        saved_seed = legacy_seed if legacy_seed is not None else (random.randrange(MAX_SEED + 1) if requested_seed == -1 else requested_seed)
        state["seed"] = saved_seed
        state["seed_mode"] = "legacy" if legacy_seed is not None else ("random" if requested_seed == -1 else "fixed")
        migrated = True
    elif not isinstance(state.get("seed_mode"), str):
        state["seed_mode"] = "legacy"; migrated = True
    if requested_seed != -1 and saved_seed != requested_seed: raise ValueError("resume seed differs")
    proposed = _new_state(workflow, style, inputs, dummy_reference, saved_seed, state["seed_mode"], workflow_config=workflow_config)
    if state.get("workflow", {}).get("sha256") != proposed["workflow"]["sha256"]: raise ValueError("resume workflow hash differs")
    saved_dummy = {key:value for key,value in state.get("dummy_reference", {}).items() if key != "upload"}
    if saved_dummy != proposed["dummy_reference"]: raise ValueError("resume dummy reference or sprite render size differs")
    if state.get("idle_style") != style: raise ValueError("resume idle style differs")
    old = [(x.get("source"), x.get("source_sha256")) for x in state.get("characters", [])]
    new = [(x["source"], x["source_sha256"]) for x in proposed["characters"]]
    if old != new: raise ValueError("resume input list or image content differs")
    if migrated: atomic_write_json(state_path, state)
    return state


def _uploaded_reference(upload: dict[str, str]) -> str:
    subfolder = upload.get("subfolder", "").strip("/\\")
    return f"{subfolder}/{upload['name']}" if subfolder else upload["name"]


def _artifact_path(directory: Path, action: str, descriptor: dict[str, str]) -> Path:
    suffix = Path(descriptor["filename"]).suffix
    if not suffix: raise ValueError(f"ComfyUI {action} output has no file extension")
    return directory / "generated" / f"{action}{suffix.lower()}"


def generate_videos(
    image: str | Path,
    output: str | Path,
    workflow: str | Path,
    *,
    idle_style: str = "neutral",
    server: str | None = None,
    timeout: float = 7200.0,
    poll_interval: float = 2.0,
    unload_when_idle: bool = True,
    sprite_render_width: int | None = None,
    sprite_render_height: int | None = None,
    pad_top_percent: float | None = None,
    dummy_image_folder: str | Path | None = None,
    seed: int | None = None,
    workflow_config: ConfigOverrides = None,
) -> dict[str, Any]:
    """Submit all images first, then download the selected animation outputs."""
    if idle_style not in {"neutral", "feminine"}: raise ValueError("idle_style must be neutral or feminine")
    sources = image_inputs(image)
    if not sources: raise ValueError("no recognized image files found")
    workflow_path = Path(workflow).resolve()
    if not workflow_path.is_file(): raise FileNotFoundError(workflow_path)
    configured_width,configured_height=configured_sprite_render_size(workflow_config)
    render_width=configured_width if sprite_render_width is None else sprite_render_width
    render_height=configured_height if sprite_render_height is None else sprite_render_height
    resolved_pad_top_percent=configured_pad_top_percent(workflow_config) if pad_top_percent is None else pad_top_percent
    resolved_dummy_folder=configured_dummy_image_folder(workflow_config) if dummy_image_folder is None else Path(dummy_image_folder).expanduser().resolve()
    pad_top_pixels=dummy_top_padding_pixels(render_height,resolved_pad_top_percent)
    requested_seed=configured_seed(workflow_config) if seed is None else seed
    if any(isinstance(value,bool) or not isinstance(value,int) or value<=0 for value in (render_width,render_height)): raise ValueError("sprite render width and height must be positive integers")
    destination = Path(output).resolve(); destination.mkdir(parents=True, exist_ok=True)
    dummy_sources = dummy_view_paths(resolved_dummy_folder)
    dummy_path=render_dummy_reference(destination/"workflow-dummy-reference.png",render_width,render_height,resolved_pad_top_percent,resolved_dummy_folder)
    dummy_reference={"path":dummy_path.name,"sha256":sha256_file(dummy_path),"sprite_width":render_width,"sprite_height":render_height,"combined_width":render_width*4,"combined_height":render_height+pad_top_pixels,"pad_top_percent":resolved_pad_top_percent,"pad_top_pixels":pad_top_pixels,"source_scale_height":512,"source_folder":str(resolved_dummy_folder) if resolved_dummy_folder is not None else None,"source_views":[{"name":path.name,"sha256":sha256_file(path)} for path in dummy_sources]}
    workflow_archive=destination/"workflow-source.json"
    configured_workflow = load_configured_workflow(workflow_path, config_path=workflow_config)
    output_nodes = workflow_output_nodes(configured_workflow)
    effective_workflow = canonical_json(configured_workflow)
    if not workflow_archive.exists(): atomic_write_bytes(workflow_archive, effective_workflow)
    elif sha256_file(workflow_archive)!=workflow_fingerprint(workflow_path, config_path=workflow_config): raise ValueError("archived workflow content differs")
    state_path = destination / "generation-state.json"
    state = _load_or_create_state(state_path, workflow_path, idle_style, sources, dummy_reference, requested_seed, workflow_config=workflow_config)
    effective_seed = state["seed"]
    client = ComfyClient(server or configured_comfyui_url(workflow_config))
    if not state["dummy_reference"].get("upload"):
        state["dummy_reference"]["upload"]=client.upload_image(dummy_path)
        atomic_write_json(state_path,state)
    uploaded_dummy=_uploaded_reference(state["dummy_reference"]["upload"])

    # Queue every unsubmitted character before waiting, preserving prompt IDs
    # after each POST so process interruption cannot duplicate submitted work.
    for character in state["characters"]:
        if character.get("prompt_id"): continue
        if character.get("status") in {"submitting","submission_unknown"}:
            recovered = client.find_prompt_by_client_id(character["client_id"])
            if recovered:
                character["prompt_id"] = recovered; character["status"] = "submitted"; atomic_write_json(state_path,state)
            else:
                character["error"] = "prior submission outcome is unknown; prompt was not resubmitted"
                continue
        if character.get("prompt_id"): continue
        try:
            source = Path(character["source"])
            upload = client.upload_image(source)
            character["upload"] = upload; character["status"] = "uploaded"; character.pop("error",None)
            atomic_write_json(state_path, state)
            _original, rendered = load_and_render_workflow(workflow_path, _uploaded_reference(upload), uploaded_dummy=uploaded_dummy, render_width=render_width, render_height=render_height+pad_top_pixels, neutral_idle=idle_style == "neutral", seed=effective_seed, config_path=workflow_config)
            rendered_path=destination/character["name"]/"generated"/"rendered-workflow.json"
            atomic_write_json(rendered_path,rendered); character["rendered_workflow_path"]=str(rendered_path.relative_to(destination/character["name"]))
            character["rendered_workflow_sha256"] = hashlib.sha256(json.dumps(rendered, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()).hexdigest()
            character["client_id"] = uuid.uuid4().hex; character["status"] = "submitting"
            atomic_write_json(state_path, state)
            try: character["prompt_id"] = client.submit(rendered,client_id=character["client_id"])
            except BaseException:
                character["status"] = "submission_unknown"; atomic_write_json(state_path,state); raise
            character["status"] = "submitted"
            atomic_write_json(state_path, state)
        except Exception as exc:
            character["error"] = f"{type(exc).__name__}: {exc}"; atomic_write_json(state_path,state)

    # Download required outputs only. Completed files are content-checked before
    # resume skips them.
    for character in state["characters"]:
        if character.get("status") in {"downloaded","complete"}:
            files = character.get("videos", {})
            if set(files)==set(output_nodes) and all((destination / character["name"] / value["path"]).is_file() and sha256_file(destination / character["name"] / value["path"]) == value["sha256"] for value in files.values()):
                continue
        if not character.get("prompt_id"): continue
        try:
            if character.get("upload") and not character.get("rendered_workflow_path"):
                _original, rendered=load_and_render_workflow(workflow_path,_uploaded_reference(character["upload"]),uploaded_dummy=uploaded_dummy,render_width=render_width,render_height=render_height+pad_top_pixels,neutral_idle=idle_style=="neutral",seed=effective_seed,config_path=workflow_config)
                rendered_path=destination/character["name"]/"generated"/"rendered-workflow.json"; atomic_write_json(rendered_path,rendered)
                character["rendered_workflow_path"]=str(rendered_path.relative_to(destination/character["name"]))
                character["rendered_workflow_sha256"]=hashlib.sha256(json.dumps(rendered,sort_keys=True,separators=(",",":"),allow_nan=False).encode()).hexdigest()
            record = client.wait(character["prompt_id"], timeout=timeout, poll_interval=poll_interval, required_nodes=set(output_nodes.values()))
            folder = destination / character["name"]
            atomic_write_json(folder/"generated"/"history.json",record)
            videos: dict[str, Any] = {}
            for action, node in output_nodes.items():
                descriptor = client.output_descriptor(record, node)
                target = _artifact_path(folder, action, descriptor)
                client.download(descriptor, target)
                videos[action] = {"path": str(target.relative_to(folder)), "sha256": sha256_file(target), "comfy_output": descriptor, "node_id": node}
            character["videos"] = videos; character["status"] = "downloaded"; character.pop("error",None)
        except Exception as exc:
            character["status"] = "failed"; character["error"] = f"{type(exc).__name__}: {exc}"
        atomic_write_json(state_path, state)
    state["generation_complete"] = all(x.get("status") in {"downloaded","complete"} for x in state["characters"])
    state["models_unloaded"] = client.free_if_idle() if unload_when_idle and client.wait_until_idle() else False
    atomic_write_json(state_path, state)
    return state


def process_characters(
    image: str | Path,
    output: str | Path,
    workflow: str | Path,
    *,
    idle_style: str = "neutral",
    run_frames: int = 8,
    walk_frames: int = 8,
    idle_frames: int = 4,
    jump_frames: int = 8,
    crouch_walk_frames: int = 8,
    sprite_height: int = 128,
    sprite_render_width: int | None = None,
    sprite_render_height: int | None = None,
    pad_top_percent: float | None = None,
    dummy_image_folder: str | Path | None = None,
    seed: int | None = None,
    server: str | None = None,
    timeout: float = 7200.0,
    poll_interval: float = 2.0,
    postprocess: Any,
    postprocess_options: dict[str, Any] | None = None,
    workflow_config: ConfigOverrides = None,
) -> dict[str, Any]:
    """Generate every video, release idle server models, then postprocess each."""
    state = generate_videos(image, output, workflow, idle_style=idle_style, server=server, timeout=timeout, poll_interval=poll_interval, sprite_render_width=sprite_render_width, sprite_render_height=sprite_render_height, pad_top_percent=pad_top_percent, dummy_image_folder=dummy_image_folder, seed=seed, workflow_config=workflow_config)
    destination = Path(output).resolve()
    processing = {"run_frames":run_frames,"walk_frames":walk_frames,"idle_frames":idle_frames,"jump_frames":jump_frames,"crouch_walk_frames":crouch_walk_frames,"sprite_height":sprite_height,"options":postprocess_options or {}}
    if state.get("processing") not in (None,processing) and any(x.get("status")=="complete" for x in state["characters"]):
        raise ValueError("resume postprocessing settings differ from completed output")
    state["processing"] = processing; atomic_write_json(destination/"generation-state.json",state)
    if not state.get("models_unloaded"):
        raise RuntimeError("ComfyUI queue did not become idle; local postprocessing was not started")
    for character in state["characters"]:
        if character.get("status") not in {"downloaded","complete"}: continue
        folder = destination / character["name"]
        videos = {action: folder / record["path"] for action, record in character["videos"].items()}
        try:
            optional_videos = {f"{action}_video": path for action, path in videos.items() if action not in {"run", "idle"}}
            result = postprocess(videos["run"], videos["idle"], folder/"sprites", run_frames=run_frames, walk_frames=walk_frames, idle_frames=idle_frames, jump_frames=jump_frames, crouch_walk_frames=crouch_walk_frames, height=sprite_height, **optional_videos, **(postprocess_options or {}))
            result["generation_provenance"]={
                "source_image":{"path":character["source"],"sha256":character["source_sha256"]},
                "workflow":{"path":state["workflow"]["path"],"sha256":state["workflow"]["sha256"],"archive":"../../workflow-source.json","rendered_path":"../"+character.get("rendered_workflow_path","generated/rendered-workflow.json"),"rendered_sha256":character.get("rendered_workflow_sha256")},
                "dummy_reference":state["dummy_reference"],
                "idle_style":idle_style,"seed":state["seed"],"seed_mode":state["seed_mode"],"prompt_id":character["prompt_id"],"input_upload":character.get("upload"),
                "outputs":{f"{action}_node_id":record["node_id"] for action,record in character["videos"].items()},
            }
            atomic_write_json(folder/"sprites"/"manifest.json",result)
            atomic_write_json(folder/"sprites"/f"character-sheet-{sprite_height}h.json",result)
            character["deliverables"] = result; character["status"] = "complete"; character.pop("error",None)
        except Exception as exc:
            character["status"] = "postprocess_failed"; character["error"] = f"{type(exc).__name__}: {exc}"
        atomic_write_json(destination / "generation-state.json", state)
    state["complete"] = all(x.get("status") == "complete" for x in state["characters"])
    atomic_write_json(destination / "generation-state.json", state)
    return state
