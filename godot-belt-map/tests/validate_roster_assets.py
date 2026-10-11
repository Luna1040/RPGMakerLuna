#!/usr/bin/env python3
"""Read-only release gate for the five authored PNG actors; requires Pillow.

Structural checks cannot assess anatomy, silhouettes, loop continuity or style.
Every action therefore also needs an explicit visually_reviewed marker. Use
--allow-pending-review only during production: it never grants release_ready.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageChops

IDS = ("scout", "caster", "elite", "boss", "serin")
REQUIRED = ("stand", "walk", "attack", "hurt")
CANVAS = (768, 768)
STORAGE_PADDING = 4


def number(value, low, high):
    try:
        return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and low <= value <= high
    except (OverflowError, TypeError):
        return False


def safe_path(directory: Path, value) -> Path | None:
    if not isinstance(value, str) or not value or "\\" in value:
        return None
    try:
        relative = Path(value)
        if relative.is_absolute() or ":" in value or ".." in relative.parts or any(ord(char) < 32 for char in value):
            return None
        target = (directory / relative).resolve()
        return target if target.is_relative_to(directory.resolve()) else None
    except (OSError, ValueError):
        return None


def storage_crop_valid(value) -> bool:
    if not isinstance(value, list) or len(value) != 4 or not all(type(part) is int for part in value):
        return False
    x, y, width, height = value
    return x >= 0 and y >= 0 and width > STORAGE_PADDING * 2 and height > STORAGE_PADDING * 2 and x + width <= CANVAS[0] and y + height <= CANVAS[1]


def canvas_point_valid(value) -> bool:
    return isinstance(value, list) and len(value) == 2 and all(number(part, 0, CANVAS[index]) for index, part in enumerate(value))


def edge_samples(alpha: Image.Image, band: int, threshold: int) -> int:
    strips = [alpha.crop((0, 0, alpha.width, band)), alpha.crop((0, alpha.height - band, alpha.width, alpha.height)),
              alpha.crop((0, 0, band, alpha.height)), alpha.crop((alpha.width - band, 0, alpha.width, alpha.height))]
    return sum(sum(strip.histogram()[threshold + 1:]) for strip in strips)


def visible_rgba(source: Image.Image) -> Image.Image:
    # Invisible RGB is irrelevant; every alpha and every RGB with alpha>0 is exact.
    canonical = Image.new("RGBA", source.size)
    canonical.paste(source, mask=source.getchannel("A").point(lambda alpha: 255 if alpha > 0 else 0))
    return canonical


def check_png(path: Path, label: str, errors: list[str], *, frame: bool, storage_crop=None, source_path: Path | None = None) -> dict:
    try:
        with Image.open(path) as source:
            source.load()
            if source.format != "PNG" or source.mode != "RGBA":
                errors.append(f"{label}: expected true RGBA PNG")
                return {}
            expected = tuple(storage_crop[2:]) if storage_crop is not None else CANVAS
            if (frame and source.size != expected) or (not frame and min(source.size) < 128):
                errors.append(f"{label}: invalid canvas {source.size}")
                return {}
            stored_size = source.size
            padding_samples = 0
            if storage_crop is not None:
                padding_samples = edge_samples(source.getchannel("A"), STORAGE_PADDING, 0)
                if padding_samples:
                    errors.append(f"{label}: storage crop lacks four fully transparent safety pixels on every edge")
                virtual = Image.new("RGBA", CANVAS)
                virtual.paste(source, tuple(storage_crop[:2]))
            else:
                virtual = source
            alpha = virtual.getchannel("A")
            histogram = alpha.histogram()
            pixels = virtual.width * virtual.height
            opaque_edge = edge_samples(alpha, 1, 20)
            if opaque_edge:
                errors.append(f"{label}: {opaque_edge} opaque border samples; likely cropped artwork/background")
            if sum(histogram[181:]) < 100:
                errors.append(f"{label}: empty or almost invisible character")
            minimum_clear = .30 if frame else .05
            if histogram[0] / pixels < minimum_clear:
                errors.append(f"{label}: insufficient fully transparent background")
            source_verified = False
            canonical = visible_rgba(virtual)
            if storage_crop is not None and source_path is not None:
                try:
                    with Image.open(source_path) as original:
                        original.load()
                        if original.mode != "RGBA" or original.size != CANVAS:
                            errors.append(f"{label}: archival source must remain full 768x768 RGBA")
                        else:
                            different = any(low != 0 or high != 0 for low, high in ImageChops.difference(canonical, visible_rgba(original)).getextrema())
                            if different:
                                errors.append(f"{label}: reconstructed crop differs from visible source RGBA; pixels lost or moved")
                            else:
                                source_verified = True
                except (OSError, ValueError) as exc:
                    errors.append(f"{label}: cannot verify uncropped archival source ({exc})")
            return {"size": list(virtual.size), "stored_size": list(stored_size), "bbox": alpha.getbbox(), "opaque_edge_samples": opaque_edge,
                    "storage_padding_samples": padding_samples, "source_verified": source_verified,
                    "transparent_fraction": round(histogram[0] / pixels, 5),
                    "sha256": hashlib.sha256(canonical.tobytes()).hexdigest()}
    except (OSError, ValueError) as exc:
        errors.append(f"{label}: cannot read PNG ({exc})")
        return {}


def validate(root: Path, *, require_review: bool = True, ids=IDS, source_root: Path | None = None) -> dict:
    errors: list[str] = []
    warnings: list[str] = []
    roles: dict = {}
    pending: list[str] = []
    frame_count = 0
    cropped_frames = 0
    source_checked_frames = 0
    for identity in ids:
        directory = root / identity
        role = {"actions": {}}
        roles[identity] = role
        try:
            manifest = json.loads((directory / "animation.json").read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            errors.append(f"{identity}: missing/invalid animation.json ({exc})")
            continue
        if not isinstance(manifest, dict):
            errors.append(f"{identity}: manifest must be an object")
            continue
        if manifest.get("version") != 1 or isinstance(manifest.get("version"), bool) or manifest.get("id") != identity:
            errors.append(f"{identity}: manifest version/identity mismatch")
        if manifest.get("canvas") != list(CANVAS):
            errors.append(f"{identity}: expected one fixed 768x768 canvas")
        portrait = safe_path(directory, manifest.get("portrait"))
        if portrait is None:
            errors.append(f"{identity}: unsafe or missing portrait path")
        else:
            role["portrait"] = check_png(portrait, f"{identity}/portrait", errors, frame=False)
        actions = manifest.get("actions")
        if not isinstance(actions, dict):
            errors.append(f"{identity}: missing actions object")
            continue
        archival_actions = {}
        archival_metadata_error = ""
        if source_root is not None:
            try:
                archival_manifest = json.loads((source_root / identity / "animation.json").read_text(encoding="utf-8"))
                if not isinstance(archival_manifest, dict) or not isinstance(archival_manifest.get("actions"), dict):
                    raise ValueError("archival manifest has no actions object")
                archival_actions = archival_manifest["actions"]
            except (OSError, ValueError) as exc:
                archival_metadata_error = str(exc)
        for action in REQUIRED + (("cast",) if identity == "serin" else ()):
            label = f"{identity}/{action}"
            clip = actions.get(action)
            if not isinstance(clip, dict):
                errors.append(f"{label}: missing required action")
                continue
            if clip.get("review_status") != "visually_reviewed":
                pending.append(label)
                (errors if require_review else warnings).append(f"{label}: full-motion and dark/light alpha review pending")
            pivot = clip.get("pivot")
            if not canvas_point_valid(pivot):
                errors.append(f"{label}: invalid fixed pivot")
            if "emitter" in clip and not canvas_point_valid(clip["emitter"]):
                errors.append(f"{label}: emitter must contain two finite coordinates inside 768x768")
            if not number(clip.get("scale"), .01, 4):
                errors.append(f"{label}: invalid fixed scale")
            if clip.get("source_count") != 124 or isinstance(clip.get("source_count"), bool):
                errors.append(f"{label}: source_count must match the preserved 124-frame source")
            crop = clip.get("storage_crop")
            if "storage_crop" in clip and not storage_crop_valid(crop):
                errors.append(f"{label}: storage_crop must be four integers inside 768x768 with room for four-pixel padding")
                continue
            if crop is not None and source_root is None:
                warnings.append(f"{label}: crop losslessness not proven; supply --source-root for original-pixel comparison")
            original_clip = archival_actions.get(action)
            verify_emitter = source_root is not None and (crop is not None or "emitter" in clip or isinstance(original_clip, dict) and "emitter" in original_clip)
            if verify_emitter:
                if archival_metadata_error or not isinstance(original_clip, dict):
                    errors.append(f"{label}: cannot verify archival emitter metadata ({archival_metadata_error or 'missing original action'})")
                elif ("emitter" in clip) != ("emitter" in original_clip) or clip.get("emitter") != original_clip.get("emitter"):
                    errors.append(f"{label}: emitter metadata differs from the original action")
            if source_root is not None and crop is not None and isinstance(original_clip, dict):
                unpacked_clip = {key: value for key, value in clip.items() if key != "storage_crop"}
                if unpacked_clip != original_clip:
                    changed = sorted(key for key in set(unpacked_clip) | set(original_clip)
                                     if key not in unpacked_clip or key not in original_clip or unpacked_clip[key] != original_clip[key])
                    errors.append(f"{label}: action metadata differs from archive after removing storage_crop: {', '.join(changed)}")
            frames = clip.get("frames")
            if not isinstance(frames, list) or len(frames) < 2 or len(frames) > 124:
                errors.append(f"{label}: expected 2..124 authored frames")
                continue
            durations = []
            hashes = set()
            entries = []
            filenames = set()
            for index, entry in enumerate(frames):
                frame_label = f"{label}[{index}]"
                if not isinstance(entry, dict):
                    errors.append(f"{frame_label}: frame must be an object")
                    continue
                if any(field in entry for field in ("pivot", "scale", "canvas", "offset", "crop", "storage_crop")):
                    errors.append(f"{frame_label}: per-frame transforms/crops violate the fixed-canvas contract")
                duration = entry.get("duration_ms")
                if not number(duration, 1, 1000):
                    errors.append(f"{frame_label}: invalid duration_ms")
                else:
                    durations.append(duration)
                source = entry.get("source_frame")
                if not number(source, 0, 123) or int(source) != source:
                    errors.append(f"{frame_label}: invalid original source_frame")
                path = safe_path(directory, entry.get("file"))
                if path is None:
                    errors.append(f"{frame_label}: unsafe or missing PNG path")
                    continue
                if path.suffix.lower() != ".png":
                    errors.append(f"{frame_label}: frame must reference PNG")
                if str(path) in filenames:
                    errors.append(f"{frame_label}: duplicate frame file; use duration to hold a pose")
                filenames.add(str(path))
                archival = safe_path(source_root / identity, entry.get("file")) if source_root is not None and crop is not None else None
                evidence = check_png(path, frame_label, errors, frame=True, storage_crop=crop, source_path=archival)
                if crop is not None:
                    cropped_frames += 1
                    source_checked_frames += int(evidence.get("source_verified", False))
                if evidence:
                    hashes.add(evidence["sha256"])
                entries.append({"file": entry.get("file"), **evidence})
                frame_count += 1
            total = sum(durations)
            if not number(clip.get("duration_ms"), 1, 20000) or not math.isclose(total, clip.get("duration_ms", -1), abs_tol=.001):
                errors.append(f"{label}: total duration differs from per-frame timing")
            if action in ("attack", "cast"):
                event = clip.get("event_ms")
                if not number(event, .001, max(.001, total - .001)):
                    errors.append(f"{label}: strike/release event must be inside the action")
            if len(hashes) < 2:
                errors.append(f"{label}: fewer than two distinct images; no authored motion")
            role["actions"][action] = {"frames": entries, "duration_ms": total, "distinct_images": len(hashes),
                                      "pivot": pivot, "scale": clip.get("scale"), "emitter": clip.get("emitter"),
                                      "storage_crop": crop, "review_status": clip.get("review_status")}
    return {"ok": not errors, "release_ready": not errors and not pending and tuple(ids) == IDS and cropped_frames == source_checked_frames,
            "root": str(root.resolve()), "checked_frames": frame_count, "pending_visual_review": pending,
            "source_root": str(source_root.resolve()) if source_root is not None else None,
            "cropped_frames": cropped_frames, "source_checked_frames": source_checked_frames,
            "lossless_storage_verified": cropped_frames == source_checked_frames,
            "errors": errors, "warnings": warnings, "characters": roles}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1] / "assets" / "roster")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--source-root", type=Path, help="Uncropped archival export; verifies each cropped frame's visible RGBA exactly")
    parser.add_argument("--allow-pending-review", action="store_true")
    args = parser.parse_args()
    report = validate(args.root, require_review=not args.allow_pending_review, source_root=args.source_root)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({key: value for key, value in report.items() if key != "characters"}, ensure_ascii=False, indent=2))
    return 0 if report["ok"] and (args.allow_pending_review or report["release_ready"]) else 1


if __name__ == "__main__":
    raise SystemExit(main())
