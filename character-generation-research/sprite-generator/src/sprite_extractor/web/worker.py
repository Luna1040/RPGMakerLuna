"""Single-scheduler durable subprocess worker."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import subprocess
import sys
import threading
import time
import uuid
from pathlib import Path
from typing import Any, Callable

from ..application import CooperativeStop, execute_request
from ..runtime_config import load_snapshot
from ..submission_journal import SubmissionRecoveryRequired
from .artifacts import publish_package
from .store import Store, now

Runner = Callable[
    [dict[str, Any], Callable[[str, dict[str, Any]], None], Callable[[], bool]], Any
]
ACTIVE = (
    "preparing",
    "generating",
    "extracting",
    "removing_backgrounds",
    "packaging",
    "stop_requested",
)


def process_identity(pid: int) -> str:
    fields = Path(f"/proc/{pid}/stat").read_text().split()
    return f"{pid}:{fields[21]}"


def process_is_same(identity: str | None) -> bool:
    try:
        pid = int(str(identity).split(":", 1)[0])
        return process_identity(pid) == identity
    except (ValueError, TypeError, OSError, IndexError):
        return False


class Scheduler:
    def __init__(self, store: Store, data_root: Path, runner: Runner | None = None):
        self.store = store
        self.root = data_root
        self.runner = runner
        self.identity = f"scheduler-{os.getpid()}-{uuid.uuid4().hex}"
        self.stop_event = threading.Event()
        self.thread: threading.Thread | None = None
        self.scheduler_lock = None

    def activity_event(self, job_id: str, detail: dict[str, Any]) -> None:
        try:
            self.store.event(job_id, "activity", detail)
        except Exception:
            pass

    def start(self) -> None:
        lock_path = self.root / ".scheduler.lock"
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        self.scheduler_lock = lock_path.open("a+b")
        try:
            fcntl.flock(self.scheduler_lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            self.scheduler_lock.close()
            self.scheduler_lock = None
            raise RuntimeError("another scheduler already owns this data root") from exc
        self.reconcile()
        self.thread = threading.Thread(
            target=self.loop, name="sprite-extractor-scheduler", daemon=True
        )
        self.thread.start()

    def stop(self) -> None:
        self.stop_event.set()
        if self.thread:
            self.thread.join(timeout=3)
        if self.scheduler_lock:
            fcntl.flock(self.scheduler_lock.fileno(), fcntl.LOCK_UN)
            self.scheduler_lock.close()
            self.scheduler_lock = None

    def reconcile(self) -> None:
        placeholders = ",".join("?" for _ in ACTIVE)
        with self.store.connect() as db:
            rows = db.execute(
                f"SELECT id,worker_id FROM jobs WHERE status IN ({placeholders})",
                ACTIVE,
            ).fetchall()
        for row in rows:
            if not process_is_same(row["worker_id"]):
                self.activity_event(
                    row["id"],
                    {
                        "state": "unknown",
                        "operation": "comfy",
                        "stage_id": None,
                        "prompt_id": None,
                        "message": "Worker ownership was lost",
                        "error": {
                            "code": "worker_lost",
                            "message": "Worker ownership was lost; submission recovery may be required",
                            "retryable": False,
                            "recovery_required": True,
                        },
                    },
                )
                self.store.update_job(
                    row["id"],
                    status="recovery_required",
                    error="Worker ownership was lost; explicit recovery is required",
                )

    def loop(self) -> None:
        placeholders = ",".join("?" for _ in ACTIVE)
        while not self.stop_event.wait(0.2):
            self.reconcile()
            with self.store.connect() as db:
                db.execute("BEGIN IMMEDIATE")
                active = db.execute(
                    f"SELECT 1 FROM jobs WHERE status IN ({placeholders}) LIMIT 1",
                    ACTIVE,
                ).fetchone()
                row = (
                    None
                    if active
                    else db.execute(
                        "SELECT id FROM jobs WHERE status='queued' ORDER BY created_at LIMIT 1"
                    ).fetchone()
                )
                if row:
                    db.execute(
                        "UPDATE jobs SET status='preparing',started_at=?,worker_id=?,heartbeat=?,updated_at=? WHERE id=? AND status='queued'",
                        (now(), self.identity, time.time(), now(), row["id"]),
                    )
            if not row:
                continue
            if self.runner:
                self.run(row["id"])
                continue
            try:
                process = subprocess.Popen(
                    [
                        sys.executable,
                        "-m",
                        "sprite_extractor.web.worker",
                        "--run-job",
                        row["id"],
                        "--data-root",
                        str(self.root),
                        "--base-path",
                        self.store.base_path,
                    ],
                    close_fds=True,
                    start_new_session=True,
                )
                owner = process_identity(process.pid)
            except Exception as exc:
                self.activity_event(
                    row["id"],
                    {
                        "state": "failed",
                        "operation": "comfy",
                        "stage_id": None,
                        "prompt_id": None,
                        "message": "Could not start the job worker",
                        "error": {
                            "code": "worker_start_failed",
                            "message": type(exc).__name__,
                            "retryable": True,
                            "recovery_required": False,
                        },
                    },
                )
                self.store.update_job(
                    row["id"], status="failed", error=f"Could not start worker: {exc}"
                )
                continue
            self.store.update_job(row["id"], worker_id=owner, heartbeat=time.time())
            while process.poll() is None and not self.stop_event.wait(0.5):
                pass
            if process.poll() is not None:
                current = self.store.job(row["id"])
                if current and current["status"] in ACTIVE:
                    self.activity_event(
                        row["id"],
                        {
                            "state": "unknown",
                            "operation": "comfy",
                            "stage_id": current.get("current_stage"),
                            "prompt_id": None,
                            "message": "The job worker exited unexpectedly",
                            "error": {
                                "code": "worker_exited",
                                "message": f"Worker exited with status {process.returncode}",
                                "retryable": False,
                                "recovery_required": True,
                            },
                        },
                    )
                    self.store.update_job(
                        row["id"],
                        status="recovery_required",
                        error=f"Worker exited with status {process.returncode}",
                    )

    def run(self, job_id: str) -> None:
        job = self.store.job(job_id)
        if job is None:
            return

        def progress(phase: str, detail: dict[str, Any]) -> None:
            updates = {"status": phase, "heartbeat": time.time()}
            for key in (
                "current_stage",
                "completed_stages",
                "total_stages",
                "cached_stages",
            ):
                if key in detail:
                    updates[key] = detail[key]
            self.store.update_job(job_id, **updates)
            self.store.event(job_id, "progress", detail)
            if detail.get("completed_stage"):
                from .previews import capture_job_revisions

                try:
                    capture_job_revisions(
                        self.root,
                        job["workspace_id"],
                        job["resolved_seed"],
                        job_id,
                        {detail["completed_stage"]},
                    )
                except (OSError, ValueError, KeyError) as exc:
                    self.store.event(
                        job_id,
                        "log",
                        {"message": f"Raw preview index was not updated: {exc}"},
                    )

        def stopped() -> bool:
            current = self.store.job(job_id)
            return bool(current and current["stop_requested"])

        def activity(detail: dict[str, Any]) -> None:
            try:
                self.store.event(job_id, "activity", detail)
            except Exception:
                # Telemetry cannot control inference or job terminal state.
                pass

        try:
            if self.runner:
                self.runner(job, progress, stopped)
                current = self.store.job(job_id)
                if current and current["status"] not in {
                    "ready",
                    "failed",
                    "stopped",
                    "recovery_required",
                }:
                    self.store.update_job(job_id, status="ready", error=None)
                return
            with self.store.connect() as db:
                row = db.execute(
                    "SELECT config_snapshot,definition_snapshot FROM jobs WHERE id=?",
                    (job_id,),
                ).fetchone()
            config = load_snapshot(json.loads(row[0]))
            workspace = self.store.get_json("workspaces", job["workspace_id"])
            upload = self.store.get_json("uploads", workspace["upload_id"])
            engine = (
                self.root
                / "workspaces"
                / job["workspace_id"]
                / "generation-sets"
                / job["resolved_seed"]
            )
            engine.mkdir(parents=True, exist_ok=True)
            definition = json.loads(row[1])
            from ..animation_definitions import registry_from_snapshot

            registry = registry_from_snapshot(definition)
            if job.get("kind") in {"cycle_analysis", "cycle_revision"}:
                self.run_cycle_child(
                    job, config, registry, engine, progress, stopped, activity
                )
                return

            def cycle_analysis_ready(character, action, analysis, generation):
                from ..cycle_review import register_cycle_analysis
                from ..io_utils import atomic_write_json, load_json

                register_cycle_analysis(
                    self.store, job["workspace_id"], job_id, analysis
                )
                summary = load_json(Path(analysis) / "summary.json")
                target = (
                    self.root
                    / "workspaces"
                    / job["workspace_id"]
                    / "cycle-job-index"
                    / f"{job_id}.json"
                )
                document = (
                    load_json(target)
                    if target.is_file()
                    else {
                        "version": 1,
                        "job_id": job_id,
                        "engine_package_id": None,
                        "groups": [],
                    }
                )
                document["groups"] = [
                    item for item in document["groups"] if item.get("action") != action
                ]
                document["groups"].append(
                    {
                        "character": character["name"],
                        "action": action,
                        "analysis_path": str(Path(analysis).resolve()),
                        "analysis_id": summary["analysis_id"],
                        "sample_set_id": summary["sample_set_id"],
                        "selected_candidate_id": summary["system_candidate_id"],
                        "system_candidate_id": summary["system_candidate_id"],
                        "selection_origin": "automatic",
                        "generation_id": (
                            generation.get("generation_id") if generation else None
                        ),
                        "video_sha256": (
                            generation.get("sha256") if generation else None
                        ),
                    }
                )
                atomic_write_json(target, document)

            result_state = execute_request(
                job["request"],
                config,
                Path(upload["path"]),
                engine,
                registry=registry,
                progress=progress,
                should_stop=stopped,
                activity=activity,
                cycle_analysis_callback=cycle_analysis_ready,
            )
            if result_state is None:
                from ..io_utils import load_json

                result_state = load_json(engine / "staged-generation-state.json")
            engine_package_id = result_state["characters"][0].get("selected_package_id")
            if not engine_package_id:
                raise RuntimeError(
                    "packaging completed without an immutable package identity"
                )
            from ..cycle_review import capture_job_cycle_index

            capture_job_cycle_index(
                self.store,
                self.root,
                self.store.job(job_id),
                engine,
                result_state,
                engine_package_id,
            )
            package = publish_package(
                self.store,
                self.root,
                self.store.job(job_id),
                engine,
                engine_package_id=engine_package_id,
            )
            self.store.update_job(
                job_id, status="ready", package_id=package["id"], error=None
            )
        except CooperativeStop as exc:
            activity(
                {
                    "state": "idle",
                    "operation": "comfy",
                    "stage_id": None,
                    "prompt_id": None,
                    "message": "The job stopped; no ComfyUI work is being started",
                    "error": None,
                }
            )
            self.store.update_job(job_id, status="stopped", error=str(exc))
        except SubmissionRecoveryRequired as exc:
            activity(
                {
                    "state": "unknown",
                    "operation": "comfy",
                    "stage_id": None,
                    "prompt_id": None,
                    "message": "Submission recovery is required",
                    "error": {
                        "code": "submission_unknown",
                        "message": str(exc)[:1000],
                        "retryable": False,
                        "recovery_required": True,
                    },
                }
            )
            self.store.update_job(job_id, status="recovery_required", error=str(exc))
        except Exception as exc:
            prior_activity = self.store.current_activity(job_id)
            if not prior_activity or prior_activity.get("state") not in {
                "failed",
                "disconnected",
                "unknown",
            }:
                current_job = self.store.job(job_id) or {}
                activity(
                    {
                        "state": "failed",
                        "operation": (
                            "comfy"
                            if current_job.get("status")
                            in {"generating", "extracting", "removing_backgrounds"}
                            else "packaging"
                        ),
                        "stage_id": current_job.get("current_stage"),
                        "prompt_id": None,
                        "message": "The job failed",
                        "error": {
                            "code": "job_failed",
                            "message": f"{type(exc).__name__}: {str(exc)[:300]}",
                            "retryable": False,
                            "recovery_required": False,
                        },
                    }
                )
            self.store.update_job(
                job_id, status="failed", error=f"{type(exc).__name__}: {exc}"
            )

    def run_cycle_child(
        self, job, config, registry, engine, progress, stopped, activity
    ) -> None:
        from ..cycle_review import (
            capture_job_cycle_index,
            ensure_cycle_analysis,
            legacy_pose_evidence,
            load_cycle_index,
            register_cycle_analysis,
            resolve_pinned_analyses,
            resolve_pinned_sources,
        )
        from ..definition_runtime import package_definitions
        from ..execution_lock import output_tree_lock
        from ..execution_hooks import execution_hooks, set_activity_stage
        from ..io_utils import atomic_write_json, load_json
        from ..submission_journal import use_submission_journal

        parent_id = job["parent_job_id"]
        request = job["request"]
        pins = request.get("_cycle_pins", {})
        sources = resolve_pinned_sources(
            self.store, self.root, job["id"], pins.get("sources", {})
        )
        if job["kind"] == "cycle_analysis":
            inherited = load_cycle_index(self.store, self.root, parent_id, inherit=True)
            resolved_analyses = resolve_pinned_analyses(
                self.root, engine, pins.get("analyses", {})
            )
            groups = []
            for action, analysis in resolved_analyses.items():
                source = sources.get(action)
                pin = pins["analyses"][action]
                if source is None:
                    continue
                groups.append(
                    {
                        "character": "character",
                        "action": action,
                        "analysis_path": str(analysis),
                        "analysis_id": pin["analysis_id"],
                        "sample_set_id": pin["sample_set_id"],
                        "selected_candidate_id": pin["selected_candidate_id"],
                        "system_candidate_id": pin["system_candidate_id"],
                        "selection_origin": pin.get("selection_origin", "automatic"),
                        "generation_id": source["generation_id"],
                        "video_sha256": source["sha256"],
                    }
                )
            inherited_identities = (
                inherited[0].get("artifact_identities", {}) if inherited else {}
            )
            actions = request.get("_cycle_actions", [])
            target = (
                self.root
                / "workspaces"
                / job["workspace_id"]
                / "cycle-job-index"
                / f"{job['id']}.json"
            )
            with (
                output_tree_lock(engine),
                use_submission_journal(engine / "submission-journal.json"),
                execution_hooks(progress, stopped, activity),
            ):
                for action in actions:
                    if stopped():
                        raise CooperativeStop("stopped before cycle analysis")
                    source = sources.get(action)
                    if not source:
                        raise ValueError(
                            f"saved generated video is unavailable for {action}"
                        )
                    stage_id = source["stage_id"]
                    set_activity_stage(stage_id)
                    progress(
                        "extracting",
                        {
                            "current_stage": stage_id,
                            "operation": "cycle_analysis",
                            "action": action,
                        },
                    )
                    analysis = ensure_cycle_analysis(
                        source["path"],
                        engine / "cycle-analyses",
                        frame_count=request["frame_counts"][action],
                        server=config.as_dict()["comfyui_url"],
                        config=config.as_dict(),
                        timeout=float(config.as_dict()["generation_timeout"]),
                        poll_interval=2.0,
                        raw_pose_evidence=legacy_pose_evidence(
                            self.store, self.root, parent_id, action, source["sha256"]
                        ),
                    )
                    summary = load_json(analysis / "summary.json")
                    register_cycle_analysis(
                        self.store, job["workspace_id"], job["id"], analysis
                    )
                    groups = [item for item in groups if item.get("action") != action]
                    groups.append(
                        {
                            "character": "character",
                            "action": action,
                            "analysis_path": str(analysis),
                            "analysis_id": summary["analysis_id"],
                            "sample_set_id": summary["sample_set_id"],
                            "selected_candidate_id": summary["system_candidate_id"],
                            "system_candidate_id": summary["system_candidate_id"],
                            "selection_origin": "automatic",
                            "generation_id": source["generation_id"],
                            "video_sha256": source["sha256"],
                        }
                    )
                    atomic_write_json(
                        target,
                        {
                            "version": 1,
                            "job_id": job["id"],
                            "engine_package_id": None,
                            "artifact_identities": inherited_identities,
                            "groups": groups,
                        },
                    )
            self.store.update_job(
                job["id"], status="ready", package_id=None, error=None
            )
            return

        inherited = load_cycle_index(self.store, self.root, parent_id, inherit=True)
        selections = request.get("_cycle_selections", {})
        pinned_analyses = resolve_pinned_analyses(
            self.root, engine, pins.get("analyses", {})
        )
        chosen = {}
        origins = {}
        for action, selection in selections.items():
            item = pins.get("analyses", {}).get(action)
            if not item or item.get("analysis_id") != selection.get("analysis_id"):
                raise ValueError(
                    f"cycle analysis changed or is unavailable for {action}"
                )
            if action not in pinned_analyses:
                raise ValueError(f"pinned cycle sample is unavailable for {action}")
            chosen[action] = selection["candidate_id"]
            origins[action] = (
                item.get("selection_origin", "automatic")
                if selection["candidate_id"] == item.get("selected_candidate_id")
                else "user"
            )
        generation_ids = {
            action: item["generation_id"] for action, item in sources.items()
        }
        artifact_identities = inherited[0].get("artifact_identities", {}) if inherited else {}
        pose_ids = {
            pose: artifact_identities.get(f"pose:{pose}", {}).get("generation_id")
            for pose in request.get("poses", [])
        }
        with (
            output_tree_lock(engine),
            use_submission_journal(engine / "submission-journal.json"),
            execution_hooks(progress, stopped, activity),
        ):
            state = load_json(engine / "staged-generation-state.json")
            progress("extracting", {"operation": "cycle_revision"})
            result_state = package_definitions(
                state,
                engine,
                registry,
                actions=request["actions"],
                poses=request.get("poses", ()),
                frame_counts=request["frame_counts"],
                height=request["sprite_size"],
                split_algorithm=request["split_method"],
                server=config.as_dict()["comfyui_url"],
                config=config.as_dict(),
                timeout=float(config.as_dict()["generation_timeout"]),
                progress=progress,
                should_stop=stopped,
                cycle_selections=chosen,
                pinned_analyses=pinned_analyses,
                pinned_generation_ids=generation_ids,
                pinned_pose_generation_ids=pose_ids,
                cycle_selection_origins=origins,
            )
        if not result_state.get("complete"):
            failures = [
                item.get("error")
                for character in result_state.get("characters", [])
                for item in character.get("packages", {}).values()
                if item.get("status") == "failed" and item.get("error")
            ]
            raise RuntimeError(
                failures[-1] if failures else "cycle revision packaging failed"
            )
        engine_package_id = result_state["characters"][0].get("selected_package_id")
        if not engine_package_id:
            raise RuntimeError("cycle revision produced no package identity")
        capture_job_cycle_index(
            self.store, self.root, job, engine, result_state, engine_package_id
        )
        package = publish_package(
            self.store,
            self.root,
            self.store.job(job["id"]),
            engine,
            engine_package_id=engine_package_id,
        )
        self.store.update_job(
            job["id"], status="ready", package_id=package["id"], error=None
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-job", required=True)
    parser.add_argument("--data-root", required=True)
    parser.add_argument("--base-path", default="")
    args = parser.parse_args()
    root = Path(args.data_root).resolve()
    Scheduler(Store(root / "jobs.sqlite3", args.base_path), root).run(args.run_job)


if __name__ == "__main__":
    main()
