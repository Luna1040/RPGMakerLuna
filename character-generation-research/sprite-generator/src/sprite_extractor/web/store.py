from __future__ import annotations
import hashlib, json, sqlite3, threading, time, uuid
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator


def now() -> str:
    from datetime import datetime, timezone

    return datetime.now(timezone.utc).isoformat()


def ident(prefix: str) -> str:
    return prefix + uuid.uuid4().hex


class Store:
    def __init__(self, path: Path, base_path: str = ""):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.path = path
        self.base_path = base_path
        self._lock = threading.RLock()
        self.initialize()

    @contextmanager
    def connect(self) -> Iterator[sqlite3.Connection]:
        db = sqlite3.connect(self.path, timeout=30)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys=ON")
        try:
            yield db
            db.commit()
        finally:
            db.close()

    def initialize(self):
        with self.connect() as db:
            db.executescript("""
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS uploads(id TEXT PRIMARY KEY,record TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS workspaces(id TEXT PRIMARY KEY,record TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS jobs(id TEXT PRIMARY KEY,workspace_id TEXT NOT NULL,status TEXT NOT NULL,created_at TEXT NOT NULL,started_at TEXT,updated_at TEXT NOT NULL,request TEXT NOT NULL,request_fingerprint TEXT,config_snapshot TEXT NOT NULL,definition_snapshot TEXT NOT NULL,resolved_seed TEXT NOT NULL,idempotency_key TEXT UNIQUE,worker_id TEXT,heartbeat REAL,stop_requested INTEGER NOT NULL DEFAULT 0,package_id TEXT,error TEXT,current_stage TEXT,completed_stages INTEGER NOT NULL DEFAULT 0,total_stages INTEGER NOT NULL DEFAULT 0,cached_stages INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS events(job_id TEXT NOT NULL,sequence INTEGER NOT NULL,kind TEXT NOT NULL,timestamp TEXT NOT NULL,data TEXT NOT NULL,PRIMARY KEY(job_id,sequence));
        CREATE TABLE IF NOT EXISTS artifacts(id TEXT PRIMARY KEY,workspace_id TEXT NOT NULL,job_id TEXT,path TEXT NOT NULL,filename TEXT NOT NULL,media_type TEXT NOT NULL,bytes INTEGER NOT NULL,sha256 TEXT NOT NULL,kind TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS packages(id TEXT PRIMARY KEY,job_id TEXT NOT NULL UNIQUE,record TEXT NOT NULL);
        """)
        with self.connect() as db:
            columns = {row[1] for row in db.execute("PRAGMA table_info(jobs)")}
            if "request_fingerprint" not in columns:
                db.execute("ALTER TABLE jobs ADD COLUMN request_fingerprint TEXT")
            for name, definition in (
                ("started_at", "TEXT"),
                ("current_stage", "TEXT"),
                ("completed_stages", "INTEGER NOT NULL DEFAULT 0"),
                ("total_stages", "INTEGER NOT NULL DEFAULT 0"),
                ("cached_stages", "INTEGER NOT NULL DEFAULT 0"),
                ("kind", "TEXT NOT NULL DEFAULT 'render'"),
                ("parent_job_id", "TEXT"),
                ("base_package_id", "TEXT"),
            ):
                if name not in columns:
                    db.execute(f"ALTER TABLE jobs ADD COLUMN {name} {definition}")

    def insert_json(self, table: str, key: str, record: dict[str, Any]):
        with self.connect() as db:
            db.execute(
                f"INSERT INTO {table}(id,record) VALUES(?,?)", (key, json.dumps(record))
            )

    def get_json(self, table: str, key: str) -> dict[str, Any] | None:
        with self.connect() as db:
            row = db.execute(
                f"SELECT record FROM {table} WHERE id=?", (key,)
            ).fetchone()
        return json.loads(row[0]) if row else None

    def create_job(
        self,
        workspace_id: str,
        request: dict[str, Any],
        config: dict[str, Any],
        definition: dict[str, Any],
        key: str,
        original_request: dict[str, Any] | None = None,
        require_workspace: bool = False,
    ) -> tuple[dict[str, Any], bool]:
        stamp = now()
        job_id = ident("job_")
        seed = request["seed"]["value"]
        fingerprint = hashlib.sha256(
            json.dumps(
                original_request or request, sort_keys=True, separators=(",", ":")
            ).encode()
        ).hexdigest()
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            if (
                require_workspace
                and not db.execute(
                    "SELECT 1 FROM workspaces WHERE id=?", (workspace_id,)
                ).fetchone()
            ):
                raise ValueError("workspace_missing")
            prior = db.execute(
                "SELECT id,workspace_id,request_fingerprint FROM jobs WHERE idempotency_key=?",
                (key,),
            ).fetchone()
            if prior:
                if prior["workspace_id"] != workspace_id or prior[
                    "request_fingerprint"
                ] not in (None, fingerprint):
                    raise ValueError("idempotency_conflict")
                return self.job(prior["id"]), False
            db.execute(
                "INSERT INTO jobs(id,workspace_id,status,created_at,updated_at,request,request_fingerprint,config_snapshot,definition_snapshot,resolved_seed,idempotency_key) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                (
                    job_id,
                    workspace_id,
                    "queued",
                    stamp,
                    stamp,
                    json.dumps(request),
                    fingerprint,
                    json.dumps(config),
                    json.dumps(definition),
                    seed,
                    key,
                ),
            )
        self.event(job_id, "state", {"message": "Queued"})
        return self.job(job_id), True

    def create_child_job(
        self,
        parent_id: str,
        kind: str,
        request: dict[str, Any],
        key: str,
        *,
        base_package_id: str | None = None,
    ) -> tuple[dict[str, Any], bool]:
        if kind not in {"cycle_analysis", "cycle_revision"}:
            raise ValueError("invalid_child_kind")
        stamp = now()
        fingerprint = hashlib.sha256(
            json.dumps(
                {
                    "parent_job_id": parent_id,
                    "kind": kind,
                    "base_package_id": base_package_id,
                    "request": request,
                },
                sort_keys=True,
                separators=(",", ":"),
            ).encode()
        ).hexdigest()
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            parent = db.execute(
                "SELECT * FROM jobs WHERE id=?", (parent_id,)
            ).fetchone()
            if parent is None:
                raise ValueError("parent_missing")
            if parent["status"] not in {"ready", "failed", "stopped"}:
                raise ValueError("parent_not_terminal")
            if not db.execute(
                "SELECT 1 FROM workspaces WHERE id=?", (parent["workspace_id"],)
            ).fetchone():
                raise ValueError("workspace_missing")
            prior = db.execute(
                "SELECT id,request_fingerprint FROM jobs WHERE idempotency_key=?",
                (key,),
            ).fetchone()
            if prior:
                if prior["request_fingerprint"] != fingerprint:
                    raise ValueError("idempotency_conflict")
                return self.job(prior["id"]), False
            job_id = ident("job_")
            db.execute(
                "INSERT INTO jobs(id,workspace_id,status,created_at,updated_at,request,request_fingerprint,config_snapshot,definition_snapshot,resolved_seed,idempotency_key,kind,parent_job_id,base_package_id) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (
                    job_id,
                    parent["workspace_id"],
                    "queued",
                    stamp,
                    stamp,
                    json.dumps(request),
                    fingerprint,
                    parent["config_snapshot"],
                    parent["definition_snapshot"],
                    parent["resolved_seed"],
                    key,
                    kind,
                    parent_id,
                    base_package_id,
                ),
            )
        self.event(job_id, "state", {"message": "Queued"})
        return self.job(job_id), True

    def job(self, job_id: str) -> dict[str, Any] | None:
        with self.connect() as db:
            row = db.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone()
        return self._job(row) if row else None

    def _job(self, row) -> dict[str, Any]:
        from datetime import datetime, timezone

        status = row["status"]
        created = row["created_at"]
        request = json.loads(row["request"])
        definition = json.loads(row["definition_snapshot"])
        action_stages = {
            details.get("outputs", {}).get("animation", {}).get("name"): name
            for name, details in definition.get("stages", {}).items()
            if details.get("outputs", {}).get("animation")
        }
        needed = {
            action_stages[name] for name in request["actions"] if name in action_stages
        }
        pending = list(needed)
        while pending:
            stage = definition["stages"][pending.pop()]
            for ref in stage.get("inputs", {}).values():
                dependency = ref.get("stage") if isinstance(ref, dict) else None
                if dependency and dependency not in needed:
                    needed.add(dependency)
                    pending.append(dependency)
        ordered = [name for name in definition.get("stages", {}) if name in needed]
        started = row["started_at"]
        start = datetime.fromisoformat(started or created)
        end = (
            datetime.fromisoformat(row["updated_at"])
            if status in {"ready", "stopped", "failed", "recovery_required"}
            else datetime.now(timezone.utc)
        )
        return {
            "id": row["id"],
            "kind": row["kind"] if "kind" in row.keys() else "render",
            "parent_job_id": (
                row["parent_job_id"] if "parent_job_id" in row.keys() else None
            ),
            "base_package_id": (
                row["base_package_id"] if "base_package_id" in row.keys() else None
            ),
            "workspace_id": row["workspace_id"],
            "status": status,
            "phase": status,
            "current_stage": row["current_stage"],
            "completed_stages": int(row["completed_stages"]),
            "total_stages": int(row["total_stages"]) or len(ordered),
            "cached_stages": int(row["cached_stages"]),
            "resolved_seed": row["resolved_seed"],
            "created_at": created,
            "started_at": started,
            "finished_at": (
                row["updated_at"]
                if status in {"ready", "stopped", "failed", "recovery_required"}
                else None
            ),
            "elapsed_seconds": max(0, (end - start).total_seconds()) if started else 0,
            "stop_requested": bool(row["stop_requested"]),
            "resume_allowed": status in {"stopped", "failed", "recovery_required"},
            "message": row["error"] or status.replace("_", " ").title(),
            "package_id": row["package_id"],
            "request": request,
            "links": {
                "self": f"{self.base_path}/api/jobs/{row['id']}",
                "events": f"{self.base_path}/api/jobs/{row['id']}/events",
            },
        }

    def jobs(self, limit: int = 50) -> list[dict[str, Any]]:
        with self.connect() as db:
            rows = db.execute(
                "SELECT * FROM jobs ORDER BY created_at DESC LIMIT ?", (limit,)
            ).fetchall()
        return [self._job(x) for x in rows]

    def update_job(self, job_id: str, **values: Any):
        values["updated_at"] = now()
        columns = ",".join(f"{k}=?" for k in values)
        with self.connect() as db:
            db.execute(
                f"UPDATE jobs SET {columns} WHERE id=?", (*values.values(), job_id)
            )
        self.event(
            job_id,
            "state",
            {"message": values.get("error") or values.get("status", "Updated")},
        )

    def event(self, job_id: str, kind: str, data: dict[str, Any]):
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            seq = db.execute(
                "SELECT COALESCE(MAX(sequence),0)+1 FROM events WHERE job_id=?",
                (job_id,),
            ).fetchone()[0]
            db.execute(
                "INSERT INTO events VALUES(?,?,?,?,?)",
                (job_id, seq, kind, now(), json.dumps(data)),
            )
            db.execute(
                "DELETE FROM events WHERE job_id=? AND sequence < ?",
                (job_id, max(0, seq - 999)),
            )

    def events(self, job_id: str, cursor: int) -> list[dict[str, Any]]:
        with self.connect() as db:
            rows = db.execute(
                "SELECT * FROM events WHERE job_id=? AND sequence>? ORDER BY sequence",
                (job_id, cursor),
            ).fetchall()
        return [
            {
                "sequence": r["sequence"],
                "event": r["kind"],
                "timestamp": r["timestamp"],
                **json.loads(r["data"]),
            }
            for r in rows
        ]

    def activities(
        self, job_id: str, cursor: int = 0, limit: int = 100
    ) -> list[dict[str, Any]]:
        with self.connect() as db:
            if cursor == 0:
                rows = list(
                    reversed(
                        db.execute(
                            "SELECT * FROM events WHERE job_id=? AND kind='activity' ORDER BY sequence DESC LIMIT ?",
                            (job_id, limit),
                        ).fetchall()
                    )
                )
            else:
                rows = db.execute(
                    "SELECT * FROM events WHERE job_id=? AND kind='activity' AND sequence>? ORDER BY sequence LIMIT ?",
                    (job_id, cursor, limit),
                ).fetchall()
        return [
            {
                "sequence": row["sequence"],
                "timestamp": row["timestamp"],
                **json.loads(row["data"]),
            }
            for row in rows
        ]

    def current_activity(self, job_id: str) -> dict[str, Any] | None:
        with self.connect() as db:
            row = db.execute(
                "SELECT * FROM events WHERE job_id=? AND kind='activity' ORDER BY sequence DESC LIMIT 1",
                (job_id,),
            ).fetchone()
        if row is None:
            return None
        return {
            "sequence": row["sequence"],
            "timestamp": row["timestamp"],
            **json.loads(row["data"]),
        }
