"""Read-only projection of authoritative raw generation artifacts."""

from __future__ import annotations

import hashlib
import json
import mimetypes
from pathlib import Path
from typing import Any

from ..io_utils import (
    atomic_write_json,
    load_json,
    sha256_file,
)
from .artifacts import safe_managed
from .store import Store


def _preview_id(
    job_id: str, character: str, stage: str, kind: str, name: str, digest: str
) -> str:
    value = "\0".join((job_id, character, stage, kind, name, digest)).encode()
    return "pv_" + job_id + "_" + hashlib.sha256(value).hexdigest()


def _dependency_map(
    definition: dict[str, Any], selected_actions: list[str]
) -> tuple[dict[str, str], dict[str, list[str]], dict[str, str]]:
    stages = definition.get("stages", {})
    action_stages = {
        details.get("outputs", {}).get("animation", {}).get("name"): stage
        for stage, details in stages.items()
        if details.get("outputs", {}).get("animation")
    }
    dependencies: dict[str, list[str]] = {stage: [] for stage in stages}
    for action in selected_actions:
        root = action_stages.get(action)
        if root is None:
            continue
        pending = [root]
        visited: set[str] = set()
        while pending:
            stage = pending.pop()
            if stage in visited:
                continue
            visited.add(stage)
            dependencies.setdefault(stage, []).append(action)
            for reference in stages[stage].get("inputs", {}).values():
                if isinstance(reference, dict) and reference.get("stage"):
                    pending.append(reference["stage"])
    # Snapshot serialization preserves registry.stage_order in mapping order;
    # filtering that mapping is the same order used by dependency_plan().
    plan = [stage for stage in stages if dependencies.get(stage)]
    plan_index = {stage: index for index, stage in enumerate(plan)}
    request_index = {action: index for index, action in enumerate(selected_actions)}
    owners = {
        stage: min(
            consumers,
            key=lambda action: (
                plan_index.get(action_stages.get(action, ""), len(plan)),
                request_index[action],
            ),
        )
        for stage, consumers in dependencies.items()
        if consumers
    }
    return action_stages, dependencies, owners


_hash_cache: dict[tuple[str, int, int], str] = {}


def capture_job_revisions(
    data_root: Path,
    workspace_id: str,
    seed: str,
    job_id: str,
    stages: set[str] | None = None,
) -> None:
    """Persist the exact active revisions observed at completed stage boundaries."""
    engine = data_root / "workspaces" / workspace_id / "generation-sets" / seed
    state_path = engine / "staged-generation-state.json"
    if not state_path.is_file():
        return
    state = load_json(state_path)
    target = (
        data_root / "workspaces" / workspace_id / "preview-revisions" / f"{job_id}.json"
    )
    existing = (
        load_json(target) if target.is_file() else {"version": 1, "characters": {}}
    )
    for character in state.get("characters", []):
        selected = existing["characters"].setdefault(character["name"], {})
        for stage, bucket in character.get("stages", {}).items():
            if stages is not None and stage not in stages:
                continue
            revision_id = bucket.get("active_revision")
            revision = bucket.get("revisions", {}).get(revision_id, {})
            if revision.get("status") == "complete":
                selected[stage] = revision_id
    atomic_write_json(target, existing)


def job_previews(
    store: Store, data_root: Path, job_id: str, *, private: bool = False
) -> dict[str, Any] | None:
    with store.connect() as database:
        row = database.execute(
            "SELECT workspace_id,request,definition_snapshot,resolved_seed,status,completed_stages,worker_id FROM jobs WHERE id=?",
            (job_id,),
        ).fetchone()
    if row is None:
        return None
    request = json.loads(row["request"])
    definition = json.loads(row["definition_snapshot"])
    action_stages, dependency_for, stage_owners = _dependency_map(
        definition, request["actions"]
    )
    empty = {"job_id": job_id, "stage_owners": stage_owners, "stages": []}
    engine = safe_managed(
        data_root,
        data_root
        / "workspaces"
        / row["workspace_id"]
        / "generation-sets"
        / row["resolved_seed"],
    )
    state_path = engine / "staged-generation-state.json"
    if not state_path.is_file() or state_path.is_symlink():
        return empty
    try:
        state = load_json(state_path)
    except (OSError, ValueError):
        return empty
    selection_path = (
        data_root
        / "workspaces"
        / row["workspace_id"]
        / "preview-revisions"
        / f"{job_id}.json"
    )
    selection = {}
    if selection_path.is_file() and not selection_path.is_symlink():
        try:
            selection_path = safe_managed(data_root, selection_path)
            selection = load_json(selection_path).get("characters", {})
        except (OSError, ValueError):
            selection = {}
    selected_stage_actions = {
        stage: action
        for action, stage in action_stages.items()
        if action in request["actions"]
    }
    stage_order = [
        stage for stage in definition.get("stages", {}) if dependency_for.get(stage)
    ]
    active_fallback = set()
    if row["status"] in {
        "generating",
        "extracting",
        "removing_backgrounds",
        "packaging",
        "stop_requested",
    }:
        from .worker import process_is_same

        with store.connect() as database:
            competitor = database.execute(
                "SELECT 1 FROM jobs WHERE id<>? AND workspace_id=? AND resolved_seed=? AND status IN ('preparing','generating','extracting','removing_backgrounds','packaging','stop_requested') LIMIT 1",
                (job_id, row["workspace_id"], row["resolved_seed"]),
            ).fetchone()
        if process_is_same(row["worker_id"]) and competitor is None:
            active_fallback = set(stage_order[: int(row["completed_stages"])])
    ready_revisions = (
        _ready_action_revisions(store, data_root, job_id)
        if row["status"] == "ready"
        else {}
    )
    result: list[dict[str, Any]] = []
    for character in state.get("characters", []):
        character_name = character.get("name")
        if not isinstance(character_name, str):
            continue
        try:
            character_root = safe_managed(engine, engine / character_name)
        except ValueError:
            continue
        for stage_name in definition.get("stages", {}):
            if stage_name not in dependency_for or not dependency_for[stage_name]:
                continue
            bucket = character.get("stages", {}).get(stage_name, {})
            revision_id = selection.get(character_name, {}).get(stage_name)
            if revision_id is None and stage_name in active_fallback:
                # A legacy scheduler cannot write the per-job selection file.
                # Persisted completed_stages advances only after this active
                # revision became complete, so this is safe for the owning job.
                revision_id = bucket.get("active_revision")
            if revision_id is None and stage_name in selected_stage_actions:
                revision_id = ready_revisions.get(selected_stage_actions[stage_name])
            revision = bucket.get("revisions", {}).get(revision_id, {})
            if revision.get("status") != "complete":
                continue
            assets = []
            video = revision.get("artifacts", {}).get("video")
            record = _validated_asset(data_root, character_root, video)
            if record:
                assets.append(
                    _asset_document(
                        store,
                        job_id,
                        character_name,
                        stage_name,
                        "video",
                        "video",
                        record,
                        private,
                    )
                )
            for pose_name, pose in sorted(revision.get("poses", {}).items()):
                record = _validated_asset(data_root, character_root, pose)
                if record:
                    assets.append(
                        _asset_document(
                            store,
                            job_id,
                            character_name,
                            stage_name,
                            "pose",
                            pose_name,
                            record,
                            private,
                        )
                    )
            if not any(asset["kind"] == "pose" for asset in assets):
                frames = revision.get("artifacts", {}).get("frames", [])
                record = _validated_asset(
                    data_root, character_root, frames[0] if frames else None
                )
                if record:
                    assets.append(
                        _asset_document(
                            store,
                            job_id,
                            character_name,
                            stage_name,
                            "image",
                            "representative",
                            record,
                            private,
                        )
                    )
            if not assets:
                continue
            stage_definition = definition["stages"][stage_name]
            animation = stage_definition.get("outputs", {}).get("animation") or {}
            action_id = selected_stage_actions.get(stage_name)
            result.append(
                {
                    "character": character_name,
                    "stage_id": stage_name,
                    "label": animation.get("label")
                    or stage_name.replace("_", " ").title(),
                    "reason": "selected" if action_id else "dependency",
                    "action_id": action_id,
                    "owner_action_id": stage_owners[stage_name],
                    "dependency_for": dependency_for[stage_name],
                    "assets": assets,
                }
            )
    return {"job_id": job_id, "stage_owners": stage_owners, "stages": result}


def _ready_action_revisions(
    store: Store, data_root: Path, job_id: str
) -> dict[str, str]:
    """Recover selected action revision IDs from an already published engine manifest."""
    with store.connect() as database:
        row = database.execute(
            "SELECT path FROM artifacts WHERE job_id=? AND kind='sheet'", (job_id,)
        ).fetchone()
    if row is None:
        return {}
    try:
        sheet = safe_managed(data_root, row["path"])
        manifest = safe_managed(data_root, sheet.parent / "manifest.json")
        if manifest.is_symlink() or not manifest.is_file():
            return {}
        document = load_json(manifest)
        identities = document.get("generation_provenance", {}).get(
            "artifact_identities", {}
        )
        return {
            key.split(":", 1)[1]: value["generation_id"]
            for key, value in identities.items()
            if key.startswith("action:")
            and isinstance(value, dict)
            and isinstance(value.get("generation_id"), str)
        }
    except (OSError, ValueError, KeyError):
        return {}


def _validated_asset(
    data_root: Path, character_root: Path, artifact: Any
) -> dict[str, Any] | None:
    if not isinstance(artifact, dict):
        return None
    relative = artifact.get("path")
    digest = artifact.get("sha256")
    if not isinstance(relative, str) or not isinstance(digest, str):
        return None
    candidate = Path(relative)
    if candidate.is_absolute():
        return None
    try:
        path = safe_managed(character_root, character_root / candidate)
    except ValueError:
        return None
    if not path.is_file() or path.is_symlink():
        return None
    try:
        stat = path.stat()
        cache_key = (str(path), stat.st_size, stat.st_mtime_ns)
        actual = _hash_cache.get(cache_key)
        if actual is None:
            actual = sha256_file(path)
            if len(_hash_cache) >= 1024:
                _hash_cache.clear()
            _hash_cache[cache_key] = actual
        if actual != digest:
            return None
    except OSError:
        return None
    media_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    if media_type not in {
        "video/mp4",
        "video/webm",
        "image/png",
        "image/jpeg",
        "image/webp",
    }:
        return None
    return {
        "path": path,
        "filename": path.name,
        "media_type": media_type,
        "bytes": path.stat().st_size,
        "sha256": digest,
    }


def _asset_document(
    store: Store,
    job_id: str,
    character: str,
    stage: str,
    kind: str,
    name: str,
    record: dict[str, Any],
    private: bool,
) -> dict[str, Any]:
    identifier = _preview_id(job_id, character, stage, kind, name, record["sha256"])
    document = {
        "id": identifier,
        "kind": kind,
        "pose_id": name if kind == "pose" else None,
        "filename": record["filename"],
        "media_type": record["media_type"],
        "bytes": record["bytes"],
        "sha256": record["sha256"],
        "url": f"{store.base_path}/api/previews/{identifier}",
    }
    if private:
        document["_path"] = record["path"]
    return document


def resolve_preview(
    store: Store, data_root: Path, preview_id: str
) -> dict[str, Any] | None:
    if not preview_id.startswith("pv_job_") or len(preview_id) != 104:
        return None
    job_id = preview_id[3:39]
    document = job_previews(store, data_root, job_id, private=True)
    for stage in document["stages"] if document else ():
        for asset in stage["assets"]:
            if asset["id"] == preview_id:
                path = safe_managed(data_root, asset["_path"])
                return {**asset, "path": path}
    return None
