from __future__ import annotations

import json
import inspect
import queue
import threading
import uuid
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .runner import StudioRunner


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class StudioJobManager:
    """One persistent FIFO worker: only one Comfy/GPU job runs at a time."""

    def __init__(self, root: Path, runner: StudioRunner, *, autostart: bool = True):
        self.root = root.resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self.runner = runner
        self._jobs: dict[str, dict[str, Any]] = {}
        self._queue: queue.Queue[str | None] = queue.Queue()
        self._lock = threading.RLock()
        self._shutdown_started = False
        self._thread: threading.Thread | None = None
        self._load_existing()
        self._reconcile_existing()
        self._runner_accepts_prompt_callback = self._supports_prompt_callback()
        if autostart:
            self._thread = threading.Thread(target=self._work, name="studio-gpu-worker", daemon=True)
            self._thread.start()

    def _path(self, job_id: str) -> Path:
        if not job_id.startswith("job_") or len(job_id) != 16:
            raise ValueError("invalid job id")
        return self.root / f"{job_id}.json"

    def _persist(self, job: dict[str, Any]) -> None:
        path = self._path(job["id"])
        temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
        temporary.write_text(json.dumps(job, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        temporary.replace(path)

    def _load_existing(self) -> None:
        for path in self.root.glob("job_*.json"):
            try:
                job = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            job_id = job.get("id")
            if not isinstance(job_id, str):
                continue
            try:
                self._path(job_id)
            except ValueError:
                continue
            current_prompt_id = job.get("prompt_id")
            raw_prompt_ids = job.get("prompt_ids", [])
            prompt_ids: list[str] = []
            if isinstance(raw_prompt_ids, list):
                for value in raw_prompt_ids:
                    clean_value = str(value).strip() if isinstance(value, str) else ""
                    if clean_value and len(clean_value) <= 256 and clean_value not in prompt_ids:
                        prompt_ids.append(clean_value)
            if isinstance(current_prompt_id, str):
                current_prompt_id = current_prompt_id.strip() or None
                if current_prompt_id and len(current_prompt_id) > 256:
                    current_prompt_id = None
            else:
                current_prompt_id = None
            if current_prompt_id and len(current_prompt_id) <= 256 and current_prompt_id not in prompt_ids:
                prompt_ids.append(current_prompt_id)
            if current_prompt_id is None and prompt_ids:
                current_prompt_id = prompt_ids[-1]
            job["prompt_ids"] = prompt_ids
            job["prompt_id"] = current_prompt_id
            self._jobs[job_id] = job

    def _reconcile_existing(self) -> None:
        """Stop persisted Comfy prompts before any new worker is allowed to start."""

        active_statuses = {"queued", "running", "cancelling"}
        cleanup_prompt = getattr(self.runner, "cleanup_prompt", None)
        for job_id, job in list(self._jobs.items()):
            if job.get("status") not in active_statuses:
                continue
            prompt_ids = list(job.get("prompt_ids", []))
            prompt_id = job.get("prompt_id")
            if prompt_id and prompt_id not in prompt_ids:
                prompt_ids.append(prompt_id)
            was_cancel_requested = bool(job.get("cancel_requested")) or job.get("status") == "cancelling"
            if prompt_ids and not callable(cleanup_prompt):
                raise RuntimeError(
                    f"cannot safely reconcile persisted ComfyUI prompts {', '.join(prompt_ids)}: "
                    "runner has no cleanup_prompt()"
                )
            if prompt_ids:
                job["cancel_requested"] = True
                job["status"] = "cancelling"
                job["updated_at"] = _now()
                self._persist(job)
                cleanup_errors: list[str] = []
                for persisted_prompt_id in prompt_ids:
                    try:
                        cleanup_prompt(
                            str(persisted_prompt_id),
                            log=lambda line, current_job_id=job_id: self._append_log(current_job_id, line),
                        )
                    except Exception as exc:
                        cleanup_errors.append(f"{persisted_prompt_id}: {exc}")
                if cleanup_errors:
                    raise RuntimeError(
                        "failed to reconcile all persisted ComfyUI prompts: " + "; ".join(cleanup_errors)
                    )
            now = _now()
            job["status"] = "cancelled" if was_cancel_requested else "interrupted"
            job["error"] = None if was_cancel_requested else "server restarted before the job completed"
            job["cancel_requested"] = was_cancel_requested
            job["completed_at"] = now
            job["updated_at"] = now
            self._persist(job)

    def _supports_prompt_callback(self) -> bool:
        try:
            parameters = inspect.signature(self.runner.run).parameters.values()
        except (TypeError, ValueError):
            return False
        return any(
            parameter.name == "on_prompt_id" or parameter.kind == inspect.Parameter.VAR_KEYWORD
            for parameter in parameters
        )

    @staticmethod
    def _validate_kind(kind: str) -> None:
        if kind not in {
            "canonicalize",
            "motion",
            "viseme_atlas",
            "temporal_repair",
            "runtime_export",
            "component_build",
        }:
            raise ValueError("unsupported job kind")

    @staticmethod
    def _same_unique_job(
        job: dict[str, Any],
        *,
        project_id: str,
        kind: str,
        motion_id: str | None,
        loadout_id: str,
    ) -> bool:
        if job.get("project_id") != project_id or job.get("kind") != kind:
            return False
        if job.get("status") not in {"queued", "running", "cancelling"}:
            return False
        if str(job.get("params", {}).get("loadout_id", "default")) != loadout_id:
            return False
        if kind in {"motion", "temporal_repair", "runtime_export"}:
            return str(job.get("params", {}).get("motion_id", "")) == (motion_id or "")
        return True

    def _submit_locked(self, project_id: str, kind: str, params: dict[str, Any] | None) -> dict[str, Any]:
        job_id = f"job_{uuid.uuid4().hex[:12]}"
        now = _now()
        job = {
            "id": job_id,
            "project_id": project_id,
            "kind": kind,
            "params": deepcopy(params) if params else {},
            "status": "queued",
            "created_at": now,
            "updated_at": now,
            "started_at": None,
            "completed_at": None,
            "cancel_requested": False,
            "prompt_id": None,
            "prompt_ids": [],
            "log": [],
            "result": None,
            "error": None,
        }
        self._jobs[job_id] = job
        self._persist(job)
        self._queue.put(job_id)
        return self.get(job_id)

    def submit(self, project_id: str, kind: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        self._validate_kind(kind)
        with self._lock:
            if self._shutdown_started:
                raise RuntimeError("Studio job manager is shutting down")
            return self._submit_locked(project_id, kind, params)

    def submit_unique(
        self,
        project_id: str,
        kind: str,
        params: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Atomically reject an equivalent active GPU job and enqueue otherwise."""

        self._validate_kind(kind)
        params = params or {}
        motion_id = str(params.get("motion_id", "")) if kind in {"motion", "temporal_repair", "runtime_export"} else None
        loadout_id = str(params.get("loadout_id", "default"))
        with self._lock:
            if self._shutdown_started:
                raise RuntimeError("Studio job manager is shutting down")
            duplicate = any(
                self._same_unique_job(
                    job,
                    project_id=project_id,
                    kind=kind,
                    motion_id=motion_id,
                    loadout_id=loadout_id,
                )
                for job in self._jobs.values()
            )
            if duplicate:
                if kind == "motion":
                    raise RuntimeError(f"motion {motion_id} for loadout {loadout_id} is already queued or running")
                if kind == "viseme_atlas":
                    raise RuntimeError(f"a viseme atlas job for loadout {loadout_id} is already active")
                if kind == "temporal_repair":
                    raise RuntimeError(f"temporal repair for {motion_id} / {loadout_id} is already active")
                if kind == "runtime_export":
                    raise RuntimeError(f"runtime export for {motion_id} / {loadout_id} is already active")
                if kind == "component_build":
                    raise RuntimeError(f"a component build for loadout {loadout_id} is already active")
                raise RuntimeError(f"a canonicalize job for loadout {loadout_id} is already active")
            return self._submit_locked(project_id, kind, params)

    def get(self, job_id: str) -> dict[str, Any]:
        with self._lock:
            if job_id not in self._jobs:
                raise FileNotFoundError(job_id)
            job = deepcopy(self._jobs[job_id])
            job["log_text"] = "\n".join(job.pop("log", [])[-300:])
            return job

    def list(self, project_id: str | None = None) -> list[dict[str, Any]]:
        with self._lock:
            ids = [job_id for job_id, job in self._jobs.items() if project_id is None or job["project_id"] == project_id]
        jobs = [self.get(job_id) for job_id in ids]
        jobs.sort(key=lambda item: item["created_at"], reverse=True)
        return jobs

    def has_active(
        self,
        project_id: str,
        kind: str | None = None,
        motion_id: str | None = None,
        loadout_id: str | None = None,
    ) -> bool:
        with self._lock:
            for job in self._jobs.values():
                if job.get("project_id") != project_id:
                    continue
                if job.get("status") not in {"queued", "running", "cancelling"}:
                    continue
                if kind is not None and job.get("kind") != kind:
                    continue
                if motion_id is not None and str(job.get("params", {}).get("motion_id", "")) != motion_id:
                    continue
                if loadout_id is not None and str(job.get("params", {}).get("loadout_id", "default")) != loadout_id:
                    continue
                return True
        return False

    def cancel(self, job_id: str) -> dict[str, Any]:
        with self._lock:
            if job_id not in self._jobs:
                raise FileNotFoundError(job_id)
            job = self._jobs[job_id]
            if job["status"] in {"succeeded", "failed", "cancelled", "interrupted"}:
                return self.get(job_id)
            job["cancel_requested"] = True
            if job["status"] == "queued":
                job["status"] = "cancelled"
                job["completed_at"] = _now()
            else:
                job["status"] = "cancelling"
            job["updated_at"] = _now()
            self._persist(job)
            return self.get(job_id)

    def _append_log(self, job_id: str, line: str) -> None:
        with self._lock:
            job = self._jobs[job_id]
            job["log"].append(str(line).rstrip())
            job["log"] = job["log"][-1000:]
            job["updated_at"] = _now()
            self._persist(job)

    def _is_cancelled(self, job_id: str) -> bool:
        with self._lock:
            return bool(self._jobs[job_id].get("cancel_requested"))

    def _record_prompt_id(self, job_id: str, prompt_id: str) -> None:
        clean_prompt_id = str(prompt_id).strip()
        if not clean_prompt_id or len(clean_prompt_id) > 256:
            raise ValueError("invalid ComfyUI prompt id")
        with self._lock:
            job = self._jobs[job_id]
            prompt_ids = job.setdefault("prompt_ids", [])
            if not isinstance(prompt_ids, list):
                raise RuntimeError("job prompt_ids persistence is invalid")
            if clean_prompt_id not in prompt_ids:
                prompt_ids.append(clean_prompt_id)
            job["prompt_id"] = clean_prompt_id
            job["updated_at"] = _now()
            self._persist(job)

    def shutdown(self, timeout: float | None = None) -> bool:
        """Cancel queued/running work and wait for the worker's Comfy cleanup."""

        with self._lock:
            if not self._shutdown_started:
                self._shutdown_started = True
                now = _now()
                for job in self._jobs.values():
                    status = job.get("status")
                    if status == "queued":
                        job["cancel_requested"] = True
                        job["status"] = "cancelled"
                        job["completed_at"] = now
                        job["updated_at"] = now
                        self._persist(job)
                    elif status in {"running", "cancelling"}:
                        job["cancel_requested"] = True
                        job["status"] = "cancelling"
                        job["updated_at"] = now
                        self._persist(job)
                if self._thread is not None:
                    self._queue.put(None)
            thread = self._thread
        if thread is None:
            return True
        if thread is threading.current_thread():
            return False
        thread.join(timeout=timeout)
        return not thread.is_alive()

    def _work(self) -> None:
        while True:
            job_id = self._queue.get()
            try:
                if job_id is None:
                    return
                with self._lock:
                    job = self._jobs[job_id]
                    if job["status"] == "cancelled":
                        continue
                    job["status"] = "running"
                    job["started_at"] = _now()
                    job["updated_at"] = _now()
                    self._persist(job)
                    project_id = job["project_id"]
                    kind = job["kind"]
                    params = deepcopy(job["params"])
                runner_kwargs: dict[str, Any] = {
                    "log": lambda line, current_job_id=job_id: self._append_log(current_job_id, line),
                    "cancelled": lambda current_job_id=job_id: self._is_cancelled(current_job_id),
                }
                if self._runner_accepts_prompt_callback:
                    runner_kwargs["on_prompt_id"] = (
                        lambda prompt_id, current_job_id=job_id: self._record_prompt_id(current_job_id, prompt_id)
                    )
                result = self.runner.run(kind, project_id, params, **runner_kwargs)
                with self._lock:
                    job = self._jobs[job_id]
                    if job.get("cancel_requested"):
                        job["status"] = "cancelled"
                    else:
                        job["status"] = "succeeded"
                        job["result"] = result
                    job["completed_at"] = _now()
                    job["updated_at"] = _now()
                    self._persist(job)
            except Exception as exc:
                with self._lock:
                    job = self._jobs[job_id]
                    cancelled = job.get("cancel_requested") or str(exc) == "job cancelled"
                    job["status"] = "cancelled" if cancelled else "failed"
                    job["error"] = None if cancelled else str(exc)
                    job["completed_at"] = _now()
                    job["updated_at"] = _now()
                    self._persist(job)
            finally:
                self._queue.task_done()
