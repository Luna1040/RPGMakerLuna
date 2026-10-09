"""Context-scoped durable journal for every ComfyUI prompt submission."""

from __future__ import annotations

import contextvars
import uuid
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator

from .io_utils import atomic_write_json, canonical_json, load_json, sha256_bytes

_path: contextvars.ContextVar[Path | None] = contextvars.ContextVar(
    "submission_journal", default=None
)


class SubmissionRecoveryRequired(RuntimeError):
    pass


@contextmanager
def use_submission_journal(path: str | Path) -> Iterator[None]:
    token = _path.set(Path(path).resolve())
    try:
        yield
    finally:
        _path.reset(token)


def _read(path: Path) -> dict[str, Any]:
    if path.is_file():
        return load_json(path)
    return {"version": 1, "submissions": {}}


def prepare(
    graph: dict[str, Any], explicit: str | None = None, *, server: str = ""
) -> tuple[str, str, dict[str, Any] | None]:
    path = _path.get()
    identity = sha256_bytes(canonical_json({"server": server, "graph": graph}))
    if path is None:
        return identity, explicit or uuid.uuid4().hex, None
    document = _read(path)
    record = document["submissions"].get(identity)
    if record is None:
        record = {
            "graph_sha256": identity,
            "client_id": explicit or uuid.uuid4().hex,
            "status": "prepared",
        }
        document["submissions"][identity] = record
        atomic_write_json(path, document)
    elif explicit and record.get("client_id") != explicit:
        raise SubmissionRecoveryRequired(
            "submission identity has a different durable client ID"
        )
    return identity, record["client_id"], record


def update(identity: str, **changes: Any) -> None:
    path = _path.get()
    if path is None:
        return
    document = _read(path)
    record = document["submissions"].setdefault(identity, {"graph_sha256": identity})
    record.update(changes)
    atomic_write_json(path, document)


def cached_upload(source_sha256: str, server: str) -> dict[str, str] | None:
    path = _path.get()
    if path is None:
        return None
    key = sha256_bytes(canonical_json({"server": server, "source": source_sha256}))
    return _read(path).get("uploads", {}).get(key)


def record_upload(source_sha256: str, server: str, descriptor: dict[str, str]) -> None:
    path = _path.get()
    if path is None:
        return
    document = _read(path)
    key = sha256_bytes(canonical_json({"server": server, "source": source_sha256}))
    document.setdefault("uploads", {})[key] = descriptor
    atomic_write_json(path, document)
