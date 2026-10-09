from __future__ import annotations

import json
import math
import os
import shutil
import subprocess
import sys
import time
import urllib.request
from io import BytesIO
from pathlib import Path
from typing import Any, Callable

from PIL import Image, ImageChops, ImageDraw, ImageFilter

from drivers._local_config import (
    COMFY_URL,
    INPUT_DIR,
    OUTPUT_DIR,
    W1_CLIP_NAME,
    W1_CONTROLNET_NAME,
    W1_LORA_NAME,
    W1_UNET_NAME,
    W1_VAE_NAME,
    W2_CLIP_NAME,
    W2_HIGH_UNET_NAME,
    W2_LOW_UNET_NAME,
    W2_VAE_NAME,
    W4_CLIP_NAME,
    W4_LORA_NAME,
    W4_UNET_NAME,
    W4_VAE_NAME,
)
from tools.render_openpose import render_pose

from .catalog import POSE_GUIDE_MOTIONS, QUALITY_PROFILES, get_motion
from .components import build_component_manifest, component_motion_id, component_motion_ids, normalize_component_actions
from .pose_guides import (
    build_pose_keypoints,
    write_lossless_mask_video,
    write_mp4,
    write_pose_control_videos,
)
from .props import canonical_equipment_prompt, build_reference_contact_sheet, equipment_prompt, select_loadout_props
from .qc import analyze_frames, load_video_frames, split_spritesheet
from .repair_service import NoRepairRequired, RegenerationRequired, RepairService
from .rigid_guides import prepare_rigid_pose_guides
from .store import StudioStore
from .temporal_repair import write_lossless_video
from .visemes import STUDIO_VISEMES, pack_viseme_atlas, validate_mouth_roi, viseme_prompt


PROJECT_ROOT = Path(__file__).resolve().parent.parent
W6_PATH = PROJECT_ROOT / "workflows" / "w6-character-canonicalize" / "workflow_api.json"
W7_PATH = PROJECT_ROOT / "workflows" / "w7-seamless-loop" / "workflow_api.json"
W8_PATH = PROJECT_ROOT / "workflows" / "w8-vace-pose-control" / "workflow_api.json"
W9_PATH = PROJECT_ROOT / "workflows" / "w9-viseme-atlas" / "workflow_api.json"
W11_PATH = PROJECT_ROOT / "workflows" / "w11-face-layer" / "workflow_api.json"
W12_PATH = PROJECT_ROOT / "workflows" / "w12-runtime-export" / "workflow_api.json"
LogCallback = Callable[[str], None]
CancelCallback = Callable[[], bool]


def _browser_mp4_bytes(path: Path) -> bytes:
    """Return an H.264 MP4 that Chromium can seek and decode reliably."""
    ffmpeg = os.environ.get("FFMPEG_EXE") or shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("ffmpeg was not found; install it or set FFMPEG_EXE")
    output = path.with_name(f".{path.stem}.browser.mp4")
    try:
        subprocess.run(
            [
                ffmpeg, "-y", "-loglevel", "error",
                "-i", str(path), "-an", "-c:v", "libx264", "-preset", "fast",
                "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
                str(output),
            ],
            check=True,
        )
        return output.read_bytes()
    finally:
        output.unlink(missing_ok=True)


PromptIdCallback = Callable[[str], None]


W7_GLOBAL_PROMPT = (
    "Production 2D character animation. Exactly one character. The supplied canonical image is immutable identity "
    "and layout reference. Start at that exact neutral anchor, perform exactly one requested motion, recover, and "
    "return to that exact neutral anchor. Fixed camera, canvas, root, ground line, scale, perspective, lighting, "
    "face, clothes, line art, colors and persistent props. Keep the entire silhouette and long props inside frame. "
)

W7_NEGATIVE = (
    "identity drift, different face, wrong hand, mirrored gesture, missing prop, duplicate prop, morphing prop, "
    "extra person, extra limb, missing limb, fused hands, malformed fingers, camera motion, camera shake, zoom, crop, "
    "scale drift, root drift, baseline drift, floor, shadow, background flicker, color shift, outline crawl, temporal "
    "jump, discontinuity, frozen middle frames"
)

W8_GUIDE_NEGATIVE = (
    ", visible pose skeleton, OpenPose colors, black guide canvas, black guide shapes, control map, "
    "mask silhouette, conditioning image in output"
)


class ComfyClient:
    def __init__(self, url: str = COMFY_URL):
        self.url = url.rstrip("/")

    def _post(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        request = urllib.request.Request(
            f"{self.url}{path}",
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8") or "{}")

    def _get(self, path: str, *, timeout: float = 10) -> dict[str, Any]:
        with urllib.request.urlopen(f"{self.url}{path}", timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8") or "{}")
        return payload if isinstance(payload, dict) else {}

    def ensure_online(self) -> None:
        try:
            with urllib.request.urlopen(f"{self.url}/system_stats", timeout=5) as response:
                response.read()
        except Exception as exc:
            raise RuntimeError(f"ComfyUI is not reachable at {self.url}: {exc}") from exc

    def free(self) -> None:
        self._post("/free", {"unload_models": True, "free_memory": True})

    def interrupt(self, prompt_id: str | None = None) -> bool:
        try:
            self._post("/interrupt", {"prompt_id": prompt_id} if prompt_id else {})
            return True
        except Exception:
            return False

    def delete_pending(self, prompt_id: str) -> bool:
        try:
            self._post("/queue", {"delete": [prompt_id]})
            return True
        except Exception:
            return False

    @staticmethod
    def _queue_contains(queue_state: dict[str, Any], prompt_id: str) -> bool:
        for key in ("queue_running", "queue_pending"):
            for item in queue_state.get(key, []) or []:
                if isinstance(item, (list, tuple)) and len(item) > 1 and str(item[1]) == prompt_id:
                    return True
                if isinstance(item, dict) and str(item.get("prompt_id", "")) == prompt_id:
                    return True
        return False

    def _abort_and_wait_for_cleanup(self, prompt_id: str, *, reason: str, log: LogCallback) -> None:
        """Abort one prompt and do not release the GPU worker until Comfy confirms cleanup."""

        def emit(line: str) -> None:
            try:
                log(line)
            except Exception:
                # Cleanup must not be skipped just because persistence/logging is unavailable.
                pass

        emit(f"Stopping ComfyUI prompt {prompt_id} after {reason} …")
        deleted = self.delete_pending(prompt_id)
        interrupted = self.interrupt(prompt_id)
        if not interrupted:
            emit("ComfyUI /interrupt was not acknowledged; waiting for queue cleanup.")
        if not deleted:
            emit("ComfyUI pending-queue deletion was not acknowledged; waiting for terminal state.")

        last_log = 0.0
        last_abort_attempt = time.time()
        while True:
            history_error: Exception | None = None
            queue_error: Exception | None = None
            try:
                history = self._get(f"/history/{prompt_id}")
            except Exception as exc:
                history = {}
                history_error = exc
            if prompt_id in history:
                emit(f"ComfyUI prompt {prompt_id} reached terminal history after {reason}.")
                return

            try:
                queue_state = self._get("/queue")
            except Exception as exc:
                queue_state = {}
                queue_error = exc
            if queue_error is None:
                if not self._queue_contains(queue_state, prompt_id):
                    emit(f"ComfyUI prompt {prompt_id} is absent from the running and pending queues.")
                    return
                if time.time() - last_abort_attempt > 5:
                    # Cover network failures and the pending -> running transition race.
                    self.delete_pending(prompt_id)
                    self.interrupt(prompt_id)
                    last_abort_attempt = time.time()

            now = time.time()
            if now - last_log > 15:
                details = "; ".join(
                    str(item)
                    for item in (history_error, queue_error)
                    if item is not None
                )
                emit(
                    f"Waiting for ComfyUI to clean prompt {prompt_id} before the next GPU job"
                    + (f": {details}" if details else " …")
                )
                last_log = now
            time.sleep(2)

    def enqueue(self, workflow: dict[str, Any]) -> str:
        payload = self._post("/prompt", {"prompt": workflow})
        prompt_id = payload.get("prompt_id")
        if not prompt_id:
            errors = payload.get("node_errors") or payload
            raise RuntimeError(f"ComfyUI rejected Studio workflow: {errors}")
        return str(prompt_id)

    def wait(
        self,
        prompt_id: str,
        *,
        timeout_s: int,
        log: LogCallback,
        cancelled: CancelCallback,
    ) -> dict[str, Any]:
        started = time.time()
        last_log = 0.0
        while True:
            if cancelled():
                self._abort_and_wait_for_cleanup(prompt_id, reason="cancellation", log=log)
                raise RuntimeError("job cancelled")
            try:
                history = self._get(f"/history/{prompt_id}")
            except Exception as exc:
                history = {}
                if time.time() - last_log > 15:
                    log(f"ComfyUI history unavailable, retrying: {exc}")
                    last_log = time.time()
            if prompt_id in history:
                entry = history[prompt_id]
                status = entry.get("status", {})
                if status.get("status_str") == "error":
                    raise RuntimeError(f"ComfyUI execution failed: {status.get('messages')}")
                return entry
            if time.time() - started > timeout_s:
                self._abort_and_wait_for_cleanup(prompt_id, reason=f"timeout ({timeout_s}s)", log=log)
                raise TimeoutError(f"ComfyUI prompt {prompt_id} exceeded {timeout_s}s")
            if time.time() - last_log > 15:
                log(f"Waiting for ComfyUI prompt {prompt_id} …")
                last_log = time.time()
            time.sleep(2)

    @staticmethod
    def output_files(history_entry: dict[str, Any]) -> list[Path]:
        files: list[Path] = []
        for node_outputs in history_entry.get("outputs", {}).values():
            for key in ("videos", "images", "gifs"):
                for spec in node_outputs.get(key, []) or []:
                    filename = spec.get("filename")
                    if filename:
                        files.append(OUTPUT_DIR / spec.get("subfolder", "") / filename)
        return files


def _profile(project: dict[str, Any]) -> dict[str, Any]:
    profile_id = project.get("settings", {}).get("quality_profile", "local_12gb")
    return next((item for item in QUALITY_PROFILES if item["id"] == profile_id), QUALITY_PROFILES[0])


def _stage_asset(store: StudioStore, project_id: str, asset_id: str, role: str) -> str:
    source, asset = store.get_asset(project_id, asset_id)
    suffix = source.suffix.lower()
    target = INPUT_DIR / f"studio_{project_id}_{role}{suffix}"
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    return target.name


def _canonical_anchor_png(source: Path) -> tuple[bytes, bool]:
    """Flatten a connected light-neutral generated background without touching the enclosed subject."""

    with Image.open(source) as opened:
        image = opened.convert("RGB")
    original = image.copy()
    width, height = image.size
    eligible = Image.new("L", image.size, 0)
    eligible.putdata(
        [
            255 if min(pixel) >= 210 and max(pixel) - min(pixel) <= 30 else 0
            for pixel in image.get_flattened_data()
        ]
    )
    edge_points = {
        (0, 0),
        (width - 1, 0),
        (0, height - 1),
        (width - 1, height - 1),
        (width // 2, 0),
        (width // 2, height - 1),
        (0, height // 2),
        (width - 1, height // 2),
    }
    for point in edge_points:
        if eligible.getpixel(point) == 255:
            ImageDraw.floodfill(eligible, point, 128)
    connected_background = eligible.point(lambda value: 255 if value == 128 else 0)
    image.paste((255, 255, 255), mask=connected_background)
    changed = ImageChops.difference(original, image).getbbox() is not None
    output = BytesIO()
    image.save(output, format="PNG")
    return output.getvalue(), changed


def _neutral_pose(project_id: str, width: int, height: int) -> str:
    sx = width / 384.0
    sy = height / 384.0
    points: dict[int, tuple[float, float, float]] = {
        0: (192, 75, 1),
        1: (192, 128, 1),
        2: (154, 142, 1),
        3: (143, 202, 1),
        4: (139, 265, 1),
        5: (230, 142, 1),
        6: (241, 202, 1),
        7: (245, 265, 1),
        8: (169, 238, 1),
        9: (166, 299, 1),
        10: (164, 354, 1),
        11: (215, 238, 1),
        12: (218, 299, 1),
        13: (220, 354, 1),
    }
    keypoints = [None] * 18
    for index, (x, y, confidence) in points.items():
        keypoints[index] = (x * sx, y * sy, confidence)
    target = INPUT_DIR / f"studio_{project_id}_neutral_pose.png"
    render_pose(keypoints, width, height).save(target)
    return target.name


def _find_one(workflow: dict[str, Any], class_type: str, title_text: str | None = None) -> str:
    matches = []
    for node_id, node in workflow.items():
        if node.get("class_type") != class_type:
            continue
        title = node.get("_meta", {}).get("title", "").lower()
        if title_text is None or title_text.lower() in title:
            matches.append(node_id)
    if len(matches) != 1:
        raise RuntimeError(f"expected one {class_type}/{title_text}, found {matches}")
    return matches[0]


def _replace_exact_anchor_endpoints(
    frames: list[Image.Image],
    anchor: Image.Image,
) -> list[Image.Image]:
    """Return an RGBA master list with exact anchor endpoints and no resizing."""

    if len(frames) < 2:
        raise RuntimeError("motion video contains fewer than two decoded frames")
    exact_anchor = anchor.convert("RGBA").copy()
    canvas = exact_anchor.size
    master: list[Image.Image] = []
    for index, frame in enumerate(frames):
        converted = frame.convert("RGBA")
        if converted.size != canvas:
            raise RuntimeError(
                f"decoded frame {index} is {converted.width}x{converted.height}; "
                f"accepted anchor is {canvas[0]}x{canvas[1]}; refusing to resize"
            )
        master.append(converted.copy())
    master[0] = exact_anchor.copy()
    master[-1] = exact_anchor.copy()
    return master


def _encode_spritesheet(frames: list[Image.Image]) -> bytes:
    if not frames:
        raise RuntimeError("cannot encode an empty motion spritesheet")
    width, height = frames[0].size
    sheet = Image.new("RGBA", (width * len(frames), height), (255, 255, 255, 0))
    for index, frame in enumerate(frames):
        if frame.size != (width, height):
            raise RuntimeError("motion master frame sizes changed during spritesheet encoding")
        sheet.paste(frame, (index * width, 0))
    output = BytesIO()
    sheet.save(output, format="PNG")
    return output.getvalue()


def _encode_png(image: Image.Image) -> bytes:
    output = BytesIO()
    image.save(output, format="PNG", optimize=False)
    return output.getvalue()


def _anchor_bbox(anchor: dict[str, Any], image: Image.Image) -> list[float] | None:
    """Return only a reviewed character-body bbox for pose-guide scaling.

    The complete foreground is not a safe fallback: staffs, wings, capes and
    long hair expand that box and turn a human pose into a canvas-sized giant.
    Without reviewed body geometry, the centered canonical pose template is
    deliberately safer and remains independent of equipment.
    """

    raw = anchor.get("neutral_bbox")
    if isinstance(raw, dict):
        if all(raw.get(key) is not None for key in ("x", "y", "width", "height")):
            left, top = float(raw["x"]), float(raw["y"])
            return [left, top, left + float(raw["width"]), top + float(raw["height"])]
    elif isinstance(raw, (list, tuple)) and len(raw) == 4:
        return [float(value) for value in raw]

    return None


class StudioRunner:
    def __init__(self, store: StudioStore, client: ComfyClient | None = None):
        self.store = store
        self.client = client or ComfyClient()

    def cleanup_prompt(self, prompt_id: str, *, log: LogCallback) -> None:
        """Reconcile a persisted prompt before a restarted worker accepts new work."""

        self.client._abort_and_wait_for_cleanup(prompt_id, reason="server restart", log=log)

    def _enqueue_tracked(
        self,
        workflow: dict[str, Any],
        *,
        on_prompt_id: PromptIdCallback | None,
        log: LogCallback,
    ) -> str:
        prompt_id = self.client.enqueue(workflow)
        if on_prompt_id is not None:
            try:
                on_prompt_id(prompt_id)
            except Exception:
                self.client._abort_and_wait_for_cleanup(
                    prompt_id,
                    reason="prompt-id persistence failure",
                    log=log,
                )
                raise
        return prompt_id

    def run(
        self,
        kind: str,
        project_id: str,
        params: dict[str, Any],
        *,
        log: LogCallback,
        cancelled: CancelCallback,
        on_prompt_id: PromptIdCallback | None = None,
    ) -> dict[str, Any]:
        if cancelled():
            raise RuntimeError("job cancelled")
        expected_signature = params.get("_input_signature")
        project = self.store.get_project(project_id)
        current_signature = self.store.generation_signature(project, kind, params)
        if expected_signature and current_signature != expected_signature:
            raise RuntimeError("project generation inputs changed before the job started")
        if kind == "canonicalize":
            return self.canonicalize(
                project_id,
                seed=int(params.get("seed", 20260715)),
                loadout_id=str(params.get("loadout_id", "default")),
                expected_signature=expected_signature or current_signature,
                log=log,
                cancelled=cancelled,
                on_prompt_id=on_prompt_id,
            )
        if kind == "motion":
            return self.generate_motion(
                project_id,
                motion_id=str(params.get("motion_id", "")),
                seed=int(params.get("seed", 20260715)),
                expected_signature=expected_signature or current_signature,
                generation_params=params,
                log=log,
                cancelled=cancelled,
                on_prompt_id=on_prompt_id,
            )
        if kind == "viseme_atlas":
            return self.generate_viseme_atlas(
                project_id,
                seed=int(params.get("seed", 20260715)),
                loadout_id=str(params.get("loadout_id", project.get("active_loadout_id", "default"))),
                expected_signature=expected_signature or current_signature,
                generation_params=params,
                log=log,
                cancelled=cancelled,
                on_prompt_id=on_prompt_id,
            )
        if kind == "temporal_repair":
            return self.repair_motion(
                project_id,
                motion_id=str(params.get("motion_id", "")),
                loadout_id=str(params.get("loadout_id", project.get("active_loadout_id", "default"))),
                seed=int(params.get("seed", 20260715)),
                expected_signature=expected_signature or current_signature,
                log=log,
                cancelled=cancelled,
                on_prompt_id=on_prompt_id,
            )
        if kind == "runtime_export":
            return self.export_runtime_clip(
                project_id,
                motion_id=str(params.get("motion_id", "")),
                loadout_id=str(params.get("loadout_id", project.get("active_loadout_id", "default"))),
                expected_signature=expected_signature or current_signature,
                generation_params=params,
                log=log,
                cancelled=cancelled,
                on_prompt_id=on_prompt_id,
            )
        if kind == "component_build":
            return self.build_component(
                project_id,
                actions=params.get("actions"),
                loadout_id=str(params.get("loadout_id", project.get("active_loadout_id", "default"))),
                seed=int(params.get("seed", 20260715)),
                max_attempts=int(params.get("max_attempts", 2)),
                force=bool(params.get("force", False)),
                rerun_action=str(params.get("rerun_action", "") or ""),
                start_step=str(params.get("start_step", "w1") or "w1"),
                extra_prompt=str(params.get("extra_prompt", "") or ""),
                negative_prompt=str(params.get("negative_prompt", "") or ""),
                positive_prompt=str(params.get("positive_prompt", "") or ""),
                frame_count=int(params.get("frame_count", 0) or 0),
                log=log,
                cancelled=cancelled,
                on_prompt_id=on_prompt_id,
            )
        raise ValueError(f"unknown Studio job kind: {kind}")

    def build_component(
        self,
        project_id: str,
        *,
        actions: Any,
        loadout_id: str,
        seed: int,
        max_attempts: int,
        force: bool,
        rerun_action: str,
        start_step: str,
        extra_prompt: str,
        negative_prompt: str,
        positive_prompt: str,
        frame_count: int,
        log: LogCallback,
        cancelled: CancelCallback,
        on_prompt_id: PromptIdCallback | None = None,
    ) -> dict[str, Any]:
        """Build and publish the small public character component in one job.

        W6/W8/W12 remain implementation details.  A public caller uploads one
        reference and receives only a ready manifest or a failed build.
        """

        public_actions = normalize_component_actions(actions)
        return self._build_original_component(
            project_id,
            public_actions=public_actions,
            seed=seed,
            force=force,
            rerun_action=rerun_action,
            start_step=start_step,
            extra_prompt=extra_prompt,
            negative_prompt=negative_prompt,
            positive_prompt=positive_prompt,
            frame_count=frame_count,
            log=log,
            cancelled=cancelled,
        )

    def _build_original_component(
        self,
        project_id: str,
        *,
        public_actions: list[str],
        seed: int,
        force: bool,
        rerun_action: str,
        start_step: str,
        extra_prompt: str,
        negative_prompt: str,
        positive_prompt: str,
        frame_count: int,
        log: LogCallback,
        cancelled: CancelCallback,
    ) -> dict[str, Any]:
        """Public builder backed exclusively by the original W1 -> W2 -> W3 pipeline."""
        project = self.store.get_project(project_id)
        primary_id = str((project.get("references") or {}).get("primary") or "")
        if not primary_id:
            raise ValueError("primary reference is required")
        source_path, _ = self.store.get_asset(project_id, primary_id)
        script = PROJECT_ROOT / "drivers" / "run_quick_sprite_pipeline.py"
        built: list[str] = []
        for index, action in enumerate(public_actions, start=1):
            project = self.store.get_project(project_id)
            existing = (project.get("component") or {}).get("actions", {}).get(action, {})
            if rerun_action and action != rerun_action:
                # A per-action rerender is a hard isolation boundary. Never
                # generate, repair, or mutate neighbouring actions merely
                # because their current record is pending or failed.
                if isinstance(existing, dict) and existing.get("status") == "ready":
                    built.append(action)
                continue
            should_rerun = not rerun_action or action == rerun_action
            if (not force or not should_rerun) and isinstance(existing, dict) and existing.get("status") == "ready":
                log(f"Published {action}.")
                built.append(action)
                continue
            log(f"Build 2/3 ({index}/{len(public_actions)}): original W1/W2/W3 pipeline for {action}.")
            preset = component_motion_id(action)
            command = [
                sys.executable,
                "-u",
                str(script),
                "--source", str(source_path),
                "--preset", preset,
                "--name", f"{project_id}_{action}",
                "--cell-size", "512",
                "--seed-w1", str(seed + index * 101),
                "--seed-w2", str(seed + index * 1009),
                "--start-step", start_step if action == rerun_action else "w1",
            ]
            if frame_count and action == rerun_action:
                command.extend(["--frames", str(frame_count)])
            if extra_prompt and action == rerun_action:
                command.extend(["--extra-prompt", extra_prompt])
            if negative_prompt and action == rerun_action:
                command.extend(["--negative-prompt", negative_prompt])
            if positive_prompt and action == rerun_action:
                command.extend(["--positive-override", positive_prompt])
            process = subprocess.Popen(
                command,
                cwd=str(PROJECT_ROOT),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            result: dict[str, Any] | None = None
            assert process.stdout is not None
            for raw_line in process.stdout:
                line = raw_line.rstrip()
                if line:
                    log(line)
                if line.startswith("RESULT_JSON:"):
                    result = json.loads(line.split(":", 1)[1].strip())
                elif line.startswith("PROMPT_JSON:"):
                    prompt_result = json.loads(line.split(":", 1)[1].strip())
                    prompt_stage = str(prompt_result.get("stage", ""))
                    if prompt_stage in {"w1", "w2"}:
                        self.store.save_component_prompts(
                            project_id,
                            action_id=action,
                            stage=prompt_stage,
                            positive_prompt=str(prompt_result.get("positive", "")),
                            negative_prompt=str(prompt_result.get("negative", "")),
                        )
                elif line.startswith("STAGE_JSON:"):
                    stage_result = json.loads(line.split(":", 1)[1].strip())
                    stage = str(stage_result.get("stage", ""))
                    stage_path = Path(str(stage_result.get("path", "")))
                    if stage in {"w1", "w2"} and stage_path.is_file():
                        stage_data = _browser_mp4_bytes(stage_path) if stage == "w2" else stage_path.read_bytes()
                        self.store.save_component_stage(
                            project_id,
                            action_id=action,
                            stage=stage,
                            filename=f"{action}_{stage}{stage_path.suffix.lower()}",
                            data=stage_data,
                            positive_prompt=(str(stage_result["positive"]) if "positive" in stage_result else None),
                            negative_prompt=(str(stage_result["negative"]) if "negative" in stage_result else None),
                        )
                if cancelled():
                    process.terminate()
                    raise RuntimeError("job cancelled")
            return_code = process.wait()
            if return_code != 0 or not result:
                if isinstance(existing, dict) and existing.get("status") == "ready" and (
                    existing.get("stages") or {}
                ).get("w3_asset_id"):
                    self.store.restore_component_action(
                        project_id,
                        action_id=action,
                        record=existing,
                    )
                raise RuntimeError(f"original W1/W2/W3 pipeline failed for {action}")
            sheet = Path(str(result["w3"]))
            if not sheet.is_file():
                raise RuntimeError(f"original pipeline produced no spritesheet for {action}")
            runtime_frame_count = int(result["output_frames"])
            sheet_data = sheet.read_bytes()
            if runtime_frame_count * 512 > 16384:
                # Chromium/WebGL image decoders commonly cap one dimension at
                # 16384 px. The 33rd idle frame closes the loop and duplicates
                # the start, so omit it from the browser runtime sheet.
                runtime_frame_count = 16384 // 512
                with Image.open(sheet) as source:
                    runtime_sheet = source.convert("RGBA").crop((0, 0, runtime_frame_count * 512, 512))
                sheet_data = _encode_png(runtime_sheet)
            project, _ = self.store.save_component_animation(
                project_id,
                action_id=action,
                filename=f"{action}_512.png",
                data=sheet_data,
                frame_count=runtime_frame_count,
                fps=14 if action in {"run_right", "run_left"} else (12 if action in {"idle", "walk_right", "walk_left", "jump_start", "jump_up"} else 16),
                w1_filename=f"{action}_w1.png",
                w1_data=Path(str(result["w1"])).read_bytes(),
                w2_filename=f"{action}_w2.mp4",
                w2_data=_browser_mp4_bytes(Path(str(result["w2"]))),
            )
            built.append(action)
            log(f"Published {action}.")
        project = self.store.get_project(project_id)
        manifest = build_component_manifest(project, requested_actions=public_actions)
        log("Component is ready.")
        return {"component_id": project_id, "actions": built, "manifest": manifest}

        # Legacy Studio path retained below for /studio-debug only.
        public_actions = normalize_component_actions(actions)
        motion_ids = component_motion_ids(public_actions)
        max_attempts = max(1, min(3, int(max_attempts)))
        project = self.store.get_project(project_id)
        anchor = self.store.anchor_for(project, loadout_id)

        if force or anchor.get("status") != "ready" or not anchor.get("asset_id"):
            log("Build 1/3: preparing the character from the reference.")
            canonical_params = {"loadout_id": loadout_id}
            canonical_signature = self.store.generation_signature(project, "canonicalize", canonical_params)
            candidate = self.canonicalize(
                project_id,
                seed=seed,
                loadout_id=loadout_id,
                expected_signature=canonical_signature,
                log=log,
                cancelled=cancelled,
                on_prompt_id=on_prompt_id,
            )
            candidate_project = candidate["project"]
            project = self.store.accept_anchor(
                project_id,
                expected_revision=int(candidate_project["revision"]),
                expected_asset_id=str(candidate["asset"]["id"]),
                loadout_id=loadout_id,
            )
            log("Character base passed structural checks and was accepted automatically.")
        else:
            log("Build 1/3: reusing the current character base.")

        built: list[str] = []
        for index, (public_action, motion_id) in enumerate(zip(public_actions, motion_ids), start=1):
            if cancelled():
                raise RuntimeError("job cancelled")
            project = self.store.get_project(project_id)
            anchor = self.store.anchor_for(project, loadout_id)
            if public_action == "idle_smile":
                overlay = (project.get("component") or {}).get("overlays", {}).get("idle_smile", {})
                overlay_ready = bool(
                    isinstance(overlay, dict)
                    and overlay.get("status") == "ready"
                    and overlay.get("anchor_asset_id") == anchor.get("asset_id")
                    and project.get("assets", {}).get(str(overlay.get("asset_id", "")))
                )
                if not overlay_ready:
                    log(f"Build 2/3 ({index}/{len(motion_ids)}): generating local smile overlay.")
                    self.generate_smile_overlay(
                        project_id,
                        seed=seed + index * 1009,
                        loadout_id=loadout_id,
                        log=log,
                        cancelled=cancelled,
                        on_prompt_id=on_prompt_id,
                    )
                built.append(public_action)
                log(f"Published {public_action}.")
                continue
            clip = project.get("clips", {}).get(self.store.clip_key(loadout_id, motion_id), {})
            current_ready = bool(
                isinstance(clip, dict)
                and clip.get("status") == "ready"
                and clip.get("runtime_ready") is True
                and clip.get("anchor_asset_id") == anchor.get("asset_id")
                and clip.get("anchor_revision") == anchor.get("revision")
            )
            if current_ready:
                log(f"Build 2/3 ({index}/{len(motion_ids)}): reusing {public_action}.")
                built.append(public_action)
                continue

            qc_passed = bool(
                isinstance(clip, dict)
                and clip.get("status") == "qc_pass"
                and (clip.get("qc") or {}).get("status") == "pass"
                and clip.get("anchor_asset_id") == anchor.get("asset_id")
                and clip.get("anchor_revision") == anchor.get("revision")
            )
            if not qc_passed:
                for attempt in range(max_attempts):
                    attempt_seed = seed + index * 1009 + attempt * 7919
                    log(
                        f"Build 2/3 ({index}/{len(motion_ids)}): generating {public_action}, "
                        f"attempt {attempt + 1}/{max_attempts}."
                    )
                    motion_params = {
                        "motion_id": motion_id,
                        "loadout_id": loadout_id,
                        "seed": attempt_seed,
                    }
                    project = self.store.get_project(project_id)
                    motion_signature = self.store.generation_signature(project, "motion", motion_params)
                    generated = self.generate_motion(
                        project_id,
                        motion_id=motion_id,
                        seed=attempt_seed,
                        expected_signature=motion_signature,
                        generation_params=motion_params,
                        log=log,
                        cancelled=cancelled,
                        on_prompt_id=on_prompt_id,
                    )
                    if generated.get("qc", {}).get("status") == "pass":
                        qc_passed = True
                        break
                    log(f"Automatic QC rejected {public_action}; retrying with a new seed.")
                if not qc_passed:
                    raise RuntimeError(
                        f"automatic QC rejected {public_action} after {max_attempts} attempts; component was not published"
                    )

            project = self.store.get_project(project_id)
            export_params = {"motion_id": motion_id, "loadout_id": loadout_id}
            export_signature = self.store.generation_signature(project, "runtime_export", export_params)
            log(f"Build 3/3 ({index}/{len(motion_ids)}): removing the background from {public_action}.")
            exported = self.export_runtime_clip(
                project_id,
                motion_id=motion_id,
                loadout_id=loadout_id,
                expected_signature=export_signature,
                generation_params=export_params,
                log=log,
                cancelled=cancelled,
                on_prompt_id=on_prompt_id,
            )
            exported_project = exported["project"]
            self.store.accept_runtime_export(
                project_id,
                motion_id=motion_id,
                loadout_id=loadout_id,
                expected_revision=int(exported_project["revision"]),
                expected_asset_id=str(exported["asset"]["id"]),
            )
            built.append(public_action)
            log(f"Published {public_action}.")

        project = self.store.get_project(project_id)
        manifest = build_component_manifest(
            project,
            loadout_id,
            requested_actions=public_actions,
        )
        log("Component is ready.")
        return {
            "component_id": project_id,
            "actions": built,
            "manifest": manifest,
        }

    def generate_smile_overlay(
        self,
        project_id: str,
        *,
        seed: int,
        loadout_id: str,
        log: LogCallback,
        cancelled: CancelCallback,
        on_prompt_id: PromptIdCallback | None = None,
    ) -> dict[str, Any]:
        """Generate only a restrained RGBA mouth patch; never regenerate the body."""
        project = self.store.get_project(project_id)
        anchor_contract = self.store.anchor_for(project, loadout_id)
        if anchor_contract.get("status") != "ready" or not anchor_contract.get("asset_id"):
            raise ValueError("accepted anchor is required for the smile overlay")
        canvas = anchor_contract.get("canvas") or {}
        width, height = int(canvas.get("width", 0)), int(canvas.get("height", 0))
        if (width, height) != (512, 512):
            raise ValueError("smile overlay requires a 512x512 anchor")
        # Conservative lower-face crop for the standardized centered character.
        roi = {"x": 192, "y": 128, "width": 128, "height": 96}
        anchor_name = _stage_asset(self.store, project_id, anchor_contract["asset_id"], "smile_anchor")
        workflow = json.loads(W11_PATH.read_text(encoding="utf-8"))
        workflow[_find_one(workflow, "UnetLoaderGGUF")]["inputs"]["unet_name"] = W1_UNET_NAME
        workflow[_find_one(workflow, "LoraLoaderModelOnly")]["inputs"]["lora_name"] = W1_LORA_NAME
        workflow[_find_one(workflow, "CLIPLoaderGGUF")]["inputs"]["clip_name"] = W1_CLIP_NAME
        workflow[_find_one(workflow, "VAELoader")]["inputs"]["vae_name"] = W1_VAE_NAME
        workflow[_find_one(workflow, "LoadImage", "canonical anchor")]["inputs"]["image"] = anchor_name
        workflow[_find_one(workflow, "ImageCrop")]["inputs"].update(roi)
        workflow[_find_one(workflow, "ImageScale", "expression tile")]["inputs"].update(
            {"width": roi["width"], "height": roi["height"]}
        )
        workflow[_find_one(workflow, "TextEncodeQwenImageEditPlus", "Target face")]["inputs"]["prompt"] = (
            "Change only the lips into a very subtle warm closed-mouth smile. Preserve the exact eyes, nose, "
            "chin, face shape, hair, costume, line art, colors and every unrelated pixel. No open mouth, no teeth."
        )
        workflow[_find_one(workflow, "KSampler")]["inputs"]["seed"] = seed
        workflow[_find_one(workflow, "SaveImage")]["inputs"]["filename_prefix"] = (
            f"character_studio/projects/{project_id}/component/smile_overlay"
        )
        self.client.ensure_online()
        self.client.free()
        log("W11 smile: editing only a 128x96 lower-face tile.")
        prompt_id = self._enqueue_tracked(workflow, on_prompt_id=on_prompt_id, log=log)
        history = self.client.wait(prompt_id, timeout_s=1200, log=log, cancelled=cancelled)
        outputs = [item for item in self.client.output_files(history) if item.suffix.lower() == ".png" and item.is_file()]
        if not outputs:
            raise RuntimeError("W11 produced no smile tile")
        target_path = max(outputs, key=lambda item: item.stat().st_mtime)
        anchor_path, _ = self.store.get_asset(project_id, str(anchor_contract["asset_id"]))
        with Image.open(anchor_path) as source:
            anchor = source.convert("RGBA")
        original = anchor.crop((roi["x"], roi["y"], roi["x"] + roi["width"], roi["y"] + roi["height"]))
        with Image.open(target_path) as source:
            target = source.convert("RGBA").resize((roi["width"], roi["height"]), Image.Resampling.LANCZOS)
        difference = ImageChops.difference(original.convert("RGB"), target.convert("RGB")).convert("L")
        alpha = difference.point(lambda value: 255 if value >= 12 else 0)
        mouth_mask = Image.new("L", (roi["width"], roi["height"]), 0)
        ImageDraw.Draw(mouth_mask).ellipse((35, 30, 93, 64), fill=255)
        alpha = ImageChops.multiply(alpha, mouth_mask).filter(ImageFilter.GaussianBlur(2.0))
        coverage = sum(1 for value in alpha.getdata() if value > 16) / float(roi["width"] * roi["height"])
        if coverage < 0.002 or coverage > 0.20:
            raise RuntimeError(f"smile edit changed an unsafe area ({coverage:.1%}); component was not published")
        patch = target.copy()
        patch.putalpha(alpha)
        updated, asset = self.store.save_component_overlay(
            project_id,
            action_id="idle_smile",
            filename="idle_smile_overlay.png",
            data=_encode_png(patch),
            roi=roi,
            loadout_id=loadout_id,
        )
        self.client.free()
        return {"project": updated, "asset": asset, "roi": roi, "coverage": coverage, "prompt_id": prompt_id}

    def _finalize_motion_output(
        self,
        project_id: str,
        *,
        motion_id: str,
        output: Path,
        expected_signature: str,
        generation_params: dict[str, Any],
        log: LogCallback,
        cancelled: CancelCallback,
        expected_keypoints: list[dict[int, tuple[float, float, float]]] | None = None,
        rigid_report: dict[str, Any] | None = None,
        control_pose_frames: list[Image.Image] | None = None,
        control_mask_frames: list[Image.Image] | None = None,
    ) -> tuple[dict[str, Any], dict[str, dict[str, Any]], dict[str, Any]]:
        if cancelled():
            raise RuntimeError("job cancelled")
        motion_contract = get_motion(motion_id) or {}
        generation_params = {
            **generation_params,
            "neutral_corridor_frames": int(motion_contract.get("neutral_corridor_frames", 0) or 0),
        }
        project = self.store.get_project(project_id)
        loadout_id = str(generation_params.get("loadout_id", "default"))
        anchor_contract = self.store.anchor_for(project, loadout_id)
        anchor_asset_id = anchor_contract.get("asset_id")
        if anchor_contract.get("status") != "ready" or not anchor_asset_id:
            raise RuntimeError("accepted anchor changed before motion postprocessing")
        anchor_path, _ = self.store.get_asset(project_id, anchor_asset_id)
        with Image.open(anchor_path) as opened_anchor:
            anchor = opened_anchor.convert("RGBA").copy()
        declared_canvas = anchor_contract.get("canvas")
        actual_canvas = {"width": anchor.width, "height": anchor.height}
        if declared_canvas and declared_canvas != actual_canvas:
            raise RuntimeError(
                f"accepted anchor pixels are {anchor.width}x{anchor.height}, "
                f"but its contract declares {declared_canvas}; refusing to resize"
            )

        decoded_frames, video_metadata = load_video_frames(output)
        master_frames = _replace_exact_anchor_endpoints(decoded_frames, anchor)
        report = analyze_frames(
            master_frames,
            anchor=anchor,
            boundary_width=max(1, int(generation_params.get("neutral_corridor_frames", 4) or 4)),
            expected_keypoints=expected_keypoints,
            control_pose_frames=control_pose_frames,
            control_mask_frames=control_mask_frames,
            source={
                "kind": "decoded_video_master",
                "filename": output.name,
                "endpoint_replacement": "exact_anchor_pixels",
                **video_metadata,
            },
        )
        if rigid_report:
            report["rigid_props"] = rigid_report
            rigid_qc = rigid_report.get("qc") or {}
            if not rigid_qc.get("ok", False):
                report["status"] = "fail"
                report["passed"] = False
            elif rigid_qc.get("needs_review") and report["status"] == "pass":
                report["status"] = "review"
                report["passed"] = False
            if rigid_qc.get("needs_review"):
                issue = {
                    "id": "rigid_grip_manual_review",
                    "status": "warning",
                    "message": "Rigid prop transforms passed, but finger/handle occlusion requires manual review.",
                }
                report.setdefault("checks", []).append(issue)
                report.setdefault("issues", []).append(issue)
        master_spritesheet_data = _encode_spritesheet(master_frames)
        runtime_spritesheet_data = _encode_spritesheet(master_frames[:-1])
        if cancelled():
            raise RuntimeError("job cancelled")
        updated, assets = self.store.finalize_clip(
            project_id,
            motion_id=motion_id,
            source_video_filename=output.name,
            source_video_data=output.read_bytes(),
            master_spritesheet_filename=f"{motion_id}_qc_master_spritesheet.png",
            master_spritesheet_data=master_spritesheet_data,
            runtime_spritesheet_filename=f"{motion_id}_runtime_spritesheet.png",
            runtime_spritesheet_data=runtime_spritesheet_data,
            qc_report=report,
            expected_generation_signature=expected_signature,
            generation_params=generation_params,
        )
        log(
            f"Continuity QC {report['status']}: {len(master_frames)} master frames; "
            f"{len(master_frames) - 1} review frames; endpoints replaced with exact anchor pixels."
        )
        return updated, assets, report

    def canonicalize(
        self,
        project_id: str,
        *,
        seed: int,
        loadout_id: str,
        expected_signature: str,
        log: LogCallback,
        cancelled: CancelCallback,
        on_prompt_id: PromptIdCallback | None = None,
    ) -> dict[str, Any]:
        project = self.store.get_project(project_id)
        refs = project.get("references", {})
        if not refs.get("primary"):
            raise ValueError("primary reference is required")
        profile = _profile(project)
        width, height = int(profile["width"]), int(profile["height"])
        loadout_props = select_loadout_props(project, loadout_id)
        workflow = json.loads(W6_PATH.read_text(encoding="utf-8"))

        primary_name = _stage_asset(self.store, project_id, refs["primary"], "primary")
        workflow[_find_one(workflow, "LoadImage", "primary")]["inputs"]["image"] = primary_name
        positive_id = _find_one(workflow, "TextEncodeQwenImageEditPlus", "canonical identity")
        negative_id = _find_one(workflow, "TextEncodeQwenImageEditPlus", "negative")
        if refs.get("secondary"):
            staged = _stage_asset(self.store, project_id, refs["secondary"], "secondary")
            workflow[_find_one(workflow, "LoadImage", "secondary")]["inputs"]["image"] = staged
        else:
            workflow[positive_id]["inputs"].pop("image2", None)
            workflow[negative_id]["inputs"].pop("image2", None)

        detail_sources: list[Path] = []
        if refs.get("detail"):
            detail_sources.append(self.store.get_asset(project_id, refs["detail"])[0])
        for prop in loadout_props:
            prop_asset_id = prop.get("reference_asset_id")
            if prop_asset_id:
                detail_sources.append(self.store.get_asset(project_id, prop_asset_id)[0])
        if detail_sources:
            if len(detail_sources) == 1 and refs.get("detail") and not loadout_props:
                detail_name = _stage_asset(self.store, project_id, refs["detail"], "detail")
            else:
                contact = INPUT_DIR / f"studio_{project_id}_{loadout_id}_detail_props.png"
                build_reference_contact_sheet(detail_sources, contact, width=width, height=height)
                detail_name = contact.name
            workflow[_find_one(workflow, "LoadImage", "detail")]["inputs"]["image"] = detail_name
        else:
            workflow[positive_id]["inputs"].pop("image3", None)
            workflow[negative_id]["inputs"].pop("image3", None)

        workflow[positive_id]["inputs"]["prompt"] += canonical_equipment_prompt(loadout_props)

        pose_name = _neutral_pose(project_id, width, height)
        workflow[_find_one(workflow, "LoadImage", "neutral anchor pose")]["inputs"]["image"] = pose_name
        for node in workflow.values():
            if node.get("class_type") == "ImageScale":
                node["inputs"]["width"] = width
                node["inputs"]["height"] = height

        workflow[_find_one(workflow, "UnetLoaderGGUF")]["inputs"]["unet_name"] = W1_UNET_NAME
        workflow[_find_one(workflow, "LoraLoaderModelOnly")]["inputs"]["lora_name"] = W1_LORA_NAME
        workflow[_find_one(workflow, "CLIPLoaderGGUF")]["inputs"]["clip_name"] = W1_CLIP_NAME
        workflow[_find_one(workflow, "VAELoader")]["inputs"]["vae_name"] = W1_VAE_NAME
        workflow[_find_one(workflow, "ControlNetLoader")]["inputs"]["control_net_name"] = W1_CONTROLNET_NAME
        workflow[_find_one(workflow, "KSampler")]["inputs"]["seed"] = seed
        next_revision = int(self.store.anchor_for(project, loadout_id).get("revision", 0)) + 1
        prefix = f"character_studio/projects/{project_id}/anchor/anchor_r{next_revision}"
        workflow[_find_one(workflow, "SaveImage")]["inputs"]["filename_prefix"] = prefix

        self.client.ensure_online()
        log(
            f"W6 canonicalize: {width}×{height}, "
            f"character refs={sum(bool(refs.get(key)) for key in ('primary', 'secondary', 'detail'))}, "
            f"loadout props={len(loadout_props)}, loadout={loadout_id}"
        )
        self.client.free()
        if cancelled():
            raise RuntimeError("job cancelled")
        prompt_id = self._enqueue_tracked(workflow, on_prompt_id=on_prompt_id, log=log)
        log(f"Queued W6 as {prompt_id}")
        history = self.client.wait(prompt_id, timeout_s=1200, log=log, cancelled=cancelled)
        outputs = [item for item in self.client.output_files(history) if item.suffix.lower() == ".png" and item.is_file()]
        if not outputs:
            raise RuntimeError("W6 produced no PNG anchor")
        output = max(outputs, key=lambda item: item.stat().st_mtime)
        anchor_data, background_normalized = _canonical_anchor_png(output)
        if background_normalized:
            log("Flattened the connected light-neutral W6 background to exact RGB white.")
        updated, asset = self.store.add_asset(
            project_id,
            filename=output.name,
            content_type="image/png",
            data=anchor_data,
            role="anchor",
            generated=True,
            expected_generation_signature=expected_signature,
            generation_kind="canonicalize",
            generation_params={"loadout_id": loadout_id},
        )
        try:
            self.client.free()
        except Exception as exc:
            log(f"Anchor was saved, but post-commit VRAM cleanup failed: {exc}")
        log("Anchor candidate saved; manual approval is required before motion generation.")
        return {"project": updated, "asset": asset, "prompt_id": prompt_id, "source_output": str(output)}

    def generate_motion(
        self,
        project_id: str,
        *,
        motion_id: str,
        seed: int,
        expected_signature: str,
        generation_params: dict[str, Any],
        log: LogCallback,
        cancelled: CancelCallback,
        on_prompt_id: PromptIdCallback | None = None,
    ) -> dict[str, Any]:
        project = self.store.get_project(project_id)
        motion = get_motion(motion_id)
        if motion is None:
            raise ValueError(f"unknown motion: {motion_id}")
        if motion["generation_mode"] == "pose_control":
            return self.generate_pose_motion(
                project_id,
                motion_id=motion_id,
                seed=seed,
                expected_signature=expected_signature,
                generation_params=generation_params,
                log=log,
                cancelled=cancelled,
                on_prompt_id=on_prompt_id,
            )
        if motion["generation_mode"] == "face_layer":
            return self.generate_face_motion(
                project_id,
                motion_id=motion_id,
                seed=seed,
                expected_signature=expected_signature,
                generation_params=generation_params,
                log=log,
                cancelled=cancelled,
                on_prompt_id=on_prompt_id,
            )
        if motion["generation_mode"] != "prompt_loop":
            raise ValueError(
                f"{motion_id} requires {motion['generation_mode']}; Studio will not silently use prompt-only generation"
            )
        loadout_id = str(generation_params.get("loadout_id", "default"))
        anchor = self.store.anchor_for(project, loadout_id)
        if anchor.get("status") != "ready" or not anchor.get("asset_id"):
            raise ValueError("accept the canonical anchor before generating motions")
        profile = _profile(project)
        width, height = int(profile["width"]), int(profile["height"])
        workflow = json.loads(W7_PATH.read_text(encoding="utf-8"))
        anchor_name = _stage_asset(self.store, project_id, anchor["asset_id"], "anchor")

        workflow[_find_one(workflow, "LoadImage", "canonical anchor")]["inputs"]["image"] = anchor_name
        high_id = _find_one(workflow, "UnetLoaderGGUF", "high-noise")
        low_id = _find_one(workflow, "UnetLoaderGGUF", "low-noise")
        workflow[high_id]["inputs"]["unet_name"] = W2_HIGH_UNET_NAME
        workflow[low_id]["inputs"]["unet_name"] = W2_LOW_UNET_NAME
        workflow[_find_one(workflow, "CLIPLoaderGGUF")]["inputs"]["clip_name"] = W2_CLIP_NAME
        workflow[_find_one(workflow, "VAELoader")]["inputs"]["vae_name"] = W2_VAE_NAME
        loadout_props = select_loadout_props(project, loadout_id)
        neutral_corridor = int(motion.get("neutral_corridor_frames", 4) or 4)
        workflow[_find_one(workflow, "CLIPTextEncode", "motion prompt")]["inputs"]["text"] = (
            W7_GLOBAL_PROMPT
            + motion["prompt"]
            + f" Hold the exact neutral anchor for the first and last {neutral_corridor} frames; "
            "put anticipation, action and recovery only between those neutral gates."
            + equipment_prompt(loadout_props)
        )
        workflow[_find_one(workflow, "CLIPTextEncode", "negative")]["inputs"]["text"] = W7_NEGATIVE
        conditioning_id = _find_one(workflow, "WanFirstLastFrameToVideo")
        workflow[conditioning_id]["inputs"].update(
            {"width": width, "height": height, "length": int(motion["frames"])}
        )
        for node in workflow.values():
            if node.get("class_type") == "KSamplerAdvanced":
                node["inputs"]["noise_seed"] = seed
        workflow[_find_one(workflow, "CreateVideo")]["inputs"]["fps"] = float(motion["fps"])
        run_id = f"{int(time.time())}_{seed}"
        prefix = f"character_studio/projects/{project_id}/runs/{run_id}/{motion_id}"
        workflow[_find_one(workflow, "SaveVideo")]["inputs"]["filename_prefix"] = prefix

        self.client.ensure_online()
        log(f"W7 {motion_id}: {width}×{height}, {motion['frames']} master frames at {motion['fps']} fps")
        self.client.free()
        if cancelled():
            raise RuntimeError("job cancelled")
        prompt_id = self._enqueue_tracked(workflow, on_prompt_id=on_prompt_id, log=log)
        log(f"Queued W7 as {prompt_id}")
        history = self.client.wait(prompt_id, timeout_s=2400, log=log, cancelled=cancelled)
        outputs = [item for item in self.client.output_files(history) if item.suffix.lower() == ".mp4" and item.is_file()]
        if not outputs:
            raise RuntimeError("W7 produced no MP4 clip")
        output = max(outputs, key=lambda item: item.stat().st_mtime)
        self.client.free()
        updated, assets, report = self._finalize_motion_output(
            project_id,
            motion_id=motion_id,
            output=output,
            expected_signature=expected_signature,
            generation_params=generation_params,
            log=log,
            cancelled=cancelled,
        )
        return {
            "project": updated,
            "asset": assets["source_video"],
            "assets": assets,
            "qc": report,
            "prompt_id": prompt_id,
            "source_output": str(output),
        }

    def generate_pose_motion(
        self,
        project_id: str,
        *,
        motion_id: str,
        seed: int,
        expected_signature: str,
        generation_params: dict[str, Any],
        log: LogCallback,
        cancelled: CancelCallback,
        on_prompt_id: PromptIdCallback | None = None,
    ) -> dict[str, Any]:
        project = self.store.get_project(project_id)
        motion = get_motion(motion_id)
        if motion is None or motion["generation_mode"] != "pose_control":
            raise ValueError(f"{motion_id} is not a pose-control motion")
        if motion_id not in POSE_GUIDE_MOTIONS:
            raise ValueError(f"deterministic pose guide is not implemented for {motion_id}")
        loadout_id = str(generation_params.get("loadout_id", "default"))
        anchor = self.store.anchor_for(project, loadout_id)
        if anchor.get("status") != "ready" or not anchor.get("asset_id"):
            raise ValueError("accept the canonical anchor before generating motions")
        profile = _profile(project)
        width, height = int(profile["width"]), int(profile["height"])
        workflow = json.loads(W8_PATH.read_text(encoding="utf-8"))
        anchor_name = _stage_asset(self.store, project_id, anchor["asset_id"], "anchor")
        anchor_path, _ = self.store.get_asset(project_id, anchor["asset_id"])
        with Image.open(anchor_path) as opened_anchor:
            anchor_pixels = opened_anchor.convert("RGBA").copy()
        neutral_corridor = int(motion.get("neutral_corridor_frames", 4) or 4)
        temporal_feather = min(4, max(1, neutral_corridor))
        anchor_bbox = _anchor_bbox(anchor, anchor_pixels)
        anchor_keypoints = anchor.get("pose_keypoints")
        guide_prefix = f"studio_{project_id}_{motion_id}"
        expected_keypoints = build_pose_keypoints(
            motion_id,
            width=width,
            height=height,
            frames=int(motion["frames"]),
            neutral_corridor_frames=neutral_corridor,
            temporal_feather_frames=temporal_feather,
            anchor_keypoints=anchor_keypoints,
            anchor_bbox=anchor_bbox,
        )
        loadout_props = select_loadout_props(project, loadout_id)
        asset_sizes: dict[str, tuple[int, int]] = {}
        for prop in loadout_props:
            if not prop.get("rigid") or not prop.get("reference_asset_id"):
                continue
            prop_path, _ = self.store.get_asset(project_id, prop["reference_asset_id"])
            with Image.open(prop_path) as prop_image:
                asset_sizes[str(prop["id"])] = prop_image.size
        rigid = prepare_rigid_pose_guides(
            project,
            loadout_id,
            expected_keypoints,
            width=width,
            height=height,
            fps=int(motion["fps"]),
            neutral_corridor_frames=neutral_corridor,
            temporal_feather_frames=temporal_feather,
            asset_sizes=asset_sizes,
        )
        expected_keypoints = rigid["pose_points"]
        guides = write_pose_control_videos(
            motion_id,
            output_dir=INPUT_DIR,
            width=width,
            height=height,
            frames=int(motion["frames"]),
            fps=int(motion["fps"]),
            prefix=guide_prefix,
            neutral_corridor_frames=neutral_corridor,
            temporal_feather_frames=temporal_feather,
            anchor_keypoints=anchor_keypoints,
            anchor_bbox=anchor_bbox,
            pose_points_override=expected_keypoints,
            extra_masks=rigid["union_masks"] if rigid["enabled"] else None,
        )
        if not guides["endpoint_masks_zero"]:
            raise RuntimeError("pose guide endpoint masks are not zero")

        workflow[_find_one(workflow, "LoadVideo", "openpose guide")]["inputs"]["file"] = guides["pose_video"].name
        workflow[_find_one(workflow, "LoadVideo", "output composite mask")]["inputs"]["file"] = guides["mask_video"].name
        workflow[_find_one(workflow, "LoadImage", "canonical anchor")]["inputs"]["image"] = anchor_name
        for entry in workflow.values():
            if entry.get("class_type") == "ImageScale":
                entry["inputs"]["width"] = width
                entry["inputs"]["height"] = height
        workflow[_find_one(workflow, "RepeatImageBatch")]["inputs"]["amount"] = int(motion["frames"])
        condition_id = _find_one(workflow, "WanVaceToVideo")
        # Native VACE pose / Animate-Anything conditioning generates the full
        # frame. The regional motion mask belongs only to the post-decode
        # ImageCompositeMasked node; feeding it here leaks the OpenPose control
        # canvas into the rendered pixels.
        workflow[condition_id]["inputs"].pop("control_masks", None)
        workflow[condition_id]["inputs"].update(
            {"width": width, "height": height, "length": int(motion["frames"])}
        )
        workflow[_find_one(workflow, "CLIPLoaderGGUF")]["inputs"]["clip_name"] = W4_CLIP_NAME
        workflow[_find_one(workflow, "VAELoader")]["inputs"]["vae_name"] = W4_VAE_NAME
        workflow[_find_one(workflow, "UnetLoaderGGUF")]["inputs"]["unet_name"] = W4_UNET_NAME
        workflow[_find_one(workflow, "LoraLoaderModelOnly")]["inputs"]["lora_name"] = W4_LORA_NAME
        workflow[_find_one(workflow, "CLIPTextEncode", "precise motion")]["inputs"]["text"] = (
            W7_GLOBAL_PROMPT
            + motion["prompt"]
            + (
                " Follow the supplied OpenPose trajectory exactly. The colored skeleton and black guide canvas are "
                "conditioning metadata only and must never appear in rendered pixels."
            )
            + (" Preserve each supplied rigid prop instance and keep every planned grip contact exact." if rigid["enabled"] else "")
            + equipment_prompt(loadout_props)
        )
        workflow[_find_one(workflow, "CLIPTextEncode", "negative")]["inputs"]["text"] = (
            W7_NEGATIVE + W8_GUIDE_NEGATIVE
        )
        workflow[_find_one(workflow, "KSampler")]["inputs"]["seed"] = seed
        workflow[_find_one(workflow, "CreateVideo")]["inputs"]["fps"] = float(motion["fps"])
        run_id = f"{int(time.time())}_{seed}"
        prefix = f"character_studio/projects/{project_id}/runs/{run_id}/{motion_id}"
        workflow[_find_one(workflow, "SaveVideo")]["inputs"]["filename_prefix"] = prefix

        self.client.ensure_online()
        log(
            f"W8 {motion_id}: full-frame VACE pose condition, regional output composite, "
            f"{width}×{height}, {motion['frames']} frames"
        )
        self.client.free()
        if cancelled():
            raise RuntimeError("job cancelled")
        prompt_id = self._enqueue_tracked(workflow, on_prompt_id=on_prompt_id, log=log)
        log(f"Queued W8 as {prompt_id}")
        history = self.client.wait(prompt_id, timeout_s=2400, log=log, cancelled=cancelled)
        outputs = [item for item in self.client.output_files(history) if item.suffix.lower() == ".mp4" and item.is_file()]
        if not outputs:
            raise RuntimeError("W8 produced no MP4 clip")
        output = max(outputs, key=lambda item: item.stat().st_mtime)
        self.client.free()
        rigid_report = None
        if rigid["enabled"]:
            mask_refs: dict[str, Any] = {"instances": {}, "contacts": {}}
            union_path = write_lossless_mask_video(
                rigid["union_masks"],
                INPUT_DIR / f"{guide_prefix}_rigid_union_ffv1.mkv",
                int(motion["fps"]),
            )
            mask_refs["union"] = str(union_path)
            sidecar_by_id = {item["instance_id"]: item for item in rigid["sidecar"]["instances"]}
            for instance_id, masks in rigid["instance_masks"].items():
                path = write_lossless_mask_video(
                    masks,
                    INPUT_DIR / f"{guide_prefix}_rigid_{instance_id}_ffv1.mkv",
                    int(motion["fps"]),
                )
                mask_refs["instances"][instance_id] = str(path)
                sidecar_by_id[instance_id]["instance_mask"] = str(path)
            for instance_id, by_hand in rigid["contact_masks"].items():
                mask_refs["contacts"][instance_id] = {}
                for hand, masks in by_hand.items():
                    path = write_lossless_mask_video(
                        masks,
                        INPUT_DIR / f"{guide_prefix}_contact_{instance_id}_{hand}_ffv1.mkv",
                        int(motion["fps"]),
                    )
                    mask_refs["contacts"][instance_id][hand] = str(path)
                    sidecar_by_id[instance_id]["contact_masks"][hand] = str(path)
            rigid["sidecar"]["union_mask"] = str(union_path)
            rigid_report = {"sidecar": rigid["sidecar"], "qc": rigid["qc"], "mask_files": mask_refs}
        updated, assets, report = self._finalize_motion_output(
            project_id,
            motion_id=motion_id,
            output=output,
            expected_signature=expected_signature,
            generation_params=generation_params,
            log=log,
            cancelled=cancelled,
            expected_keypoints=expected_keypoints,
            rigid_report=rigid_report,
            control_pose_frames=load_video_frames(guides["pose_video"])[0],
            control_mask_frames=load_video_frames(guides["mask_video"])[0],
        )
        return {
            "project": updated,
            "asset": assets["source_video"],
            "assets": assets,
            "qc": report,
            "prompt_id": prompt_id,
            "source_output": str(output),
            "guide": {
                "pose_video": str(guides["pose_video"]),
                "mask_video": str(guides["mask_video"]),
                "mask_codec": guides["mask_codec"],
                "neutral_corridor_frames": neutral_corridor,
                "anchor_bbox": anchor_bbox,
                "rigid_props": rigid_report,
                "endpoint_masks_zero": True,
            },
        }

    def generate_face_motion(
        self,
        project_id: str,
        *,
        motion_id: str,
        seed: int,
        expected_signature: str,
        generation_params: dict[str, Any],
        log: LogCallback,
        cancelled: CancelCallback,
        on_prompt_id: PromptIdCallback | None = None,
    ) -> dict[str, Any]:
        """Generate one expression tile and animate it as an independent face channel."""

        if motion_id not in {"blink", "smile"}:
            raise ValueError(f"unsupported face-layer motion: {motion_id}")
        project = self.store.get_project(project_id)
        loadout_id = str(generation_params.get("loadout_id", "default"))
        anchor_contract = self.store.anchor_for(project, loadout_id)
        if anchor_contract.get("status") != "ready" or not anchor_contract.get("asset_id"):
            raise ValueError("accept the loadout anchor before generating face layers")
        canvas = anchor_contract.get("canvas") or {}
        width, height = int(canvas.get("width", 0)), int(canvas.get("height", 0))
        roi_name = "eye_roi" if motion_id == "blink" else "mouth_roi"
        roi = validate_mouth_roi(anchor_contract.get(roi_name), canvas_width=width, canvas_height=height)
        tile_width = min(320, max(64, ((roi["width"] + 15) // 16) * 16))
        tile_height = min(256, max(64, ((roi["height"] + 15) // 16) * 16))
        anchor_name = _stage_asset(self.store, project_id, anchor_contract["asset_id"], "face_anchor")
        workflow = json.loads(W11_PATH.read_text(encoding="utf-8"))
        workflow[_find_one(workflow, "UnetLoaderGGUF")]["inputs"]["unet_name"] = W1_UNET_NAME
        workflow[_find_one(workflow, "LoraLoaderModelOnly")]["inputs"]["lora_name"] = W1_LORA_NAME
        workflow[_find_one(workflow, "CLIPLoaderGGUF")]["inputs"]["clip_name"] = W1_CLIP_NAME
        workflow[_find_one(workflow, "VAELoader")]["inputs"]["vae_name"] = W1_VAE_NAME
        workflow[_find_one(workflow, "LoadImage", "canonical anchor")]["inputs"]["image"] = anchor_name
        workflow[_find_one(workflow, "ImageCrop")]["inputs"].update(roi)
        workflow[_find_one(workflow, "ImageScale", "expression tile")]["inputs"].update(
            {"width": tile_width, "height": tile_height}
        )
        expression = (
            "both eyelids naturally and fully closed for one blink; preserve eyebrows and gaze alignment"
            if motion_id == "blink"
            else "a warm subtle smile with symmetric lip corners; keep the mouth closed and preserve the nose and chin"
        )
        workflow[_find_one(workflow, "TextEncodeQwenImageEditPlus", "Target face")]["inputs"]["prompt"] = (
            f"Edit only the reviewed {roi_name} into {expression}. Preserve exact identity, face geometry, "
            "line art, colors, lighting, crop and every unrelated pixel. Produce no text or grid."
        )
        workflow[_find_one(workflow, "KSampler")]["inputs"]["seed"] = seed
        workflow[_find_one(workflow, "SaveImage")]["inputs"]["filename_prefix"] = (
            f"character_studio/projects/{project_id}/face/{loadout_id}/{motion_id}"
        )
        self.client.ensure_online()
        self.client.free()
        log(f"W11 {motion_id}: reviewed {roi_name} {roi['width']}×{roi['height']}; one sequential Qwen edit.")
        prompt_id = self._enqueue_tracked(workflow, on_prompt_id=on_prompt_id, log=log)
        history = self.client.wait(prompt_id, timeout_s=1200, log=log, cancelled=cancelled)
        outputs = [item for item in self.client.output_files(history) if item.suffix.lower() == ".png" and item.is_file()]
        if not outputs:
            raise RuntimeError(f"W11 produced no target tile for {motion_id}")
        target_path = max(outputs, key=lambda item: item.stat().st_mtime)
        anchor_path, _ = self.store.get_asset(project_id, anchor_contract["asset_id"])
        with Image.open(anchor_path) as source:
            anchor = source.convert("RGBA").copy()
        with Image.open(target_path) as source:
            target = source.convert("RGBA").resize((roi["width"], roi["height"]), Image.Resampling.LANCZOS)
        original = anchor.crop((roi["x"], roi["y"], roi["x"] + roi["width"], roi["y"] + roi["height"]))
        spatial = Image.new("L", (roi["width"], roi["height"]), 0)
        inset = max(2, min(8, min(roi["width"], roi["height"]) // 10))
        ImageDraw.Draw(spatial).rounded_rectangle(
            (inset, inset, roi["width"] - inset - 1, roi["height"] - inset - 1),
            radius=max(2, inset * 2),
            fill=255,
        )
        spatial = spatial.filter(ImageFilter.GaussianBlur(max(1.0, inset / 2)))
        motion = get_motion(motion_id) or {}
        frame_count = int(motion.get("frames", 9))
        corridor = int(motion.get("neutral_corridor_frames", 2) or 2)
        frames: list[Image.Image] = []
        action_count = frame_count - 2 * corridor
        for index in range(frame_count):
            if index < corridor or index >= frame_count - corridor:
                amount = 0.0
            else:
                t = (index - corridor) / max(1, action_count - 1)
                amount = min(1.0, math.sin(math.pi * t) * (1.35 if motion_id == "smile" else 1.1))
            frame = anchor.copy()
            if amount > 0:
                blended = Image.blend(original, target, amount)
                frame.paste(blended, (roi["x"], roi["y"]), spatial)
            frames.append(frame)
        frames[0] = anchor.copy()
        frames[-1] = anchor.copy()
        report = analyze_frames(
            frames,
            anchor=anchor,
            boundary_width=corridor,
            source={"kind": "w11_face_layer", "motion_id": motion_id, "roi": roi_name},
        )
        if report["status"] == "pass":
            report["status"] = "review"
            report["passed"] = False
        identity_review = {
            "id": "face_identity_manual_review",
            "status": "warning",
            "message": "Review the generated expression tile for eyelid/lip identity before runtime use.",
        }
        report.setdefault("checks", []).append(identity_review)
        report.setdefault("issues", []).append(identity_review)
        report["face_layer"] = {"workflow": "W11", "roi_name": roi_name, "roi": roi, "target": target_path.name}
        source_path = INPUT_DIR / f"{project_id}_{loadout_id}_{motion_id}_face.mp4"
        write_mp4(frames, source_path, int(motion.get("fps", 16)))
        generation_params = {
            **generation_params,
            "neutral_corridor_frames": corridor,
            "channel": "face",
        }
        updated, assets = self.store.finalize_clip(
            project_id,
            motion_id=motion_id,
            source_video_filename=source_path.name,
            source_video_data=source_path.read_bytes(),
            master_spritesheet_filename=f"{motion_id}_face_master.png",
            master_spritesheet_data=_encode_spritesheet(frames),
            runtime_spritesheet_filename=f"{motion_id}_face_runtime.png",
            runtime_spritesheet_data=_encode_spritesheet(frames[:-1]),
            qc_report=report,
            expected_generation_signature=expected_signature,
            generation_params=generation_params,
        )
        self.client.free()
        return {
            "project": updated,
            "asset": assets["source_video"],
            "assets": assets,
            "qc": report,
            "prompt_id": prompt_id,
            "source_output": str(source_path),
        }

    def generate_viseme_atlas(
        self,
        project_id: str,
        *,
        seed: int,
        loadout_id: str,
        expected_signature: str,
        generation_params: dict[str, Any],
        log: LogCallback,
        cancelled: CancelCallback,
        on_prompt_id: PromptIdCallback | None = None,
    ) -> dict[str, Any]:
        """Generate the ten mouth tiles sequentially and attach one review atlas."""

        project = self.store.get_project(project_id)
        anchor = self.store.anchor_for(project, loadout_id)
        if anchor.get("status") != "ready" or not anchor.get("asset_id"):
            raise ValueError("accept the loadout anchor before generating its viseme atlas")
        canvas = anchor.get("canvas") or {}
        width, height = int(canvas.get("width", 0)), int(canvas.get("height", 0))
        if width <= 0 or height <= 0:
            raise ValueError("accepted anchor has no valid canvas contract")
        roi = validate_mouth_roi(anchor.get("mouth_roi"), canvas_width=width, canvas_height=height)
        tile_width = min(256, max(64, ((roi["width"] + 15) // 16) * 16))
        tile_height = min(256, max(64, ((roi["height"] + 15) // 16) * 16))
        anchor_name = _stage_asset(self.store, project_id, anchor["asset_id"], "viseme_anchor")
        prompt_ids: list[str] = []
        tile_paths: dict[str, Path] = {}

        self.client.ensure_online()
        self.client.free()
        log(
            f"W9 viseme atlas: loadout={loadout_id}, ROI="
            f"{roi['x']},{roi['y']} {roi['width']}×{roi['height']}, tile={tile_width}×{tile_height}; "
            "ten Qwen edits will run sequentially for the 12 GB profile."
        )
        for index, viseme in enumerate(STUDIO_VISEMES):
            if cancelled():
                raise RuntimeError("job cancelled")
            workflow = json.loads(W9_PATH.read_text(encoding="utf-8"))
            workflow[_find_one(workflow, "UnetLoaderGGUF")]["inputs"]["unet_name"] = W1_UNET_NAME
            workflow[_find_one(workflow, "LoraLoaderModelOnly")]["inputs"]["lora_name"] = W1_LORA_NAME
            workflow[_find_one(workflow, "CLIPLoaderGGUF")]["inputs"]["clip_name"] = W1_CLIP_NAME
            workflow[_find_one(workflow, "VAELoader")]["inputs"]["vae_name"] = W1_VAE_NAME
            workflow[_find_one(workflow, "LoadImage", "canonical anchor")]["inputs"]["image"] = anchor_name
            crop = workflow[_find_one(workflow, "ImageCrop")]["inputs"]
            crop.update(roi)
            scale = workflow[_find_one(workflow, "ImageScale", "viseme tile")]["inputs"]
            scale.update({"width": tile_width, "height": tile_height})
            positive = workflow[_find_one(workflow, "TextEncodeQwenImageEditPlus", "Target viseme")]["inputs"]
            positive["prompt"] = (
                "Edit only the lips and immediately visible inner mouth into this target viseme: "
                f"{viseme_prompt(viseme)}. Preserve the exact character identity, face geometry, skin, nose, "
                "chin, line art, colors, lighting and crop. Do not move any pixel outside the mouth region. "
                "Produce one clean 2D mouth tile without text or a grid."
            )
            workflow[_find_one(workflow, "KSampler")]["inputs"]["seed"] = seed + index
            prefix = f"character_studio/projects/{project_id}/visemes/{loadout_id}/{viseme}"
            workflow[_find_one(workflow, "SaveImage")]["inputs"]["filename_prefix"] = prefix

            prompt_id = self._enqueue_tracked(workflow, on_prompt_id=on_prompt_id, log=log)
            prompt_ids.append(prompt_id)
            log(f"Queued W9 {index + 1}/{len(STUDIO_VISEMES)} {viseme} as {prompt_id}")
            history = self.client.wait(prompt_id, timeout_s=1200, log=log, cancelled=cancelled)
            outputs = [
                item
                for item in self.client.output_files(history)
                if item.suffix.lower() == ".png" and item.is_file()
            ]
            if not outputs:
                raise RuntimeError(f"W9 produced no PNG tile for {viseme}")
            tile_paths[viseme] = max(outputs, key=lambda item: item.stat().st_mtime)
            self.client.free()

        atlas, manifest = pack_viseme_atlas(
            tile_paths,
            cell_size=(tile_width, tile_height),
            columns=5,
            padding=0,
        )
        manifest.update(
            {
                "loadout_id": loadout_id,
                "anchor_revision": anchor.get("revision"),
                "anchor_asset_id": anchor.get("asset_id"),
                "mouth_roi": roi,
                "review_required": True,
            }
        )
        tiles = {
            viseme: {
                "filename": tile_paths[viseme].name,
                "data": tile_paths[viseme].read_bytes(),
            }
            for viseme in STUDIO_VISEMES
        }
        updated, assets = self.store.finalize_viseme_atlas(
            project_id,
            loadout_id=loadout_id,
            tiles=tiles,
            atlas_filename=f"{loadout_id}_viseme_atlas.png",
            atlas_data=_encode_png(atlas),
            manifest=manifest,
            expected_generation_signature=expected_signature,
            generation_params=generation_params,
        )
        log("W9 atlas saved for manual review; runtime mouth playback remains gated until acceptance.")
        return {
            "project": updated,
            "asset": assets["atlas"],
            "assets": assets,
            "manifest": manifest,
            "prompt_id": prompt_ids[-1],
            "prompt_ids": prompt_ids,
        }

    def export_runtime_clip(
        self,
        project_id: str,
        *,
        motion_id: str,
        loadout_id: str,
        expected_signature: str,
        generation_params: dict[str, Any],
        log: LogCallback,
        cancelled: CancelCallback,
        on_prompt_id: PromptIdCallback | None = None,
    ) -> dict[str, Any]:
        """Run W12 on the lossless QC master and attach a review-only RGBA sheet."""

        project = self.store.get_project(project_id)
        clip = project.get("clips", {}).get(self.store.clip_key(loadout_id, motion_id))
        if not isinstance(clip, dict):
            raise ValueError("motion clip does not exist for the selected loadout")
        if clip.get("status") != "qc_pass" or clip.get("qc", {}).get("status") != "pass":
            raise ValueError("W12 requires a current clip that passed continuity QC")
        master_asset_id = clip.get("master_spritesheet_asset_id") or clip.get("master_asset_id")
        master_frame_count = int(clip.get("master_frame_count", 0) or 0)
        runtime_frame_count = int(clip.get("runtime_frame_count", 0) or 0)
        if not master_asset_id or master_frame_count < 2 or runtime_frame_count != master_frame_count - 1:
            raise ValueError("clip has no valid lossless master/runtime frame contract")
        anchor_contract = self.store.anchor_for(project, loadout_id)
        if (
            anchor_contract.get("status") != "ready"
            or clip.get("anchor_asset_id") != anchor_contract.get("asset_id")
            or clip.get("anchor_revision") != anchor_contract.get("revision")
        ):
            raise ValueError("clip is not bound to the current accepted anchor")
        canvas = anchor_contract.get("canvas") or {}
        width, height = int(canvas.get("width", 0)), int(canvas.get("height", 0))
        if width <= 0 or height <= 0:
            raise ValueError("accepted anchor has no valid canvas contract")
        master_path, _ = self.store.get_asset(project_id, str(master_asset_id))
        master_frames = split_spritesheet(master_path, frame_count=master_frame_count)
        if any(frame.size != (width, height) for frame in master_frames):
            raise ValueError("lossless master canvas does not match the accepted anchor")
        runtime_frames = [frame.convert("RGBA") for frame in master_frames[:-1]]
        staged_name = f"studio_{project_id}_{loadout_id}_{motion_id}_w12_master_ffv1.mkv"
        staged_path = write_lossless_video(
            runtime_frames,
            INPUT_DIR / staged_name,
            fps=int((get_motion(motion_id) or {}).get("fps", 16)),
        )
        workflow = json.loads(W12_PATH.read_text(encoding="utf-8"))
        workflow["1"]["inputs"]["file"] = staged_path.name
        workflow["3"]["inputs"].update({"batch_index": 0, "length": runtime_frame_count})
        workflow["5"]["inputs"]["filename_prefix"] = (
            f"character_studio/projects/{project_id}/runtime/{loadout_id}/{motion_id}"
        )
        self.client.ensure_online()
        self.client.free()
        log(
            f"W12 {motion_id}: {runtime_frame_count} lossless frames; BiRefNet_toonout "
            "processes the batch sequentially and emits color RGBA."
        )
        prompt_id = self._enqueue_tracked(workflow, on_prompt_id=on_prompt_id, log=log)
        history = self.client.wait(prompt_id, timeout_s=1200, log=log, cancelled=cancelled)
        outputs = sorted(
            (
                item
                for item in self.client.output_files(history)
                if item.suffix.lower() == ".png" and item.is_file()
            ),
            key=lambda item: item.name,
        )
        if len(outputs) != runtime_frame_count:
            raise RuntimeError(
                f"W12 produced {len(outputs)} RGBA frames; expected exactly {runtime_frame_count}"
            )
        exported: list[Image.Image] = []
        coverage: list[float] = []
        low_alpha_clamped = 0
        for index, path in enumerate(outputs):
            with Image.open(path) as opened:
                frame = opened.convert("RGBA").copy()
            if frame.size != (width, height):
                raise RuntimeError(
                    f"W12 frame {index} is {frame.width}x{frame.height}; expected {width}x{height}"
                )
            alpha = frame.getchannel("A")
            histogram = alpha.histogram()
            low_alpha_clamped += sum(histogram[1:17])
            # Values below 17 are visually negligible foreground but can leave
            # a faint full-canvas haze.  Make the runtime background exactly
            # transparent while preserving the meaningful antialiased edge.
            alpha = alpha.point(lambda value: 0 if value <= 16 else value)
            frame.putalpha(alpha)
            histogram = alpha.histogram()
            foreground_pixels = sum(histogram[17:])
            ratio = foreground_pixels / float(width * height)
            if ratio < 0.005 or ratio > 0.95:
                raise RuntimeError(
                    f"W12 alpha coverage is unsafe on frame {index}: {ratio:.4f}; review the segmentation model"
                )
            coverage.append(ratio)
            exported.append(frame)
        adjacent_coverage_delta = max(
            (abs(right - left) for left, right in zip(coverage, coverage[1:])),
            default=0.0,
        )
        if adjacent_coverage_delta > 0.25:
            raise RuntimeError(
                "W12 matte coverage changes too abruptly between adjacent frames: "
                f"{adjacent_coverage_delta:.4f}"
            )
        if cancelled():
            raise RuntimeError("job cancelled")
        diagnostics = {
            "schema": "studio.runtime-export.v1",
            "workflow": "W12",
            "model": "BiRefNet_toonout",
            "frame_count": runtime_frame_count,
            "canvas": {"width": width, "height": height},
            "alpha_coverage": {
                "min": min(coverage),
                "max": max(coverage),
                "mean": sum(coverage) / len(coverage),
                "max_adjacent_delta": adjacent_coverage_delta,
                "low_alpha_pixels_clamped": low_alpha_clamped,
            },
            "source": "lossless_qc_master_without_duplicate_anchor",
            "review_required": True,
        }
        sheet_data = _encode_spritesheet(exported)
        updated, asset = self.store.finalize_runtime_export(
            project_id,
            motion_id=motion_id,
            loadout_id=loadout_id,
            filename=f"{motion_id}_runtime_rgba_review.png",
            data=sheet_data,
            frame_count=runtime_frame_count,
            diagnostics=diagnostics,
            expected_generation_signature=expected_signature,
            generation_params=generation_params,
        )
        self.client.free()
        log("W12 RGBA candidate passed structural alpha checks and now requires visual acceptance.")
        return {
            "project": updated,
            "asset": asset,
            "diagnostics": diagnostics,
            "prompt_id": prompt_id,
        }

    def repair_motion(
        self,
        project_id: str,
        *,
        motion_id: str,
        loadout_id: str,
        seed: int,
        expected_signature: str,
        log: LogCallback,
        cancelled: CancelCallback,
        on_prompt_id: PromptIdCallback | None = None,
    ) -> dict[str, Any]:
        """Repair bounded QC defects with W10 and commit only a full QC pass."""

        project = self.store.get_project(project_id)
        if self.store.generation_signature(
            project, "temporal_repair", {"motion_id": motion_id, "loadout_id": loadout_id}
        ) != expected_signature:
            raise RuntimeError("clip changed before temporal repair started")
        clip = project.get("clips", {}).get(self.store.clip_key(loadout_id, motion_id))
        if not isinstance(clip, dict):
            raise ValueError("motion clip does not exist for the selected loadout")
        master_asset_id = clip.get("master_spritesheet_asset_id") or clip.get("master_asset_id")
        report_asset_id = clip.get("qc_report_asset_id") or clip.get("qc", {}).get("report_asset_id")
        if not master_asset_id or not report_asset_id:
            raise ValueError("clip has no lossless master/QC report and cannot be repaired safely")
        anchor_contract = self.store.anchor_for(project, loadout_id)
        if anchor_contract.get("status") != "ready" or not anchor_contract.get("asset_id"):
            raise ValueError("accepted loadout anchor is required for W10 repair")
        master_path, _ = self.store.get_asset(project_id, master_asset_id)
        report_path, _ = self.store.get_asset(project_id, report_asset_id)
        anchor_path, _ = self.store.get_asset(project_id, anchor_contract["asset_id"])
        report = json.loads(report_path.read_text(encoding="utf-8"))
        frame_count = int(clip.get("master_frame_count") or report.get("frame_count") or 0)
        frames = split_spritesheet(master_path, frame_count=frame_count)
        with Image.open(anchor_path) as opened_anchor:
            anchor = opened_anchor.convert("RGBA").copy()
        fps = int((get_motion(motion_id) or {}).get("fps", 16))
        service = RepairService()
        prompt_ids: list[str] = []
        current_frames = frames
        current_report = report
        final_result = None

        self.client.ensure_online()
        for iteration in range(2):
            if cancelled():
                raise RuntimeError("job cancelled")
            run_token = f"{project_id}_{loadout_id}_{motion_id}_{int(time.time())}_{iteration + 1}"
            try:
                prepared = service.prepare(
                    current_frames,
                    anchor,
                    current_report,
                    output_dir=INPUT_DIR,
                    fps=fps,
                    seed=seed + iteration,
                    prefix=run_token,
                    output_prefix=f"character_studio/projects/{project_id}/repair/{run_token}",
                )
            except NoRepairRequired as exc:
                log("W10 planner found no repairable discontinuity; clip was left unchanged.")
                return {"project": project, "action": "none", "plan": exc.plan, "prompt_ids": prompt_ids}
            except RegenerationRequired as exc:
                raise RuntimeError(f"W10 refused unsafe local repair: {exc}") from exc

            workflow = prepared.workflow
            workflow[_find_one(workflow, "UnetLoaderGGUF")]["inputs"]["unet_name"] = W4_UNET_NAME
            workflow[_find_one(workflow, "CLIPLoaderGGUF")]["inputs"]["clip_name"] = W4_CLIP_NAME
            workflow[_find_one(workflow, "VAELoader")]["inputs"]["vae_name"] = W4_VAE_NAME
            workflow[_find_one(workflow, "LoraLoaderModelOnly")]["inputs"]["lora_name"] = W4_LORA_NAME
            self.client.free()
            log(
                f"W10 window {iteration + 1}: {prepared.window['kind']} / "
                f"{prepared.window['length']} frames, lossless FFV1 inputs."
            )
            prompt_id = self._enqueue_tracked(workflow, on_prompt_id=on_prompt_id, log=log)
            prompt_ids.append(prompt_id)
            history = self.client.wait(prompt_id, timeout_s=2400, log=log, cancelled=cancelled)
            outputs = [
                item
                for item in self.client.output_files(history)
                if item.suffix.lower() in {".mp4", ".webm", ".mov"} and item.is_file()
            ]
            if not outputs:
                raise RuntimeError("W10 produced no repaired-window video")
            repaired_path = max(outputs, key=lambda item: item.stat().st_mtime)
            repaired_window, _ = load_video_frames(repaired_path)
            final_result = service.finalize(
                current_frames,
                anchor,
                current_report,
                prepared,
                repaired_window,
                boundary_frames=max(1, int(clip.get("neutral_corridor_frames", 4) or 4)),
            )
            log(
                f"W10 re-QC {final_result.qc['status']}: max adjacent "
                f"{final_result.previous_max_adjacent} → {final_result.repaired_max_adjacent}."
            )
            current_frames = list(final_result.frames)
            current_report = final_result.qc
            if final_result.accepted:
                break
            if not final_result.improved:
                raise RuntimeError("W10 did not improve the discontinuity; regenerate instead of stacking repairs")

        if final_result is None or not final_result.accepted:
            raise RuntimeError("W10 bounded repair did not reach a full QC pass; regenerate the motion")
        if cancelled():
            raise RuntimeError("job cancelled")
        final_result.qc["temporal_repair"] = {
            "workflow": "W10",
            "prompt_ids": prompt_ids,
            "plan": final_result.plan,
            "last_window": final_result.window,
            "improved": final_result.improved,
            "previous_max_adjacent": final_result.previous_max_adjacent,
            "repaired_max_adjacent": final_result.repaired_max_adjacent,
            "root_stabilization": list(final_result.root_stabilization),
        }
        full_video_path = INPUT_DIR / f"{project_id}_{loadout_id}_{motion_id}_w10_repaired.mp4"
        write_mp4(list(final_result.frames), full_video_path, fps)
        motion_params = {
            "motion_id": motion_id,
            "loadout_id": loadout_id,
            "neutral_corridor_frames": int(clip.get("neutral_corridor_frames", 4) or 4),
        }
        current_project = self.store.get_project(project_id)
        motion_signature = self.store.generation_signature(current_project, "motion", motion_params)
        if clip.get("input_signature") and clip.get("input_signature") != motion_signature:
            raise RuntimeError("motion inputs changed; repaired clip was not attached")
        master_data = _encode_spritesheet(list(final_result.frames))
        runtime_data = _encode_spritesheet(list(final_result.frames[:-1]))
        updated, assets = self.store.finalize_clip(
            project_id,
            motion_id=motion_id,
            source_video_filename=full_video_path.name,
            source_video_data=full_video_path.read_bytes(),
            master_spritesheet_filename=f"{motion_id}_w10_qc_master.png",
            master_spritesheet_data=master_data,
            runtime_spritesheet_filename=f"{motion_id}_w10_runtime.png",
            runtime_spritesheet_data=runtime_data,
            qc_report=final_result.qc,
            expected_generation_signature=motion_signature,
            generation_params=motion_params,
        )
        self.client.free()
        return {
            "project": updated,
            "asset": assets["source_video"],
            "assets": assets,
            "qc": final_result.qc,
            "action": "committed",
            "prompt_id": prompt_ids[-1],
            "prompt_ids": prompt_ids,
        }
