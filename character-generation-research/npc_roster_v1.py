"""Resumable H3 roster production, with independent CPU alpha export.

This script owns only h3-runtime/npc-roster-v1 and uniquely named Comfy inputs
and outputs. It never modifies old knight clips or the user's port 9315.
Each action uses the approved full 124-frame, 20-step H3 workflow. Generated
frames are whole-body animation; no cutout limbs or transform-only substitutes.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import shutil
import sys
import time
import urllib.error

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from run_h3_smoke import ROOT, api, graph

OUT = ROOT / "npc-roster-v1"
CONFIG = OUT / "roster.json"
SPECS = OUT / "export-specs.json"
IDS = ["scout", "caster", "elite", "boss", "serin"]
ACTION_ORDER = ["stand", "walk", "attack", "hurt", "cast"]
MOTIONS = {
    "stand": "A natural relaxed combat-ready standing idle loop. Feet stay planted. A small breath moves the chest, shoulders and head, weight shifts through hips and knees, then returns to the initial stance. Hair and loose fabric sway and settle. The held weapon remains present and exactly the same size. No walking or attacking.",
    "walk": "Several complete walking cycles in place facing right. Alternating clear left and right steps with heel contact and toe-off, coordinated hip rotation and weight transfer, modest torso rotation and head response. Arms counterbalance while the same weapon remains held consistently throughout. Hair and clothing follow with secondary motion. Stay at the same ground location with no forward drift.",
    "hurt": "One complete quick recoiling body gesture. From the ready stance, abruptly lean the head and shoulders backward, bend the knees and lower the hips while drawing the arms closer to the torso, then regain balance and return to the starting stance. The whole torso, hips, knees and head participate naturally, and hair and fabric follow through. Keep feet in the same small area and keep the same held weapon. Only the character moves. The surrounding empty background stays entirely unchanged and featureless throughout."
}
ROSTER = {
    "scout": {
        "name": "灰誓斥候",
        "description": "An adult male fantasy scout wearing brown leather armor and a dark red scarf, holding one short sword. Preserve his exact illustrated face, hair, outfit, proportions and weapon from the reference.",
        "attack": "One complete physical fencing practice toward the right. From the ready stance shift weight backward and draw the short sword near the hip, drive hips and shoulders forward into one compact diagonal sword cut, follow through and recover to ready. Clear preparation, quick swing and full-body recovery. The sword is a solid rigid unlit metal object of constant length. A quiet physical rehearsal. Only the body, clothes and sword move; the empty background remains completely unchanged, with no motion lines, energy effects or sparks.",
        "height": 238,
        "hurt": "One complete quick recoiling body gesture. From the ready stance, abruptly lean the head and shoulders backward, bend the knees and lower the hips while drawing the arms closer to the torso, then regain balance and return to the starting stance. The whole torso, hips, knees and head participate naturally, and hair and fabric follow through. Keep feet in the same small area and keep the same held weapon. Only the character moves. The surrounding empty background stays entirely unchanged and featureless throughout."
    },
    "caster": {
        "name": "灰誓咒术师",
        "description": "An adult female fantasy sorceress in purple robes with silver ornaments, holding her staff. Preserve her exact illustrated face, hair, outfit, proportions and staff from the reference.",
        "attack": "One complete quick open-palm reaching and pointing gesture toward the right. Begin in the ready stance with the same staff held steadily in one hand. Draw the free open hand toward the chest, rotate shoulders and hips, then extend the free arm and open palm firmly toward the right at shoulder height. Briefly hold the fully extended pose and recover to the starting stance. Her head tracks the hand, shoulders, chest, hips and knees coordinate naturally, and hair and fabric follow through. This is a plain physical acting gesture. Nothing appears, shines, flies, or changes in the background; preserve the same unlit staff and normal clothing colors throughout.",
        "height": 246,
        "hurt": "One complete quick recoiling body gesture. From the ready stance, abruptly lean the head and shoulders backward, bend the knees and lower the hips while drawing the arms closer to the torso, then regain balance and return to the starting stance. The whole torso, hips, knees and head participate naturally, and hair and fabric follow through. Keep feet in the same small area and keep the same held weapon. Only the character moves. The surrounding empty background stays entirely unchanged and featureless throughout."
    },
    "elite": {
        "name": "灰誓重卫",
        "description": "A broad adult male heavy guard in iron gray plate armor and a dark red cape, holding one great axe. Preserve his exact illustrated helmet or face, armor, proportions and large axe from the reference.",
        "attack": "One complete physical rehearsal of an overhead axe swing toward the right. Bend knees and load the hips, wind shoulders and lift the same double-headed axe overhead, push through the legs and rotate the torso into a downward diagonal chop, then follow through and recover to ready. Both axe blades and its long shaft stay rigid and unchanged. Full-body effort and delayed fabric movement. Only the person, clothing and unlit metal axe move. Empty black background stays completely unchanged, without motion lines, dust, sparks, flashes or energy effects.",
        "height": 266,
        "hurt": "One complete quick recoiling body gesture. From the ready stance, abruptly lean the head and shoulders backward, bend the knees and lower the hips while drawing the arms closer to the torso, then regain balance and return to the starting stance. The whole torso, hips, knees and head participate naturally, and hair and fabric follow through. Keep feet in the same small area and keep the same held weapon. Only the character moves. The surrounding empty background stays entirely unchanged and featureless throughout.",
        "reference_height": 440
    },
    "boss": {
        "name": "陨星执政官",
        "description": "An imposing adult male fantasy commander in black and gold plate armor with a burgundy cape, holding one great sword. Preserve his exact illustrated face or helmet, armor, proportions and great sword from the reference.",
        "attack": "The man performs one continuous physical rehearsal with the same solid metal sword. He raises the sword over his shoulder while rotating his chest away, pauses briefly, brings the physical blade diagonally down and forward, then lowers it to the original relaxed stance. His knees bend and his hips shift with the movement, his head follows the direction, and the fabric follows his torso. Show the visible solid blade clearly at every position. Only the man, clothing and metal sword move. Keep the surrounding empty black space completely flat, featureless and unlit throughout. No emitted light or trails.",
        "height": 294,
        "hurt": "One complete quick recoiling body gesture. From the ready stance, abruptly lean the head and shoulders backward, bend the knees and lower the hips while drawing the arms closer to the torso, then regain balance and return to the starting stance. The whole torso, hips, knees and head participate naturally, and hair and fabric follow through. Keep feet in the same small area and keep the same held weapon. Only the character moves. The surrounding empty background stays entirely unchanged and featureless throughout.",
        "reference_height": 440
    },
    "serin": {
        "name": "瑟琳",
        "description": "An adult silver-haired female battle cleric wearing an ivory white and teal short robe with gold ornaments and tall boots, holding a short staff. Preserve her exact illustrated face, hair, outfit, proportions and short staff from the reference.",
        "attack": "One complete precise holy-bolt casting gesture toward the right. Keep the short staff in one hand, draw it back near the shoulder as hips turn, then extend the staff with a crisp full-body forward weight transfer to aim a light bolt, and recover to ready. Her head tracks the aim, shoulders and chest respond naturally, hair and robe follow. Draw only the character and staff, no beam, glow, projectile or particle; effects are independent game layers.",
        "cast": "One complete practical greeting gesture. The woman holds the same unlit short staff steadily in one hand. Her free empty hand lifts naturally near her chest as her head inclines, then she extends the open hand toward the right as if indicating the direction to another person. Fingers naturally spread. Her shoulders, chest and hips coordinate with the reaching hand, then she lowers the hand and returns to the initial stance. Silver hair and teal fabric follow her movement. Only physical body movement, completely flat unlit background. The staff stays physically unchanged and unlit for the entire sequence. No energy is produced.",
        "height": 250
    }
}


def write_json(path: Path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(value, indent=2, ensure_ascii=False), encoding="utf-8")
    temp.replace(path)


def read_json(path: Path, default=None):
    return json.loads(path.read_text(encoding="utf-8-sig")) if path.exists() else default


def initialize():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "references").mkdir(exist_ok=True)
    if not CONFIG.exists():
        data = {"version": 1, "characters": {}}
        for index, (key, entry) in enumerate(ROSTER.items()):
            data["characters"][key] = dict(entry, reference=str(OUT / "references" / f"{key}.png"), seed=1011000 + index * 100, actions=["stand", "walk", "attack", "hurt"] + (["cast"] if key == "serin" else []))
        write_json(CONFIG, data)
    if not SPECS.exists():
        write_json(SPECS, {})


def prepare_reference(key, entry):
    from PIL import Image
    path = Path(entry["reference"])
    source = Image.open(path).convert("RGBA")
    bbox = source.getbbox()
    if not bbox:
        raise ValueError(f"Empty reference: {path}")
    crop = source.crop(bbox)
    # Long weapons require overhead/sweep space. Game display size is restored
    # by one fixed export scale; input framing must not squeeze the weapon.
    crop.thumbnail((540, int(entry.get("reference_height", 520 if key == "serin" else 480))), Image.Resampling.LANCZOS)
    black = Image.new("RGBA", (768, 768), (0, 0, 0, 255))
    origin = ((768 - crop.width) // 2, 648 - crop.height)
    black.alpha_composite(crop, origin)
    prepared = OUT / "references" / f"{key}-h3.png"
    black.convert("RGB").save(prepared)
    core = next(ROOT.glob("ComfyUI-*"))
    input_name = f"npc-roster-v1-{key}.png"
    shutil.copyfile(prepared, core / "input" / input_name)
    write_json(OUT / "references" / f"{key}-reference.json", {"source": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "source_bbox": bbox, "prepared_origin": origin, "prepared_size": crop.size, "canvas": [768, 768], "ground_y": 648})
    portrait = OUT / "export" / key / "portrait.png"
    portrait.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(path, portrait)
    return input_name


def clean_reference(key, source_path, publish=False):
    """Clean generated alpha fringe, save dark/light evidence before publishing."""
    import numpy as np
    from PIL import Image, ImageDraw
    from biref_h3_matte import extract
    original_path = OUT / "raw-reference" / f"{key}.png"
    original_path.parent.mkdir(parents=True, exist_ok=True)
    if source_path.resolve() != original_path.resolve():
        shutil.copyfile(source_path, original_path)
    original = Image.open(original_path).convert("RGBA")
    raw = np.asarray(original).astype(np.float32)
    base_alpha = raw[:, :, 3] / 255
    on_black = Image.fromarray((raw[:, :, :3] * base_alpha[:, :, None]).astype(np.uint8), "RGB")
    # The API output can have opaque paint at alpha=253 rather than 255. Use
    # a robust high percentile so this normalization does not key away paint.
    opaque = max(1, float(np.percentile(raw[:, :, 3][raw[:, :, 3] > 32], 99)))
    original_alpha = np.clip((raw[:, :, 3] - 3) / max(1, opaque - 3), 0, 1)
    _, probability = extract(get_matte_session(), on_black, return_mask=True)
    semantic_alpha = np.clip((probability - .08) / .84, 0, 1)
    alpha = np.minimum(original_alpha, semantic_alpha)
    # A supplied transparent PNG already has authoritative opaque geometry.
    # BiRef can mistake an oversized axe blade for scenery. In that case it
    # may clean only the fractional fringe, not erase solid original paint.
    has_real_alpha = float(np.mean(base_alpha < .1)) > .3
    if has_real_alpha:
        solid_original = original_alpha >= .90
        alpha[solid_original] = original_alpha[solid_original]
    alpha[alpha < .015] = 0
    alpha[alpha > .985] = 1
    rgba = raw.copy()
    rgba[:, :, 3] = alpha * 255
    rgba[alpha == 0] = 0
    candidate = Image.fromarray(rgba.astype(np.uint8), "RGBA")
    candidate_path = OUT / "review" / f"{key}-reference-clean.png"
    candidate_path.parent.mkdir(parents=True, exist_ok=True)
    candidate.save(candidate_path)
    sheet = Image.new("RGB", (1024, 768), "#172536")
    draw = ImageDraw.Draw(sheet)
    for col, color in enumerate(("#132334", "#e7e2d9")):
        bg = Image.new("RGBA", original.size, color)
        bg.alpha_composite(candidate)
        sheet.paste(bg.resize((512, 768)), (col * 512, 0))
        draw.text((col * 512 + 12, 12), f"{key} / cleaned alpha", fill="white" if col == 0 else "black")
    sheet.save(OUT / "review" / f"{key}-reference-alpha.jpg", quality=95)
    write_json(OUT / "review" / f"{key}-reference-clean.json", {"source_sha256": hashlib.sha256(original_path.read_bytes()).hexdigest(), "original_size": original.size, "opaque_alpha_percentile": opaque, "bounds": candidate.getbbox(), "opaque_pixels": int(np.count_nonzero(alpha > .98)), "fractional_pixels": int(np.count_nonzero((alpha > 0) & (alpha < 1))), "method": "native opaque alpha preserved; BiRefNet trims fractional fringe", "has_native_alpha": has_real_alpha, "published": publish})
    if publish:
        reference = OUT / "references" / f"{key}.png"
        # Publish atomically so the watching generator never sees half a PNG.
        tmp = reference.with_suffix(".tmp.png")
        candidate.save(tmp)
        tmp.replace(reference)
        for dest in (OUT / "export" / key / "portrait.png", HERE.parent / "godot-belt-map" / "assets" / "roster" / key / "portrait.png"):
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(reference, dest)
    print("REFERENCE", key, candidate_path, "published", publish, flush=True)
    return candidate_path


def make_graph(key, action, entry):
    g = graph("attack")
    del g["5"]
    g["1"]["inputs"]["image"] = prepare_reference(key, entry)
    g["7"]["inputs"]["model"] = ["3", 0]
    g["10"]["inputs"].update(model=["3", 0], steps=20, scheduler="normal")
    g["8"]["inputs"]["noise_seed"] = entry["seed"] + ACTION_ORDER.index(action)
    motion = entry.get(action, MOTIONS.get(action))
    if not motion:
        raise ValueError(f"Missing motion: {key}/{action}")
    prompt = "The character in <Picture 1>. " + entry["description"] + " " + motion + " Detailed polished hand-painted 2D fantasy game illustration, crisp contours and precise cel-painted shading consistent with the reference, natural anatomy and coherent full-body movement. Fixed side-view camera facing right, full body at constant scale with the same ground line. Entire hair, hands, weapon, clothing and feet visible throughout; broad empty margins. Uniform pure black background, no floor, no ground shadow, no scenery, no camera motion, no zoom, no cuts, no captions, no extra character, no motion blur. Silent."
    prefix = f"npc-roster-v1-{key}-{action}"
    g["6"]["inputs"].update(width=768, height=768, length=124, prompt=prompt)
    g["14"]["inputs"]["filename_prefix"] = prefix
    g["15"]["inputs"]["filename_prefix"] = "frames/" + prefix
    return g


def source_paths(key, action, history=None):
    history = history or read_json(OUT / "jobs" / key / action / "history.json", {})
    paths = [ROOT / "output" / f["subfolder"] / f["filename"] for f in history.get("outputs", {}).get("15", {}).get("images", [])]
    if len(paths) == 124 and all(p.exists() for p in paths):
        return paths
    # A native backend crash can lose in-memory history after SaveImage wrote
    # every frame. Recovery is explicit and records verified PNG provenance;
    # it must never invent a successful Comfy history record.
    recovered = read_json(OUT / "jobs" / key / action / "recovered-frames.json", {})
    records = recovered.get("frames", [])
    if len(records) == 124:
        paths = [ROOT / "output" / r["file"] for r in records]
        if all(p.is_file() and hashlib.sha256(p.read_bytes()).hexdigest() == r["sha256"] for p, r in zip(paths, records)):
            return paths
    return []


def generate_one(key, action, entry):
    folder = OUT / "jobs" / key / action
    old = read_json(folder / "history.json")
    if (folder / "recovered-frames.json").exists() and source_paths(key, action):
        print("REUSE_VERIFIED_RECOVERY", key, action, flush=True)
        return
    if old and old.get("status", {}).get("status_str") == "success" and source_paths(key, action, old):
        print("REUSE", key, action, flush=True)
        return
    job = read_json(folder / "job.json")
    pid = job.get("prompt_id") if job else None
    if pid:
        history = api("/history/" + pid)
        queue = api("/queue")
        queued = any(row[1] == pid for rows in queue.values() if isinstance(rows, list) for row in rows)
        if pid in history:
            result = history[pid]
            if result["status"]["status_str"] == "success" and source_paths(key, action, result):
                write_json(folder / "history.json", result)
                return
            raise RuntimeError(f"Previous job failed/incomplete: {key}/{action}, inspect {folder}")
        if not queued:
            print("LOST_JOB_RESUBMIT", key, action, pid, flush=True)
            pid = None
    if not pid:
        while True:
            queue = api("/queue")
            if not queue["queue_running"] and not queue["queue_pending"]:
                break
            print("WAIT_EXISTING_QUEUE", key, action, flush=True)
            time.sleep(10)
        g = make_graph(key, action, entry)
        write_json(folder / "workflow.json", g)
        job = api("/prompt", {"prompt": g, "client_id": "npc-roster-v1"})
        write_json(folder / "job.json", job)
        pid = job["prompt_id"]
    start = time.time()
    print("GENERATING", key, action, pid, flush=True)
    while True:
        history = api("/history/" + pid)
        if pid in history:
            result = history[pid]
            write_json(folder / "history.json", result)
            if result["status"]["status_str"] != "success" or not source_paths(key, action, result):
                raise RuntimeError(f"Failed/incomplete H3 output: {key}/{action}")
            print("GENERATED", key, action, "seconds", round(time.time() - start), flush=True)
            make_source_review(key, action)
            return
        time.sleep(10)


def make_source_review(key, action):
    from PIL import Image, ImageDraw
    paths = source_paths(key, action)
    sheet = Image.new("RGB", (1536, 1536), "#171e29")
    draw = ImageDraw.Draw(sheet)
    for n, index in enumerate([0, 8, 16, 24, 32, 40, 48, 56, 64, 72, 80, 88, 96, 104, 112, 123]):
        image = Image.open(paths[index]).convert("RGB").resize((384, 384))
        xy = (n % 4 * 384, n // 4 * 384)
        sheet.paste(image, xy)
        draw.text((xy[0] + 8, xy[1] + 8), f"{key}/{action} source {index}", fill="white", stroke_width=1, stroke_fill="black")
    target = OUT / "review" / f"{key}-{action}-source.jpg"
    target.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(target, quality=94)


_MATTE_SESSION = None


def get_matte_session():
    global _MATTE_SESSION
    if _MATTE_SESSION is None:
        from biref_h3_matte import session
        _MATTE_SESSION = session(use_gpu=False)
    return _MATTE_SESSION


def matte_frame(path, cache):
    import numpy as np
    from PIL import Image
    from biref_h3_matte import extract
    from improve_h3_matte import matte
    source_digest = hashlib.sha256(path.read_bytes()).hexdigest()
    stamp = cache.with_suffix(".source.sha256")
    if cache.exists() and stamp.exists() and stamp.read_text(encoding="ascii").strip() == source_digest:
        return Image.open(cache).convert("RGBA")
    raw = Image.open(path).convert("RGB")
    result, probability = extract(get_matte_session(), raw, return_mask=True)
    rgba = np.asarray(result).copy()
    keyed = np.asarray(matte(raw, True))
    # H3 backgrounds are black. Keep high-confidence opaque painted fabric
    # (including navy/teal) instead of interpreting its color as additive light.
    # No hard-coded character-shaped region or body-part motion is used here.
    body = probability >= .82
    rgba[body] = keyed[body]
    # Oversized weapons and detached staff crystals can be rejected by the
    # semantic model. Against verified black H3 backgrounds, clearly painted
    # nonblack pixels are evidence and may not be deleted by that classifier.
    paint = (np.asarray(raw).max(axis=2) > 28) & (keyed[:, :, 3] > 0)
    rgba[paint] = keyed[paint]
    # Detached light was not requested; preserve only the segmentation output
    # elsewhere. Every action is reviewed on dark and pale backgrounds below.
    rgba[rgba[:, :, 3] < 3] = 0
    result = Image.fromarray(rgba, "RGBA")
    cache.parent.mkdir(parents=True, exist_ok=True)
    result.save(cache)
    stamp.write_text(source_digest + "\n", encoding="ascii")
    return result


def best_loop(paths, minimum, maximum, require_motion=False):
    import numpy as np
    from PIL import Image
    small = np.stack([np.asarray(Image.open(p).convert("RGB").resize((80, 80)), dtype=np.float32) for p in paths])
    activity = np.mean(np.abs(np.diff(small, axis=0)), axis=(1, 2, 3))
    required_activity = max(.2, float(np.percentile(activity, 60)) * .75) if require_motion else 0
    best = (float("inf"), 8, minimum + 8)
    for start in range(4, min(55, len(paths) - maximum - 1)):
        for span in range(minimum, maximum + 1):
            end = start + span
            if float(activity[start:end].mean()) < required_activity:
                continue
            pose = float(np.mean((small[start] - small[end]) ** 2))
            velocity = float(np.mean(((small[start + 1] - small[start]) - (small[end + 1] - small[end])) ** 2))
            candidate = (pose + velocity * .35, start, end)
            if candidate < best:
                best = candidate
    if not np.isfinite(best[0]):
        raise ValueError("No moving loop candidate; inspect the source before export")
    return {"start": best[1], "end": best[2], "seam_score": best[0], "mean_motion": float(activity[best[1]:best[2]].mean())}


def select_frames(key, action, paths):
    spec = read_json(SPECS, {}).get(key, {}).get(action, {})
    if "indices" in spec:
        return spec, spec["indices"], spec["durations"]
    if action in ("stand", "walk"):
        loop = best_loop(paths, *( (48, 88) if action == "stand" else (22, 80) ), require_motion=action == "walk")
        indices = list(range(loop["start"], loop["end"], 3))
        durations = [125 if action == "stand" else 70] * len(indices)
        spec["loop_selection"] = loop
    else:
        indices = [0, 8, 16, 24, 32, 40, 48, 56, 64, 72, 80, 88, 96, 104, 112, 123]
        durations = [60, 60, 50, 50, 40, 25, 20, 20, 20, 45, 30, 35, 40, 45, 60, 60]
        if action == "hurt":
            durations = [max(20, round(ms * .6)) for ms in durations]
        elif action == "cast":
            durations = [round(ms * 1.2) for ms in durations]
    spec["indices"] = indices
    spec["durations"] = durations
    return spec, indices, durations


def cleanup_effect(cut, source, spec, raw_path=None):
    """Apply only reviewed, explicit per-source-frame background-FX cleanup."""
    import numpy as np
    from PIL import Image
    rule = spec.get("alpha_cleanup", {}).get(str(source))
    if not rule:
        return cut
    rgba = np.asarray(cut).copy()
    if rule["mode"] == "semantic":
        probability = np.load(OUT / rule["probability"])
        keep = np.clip((probability - .03) / .94, 0, 1)
        rgba[:, :, 3] = np.minimum(rgba[:, :, 3], keep * 255).astype(np.uint8)
    elif rule["mode"] == "clear_background_regions":
        yy, xx = np.indices(rgba.shape[:2])
        region = np.zeros(rgba.shape[:2], bool)
        for x0, y0, x1, y1 in rule["rects"]:
            region[y0:y1, x0:x1] = True
        for ax, ay, bx, by, radius in rule.get("protect_capsules", []):
            dx, dy = bx - ax, by - ay
            t = np.clip(((xx - ax) * dx + (yy - ay) * dy) / max(1, dx * dx + dy * dy), 0, 1)
            protected = (xx - ax - t * dx) ** 2 + (yy - ay - t * dy) ** 2 <= radius ** 2
            region &= ~protected
        rgba[:, :, 3][region] = 0
    elif rule["mode"] == "gold_arc_regions":
        rgb = rgba[:, :, :3].astype(np.int16)
        gold = (rgb[:, :, 0] - rgb[:, :, 2] > 45) & (rgb[:, :, 1] - rgb[:, :, 2] > 25) & (rgb[:, :, 0] > 70)
        region = np.zeros(gold.shape, bool)
        for x0, y0, x1, y1 in rule["rects"]:
            region[y0:y1, x0:x1] = True
        rgba[:, :, 3][gold & region] = 0
    elif rule["mode"] in ("glow_coverage", "smear_coverage", "glow_from_source"):
        pass
    else:
        raise ValueError(f"Unknown cleanup mode {rule['mode']}")
    if "glow_center" in rule or "coverage_rects" in rule:
        yy, xx = np.indices(rgba.shape[:2])
        region = np.zeros(rgba.shape[:2], bool)
        if "glow_center" in rule:
            cx, cy = rule["glow_center"]
            region |= (xx - cx) ** 2 + (yy - cy) ** 2 <= rule.get("radius", 36) ** 2
        for x0, y0, x1, y1 in rule.get("coverage_rects", []):
            region[y0:y1, x0:x1] = True
        if "max_y" in rule:
            region &= yy < rule["max_y"]
        for ax, ay, bx, by, radius in rule.get("protect_capsules", []):
            dx, dy = bx - ax, by - ay
            t = np.clip(((xx - ax) * dx + (yy - ay) * dy) / max(1, dx * dx + dy * dy), 0, 1)
            region &= (xx - ax - t * dx) ** 2 + (yy - ay - t * dy) ** 2 > radius ** 2
        rgb = rgba[:, :, :3].astype(np.float32)
        if "protect_low_saturation" in rule:
            maximum = rgb.max(axis=2)
            saturation = (maximum - rgb.min(axis=2)) / np.maximum(maximum, 1)
            region &= ~((saturation < rule["protect_low_saturation"]) & (maximum > 35))
        if rule.get("protect_polygons"):
            from PIL import ImageDraw
            mask = Image.new("L", (rgba.shape[1], rgba.shape[0]))
            painter = ImageDraw.Draw(mask)
            for polygon in rule["protect_polygons"]:
                painter.polygon([tuple(point) for point in polygon], fill=255)
            region &= np.asarray(mask) == 0
        if "protect_mask" in rule:
            region &= np.asarray(Image.open(OUT / rule["protect_mask"]).convert("L")) == 0
        if rule["mode"] == "glow_from_source":
            if raw_path is None:
                raise ValueError("Raw RGB is required to reconstruct a smooth glow")
            raw_rgb = np.asarray(Image.open(raw_path).convert("RGB"), dtype=np.float32)
            if "background_reference" in rule:
                background = np.asarray(Image.open(ROOT / "output" / rule["background_reference"]).convert("RGB"), dtype=np.float32)
                if "background_rects" in rule:
                    keep_background = np.zeros(background.shape[:2], bool)
                    for x0,y0,x1,y1 in rule["background_rects"]:
                        keep_background[y0:y1,x0:x1] = True
                    background[~keep_background] = 0
                raw_rgb = np.maximum(0, raw_rgb - background)
            black_level = rule.get("black_level", 2)
            coverage = np.clip((raw_rgb.max(axis=2) - black_level) / (255-black_level), 0, 1)
            straight = np.clip(raw_rgb / np.maximum(coverage[:, :, None], .008), 0, 255)
            rgba[:, :, :3][region] = straight[region].astype(np.uint8)
            rgba[:, :, 3][region] = (coverage[region] * 255).astype(np.uint8)
            rgba[rgba[:, :, 3] < 3] = 0
            return Image.fromarray(rgba, "RGBA")
        coverage = np.clip((rgb.max(axis=2) - 3) / 252, 0, 1)
        old_alpha = rgba[:, :, 3].astype(np.float32) / 255
        new_alpha = np.minimum(old_alpha, coverage)
        fade = region & (new_alpha < old_alpha)
        rgb[fade] = np.clip(rgb[fade] * (old_alpha[fade] / np.maximum(new_alpha[fade], .025))[:, None], 0, 255)
        rgba[:, :, :3] = rgb.astype(np.uint8)
        rgba[:, :, 3][fade] = (new_alpha[fade] * 255).astype(np.uint8)
    rgba[rgba[:, :, 3] < 3] = 0
    return Image.fromarray(rgba, "RGBA")


def make_selected_review(key, action):
    """Show every exported frame on both backgrounds, not just six samples."""
    from PIL import Image, ImageDraw
    manifest = read_json(OUT / "export" / key / "animation.json")
    records = manifest["actions"][action]["frames"]
    rows = (len(records) + 3) // 4
    for variant, color in (("dark", "#172536"), ("light", "#e0e5e8")):
        sheet = Image.new("RGB", (1536, rows * 408), color)
        draw = ImageDraw.Draw(sheet)
        for index, record in enumerate(records):
            pic = Image.open(OUT / "export" / key / record["file"]).convert("RGBA")
            bg = Image.new("RGBA", pic.size, color)
            bg.alpha_composite(pic)
            x, y = index % 4 * 384, index // 4 * 408
            sheet.paste(bg.resize((384, 384)), (x, y + 24))
            draw.text((x + 8, y + 6), f'{key}/{action} #{index} source {record["source_frame"]} {record["duration_ms"]}ms', fill="white" if variant == "dark" else "black")
        sheet.save(OUT / "review" / f"{key}-{action}-all-{variant}.jpg", quality=96)


def export_one(key, action, entry, force=False):
    import numpy as np
    from PIL import Image, ImageDraw
    paths = source_paths(key, action)
    if not paths:
        return False
    dest = OUT / "export" / key
    manifest_path = dest / "animation.json"
    manifest = read_json(manifest_path, {"version": 1, "id": key, "name": entry["name"], "canvas": [768, 768], "portrait": "portrait.png", "actions": {}})
    if not force and action in manifest["actions"]:
        return True
    spec, indices, durations = select_frames(key, action, paths)
    if len(indices) != len(durations) or any(i < 0 or i >= 124 for i in indices):
        raise ValueError(f"Invalid export spec for {key}/{action}")
    pics, records = [], []
    for i, (source, ms) in enumerate(zip(indices, durations)):
        cache = OUT / "mattes" / key / action / f"{source:04d}.png"
        cut = matte_frame(paths[source], cache)
        cut = cleanup_effect(cut, source, spec, paths[source])
        name = f"{action}/{i:03d}.png"
        target = dest / name
        target.parent.mkdir(parents=True, exist_ok=True)
        cut.save(target)
        records.append({"file": name, "source_frame": source, "duration_ms": ms})
        pics.append(cut)
        if i % 8 == 0:
            print("MATTE", key, action, i, "/", len(indices), flush=True)
    first = matte_frame(paths[0], OUT / "mattes" / key / action / "0000.png")
    alpha = np.asarray(first)[:, :, 3]
    yy, xx = np.where(alpha > 180)
    if len(yy) < 100:
        raise ValueError(f"Empty character after alpha extraction: {key}/{action}")
    floor = int(np.percentile(yy, 99.8))
    top = int(yy.min())
    foot_x = float(np.median(xx[yy > floor - 24]))
    anchor = manifest.get("actions", {}).get("stand", {}) if action != "stand" else {}
    info = {"frames": records, "duration_ms": sum(durations), "pivot": spec.get("pivot", anchor.get("pivot", [round(foot_x, 2), floor])), "scale": spec.get("scale", anchor.get("scale", entry["height"] / max(1, floor - top))), "source": f"npc-roster-v1-{key}-{action}", "review_status": spec.get("review_status", "needs_visual_review"), "source_count": 124}
    if action in ("attack", "cast"):
        info["event_ms"] = spec.get("event_ms", sum(durations[:8]))
    if "emitter" in spec:
        info["emitter"] = spec["emitter"]
        info["emitter_source_frame"] = spec.get("emitter_source_frame")
    if "loop_selection" in spec:
        info["loop_selection"] = spec["loop_selection"]
    # A reviewer may export another action while the production worker is
    # finishing this one. Merge into the latest manifest to retain its changes.
    manifest = read_json(manifest_path, manifest)
    manifest["actions"][action] = info
    write_json(manifest_path, manifest)
    chosen = OUT / "jobs" / key / action / "export-selection.json"
    write_json(chosen, spec)
    review = OUT / "review"
    review.mkdir(exist_ok=True)
    preview = []
    sheet = Image.new("RGB", (1536, 768), "#172536")
    draw = ImageDraw.Draw(sheet)
    for n, index in enumerate(np.linspace(0, len(pics) - 1, 6, dtype=int)):
        for row, color in enumerate(("#172536", "#d8e2eb")):
            bg = Image.new("RGBA", (768, 768), color)
            bg.alpha_composite(pics[index])
            sheet.paste(bg.resize((256, 256)), (n * 256, row * 384 + 40))
            draw.text((n * 256 + 6, row * 384 + 8), f"{key}/{action} src {indices[index]}", fill="white" if row == 0 else "black")
    sheet.save(review / f"{key}-{action}-alpha.jpg", quality=95)
    for pic in pics:
        bg = Image.new("RGBA", (768, 768), "#172536")
        bg.alpha_composite(pic)
        preview.append(bg.resize((384, 384)))
    preview[0].save(review / f"{key}-{action}.webp", save_all=True, append_images=preview[1:], duration=durations, loop=0, lossless=True)
    write_json(review / f"{key}-{action}-checks.json", {"canvas": [768, 768], "count": len(pics), "duration_ms": sum(durations), "opaque_edge_pixels": [int(np.count_nonzero(np.asarray(p)[:, :, 3][0, :] > 20) + np.count_nonzero(np.asarray(p)[:, :, 3][-1, :] > 20) + np.count_nonzero(np.asarray(p)[:, :, 3][:, 0] > 20) + np.count_nonzero(np.asarray(p)[:, :, 3][:, -1] > 20)) for p in pics], "bounds": [p.getbbox() for p in pics], "review_status": info["review_status"]})
    make_selected_review(key, action)
    print("EXPORTED", key, action, len(pics), info["duration_ms"], "ms", flush=True)
    return True


def status():
    data = read_json(CONFIG)["characters"]
    result = []
    for key, entry in data.items():
        manifest = read_json(OUT / "export" / key / "animation.json", {})
        for action in entry["actions"]:
            history = read_json(OUT / "jobs" / key / action / "history.json", {})
            result.append({"id": key, "action": action, "reference_ready": Path(entry["reference"]).exists(), "generated": len(source_paths(key, action, history)) == 124, "exported": action in manifest.get("actions", {}), "review": manifest.get("actions", {}).get(action, {}).get("review_status", "pending")})
    write_json(OUT / "status.json", result)
    print(json.dumps(result, indent=2, ensure_ascii=False))


def validate(ids):
    import math
    import numpy as np
    from PIL import Image
    errors, warnings, checked = [], [], 0
    for key in ids:
        dest = OUT / "export" / key
        entry = read_json(CONFIG)["characters"][key]
        manifest = read_json(dest / "animation.json", {})
        if not (dest / "portrait.png").is_file():
            errors.append(f"{key}: missing portrait")
        for action in entry["actions"]:
            info = manifest.get("actions", {}).get(action)
            if not info:
                errors.append(f"{key}/{action}: missing action")
                continue
            frames = info.get("frames", [])
            duration = sum(f.get("duration_ms", 0) for f in frames)
            if duration != info.get("duration_ms") or duration <= 0:
                errors.append(f"{key}/{action}: invalid duration")
            if action in ("attack", "cast") and not (0 < info.get("event_ms", 0) < duration):
                errors.append(f"{key}/{action}: event outside action")
            if not all(math.isfinite(v) for v in info.get("pivot", [])) or not (0 < info.get("scale", 0) < 4):
                errors.append(f"{key}/{action}: invalid fixed transform")
            if info.get("review_status") != "visually_reviewed":
                warnings.append(f"{key}/{action}: manual visual review pending")
            for frame in frames:
                path = dest / frame["file"]
                if not path.is_file():
                    errors.append(f"{key}/{action}: missing {frame['file']}")
                    continue
                im = Image.open(path)
                if im.mode != "RGBA" or im.size != (768, 768):
                    errors.append(f"{path}: expected 768x768 RGBA")
                    continue
                alpha = np.asarray(im)[:, :, 3]
                edge = np.concatenate([alpha[0], alpha[-1], alpha[:, 0], alpha[:, -1]])
                if np.any(edge > 20):
                    errors.append(f"{path}: opaque canvas edge/cropped character")
                if np.count_nonzero(alpha > 180) < 100 or np.count_nonzero(alpha == 0) < alpha.size * .3:
                    errors.append(f"{path}: empty or unremoved background")
                if not (0 <= frame.get("source_frame", -1) < 124) or frame.get("duration_ms", 0) <= 0:
                    errors.append(f"{path}: source index/timing invalid")
                checked += 1
    report = {"ok": not errors, "checked_frames": checked, "errors": errors, "warnings": warnings}
    write_json(OUT / "validation.json", report)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return report["ok"]


def publish_reviewed(ids):
    """Pack reviewed game copies; preserve original full-canvas source frames."""
    from pack_roster_runtime import pack_character
    for key in ids:
        source = OUT / "export" / key
        manifest = read_json(source / "animation.json")
        if not manifest:
            continue
        accepted = {action: info for action, info in manifest["actions"].items() if info.get("review_status") == "visually_reviewed"}
        if not accepted:
            continue
        pack_character(key)
        print("PUBLISHED", key, ",".join(accepted), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["init", "run", "export", "status", "review", "validate", "reference", "publish"])
    parser.add_argument("--ids", nargs="+", choices=IDS, default=IDS)
    parser.add_argument("--actions", nargs="+", choices=ACTION_ORDER, default=ACTION_ORDER)
    parser.add_argument("--watch-references", action="store_true")
    parser.add_argument("--no-export", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--source", type=Path)
    parser.add_argument("--publish", action="store_true")
    args = parser.parse_args()
    initialize()
    if args.mode == "init":
        print(CONFIG)
        return
    if args.mode == "status":
        status()
        return
    if args.mode == "validate":
        raise SystemExit(0 if validate(args.ids) else 1)
    if args.mode == "publish":
        publish_reviewed(args.ids)
        return
    if args.mode == "reference":
        if len(args.ids) != 1 or not args.source:
            parser.error("reference requires --ids ONE_ID and --source PATH")
        clean_reference(args.ids[0], args.source, args.publish)
        return
    entries = read_json(CONFIG)["characters"]
    jobs = [(key, action) for action in args.actions for key in args.ids if action in entries[key]["actions"]]
    if args.mode == "export":
        for key, action in jobs:
            export_one(key, action, entries[key], args.force)
        status()
        return
    if args.mode == "review":
        for key, action in jobs:
            if source_paths(key, action):
                make_source_review(key, action)
        return
    started = time.time()
    futures = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=1, thread_name_prefix="roster-alpha") as pool:
        while jobs:
            if (OUT / "STOP_AFTER_CURRENT").exists():
                print("STOP_REQUESTED", flush=True)
                break
            entries = read_json(CONFIG)["characters"]
            priority = read_json(OUT / "schedule.json", {}).get("priority_characters", [])
            if priority:
                jobs.sort(key=lambda job: (priority.index(job[0]) if job[0] in priority else len(priority), ACTION_ORDER.index(job[1]), IDS.index(job[0])))
            ready = next(((i, key, action) for i, (key, action) in enumerate(jobs) if Path(entries[key]["reference"]).exists()), None)
            if ready is None:
                if not args.watch_references:
                    raise FileNotFoundError("References not ready. Supply RGBA originals in references/ or use --watch-references.")
                print("WAIT_REFERENCES", round(time.time() - started), flush=True)
                time.sleep(10)
                entries = read_json(CONFIG)["characters"]
                continue
            i, key, action = ready
            generate_one(key, action, entries[key])
            if not args.no_export:
                futures.append(pool.submit(export_one, key, action, entries[key], args.force))
            jobs.pop(i)
            # Surface failed alpha tasks promptly without killing healthy GPU work.
            for future in futures:
                if future.done() and future.exception():
                    raise future.exception()
        for future in futures:
            future.result()
    status()
    print("ROSTER_COMPLETE", round(time.time() - started), "seconds", flush=True)


if __name__ == "__main__":
    main()
