"""Catalog-backed staged execution with immutable generation and pose revisions."""

from __future__ import annotations

import copy
import os
import random
import shutil
import uuid
from pathlib import Path
from typing import Any, Iterable

from .animation_definitions import AnimationRegistry
from .comfy_workflow import (
    MAX_SEED,
    ComfyClient,
    ComfyPromptRejected,
    ConfigOverrides,
    _load_model_config,
    configured_comfyui_url,
    configured_dummy_image_folder,
    configured_pad_top_percent,
    configured_seed,
    configured_sprite_render_size,
    dummy_top_padding_pixels,
    dummy_view_paths,
    render_dummy_reference,
)
from .generate_character import _slug, _uploaded_reference, image_inputs
from .io_utils import (
    atomic_write_bytes,
    atomic_write_json,
    canonical_json,
    load_json,
    sha256_bytes,
    sha256_file,
)
from .media import decode_frames, probe_media
from .workflow_templates import (
    normalized_generation_signature,
    output_contract,
    render_stage_workflow,
    template_identity,
)

STATE_VERSION = "3.0-definitions"


def _artifact_path(
    root: Path, character: dict[str, Any], artifact: dict[str, Any]
) -> Path:
    return root / character["name"] / artifact["path"]


def _valid_artifact(root: Path, character: dict[str, Any], artifact: Any) -> bool:
    if (
        not isinstance(artifact, dict)
        or not isinstance(artifact.get("path"), str)
        or not isinstance(artifact.get("sha256"), str)
    ):
        return False
    path = _artifact_path(root, character, artifact)
    return path.is_file() and sha256_file(path) == artifact["sha256"]


def _migrate_state(state: dict[str, Any]) -> dict[str, Any]:
    """Retain 2.0 records for lazy, evidence-based import or recovery."""
    if state.get("version") == STATE_VERSION:
        return state
    if state.get("version") != "2.0-staged":
        raise ValueError("unsupported staged generation state")
    migrated = {
        key: copy.deepcopy(value)
        for key, value in state.items()
        if key
        not in {
            "version",
            "generation_identity",
            "selection",
            "generation_complete",
            "complete",
            "models_unloaded",
        }
    }
    migrated["version"] = STATE_VERSION
    migrated["migration"] = {
        "source_version": "2.0-staged",
        "legacy_generation_identity": copy.deepcopy(state.get("generation_identity")),
    }
    for character in migrated.get("characters", []):
        character["legacy_stages"] = character.pop("stages", {})
        character["stages"] = {}
    migrated.update(generation_complete=False, complete=False, models_unloaded=False)
    return migrated


def _state(
    root: Path, sources: list[Path], requested_seed: int
) -> tuple[dict[str, Any], Path]:
    path = root / "staged-generation-state.json"
    records = [
        {"source": str(item), "source_sha256": sha256_file(item)} for item in sources
    ]
    if path.exists():
        loaded = load_json(path)
        migrating = loaded.get("version") == "2.0-staged"
        state = _migrate_state(loaded)
        if migrating:
            legacy_dummy = root / "workflow-dummy-reference.png"
            state.setdefault("migration", {})["legacy_dummy_sha256"] = (
                sha256_file(legacy_dummy) if legacy_dummy.is_file() else None
            )
            if legacy_dummy.is_file():
                archived = (
                    root
                    / "generation-inputs"
                    / "dummy"
                    / f"{state['migration']['legacy_dummy_sha256']}.png"
                )
                if not archived.exists():
                    atomic_write_bytes(archived, legacy_dummy.read_bytes())
        actual = [
            (item.get("source"), item.get("source_sha256"))
            for item in state.get("characters", [])
        ]
        expected = [(item["source"], item["source_sha256"]) for item in records]
        if actual != expected:
            raise ValueError("staged resume input list or image content differs")
        if requested_seed != -1 and state.get("seed") != requested_seed:
            raise ValueError("staged resume seed differs")
        return state, path
    seed = random.randrange(MAX_SEED + 1) if requested_seed == -1 else requested_seed
    used: set[str] = set()
    state = {
        "version": STATE_VERSION,
        "seed": seed,
        "seed_mode": "random" if requested_seed == -1 else "fixed",
        "definition_archives": {},
        "characters": [
            {
                **record,
                "name": _slug(Path(record["source"]).stem, used),
                "stages": {},
                "packages": {},
            }
            for record in records
        ],
        "generation_complete": False,
        "complete": False,
        "models_unloaded": False,
    }
    return state, path


def _pose_identity(video_sha: str, frame: str | int) -> str:
    return sha256_bytes(
        canonical_json(
            {
                "video_sha256": video_sha,
                "frame": frame,
                "decode": "ffmpeg-lossless-png-v1",
            }
        )
    )


def expected_pose_identity(revision: dict[str, Any], frame: str | int) -> str:
    frames = revision.get("artifacts", {}).get("frames", [])
    source_identity = (
        sha256_bytes(canonical_json([item.get("sha256") for item in frames]))
        if frames
        else revision["artifacts"]["video"]["sha256"]
    )
    return _pose_identity(source_identity, frame)


def _install_frame_cache(graph: dict[str, Any]) -> str:
    """Attach a lossless SaveImage sink without changing video generation."""
    decoded = output_contract(graph)["decoded_image_nodes"]
    if len(decoded) != 1:
        raise ValueError(
            "workflow template must expose exactly one final decoded image batch"
        )
    node_id = "definition_frame_cache"
    while node_id in graph:
        node_id += "_"
    graph[node_id] = {
        "inputs": {
            "filename_prefix": "sprite-extractor/frame-cache",
            "images": [decoded[0], 0],
        },
        "class_type": "SaveImage",
        "_meta": {"title": "Definition Frame Cache"},
    }
    return node_id


def _ensure_frame_cache(
    client: ComfyClient,
    root: Path,
    character: dict[str, Any],
    stage_name: str,
    generation_id: str,
    revision: dict[str, Any],
) -> None:
    node = revision.get("frame_cache_node")
    if not node:
        return
    frames = revision.get("artifacts", {}).get("frames", [])
    if frames and all(_valid_artifact(root, character, item) for item in frames):
        return
    if not frames:
        raise ValueError("generation frame cache has no recorded immutable hashes")
    history_path = (
        root
        / character["name"]
        / "generated"
        / "stages"
        / stage_name
        / "revisions"
        / generation_id
        / "history.json"
    )
    if not history_path.is_file():
        raise ValueError("generation frame cache is corrupt and history is unavailable")
    descriptors = client.output_descriptors(load_json(history_path), node)
    if len(descriptors) != len(frames):
        raise ValueError(
            "generation frame cache recovery count differs from the immutable revision"
        )
    restored = []
    for index, item in enumerate(descriptors):
        target = _artifact_path(root, character, frames[index])
        recovery = target.with_name(target.name + f".{uuid.uuid4().hex}.recovery")
        client.download(item, recovery)
        digest = sha256_file(recovery)
        if digest != frames[index]["sha256"]:
            recovery.unlink(missing_ok=True)
            raise ValueError(
                "generation frame cache recovery hash differs from the immutable revision"
            )
        target.parent.mkdir(parents=True, exist_ok=True)
        os.replace(recovery, target)
        restored.append({**frames[index], "comfy_output": item})
    revision.setdefault("artifacts", {})["frames"] = restored


def _extract_pose(
    root: Path,
    character: dict[str, Any],
    stage_name: str,
    generation_id: str,
    revision: dict[str, Any],
    pose_name: str,
    frame: str | int,
    state_path: Path,
    state: dict[str, Any],
) -> dict[str, Any]:
    video = revision["artifacts"]["video"]
    cached_frames = revision.get("artifacts", {}).get("frames", [])
    if cached_frames and not all(
        _valid_artifact(root, character, item) for item in cached_frames
    ):
        raise ValueError("generation frame cache is missing or corrupt")
    identity = expected_pose_identity(revision, frame)
    existing = revision.setdefault("poses", {}).get(pose_name)
    if (
        existing
        and existing.get("identity") == identity
        and _valid_artifact(root, character, existing)
    ):
        return existing
    destination = (
        root
        / character["name"]
        / "generated"
        / "stages"
        / stage_name
        / "revisions"
        / generation_id
        / "poses"
    )
    working = destination.with_name(
        destination.name + f".working-{os.getpid()}-{uuid.uuid4().hex}"
    )
    target = destination / f"{pose_name}-{identity[:12]}.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    if cached_frames:
        ordinal = (
            0
            if frame == "first"
            else len(cached_frames) - 1 if frame == "last" else frame
        )
        if (
            isinstance(ordinal, bool)
            or not isinstance(ordinal, int)
            or not 0 <= ordinal < len(cached_frames)
        ):
            raise ValueError(
                f"pose {pose_name} frame {frame!r} is outside the {len(cached_frames)} cached frames"
            )
        source = _artifact_path(root, character, cached_frames[ordinal])
        temporary = target.with_name(target.name + f".{uuid.uuid4().hex}.working")
        shutil.copyfile(source, temporary)
        os.replace(temporary, target)
        source_record = {
            "kind": "lossless_generation_frame_cache",
            "frame_sha256": cached_frames[ordinal]["sha256"],
        }
    else:
        source_path = _artifact_path(root, character, video)
        manifest = probe_media(source_path)
        ordinal = (
            0
            if frame == "first"
            else len(manifest.frames) - 1 if frame == "last" else frame
        )
        if (
            isinstance(ordinal, bool)
            or not isinstance(ordinal, int)
            or not 0 <= ordinal < len(manifest.frames)
        ):
            raise ValueError(
                f"pose {pose_name} frame {frame!r} is outside the {len(manifest.frames)} decoded frames"
            )
        try:
            decoded = decode_frames(manifest, working, [ordinal])[0]
            os.replace(decoded.decode_path, target)
        finally:
            shutil.rmtree(working, ignore_errors=True)
        source_record = {
            "kind": "decoded_video_fallback",
            "video_sha256": video["sha256"],
        }
    record = {
        "identity": identity,
        "frame": frame,
        "frame_id": ordinal,
        "path": str(target.relative_to(root / character["name"])),
        "sha256": sha256_file(target),
        "source": source_record,
    }
    revision.setdefault("poses", {})[pose_name] = record
    atomic_write_json(state_path, state)
    return record


def _legacy_import(
    root: Path,
    character: dict[str, Any],
    stage_name: str,
    generation_id: str,
    expected_signature: str,
    dependency_hashes: dict[str, Any],
    *,
    dummy_compatible: bool | None = True,
) -> dict[str, Any] | None:
    legacy = character.get("legacy_stages", {}).get(stage_name)
    if not isinstance(legacy, dict):
        return None
    if dummy_compatible is not True:
        return None
    rendered = (
        root
        / character["name"]
        / "generated"
        / "stages"
        / stage_name
        / "rendered-workflow.json"
    )
    if not rendered.is_file():
        return None
    try:
        rendered_graph = load_json(rendered)
        if normalized_generation_signature(rendered_graph) != expected_signature:
            return None
    except (OSError, ValueError):
        return None
    # Every legacy dependency must still resolve to the exact current pose hash.
    for dependency in dependency_hashes.values():
        provider = character.get("legacy_stages", {}).get(dependency["stage"], {})
        if (
            provider.get("artifacts", {}).get(dependency["output"], {}).get("sha256")
            != dependency["sha256"]
        ):
            return None
    imported = {
        key: copy.deepcopy(value)
        for key, value in legacy.items()
        if key in {"status", "client_id", "prompt_id", "error"}
    }
    imported.update(
        {
            "generation_id": generation_id,
            "generation_signature": expected_signature,
            "dependency_hashes": dependency_hashes,
            "migration": "verified-2.0-staged",
            "rendered_workflow": str(rendered.relative_to(root / character["name"])),
            "video_node": output_contract(rendered_graph)["video_node"],
            "poses": {},
        }
    )
    legacy_video = legacy.get("artifacts", {}).get("video")
    if (
        legacy.get("status") == "complete"
        and isinstance(legacy_video, dict)
        and isinstance(legacy_video.get("path"), str)
        and isinstance(legacy_video.get("sha256"), str)
    ):
        item = copy.deepcopy(legacy_video)
        item["path"] = str(Path("generated/stages") / stage_name / item["path"])
        imported["artifacts"] = {"video": item}
        imported["status"] = "complete"
        for pose_name, pose_item in legacy.get("artifacts", {}).items():
            if pose_name == "video":
                continue
            candidate = copy.deepcopy(pose_item)
            candidate["path"] = str(
                Path("generated/stages") / stage_name / candidate["path"]
            )
            if _valid_artifact(root, character, candidate):
                imported["poses"][pose_name] = {
                    **candidate,
                    "identity": _pose_identity(
                        item["sha256"], "first" if pose_name == "run_first" else "last"
                    ),
                    "frame": "first" if pose_name == "run_first" else "last",
                    "source": {
                        "kind": "legacy_canonical_save",
                        "video_sha256": item["sha256"],
                    },
                }
    return imported


def _legacy_may_match(
    root: Path,
    character: dict[str, Any],
    stage_name: str,
    expected_signature: str,
    dependency_hashes: dict[str, Any],
    dummy_compatible: bool | None,
) -> dict[str, Any] | None:
    legacy = character.get("legacy_stages", {}).get(stage_name)
    if not isinstance(legacy, dict):
        return None
    protected_status = (
        legacy.get("status") in {"submitting", "submission_unknown", "submitted"}
        or legacy.get("status") == "failed"
        and (legacy.get("prompt_id") or legacy.get("client_id"))
    )
    if not protected_status or dummy_compatible is False:
        return None
    rendered = (
        root
        / character["name"]
        / "generated"
        / "stages"
        / stage_name
        / "rendered-workflow.json"
    )
    if not rendered.is_file():
        return legacy
    try:
        if normalized_generation_signature(load_json(rendered)) != expected_signature:
            return None
    except (OSError, ValueError):
        return legacy
    for dependency in dependency_hashes.values():
        prior = (
            character.get("legacy_stages", {})
            .get(dependency["stage"], {})
            .get("artifacts", {})
            .get(dependency["output"], {})
        )
        if prior.get("sha256") and prior["sha256"] != dependency["sha256"]:
            return None
    return legacy


def _resolve_unverified_legacy(
    client: ComfyClient,
    root: Path,
    character: dict[str, Any],
    stage_name: str,
    legacy: dict[str, Any],
    *,
    timeout: float,
    poll_interval: float,
) -> None:
    """Finish a known 2.0 prompt without treating it as a compatible revision."""
    from .staged_workflow import STAGES as LEGACY_STAGES

    spec = LEGACY_STAGES[stage_name]
    history = client.wait(
        legacy["prompt_id"],
        timeout=timeout,
        poll_interval=poll_interval,
        required_nodes={spec.video_node, spec.pose_node},
    )
    folder = root / character["name"] / "generated" / "stages" / stage_name
    atomic_write_json(folder / "history.json", history)
    artifacts = {}
    recovered = []
    try:
        for name, node, basename in (
            ("video", spec.video_node, "video"),
            (spec.pose, spec.pose_node, spec.pose),
        ):
            descriptor = client.output_descriptor(history, node)
            prior = legacy.get("artifacts", {}).get(name, {})
            prior_path = prior.get("path") if isinstance(prior, dict) else None
            target = (
                folder / prior_path
                if isinstance(prior_path, str)
                else folder / f"{basename}{Path(descriptor['filename']).suffix.lower()}"
            )
            temporary = folder / f".{target.name}.recovery-{uuid.uuid4().hex}"
            recovered.append((temporary, target))
            client.download(descriptor, temporary)
            recovered_sha = sha256_file(temporary)
            expected_sha = prior.get("sha256") if isinstance(prior, dict) else None
            if isinstance(expected_sha, str) and recovered_sha != expected_sha:
                raise ValueError(
                    f"recovered legacy {stage_name}.{name} does not match its recorded checksum"
                )
            artifacts[name] = {
                "path": str(target.relative_to(folder)),
                "sha256": recovered_sha,
                "node_id": node,
                "comfy_output": descriptor,
            }
        for temporary, target in recovered:
            target.parent.mkdir(parents=True, exist_ok=True)
            os.replace(temporary, target)
    finally:
        for temporary, _target in recovered:
            temporary.unlink(missing_ok=True)
    legacy["artifacts"] = artifacts
    legacy["status"] = "complete"
    legacy.pop("error", None)
    legacy.pop("recovery_error", None)


def plan_definitions(
    registry: AnimationRegistry,
    actions: Iterable[str],
    poses: Iterable[str],
    frame_counts: dict[str, int],
    *,
    output: str | Path | None = None,
    image: str | Path | None = None,
    width: int | None = None,
    base_height: int | None = None,
    pad_top_percent: float = 0,
    dummy_image_folder: str | Path | None = None,
    seed: int | None = None,
    workflow_config: ConfigOverrides = None,
) -> dict[str, Any]:
    stages = registry.dependency_plan(actions, poses)
    resolved_dummy_folder = (
        configured_dummy_image_folder(workflow_config)
        if dummy_image_folder is None
        else Path(dummy_image_folder).expanduser().resolve()
    )
    state = None
    if output is not None:
        path = Path(output).resolve() / "staged-generation-state.json"
        if path.is_file():
            try:
                state = load_json(path)
            except (OSError, ValueError):
                state = None
    decisions = {name: "miss" for name in stages}
    if (
        isinstance(state, dict)
        and state.get("version") == STATE_VERSION
        and image is not None
        and width
        and base_height
    ):
        try:
            sources = image_inputs(image)
            source_map = {item["source"]: item for item in state.get("characters", [])}
            models = _load_model_config(workflow_config)
            dummy_sources = dummy_view_paths(resolved_dummy_folder)
            dummy_spec = {
                "width": width,
                "base_height": base_height,
                "pad_top_percent": pad_top_percent,
                "source_folder": (
                    str(resolved_dummy_folder)
                    if resolved_dummy_folder is not None
                    else None
                ),
                "sources": {
                    path.name: sha256_file(path) for path in dummy_sources
                },
            }
            dummy_sha = (
                state.get("dummy", {}).get("sha256")
                if state.get("dummy", {}).get("spec") == dummy_spec
                else None
            )
            effective_seed = state.get("seed") if seed in (None, -1) else seed
            aggregate = {name: [] for name in stages}
            for source in sources:
                character = source_map.get(str(source))
                resolved = {}
                if not character or character.get("source_sha256") != sha256_file(
                    source
                ):
                    for name in stages:
                        aggregate[name].append("miss")
                    continue
                for name in stages:
                    stage = registry.stages[name]
                    deps = {}
                    blocked = False
                    for semantic, ref in stage.inputs.items():
                        if not ref.stage:
                            continue
                        pose = resolved.get((ref.stage, ref.output))
                        if not pose:
                            blocked = True
                            break
                        deps[semantic] = {
                            "stage": ref.stage,
                            "output": ref.output,
                            "sha256": pose["sha256"],
                        }
                    uses_dummy = any(
                        ref.source == "dummy" for ref in stage.inputs.values()
                    )
                    if blocked or uses_dummy and not dummy_sha:
                        aggregate[name].append(
                            "awaiting_dependency" if blocked else "miss"
                        )
                        continue
                    logical = {
                        (
                            value["stage"],
                            value["output"],
                        ): f"artifact/{value['sha256']}.png"
                        for value in deps.values()
                    }
                    graph = render_stage_workflow(
                        registry,
                        name,
                        character_image=f"source/{character['source_sha256']}",
                        dummy_image=f"dummy/{dummy_sha}",
                        artifact_images=logical,
                        width=width,
                        height=base_height
                        + dummy_top_padding_pixels(base_height, pad_top_percent),
                        seed=effective_seed,
                        model_config=models,
                    )
                    signature = normalized_generation_signature(graph)
                    gid = sha256_bytes(
                        canonical_json(
                            {
                                "template": template_identity(stage.template),
                                "signature": signature,
                                "source_sha256": character["source_sha256"],
                                "dummy_sha256": dummy_sha if uses_dummy else None,
                                "dependencies": deps,
                            }
                        )
                    )
                    revision = (
                        character.get("stages", {})
                        .get(name, {})
                        .get("revisions", {})
                        .get(gid)
                    )
                    if (
                        revision
                        and revision.get("status") == "complete"
                        and _valid_artifact(
                            Path(output).resolve(),
                            character,
                            revision.get("artifacts", {}).get("video"),
                        )
                    ):
                        aggregate[name].append("hit")
                        cache_frames = revision.get("artifacts", {}).get("frames", [])
                        cache_identity = (
                            sha256_bytes(
                                canonical_json(
                                    [item.get("sha256") for item in cache_frames]
                                )
                            )
                            if cache_frames
                            else revision["artifacts"]["video"]["sha256"]
                        )
                        for pose_name, pose in stage.poses.items():
                            item = revision.get("poses", {}).get(pose_name)
                            if _valid_artifact(
                                Path(output).resolve(), character, item
                            ) and item.get("identity") == _pose_identity(
                                cache_identity, pose.frame
                            ):
                                resolved[name, pose_name] = item
                    elif revision and revision.get("status") in {
                        "submitting",
                        "submission_unknown",
                        "submitted",
                    }:
                        aggregate[name].append("awaiting_submission")
                    else:
                        aggregate[name].append("miss")
            for name, items in aggregate.items():
                decisions[name] = items[0] if len(set(items)) == 1 else "mixed"
        except (OSError, ValueError, KeyError, TypeError):
            decisions = {name: "unavailable" for name in stages}
    elif isinstance(state, dict) and state.get("version") == "2.0-staged":
        decisions = {name: "migration_review" for name in stages}
    return {
        "version": "2.0",
        "workflow": "staged",
        "actions": list(actions),
        "poses": list(poses),
        "stages": [
            {
                "name": name,
                "dependencies": list(registry.stages[name].dependencies),
                "inputs": {
                    key: ref.to_document()
                    for key, ref in registry.stages[name].inputs.items()
                },
                "generation": {
                    **registry.stages[name].generation.to_document(),
                    "frame_length": registry.stages[name].generation.frame_length,
                    "effective_duration_seconds": registry.stages[
                        name
                    ].generation.effective_duration_seconds,
                },
                "cache": {"decision": decisions[name]},
            }
            for name in stages
        ],
        "frame_counts": {name: frame_counts[name] for name in actions},
    }


def generate_definitions(
    image: str | Path,
    output: str | Path,
    registry: AnimationRegistry,
    *,
    actions: Iterable[str],
    poses: Iterable[str] = (),
    idle_style: str = "neutral",
    server: str | None = None,
    timeout: float = 7200,
    poll_interval: float = 2,
    sprite_render_width: int | None = None,
    sprite_render_height: int | None = None,
    pad_top_percent: float | None = None,
    dummy_image_folder: str | Path | None = None,
    seed: int | None = None,
    workflow_config: ConfigOverrides = None,
    progress=None,
    should_stop=None,
) -> dict[str, Any]:
    """Generate the requested catalog closure into immutable stage revisions."""
    actions, poses = tuple(actions), tuple(poses)
    if not actions and not poses:
        raise ValueError("staged workflow requires at least one action or pose")
    sources = image_inputs(image)
    if not sources:
        raise ValueError("no recognized image files found")
    configured_width, configured_height = configured_sprite_render_size(workflow_config)
    width = configured_width if sprite_render_width is None else sprite_render_width
    base_height = (
        configured_height if sprite_render_height is None else sprite_render_height
    )
    padding = (
        configured_pad_top_percent(workflow_config)
        if pad_top_percent is None
        else pad_top_percent
    )
    resolved_dummy_folder = (
        configured_dummy_image_folder(workflow_config)
        if dummy_image_folder is None
        else Path(dummy_image_folder).expanduser().resolve()
    )
    height = base_height + dummy_top_padding_pixels(base_height, padding)
    requested_seed = configured_seed(workflow_config) if seed is None else seed
    if (
        isinstance(requested_seed, bool)
        or not isinstance(requested_seed, int)
        or not -1 <= requested_seed <= MAX_SEED
    ):
        raise ValueError(f"seed must be -1 or an integer from 0 through {MAX_SEED}")
    root = Path(output).resolve()
    root.mkdir(parents=True, exist_ok=True)
    state, state_path = _state(root, sources, requested_seed)
    state.update(
        selection={"actions": list(actions), "poses": list(poses)},
        generation_complete=False,
        complete=False,
        models_unloaded=False,
    )
    archive = registry.provenance()
    archive_id = sha256_bytes(canonical_json(archive))
    archive_path = root / "definition-archives" / f"{archive_id}.json"
    if not archive_path.exists():
        atomic_write_json(archive_path, archive)
    state.setdefault("definition_archives", {})[archive_id] = str(
        archive_path.relative_to(root)
    )
    atomic_write_json(state_path, state)
    dummy_sources = dummy_view_paths(resolved_dummy_folder)
    dummy_path = render_dummy_reference(
        root / "workflow-dummy-reference.png",
        width,
        base_height,
        padding,
        resolved_dummy_folder,
    )
    dummy_sha = sha256_file(dummy_path)
    immutable_dummy = root / "generation-inputs" / "dummy" / f"{dummy_sha}.png"
    if not immutable_dummy.exists():
        atomic_write_bytes(immutable_dummy, dummy_path.read_bytes())
    client = ComfyClient(server or configured_comfyui_url(workflow_config))
    dummy_spec = {
        "width": width,
        "base_height": base_height,
        "pad_top_percent": padding,
        "source_folder": (
            str(resolved_dummy_folder)
            if resolved_dummy_folder is not None
            else None
        ),
        "sources": {
            path.name: sha256_file(path) for path in dummy_sources
        },
    }
    dummy_key = sha256_bytes(canonical_json({"sha256": dummy_sha, "spec": dummy_spec}))
    if state.get("dummy", {}).get("identity") != dummy_key:
        state["dummy"] = {
            "identity": dummy_key,
            "sha256": dummy_sha,
            "path": str(immutable_dummy.relative_to(root)),
            "spec": dummy_spec,
            "upload": client.upload_image(immutable_dummy),
        }
        atomic_write_json(state_path, state)
    for character in state["characters"]:
        if not character.get("upload"):
            character["upload"] = client.upload_image(Path(character["source"]))
            atomic_write_json(state_path, state)
    model_config = _load_model_config(workflow_config)
    required_poses = set(poses)
    planned_stages = registry.dependency_plan(actions, poses)
    completed_count = 0
    cached_count = 0
    for stage_index, stage_name in enumerate(planned_stages):
        from .execution_hooks import set_activity_stage

        set_activity_stage(stage_name)
        if should_stop and should_stop():
            from .application import CooperativeStop

            raise CooperativeStop(f"stopped before stage {stage_name}")
        if progress:
            progress(
                "generating",
                {
                    "current_stage": stage_name,
                    "completed_stages": completed_count,
                    "cached_stages": cached_count,
                    "total_stages": len(planned_stages),
                },
            )
        for later in registry.stages.values():
            if later.name in registry.dependency_plan(actions, poses):
                required_poses.update(
                    ref.output
                    for ref in later.inputs.values()
                    if ref.stage == stage_name and ref.output
                )
        jobs: list[tuple[dict[str, Any], dict[str, Any], Path, str, str | None]] = []
        all_cached = True
        stage = registry.stages[stage_name]
        for character in state["characters"]:
            dependency_records: dict[tuple[str, str], dict[str, Any]] = {}
            blocked = False
            for ref in stage.inputs.values():
                if not ref.stage:
                    continue
                provider_bucket = character.get("stages", {}).get(ref.stage, {})
                provider_id = provider_bucket.get("active_revision")
                provider = provider_bucket.get("revisions", {}).get(provider_id, {})
                pose_record = provider.get("poses", {}).get(ref.output)
                provider_pose = registry.stages[ref.stage].poses[ref.output]
                provider_frames = provider.get("artifacts", {}).get("frames", [])
                provider_video = provider.get("artifacts", {}).get("video", {})
                provider_cache_identity = (
                    sha256_bytes(
                        canonical_json([item.get("sha256") for item in provider_frames])
                    )
                    if provider_frames
                    else provider_video.get("sha256")
                )
                expected_identity = (
                    expected_pose_identity(provider, provider_pose.frame)
                    if provider_cache_identity
                    else None
                )
                if (
                    provider.get("status") != "complete"
                    or pose_record.get("identity") != expected_identity
                    or not _valid_artifact(root, character, pose_record)
                ):
                    blocked = True
                    break
                dependency_records[ref.stage, ref.output] = pose_record
            bucket = character.setdefault("stages", {}).setdefault(
                stage_name, {"revisions": {}}
            )
            if blocked:
                all_cached = False
                bucket.pop("active_revision", None)
                bucket["blocked"] = "a dependency pose is incomplete"
                atomic_write_json(state_path, state)
                continue
            bucket.pop("blocked", None)
            dependency_hashes = {
                semantic: {
                    "stage": ref.stage,
                    "output": ref.output,
                    "sha256": dependency_records[ref.stage, ref.output]["sha256"],
                }
                for semantic, ref in stage.inputs.items()
                if ref.stage
            }
            logical_images = {
                (a, b): f"artifact/{a}/{b}/{item['sha256']}.png"
                for (a, b), item in dependency_records.items()
            }
            logical_graph = render_stage_workflow(
                registry,
                stage_name,
                character_image=f"source/{character['source_sha256']}",
                dummy_image=f"dummy/{dummy_sha}",
                artifact_images=logical_images,
                width=width,
                height=height,
                seed=state["seed"],
                model_config=model_config,
            )
            signature = normalized_generation_signature(logical_graph)
            uses_dummy = any(ref.source == "dummy" for ref in stage.inputs.values())
            generation_id = sha256_bytes(
                canonical_json(
                    {
                        "template": template_identity(stage.template),
                        "signature": signature,
                        "source_sha256": character["source_sha256"],
                        "dummy_sha256": dummy_sha if uses_dummy else None,
                        "dependencies": dependency_hashes,
                    }
                )
            )
            revision = bucket["revisions"].get(generation_id)
            if revision is None:
                legacy_dummy_sha = state.get("dummy_reference", {}).get("sha256")
                legacy_meta = state.get("migration", {})
                legacy_identity = legacy_meta.get("legacy_generation_identity") or {}
                legacy_dummy_sha = (
                    legacy_meta.get("legacy_dummy_sha256") or legacy_dummy_sha
                )
                if not uses_dummy:
                    dummy_compatible = True
                elif not legacy_dummy_sha or not legacy_identity:
                    dummy_compatible = None
                else:
                    dummy_compatible = (
                        legacy_dummy_sha == dummy_sha
                        and legacy_identity.get("sprite_render_width") == width
                        and legacy_identity.get("sprite_render_height") == base_height
                        and legacy_identity.get("pad_top_percent") == padding
                        and legacy_identity.get("dummy_sources")
                        == dummy_spec["sources"]
                    )
                revision = _legacy_import(
                    root,
                    character,
                    stage_name,
                    generation_id,
                    signature,
                    dependency_hashes,
                    dummy_compatible=dummy_compatible,
                )
                if revision is None:
                    uncertain = _legacy_may_match(
                        root,
                        character,
                        stage_name,
                        signature,
                        dependency_hashes,
                        dummy_compatible,
                    )
                    if uncertain is not None:
                        all_cached = False
                        if uncertain.get("client_id"):
                            recovered = client.find_prompt_by_client_id(
                                uncertain["client_id"]
                            )
                            if recovered:
                                uncertain["prompt_id"] = recovered
                                uncertain["status"] = "submitted"
                        if uncertain.get("prompt_id"):
                            try:
                                _resolve_unverified_legacy(
                                    client,
                                    root,
                                    character,
                                    stage_name,
                                    uncertain,
                                    timeout=timeout,
                                    poll_interval=poll_interval,
                                )
                            except Exception as exc:
                                uncertain["status"] = "submitted"
                                uncertain["recovery_error"] = (
                                    f"{type(exc).__name__}: {exc}"
                                )
                        bucket.pop("active_revision", None)
                        bucket["legacy_blocking"] = (
                            "a potentially matching legacy submission must be resolved before retry"
                        )
                        atomic_write_json(state_path, state)
                        continue
                    revision = {
                        "generation_id": generation_id,
                        "generation_signature": signature,
                        "definition_archive": archive_id,
                        "dependency_hashes": dependency_hashes,
                        "status": "pending",
                        "poses": {},
                    }
                bucket["revisions"][generation_id] = revision
            bucket["active_revision"] = generation_id
            bucket.pop("legacy_blocking", None)
            if revision.get("status") == "complete" and _valid_artifact(
                root, character, revision.get("artifacts", {}).get("video")
            ):
                try:
                    _ensure_frame_cache(
                        client, root, character, stage_name, generation_id, revision
                    )
                    atomic_write_json(state_path, state)
                    for pose_name, pose in stage.poses.items():
                        if pose_name in required_poses:
                            _extract_pose(
                                root,
                                character,
                                stage_name,
                                generation_id,
                                revision,
                                pose_name,
                                pose.frame,
                                state_path,
                                state,
                            )
                except Exception as exc:
                    revision["status"] = "failed"
                    revision["error"] = f"{type(exc).__name__}: {exc}"
                    atomic_write_json(state_path, state)
                continue
            all_cached = False
            if revision.get("status") in {"submitting", "submission_unknown"}:
                recovered = client.find_prompt_by_client_id(revision["client_id"])
                if recovered:
                    revision["prompt_id"] = recovered
                    revision["status"] = "submitted"
                    atomic_write_json(state_path, state)
                else:
                    revision["status"] = "submission_unknown"
                    revision["error"] = (
                        "prior submission outcome is unknown; prompt was not resubmitted"
                    )
                    atomic_write_json(state_path, state)
                    continue
            folder = (
                root
                / character["name"]
                / "generated"
                / "stages"
                / stage_name
                / "revisions"
                / generation_id
            )
            folder.mkdir(parents=True, exist_ok=True)
            if not revision.get("prompt_id"):
                upload_images = {
                    (a, b): _uploaded_reference(
                        client.upload_image(_artifact_path(root, character, item))
                    )
                    for (a, b), item in dependency_records.items()
                }
                graph = render_stage_workflow(
                    registry,
                    stage_name,
                    character_image=_uploaded_reference(character["upload"]),
                    dummy_image=_uploaded_reference(state["dummy"]["upload"]),
                    artifact_images=upload_images,
                    width=width,
                    height=height,
                    seed=state["seed"],
                    model_config=model_config,
                )
                revision["frame_cache_node"] = _install_frame_cache(graph)
                revision["video_node"] = output_contract(graph)["video_node"]
                atomic_write_json(folder / "rendered-workflow.json", graph)
                atomic_write_json(
                    folder / "generation-provenance.json",
                    {
                        "generation_id": generation_id,
                        "template": template_identity(stage.template),
                        "effective_definition": {
                            "template": stage.template,
                            "inputs": {
                                name: ref.to_document()
                                for name, ref in stage.inputs.items()
                            },
                            "prompt": {"inline": stage.prompt},
                            "generation": stage.generation.to_document(),
                        },
                        "generation_signature": signature,
                        "models": {
                            f"{node}.{name}": value
                            for (node, name), value in model_config.items()
                        },
                        "seed": state["seed"],
                        "source_sha256": character["source_sha256"],
                        "dummy": (
                            {
                                "sha256": dummy_sha,
                                "path": str(immutable_dummy.relative_to(root)),
                            }
                            if uses_dummy
                            else None
                        ),
                        "dependency_artifacts": dependency_hashes,
                    },
                )
                revision["rendered_workflow"] = str(
                    (folder / "rendered-workflow.json").relative_to(
                        root / character["name"]
                    )
                )
                revision["generation_provenance"] = str(
                    (folder / "generation-provenance.json").relative_to(
                        root / character["name"]
                    )
                )
                revision["client_id"] = uuid.uuid4().hex
                revision["status"] = "submitting"
                atomic_write_json(state_path, state)
                try:
                    revision["prompt_id"] = client.submit(
                        graph, client_id=revision["client_id"]
                    )
                except ComfyPromptRejected:
                    revision["status"] = "failed"
                    atomic_write_json(state_path, state)
                    raise
                except BaseException:
                    revision["status"] = "submission_unknown"
                    atomic_write_json(state_path, state)
                    raise
                revision["status"] = "submitted"
                atomic_write_json(state_path, state)
            jobs.append(
                (
                    character,
                    revision,
                    folder,
                    revision.get("video_node"),
                    revision.get("frame_cache_node"),
                )
            )
        for character, revision, folder, video_node, frame_cache_node in jobs:
            try:
                required = {video_node} | (
                    {frame_cache_node} if frame_cache_node else set()
                )
                history = client.wait(
                    revision["prompt_id"],
                    timeout=timeout,
                    poll_interval=poll_interval,
                    required_nodes=required,
                )
                atomic_write_json(folder / "history.json", history)
                descriptor = client.output_descriptor(history, video_node)
                suffix = Path(descriptor["filename"]).suffix.lower()
                target = folder / f"video{suffix}"
                expected_video = revision.get("artifacts", {}).get("video")
                if expected_video and isinstance(expected_video.get("sha256"), str):
                    recovery = target.with_name(
                        target.name + f".{uuid.uuid4().hex}.recovery"
                    )
                    client.download(descriptor, recovery)
                    if sha256_file(recovery) != expected_video["sha256"]:
                        recovery.unlink(missing_ok=True)
                        raise ValueError(
                            "video recovery hash differs from the immutable revision"
                        )
                    os.replace(recovery, target)
                else:
                    client.download(descriptor, target)
                artifacts = {
                    "video": {
                        "path": str(target.relative_to(root / character["name"])),
                        "sha256": sha256_file(target),
                        "node_id": video_node,
                        "comfy_output": descriptor,
                    }
                }
                if frame_cache_node:
                    descriptors = client.output_descriptors(history, frame_cache_node)
                    expected_frames = revision.get("artifacts", {}).get("frames", [])
                    frames = []
                    if expected_frames and len(expected_frames) != len(descriptors):
                        raise ValueError(
                            "generation frame cache recovery count differs from the immutable revision"
                        )
                    for index, item in enumerate(descriptors):
                        frame_target = folder / "frames" / f"frame-{index:06d}.png"
                        if expected_frames:
                            recovery = frame_target.with_name(
                                frame_target.name + f".{uuid.uuid4().hex}.recovery"
                            )
                            client.download(item, recovery)
                            if (
                                sha256_file(recovery)
                                != expected_frames[index]["sha256"]
                            ):
                                recovery.unlink(missing_ok=True)
                                raise ValueError(
                                    "generation frame cache recovery hash differs from the immutable revision"
                                )
                            frame_target.parent.mkdir(parents=True, exist_ok=True)
                            os.replace(recovery, frame_target)
                            frames.append(
                                {**expected_frames[index], "comfy_output": item}
                            )
                        else:
                            client.download(item, frame_target)
                            frames.append(
                                {
                                    "path": str(
                                        frame_target.relative_to(
                                            root / character["name"]
                                        )
                                    ),
                                    "sha256": sha256_file(frame_target),
                                    "frame_id": index,
                                    "comfy_output": item,
                                }
                            )
                    if not frames:
                        raise ValueError("generation frame cache returned no images")
                    artifacts["frames"] = frames
                revision["artifacts"] = artifacts
                revision["status"] = "complete"
                revision.pop("error", None)
                for pose_name, pose in stage.poses.items():
                    if pose_name in required_poses:
                        _extract_pose(
                            root,
                            character,
                            stage_name,
                            revision["generation_id"],
                            revision,
                            pose_name,
                            pose.frame,
                            state_path,
                            state,
                        )
            except Exception as exc:
                revision["status"] = "failed"
                revision["error"] = f"{type(exc).__name__}: {exc}"
            atomic_write_json(state_path, state)
        stage_complete = all(
            character.get("stages", {})
            .get(stage_name, {})
            .get("revisions", {})
            .get(
                character.get("stages", {}).get(stage_name, {}).get("active_revision"),
                {},
            )
            .get("status")
            == "complete"
            for character in state["characters"]
        )
        if stage_complete:
            completed_count += 1
        if stage_complete and all_cached:
            cached_count += 1
        if progress:
            progress(
                "generating",
                {
                    "current_stage": None,
                    "completed_stage": stage_name if stage_complete else None,
                    "completed_stages": completed_count,
                    "cached_stages": cached_count,
                    "total_stages": len(planned_stages),
                },
            )
    planned = planned_stages
    state["generation_complete"] = all(
        all(
            character.get("stages", {})
            .get(name, {})
            .get("revisions", {})
            .get(character.get("stages", {}).get(name, {}).get("active_revision"), {})
            .get("status")
            == "complete"
            for name in planned
        )
        for character in state["characters"]
    )
    state["models_unloaded"] = (
        client.free_if_idle() if client.wait_until_idle() else False
    )
    if progress:
        progress(
            "generating",
            {
                "current_stage": None,
                "completed_stages": completed_count,
                "cached_stages": cached_count,
                "total_stages": len(planned),
            },
        )
    atomic_write_json(state_path, state)
    return state


def selected_definition_artifacts(
    root: str | Path,
    registry: AnimationRegistry,
    character: dict[str, Any],
    actions: Iterable[str],
    poses: Iterable[str],
    pinned_generation_ids: dict[str, str] | None = None,
    pinned_pose_generation_ids: dict[str, str] | None = None,
) -> tuple[dict[str, Path], dict[str, Path], dict[str, Any]]:
    base = Path(root).resolve()
    identities: dict[str, Any] = {}
    videos: dict[str, Path] = {}
    images: dict[str, Path] = {}
    for action in actions:
        stage_name = registry.action_stages[action]
        bucket = character["stages"][stage_name]
        if pinned_generation_ids is not None and action not in pinned_generation_ids:
            raise ValueError(f"pinned generation revision is missing {action}")
        revision_id = (
            pinned_generation_ids[action]
            if pinned_generation_ids is not None
            else bucket["active_revision"]
        )
        revision = bucket["revisions"][revision_id]
        artifact = revision["artifacts"]["video"]
        if not _valid_artifact(base, character, artifact):
            raise ValueError(f"selected action {action} artifact is missing or corrupt")
        videos[action] = _artifact_path(base, character, artifact)
        identities[f"action:{action}"] = {
            "generation_id": revision["generation_id"],
            "sha256": artifact["sha256"],
        }
    for pose in poses:
        stage_name = registry.pose_stages[pose]
        bucket = character["stages"][stage_name]
        if (
            pinned_pose_generation_ids is not None
            and pose not in pinned_pose_generation_ids
        ):
            raise ValueError(f"pinned pose revision is missing {pose}")
        revision_id = (
            pinned_pose_generation_ids[pose]
            if pinned_pose_generation_ids is not None
            else bucket["active_revision"]
        )
        revision = bucket["revisions"][revision_id]
        artifact = revision["poses"][pose]
        if not _valid_artifact(base, character, artifact):
            raise ValueError(f"selected pose {pose} artifact is missing or corrupt")
        images[pose] = _artifact_path(base, character, artifact)
        identities[f"pose:{pose}"] = {
            "generation_id": revision["generation_id"],
            "pose_identity": artifact["identity"],
            "sha256": artifact["sha256"],
        }
    return videos, images, identities


def package_definitions(
    state: dict[str, Any],
    output: str | Path,
    registry: AnimationRegistry,
    *,
    actions: Iterable[str],
    poses: Iterable[str],
    frame_counts: dict[str, int],
    height: int,
    directions: tuple[str, ...] = ("right", "left", "back", "front"),
    split_algorithm: str = "blobs",
    server: str | None = None,
    config: ConfigOverrides = None,
    timeout: float = 7200,
    poll_interval: float = 2,
    progress=None,
    should_stop=None,
    cycle_selections: dict[str, str] | None = None,
    pinned_analyses: dict[str, Path] | None = None,
    pinned_generation_ids: dict[str, str] | None = None,
    pinned_pose_generation_ids: dict[str, str] | None = None,
    cycle_analysis_callback=None,
    cycle_selection_origins: dict[str, str] | None = None,
) -> dict[str, Any]:
    from .character_animations import build_selected_character_animations
    from .comfy_postprocess import postprocess_settings

    if not state.get("generation_complete"):
        raise RuntimeError("selected generation stages are incomplete")
    if not state.get("models_unloaded"):
        raise RuntimeError(
            "ComfyUI queue did not become idle; postprocessing was not started"
        )
    actions, poses = tuple(actions), tuple(poses)
    base = Path(output).resolve()
    models = postprocess_settings(config)
    current_archive = sha256_bytes(canonical_json(registry.provenance()))
    policies = {
        action: registry.stages[
            registry.action_stages[action]
        ].animation.selection.to_document()
        for action in actions
    }
    conceptual = {
        action: registry.stages[
            registry.action_stages[action]
        ].animation.conceptual_loop
        for action in actions
    }
    playback = {
        action: registry.stages[registry.action_stages[action]].animation.webp_loop
        for action in actions
    }
    order = tuple(action for action in registry.actions if action in actions)
    base_request = {
        "actions": list(order),
        "poses": list(poses),
        "frame_counts": {name: frame_counts[name] for name in order},
        "action_policies": policies,
        "conceptual_loops": conceptual,
        "webp_loops": playback,
        "height": height,
        "directions": list(directions),
        "split_algorithm": split_algorithm,
        "postprocess_models": models,
    }
    current_results = []
    for character in state["characters"]:
        if should_stop and should_stop():
            from .application import CooperativeStop

            raise CooperativeStop("stopped before postprocessing")
        if progress:
            progress("extracting", {"character": character["name"]})
        package: Path | None = None
        try:
            videos, images, identities = selected_definition_artifacts(
                base,
                registry,
                character,
                order,
                poses,
                pinned_generation_ids,
                pinned_pose_generation_ids,
            )
            request = {**base_request, "source_identities": identities}
            package = (
                base
                / character["name"]
                / "sprites"
                / f".cycle-package-{uuid.uuid4().hex}"
            )
            manifest = build_selected_character_animations(
                videos,
                images,
                package,
                frame_counts=frame_counts,
                action_policies=policies,
                conceptual_loops=conceptual,
                webp_loops=playback,
                action_order=order,
                height=height,
                directions=directions,
                split_algorithm=split_algorithm,
                server=server,
                config=config,
                timeout=timeout,
                poll_interval=poll_interval,
                analysis_cache_root=base / "cycle-analyses",
                cycle_selections=cycle_selections,
                mask_cache_root=base / "background-mask-cache",
                pinned_analyses=pinned_analyses,
                analysis_callback=(
                    (
                        lambda action, analysis: cycle_analysis_callback(
                            character,
                            action,
                            analysis,
                            identities.get(f"action:{action}"),
                        )
                    )
                    if cycle_analysis_callback
                    else None
                ),
                cycle_selection_origins=cycle_selection_origins,
                analysis_stage_ids={
                    action: registry.action_stages[action] for action in order
                },
                analysis_started_callback=(
                    lambda action: progress(
                        "extracting",
                        {
                            "current_stage": registry.action_stages[action],
                            "operation": "cycle_analysis",
                            "action": action,
                        },
                    )
                ) if progress else None,
            )
            if manifest.get("cycle_selections"):
                request["cycle_selections"] = {
                    action: {
                        key: value
                        for key, value in item.items()
                        if key != "analysis_path"
                    }
                    for action, item in manifest["cycle_selections"].items()
                }
            package_id = sha256_bytes(canonical_json(request))
            final_package = (
                base / character["name"] / "sprites" / f"selection-{package_id[:12]}"
            )
            manifest["definition_selection"] = request
            manifest["generation_provenance"] = {
                "mode": "definitions",
                "state": "../../../staged-generation-state.json",
                "definition_archive": f"../../../definition-archives/{current_archive}.json",
                "seed": state["seed"],
                "seed_mode": state["seed_mode"],
                "artifact_identities": identities,
            }
            atomic_write_json(package / "manifest.json", manifest)
            atomic_write_json(package / f"character-sheet-{height}h.json", manifest)
            if final_package.exists():
                shutil.rmtree(package)
                package = final_package
                manifest = load_json(package / "manifest.json")
                deliverables = [manifest.get("sheet")]
                deliverables.extend(manifest.get("webps", {}).values())
                deliverables.append(f"character-sheet-{height}h.json")
                package_root = package.resolve()
                if manifest.get("definition_selection") != request or any(
                    not isinstance(relative, str)
                    or not (package / relative).resolve().is_relative_to(package_root)
                    or not (package / relative).is_file()
                    or (package / relative).is_symlink()
                    for relative in deliverables
                ):
                    raise ValueError(
                        "cached package identity or deliverables do not match"
                    )
            else:
                os.replace(package, final_package)
                package = final_package
            character.setdefault("packages", {})[package_id] = {
                "path": str(package.relative_to(base / character["name"])),
                "request": request,
                "status": "complete",
            }
            character["selected_package_id"] = package_id
            current_results.append(True)
        except Exception as exc:
            from .application import CooperativeStop
            from .submission_journal import SubmissionRecoveryRequired

            if isinstance(exc, (CooperativeStop, SubmissionRecoveryRequired)):
                raise
            failed_id = sha256_bytes(
                canonical_json(
                    {**base_request, "character": character["source_sha256"]}
                )
            )
            character.setdefault("packages", {})[failed_id] = {
                "path": (
                    str(package.relative_to(base / character["name"]))
                    if package
                    else None
                ),
                "request": base_request,
                "status": "failed",
                "error": f"{type(exc).__name__}: {exc}",
            }
            current_results.append(False)
        atomic_write_json(base / "staged-generation-state.json", state)
    state["complete"] = (
        state.get("generation_complete", False)
        and len(current_results) == len(state["characters"])
        and all(current_results)
    )
    atomic_write_json(base / "staged-generation-state.json", state)
    return state
