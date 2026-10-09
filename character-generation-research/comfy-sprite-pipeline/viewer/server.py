from __future__ import annotations

import argparse
import cgi
import json
import io
import mimetypes
import os
import posixpath
import shutil
import subprocess
import sys
import threading
import time
import tempfile
import urllib.request
import uuid
import zipfile
from dataclasses import dataclass, field
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, unquote, urlparse
from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parent.parent
STATIC_ROOT = PROJECT_ROOT / "viewer" / "static"
UPLOAD_ROOT = PROJECT_ROOT / "viewer" / "uploads"
DEFAULT_OUTPUT_ROOT = (
    Path(os.environ.get("COMFYUI_ROOT", PROJECT_ROOT.parent / "ComfyUI"))
    / "output"
    / "character_pipeline"
).expanduser().resolve()
QUICK_PIPELINE = PROJECT_ROOT / "drivers" / "run_quick_sprite_pipeline.py"
FRAME_INTERPOLATION_WORKFLOW = PROJECT_ROOT / "workflows" / "w3-frame-interpolation" / "workflow_api.json"
PYTHON_EXE = Path(os.environ.get("PIPELINE_PYTHON", sys.executable)).expanduser().resolve()

if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from drivers.pose_presets import list_presets  # noqa: E402
from drivers._local_config import COMFYUI_ROOT, COMFY_URL  # noqa: E402
from studio.capabilities import inspect_capabilities  # noqa: E402
from studio.catalog import get_motion, studio_schema  # noqa: E402
from studio.components import (  # noqa: E402
    PUBLIC_ACTIONS,
    component_actions_payload,
    component_build_progress,
    build_component_manifest,
    component_motion_ids,
    component_requested_actions,
    normalize_component_actions,
    component_pipeline_results,
)
from studio.jobs import StudioJobManager  # noqa: E402
from studio.planner import build_generation_plan  # noqa: E402
from studio.prompt_tags import PromptTagStore, compile_tags, public_catalog  # noqa: E402
from studio.runner import StudioRunner  # noqa: E402
from studio.runtime import build_runtime_manifest  # noqa: E402
from studio.store import StudioStore  # noqa: E402
from studio.visemes import (  # noqa: E402
    build_rhubarb_command,
    build_runtime_timeline,
    normalize_tts_timings,
    parse_rhubarb_json,
    smooth_cues,
)

RHUBARB_EXE = Path(
    os.environ.get(
        "RHUBARB_EXE",
        shutil.which("rhubarb")
        or PROJECT_ROOT / "tools" / "bin" / "rhubarb" / "Rhubarb-Lip-Sync-1.14.0-Windows" / "rhubarb.exe",
    )
).expanduser()
FFMPEG_EXE = Path(os.environ.get("FFMPEG_EXE", shutil.which("ffmpeg") or "ffmpeg")).expanduser()


@dataclass
class JobState:
    id: str
    params: dict[str, Any]
    source_path: str
    status: str = "queued"
    created_at: float = field(default_factory=time.time)
    updated_at: float = field(default_factory=time.time)
    log_lines: list[str] = field(default_factory=list)
    result: dict[str, Any] | None = None
    error: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "params": self.params,
            "source_path": self.source_path,
            "status": self.status,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "log": "".join(self.log_lines[-200:]),
            "result": self.result,
            "error": self.error,
        }


JOBS: dict[str, JobState] = {}
JOBS_LOCK = threading.Lock()


def iter_animation_dirs(base_dir: Path) -> list[Path]:
    if not base_dir.exists():
        return []
    return sorted((item for item in base_dir.iterdir() if item.is_dir()), key=lambda item: item.name.lower())


def build_index(output_root: Path) -> dict[str, object]:
    base_animations_root = output_root / "base_animations"
    animations: list[dict[str, object]] = []

    for animation_dir in iter_animation_dirs(base_animations_root):
        mp4s = sorted(animation_dir.glob("*.mp4"))
        spritesheets = sorted(animation_dir.glob("*_spritesheet_*.png"))
        poses = sorted((animation_dir / "poses").glob("*.png"))
        renders = [
            {
                "name": mp4.name,
                "url": f"/media/{mp4.relative_to(output_root).as_posix()}",
                "size_mb": round(mp4.stat().st_size / (1024 * 1024), 2),
                "modified": int(mp4.stat().st_mtime),
            }
            for mp4 in reversed(mp4s)
        ]
        sprite_renders = [
            {
                "name": png.name,
                "url": f"/media/{png.relative_to(output_root).as_posix()}",
                "size_mb": round(png.stat().st_size / (1024 * 1024), 2),
                "modified": int(png.stat().st_mtime),
            }
            for png in reversed(spritesheets)
        ]

        if not renders and not sprite_renders:
            continue

        pose_preview = None
        if poses:
            latest_pose = poses[-1]
            pose_preview = f"/media/{latest_pose.relative_to(output_root).as_posix()}"

        animations.append(
            {
                "id": animation_dir.name,
                "title": animation_dir.name.replace("_", " "),
                "preview": pose_preview,
                "poses_count": len(poses),
                "renders": renders,
                "spritesheets": sprite_renders,
            }
        )

    cosmetics_root = output_root / "cosmetics"
    cosmetics = []
    if cosmetics_root.exists():
        for item in sorted(cosmetics_root.glob("*")):
            if item.is_file():
                cosmetics.append(
                    {
                        "name": item.name,
                        "url": f"/media/{item.relative_to(output_root).as_posix()}",
                        "size_mb": round(item.stat().st_size / (1024 * 1024), 2),
                    }
                )

    return {
        "output_root": str(output_root),
        "animations": animations,
        "cosmetics": cosmetics,
    }


def presets_payload() -> list[dict[str, Any]]:
    return [
        {
            "slug": preset.slug,
            "label": preset.label,
            "frames": preset.output_frames,
            "render_frames": preset.num_frames,
            "fps": preset.fps,
            "description": preset.pose_description,
        }
        for preset in list_presets()
    ]


def add_job_log(job: JobState, line: str) -> None:
    with JOBS_LOCK:
        job.log_lines.append(line)
        job.updated_at = time.time()


def update_job(job_id: str, **kwargs: Any) -> None:
    with JOBS_LOCK:
        job = JOBS[job_id]
        for key, value in kwargs.items():
            setattr(job, key, value)
        job.updated_at = time.time()


def create_upload_copy(form: cgi.FieldStorage) -> tuple[Path, str | None, int, bool, str | None]:
    file_item = form["source_file"] if "source_file" in form else None
    cell_size = int(form.getfirst("cell_size", "512"))
    greyscale = form.getfirst("greyscale", "false").lower() in {"1", "true", "yes", "on"}
    animation_name = (form.getfirst("animation_name", "") or "").strip() or None
    extra_prompt = (form.getfirst("extra_prompt", "") or "").strip() or None

    if file_item is None or not getattr(file_item, "filename", ""):
        raise ValueError("source_file is required")

    original_name = Path(file_item.filename).name
    suffix = Path(original_name).suffix or ".png"
    safe_name = f"{int(time.time())}_{uuid.uuid4().hex[:8]}{suffix.lower()}"
    UPLOAD_ROOT.mkdir(parents=True, exist_ok=True)
    target = UPLOAD_ROOT / safe_name
    target.write_bytes(file_item.file.read())
    return target, animation_name, cell_size, greyscale, extra_prompt


def start_generation_job(
    source_path: Path,
    preset: str,
    cell_size: int,
    greyscale: bool,
    animation_name: str | None,
    extra_prompt: str | None,
) -> JobState:
    UPLOAD_ROOT.mkdir(parents=True, exist_ok=True)
    job_id = uuid.uuid4().hex[:10]
    params = {
        "preset": preset,
        "cell_size": cell_size,
        "greyscale": greyscale,
        "name": animation_name or "",
        "extra_prompt": extra_prompt or "",
    }
    job = JobState(id=job_id, params=params, source_path=str(source_path.resolve()))
    with JOBS_LOCK:
        JOBS[job_id] = job

    cmd = [
        str(PYTHON_EXE),
        "-u",
        str(QUICK_PIPELINE),
        "--source",
        str(source_path.resolve()),
        "--preset",
        preset,
        "--cell-size",
        str(cell_size),
    ]
    if animation_name:
        cmd.extend(["--name", animation_name])
    if extra_prompt:
        cmd.extend(["--extra-prompt", extra_prompt])
    if greyscale:
        cmd.append("--greyscale")

    def run() -> None:
        update_job(job_id, status="running")
        try:
            process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
                cwd=str(PROJECT_ROOT),
                bufsize=1,
            )
        except Exception as exc:
            update_job(job_id, status="failed", error=str(exc))
            return

        result_payload: dict[str, Any] | None = None
        assert process.stdout is not None
        for line in process.stdout:
            add_job_log(job, line)
            if line.startswith("RESULT_JSON:"):
                payload = line.split("RESULT_JSON:", 1)[1].strip()
                try:
                    result_payload = json.loads(payload)
                except json.JSONDecodeError:
                    pass

        return_code = process.wait()
        if return_code == 0:
            update_job(job_id, status="succeeded", result=result_payload or {})
        else:
            update_job(job_id, status="failed", error=f"Pipeline exited with code {return_code}", result=result_payload)

    threading.Thread(target=run, daemon=True).start()
    return job


def start_generate_all_job(
    source_path: Path,
    cell_size: int,
    greyscale: bool,
    animation_prefix: str | None,
    extra_prompt: str | None,
) -> JobState:
    presets = list_presets()
    job_id = uuid.uuid4().hex[:10]
    params = {
        "mode": "all",
        "preset_count": len(presets),
        "cell_size": cell_size,
        "greyscale": greyscale,
        "name": animation_prefix or "",
        "extra_prompt": extra_prompt or "",
    }
    job = JobState(id=job_id, params=params, source_path=str(source_path.resolve()))
    with JOBS_LOCK:
        JOBS[job_id] = job

    def run() -> None:
        update_job(job_id, status="running")
        last_result: dict[str, Any] | None = None
        for index, preset in enumerate(presets, start=1):
            generated_name = f"{animation_prefix}_{preset.slug}" if animation_prefix else preset.slug
            add_job_log(job, f"\n=== [{index}/{len(presets)}] {preset.slug} -> {generated_name} ===\n")
            cmd = [
                str(PYTHON_EXE),
                "-u",
                str(QUICK_PIPELINE),
                "--source",
                str(source_path.resolve()),
                "--preset",
                preset.slug,
                "--cell-size",
                str(cell_size),
                "--name",
                generated_name,
            ]
            if extra_prompt:
                cmd.extend(["--extra-prompt", extra_prompt])
            if greyscale:
                cmd.append("--greyscale")
            try:
                process = subprocess.Popen(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    cwd=str(PROJECT_ROOT),
                    bufsize=1,
                )
            except Exception as exc:
                update_job(job_id, status="failed", error=str(exc), result=last_result)
                return

            assert process.stdout is not None
            for line in process.stdout:
                add_job_log(job, line)
                if line.startswith("RESULT_JSON:"):
                    payload = line.split("RESULT_JSON:", 1)[1].strip()
                    try:
                        last_result = json.loads(payload)
                    except json.JSONDecodeError:
                        pass

            return_code = process.wait()
            if return_code != 0:
                update_job(
                    job_id,
                    status="failed",
                    error=f"Batch stopped on preset '{preset.slug}' with code {return_code}",
                    result=last_result,
                )
                return

        update_job(job_id, status="succeeded", result=last_result or {})

    threading.Thread(target=run, daemon=True).start()
    return job


class ViewerHandler(SimpleHTTPRequestHandler):
    server_version = "CharacterViewer/3.0"

    def __init__(
        self,
        *args,
        static_root: Path,
        output_root: Path,
        studio_store: StudioStore,
        studio_jobs: StudioJobManager,
        prompt_tags: PromptTagStore,
        **kwargs,
    ):
        self.static_root = static_root
        self.output_root = output_root
        self.studio_store = studio_store
        self.studio_jobs = studio_jobs
        self.prompt_tags = prompt_tags
        super().__init__(*args, directory=str(static_root), **kwargs)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)

        if parsed.path == "/api/index":
            self._serve_json(build_index(self.output_root))
            return
        if parsed.path == "/api/presets":
            self._serve_json({"presets": presets_payload()})
            return
        if parsed.path == "/api/component-actions":
            self._serve_json({"actions": component_actions_payload()})
            return
        if parsed.path == "/api/studio/schema":
            self._serve_json(studio_schema())
            return
        if parsed.path == "/api/studio/capabilities":
            self._serve_json(
                inspect_capabilities(
                    project_root=PROJECT_ROOT,
                    comfyui_root=COMFYUI_ROOT,
                    comfy_url=COMFY_URL,
                )
            )
            return
        if parsed.path == "/api/prompt-tags":
            query = parse_qs(parsed.query)
            self._serve_json(public_catalog(query.get("action", [""])[0], query.get("stage", ["w1"])[0], self.prompt_tags.list()))
            return
        if parsed.path == "/api/studio/projects":
            self._serve_json({"projects": self.studio_store.list_projects()})
            return
        if parsed.path == "/api/studio/jobs":
            query = parse_qs(parsed.query)
            project_id = query.get("project_id", [None])[0]
            self._serve_json({"jobs": self.studio_jobs.list(project_id)})
            return
        if parsed.path.startswith("/api/components/"):
            if parsed.path.endswith("/package"):
                self._handle_component_package(parsed.path)
                return
            self._handle_component_get(parsed.path)
            return
        if parsed.path.startswith("/api/studio/jobs/"):
            job_id = parsed.path.rsplit("/", 1)[-1]
            try:
                self._serve_json(self.studio_jobs.get(job_id))
            except (ValueError, FileNotFoundError) as exc:
                self._serve_api_error(exc)
            return
        if parsed.path.startswith("/api/studio/projects/"):
            self._handle_studio_project_get(parsed.path, parsed.query)
            return
        if parsed.path.startswith("/studio-media/"):
            self._serve_studio_media(parsed.path)
            return
        if parsed.path.startswith("/api/jobs/"):
            job_id = parsed.path.split("/api/jobs/", 1)[1]
            with JOBS_LOCK:
                job = JOBS.get(job_id)
            if job is None:
                self.send_error(HTTPStatus.NOT_FOUND, "Job not found")
                return
            self._serve_json(job.to_dict())
            return
        if parsed.path.startswith("/media/"):
            self._serve_media(parsed.path[len("/media/") :])
            return
        if parsed.path in {"/studio", "/studio/"}:
            self.path = "/character-creator.html"
        elif parsed.path == "/":
            self.path = "/character-creator.html"

        super().do_GET()

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/generate":
            self._handle_generate()
            return
        if parsed.path == "/api/generate-all":
            self._handle_generate_all()
            return
        if parsed.path == "/api/studio/projects":
            self._handle_studio_project_create()
            return
        if parsed.path == "/api/components":
            self._handle_component_create()
            return
        if parsed.path == "/api/prompt-tags":
            try:
                payload = self._read_json()
                self._serve_json(self.prompt_tags.create(label=str(payload.get("label", "")), text=str(payload.get("text", "")), kind=str(payload.get("kind", ""))), status=HTTPStatus.CREATED)
            except (ValueError, OSError, json.JSONDecodeError) as exc:
                self._serve_api_error(exc)
            return
        if parsed.path.startswith("/api/components/") and parsed.path.endswith("/rebuild"):
            self._handle_component_rebuild(parsed.path)
            return
        if parsed.path.startswith("/api/components/") and parsed.path.endswith("/w3-edit"):
            self._handle_component_w3_edit(parsed.path)
            return
        if parsed.path.startswith("/api/components/") and parsed.path.endswith("/interpolate-frame"):
            self._handle_component_frame_interpolation(parsed.path)
            return
        if parsed.path.startswith("/api/studio/projects/"):
            self._handle_studio_project_post(parsed.path)
            return
        if parsed.path.startswith("/api/studio/jobs/") and parsed.path.endswith("/cancel"):
            job_id = parsed.path.split("/api/studio/jobs/", 1)[1].rsplit("/cancel", 1)[0]
            try:
                self._serve_json(self.studio_jobs.cancel(job_id))
            except (ValueError, FileNotFoundError) as exc:
                self._serve_api_error(exc)
            return
        self.send_error(HTTPStatus.NOT_FOUND, "Not found")

    def do_DELETE(self) -> None:
        parsed = urlparse(self.path)
        if not parsed.path.startswith("/api/components/"):
            self.send_error(HTTPStatus.NOT_FOUND, "Not found")
            return
        suffix = parsed.path.split("/api/components/", 1)[1].strip("/")
        parts = suffix.split("/") if suffix else []
        if len(parts) == 3 and parts[1] == "actions":
            component_id, action_id = parts[0], parts[2]
            try:
                if action_id not in PUBLIC_ACTIONS:
                    raise ValueError("unknown component action")
                if self.studio_jobs.has_active(component_id, kind="component_build"):
                    raise RuntimeError("нельзя удалить анимацию во время рендера")
                project = self.studio_store.remove_component_action(component_id, action_id)
                actions = component_requested_actions(project)
                records = (project.get("component") or {}).get("actions", {})
                manifest_ready = all(
                    isinstance(records.get(action), dict) and records[action].get("status") == "ready"
                    for action in actions
                )
                if manifest_ready:
                    build_component_manifest(project, "default", requested_actions=actions)
                self._serve_json({
                    "ok": True,
                    "id": component_id,
                    "removed_action": action_id,
                    "actions": actions,
                    "pipeline": component_pipeline_results(project, actions),
                    "manifest_url": f"/api/components/{component_id}/manifest" if manifest_ready else None,
                })
            except (ValueError, FileNotFoundError, RuntimeError) as exc:
                self._serve_api_error(exc)
            return
        if len(parts) != 1:
            self.send_error(HTTPStatus.NOT_FOUND, "Not found")
            return
        component_id = parts[0]
        try:
            active = [job for job in self.studio_jobs.list(component_id) if job.get("status") in {
                "queued", "running", "cancelling",
            }]
            if active:
                raise RuntimeError("нельзя удалить персонажа во время рендера")
            self.studio_store.delete_project(component_id)
            self._serve_json({"ok": True, "id": component_id})
        except (ValueError, FileNotFoundError, RuntimeError) as exc:
            self._serve_api_error(exc)

    def _handle_component_create(self) -> None:
        """Accept one reference and enqueue the complete hidden build."""

        try:
            content_length = int(self.headers.get("Content-Length", "0") or "0")
            if content_length <= 0 or content_length > 30 * 1024 * 1024:
                raise ValueError("reference upload must be between 1 byte and 30 MB")
            form = cgi.FieldStorage(
                fp=self.rfile,
                headers=self.headers,
                environ={
                    "REQUEST_METHOD": "POST",
                    "CONTENT_TYPE": self.headers.get("Content-Type", ""),
                    "CONTENT_LENGTH": str(content_length),
                },
            )
            reference = form["reference"] if "reference" in form else None
            if reference is None or not getattr(reference, "filename", ""):
                raise ValueError("reference is required")
            actions = normalize_component_actions(form.getlist("motion"))
            raw_name = " ".join(str(form.getfirst("name", "")).strip().split())
            name = raw_name or Path(str(reference.filename)).stem[:100] or "Character"
            project = self.studio_store.create_project(name, quality_profile="quality_512", language="ru")
            data = reference.file.read()
            project, _ = self.studio_store.add_asset(
                str(project["id"]),
                filename=Path(str(reference.filename)).name,
                content_type=getattr(reference, "type", "application/octet-stream") or "application/octet-stream",
                data=data,
                role="primary",
            )
            project = self.studio_store.set_component_actions(str(project["id"]), actions)
            params = {
                "actions": actions,
                "motion_ids": component_motion_ids(actions),
                "loadout_id": "default",
                "seed": int(uuid.uuid4().hex[:15], 16),
                "max_attempts": 2,
            }
            params["_input_signature"] = self.studio_store.generation_signature(
                project,
                "component_build",
                params,
            )
            job = self.studio_jobs.submit_unique(str(project["id"]), "component_build", params)
            component_id = str(project["id"])
            self._serve_json(
                {
                    "id": component_id,
                    "project_id": component_id,
                    "job_id": job["id"],
                    "status": "queued",
                    "status_url": f"/api/components/{component_id}",
                },
                status=HTTPStatus.ACCEPTED,
            )
        except (ValueError, FileNotFoundError, RuntimeError) as exc:
            self._serve_api_error(exc)

    def _handle_component_get(self, path: str) -> None:
        suffix = path.split("/api/components/", 1)[1].strip("/")
        parts = suffix.split("/") if suffix else []
        if len(parts) not in {1, 2} or (len(parts) == 2 and parts[1] != "manifest"):
            self.send_error(HTTPStatus.NOT_FOUND, "Not found")
            return
        component_id = parts[0]
        try:
            project = self.studio_store.get_project(component_id)
            jobs = [job for job in self.studio_jobs.list(component_id) if job.get("kind") == "component_build"]
            if not jobs:
                raise FileNotFoundError(component_id)
            job = jobs[0]
            actions = component_requested_actions(project, job.get("params", {}).get("actions"))
            if len(parts) == 2:
                self._serve_json(
                    build_component_manifest(
                        project,
                        str(job.get("params", {}).get("loadout_id", "default")),
                        requested_actions=actions,
                    )
                )
                return

            raw_status = str(job.get("status", "queued"))
            manifest_error = None
            published_manifest = False
            if raw_status in {"succeeded", "failed", "cancelled", "interrupted"}:
                try:
                    build_component_manifest(
                        project,
                        str(job.get("params", {}).get("loadout_id", "default")),
                        requested_actions=actions,
                    )
                    published_manifest = True
                except ValueError as exc:
                    # A failed original W1/W2/W3 build may leave only part of
                    # the requested actions published.  Do not replace its
                    # real error with a legacy loadout/anchor validation error.
                    if raw_status == "succeeded":
                        manifest_error = str(exc)
            status = "ready" if raw_status == "succeeded" or published_manifest else "failed" if raw_status in {
                "failed",
                "cancelled",
                "interrupted",
            } else raw_status
            if manifest_error:
                status = "failed"
            messages = {
                "queued": "Сборка ожидает запуска",
                "running": "Персонаж и анимации собираются автоматически",
                "cancelling": "Сборка отменяется",
                "ready": "Компонент готов",
                "failed": "Сборка не завершена",
            }
            response = {
                "id": component_id,
                "job_id": job["id"],
                "status": status,
                "message": messages.get(status, status),
                "actions": actions,
                "pipeline": component_pipeline_results(project, actions),
                "manifest_url": f"/api/components/{component_id}/manifest" if status == "ready" else None,
                "error": (manifest_error or job.get("error")) if status == "failed" else None,
                **component_build_progress(job),
            }
            rerun_action = str((job.get("params") or {}).get("rerun_action", "") or "")
            start_step = str((job.get("params") or {}).get("start_step", "") or "")
            if raw_status in {"queued", "running", "cancelling"} and rerun_action and start_step:
                response["rerender"] = {"action": rerun_action, "stage": start_step}
            if status == "failed":
                response["stage"] = "Сборка остановлена"
                response["progress"] = min(99, int(response.get("progress", 0) or 0))
            self._serve_json(response)
        except (ValueError, FileNotFoundError, RuntimeError) as exc:
            self._serve_api_error(exc)

    def _handle_component_package(self, path: str) -> None:
        component_id = path.split("/api/components/", 1)[1].rsplit("/package", 1)[0].strip("/")
        try:
            project = self.studio_store.get_project(component_id)
            records = (project.get("component") or {}).get("actions", {})
            actions = [action for action in PUBLIC_ACTIONS if (
                isinstance(records.get(action), dict) and records[action].get("status") == "ready"
            )]
            if not actions:
                raise RuntimeError("component has no ready animations")
            manifest = build_component_manifest(project, "default", requested_actions=actions)
            archive = io.BytesIO()
            with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as package:
                for action in actions:
                    asset_id = str((records[action].get("stages") or {}).get("w3_asset_id", ""))
                    asset_path, _ = self.studio_store.get_asset(component_id, asset_id)
                    filename = f"animations/{action}.png"
                    package.write(asset_path, filename)
                    manifest["actions"][action]["src"] = filename
                manifest["neutral"]["src"] = manifest["actions"][manifest["default_action"]]["src"]
                package.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))
                package.write(STATIC_ROOT / "animated-character.js", "animated-character.js")
                package.writestr(
                    "README.txt",
                    f"{project.get('name', component_id)}\n\n"
                    "Файлы анимаций находятся в папке animations.\n"
                    "manifest.json подключается к Web Component animated-character.js.\n",
                )
            data = archive.getvalue()
            filename = f"{component_id}-character.zip"
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "application/zip")
            self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)
        except (ValueError, FileNotFoundError, RuntimeError) as exc:
            self._serve_api_error(exc)

    def _handle_component_rebuild(self, path: str) -> None:
        suffix = path.split("/api/components/", 1)[1].strip("/")
        parts = suffix.split("/") if suffix else []
        if len(parts) != 2 or parts[1] != "rebuild":
            self.send_error(HTTPStatus.NOT_FOUND, "Not found")
            return
        component_id = parts[0]
        try:
            payload = self._read_json()
            project = self.studio_store.get_project(component_id)
            prior_jobs = [job for job in self.studio_jobs.list(component_id) if job.get("kind") == "component_build"]
            prior_actions = prior_jobs[0].get("params", {}).get("actions") if prior_jobs else None
            incoming_actions = normalize_component_actions(payload.get("actions", prior_actions))
            existing_actions = component_requested_actions(project, prior_actions)
            actions = normalize_component_actions([*existing_actions, *incoming_actions])
            rerun_action = str(payload.get("rerun_action", "") or "")
            if rerun_action and rerun_action not in actions:
                raise ValueError("rerun_action must be one of the component actions")
            start_step = str(payload.get("start_step", "w1") or "w1").lower()
            if start_step not in {"w1", "w2", "w3"}:
                raise ValueError("start_step must be w1, w2 or w3")
            extra_prompt = str(payload.get("extra_prompt", "") or "").strip()
            if len(extra_prompt) > 1000:
                raise ValueError("extra_prompt is too long")
            if "positive_tags" in payload or "negative_tags" in payload:
                custom_tags = self.prompt_tags.by_id()
                positive_prompt = compile_tags(payload.get("positive_tags", []), "positive", payload.get("custom_positive", ""), action=rerun_action, stage=start_step, custom_tags=custom_tags)
                negative_prompt = compile_tags(payload.get("negative_tags", []), "negative", payload.get("custom_negative", ""), action=rerun_action, stage=start_step, custom_tags=custom_tags)
            else:
                positive_prompt = str(payload.get("positive_prompt", "") or "").strip()
                negative_prompt = str(payload.get("negative_prompt", "") or "").strip()
            if len(negative_prompt) > 12000:
                raise ValueError("negative_prompt is too long")
            if len(positive_prompt) > 12000:
                raise ValueError("positive_prompt is too long")
            frame_count = int(payload.get("frame_count", 0) or 0)
            if frame_count and (frame_count < 8 or frame_count > 80 or frame_count % 4):
                raise ValueError("frame_count must be between 8 and 80 and divisible by 4")
            if project.get("settings", {}).get("quality_profile") != "quality_512":
                project = self.studio_store.update_project(
                    component_id,
                    {"settings": {"quality_profile": "quality_512"}},
                    expected_revision=int(project["revision"]),
                )
            if self.studio_jobs.has_active(component_id, kind="component_build"):
                raise RuntimeError("a component build for loadout default is already active")
            project = self.studio_store.set_component_actions(component_id, actions)
            params = {
                "actions": actions,
                "motion_ids": component_motion_ids(actions),
                "loadout_id": "default",
                "seed": int(uuid.uuid4().hex[:15], 16),
                "max_attempts": 2,
                "force": bool(payload.get("force", True)),
                "rerun_action": rerun_action,
                "start_step": start_step,
                "extra_prompt": extra_prompt,
                "negative_prompt": negative_prompt,
                "positive_prompt": positive_prompt,
                "frame_count": frame_count,
            }
            records = (project.get("component") or {}).get("actions", {})
            if not rerun_action and not params["force"] and all(
                isinstance(records.get(action), dict) and records[action].get("status") == "ready"
                for action in actions
            ):
                self._serve_json({
                    "id": component_id,
                    "project_id": component_id,
                    "status": "ready",
                    "status_url": f"/api/components/{component_id}",
                    "manifest_url": f"/api/components/{component_id}/manifest",
                })
                return
            params["_input_signature"] = self.studio_store.generation_signature(
                project,
                "component_build",
                params,
            )
            job = self.studio_jobs.submit_unique(component_id, "component_build", params)
            self._serve_json(
                {
                    "id": component_id,
                    "project_id": component_id,
                    "job_id": job["id"],
                    "status": "queued",
                    "status_url": f"/api/components/{component_id}",
                },
                status=HTTPStatus.ACCEPTED,
            )
        except (ValueError, FileNotFoundError, RuntimeError) as exc:
            self._serve_api_error(exc)

    def _handle_component_w3_edit(self, path: str) -> None:
        component_id = path.split("/api/components/", 1)[1].rsplit("/w3-edit", 1)[0].strip("/")
        try:
            content_length = int(self.headers.get("Content-Length", "0") or "0")
            if content_length <= 0 or content_length > 40 * 1024 * 1024:
                raise ValueError("edited W3 must be between 1 byte and 40 MB")
            form = cgi.FieldStorage(
                fp=self.rfile,
                headers=self.headers,
                environ={
                    "REQUEST_METHOD": "POST",
                    "CONTENT_TYPE": self.headers.get("Content-Type", ""),
                    "CONTENT_LENGTH": str(content_length),
                },
            )
            action = str(form.getfirst("action", "")).strip()
            if action not in normalize_component_actions([action]):
                raise ValueError("unsupported component action")
            upload = form["spritesheet"] if "spritesheet" in form else None
            if upload is None or not getattr(upload, "file", None):
                raise ValueError("spritesheet is required")
            data = upload.file.read()
            frame_count = int(form.getfirst("frame_count", "0") or "0")
            if frame_count < 1 or frame_count > 64:
                raise ValueError("frame_count must be between 1 and 64")
            with Image.open(io.BytesIO(data)) as sheet:
                if sheet.format != "PNG" or sheet.height != 512 or sheet.width != frame_count * 512:
                    raise ValueError("spritesheet dimensions do not match frame_count")
            project, asset = self.studio_store.save_component_w3_edit(
                component_id,
                action_id=action,
                data=data,
                frame_count=frame_count,
            )
            self._serve_json({
                "ok": True,
                "asset_url": asset["url"],
                "pipeline": component_pipeline_results(project, [action]),
                "manifest_url": f"/api/components/{component_id}/manifest",
            })
        except (ValueError, FileNotFoundError, RuntimeError) as exc:
            self._serve_api_error(exc)

    def _handle_component_frame_interpolation(self, path: str) -> None:
        """Generate one middle frame conditioned by exact left/right endpoints."""
        component_id = path.split("/api/components/", 1)[1].rsplit("/interpolate-frame", 1)[0].strip("/")
        staged: list[Path] = []
        try:
            self.studio_store.get_project(component_id)
            content_length = int(self.headers.get("Content-Length", "0") or "0")
            if content_length <= 0 or content_length > 12 * 1024 * 1024:
                raise ValueError("endpoint frames must be between 1 byte and 12 MB")
            form = cgi.FieldStorage(
                fp=self.rfile,
                headers=self.headers,
                environ={
                    "REQUEST_METHOD": "POST",
                    "CONTENT_TYPE": self.headers.get("Content-Type", ""),
                    "CONTENT_LENGTH": str(content_length),
                },
            )
            token = uuid.uuid4().hex
            input_root = COMFYUI_ROOT / "input"
            input_root.mkdir(parents=True, exist_ok=True)
            names: list[str] = []
            for field_name in ("left", "right"):
                upload = form[field_name] if field_name in form else None
                if upload is None or not getattr(upload, "file", None):
                    raise ValueError(f"{field_name} endpoint frame is required")
                with Image.open(io.BytesIO(upload.file.read())) as source:
                    source.load()
                    rgba = source.convert("RGBA").resize((512, 512), Image.Resampling.LANCZOS)
                    white = Image.new("RGBA", rgba.size, "white")
                    white.alpha_composite(rgba)
                    target = input_root / f"frame_interp_{token}_{field_name}.png"
                    white.convert("RGB").save(target, "PNG")
                staged.append(target)
                names.append(target.name)

            workflow = json.loads(FRAME_INTERPOLATION_WORKFLOW.read_text(encoding="utf-8"))
            workflow["9"]["inputs"]["image"] = names[0]
            workflow["10"]["inputs"]["image"] = names[1]
            workflow["19"]["inputs"]["filename_prefix"] = (
                f"character_pipeline/frame_interpolation/{component_id}_{token}"
            )
            request = urllib.request.Request(
                f"{COMFY_URL}/prompt",
                data=json.dumps({"prompt": workflow}).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(request, timeout=30) as response:
                prompt_id = str(json.loads(response.read().decode("utf-8"))["prompt_id"])

            deadline = time.monotonic() + 900
            history: dict[str, Any] | None = None
            while time.monotonic() < deadline:
                with urllib.request.urlopen(f"{COMFY_URL}/history/{prompt_id}", timeout=15) as response:
                    payload = json.loads(response.read().decode("utf-8"))
                history = payload.get(prompt_id)
                if history:
                    break
                time.sleep(1)
            if not history:
                raise RuntimeError("frame interpolation timed out")
            status = history.get("status") or {}
            if status.get("status_str") == "error":
                messages = status.get("messages") or []
                raise RuntimeError(f"frame interpolation failed: {messages[-1] if messages else 'ComfyUI error'}")
            images = ((history.get("outputs") or {}).get("19") or {}).get("images") or []
            if not images:
                raise RuntimeError("frame interpolation produced no image")
            image_info = images[-1]
            output_path = COMFYUI_ROOT / "output" / str(image_info.get("subfolder", "")) / str(image_info["filename"])
            data = output_path.read_bytes()
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)
        except (ValueError, FileNotFoundError, RuntimeError, OSError, KeyError, json.JSONDecodeError) as exc:
            self._serve_api_error(exc)
        finally:
            for target in staged:
                target.unlink(missing_ok=True)

    def do_PUT(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path.startswith("/api/studio/projects/"):
            project_id = parsed.path.split("/api/studio/projects/", 1)[1].strip("/")
            if "/" in project_id or not project_id:
                self.send_error(HTTPStatus.NOT_FOUND, "Not found")
                return
            try:
                payload = self._read_json()
                expected_revision = payload.pop("expected_revision", None)
                if expected_revision is None:
                    raise ValueError("expected_revision is required")
                project = self.studio_store.update_project(
                    project_id,
                    payload,
                    expected_revision=int(expected_revision),
                )
                self._serve_json(project)
            except (ValueError, FileNotFoundError, RuntimeError) as exc:
                self._serve_api_error(exc)
            return
        self.send_error(HTTPStatus.NOT_FOUND, "Not found")

    def _handle_studio_project_get(self, path: str, query_string: str = "") -> None:
        suffix = path.split("/api/studio/projects/", 1)[1].strip("/")
        parts = suffix.split("/") if suffix else []
        if not parts:
            self.send_error(HTTPStatus.NOT_FOUND, "Not found")
            return
        project_id = parts[0]
        try:
            project = self.studio_store.get_project(project_id)
            if len(parts) == 1:
                self._serve_json(project)
            elif len(parts) == 2 and parts[1] == "library":
                self._serve_json(
                    {
                        "project_id": project_id,
                        "active_loadout_id": project.get("active_loadout_id", "default"),
                        "anchor": project.get("anchor"),
                        "anchors": project.get("anchors", {}),
                        "clips": project.get("clips", {}),
                    }
                )
            elif len(parts) == 2 and parts[1] == "runtime":
                query = parse_qs(query_string)
                loadout_id = query.get("loadout_id", [project.get("active_loadout_id", "default")])[0]
                self._serve_json(build_runtime_manifest(project, str(loadout_id)))
            else:
                self.send_error(HTTPStatus.NOT_FOUND, "Not found")
        except (ValueError, FileNotFoundError) as exc:
            self._serve_api_error(exc)

    def _handle_studio_project_create(self) -> None:
        try:
            payload = self._read_json()
            project = self.studio_store.create_project(
                str(payload.get("name", "")),
                quality_profile=str(payload.get("quality_profile", "local_12gb")),
                language=str(payload.get("language", "ru")),
            )
            self._serve_json(project, status=HTTPStatus.CREATED)
        except ValueError as exc:
            self._serve_api_error(exc)

    def _handle_studio_project_post(self, path: str) -> None:
        suffix = path.split("/api/studio/projects/", 1)[1].strip("/")
        parts = suffix.split("/") if suffix else []
        if len(parts) != 2:
            self.send_error(HTTPStatus.NOT_FOUND, "Not found")
            return
        project_id, action = parts
        try:
            if action == "assets":
                self._handle_studio_asset_upload(project_id)
                return
            payload = self._read_json()
            if action == "plan":
                project = self.studio_store.get_project(project_id)
                capabilities = inspect_capabilities(
                    project_root=PROJECT_ROOT,
                    comfyui_root=COMFYUI_ROOT,
                    comfy_url=COMFY_URL,
                )
                plan = build_generation_plan(
                    project,
                    motion_ids=payload.get("motion_ids"),
                    loadout_id=str(payload.get("loadout_id", project.get("active_loadout_id", "default"))),
                    capabilities=capabilities,
                )
                self.studio_store.save_plan(project_id, plan, expected_revision=project["revision"])
                self._serve_json(plan)
                return
            if action == "generate":
                kind = str(payload.get("kind", "canonicalize"))
                raw_params = payload.get("params", {})
                if not isinstance(raw_params, dict):
                    raise ValueError("params must be an object")
                params = dict(raw_params)
                project = self.studio_store.get_project(project_id)
                capabilities = inspect_capabilities(
                    project_root=PROJECT_ROOT,
                    comfyui_root=COMFYUI_ROOT,
                    comfy_url=COMFY_URL,
                )
                seed = int(params.get("seed", 20260715))
                if seed < 0 or seed > 2**63 - 1:
                    raise ValueError("seed is out of range")
                params["seed"] = seed
                if kind == "canonicalize":
                    if not project.get("references", {}).get("primary"):
                        raise ValueError("primary reference is required")
                    if not capabilities.get("features", {}).get("canonicalize"):
                        raise ValueError("canonicalize stack is unavailable")
                    loadout_id = str(params.get("loadout_id", project.get("active_loadout_id", "default")))
                    params["loadout_id"] = loadout_id
                    canonical_preflight = build_generation_plan(
                        project,
                        motion_ids=[],
                        loadout_id=loadout_id,
                        capabilities=capabilities,
                    )
                    prop_errors = [
                        item["message"]
                        for item in canonical_preflight["issues"]
                        if item.get("severity") == "error" and item.get("target") != "anchor"
                    ]
                    if prop_errors:
                        raise ValueError(f"canonicalize preflight failed: {'; '.join(prop_errors)}")
                elif kind == "motion":
                    motion_id = str(params.get("motion_id", ""))
                    loadout_id = str(params.get("loadout_id", project.get("active_loadout_id", "default")))
                    params["loadout_id"] = loadout_id
                    preflight = build_generation_plan(
                        project,
                        motion_ids=[motion_id],
                        loadout_id=loadout_id,
                        capabilities=capabilities,
                    )
                    task = next(
                        (
                            item
                            for stage in preflight["stages"]
                            if stage["id"] == "motion_generation"
                            for item in stage.get("tasks", [])
                            if item["id"] == motion_id
                        ),
                        None,
                    )
                    selected_anchor = self.studio_store.anchor_for(project, loadout_id)
                    if task is None or task["status"] != "ready" or selected_anchor.get("status") != "ready":
                        messages = "; ".join(item["message"] for item in preflight["issues"]) or "anchor is not ready"
                        raise ValueError(f"motion preflight failed: {messages}")
                    motion = get_motion(motion_id) or {}
                    if motion.get("generation_mode") == "face_layer":
                        required_roi = "eye_roi" if motion_id == "blink" else "mouth_roi"
                        if not selected_anchor.get(required_roi):
                            label = "eye ROI" if required_roi == "eye_roi" else "mouth ROI"
                            raise ValueError(f"set and save {label} on the accepted anchor before generating {motion_id}")
                elif kind == "viseme_atlas":
                    loadout_id = str(params.get("loadout_id", project.get("active_loadout_id", "default")))
                    params["loadout_id"] = loadout_id
                    selected_anchor = self.studio_store.anchor_for(project, loadout_id)
                    if selected_anchor.get("status") != "ready" or not selected_anchor.get("asset_id"):
                        raise ValueError("accept the selected loadout anchor before generating a viseme atlas")
                    if not selected_anchor.get("mouth_roi"):
                        raise ValueError("set and save mouth ROI on the accepted anchor first")
                    if not capabilities.get("features", {}).get("viseme_atlas"):
                        raise ValueError("W9 viseme-atlas stack is unavailable")
                elif kind == "temporal_repair":
                    motion_id = str(params.get("motion_id", ""))
                    loadout_id = str(params.get("loadout_id", project.get("active_loadout_id", "default")))
                    params.update({"motion_id": motion_id, "loadout_id": loadout_id})
                    clip = project.get("clips", {}).get(self.studio_store.clip_key(loadout_id, motion_id))
                    if not isinstance(clip, dict):
                        raise ValueError("selected loadout has no such clip")
                    if not clip.get("master_spritesheet_asset_id") or not clip.get("qc_report_asset_id"):
                        raise ValueError("clip has no lossless master/QC report for safe W10 repair")
                    if clip.get("qc", {}).get("status") == "pass":
                        raise ValueError("clip already passes continuity QC")
                    if not capabilities.get("features", {}).get("temporal_repair"):
                        raise ValueError("W10 temporal-repair stack is unavailable")
                elif kind == "runtime_export":
                    motion_id = str(params.get("motion_id", ""))
                    loadout_id = str(params.get("loadout_id", project.get("active_loadout_id", "default")))
                    params.update({"motion_id": motion_id, "loadout_id": loadout_id})
                    clip = project.get("clips", {}).get(self.studio_store.clip_key(loadout_id, motion_id))
                    if not isinstance(clip, dict):
                        raise ValueError("selected loadout has no such clip")
                    if clip.get("status") != "qc_pass" or clip.get("qc", {}).get("status") != "pass":
                        raise ValueError("W12 requires a current clip that passed continuity QC")
                    selected_anchor = self.studio_store.anchor_for(project, loadout_id)
                    if (
                        selected_anchor.get("status") != "ready"
                        or clip.get("anchor_asset_id") != selected_anchor.get("asset_id")
                        or clip.get("anchor_revision") != selected_anchor.get("revision")
                    ):
                        raise ValueError("clip is not bound to the current accepted anchor")
                    if not clip.get("master_spritesheet_asset_id") or not clip.get("runtime_frame_count"):
                        raise ValueError("clip has no lossless master/runtime frame contract")
                    if not capabilities.get("features", {}).get("runtime_export"):
                        raise ValueError("W12 runtime-export stack is unavailable")
                else:
                    raise ValueError("unsupported job kind")
                params["_input_signature"] = self.studio_store.generation_signature(project, kind, params)
                job = self.studio_jobs.submit_unique(project_id, kind, params)
                self._serve_json(job, status=HTTPStatus.ACCEPTED)
                return
            if action == "accept-anchor":
                project = self.studio_store.get_project(project_id)
                loadout_id = str(payload.get("loadout_id", project.get("active_loadout_id", "default")))
                selected_anchor = self.studio_store.anchor_for(project, loadout_id)
                if not selected_anchor.get("asset_id"):
                    raise ValueError("project has no anchor candidate")
                if self.studio_jobs.has_active(project_id, kind="canonicalize", loadout_id=loadout_id):
                    raise RuntimeError("wait for the active canonicalize job before accepting an anchor")
                expected_revision = payload.get("expected_revision")
                expected_asset_id = str(payload.get("expected_asset_id", ""))
                if expected_revision is None or not expected_asset_id:
                    raise ValueError("expected_revision and expected_asset_id are required")
                metadata = {}
                for key in ("root", "ground_y", "neutral_bbox", "pose_keypoints", "mouth_roi", "eye_roi"):
                    if key in payload:
                        metadata[key] = payload[key]
                updated = self.studio_store.accept_anchor(
                    project_id,
                    expected_revision=int(expected_revision),
                    expected_asset_id=expected_asset_id,
                    loadout_id=loadout_id,
                    metadata=metadata,
                )
                self._serve_json(updated)
                return
            if action == "accept-viseme-atlas":
                project = self.studio_store.get_project(project_id)
                loadout_id = str(payload.get("loadout_id", project.get("active_loadout_id", "default")))
                if self.studio_jobs.has_active(project_id, kind="viseme_atlas", loadout_id=loadout_id):
                    raise RuntimeError("wait for the active W9 job before accepting its atlas")
                expected_revision = payload.get("expected_revision")
                expected_asset_id = str(payload.get("expected_asset_id", ""))
                if expected_revision is None or not expected_asset_id:
                    raise ValueError("expected_revision and expected_asset_id are required")
                updated = self.studio_store.accept_viseme_atlas(
                    project_id,
                    loadout_id=loadout_id,
                    expected_revision=int(expected_revision),
                    expected_asset_id=expected_asset_id,
                )
                self._serve_json(updated)
                return
            if action == "accept-runtime-export":
                project = self.studio_store.get_project(project_id)
                loadout_id = str(payload.get("loadout_id", project.get("active_loadout_id", "default")))
                motion_id = str(payload.get("motion_id", ""))
                if self.studio_jobs.has_active(
                    project_id,
                    kind="runtime_export",
                    motion_id=motion_id,
                    loadout_id=loadout_id,
                ):
                    raise RuntimeError("wait for the active W12 job before accepting its RGBA export")
                expected_revision = payload.get("expected_revision")
                expected_asset_id = str(payload.get("expected_asset_id", ""))
                if expected_revision is None or not expected_asset_id:
                    raise ValueError("expected_revision and expected_asset_id are required")
                updated = self.studio_store.accept_runtime_export(
                    project_id,
                    motion_id=motion_id,
                    loadout_id=loadout_id,
                    expected_revision=int(expected_revision),
                    expected_asset_id=expected_asset_id,
                )
                self._serve_json(updated)
                return
            if action == "reject-runtime-export":
                project = self.studio_store.get_project(project_id)
                loadout_id = str(payload.get("loadout_id", project.get("active_loadout_id", "default")))
                motion_id = str(payload.get("motion_id", ""))
                if self.studio_jobs.has_active(
                    project_id,
                    kind="runtime_export",
                    motion_id=motion_id,
                    loadout_id=loadout_id,
                ):
                    raise RuntimeError("wait for the active W12 job before rejecting its RGBA export")
                expected_revision = payload.get("expected_revision")
                expected_asset_id = str(payload.get("expected_asset_id", ""))
                if expected_revision is None or not expected_asset_id:
                    raise ValueError("expected_revision and expected_asset_id are required")
                updated = self.studio_store.reject_runtime_export(
                    project_id,
                    motion_id=motion_id,
                    loadout_id=loadout_id,
                    expected_revision=int(expected_revision),
                    expected_asset_id=expected_asset_id,
                )
                self._serve_json(updated)
                return
            if action == "analyze-audio":
                project = self.studio_store.get_project(project_id)
                loadout_id = str(payload.get("loadout_id", project.get("active_loadout_id", "default")))
                atlas_record = self.studio_store.viseme_atlas_for(project, loadout_id)
                if atlas_record.get("status") != "ready" or not atlas_record.get("manifest"):
                    raise ValueError("accept the W9 atlas before analyzing audio")
                audio_asset_id = project.get("voice", {}).get("audio_asset_id")
                if not audio_asset_id:
                    raise ValueError("upload an audio file first")
                if not RHUBARB_EXE.is_file():
                    raise ValueError("local Rhubarb executable is not installed")
                if not FFMPEG_EXE.is_file():
                    raise ValueError("ffmpeg is required to normalize audio for Rhubarb")
                source_audio, _ = self.studio_store.get_asset(project_id, str(audio_asset_id))
                transcript = str(payload.get("transcript", "")).strip()
                if len(transcript) > 50_000:
                    raise ValueError("transcript is too long")
                with tempfile.TemporaryDirectory(prefix="studio-rhubarb-") as temporary_name:
                    temporary = Path(temporary_name)
                    normalized_audio = temporary / "voice.wav"
                    conversion = subprocess.run(
                        [
                            str(FFMPEG_EXE),
                            "-hide_banner",
                            "-loglevel",
                            "error",
                            "-y",
                            "-i",
                            str(source_audio),
                            "-ac",
                            "1",
                            "-ar",
                            "16000",
                            str(normalized_audio),
                        ],
                        shell=False,
                        check=False,
                        capture_output=True,
                        text=True,
                        encoding="utf-8",
                        errors="replace",
                        timeout=180,
                    )
                    if conversion.returncode != 0 or not normalized_audio.is_file():
                        raise RuntimeError(f"ffmpeg audio conversion failed: {conversion.stderr.strip()}")
                    dialog_file = None
                    if transcript:
                        dialog_file = temporary / "dialog.txt"
                        dialog_file.write_text(transcript, encoding="utf-8")
                    raw_timing = temporary / "rhubarb.json"
                    command = build_rhubarb_command(
                        RHUBARB_EXE,
                        normalized_audio,
                        output_file=raw_timing,
                        dialog_file=dialog_file,
                        language=str(project.get("settings", {}).get("language", "ru")),
                        extended_shapes="GHX",
                        quiet=True,
                        machine_readable=False,
                    )
                    analyzed = subprocess.run(
                        command,
                        shell=False,
                        check=False,
                        capture_output=True,
                        text=True,
                        encoding="utf-8",
                        errors="replace",
                        timeout=600,
                    )
                    if analyzed.returncode != 0 or not raw_timing.is_file():
                        diagnostic = analyzed.stderr.strip() or analyzed.stdout.strip() or "unknown Rhubarb failure"
                        raise RuntimeError(f"Rhubarb failed: {diagnostic}")
                    parsed_timing = parse_rhubarb_json(raw_timing)
                    cues = smooth_cues(parsed_timing.cues, duration=parsed_timing.duration)
                    timeline = build_runtime_timeline(
                        cues,
                        duration=parsed_timing.duration,
                        fps=float(payload.get("fps", 60.0)),
                        atlas={
                            **atlas_record["manifest"],
                            "atlas_asset_id": atlas_record["atlas_asset_id"],
                            "atlas_manifest_asset_id": atlas_record.get("manifest_asset_id"),
                        },
                        audio={
                            "asset_id": audio_asset_id,
                            "source": "rhubarb-1.14.0",
                            "duration_seconds": parsed_timing.duration,
                            "transcript_supplied": bool(transcript),
                        },
                    )
                updated, asset = self.studio_store.save_voice_timeline(
                    project_id,
                    timeline=timeline,
                    timing_source="rhubarb-1.14.0",
                    expected_revision=int(payload.get("expected_revision", project["revision"])),
                )
                self._serve_json({"project": updated, "asset": asset, "timeline": timeline})
                return
            if action == "voice-timeline":
                project = self.studio_store.get_project(project_id)
                loadout_id = str(payload.get("loadout_id", project.get("active_loadout_id", "default")))
                atlas_record = self.studio_store.viseme_atlas_for(project, loadout_id)
                if atlas_record.get("status") != "ready" or not atlas_record.get("manifest"):
                    raise ValueError("accept the W9 atlas before building a runtime timeline")
                source = str(payload.get("source", "tts")).strip().lower()
                timings = payload.get("timings")
                if source == "rhubarb":
                    parsed_timings = parse_rhubarb_json(timings)
                    duration = parsed_timings.duration
                    cues = smooth_cues(parsed_timings.cues, duration=duration)
                elif source == "tts":
                    duration_value = payload.get("duration")
                    duration = float(duration_value) if duration_value is not None else None
                    cues = normalize_tts_timings(
                        timings,
                        duration=duration,
                        unit=str(payload.get("unit", "auto")),
                        value_map=payload.get("value_map"),
                    )
                    duration = float(duration or cues[-1].end)
                else:
                    raise ValueError("timeline source must be rhubarb or tts")
                audio_asset_id = project.get("voice", {}).get("audio_asset_id")
                timeline = build_runtime_timeline(
                    cues,
                    duration=duration,
                    fps=float(payload.get("fps", 60.0)),
                    atlas={
                        **atlas_record["manifest"],
                        "atlas_asset_id": atlas_record["atlas_asset_id"],
                        "atlas_manifest_asset_id": atlas_record.get("manifest_asset_id"),
                    },
                    audio={
                        "asset_id": audio_asset_id,
                        "source": source,
                        "duration_seconds": duration,
                    },
                )
                updated, asset = self.studio_store.save_voice_timeline(
                    project_id,
                    timeline=timeline,
                    timing_source=source,
                    expected_revision=int(payload.get("expected_revision", project["revision"])),
                )
                self._serve_json({"project": updated, "asset": asset, "timeline": timeline})
                return
            self.send_error(HTTPStatus.NOT_FOUND, "Not found")
        except (ValueError, FileNotFoundError, RuntimeError) as exc:
            self._serve_api_error(exc)

    def _handle_studio_asset_upload(self, project_id: str) -> None:
        content_length = int(self.headers.get("Content-Length", "0") or "0")
        if content_length <= 0 or content_length > 110 * 1024 * 1024:
            raise ValueError("upload must be between 1 byte and 110 MB")
        form = cgi.FieldStorage(
            fp=self.rfile,
            headers=self.headers,
            environ={
                "REQUEST_METHOD": "POST",
                "CONTENT_TYPE": self.headers.get("Content-Type", ""),
                "CONTENT_LENGTH": str(content_length),
            },
        )
        file_item = form["file"] if "file" in form else None
        if file_item is None or not getattr(file_item, "filename", ""):
            raise ValueError("file is required")
        role = str(form.getfirst("role", ""))
        prop_id = (form.getfirst("prop_id", "") or "").strip() or None
        data = file_item.file.read()
        project, asset = self.studio_store.add_asset(
            project_id,
            filename=Path(file_item.filename).name,
            content_type=getattr(file_item, "type", "application/octet-stream") or "application/octet-stream",
            data=data,
            role=role,
            prop_id=prop_id,
        )
        self._serve_json({"project": project, "asset": asset}, status=HTTPStatus.CREATED)

    def _read_json(self, max_bytes: int = 2 * 1024 * 1024) -> dict[str, Any]:
        content_length = int(self.headers.get("Content-Length", "0") or "0")
        if content_length < 0 or content_length > max_bytes:
            raise ValueError("JSON request is too large")
        raw = self.rfile.read(content_length) if content_length else b"{}"
        try:
            payload = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise ValueError("invalid JSON body") from exc
        if not isinstance(payload, dict):
            raise ValueError("JSON body must be an object")
        return payload

    def _serve_studio_media(self, path: str) -> None:
        suffix = path.split("/studio-media/", 1)[1].strip("/")
        parts = suffix.split("/")
        if len(parts) != 2:
            self.send_error(HTTPStatus.NOT_FOUND, "Not found")
            return
        try:
            target, asset = self.studio_store.get_asset(parts[0], parts[1])
        except (ValueError, FileNotFoundError) as exc:
            self._serve_api_error(exc)
            return
        size = target.stat().st_size
        start, end = 0, size - 1
        range_header = self.headers.get("Range", "")
        partial = False
        if range_header.startswith("bytes="):
            try:
                raw_start, raw_end = range_header[6:].split("-", 1)
                start = int(raw_start) if raw_start else 0
                end = min(size - 1, int(raw_end)) if raw_end else size - 1
                if start < 0 or start > end or start >= size:
                    raise ValueError("invalid byte range")
                partial = True
            except (ValueError, TypeError):
                self.send_error(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
                return
        length = end - start + 1
        self.send_response(HTTPStatus.PARTIAL_CONTENT if partial else HTTPStatus.OK)
        self.send_header("Content-Type", asset.get("content_type") or mimetypes.guess_type(target.name)[0] or "application/octet-stream")
        self.send_header("Content-Length", str(length))
        self.send_header("Accept-Ranges", "bytes")
        if partial:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        with target.open("rb") as source:
            source.seek(start)
            remaining = length
            while remaining:
                chunk = source.read(min(1024 * 1024, remaining))
                if not chunk:
                    break
                self.wfile.write(chunk)
                remaining -= len(chunk)

    def _serve_api_error(self, exc: Exception) -> None:
        if isinstance(exc, FileNotFoundError):
            status = HTTPStatus.NOT_FOUND
        elif isinstance(exc, RuntimeError):
            status = HTTPStatus.CONFLICT
        else:
            status = HTTPStatus.BAD_REQUEST
        self._serve_json({"error": str(exc)}, status=status)

    def _handle_generate(self) -> None:
        form = cgi.FieldStorage(
            fp=self.rfile,
            headers=self.headers,
            environ={
                "REQUEST_METHOD": "POST",
                "CONTENT_TYPE": self.headers.get("Content-Type", ""),
            },
        )
        preset = form.getfirst("preset", "idle_breathing")
        try:
            target, animation_name, cell_size, greyscale, extra_prompt = create_upload_copy(form)
        except ValueError as exc:
            self.send_error(HTTPStatus.BAD_REQUEST, str(exc))
            return

        job = start_generation_job(
            source_path=target,
            preset=preset,
            cell_size=cell_size,
            greyscale=greyscale,
            animation_name=animation_name,
            extra_prompt=extra_prompt,
        )
        self._serve_json(job.to_dict(), status=HTTPStatus.ACCEPTED)

    def _handle_generate_all(self) -> None:
        form = cgi.FieldStorage(
            fp=self.rfile,
            headers=self.headers,
            environ={
                "REQUEST_METHOD": "POST",
                "CONTENT_TYPE": self.headers.get("Content-Type", ""),
            },
        )
        try:
            target, animation_name, cell_size, greyscale, extra_prompt = create_upload_copy(form)
        except ValueError as exc:
            self.send_error(HTTPStatus.BAD_REQUEST, str(exc))
            return

        job = start_generate_all_job(
            source_path=target,
            cell_size=cell_size,
            greyscale=greyscale,
            animation_prefix=animation_name,
            extra_prompt=extra_prompt,
        )
        self._serve_json(job.to_dict(), status=HTTPStatus.ACCEPTED)

    def _serve_json(self, payload: object, status: HTTPStatus = HTTPStatus.OK) -> None:
        encoded = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _serve_media(self, relative_path: str) -> None:
        safe_relative = posixpath.normpath(unquote(relative_path)).lstrip("/")
        target = (self.output_root / safe_relative).resolve()

        try:
            target.relative_to(self.output_root)
        except ValueError:
            self.send_error(HTTPStatus.FORBIDDEN, "Forbidden")
            return

        if not target.is_file():
            self.send_error(HTTPStatus.NOT_FOUND, "Not found")
            return

        mime_type = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
        data = target.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", mime_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format: str, *args) -> None:
        print(f"[viewer] {self.address_string()} - {format % args}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Local viewer and generator UI for character animations.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8010)
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT_ROOT)
    parser.add_argument("--studio-root", type=Path, default=None)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output_root = args.output_root.resolve()
    studio_root = args.studio_root.resolve() if args.studio_root else (output_root / "studio").resolve()
    studio_store = StudioStore(studio_root)
    studio_runner = StudioRunner(studio_store)
    studio_jobs = StudioJobManager(studio_root / "jobs", studio_runner)
    prompt_tags = PromptTagStore(studio_root / "prompt_tags.json")
    handler = lambda *handler_args, **handler_kwargs: ViewerHandler(
        *handler_args,
        static_root=STATIC_ROOT,
        output_root=output_root,
        studio_store=studio_store,
        studio_jobs=studio_jobs,
        prompt_tags=prompt_tags,
        **handler_kwargs,
    )

    server = ThreadingHTTPServer((args.host, args.port), handler)
    print(f"Viewer root: {output_root}")
    print(f"Studio root: {studio_root}")
    print(f"Legacy viewer: http://{args.host}:{args.port}")
    print(f"Animation Studio: http://{args.host}:{args.port}/studio")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        print("Stopping Studio jobs and reconciling any active ComfyUI prompt …")
        studio_jobs.shutdown()
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
