"""Publish lossless, action-wide alpha crops for the Godot NPC roster.

The approved 768x768 export is read-only. Every action gets one union alpha
bounds rectangle plus four transparent pixels on each side. The runtime
manifest retains the virtual canvas, pivot, scale and frame timing and adds
only ``storage_crop`` to each action. Godot AtlasTexture.margin supplies the
missing transparent canvas without allocating a full-size GPU texture.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import tempfile
from typing import Any

from PIL import Image

HERE = Path(__file__).resolve().parent
DEFAULT_SOURCE = HERE / "h3-runtime" / "npc-roster-v1" / "export"
DEFAULT_DESTINATION = HERE.parent / "godot-belt-map" / "assets" / "roster"
CHARACTERS = ("scout", "caster", "elite", "boss", "serin")


def _json(path: Path, default: Any = None) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig")) if path.is_file() else default


def _atomic_bytes(path: Path, contents: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(contents)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def _safe_file(directory: Path, relative: str) -> Path:
    if not isinstance(relative, str) or not relative or "\\" in relative:
        raise ValueError(f"Invalid relative asset name: {relative!r}")
    path = (directory / relative).resolve()
    if not path.is_relative_to(directory.resolve()) or path == directory.resolve():
        raise ValueError(f"Asset escapes character directory: {relative!r}")
    return path


def _digest(contents: bytes) -> str:
    return hashlib.sha256(contents).hexdigest()


def pack_character(
    character_id: str,
    source_root: Path | str = DEFAULT_SOURCE,
    destination_root: Path | str = DEFAULT_DESTINATION,
    *,
    padding: int = 4,
    reviewed_only: bool = True,
    dry_run: bool = False,
) -> dict[str, Any]:
    """Publish one character; repeat calls reuse verified, unchanged crops.

    The producer may call this directly after marking an action reviewed.
    Unreviewed actions are omitted, and no source file is changed or removed.
    Run Godot's normal import after publication before export or memory tests.
    """
    if character_id not in CHARACTERS:
        raise ValueError(f"Unknown character: {character_id}")
    if not isinstance(padding, int) or padding < 4:
        raise ValueError("Runtime packing requires at least four transparent padding pixels")
    source = Path(source_root).resolve() / character_id
    destination = Path(destination_root).resolve() / character_id
    if destination == source or destination.is_relative_to(source) or source.is_relative_to(destination):
        raise ValueError("Source export and runtime destination must be separate directories")
    original = _json(source / "animation.json")
    if not isinstance(original, dict):
        return {"id": character_id, "status": "skipped_no_manifest", "actions": {}}
    if original.get("canvas") != [768, 768] or not isinstance(original.get("actions"), dict):
        raise ValueError(f"{character_id}: source must be a 768x768 authored export")
    result_manifest = deepcopy(original)
    result_manifest["actions"] = {}
    previous = _json(destination / "runtime-pack-report.json", {})
    previous_manifest = _json(destination / "animation.json", {})
    report: dict[str, Any] = {"version": 1, "id": character_id, "status": "packed", "padding": padding,
        "generated_utc": datetime.now(timezone.utc).isoformat(), "actions": {}, "skipped_actions": []}
    pending_files: dict[Path, bytes] = {}
    canvas = tuple(original["canvas"])
    for action, clip in original["actions"].items():
        if reviewed_only and clip.get("review_status") != "visually_reviewed":
            report["skipped_actions"].append(action)
            continue
        if "storage_crop" in clip:
            raise ValueError(f"{character_id}/{action}: source is already packed; use the untouched export")
        if not isinstance(clip.get("frames"), list) or not clip["frames"]:
            raise ValueError(f"{character_id}/{action}: missing frames")
        files: dict[str, bytes] = {}
        for entry in clip["frames"]:
            relative = entry["file"]
            if not isinstance(relative, str) or not relative.startswith(action + "/"):
                raise ValueError(f"{character_id}/{action}: frame path must remain in its action directory")
            if relative in files:
                continue
            files[relative] = _safe_file(source, relative).read_bytes()
        source_hashes = {name: _digest(contents) for name, contents in files.items()}
        fingerprint = _digest(json.dumps({"clip": clip, "source_hashes": source_hashes, "padding": padding},
            ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8"))
        cached = previous.get("actions", {}).get(action, {})
        old_clip = previous_manifest.get("actions", {}).get(action, {})
        cache_valid = cached.get("fingerprint") == fingerprint and old_clip.get("storage_crop") == cached.get("storage_crop")
        if cache_valid:
            for name, expected_hash in cached.get("packed_hashes", {}).items():
                existing = _safe_file(destination, name)
                if not existing.is_file() or _digest(existing.read_bytes()) != expected_hash:
                    cache_valid = False
                    break
            cache_valid = cache_valid and set(cached.get("packed_hashes", {})) == set(files)
        if cache_valid:
            result_manifest["actions"][action] = dict(deepcopy(clip), storage_crop=list(cached["storage_crop"]))
            report["actions"][action] = dict(deepcopy(cached), reused=True)
            continue
        images: dict[str, Image.Image] = {}
        union: tuple[int, int, int, int] | None = None
        for name, contents in files.items():
            with Image.open(io.BytesIO(contents)) as opened:
                image = opened.convert("RGBA")
            if image.size != canvas:
                raise ValueError(f"{character_id}/{name}: expected {canvas}, got {image.size}")
            bbox = image.getchannel("A").getbbox()  # Every alpha > 0 pixel is preserved.
            if bbox is None:
                raise ValueError(f"{character_id}/{name}: a completely empty frame cannot be published")
            union = bbox if union is None else (min(union[0], bbox[0]), min(union[1], bbox[1]), max(union[2], bbox[2]), max(union[3], bbox[3]))
            images[name] = image
        assert union is not None
        if union[0] < padding or union[1] < padding or union[2] > canvas[0] - padding or union[3] > canvas[1] - padding:
            raise ValueError(f"{character_id}/{action}: visible alpha reaches within {padding}px of source edge; review the source before publishing")
        bounds = (union[0] - padding, union[1] - padding, union[2] + padding, union[3] + padding)
        crop = [bounds[0], bounds[1], bounds[2] - bounds[0], bounds[3] - bounds[1]]
        packed_hashes: dict[str, str] = {}
        for name, image in images.items():
            encoded = io.BytesIO()
            image.crop(bounds).save(encoded, format="PNG", optimize=True)
            contents = encoded.getvalue()
            packed_hashes[name] = _digest(contents)
            pending_files[_safe_file(destination, name)] = contents
        original_bytes = len(files) * canvas[0] * canvas[1] * 4
        packed_bytes = len(files) * crop[2] * crop[3] * 4
        report["actions"][action] = {"fingerprint": fingerprint, "frames": len(files), "storage_crop": crop,
            "source_alpha_union": list(union), "source_rgba_bytes": original_bytes, "packed_rgba_bytes": packed_bytes,
            "saved_rgba_bytes": original_bytes - packed_bytes, "saved_fraction": 1.0 - packed_bytes / original_bytes,
            "source_hashes": source_hashes, "packed_hashes": packed_hashes, "reused": False}
        result_manifest["actions"][action] = dict(deepcopy(clip), storage_crop=crop)
    report["source_rgba_bytes"] = sum(entry["source_rgba_bytes"] for entry in report["actions"].values())
    report["packed_rgba_bytes"] = sum(entry["packed_rgba_bytes"] for entry in report["actions"].values())
    report["saved_rgba_bytes"] = report["source_rgba_bytes"] - report["packed_rgba_bytes"]
    if not dry_run:
        portrait = str(original.get("portrait", "portrait.png"))
        pending_files[_safe_file(destination, portrait)] = _safe_file(source, portrait).read_bytes()
        # Validate and encode every accepted action before touching published
        # files. A later source-edge failure cannot leave earlier clips half-updated.
        for path, contents in pending_files.items():
            _atomic_bytes(path, contents)
        # Publish the manifest last so it never references unfinished new files.
        _atomic_bytes(destination / "animation.json", json.dumps(result_manifest, indent=2, ensure_ascii=False).encode("utf-8"))
        _atomic_bytes(destination / "runtime-pack-report.json", json.dumps(report, indent=2, ensure_ascii=False).encode("utf-8"))
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--characters", nargs="+", choices=CHARACTERS, default=list(CHARACTERS))
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--destination", type=Path, default=DEFAULT_DESTINATION)
    parser.add_argument("--padding", type=int, default=4)
    parser.add_argument("--dry-run", action="store_true")
    arguments = parser.parse_args()
    reports = [pack_character(key, arguments.source, arguments.destination, padding=arguments.padding, dry_run=arguments.dry_run)
        for key in arguments.characters]
    summary = [{"id": item["id"], "status": item["status"], "actions": list(item["actions"]),
        "source_rgba_bytes": item.get("source_rgba_bytes", 0), "packed_rgba_bytes": item.get("packed_rgba_bytes", 0),
        "saved_rgba_bytes": item.get("saved_rgba_bytes", 0)} for item in reports]
    print(json.dumps(summary, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
