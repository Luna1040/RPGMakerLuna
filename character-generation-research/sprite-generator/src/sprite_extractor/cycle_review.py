"""Durable cycle-analysis cache and read-only web projection."""

from __future__ import annotations

import hashlib
import json
import mimetypes
import os
import shutil
import uuid
from pathlib import Path
from types import SimpleNamespace
from typing import Any

from .comfy_postprocess import postprocess_settings
from .diagnose_cycle import extract_sdpose
from .extract_frames import _worker
from .io_utils import atomic_write_json, canonical_json, load_json, sha256_file
from .media import probe_media
from .web.artifacts import safe_managed
from .web.store import Store

PERIOD_MIN = 0.35
PERIOD_MAX = 3.0


def _identity(prefix: str, value: Any) -> str:
    return prefix + hashlib.sha256(canonical_json(value)).hexdigest()


def _valid_pose(root: Path, request: dict[str, Any], source_sha: str) -> bool:
    try:
        identity = load_json(root / "identity.json")
        raw = root / "raw_pose.json"
        return (
            identity.get("request") == request
            and sha256_file(raw) == identity.get("raw_pose_sha256")
            and load_json(raw).get("source", {}).get("sha256") == source_sha
        )
    except (OSError, ValueError):
        return False


def _valid_sample(root: Path, request: dict[str, Any]) -> bool:
    try:
        identity = load_json(root / "sample-identity.json")
        summary_path = safe_managed(root, root / "summary.json")
        if identity.get("request") != request or sha256_file(
            summary_path
        ) != identity.get("summary_sha256"):
            return False
        summary = load_json(summary_path)
        if (
            not summary.get("cycle_candidates")
            or not (root / "manifest.json").is_file()
        ):
            return False
        return all(
            (path := safe_managed(root, root / frame["path"])).is_file()
            and not path.is_symlink()
            and sha256_file(path) == frame.get("sha256")
            for candidate in summary["cycle_candidates"]
            for frame in candidate["frames"]
        )
    except (OSError, ValueError, KeyError):
        return False


def ensure_cycle_analysis(
    video: Path,
    cache_root: Path,
    *,
    frame_count: int,
    server: str | None,
    config: Any,
    timeout: float,
    poll_interval: float,
    raw_pose_evidence: Path | None = None,
) -> Path:
    """Return an immutable sampled-cycle analysis, running only missing work."""
    video = video.resolve()
    media = probe_media(video)
    edges = [round(media.width * index / 4) for index in range(5)]
    crop = (edges[3], edges[4], 0, media.height)
    settings = postprocess_settings(config)
    pose_request = {
        "version": 1,
        "source_sha256": media.content_sha256,
        "crop": list(crop),
        "sdpose": settings["sdpose_checkpoint"],
        "extractor": "sdpose-openpose-v1",
    }
    pose_id = _identity("cyp_", pose_request)
    pose_root = cache_root / "poses" / pose_id
    raw_pose = pose_root / "raw_pose.json"
    if not _valid_pose(pose_root, pose_request, media.content_sha256):
        pose_root.parent.mkdir(parents=True, exist_ok=True)
        temporary = pose_root.with_name(f".{pose_id}.{uuid.uuid4().hex}.working")
        try:
            if raw_pose_evidence is not None:
                evidence = load_json(raw_pose_evidence)
                if evidence.get("source", {}).get("sha256") != media.content_sha256:
                    raise ValueError(
                        "saved pose evidence does not match the generated video"
                    )
                temporary.mkdir(parents=True)
                shutil.copy2(raw_pose_evidence, temporary / "raw_pose.json")
            else:
                extract_sdpose(
                    SimpleNamespace(
                        source=str(video),
                        output=str(temporary),
                        crop=crop,
                        server=server,
                        config=config,
                        timeout=timeout,
                        poll_interval=poll_interval,
                    )
                )
            atomic_write_json(
                temporary / "identity.json",
                {
                    "request": pose_request,
                    "raw_pose_sha256": sha256_file(temporary / "raw_pose.json"),
                },
            )
            try:
                os.replace(temporary, pose_root)
            except FileExistsError:
                if not _valid_pose(pose_root, pose_request, media.content_sha256):
                    raise
        finally:
            shutil.rmtree(temporary, ignore_errors=True)
    if load_json(raw_pose).get("source", {}).get("sha256") != media.content_sha256:
        raise ValueError("cached pose analysis source hash does not match")
    sample_request = {
        "version": 1,
        "pose_id": pose_id,
        "raw_pose_sha256": sha256_file(raw_pose),
        "min_period": PERIOD_MIN,
        "max_period": PERIOD_MAX,
        "frame_count": frame_count,
        "sampling": "nearest-half-open-v1",
    }
    sample_id = _identity("cys_", sample_request)
    target = cache_root / "samples" / sample_id
    if not _valid_sample(target, sample_request):
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_name(f".{sample_id}.{uuid.uuid4().hex}.working")
        try:
            _worker(
                SimpleNamespace(
                    input=str(video),
                    output=str(temporary),
                    crop=crop,
                    views=4,
                    view_index=3,
                    server=server,
                    config=config,
                    timeout=timeout,
                    poll_interval=poll_interval,
                    min_period=PERIOD_MIN,
                    max_period=PERIOD_MAX,
                    frame_count=frame_count,
                    sprite_height=1,
                    frames_only=True,
                    directions="right,left,back,front",
                    split_algorithm="blobs",
                    raw_pose=str(raw_pose),
                )
            )
            summary = load_json(temporary / "summary.json")
            summary["pose_analysis_id"] = pose_id
            summary["sample_set_id"] = sample_id
            for candidate in summary.get("cycle_candidates", []):
                for frame in candidate["frames"]:
                    frame["sha256"] = sha256_file(temporary / frame["path"])
            selected = next(
                item
                for item in summary["cycle_candidates"]
                if item["id"] == summary["system_candidate_id"]
            )
            summary["six_frame_cycle"]["frames"] = selected["frames"]
            atomic_write_json(temporary / "summary.json", summary)
            atomic_write_json(
                temporary / "sample-identity.json",
                {
                    "request": sample_request,
                    "summary_sha256": sha256_file(temporary / "summary.json"),
                },
            )
            try:
                os.replace(temporary, target)
            except FileExistsError:
                if not _valid_sample(target, sample_request):
                    raise
        finally:
            shutil.rmtree(temporary, ignore_errors=True)
    return target


def legacy_pose_evidence(
    store: Store, data_root: Path, job_id: str, action: str, source_sha: str
) -> Path | None:
    lineage = []
    current = job_id
    while current and current not in lineage:
        lineage.append(current)
        row = _job_row(store, current)
        current = (
            row["parent_job_id"]
            if row is not None and "parent_job_id" in row.keys()
            else None
        )
    with store.connect() as database:
        for item in lineage:
            sheet = database.execute(
                "SELECT path FROM artifacts WHERE job_id=? AND kind='sheet'", (item,)
            ).fetchone()
            if not sheet:
                continue
            try:
                candidate = safe_managed(
                    data_root,
                    Path(sheet["path"]).parent
                    / "timing-evidence"
                    / (action.replace("_", "-") + "-extraction")
                    / "raw_pose.json",
                )
                if (
                    candidate.is_file()
                    and not candidate.is_symlink()
                    and load_json(candidate).get("source", {}).get("sha256")
                    == source_sha
                ):
                    return candidate
            except (OSError, ValueError, KeyError):
                continue
    return None


def selected_cycle_records(analysis: Path, candidate_id: str | None = None):
    summary = load_json(analysis / "summary.json")
    selected_id = candidate_id or summary["system_candidate_id"]
    candidate = next(
        (item for item in summary["cycle_candidates"] if item["id"] == selected_id),
        None,
    )
    if candidate is None:
        raise ValueError("cycle candidate does not belong to this analysis")
    records = []
    for frame in candidate["frames"]:
        path = safe_managed(analysis, analysis / frame["path"])
        if not path.is_file() or sha256_file(path) != frame.get("sha256"):
            raise ValueError("cycle candidate frame is missing or corrupt")
        records.append({**frame, "path": str(path)})
    return summary, candidate, records


def register_cycle_analysis(
    store: Store, workspace_id: str, job_id: str, analysis: Path
) -> None:
    summary = load_json(analysis / "summary.json")
    with store.connect() as database:
        for candidate in summary.get("cycle_candidates", []):
            for frame in candidate["frames"]:
                path = safe_managed(store.path.parent, analysis / frame["path"])
                digest = frame.get("sha256")
                if (
                    not path.is_file()
                    or path.is_symlink()
                    or not digest
                    or sha256_file(path) != digest
                ):
                    raise ValueError("cycle candidate frame is missing or corrupt")
                asset_id = (
                    "cya_"
                    + hashlib.sha256(
                        (
                            workspace_id
                            + "\0"
                            + summary["sample_set_id"]
                            + "\0"
                            + candidate["id"]
                            + "\0"
                            + digest
                        ).encode()
                    ).hexdigest()
                )
                database.execute(
                    "INSERT OR IGNORE INTO artifacts(id,workspace_id,job_id,path,filename,media_type,bytes,sha256,kind) VALUES(?,?,?,?,?,?,?,?,?)",
                    (
                        asset_id,
                        workspace_id,
                        job_id,
                        str(path),
                        path.name,
                        mimetypes.guess_type(path.name)[0] or "image/png",
                        path.stat().st_size,
                        digest,
                        "cycle_preview",
                    ),
                )


def cycle_asset(store: Store, data_root: Path, asset_id: str) -> dict[str, Any] | None:
    with store.connect() as database:
        row = database.execute(
            "SELECT * FROM artifacts WHERE id=? AND kind='cycle_preview'", (asset_id,)
        ).fetchone()
    if row is None:
        return None
    value = dict(row)
    try:
        path = safe_managed(data_root, value["path"])
        if (
            not path.is_file()
            or path.is_symlink()
            or sha256_file(path) != value["sha256"]
        ):
            return None
    except (OSError, ValueError):
        return None
    value["path"] = path
    return value


def cycle_group_document(
    store: Store,
    base_path: str,
    workspace_id: str,
    action: str,
    label: str,
    stage_id: str,
    analysis: Path,
    selected_id: str | None = None,
    origin: str = "automatic",
) -> dict[str, Any]:
    summary = load_json(analysis / "summary.json")
    candidates = []
    total_ms = round(float(summary["period"]["seconds"]) * 1000)
    count = int(summary["selected_frame_count"])
    durations = [
        round((i + 1) * total_ms / count) - round(i * total_ms / count)
        for i in range(count)
    ]
    for candidate in summary.get("cycle_candidates", []):
        frames = []
        for frame in candidate["frames"]:
            path = safe_managed(analysis, analysis / frame["path"])
            digest = frame.get("sha256") or sha256_file(path)
            asset_id = (
                "cya_"
                + hashlib.sha256(
                    (
                        workspace_id
                        + "\0"
                        + summary["sample_set_id"]
                        + "\0"
                        + candidate["id"]
                        + "\0"
                        + digest
                    ).encode()
                ).hexdigest()
            )
            with store.connect() as database:
                exists = database.execute(
                    "SELECT 1 FROM artifacts WHERE id=? AND kind='cycle_preview'",
                    (asset_id,),
                ).fetchone()
            if not exists:
                raise ValueError("cycle preview index is unavailable")
            frames.append(
                {
                    "id": asset_id,
                    "frame_id": frame["frame_id"],
                    "pts": frame["pts"],
                    "time_seconds": frame["time_seconds"],
                    "url": f"{base_path}/api/cycle-assets/{asset_id}",
                }
            )
        candidates.append(
            {
                "id": candidate["id"],
                "start_time_seconds": candidate["start_time_seconds"],
                "end_time_seconds": candidate["end_time_seconds"],
                "period_seconds": candidate["period_seconds"],
                "frames": frames,
                "frame_durations_ms": durations,
                "system_selected": candidate["id"] == summary["system_candidate_id"],
            }
        )
    return {
        "action": action,
        "label": label,
        "stage_id": stage_id,
        "status": "ready",
        "message": None,
        "analysis_id": summary["analysis_id"],
        "sample_set_id": summary.get("sample_set_id"),
        "system_candidate_id": summary["system_candidate_id"],
        "selected_candidate_id": selected_id or summary["system_candidate_id"],
        "selection_origin": origin,
        "frame_count": count,
        "candidates": candidates,
    }


def capture_job_cycle_index(
    store: Store,
    data_root: Path,
    job: dict[str, Any],
    engine_root: Path,
    state: dict[str, Any],
    package_id: str,
) -> None:
    groups = []
    artifact_identities = {}
    for character in state.get("characters", []):
        package = character.get("packages", {}).get(package_id, {})
        if package.get("status") != "complete":
            continue
        manifest_path = safe_managed(
            data_root,
            engine_root / character["name"] / package["path"] / "manifest.json",
        )
        manifest = load_json(manifest_path)
        artifact_identities.update(
            manifest.get("generation_provenance", {}).get("artifact_identities", {})
        )
        for action, selection in manifest.get("cycle_selections", {}).items():
            analysis = safe_managed(data_root, selection["analysis_path"])
            register_cycle_analysis(store, job["workspace_id"], job["id"], analysis)
            generation = (
                manifest.get("generation_provenance", {})
                .get("artifact_identities", {})
                .get(f"action:{action}", {})
            )
            groups.append(
                {
                    "character": character["name"],
                    "action": action,
                    "analysis_path": str(analysis),
                    "analysis_id": selection["analysis_id"],
                    "sample_set_id": selection.get("sample_set_id"),
                    "selected_candidate_id": selection["candidate_id"],
                    "system_candidate_id": selection["system_candidate_id"],
                    "selection_origin": selection["origin"],
                    "generation_id": generation.get("generation_id"),
                    "video_sha256": generation.get("sha256"),
                }
            )
    target = (
        data_root
        / "workspaces"
        / job["workspace_id"]
        / "cycle-job-index"
        / f"{job['id']}.json"
    )
    atomic_write_json(
        target,
        {
            "version": 1,
            "job_id": job["id"],
            "engine_package_id": package_id,
            "artifact_identities": artifact_identities,
            "groups": groups,
        },
    )


def _job_row(store: Store, job_id: str):
    with store.connect() as database:
        return database.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone()


def _index_path(data_root: Path, workspace_id: str, job_id: str) -> Path:
    return (
        data_root / "workspaces" / workspace_id / "cycle-job-index" / f"{job_id}.json"
    )


def load_cycle_index(
    store: Store, data_root: Path, job_id: str, *, inherit: bool = False
) -> tuple[dict[str, Any], str] | None:
    seen = set()
    current = job_id
    while current and current not in seen:
        seen.add(current)
        row = _job_row(store, current)
        if row is None:
            return None
        path = _index_path(data_root, row["workspace_id"], current)
        if path.is_file() and not path.is_symlink():
            try:
                return load_json(safe_managed(data_root, path)), current
            except (OSError, ValueError):
                return None
        if not inherit:
            break
        current = row["parent_job_id"] if "parent_job_id" in row.keys() else None
    return None


def pinned_action_sources(
    store: Store, data_root: Path, job_id: str
) -> dict[str, dict[str, Any]]:
    row = _job_row(store, job_id)
    if row is None:
        return {}
    request = json.loads(row["request"])
    definition = json.loads(row["definition_snapshot"])
    action_stages = {
        details.get("outputs", {}).get("animation", {}).get("name"): stage
        for stage, details in definition.get("stages", {}).items()
        if details.get("outputs", {}).get("animation")
    }
    engine = (
        data_root
        / "workspaces"
        / row["workspace_id"]
        / "generation-sets"
        / row["resolved_seed"]
    )
    state_path = engine / "staged-generation-state.json"
    if not state_path.is_file() or state_path.is_symlink():
        return {}
    state = load_json(state_path)
    characters = state.get("characters", [])
    if not characters:
        return {}
    generation_ids = {}
    lineage = []
    current = job_id
    while current and current not in lineage:
        lineage.append(current)
        current_row = _job_row(store, current)
        current = (
            current_row["parent_job_id"]
            if current_row is not None and "parent_job_id" in current_row.keys()
            else None
        )
    package_job_ids = []
    if "base_package_id" in row.keys() and row["base_package_id"]:
        package = store.get_json("packages", row["base_package_id"])
        if package:
            package_job_ids.append(package["job_id"])
    package_job_ids.extend(lineage)
    with store.connect() as database:
        for package_job_id in package_job_ids:
            artifact = database.execute(
                "SELECT path FROM artifacts WHERE job_id=? AND kind='sheet'",
                (package_job_id,),
            ).fetchone()
            if not artifact:
                continue
            try:
                manifest = load_json(
                    safe_managed(
                        data_root, Path(artifact["path"]).parent / "manifest.json"
                    )
                )
                identities = manifest.get("generation_provenance", {}).get(
                    "artifact_identities", {}
                )
                generation_ids.update(
                    {
                        action: identities.get(f"action:{action}", {}).get(
                            "generation_id"
                        )
                        for action in request.get("actions", [])
                        if identities.get(f"action:{action}", {}).get("generation_id")
                    }
                )
                break
            except (OSError, ValueError, KeyError):
                continue
    if len(generation_ids) < len(request.get("actions", [])):
        for lineage_job in lineage:
            selection = (
                data_root
                / "workspaces"
                / row["workspace_id"]
                / "preview-revisions"
                / f"{lineage_job}.json"
            )
            if not selection.is_file() or selection.is_symlink():
                continue
            try:
                selected = (
                    load_json(safe_managed(data_root, selection))
                    .get("characters", {})
                    .get(characters[0]["name"], {})
                )
                for action, stage in action_stages.items():
                    if (
                        action in request.get("actions", [])
                        and action not in generation_ids
                        and selected.get(stage)
                    ):
                        generation_ids[action] = selected[stage]
            except (OSError, ValueError, KeyError):
                continue
    inherited = load_cycle_index(store, data_root, job_id, inherit=True)
    if inherited:
        generation_ids.update(
            {
                item["action"]: item.get("generation_id")
                for item in inherited[0].get("groups", [])
                if item.get("generation_id")
            }
        )
    result = {}
    character = characters[0]
    for action in request.get("actions", []):
        stage = action_stages.get(action)
        generation_id = generation_ids.get(action)
        revision = (
            character.get("stages", {})
            .get(stage, {})
            .get("revisions", {})
            .get(generation_id, {})
        )
        artifact = revision.get("artifacts", {}).get("video", {})
        relative = artifact.get("path")
        digest = artifact.get("sha256")
        if isinstance(relative, str) and isinstance(digest, str):
            path = safe_managed(data_root, engine / character["name"] / relative)
            if path.is_file() and not path.is_symlink() and sha256_file(path) == digest:
                result[action] = {
                    "path": path,
                    "sha256": digest,
                    "generation_id": generation_id,
                    "stage_id": stage,
                }
    return result


def resolve_pinned_sources(
    store: Store, data_root: Path, job_id: str, pins: dict[str, Any]
) -> dict[str, dict[str, Any]]:
    row = _job_row(store, job_id)
    if row is None:
        return {}
    engine = data_root / "workspaces" / row["workspace_id"] / "generation-sets" / row["resolved_seed"]
    state = load_json(safe_managed(data_root, engine / "staged-generation-state.json"))
    characters = state.get("characters", [])
    if not characters:
        return {}
    character = characters[0]
    result = {}
    for action, pin in pins.items():
        revision = (
            character.get("stages", {})
            .get(pin.get("stage_id"), {})
            .get("revisions", {})
            .get(pin.get("generation_id"), {})
        )
        artifact = revision.get("artifacts", {}).get("video", {})
        relative = artifact.get("path")
        if (
            not isinstance(relative, str)
            or artifact.get("sha256") != pin.get("sha256")
        ):
            continue
        path = safe_managed(data_root, engine / character["name"] / relative)
        if path.is_file() and not path.is_symlink() and sha256_file(path) == pin["sha256"]:
            result[action] = {
                "path": path,
                "sha256": pin["sha256"],
                "generation_id": pin["generation_id"],
                "stage_id": pin["stage_id"],
            }
    return result


def resolve_pinned_analyses(
    data_root: Path, engine: Path, pins: dict[str, Any]
) -> dict[str, Path]:
    result = {}
    for action, pin in pins.items():
        sample_id = pin.get("sample_set_id")
        if not isinstance(sample_id, str):
            continue
        path = safe_managed(
            data_root, engine / "cycle-analyses" / "samples" / sample_id
        )
        try:
            summary = load_json(path / "summary.json")
            if (
                summary.get("analysis_id") == pin.get("analysis_id")
                and summary.get("sample_set_id") == sample_id
            ):
                result[action] = path
        except (OSError, ValueError):
            continue
    return result


def job_cycles(store: Store, data_root: Path, job_id: str) -> dict[str, Any] | None:
    row = _job_row(store, job_id)
    if row is None:
        return None
    request = json.loads(row["request"])
    definition = json.loads(row["definition_snapshot"])
    action_details = {
        details.get("outputs", {})
        .get("animation", {})
        .get("name"): (stage, details.get("outputs", {}).get("animation", {}))
        for stage, details in definition.get("stages", {}).items()
        if details.get("outputs", {}).get("animation")
    }
    inherited = load_cycle_index(store, data_root, job_id, inherit=True)
    indexed = (
        {item["action"]: item for item in inherited[0].get("groups", [])}
        if inherited
        else {}
    )
    sources = pinned_action_sources(store, data_root, job_id)
    groups = []
    for action in request.get("actions", []):
        stage, animation = action_details.get(action, (None, {}))
        policy = animation.get("selection", {})
        if policy.get("method") != "cycle":
            continue
        item = indexed.get(action)
        if item:
            try:
                group = cycle_group_document(
                    store,
                    store.base_path,
                    row["workspace_id"],
                    action,
                    animation.get("label") or action.replace("_", " ").title(),
                    stage,
                    safe_managed(data_root, item["analysis_path"]),
                    item.get("selected_candidate_id"),
                    item.get("selection_origin", "automatic"),
                )
            except (OSError, ValueError, KeyError):
                group = {
                    "action": action,
                    "label": animation.get("label") or action.title(),
                    "stage_id": stage,
                    "status": "failed",
                    "message": "Saved cycle analysis is missing or corrupt",
                    "analysis_id": item.get("analysis_id"),
                    "system_candidate_id": item.get("system_candidate_id"),
                    "selected_candidate_id": item.get("selected_candidate_id"),
                    "selection_origin": item.get("selection_origin"),
                    "frame_count": request.get("frame_counts", {}).get(action, 0),
                    "candidates": [],
                }
        else:
            requested = (
                request.get("_cycle_actions", [])
                if row["kind"] == "cycle_analysis"
                else [
                    candidate
                    for candidate in request.get("actions", [])
                    if action_details.get(candidate, (None, {}))[1]
                    .get("selection", {})
                    .get("method")
                    == "cycle"
                ]
            )
            working = row["status"] in {
                "queued",
                "preparing",
                "extracting",
                "generating",
                "removing_backgrounds",
                "packaging",
                "stop_requested",
            }
            status = (
                "analyzing"
                if (
                    working
                    and row["status"] == "extracting"
                    and action in requested
                    and row["current_stage"] == stage
                )
                else "pending" if working and action in requested else "unavailable"
            )
            message = {
                "analyzing": "Finding complete cycles",
                "pending": "Cycle analysis pending",
                "unavailable": "Cycle analysis has not been saved for this render",
            }[status]
            group = {
                "action": action,
                "label": animation.get("label") or action.replace("_", " ").title(),
                "stage_id": stage,
                "status": status,
                "message": message,
                "analysis_id": None,
                "system_candidate_id": None,
                "selected_candidate_id": None,
                "selection_origin": None,
                "frame_count": request.get("frame_counts", {}).get(action, 0),
                "candidates": [],
            }
        group["can_analyze"] = (
            row["status"] in {"ready", "failed", "stopped"}
            and group["status"] != "ready"
            and action in sources
        )
        groups.append(group)
    terminal = row["status"] in {"ready", "failed", "stopped"}
    all_sources = all(action in sources for action in request.get("actions", []))
    return {
        "job_id": job_id,
        "groups": groups,
        "can_revise": terminal
        and all_sources
        and bool(groups)
        and all(item["status"] == "ready" for item in groups),
        "can_analyze": terminal
        and any(
            item["status"] != "ready" and item["action"] in sources for item in groups
        ),
    }
