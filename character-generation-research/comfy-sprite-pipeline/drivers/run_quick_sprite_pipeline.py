from __future__ import annotations

import argparse
import asyncio
import json
import shutil
import sys
import time
import urllib.request
import uuid
from collections import deque
from dataclasses import replace
from pathlib import Path

from PIL import Image, ImageChops, ImageStat
import cv2
import numpy as np

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from _local_config import (  # noqa: E402
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
)
from drivers import run_w1_pose_edit as w1  # noqa: E402
from drivers import run_w2_video_gen as w2  # noqa: E402
from drivers import run_w3_spritesheet as w3  # noqa: E402
from drivers.pose_presets import get_preset, list_presets  # noqa: E402
from drivers.prompt_defaults import DEFAULT_SHADOW_NEGATIVE, merge_negative_prompts  # noqa: E402
from tools.repair_temporal_defects import repair_video  # noqa: E402
from tools.render_openpose import render_pose  # noqa: E402

# The pushed W1/W2/W3 drivers retain the original author's F:/ComfyUI
# defaults.  Keep those files byte-for-byte compatible with origin/main and
# bind their runtime locations here to this installation.
for _driver in (w1, w2, w3):
    _driver.COMFY_URL = COMFY_URL
    _driver.INPUT_DIR = INPUT_DIR
    _driver.OUTPUT_DIR = OUTPUT_DIR
    _driver.ANIM_ROOT = OUTPUT_DIR / "character_pipeline" / "base_animations"


GLOBAL_REQUIREMENTS = (
    "GLOBAL REQUIREMENTS. This is a production-quality sprite animation. The following rules are mandatory and "
    "override every other instruction. Keep EXACTLY ONE character. Never generate additional people or creatures. "
    "Never remove body parts. Never crop the character. The entire character, including hair, feet, fingers, cape, "
    "weapon, and accessories, must remain fully visible in every frame. The character must remain centered. The "
    "character scale, baseline, and pivot point must NEVER change. Use fixed camera, fixed perspective, fixed framing, "
    "fixed focal length, fixed zoom, fixed distance, fixed lighting, fixed colors, fixed outline thickness, and fixed "
    "proportions. The background is solid pure white (#FFFFFF), with no floor, shadows, environment, props, or "
    "particles unless explicitly requested."
)

CHARACTER_PLACEMENT_REQUIREMENTS = (
    "CHARACTER PLACEMENT. The character occupies approximately 72-75% of the canvas height. Preserve equal top and "
    "bottom margins and equal left and right margins. Never become larger or smaller. Never drift. Never move "
    "vertically or horizontally. Every frame must preserve identical framing. The character must overlap itself "
    "across frames. Do not reposition the character to follow the motion. The animation must happen inside the body, "
    "not through camera movement."
)

CAMERA_LOCK_REQUIREMENTS = (
    "CAMERA LOCK. The virtual camera is physically locked on a tripod. No pan, tilt, roll, orbit, dolly, zoom, "
    "handheld motion, reframing, perspective shift, lens change, focus breathing, camera shake, or stabilization "
    "artifacts."
)

APPEARANCE_REQUIREMENTS = (
    "APPEARANCE LOCK. The weapon is permanently attached to the same hand: it must never disappear, detach, morph, "
    "duplicate, change size, or change orientation unexpectedly. Clothing topology is fixed: no new or removed "
    "folds, color changes, cloth regeneration, costume redesign, or accessory replacement. Background must remain "
    "solid pure white (#FFFFFF): no gradients, vignette, texture, horizon, wall, floor, environmental lighting, "
    "ambient shadows, transparency, or alpha artifacts. Every visible surface remains complete and continuously "
    "filled throughout the sequence. The character silhouette remains closed and continuous. Clothing and hair "
    "preserve identical topology and stable geometry. Thin structures remain connected and continuous. Preserve "
    "all narrow details and connected accessories. Maintain clean, continuous, closed contours."
)

MOTION_REQUIREMENTS = (
    "MOTION CONTINUITY. Every frame must contain visible natural body motion. Use continuous movement throughout. "
    "No dead frames, paused frames, frozen animation, static pose, or motion interruption."
)

SUBTLE_IDLE_MOTION_REQUIREMENTS = (
    "SUBTLE IDLE MOTION. Preserve a calm held pose. The upper torso is the only source of motion. The head translates "
    "with the torso as one rigid connected structure. Hair and cape respond only to that torso movement with minimal "
    "delayed follow-through. The pelvis, root, feet, and body center remain fixed. Use one continuous breathing curve "
    "with smooth easing and strong temporal consistency. Reuse the same character geometry and line art throughout."
)

LOOP_REQUIREMENTS = (
    "LOOP STRUCTURE. Animation starts at key pose A, performs the COMPLETE motion, and returns EXACTLY to key pose A. "
    "The loop closes perfectly. The first and last frames are visually identical in composition, scale, baseline, "
    "pivot, foot placement, and screen position."
)

W1_NEGATIVE = merge_negative_prompts(
    (
    "cropped body, cropped head, cropped feet, cropped hands, cropped weapon, out of frame, duplicate body, "
    "duplicate arms, duplicate legs, duplicate hands, duplicate weapon, duplicate accessories, extra limbs, "
    "extra arms, extra legs, extra hands, extra fingers, missing fingers, missing feet, broken hands, broken feet, "
    "fused arms, merged hands, malformed fingers, bad anatomy, mutated anatomy, warped anatomy, body stretching, "
    "body shrinking, wrong proportions, scale drift, camera drift, camera movement, camera shake, camera orbit, "
    "camera zoom, camera pan, lens distortion, perspective distortion, motion blur, ghosting, double exposure, "
    "black artifacts, alpha holes, transparent holes, background leakage, grey background, environment, floor, "
    "shadow, reflection, particles, floating objects, extra props, watermark, text, logo, compression artifacts, "
    "missing clothing pieces, missing fill, blurry, flicker, jitter, border, picture frame, rectangular frame, "
    "bounding box, crop marks, selection outline, blue rectangle, grid, graph paper, coordinate grid, guide lines"
    ),
    DEFAULT_SHADOW_NEGATIVE,
)


class RectangularFrameError(RuntimeError):
    pass

W2_NEGATIVE = merge_negative_prompts(
    W1_NEGATIVE,
    "frame interpolation artifacts, color shift, size drift, perspective shift, tracking shot, "
    "reframing, sudden zoom, zoom in, close-up framing, body deformation, messy outlines, missing fabric, "
    "black patches, flickering dark spots",
)

IDLE_BREATHING_NEGATIVE = (
    "frame redraw, temporal inconsistency, body deformation, facial morphing, clothing morphing, outline crawl, "
    "jitter, flicker, ghosting, independent head motion, wind-driven hair, wind-driven cape, camera movement, "
    "scale drift, position drift, background flicker, missing regions, incomplete surfaces, interior holes, holes "
    "in clothing, holes in hair, broken silhouette, disconnected geometry, background leakage, white gaps, alpha "
    "holes, unfinished rendering, partial rendering, broken thin parts, simplified geometry, collapsed edges, "
    "disconnected accessories, floating fragments, detached parts, disconnected outlines, open contours"
)


def _post_json(path: str, body: dict) -> dict:
    req = urllib.request.Request(
        f"{COMFY_URL}{path}",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    return json.loads(urllib.request.urlopen(req, timeout=30).read().decode() or "{}")


_COMFY_CLIENT_ID = uuid.uuid4().hex


def _post_prompt(workflow: dict) -> str:
    response = _post_json("/prompt", {"prompt": workflow, "client_id": _COMFY_CLIENT_ID})
    prompt_id = str(response.get("prompt_id", ""))
    if not prompt_id:
        raise RuntimeError(f"ComfyUI rejected workflow: {response}")
    return prompt_id


async def _stream_comfy_progress(prompt_id: str, stage: str) -> None:
    import aiohttp

    ws_base = COMFY_URL.replace("http://", "ws://").replace("https://", "wss://")
    async with aiohttp.ClientSession() as session:
        async with session.ws_connect(f"{ws_base}/ws?clientId={_COMFY_CLIENT_ID}", heartbeat=20) as socket:
            while True:
                message = await socket.receive(timeout=1800)
                if message.type != aiohttp.WSMsgType.TEXT:
                    if message.type in {aiohttp.WSMsgType.CLOSED, aiohttp.WSMsgType.ERROR}:
                        return
                    continue
                event = json.loads(message.data)
                event_type = event.get("type")
                data = event.get("data") or {}
                if event_type == "progress" and str(data.get("prompt_id", prompt_id)) == prompt_id:
                    value = int(data.get("value", 0) or 0)
                    maximum = max(1, int(data.get("max", 1) or 1))
                    print("PROGRESS_JSON:", json.dumps({
                        "stage": stage,
                        "value": value,
                        "max": maximum,
                        "percent": round(value * 100 / maximum, 2),
                    }), flush=True)
                elif event_type == "executing" and str(data.get("prompt_id", "")) == prompt_id and data.get("node") is None:
                    return
                elif event_type == "execution_error" and str(data.get("prompt_id", "")) == prompt_id:
                    return


def _wait_with_progress(prompt_id: str, stage: str, fallback) -> dict:
    try:
        asyncio.run(_stream_comfy_progress(prompt_id, stage))
    except Exception as exc:
        print(f"[PIPE/{stage.upper()}] live progress unavailable: {exc}", flush=True)
    return fallback(prompt_id)


def _ensure_comfy() -> None:
    try:
        urllib.request.urlopen(f"{COMFY_URL}/system_stats", timeout=15).read()
    except Exception as exc:
        raise RuntimeError(f"ComfyUI is not reachable on {COMFY_URL}: {exc}") from exc


def _free_memory(label: str) -> None:
    try:
        _post_json("/free", {"unload_models": True, "free_memory": True})
        print(f"[PIPE] {label}: /free OK")
    except Exception as exc:
        print(f"[PIPE] {label}: /free skipped ({exc})")


def _render_pose_png(preset_slug: str, keypoints_2d: list[int]) -> tuple[Path, Path]:
    canvas_w = 512
    canvas_h = 512
    pose_json_path = INPUT_DIR / f"pose_{preset_slug}.json"
    pose_png_path = INPUT_DIR / f"pose_{preset_slug}.png"
    payload = {
        "canvas_width": canvas_w,
        "canvas_height": canvas_h,
        "people": [{"pose_keypoints_2d": keypoints_2d}],
    }
    pose_json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    triples = [tuple(keypoints_2d[i:i + 3]) for i in range(0, len(keypoints_2d), 3)]
    keypoints = [None if c <= 0 else (float(x), float(y), float(c)) for x, y, c in triples]
    render_pose(keypoints, canvas_w, canvas_h).save(pose_png_path)
    return pose_json_path, pose_png_path


def _stage_source_image(source: Path, animation_base: str) -> str:
    staged = INPUT_DIR / f"source_{animation_base}{source.suffix.lower()}"
    shutil.copy2(source, staged)
    return staged.name


def _rotate_spritesheet_to_softest_seam(path: Path, cell_size: int) -> Path:
    image = Image.open(path).convert("RGBA")
    frame_count = image.width // cell_size
    if frame_count < 3:
        return path

    frames = [
        image.crop((i * cell_size, 0, (i + 1) * cell_size, image.height))
        for i in range(frame_count)
    ]
    diffs: list[tuple[int, float]] = []
    for i in range(frame_count):
        current = frames[i]
        nxt = frames[(i + 1) % frame_count]
        delta = ImageChops.difference(current, nxt).convert("L")
        score = ImageStat.Stat(delta).mean[0]
        diffs.append((i, score))

    best_idx, best_score = min(diffs, key=lambda item: item[1])
    cut = (best_idx + 1) % frame_count
    if cut == 0:
        return path

    rotated = Image.new("RGBA", image.size)
    for out_idx in range(frame_count):
        src_idx = (cut + out_idx) % frame_count
        rotated.paste(frames[src_idx], (out_idx * cell_size, 0))
    rotated.save(path)
    print(f"[PIPE/W3] rotated spritesheet seam -> start frame {cut + 1} (best diff={best_score:.3f})")
    return path


def _replace_alpha_with_border_white_key(path: Path, cell_size: int) -> Path:
    """Combine segmentation with a conservative white-background key.

    The segmentation alpha removes shadows and other neutral background junk.
    Any pixel that is observably different from the white canvas can restore
    thin props and light/neutral character details that segmentation missed.
    Border-connected white canvas always remains transparent.
    """
    sheet = Image.open(path).convert("RGBA")
    frame_count = sheet.width // cell_size
    result = Image.new("RGBA", sheet.size)

    for frame_idx in range(frame_count):
        frame = sheet.crop((frame_idx * cell_size, 0, (frame_idx + 1) * cell_size, sheet.height))
        rgb = frame.convert("RGB")
        segmented_alpha = frame.getchannel("A")
        pixels = rgb.load()
        segmented_pixels = segmented_alpha.load()
        width, height = rgb.size

        def is_background_candidate(x: int, y: int) -> bool:
            r, g, b = pixels[x, y]
            return min(r, g, b) >= 225 and max(r, g, b) - min(r, g, b) <= 24

        background = bytearray(width * height)
        queue: deque[tuple[int, int]] = deque()

        def enqueue(x: int, y: int) -> None:
            idx = y * width + x
            if not background[idx] and is_background_candidate(x, y):
                background[idx] = 1
                queue.append((x, y))

        for x in range(width):
            enqueue(x, 0)
            enqueue(x, height - 1)
        for y in range(height):
            enqueue(0, y)
            enqueue(width - 1, y)

        while queue:
            x, y = queue.popleft()
            if x > 0:
                enqueue(x - 1, y)
            if x + 1 < width:
                enqueue(x + 1, y)
            if y > 0:
                enqueue(x, y - 1)
            if y + 1 < height:
                enqueue(x, y + 1)

        alpha = Image.new("L", (width, height), 0)
        alpha_pixels = alpha.load()
        for idx, is_background in enumerate(background):
            x, y = idx % width, idx // width
            if is_background:
                continue
            # Trust BiRefNet for the main silhouette. Restore only pixels that
            # differ from the white canvas.  The previous chroma/darkness test
            # discarded low-saturation light surfaces (white clothes, sclera,
            # highlights) whenever BiRefNet missed them.  Pure-white enclosed
            # regions still require BiRefNet support, preserving real gaps
            # between limbs, hair, capes, and weapons.
            if segmented_pixels[x, y] > 24:
                alpha_pixels[x, y] = segmented_pixels[x, y]
            elif not is_background_candidate(x, y):
                alpha_pixels[x, y] = 255

        # Remove generated floor/shadow plates that BiRefNet sometimes joins
        # to the feet. They are large, flat, low-saturation components near
        # the bottom; narrow props and normal costume details cannot match.
        neutral_seen = bytearray(width * height)
        lower_start = int(height * 0.55)

        def is_neutral_floor_candidate(x: int, y: int) -> bool:
            if y < lower_start or alpha_pixels[x, y] == 0:
                return False
            r, g, b = pixels[x, y]
            return 110 <= min(r, g, b) and max(r, g, b) <= 235 and max(r, g, b) - min(r, g, b) <= 14

        for start_y in range(lower_start, height):
            for start_x in range(width):
                start_idx = start_y * width + start_x
                if neutral_seen[start_idx] or not is_neutral_floor_candidate(start_x, start_y):
                    continue
                neutral_seen[start_idx] = 1
                component = [(start_x, start_y)]
                component_queue: deque[tuple[int, int]] = deque([(start_x, start_y)])
                min_x = max_x = start_x
                min_y = max_y = start_y
                while component_queue:
                    x, y = component_queue.popleft()
                    for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                        if nx < 0 or nx >= width or ny < lower_start or ny >= height:
                            continue
                        idx = ny * width + nx
                        if neutral_seen[idx] or not is_neutral_floor_candidate(nx, ny):
                            continue
                        neutral_seen[idx] = 1
                        component_queue.append((nx, ny))
                        component.append((nx, ny))
                        min_x, max_x = min(min_x, nx), max(max_x, nx)
                        min_y, max_y = min(min_y, ny), max(max_y, ny)

                component_width = max_x - min_x + 1
                component_height = max_y - min_y + 1
                is_floor_plate = (
                    component_width >= width * 0.25
                    and component_width >= component_height * 2.5
                    and len(component) >= width * height * 0.01
                )
                if is_floor_plate:
                    for x, y in component:
                        alpha_pixels[x, y] = 0

        # BiRefNet predicts alpha for an image that was rendered over white.
        # Keeping those white-matted RGB values under a fractional alpha makes
        # a pale fringe on dark backgrounds.  Reverse the white compositing for
        # edge pixels without changing the mask geometry.
        rgba = rgb.convert("RGBA")
        rgba_pixels = rgba.load()
        for y in range(height):
            for x in range(width):
                a_u8 = alpha_pixels[x, y]
                if not 0 < a_u8 < 255:
                    continue
                a = a_u8 / 255.0
                r, g, b = rgba_pixels[x, y][:3]
                rgba_pixels[x, y] = (
                    max(0, min(255, round((r - 255 * (1.0 - a)) / a))),
                    max(0, min(255, round((g - 255 * (1.0 - a)) / a))),
                    max(0, min(255, round((b - 255 * (1.0 - a)) / a))),
                    255,
                )
        rgba.putalpha(alpha)
        result.paste(rgba, (frame_idx * cell_size, 0))

    result.save(path)
    print("[PIPE/W3] fused border-connected white key and removed white edge matte")
    return path


def _normalize_keyframe_placement(
    path: Path,
    target_height_ratio: float = 0.74,
    target_bottom_ratio: float = 0.92,
) -> Path:
    """Give every W1 result the same scale, horizontal center, and baseline.

    Prompting does not reliably lock framing: equivalent poses have varied
    from roughly 69% to 84% of canvas height.  W2 inherits that error.  Since
    W1 uses a clean white canvas, normalize its generated foreground before it
    becomes the video keyframe.
    """
    image = Image.open(path).convert("RGB")
    width, height = image.size
    foreground = Image.new("L", image.size, 0)
    source_pixels = image.load()
    mask_pixels = foreground.load()
    for y in range(height):
        for x in range(width):
            r, g, b = source_pixels[x, y]
            if min(r, g, b) < 242:
                mask_pixels[x, y] = 255

    bbox = foreground.getbbox()
    if bbox is None:
        raise RuntimeError(f"W1 keyframe has no visible foreground: {path}")
    left, top, right, bottom = bbox
    source_w = right - left
    source_h = bottom - top
    target_h = round(height * target_height_ratio)
    # Height defines character scale; width cap only prevents a wide weapon or
    # raised arm from being clipped by the canvas.
    scale = min(target_h / source_h, (width * 0.92) / source_w)
    resized_w = max(1, round(source_w * scale))
    resized_h = max(1, round(source_h * scale))
    character = image.crop(bbox).resize((resized_w, resized_h), Image.Resampling.LANCZOS)

    target_bottom = round(height * target_bottom_ratio)
    paste_x = (width - resized_w) // 2
    paste_y = target_bottom - resized_h
    normalized = Image.new("RGB", image.size, "white")
    normalized.paste(character, (paste_x, paste_y))
    normalized.save(path)
    print(
        f"[PIPE/W1] normalized framing: {source_w}x{source_h} -> "
        f"{resized_w}x{resized_h}, baseline={target_bottom}px"
    )
    return path


def _has_blue_rectangular_frame(path: Path) -> bool:
    pixels = np.asarray(Image.open(path).convert("RGB"))
    red, green, blue = pixels[..., 0], pixels[..., 1], pixels[..., 2]
    mask = (blue > 145) & (blue > red * 1.35) & (blue > green * 1.12)
    rows = np.flatnonzero(mask.mean(axis=1) > 0.28)
    columns = np.flatnonzero(mask.mean(axis=0) > 0.28)
    return bool(
        len(rows) >= 2
        and len(columns) >= 2
        and rows[-1] - rows[0] > pixels.shape[0] * 0.35
        and columns[-1] - columns[0] > pixels.shape[1] * 0.35
    )


def _has_background_grid(path: Path) -> bool:
    pixels = np.asarray(Image.open(path).convert("RGB"))
    channel_spread = pixels.max(axis=2) - pixels.min(axis=2)
    brightness = pixels.mean(axis=2)
    grey_lines = (channel_spread < 16) & (brightness > 145) & (brightness < 245)
    long_rows = np.flatnonzero(grey_lines.mean(axis=1) > 0.48)
    long_columns = np.flatnonzero(grey_lines.mean(axis=0) > 0.48)
    return bool(len(long_rows) >= 4 and len(long_columns) >= 4)


def _has_detached_text_or_watermark(path: Path) -> bool:
    """Reject sizeable foreground islands outside the character silhouette."""
    pixels = np.asarray(Image.open(path).convert("RGB"))
    mask = np.any(pixels < 242, axis=2).astype(np.uint8)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((2, 2), np.uint8))
    count, _labels, stats, _centroids = cv2.connectedComponentsWithStats(mask, 8)
    if count <= 2:
        return False
    areas = stats[1:, cv2.CC_STAT_AREA]
    main_id = int(np.argmax(areas)) + 1
    height, width = mask.shape
    for component_id in range(1, count):
        if component_id == main_id:
            continue
        x, y, component_width, component_height, area = map(int, stats[component_id])
        in_outer_band = y + component_height < height * 0.28 or y > height * 0.82
        watermark_line = component_width > width * 0.35 and component_height < height * 0.08
        if (in_outer_band and area >= 90) or (watermark_line and area >= 150):
            return True
    return False


def _run_w1(
    animation_base: str,
    source_image_name: str,
    pose_png_name: str,
    pose_description: str,
    controlnet_strength: float,
    edit_denoise: float,
    seed: int,
    extra_prompt: str,
    facial_expression: str | None,
    negative_prompt: str = "",
    positive_override: str = "",
) -> tuple[str, list[Path]]:
    w1.ANIMATION_NAME_BASE = animation_base
    w1.SOURCE_IMAGE = source_image_name
    w1.POSE_SKELETON = pose_png_name
    w1.SEED = seed
    w1.CONTROLNET_STRENGTH = controlnet_strength
    w1.DENOISE = edit_denoise
    w1.IMAGE_SIZE = 512
    positive, negative = _w1_prompts(
        pose_description, extra_prompt, facial_expression, negative_prompt, positive_override
    )
    w1.POS_PROMPT = positive
    w1.NEG_PROMPT = negative

    animation_name = w1.resolve_next_animation_name(animation_base)
    (w1.ANIM_ROOT / animation_name / "poses").mkdir(parents=True, exist_ok=True)
    print(f"[PIPE/W1] {animation_name} | src={source_image_name} | pose={pose_png_name} | seed={seed}")
    workflow = w1.build_workflow(animation_name)
    for node in workflow.values():
        class_type = node.get("class_type")
        inputs = node.get("inputs", {})
        if class_type == "UnetLoaderGGUF":
            inputs["unet_name"] = W1_UNET_NAME
        elif class_type == "CLIPLoaderGGUF":
            inputs["clip_name"] = W1_CLIP_NAME
        elif class_type == "VAELoader":
            inputs["vae_name"] = W1_VAE_NAME
        elif class_type == "LoraLoaderModelOnly":
            inputs["lora_name"] = W1_LORA_NAME
        elif class_type in {"ControlNetLoader", "ControlNetLoaderAdvanced"}:
            inputs["control_net_name"] = W1_CONTROLNET_NAME
    pid = _post_prompt(workflow)
    print(f"  enqueued: {pid}")
    history = _wait_with_progress(pid, "w1", w1.wait_for)
    saved = w1.output_files(history)
    if not saved:
        raise RuntimeError("W1 produced no output")
    saved = [_normalize_keyframe_placement(path) for path in saved]
    if any(
        _has_blue_rectangular_frame(path)
        or _has_background_grid(path)
        or _has_detached_text_or_watermark(path)
        for path in saved
    ):
        raise RectangularFrameError("W1 generated a frame, grid, text, or watermark artifact")
    return animation_name, saved


def _w1_prompts(
    pose_description: str,
    extra_prompt: str = "",
    facial_expression: str | None = None,
    negative_prompt: str = "",
    positive_override: str = "",
) -> tuple[str, str]:
    """Return the exact effective prompts sent to W1."""
    prompt_tail = f" Additional action/style direction: {extra_prompt}." if extra_prompt else ""
    edit_scope = "Edit only the body pose and the requested facial expression" if facial_expression else "Edit only the body pose"
    identity_lock = (
        "Preserve the character's facial identity, facial proportions, eye design, and all facial details while "
        "changing only the expression. "
        if facial_expression
        else "Preserve the identical face and eyes. "
    )
    expression_text = f" FACIAL EXPRESSION REQUIREMENT: {facial_expression}." if facial_expression else ""
    positive = (
        f"{GLOBAL_REQUIREMENTS} {CHARACTER_PLACEMENT_REQUIREMENTS} {CAMERA_LOCK_REQUIREMENTS} "
        f"{APPEARANCE_REQUIREMENTS} "
        f"POSE EDIT. {edit_scope} of the character from the reference image. Copy every other visual detail from the "
        f"reference without adding, removing, replacing, or redesigning anything. {identity_lock}Preserve the identical "
        "hair, outfit, every held object, accessories, colors, outlines, and character identity. Every held "
        "object must remain fully visible and connected to the same hand after the pose change. Pose the character in "
        f"{pose_description}. Keep the full body visible, feet visible, clean line art, flat colors, "
        "consistent lighting, pure white background, and absolutely no floor, no ground, and no shadows. "
        "Do not draw any border, frame, bounding box, rectangle, crop guide, selection outline, or colored line "
        "around the character. Do not draw a grid, graph paper, coordinate plane, ruler, guide lines, or pose editor."
        f"{expression_text}"
        f"{prompt_tail}"
    )
    negative = merge_negative_prompts(W1_NEGATIVE, negative_prompt)
    return positive_override or positive, negative


def _run_w2(
    animation_base: str,
    preset_slug: str,
    motion_prompt: str,
    num_frames: int,
    fps: int,
    seed: int,
    extra_prompt: str,
    subtle_idle_motion: bool,
    negative_prompt: str = "",
    positive_override: str = "",
    locked_idle_prompts: bool = False,
) -> list[Path]:
    w2.ANIMATION_NAME_BASE = animation_base
    w2.SEED = seed
    w2.NUM_FRAMES = num_frames
    w2.FPS = fps
    w2.IMAGE_SIZE = 512
    prompt_tail = f" Additional action/style direction: {extra_prompt}." if extra_prompt else ""
    motion_requirements = SUBTLE_IDLE_MOTION_REQUIREMENTS if subtle_idle_motion else MOTION_REQUIREMENTS
    if preset_slug in {"jump_start", "jump_up"}:
        structure_requirements = (
            "Keep exactly one complete full-body character inside the 512x512 canvas. Keep camera, focal length, "
            "framing, character scale and horizontal position fixed. Vertical BODY motion is required and must be "
            "created by articulated hip, knee and ankle extension, never by camera movement or rigid whole-image "
            "translation. The feet begin on a fixed baseline and may rise only after the legs visibly straighten. "
            "This is a one-way jump phase, not a loop; do not return to its first pose."
        )
        loop_requirements = ""
    else:
        structure_requirements = (
            f"{GLOBAL_REQUIREMENTS} {CHARACTER_PLACEMENT_REQUIREMENTS} {CAMERA_LOCK_REQUIREMENTS}"
        )
        loop_requirements = LOOP_REQUIREMENTS
    w2.POS_PROMPT = (
        f"{structure_requirements} {APPEARANCE_REQUIREMENTS} {motion_requirements} {loop_requirements} "
        "ANIMATION. The same chibi cartoon character from the reference image; preserve the same face, hair, outfit, "
        "weapon, accessories, colors, and character identity. "
        f"{motion_prompt}. Stable costume details across every frame, stable silhouette, solid filled clothing "
        "areas, no transparent gaps, no missing fabric, no background bleed. Clean line art, flat colors, "
        "consistent lighting, pure white background."
        f"{prompt_tail}"
    )
    w2.NEG_PROMPT = merge_negative_prompts(
        IDLE_BREATHING_NEGATIVE if subtle_idle_motion else W2_NEGATIVE,
        DEFAULT_SHADOW_NEGATIVE,
        negative_prompt,
    )
    if positive_override:
        w2.POS_PROMPT = positive_override
    if locked_idle_prompts:
        locked_text = (Path(__file__).parent / "prompts" / "idle_breathing_locked.txt").read_text(encoding="utf-8")
        positive_text, negative_text = locked_text.split("Негативный промт", 1)
        default_positive = positive_text.removeprefix("Позитивный промт").strip()
        default_negative = negative_text.strip()
        # Idle keeps its self-contained default bans. UI values may add bans,
        # but cannot remove the global no-shadow requirement.
        w2.POS_PROMPT = positive_override or default_positive
        w2.NEG_PROMPT = merge_negative_prompts(default_negative, negative_prompt)

    print("PROMPT_JSON:", json.dumps({
        "stage": "w2",
        "positive": w2.POS_PROMPT,
        "negative": w2.NEG_PROMPT,
    }, ensure_ascii=False), flush=True)

    animation_name = w2.resolve_latest_animation_name(animation_base)
    src_keyframe = w2.latest_posed_keyframe(animation_name)
    staged_name = f"keyframe_{animation_name}.png"
    shutil.copy2(src_keyframe, INPUT_DIR / staged_name)
    print(f"[PIPE/W2] {animation_name} | keyframe={src_keyframe.name} | seed={seed} | frames={num_frames} | fps={fps}")
    workflow = w2.build_workflow(animation_name, staged_name)
    unet_nodes = [
        node for node in workflow.values()
        if node.get("class_type") == "UnetLoaderGGUF"
    ]
    for node in unet_nodes:
        title = str(node.get("_meta", {}).get("title", "")).lower()
        node["inputs"]["unet_name"] = W2_HIGH_UNET_NAME if "high" in title else W2_LOW_UNET_NAME
    for node in workflow.values():
        class_type = node.get("class_type")
        if class_type == "CLIPLoaderGGUF":
            node["inputs"]["clip_name"] = W2_CLIP_NAME
        elif class_type == "VAELoader":
            node["inputs"]["vae_name"] = W2_VAE_NAME
    pid = _post_prompt(workflow)
    print(f"  enqueued: {pid}")
    history = _wait_with_progress(pid, "w2", w2.wait_for)
    saved = w2.output_files(history)
    if not saved:
        raise RuntimeError("W2 produced no output")
    return saved


def _run_w3(
    animation_base: str,
    num_frames: int,
    cell_size: int,
    source_video: Path,
) -> list[Path]:
    w3.ANIMATION_NAME_BASE = animation_base
    w3.NUM_FRAMES = num_frames
    w3.CELL_SIZE = cell_size
    w3.RMBG_MODEL = "BiRefNet_toonout"
    w3.GREYSCALE = _RUN_GREYSCALE

    animation_name = w3.resolve_latest_animation_name(animation_base)
    staged = INPUT_DIR / f"video_{animation_name}.mp4"
    shutil.copy2(source_video, staged)
    print(f"[PIPE/W3] {animation_name} | video={source_video.name} | color spritesheet")
    workflow = w3.build_workflow(animation_name, staged.name)
    if not _RUN_GREYSCALE:
        # The pushed W3 graph routes luma through nodes 26-28 for tintable
        # monochrome sprites. Public Web Components need the source RGB.
        workflow["25"]["inputs"]["image"] = ["20", 0]
        workflow["25"].setdefault("_meta", {})["title"] = "RGBA (source colour + character mask)"
    pid = _post_prompt(workflow)
    print(f"  enqueued: {pid}")
    history = _wait_with_progress(pid, "w3", w3.wait_for)
    saved = w3.output_files(history)
    if not saved:
        raise RuntimeError("W3 produced no output")
    return saved


def _repair_idle_video(animation_name: str, w2_saved: list[Path]) -> Path:
    videos = [path for path in w2_saved if path.suffix.lower() == ".mp4"]
    if not videos:
        raise RuntimeError("W2 produced no mp4 for temporal repair")
    source = videos[-1]
    output = source.parent / f"{animation_name}_repaired.mp4"
    report = source.parent / f"{animation_name}_repair.json"
    print(f"[PIPE/REPAIR] flow + topology validation | source={source.name}")
    repaired_area = repair_video(source, output, report)
    if repaired_area == 0:
        print("[PIPE/REPAIR] no validated defects; using original without re-encoding")
        print(f"[PIPE/REPAIR] report -> {report.name}")
        return source
    print(f"[PIPE/REPAIR] repaired {repaired_area} px -> {output.name}")
    print(f"[PIPE/REPAIR] report -> {report.name}")
    return output


def _camera_scale_drift(video: Path) -> float:
    """Measure camera-like foreground scale drift without modifying frames."""
    capture = cv2.VideoCapture(str(video))
    sizes: list[tuple[int, int]] = []
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        # MP4 encoding leaves isolated near-white pixels at canvas edges. A
        # raw min/max bbox treats one such pixel as character content and can
        # jump between the real silhouette and 512x512. Remove tiny noise and
        # retain only meaningful connected foreground regions.
        mask = np.any(frame < 242, axis=2).astype(np.uint8)
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        component_count, labels, stats, _ = cv2.connectedComponentsWithStats(mask, 8)
        meaningful = [
            component_id
            for component_id in range(1, component_count)
            if int(stats[component_id, cv2.CC_STAT_AREA]) >= 100
        ]
        if not meaningful:
            continue
        ys, xs = np.where(np.isin(labels, meaningful))
        if len(xs):
            sizes.append((int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)))
    capture.release()
    if len(sizes) < 2:
        return 1.0
    ref_w, ref_h = sizes[0]
    return max(
        max(abs(width / max(1, ref_w) - 1.0), abs(height / max(1, ref_h) - 1.0))
        for width, height in sizes[1:]
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run a one-click W1+W2+W3 pipeline with a preset pose.")
    parser.add_argument("--source", type=Path, help="Path to the source character image.")
    parser.add_argument("--preset", default="idle_breathing", help="Preset slug. Use --list-presets to inspect.")
    parser.add_argument("--name", help="Optional animation base name. Defaults to the preset slug.")
    parser.add_argument("--seed-w1", type=int, default=30123)
    parser.add_argument("--seed-w2", type=int, default=92003)
    parser.add_argument("--cell-size", type=int, default=128)
    parser.add_argument("--frames", type=int, help="Output frame count (8..80, divisible by 4).")
    parser.add_argument("--extra-prompt", default="", help="Optional action/style hint appended to the preset prompts.")
    parser.add_argument("--negative-prompt", default="", help="Optional negative hint appended to W1/W2.")
    parser.add_argument("--positive-override", default="", help="Complete positive prompt replacement for rerenders.")
    parser.add_argument("--start-step", choices=("w1", "w2", "w3"), default="w1")
    parser.add_argument("--greyscale", action="store_true")
    parser.add_argument("--list-presets", action="store_true")
    return parser.parse_args()


_RUN_GREYSCALE = False


def main() -> int:
    args = parse_args()
    if args.list_presets:
        for preset in list_presets():
            loop_note = f"  render={preset.num_frames:2d}" if preset.output_frames != preset.num_frames else ""
            print(f"{preset.slug:16}  frames={preset.output_frames:2d}  fps={preset.fps:2d}{loop_note}  {preset.label}")
        return 0

    if args.source is None:
        raise RuntimeError("--source is required unless --list-presets is used")
    if not args.source.exists():
        raise RuntimeError(f"Source image not found: {args.source}")

    global _RUN_GREYSCALE
    _RUN_GREYSCALE = args.greyscale

    preset = get_preset(args.preset)
    if args.frames is not None:
        if not 8 <= args.frames <= 80 or args.frames % 4:
            raise RuntimeError("--frames must be between 8 and 80 and divisible by 4")
        # WAN renders 4n+1 frames; W3 omits the duplicated closing frame.
        preset = replace(preset, num_frames=args.frames + 1, sprite_frames=args.frames)
    animation_base = args.name or preset.slug
    extra_prompt = args.extra_prompt.strip()
    directional_negative = ""
    if preset.slug in {"walk_right", "walk_left", "run_right", "run_left"}:
        wrong_direction = "screen-right, facing screen-right, rightward" if preset.slug in {"walk_left", "run_left"} else "screen-left, facing screen-left, leftward"
        forbidden_view = "strict full profile, exact 90-degree profile"
        directional_negative = (
            f"front-facing, frontal view, {forbidden_view}, facing viewer, walking toward camera, "
            f"walking {wrong_direction} motion, perspective foreshortening, swapped equipment hand, mirrored character"
        )
    effective_negative = ", ".join(filter(None, [args.negative_prompt.strip(), directional_negative]))
    if preset.slug == "jump_up":
        effective_negative = ", ".join(filter(None, [
            effective_negative,
            "cast shadow, oval shadow, contact shadow, drop shadow, ground marker, floor ellipse, platform, ground, "
            "grass, soil, dirt, terrain, tile, game level, scenery, flowers, rocks, pedestal, base",
        ]))
    effective_positive_override = args.positive_override.strip()
    if preset.slug == "walk_right" and not effective_positive_override:
        effective_positive_override = (
            "Rotate the single character exactly 90 degrees into a strict full right-facing side-profile turnaround "
            "view. This is a character rotation edit, not a front-view pose edit. The nose, chin, chest, knees, feet, "
            "and toes point toward the RIGHT EDGE of the canvas. Only one eye is visible. The shoulders and hips "
            "overlap in side view. Use a readable right-facing walk contact pose with the character's anatomical "
            "RIGHT LEG clearly extended forward toward the right edge and the LEFT LEG clearly trailing behind. "
            "Preserve the same character identity, hairstyle, existing costume, existing held equipment, colors, line "
            "art, and proportions. Keep exactly one complete full-body character centered at constant scale on a "
            "solid pure white background. No text, border, floor, or shadow. Never show a frontal, three-quarter, "
            "left-facing, or toward-camera view."
        )
    elif preset.slug == "walk_left" and not effective_positive_override:
        effective_positive_override = (
            "Create a left-facing side view with the head and torso turned only slightly toward the camera, about "
            "70 to 80 degrees away from frontal. This must read unmistakably as walking toward screen-left, while "
            "remaining more readable than a strict 90-degree profile. This is a new character rotation edit, never "
            "a horizontal mirror. The nose, chin, chest, knees, "
            "feet, and toes point toward the LEFT EDGE of the canvas, while the face and costume remain readable. Use a "
            "left-facing walk contact pose with one leg forward and the other back. Preserve every existing held object in the exact "
            "same anatomical hand as in the source reference, with the same grip and equipment design. Preserve "
            "identity, hairstyle, costume, cape, colors, line art, and proportions. Keep exactly one complete "
            "full-body character centered at constant scale on pure white. No text, border, floor, or shadow. "
            "Never show a frontal, strict 90-degree profile, right-facing, mirrored, or toward-camera view."
        )
    elif preset.slug == "run_right" and not effective_positive_override:
        effective_positive_override = (
            "Rotate the same single character into a clear right-facing three-quarter side view and create a dynamic "
            "running contact pose: torso leaning forward, right knee driving toward the RIGHT EDGE, left leg extended "
            "behind and arms counterbalancing naturally. Preserve identity, clothing, proportions and every object "
            "that actually exists in the source. Keep held equipment in the same anatomical hand and preserve physical "
            "layer order. Keep the complete full body inside the canvas at constant scale on pure white. No text, "
            "border, floor or shadow. Never show frontal, left-facing, mirrored or toward-camera movement."
        )
    elif preset.slug == "run_left" and not effective_positive_override:
        effective_positive_override = (
            "Rotate the same single character into a clear left-facing three-quarter side view and create a dynamic "
            "running contact pose: torso leaning forward, left knee driving toward the LEFT EDGE, right leg extended "
            "behind and arms counterbalancing naturally. Preserve identity, clothing, proportions and every object "
            "that actually exists in the source. Keep held equipment in the same anatomical hand and preserve physical "
            "layer order. Keep the complete full body inside the canvas at constant scale on pure white. No text, "
            "border, floor or shadow. Never show frontal, right-facing, mirrored or toward-camera movement."
        )
    elif preset.slug == "jump_start" and not effective_positive_override:
        effective_positive_override = (
            "Pose the same single character in an unmistakable DEEP CROUCH immediately before a vertical jump. "
            "Lower the pelvis close to the heels, bend BOTH knees sharply, compress the torso forward and keep BOTH "
            "feet planted on the same baseline. The character is grounded and visibly storing upward force; this is "
            "not a neutral standing pose and not an airborne pose. Arms naturally brace for the upward push. "
            "Preserve identity, proportions, clothing and every source-existing object with correct attachment and "
            "layer order. Keep the complete full body centered at constant scale on pure white. No text, border, "
            "floor or shadow. Do not show floating, an airborne apex, falling, landing or camera movement."
        )
    elif preset.slug == "jump_up" and not effective_positive_override:
        effective_positive_override = (
            "Pose the same single character in a SHALLOW CROUCH immediately before a vertical jump. "
            "jump. Lower the pelvis slightly, bend BOTH knees clearly and keep BOTH feet planted on the same baseline. "
            "This is a small anticipation pose, less compressed than a deep crouch, and not an airborne pose. "
            "Preserve identity, proportions, clothing, every source-existing object, attachment point and physical "
            "layer order. Keep the whole silhouette centered at the same scale on pure white. No text, border, floor "
            "or shadow. The canvas contains ONLY the character and pure white pixels. Do not draw grass, soil, dirt, "
            "terrain, a game tile, platform, floor, pedestal, base, flowers, rocks, oval, cast shadow, contact shadow "
            "or ground marker anywhere. No floating, fall, landing, rigid cutout translation or camera movement."
        )
    _ensure_comfy()

    started = time.time()
    source_image_name = _stage_source_image(args.source, animation_base)
    pose_json_path, pose_png_path = _render_pose_png(preset.slug, preset.keypoints_2d)
    print(f"[PIPE] preset={preset.slug} | source={source_image_name}")
    if extra_prompt:
        print(f"[PIPE] extra prompt -> {extra_prompt}")
    print(f"[PIPE] pose json -> {pose_json_path}")
    print(f"[PIPE] pose png  -> {pose_png_path}")

    if args.start_step == "w1":
        _free_memory("before W1")
        for w1_attempt in range(3):
            try:
                animation_name, w1_saved = _run_w1(
                    animation_base=animation_base,
                    source_image_name=source_image_name,
                    pose_png_name=pose_png_path.name,
                    pose_description=preset.pose_description,
                    controlnet_strength=preset.controlnet_strength,
                    edit_denoise=preset.edit_denoise,
                    seed=args.seed_w1 + w1_attempt * 3571,
                    extra_prompt=extra_prompt,
                    facial_expression=preset.facial_expression,
                    negative_prompt=effective_negative,
                    positive_override=effective_positive_override,
                )
                break
            except RectangularFrameError as exc:
                print(f"[PIPE/W1] rejected attempt {w1_attempt + 1}/3: {exc}")
                _free_memory("retry W1 after rectangular-frame artifact")
        else:
            raise RuntimeError("W1 rectangular-frame QC rejected all 3 attempts")
    else:
        animation_name = w2.resolve_latest_animation_name(animation_base)
        w1_saved = [w2.latest_posed_keyframe(animation_name)]
    w1_stage = {"stage": "w1", "path": str(w1_saved[-1])}
    if args.start_step == "w1":
        w1_stage.update({"positive": w1.POS_PROMPT, "negative": w1.NEG_PROMPT})
    print("STAGE_JSON:", json.dumps(w1_stage, ensure_ascii=False), flush=True)

    if args.start_step in {"w1", "w2"}:
        _free_memory("between W1 and W2")
        for w2_attempt in range(3):
            w2_saved = _run_w2(
                animation_base=animation_base,
                preset_slug=preset.slug,
                motion_prompt=preset.motion_prompt,
                num_frames=preset.num_frames,
                fps=preset.fps,
                seed=args.seed_w2 + w2_attempt * 7919,
                extra_prompt=extra_prompt,
                subtle_idle_motion=preset.subtle_idle_motion,
                negative_prompt=effective_negative,
                positive_override=args.positive_override.strip(),
                locked_idle_prompts=preset.slug == "idle_breathing",
            )
            candidate_video = next(path for path in reversed(w2_saved) if path.suffix.lower() == ".mp4")
            drift = _camera_scale_drift(candidate_video) if preset.subtle_idle_motion else 0.0
            if drift <= 0.035:
                print(f"[PIPE/W2] camera-scale QC pass: {drift:.2%}")
                break
            print(f"[PIPE/W2] camera-scale QC rejected attempt {w2_attempt + 1}/3: {drift:.2%}")
            _free_memory("retry W2 after camera-scale drift")
        else:
            raise RuntimeError("W2 camera-scale QC rejected all 3 attempts; zoomed output was not published")
    else:
        animation_dir = OUTPUT_DIR / "character_pipeline" / "base_animations" / animation_name
        videos = sorted(animation_dir.glob("*.mp4"), key=lambda path: path.stat().st_mtime, reverse=True)
        if not videos:
            raise RuntimeError(f"W3 restart requires an existing W2 video in {animation_dir}")
        w2_saved = [videos[0]]
    w2_video = next(path for path in reversed(w2_saved) if path.suffix.lower() == ".mp4")

    repaired_video = None
    w3_source = next(path for path in reversed(w2_saved) if path.suffix.lower() == ".mp4")
    if preset.subtle_idle_motion and args.start_step != "w3":
        repaired_video = _repair_idle_video(animation_name, w2_saved)
        w3_source = repaired_video
        w2_video = repaired_video
    w2_stage = {"stage": "w2", "path": str(w2_video)}
    if args.start_step in {"w1", "w2"}:
        w2_stage.update({"positive": w2.POS_PROMPT, "negative": w2.NEG_PROMPT})
    print("STAGE_JSON:", json.dumps(w2_stage, ensure_ascii=False), flush=True)

    _free_memory("between W2 and W3")
    w3_saved = _run_w3(
        animation_base=animation_base,
        num_frames=preset.output_frames,
        cell_size=args.cell_size,
        source_video=w3_source,
    )
    w3_saved = [_replace_alpha_with_border_white_key(path, args.cell_size) for path in w3_saved]
    if preset.optimize_loop_seam:
        w3_saved = [_rotate_spritesheet_to_softest_seam(path, args.cell_size) for path in w3_saved]

    print("[PIPE] done")
    print(f"  animation_dir -> {OUTPUT_DIR / 'character_pipeline' / 'base_animations' / animation_name}")
    print(f"  W1 -> {w1_saved[-1]}")
    print(f"  W2 -> {w2_saved[-1]}")
    print(f"  W3 -> {w3_saved[-1]}")
    print(f"  wall_time -> {time.time() - started:.1f}s")
    result = {
        "animation_name": animation_name,
        "preset": preset.slug,
        "render_frames": preset.num_frames,
        "output_frames": preset.output_frames,
        "cell_size": args.cell_size,
        "greyscale": args.greyscale,
        "extra_prompt": extra_prompt,
        "animation_dir": str(OUTPUT_DIR / "character_pipeline" / "base_animations" / animation_name),
        "w1": str(w1_saved[-1]),
        "w2": str(w2_video),
        "repaired_video": str(repaired_video) if repaired_video else None,
        "w3": str(w3_saved[-1]),
    }
    print("RESULT_JSON:", json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
