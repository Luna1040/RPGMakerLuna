from __future__ import annotations
import hashlib, io, json, mimetypes, os, uuid, zipfile
from pathlib import Path
from typing import Any, Iterable
from ..io_utils import sha256_file
from .store import Store, ident, now

ALLOWED = {".png", ".json", ".webp"}


def safe_managed(root: Path, value: str | Path) -> Path:
    raw = Path(value).absolute()
    managed = root.resolve()
    cursor = raw
    while cursor != managed and managed in cursor.parents:
        if cursor.is_symlink():
            raise ValueError("symlink artifacts are not served")
        cursor = cursor.parent
    path = raw.resolve()
    if path != managed and managed not in path.parents:
        raise ValueError("path is outside managed storage")
    return path


def publish_package(
    store: Store,
    data_root: Path,
    job: dict[str, Any],
    engine_root: Path,
    *,
    engine_package_id: str | None = None,
) -> dict[str, Any]:
    with store.connect() as db:
        prior = db.execute(
            "SELECT record FROM packages WHERE job_id=?", (job["id"],)
        ).fetchone()
    if prior:
        return json.loads(prior[0])
    state = json.loads((engine_root / "staged-generation-state.json").read_text())
    character = state["characters"][0]
    selected = engine_package_id or character.get("selected_package_id")
    item = character.get("packages", {}).get(selected)
    complete = (
        [(selected, item)]
        if selected and isinstance(item, dict) and item.get("status") == "complete"
        else []
    )
    if not complete:
        raise RuntimeError("no completed package was published")
    _engine_id, item = complete[-1]
    package_dir = safe_managed(
        data_root, engine_root / character["name"] / item["path"]
    )
    manifest_path = package_dir / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    package_id = ident("pkg_")
    records = []
    publication = data_root / "publications" / job["id"]
    publication.mkdir(parents=True, exist_ok=True)
    public_manifest = {
        key: manifest[key]
        for key in (
            "version",
            "sheet",
            "layout",
            "origin",
            "webp_origin",
            "actions",
            "cells",
            "webps",
            "frame_durations_ms",
        )
        if key in manifest
    }
    public_manifest["actions"] = {
        name: {
            key: value
            for key, value in details.items()
            if key in {"duration_seconds", "frame_count", "looping", "webp_loop"}
        }
        for name, details in manifest.get("actions", {}).items()
    }
    public_manifest["quality_evaluated"] = False
    public_manifest["cycle_selections"] = {
        action: {
            key: item.get(key)
            for key in (
                "analysis_id",
                "sample_set_id",
                "candidate_id",
                "system_candidate_id",
                "origin",
            )
        }
        for action, item in manifest.get("cycle_selections", {}).items()
    }
    public_manifest_path = publication / "manifest.json"
    public_manifest_path.write_text(
        json.dumps(public_manifest, indent=2, sort_keys=True) + "\n"
    )
    public_metadata_path = (
        publication / f"character-sheet-{job['request']['sprite_size']}h.json"
    )
    public_metadata_path.write_text(
        json.dumps(public_manifest, indent=2, sort_keys=True) + "\n"
    )
    # Explicit allowlist: final sheet, its public JSON, manifest, and selected WebPs.
    sheet = package_dir / manifest["sheet"]
    candidates = [
        ("sheet", sheet),
        ("manifest", public_manifest_path),
        ("metadata", public_metadata_path),
    ]
    for rel in manifest.get("webps", {}).values():
        candidates.append(("animation", package_dir / rel))
    for kind, path in candidates:
        path = safe_managed(data_root, path)
        if not path.is_file() or path.suffix.lower() not in ALLOWED:
            raise ValueError("package contains an unsupported deliverable")
        artifact_id = ident("ar_")
        record = {
            "id": artifact_id,
            "workspace_id": job["workspace_id"],
            "job_id": job["id"],
            "path": str(path),
            "filename": path.name,
            "media_type": mimetypes.guess_type(path.name)[0]
            or "application/octet-stream",
            "bytes": path.stat().st_size,
            "sha256": sha256_file(path),
            "kind": kind,
        }
        with store.connect() as db:
            db.execute(
                "INSERT INTO artifacts VALUES(?,?,?,?,?,?,?,?,?)",
                tuple(
                    record[k]
                    for k in (
                        "id",
                        "workspace_id",
                        "job_id",
                        "path",
                        "filename",
                        "media_type",
                        "bytes",
                        "sha256",
                        "kind",
                    )
                ),
            )
        records.append(record)

    def public(record):
        return {
            "artifact_id": record["id"],
            "filename": record["filename"],
            "media_type": record["media_type"],
            "bytes": record["bytes"],
            "sha256": record["sha256"],
            "url": f"{store.base_path}/api/artifacts/{record['id']}",
        }

    byname = {x["filename"]: x for x in records}
    animations = []
    for key, name in manifest.get("webps", {}).items():
        action, direction = key.split(":", 1)
        animations.append(
            {"action": action, "direction": direction, **public(byname[name])}
        )
    result = {
        "id": package_id,
        "job_id": job["id"],
        "created_at": now(),
        "sheet": public(next(x for x in records if x["kind"] == "sheet")),
        "metadata": public(next(x for x in records if x["kind"] == "metadata")),
        "manifest": public(next(x for x in records if x["kind"] == "manifest")),
        "animations": animations,
        "still_actions": [
            a
            for a in job["request"]["actions"]
            if not any(x["action"] == a for x in animations)
        ],
        "download_url": f"{store.base_path}/api/packages/{package_id}/download",
        "action_downloads": {
            a: f"{store.base_path}/api/packages/{package_id}/download?action={a}"
            for a in sorted({x["action"] for x in animations})
        },
        "preview": {
            "layout": manifest.get("layout"),
            "frame_durations_ms": manifest.get("frame_durations_ms", {}),
        },
        "cycle_selections": public_manifest["cycle_selections"],
    }
    with store.connect() as db:
        db.execute(
            "INSERT INTO packages(id,job_id,record) VALUES(?,?,?)",
            (package_id, job["id"], json.dumps(result)),
        )
    return result


def artifact(store: Store, artifact_id: str) -> dict[str, Any] | None:
    with store.connect() as db:
        row = db.execute(
            "SELECT * FROM artifacts WHERE id=?", (artifact_id,)
        ).fetchone()
    return dict(row) if row else None


def zip_file(
    store: Store, package: dict[str, Any], destination: Path, action: str | None = None
) -> Path:
    ids = []
    if action:
        ids = [x["artifact_id"] for x in package["animations"] if x["action"] == action]
        if not ids:
            raise ValueError("unknown or still-only action")
    else:
        ids = [package[k]["artifact_id"] for k in ("sheet", "metadata", "manifest")] + [
            x["artifact_id"] for x in package["animations"]
        ]
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(
        "." + destination.name + f".{uuid.uuid4().hex}.working"
    )
    with zipfile.ZipFile(
        temporary, "w", zipfile.ZIP_DEFLATED, allowZip64=True
    ) as archive:
        for aid in ids:
            item = artifact(store, aid)
            archive.write(item["path"], Path(item["filename"]).name)
    os.replace(temporary, destination)
    return destination
