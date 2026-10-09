"""Select and pack any supported animation and generated-pose combination."""

from __future__ import annotations
import argparse, copy, json, math, os, shutil
from pathlib import Path
from types import SimpleNamespace
from typing import Any
import numpy as np
from .comfy_postprocess import postprocess_settings, remove_background_masks
from .comfy_workflow import (
    ComfyClient,
    configured_animation_frame_counts,
    configured_comfyui_url,
    configured_generation_timeout,
    configured_sprite_box_height,
)
from .io_utils import atomic_write_json, sha256_file, canonical_json
from .media import probe_media, decode_frames
from .sprite_sheet import _premultiplied_resize, _ground
from .sprite_split import (
    ALPHA_NOISE_THRESHOLD,
    SPLIT_ALGORITHMS,
    scale_edges,
    shared_split_edges,
    split_edges,
)

SELECTABLE_ACTIONS = ("idle", "run", "jump", "crouch", "crouch_walk", "walk")
PERIODIC_ACTIONS = ("run", "crouch_walk", "walk")


def _durations(total_ms, count):
    if total_ms < count:
        raise ValueError("action duration is too short for positive millisecond holds")
    result = [
        round((i + 1) * total_ms / count) - round(i * total_ms / count)
        for i in range(count)
    ]
    if any(v <= 0 for v in result):
        raise ValueError("action duration produced a zero-length frame")
    return result


def _sample_frames(
    video: Path, count: int, destination: Path, *, include_last: bool = False
):
    source = probe_media(video)
    first = source.frames[0]
    start = source.time_base.seconds(first.pts)
    end = source.time_base.seconds(source.frames[-1].pts + source.frames[-1].duration)
    duration = end - start
    if count <= 0:
        raise ValueError("frame count must be positive")
    targets = (
        [start + i * duration / (count - 1) for i in range(count)]
        if include_last and count > 1
        else [start + i * duration / count for i in range(count)]
    )
    if include_last:
        targets[-1] = source.time_base.seconds(source.frames[-1].pts)
    chosen = []
    used = set()
    for target in targets:
        frame = min(
            source.frames, key=lambda f: abs(source.time_base.seconds(f.pts) - target)
        )
        if frame.frame_id in used:
            raise ValueError("idle timestamps map to duplicate source frames")
        used.add(frame.frame_id)
        chosen.append(frame)
    decoded = decode_frames(source, destination, [f.frame_id for f in chosen])
    by_id = {f.frame_id: f for f in decoded}
    records = []
    for index, frame in enumerate(chosen):
        source_path = Path(by_id[frame.frame_id].decode_path)
        target = destination / f"frame-{index:04d}-source-{frame.frame_id:06d}.png"
        if source_path != target:
            shutil.move(source_path, target)
        records.append(
            {
                "frame_id": frame.frame_id,
                "pts": frame.pts,
                "duration_ticks": frame.duration,
                "time_seconds": source.time_base.seconds(frame.pts),
                "path": str(target),
            }
        )
    return source, duration, records


def _idle_frames(video: Path, count: int, destination: Path):
    return _sample_frames(video, count, destination)


def _jump_frames(video: Path, count: int, destination: Path):
    return _sample_frames(video, count, destination, include_last=True)


def _crouch_frame(video: Path, destination: Path):
    return _sample_frames(video, 1, destination, include_last=True)


def _webp(frames, path, total_ms, loop=0):
    durations = _durations(total_ms, len(frames))
    temporary = path.with_name(path.name + ".working")
    frames[0].save(
        temporary,
        format="WEBP",
        save_all=True,
        append_images=frames[1:],
        duration=durations,
        loop=loop,
        lossless=True,
        method=6,
        exact=True,
    )
    temporary.replace(path)
    return durations


def _single_frame(video: Path, selector: str | int, destination: Path):
    source = probe_media(video)
    if selector == "first":
        ordinal = 0
    elif selector == "last":
        ordinal = len(source.frames) - 1
    elif isinstance(selector, int) and not isinstance(selector, bool):
        ordinal = selector
    else:
        raise ValueError(
            "single-frame selector must be first, last, or a zero-based integer"
        )
    if not 0 <= ordinal < len(source.frames):
        raise ValueError(
            f"single-frame index {ordinal} is outside the {len(source.frames)} decoded frames"
        )
    frame = source.frames[ordinal]
    decoded = decode_frames(source, destination, [frame.frame_id])[0]
    source_path = Path(decoded.decode_path)
    target = destination / f"frame-0000-source-{frame.frame_id:06d}.png"
    if source_path != target:
        shutil.move(source_path, target)
    record = {
        "frame_id": frame.frame_id,
        "pts": frame.pts,
        "duration_ticks": frame.duration,
        "time_seconds": source.time_base.seconds(frame.pts),
        "path": str(target),
    }
    start = source.time_base.seconds(source.frames[0].pts)
    end = source.time_base.seconds(source.frames[-1].pts + source.frames[-1].duration)
    return source, end - start, [record]


def _background_masks(
    paths, destination, *, server, config, timeout, poll_interval, cache_root=None
):
    from PIL import Image

    if cache_root is not None:
        import hashlib, uuid

        settings = postprocess_settings(config)
        cache_root = Path(cache_root)
        cached = []
        missing = []
        for index, path in enumerate(paths):
            identity = {
                "version": 1,
                "source_sha256": sha256_file(path),
                "model": settings["background_removal_model"],
                "processing": "birefnet-mask-v1",
            }
            key = hashlib.sha256(canonical_json(identity)).hexdigest()
            target = cache_root / f"{key}.png"
            sidecar = target.with_suffix(".json")
            try:
                valid = (
                    target.is_file()
                    and not target.is_symlink()
                    and json.loads(sidecar.read_text()).get("identity") == identity
                    and sha256_file(target)
                    == json.loads(sidecar.read_text()).get("sha256")
                )
            except (OSError, ValueError):
                valid = False
            if valid:
                cached.append(target)
            else:
                cached.append(None)
                missing.append((index, path, target, identity))
        provenance = {
            "model": settings["background_removal_model"],
            "cache_hits": len(paths) - len(missing),
            "cache_misses": len(missing),
        }
        if missing:
            temporary = destination.with_name(
                f".{destination.name}.{uuid.uuid4().hex}.working"
            )
            client = ComfyClient(server or configured_comfyui_url(config))
            try:
                generated, run_provenance = remove_background_masks(
                    client,
                    [item[1] for item in missing],
                    temporary,
                    config_path=config,
                    timeout=timeout,
                    poll_interval=poll_interval,
                )
            finally:
                client.free_if_idle()
            if len(generated) != len(missing):
                raise ValueError(
                    "background mask count does not match requested cache misses"
                )
            cache_root.mkdir(parents=True, exist_ok=True)
            for generated_path, (index, _source, target, identity) in zip(
                generated, missing
            ):
                work = target.with_name(f".{target.name}.{uuid.uuid4().hex}.working")
                shutil.copy2(generated_path, work)
                os.replace(work, target)
                atomic_write_json(
                    target.with_suffix(".json"),
                    {"identity": identity, "sha256": sha256_file(target)},
                )
                cached[index] = target
            shutil.rmtree(temporary, ignore_errors=True)
            provenance.update(run_provenance)
        masks = []
        for path in cached:
            record = json.loads(path.with_suffix(".json").read_text())
            if sha256_file(path) != record.get("sha256"):
                raise ValueError("cached background mask is corrupt")
            with Image.open(path) as image:
                masks.append(np.asarray(image.convert("L"), np.float32) / 255.0)
        return masks, provenance
    client = ComfyClient(server or configured_comfyui_url(config))
    try:
        mask_paths, provenance = remove_background_masks(
            client,
            paths,
            destination,
            config_path=config,
            timeout=timeout,
            poll_interval=poll_interval,
        )
    finally:
        client.free_if_idle()
    masks = []
    for path in mask_paths:
        with Image.open(path) as image:
            masks.append(np.asarray(image.convert("L"), np.float32) / 255.0)
    return masks, provenance


def _combined_alpha_span(frames):
    """Return the horizontal span and area of an animation's union alpha mask."""
    combined = np.maximum.reduce(
        [np.asarray(frame.getchannel("A"), np.uint8) for frame in frames]
    )
    foreground = np.argwhere(combined > 0)
    if not len(foreground):
        return None, 0
    return (int(foreground[:, 1].min()), int(foreground[:, 1].max()) + 1), int(
        np.count_nonzero(combined)
    )


def _source_fields(source):
    if isinstance(source, dict):
        record = source.get("source", source)
        return record["sha256"], record.get("time_base")
    return source.content_sha256, {
        "numerator": source.time_base.numerator,
        "denominator": source.time_base.denominator,
    }


def _pack_selected_frames(
    actions: dict[str, list[dict[str, Any]]],
    poses: dict[str, list[dict[str, Any]]],
    output: Path,
    *,
    action_seconds: dict[str, float],
    action_sources: dict[str, Any],
    action_directories: dict[str, str],
    pose_sources: dict[str, dict[str, Any]],
    pose_directories: dict[str, str],
    conceptual_loops: dict[str, bool] | None = None,
    webp_loops: dict[str, int] | None = None,
    run_ground: tuple[Path, dict[str, Any]] | None = None,
    height: int = 128,
    directions=("right", "left", "back", "front"),
    split_algorithm: str = "blobs",
    server=None,
    config=None,
    timeout: float = 7200.0,
    poll_interval: float = 2.0,
    mask_cache_root: Path | None = None,
):
    """Pack already-selected action frames and still poses into one sheet."""
    from PIL import Image

    if not actions and not poses:
        raise ValueError("at least one action or pose is required")
    if (
        height <= 0
        or len(directions) != 4
        or any(not str(x).strip() for x in directions)
    ):
        raise ValueError("positive height and four directions are required")
    if split_algorithm not in SPLIT_ALGORITHMS:
        raise ValueError(
            f"split algorithm must be one of {', '.join(SPLIT_ALGORITHMS)}"
        )
    conceptual_loops = conceptual_loops or {}
    webp_loops = webp_loops or {}
    entries = [("action", name, records) for name, records in actions.items()] + [
        ("pose", name, records) for name, records in poses.items()
    ]
    if any(not records for _kind, _name, records in entries):
        raise ValueError("selected actions and poses must contain at least one frame")
    arrays = []
    keys = []
    for kind, name, records in entries:
        for index, record in enumerate(records):
            path = Path(record["path"]).resolve()
            with Image.open(path) as image:
                arrays.append(np.asarray(image.convert("RGB"), np.float32) / 255)
            keys.append((kind, name, index, path))
    masks, background_provenance = _background_masks(
        [item[3] for item in keys],
        output / "background-masks",
        server=server,
        config=config,
        timeout=timeout,
        poll_interval=poll_interval,
        cache_root=mask_cache_root,
    )
    if len(masks) != len(arrays):
        raise ValueError("BiRefNet mask count does not match selected frames")
    shared_source_edges = None
    shared_scaled_edges = None
    shared_blobs = []
    combined_mask = None
    prepared_masks = None
    if split_algorithm == "blobs":
        prepared_masks, combined_mask, shared_source_edges, shared_blobs = (
            shared_split_edges(masks, split_algorithm)
        )
        shared_scaled_edges = scale_edges(
            shared_source_edges,
            arrays[0].shape[1],
            round(arrays[0].shape[1] * height / arrays[0].shape[0]),
        )
    panels = {
        (kind, name): [[None] * len(records) for _ in range(4)]
        for kind, name, records in entries
    }
    entry_transforms = {}
    split_records = []
    for mask_index, ((kind, name, index, path), rgb, mask) in enumerate(
        zip(keys, arrays, masks)
    ):
        h, w = rgb.shape[:2]
        if mask.shape != (h, w):
            raise ValueError("BiRefNet mask size does not match source")
        scaled_w = round(w * height / h)
        if scaled_w < 4:
            raise ValueError("scaled image cannot form four views")
        if split_algorithm == "blobs":
            prepared = prepared_masks[mask_index]
            source_edges = shared_source_edges
            blobs = shared_blobs
        else:
            prepared, source_edges, blobs = split_edges(mask, split_algorithm)
        edges = scale_edges(source_edges, w, scaled_w)
        whole = _premultiplied_resize(rgb, prepared, (scaled_w, height))
        entry_transforms[kind, name] = {
            "source_width": w,
            "source_height": h,
            "scaled_width": scaled_w,
            "scaled_height": height,
            "scale": height / h,
            "split_edges": edges,
        }
        for row in range(4):
            panels[kind, name][row][index] = whole.crop(
                (edges[row], 0, edges[row + 1], height)
            )
        split_record = {
            "kind": kind,
            "frame": index,
            "source_edges": source_edges,
            "scaled_edges": edges,
            "blobs": [
                {
                    "area": blob.area,
                    "x0": blob.x0,
                    "y0": blob.y0,
                    "x1": blob.x1,
                    "y1": blob.y1,
                }
                for blob in blobs
            ],
        }
        split_record[kind] = name
        split_records.append(split_record)
    spans = {}
    areas = {}
    for kind, name, _records in entries:
        key = (kind, name)
        spans[key] = []
        areas[key] = []
        for row in range(4):
            span, area = _combined_alpha_span(panels[key][row])
            if span is None:
                raise ValueError(f"{name} direction row {row} has no foreground alpha")
            spans[key].append(span)
            areas[key].append(area)
    cell = (
        max(
            height,
            max(hi - lo for item_spans in spans.values() for lo, hi in item_spans),
        )
        if split_algorithm == "blobs"
        else max(
            height,
            max(
                panel.width for rows in panels.values() for row in rows for panel in row
            ),
        )
    )
    top = (cell - height) // 2
    offsets = {
        key: [round((cell - (hi - lo)) / 2 - lo) for lo, hi in item_spans]
        for key, item_spans in spans.items()
    }
    ranges = {}
    column = 0
    for kind, name, records in entries:
        ranges[kind, name] = [column, column + len(records)]
        column += len(records)
    columns = column
    sheet = Image.new("RGBA", (columns * cell, 4 * cell), (0, 0, 0, 0))
    cells = []
    for row, direction in enumerate(directions):
        column = 0
        for kind, name, records in entries:
            for index, panel in enumerate(panels[kind, name][row]):
                packed = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
                packed.alpha_composite(panel, (offsets[kind, name][row], top))
                sheet.alpha_composite(packed, (column * cell, row * cell))
                record = records[index]
                cell_record = {
                    "row": row,
                    "column": column,
                    "direction": direction,
                    "action_frame" if kind == "action" else "pose_frame": index,
                    "source_frame_id": record["frame_id"],
                    "source_pts": record["pts"],
                    "source_time_seconds": record["time_seconds"],
                    "rect": {
                        "x": column * cell,
                        "y": row * cell,
                        "width": cell,
                        "height": cell,
                    },
                }
                cell_record[kind] = name
                cells.append(cell_record)
                column += 1
    if run_ground is not None:
        run_export, run_summary = run_ground
        ground, evidence = _ground(
            run_summary, json.loads((run_export / "raw_pose.json").read_text())
        )
        origin_y = ground * entry_transforms["action", "run"]["scale"] + top
    else:
        alpha_bottoms = []
        for kind, name, _records in entries:
            for row in range(4):
                for panel in panels[kind, name][row]:
                    alpha = np.asarray(panel.getchannel("A"), np.uint8)
                    foreground_rows = np.flatnonzero(np.any(alpha > 0, axis=1))
                    if len(foreground_rows):
                        alpha_bottoms.append(int(foreground_rows[-1]) + 1)
        if not alpha_bottoms:
            raise ValueError("selected frames have no foreground alpha for origin")
        selected_bottom = max(alpha_bottoms)
        origin_y = top + selected_bottom
        evidence = {
            "method": "selected_alpha_bottom",
            "description": "bottommost foreground alpha row across selected frames and directions",
            "scaled_alpha_bottom_y": selected_bottom,
            "sample_count": len(alpha_bottoms),
        }
    origin = {"x": cell / 2, "y": origin_y, "coordinate_basis": "cell_top_left_pixels"}
    sheet_path = output / f"character-sheet-{height}h.png"
    temporary = sheet_path.with_name(sheet_path.name + ".working")
    sheet.save(temporary, format="PNG")
    temporary.replace(sheet_path)
    action_counts = {name: len(records) for name, records in actions.items()}
    action_ranges = {name: ranges["action", name] for name in actions}
    pose_ranges = {name: ranges["pose", name] for name in poses}
    webps = {}
    timings = {}
    for row, direction in enumerate(directions):
        for action in actions:
            if action_counts[action] == 1 or webp_loops.get(action, 0) is None:
                continue
            start = action_ranges[action][0]
            frames = [
                sheet.crop(
                    (
                        cell * (start + i),
                        row * cell,
                        cell * (start + i + 1),
                        (row + 1) * cell,
                    )
                ).resize((height, height), Image.Resampling.LANCZOS)
                for i in range(action_counts[action])
            ]
            name = f"{action}-{direction}-{height}h.webp"
            timings[f"{action}:{direction}"] = _webp(
                frames,
                output / name,
                round(action_seconds[action] * 1000),
                webp_loops.get(action, 0),
            )
            webps[f"{action}:{direction}"] = name
    action_manifests = {}
    for action, records in actions.items():
        source_sha, time_base = _source_fields(action_sources[action])
        action_manifests[action] = {
            "source_sha256": source_sha,
            "time_base": time_base,
            "duration_seconds": action_seconds[action],
            "frame_count": len(records),
            "looping": conceptual_loops.get(action, action != "crouch"),
            "webp_loop": webp_loops.get(action, 0),
            "frames": [
                {**r, "path": action_directories[action] + "/" + Path(r["path"]).name}
                for r in records
            ],
        }
    pose_manifests = {}
    for pose, records in poses.items():
        pose_manifests[pose] = {
            "source_sha256": pose_sources[pose]["sha256"],
            "frame_count": len(records),
            "looping": False,
            "frames": [
                {**r, "path": pose_directories[pose] + "/" + Path(r["path"]).name}
                for r in records
            ],
        }
    action_offsets = {name: offsets["action", name] for name in actions}
    pose_offsets = {name: offsets["pose", name] for name in poses}
    centering = {
        "basis": "per-animation-direction-combined-alpha",
        "directions": list(directions),
        "animations": {
            name: [
                {
                    "source_span": [*span],
                    "horizontal_offset": offsets["action", name][row],
                    "combined_foreground_pixels": areas["action", name][row],
                }
                for row, span in enumerate(spans["action", name])
            ]
            for name in actions
        },
    }
    if poses:
        centering["poses"] = {
            name: [
                {
                    "source_span": [*span],
                    "horizontal_offset": offsets["pose", name][row],
                    "combined_foreground_pixels": areas["pose", name][row],
                }
                for row, span in enumerate(spans["pose", name])
            ]
            for name in poses
        }
    layout = {
        "rows": 4,
        "columns": columns,
        "cell_size": cell,
        "directions": list(directions),
        "animation_ranges": action_ranges,
    }
    if poses:
        layout["pose_ranges"] = pose_ranges
    manifest = {
        "version": "1.0",
        "sheet": sheet_path.name,
        "layout": layout,
        "origin": origin,
        "webp_origin": {
            "x": height / 2,
            "y": origin_y * height / cell,
            "coordinate_basis": "webp_top_left_pixels",
        },
        "origin_evidence": evidence,
        "animation_horizontal_offsets": action_offsets,
        "horizontal_centering": centering,
        "vertical_padding": {"top": top, "bottom": cell - height - top},
        "transforms": {name: entry_transforms["action", name] for name in actions},
        "splitting": {
            "algorithm": split_algorithm,
            "basis": (
                "combined-selected-frame-alpha"
                if split_algorithm == "blobs"
                else "fixed-quarters"
            ),
            "alpha_noise_threshold": (
                ALPHA_NOISE_THRESHOLD if split_algorithm == "blobs" else None
            ),
            "source_edges": shared_source_edges,
            "scaled_edges": shared_scaled_edges,
            "combined_foreground_pixels": (
                int(np.count_nonzero(combined_mask))
                if combined_mask is not None
                else None
            ),
            "blobs": [
                {
                    "area": blob.area,
                    "x0": blob.x0,
                    "y0": blob.y0,
                    "x1": blob.x1,
                    "y1": blob.y1,
                }
                for blob in shared_blobs
            ],
            "frames": split_records,
        },
        "actions": action_manifests,
        "cells": cells,
        "webps": webps,
        "frame_durations_ms": timings,
        "background_removal": {
            "backend": "ComfyUI API workflow",
            **background_provenance,
        },
    }
    if poses:
        manifest["poses"] = pose_manifests
        manifest["pose_horizontal_offsets"] = pose_offsets
        manifest["pose_transforms"] = {
            name: entry_transforms["pose", name] for name in poses
        }
    atomic_write_json(output / "manifest.json", manifest)
    return manifest


def _pack_character_animations(
    run_export: Path,
    idle_video: Path,
    output: Path,
    *,
    idle_frames: int = 4,
    walk_frames: int = 8,
    jump_frames: int = 8,
    crouch_walk_frames: int = 8,
    jump_video: Path | None = None,
    crouch_video: Path | None = None,
    crouch_walk_export: Path | None = None,
    walk_export: Path | None = None,
    height: int = 128,
    directions=("right", "left", "back", "front"),
    split_algorithm: str = "blobs",
    server=None,
    config=None,
    timeout: float = 7200.0,
    poll_interval: float = 2.0,
):
    run_export = Path(run_export).resolve()
    idle_video = Path(idle_video).resolve()
    output = Path(output).resolve()
    if output.exists():
        raise FileExistsError(f"output already exists: {output}")
    if (
        idle_frames < 2
        or walk_frames < 2
        or jump_frames < 2
        or crouch_walk_frames < 2
        or height <= 0
        or len(directions) != 4
        or any(not str(x).strip() for x in directions)
    ):
        raise ValueError(
            "animation frame counts>=2, positive height, and four directions are required"
        )
    if split_algorithm not in SPLIT_ALGORITHMS:
        raise ValueError(
            f"split algorithm must be one of {', '.join(SPLIT_ALGORITHMS)}"
        )
    run_summary = json.loads((run_export / "summary.json").read_text())
    run_records = run_summary["six_frame_cycle"]["frames"]
    if len(run_records) < 2:
        raise ValueError("run export needs at least two selected frames")
    full_inputs = (jump_video, crouch_video, crouch_walk_export, walk_export)
    if any(value is not None for value in full_inputs) and not all(
        value is not None for value in full_inputs
    ):
        raise ValueError(
            "jump, crouch, crouch-walk, and walk inputs must be supplied together"
        )
    output.mkdir(parents=True)
    idle_dir = output / "idle-frames"
    idle_dir.mkdir()
    idle_source, idle_seconds, idle_records = _idle_frames(
        idle_video, idle_frames, idle_dir
    )
    actions = {
        "idle": idle_records,
        "run": [
            {**r, "path": str((run_export / r["path"]).resolve())} for r in run_records
        ],
    }
    action_seconds = {
        "idle": idle_seconds,
        "run": float(run_summary["period"]["seconds"]),
    }
    action_sources = {"idle": idle_source, "run": run_summary}
    frame_directories = {"idle": "idle-frames", "run": "run-frames"}
    if all(value is not None for value in full_inputs):
        jump_dir = output / "jump-frames"
        jump_dir.mkdir()
        jump_source, jump_seconds, jump_records = _jump_frames(
            Path(jump_video), jump_frames, jump_dir
        )
        crouch_dir = output / "crouch-frames"
        crouch_dir.mkdir()
        crouch_source, crouch_seconds, crouch_records = _crouch_frame(
            Path(crouch_video), crouch_dir
        )
        crouch_walk_summary = json.loads(
            (Path(crouch_walk_export) / "summary.json").read_text()
        )
        crouch_walk_records = crouch_walk_summary["six_frame_cycle"]["frames"]
        walk_summary = json.loads((Path(walk_export) / "summary.json").read_text())
        walk_records = walk_summary["six_frame_cycle"]["frames"]
        if len(crouch_walk_records) != crouch_walk_frames:
            raise ValueError(
                "crouch-walk export frame count does not match crouch_walk_frames"
            )
        if len(walk_records) != walk_frames:
            raise ValueError("walk export frame count does not match walk_frames")
        actions.update(
            {
                "jump": jump_records,
                "crouch": crouch_records,
                "crouch_walk": [
                    {**r, "path": str((Path(crouch_walk_export) / r["path"]).resolve())}
                    for r in crouch_walk_records
                ],
                "walk": [
                    {**r, "path": str((Path(walk_export) / r["path"]).resolve())}
                    for r in walk_records
                ],
            }
        )
        action_seconds.update(
            {
                "jump": jump_seconds,
                "crouch": crouch_seconds,
                "crouch_walk": float(crouch_walk_summary["period"]["seconds"]),
                "walk": float(walk_summary["period"]["seconds"]),
            }
        )
        action_sources.update(
            {
                "jump": jump_source,
                "crouch": crouch_source,
                "crouch_walk": crouch_walk_summary,
                "walk": walk_summary,
            }
        )
        frame_directories.update(
            {
                "jump": "jump-frames",
                "crouch": "crouch-frames",
                "crouch_walk": "crouch-walk-frames",
                "walk": "walk-frames",
            }
        )
    return _pack_selected_frames(
        actions,
        {},
        output,
        action_seconds=action_seconds,
        action_sources=action_sources,
        action_directories=frame_directories,
        pose_sources={},
        pose_directories={},
        run_ground=(run_export, run_summary),
        height=height,
        directions=directions,
        split_algorithm=split_algorithm,
        server=server,
        config=config,
        timeout=timeout,
        poll_interval=poll_interval,
    )


def _pack_selected_character_animations(
    videos: dict[str, Path],
    poses: dict[str, Path],
    periodic_exports: dict[str, Path],
    output: Path,
    *,
    frame_counts: dict[str, int],
    action_policies: dict[str, dict[str, Any]] | None = None,
    conceptual_loops: dict[str, bool] | None = None,
    webp_loops: dict[str, int] | None = None,
    action_order: tuple[str, ...] | None = None,
    height: int = 128,
    directions=("right", "left", "back", "front"),
    split_algorithm: str = "blobs",
    server=None,
    config=None,
    timeout: float = 7200.0,
    poll_interval: float = 2.0,
    cycle_selections: dict[str, str] | None = None,
    mask_cache_root: Path | None = None,
):
    """Select frames from staged artifacts and pass them to the shared packer."""
    from PIL import Image

    output = Path(output).resolve()
    if output.exists():
        raise FileExistsError(f"output already exists: {output}")
    output.mkdir(parents=True)
    policies = action_policies or {}
    actions = {}
    action_seconds = {}
    action_sources = {}
    action_directories = {}
    run_ground = None
    for action in action_order or tuple(videos):
        if action not in videos:
            continue
        directory = action.replace("_", "-") + "-frames"
        action_directories[action] = directory
        policy = policies.get(
            action,
            {
                "method": (
                    "cycle"
                    if action in PERIODIC_ACTIONS
                    else ("single" if action == "crouch" else "uniform")
                ),
                "include_last": action == "jump",
                "frame": "last",
            },
        )
        method = policy["method"]
        if method == "cycle":
            export = Path(periodic_exports[action]).resolve()
            summary = json.loads((export / "summary.json").read_text())
            candidate_id = (cycle_selections or {}).get(
                action, summary.get("system_candidate_id")
            )
            candidate = next(
                (
                    item
                    for item in summary.get("cycle_candidates", [])
                    if item["id"] == candidate_id
                ),
                None,
            )
            if cycle_selections is not None and candidate is None:
                raise ValueError(
                    f"selected cycle candidate is unavailable for {action}"
                )
            records = (
                candidate["frames"]
                if candidate
                else summary["six_frame_cycle"]["frames"]
            )
            selected_summary = copy.deepcopy(summary)
            if candidate:
                selected_summary["six_frame_cycle"] = {
                    "candidate_id": candidate["id"],
                    "start_time_seconds": candidate["start_time_seconds"],
                    "sample_times_seconds": candidate["sample_times_seconds"],
                    "frames": candidate["frames"],
                }
            if len(records) != frame_counts[action]:
                raise ValueError(
                    f"{action} export frame count does not match frame_counts"
                )
            actions[action] = [
                {**record, "path": str((export / record["path"]).resolve())}
                for record in records
            ]
            action_seconds[action] = float(summary["period"]["seconds"])
            action_sources[action] = selected_summary
            if action == "run":
                run_ground = (export, selected_summary)
            continue
        destination = output / directory
        destination.mkdir()
        if method == "uniform":
            source, seconds, records = _sample_frames(
                videos[action],
                frame_counts[action],
                destination,
                include_last=bool(policy.get("include_last", False)),
            )
        elif method == "single":
            source, seconds, records = _single_frame(
                videos[action], policy.get("frame", "last"), destination
            )
        else:
            raise ValueError(f"unsupported selection method {method!r} for {action}")
        actions[action] = records
        action_seconds[action] = seconds
        action_sources[action] = source
    pose_records = {}
    pose_sources = {}
    pose_directories = {}
    if poses:
        destination = output / "pose-frames"
        destination.mkdir()
        for index, (pose, source_path) in enumerate(poses.items()):
            source_path = Path(source_path).resolve()
            target = destination / f"pose-{index:04d}.png"
            with Image.open(source_path) as image:
                image.convert("RGB").save(target, format="PNG")
            pose_records[pose] = [
                {
                    "frame_id": None,
                    "pts": None,
                    "duration_ticks": None,
                    "time_seconds": None,
                    "source_kind": "generated_pose_image",
                    "path": str(target),
                }
            ]
            pose_sources[pose] = {
                "path": str(source_path),
                "sha256": sha256_file(source_path),
            }
            pose_directories[pose] = "pose-frames"
    return _pack_selected_frames(
        actions,
        pose_records,
        output,
        action_seconds=action_seconds,
        action_sources=action_sources,
        action_directories=action_directories,
        pose_sources=pose_sources,
        pose_directories=pose_directories,
        conceptual_loops=conceptual_loops,
        webp_loops=webp_loops,
        run_ground=run_ground,
        height=height,
        directions=directions,
        split_algorithm=split_algorithm,
        server=server,
        config=config,
        timeout=timeout,
        poll_interval=poll_interval,
        mask_cache_root=mask_cache_root,
    )


def build_selected_character_animations(
    videos: dict[str, Path],
    poses: dict[str, Path],
    output: Path,
    *,
    frame_counts: dict[str, int],
    action_policies: dict[str, dict[str, Any]] | None = None,
    conceptual_loops: dict[str, bool] | None = None,
    webp_loops: dict[str, int] | None = None,
    action_order: tuple[str, ...] | None = None,
    height: int = 128,
    directions=("right", "left", "back", "front"),
    split_algorithm: str = "blobs",
    server=None,
    config=None,
    timeout: float = 7200.0,
    poll_interval: float = 2.0,
    min_period: float = 0.35,
    max_period: float = 3.0,
    analysis_cache_root: Path | None = None,
    cycle_selections: dict[str, str] | None = None,
    mask_cache_root: Path | None = None,
    pinned_analyses: dict[str, Path] | None = None,
    analysis_callback=None,
    cycle_selection_origins: dict[str, str] | None = None,
    analysis_stage_ids: dict[str, str] | None = None,
    analysis_started_callback=None,
):
    """Build a package from only the requested staged action videos and poses."""
    from .extract_frames import _worker

    videos = {
        str(name).replace("-", "_"): Path(path).resolve()
        for name, path in videos.items()
    }
    poses = {
        str(name).replace("-", "_"): Path(path).resolve()
        for name, path in poses.items()
    }
    output = Path(output).resolve()
    if not videos and not poses:
        raise ValueError("at least one action or pose is required")
    order = action_order or tuple(
        name for name in SELECTABLE_ACTIONS if name in videos
    ) + tuple(sorted(set(videos) - set(SELECTABLE_ACTIONS)))
    if set(order) != set(videos) or len(order) != len(videos):
        raise ValueError("action_order must contain every selected action exactly once")
    ordered_videos = {name: videos[name] for name in order}
    policies = action_policies or {
        action: {
            "method": (
                "cycle"
                if action in PERIODIC_ACTIONS
                else ("single" if action == "crouch" else "uniform")
            ),
            "include_last": action == "jump",
            "frame": "last",
        }
        for action in ordered_videos
    }
    resolved_conceptual = conceptual_loops or {}
    resolved_webp = webp_loops or {}
    if any(not isinstance(value, bool) for value in resolved_conceptual.values()):
        raise ValueError("conceptual loop values must be booleans")
    if any(
        value is not None
        and (
            isinstance(value, bool)
            or not isinstance(value, int)
            or not 0 <= value <= 65535
        )
        for value in resolved_webp.values()
    ):
        raise ValueError(
            "WebP loop values must be null or integers from 0 through 65535"
        )
    for action in ordered_videos:
        if action not in frame_counts:
            raise ValueError(f"frame_counts is missing {action}")
        count = frame_counts[action]
        if isinstance(count, bool) or not isinstance(count, int):
            raise ValueError(f"{action} frame count must be an integer")
        method = policies.get(action, {}).get("method")
        if method not in {"cycle", "uniform", "single"}:
            raise ValueError(f"unsupported selection method for {action}")
        if method == "single" and count != 1:
            raise ValueError(f"{action} single frame count must be 1")
        if method != "single" and count < 2:
            raise ValueError(f"{action} frame count must be at least 2")
    if (
        height <= 0
        or len(directions) != 4
        or any(not str(item).strip() for item in directions)
    ):
        raise ValueError("positive height and four directions are required")
    if split_algorithm not in SPLIT_ALGORITHMS:
        raise ValueError(
            f"split algorithm must be one of {', '.join(SPLIT_ALGORITHMS)}"
        )
    periodic_selected = any(
        policies[action]["method"] == "cycle" for action in ordered_videos
    )
    if periodic_selected and not (
        math.isfinite(min_period)
        and math.isfinite(max_period)
        and 0 < min_period < max_period
    ):
        raise ValueError(
            "finite period bounds must satisfy 0 < min_period < max_period"
        )
    settings = postprocess_settings(config)
    request = {
        "mode": "selected",
        "videos": {
            action: {"path": str(path), "sha256": sha256_file(path)}
            for action, path in ordered_videos.items()
        },
        "poses": {
            pose: {"path": str(path), "sha256": sha256_file(path)}
            for pose, path in poses.items()
        },
        "frame_counts": {action: frame_counts[action] for action in ordered_videos},
        "action_policies": policies,
        "conceptual_loops": resolved_conceptual,
        "webp_loops": resolved_webp,
        "action_order": list(order),
        "height": height,
        "directions": list(directions),
        "split_algorithm": split_algorithm,
        "background_removal_model": settings["background_removal_model"],
    }
    if periodic_selected:
        request.update(
            {
                "min_period": min_period,
                "max_period": max_period,
                "sdpose_checkpoint": settings["sdpose_checkpoint"],
            }
        )
    animated = [
        action
        for action in ordered_videos
        if policies[action]["method"] != "single"
        and frame_counts[action] > 1
        and resolved_webp.get(action, 0) is not None
    ]
    expected = [
        output / f"{action}-{direction}-{height}h.webp"
        for direction in directions
        for action in animated
    ]
    if (
        output.is_dir()
        and (output / "manifest.json").is_file()
        and (output / f"character-sheet-{height}h.png").is_file()
        and all(path.is_file() for path in expected)
    ):
        existing = json.loads((output / "manifest.json").read_text())
        if existing.get("request") == request:
            return existing
        raise FileExistsError(
            f"complete output exists for different inputs or settings: {output}"
        )
    if output.exists():
        raise FileExistsError(f"output exists but is incomplete: {output}")
    stage = output.with_name(output.name + f".working-{os.getpid()}")
    package = stage / "package"
    periodic_exports = {
        action: stage / (action.replace("_", "-") + "-extraction")
        for action in ordered_videos
        if policies[action]["method"] == "cycle"
    }
    try:
        for action, export in list(periodic_exports.items()):
            if analysis_stage_ids and action in analysis_stage_ids:
                from .execution_hooks import set_activity_stage

                set_activity_stage(analysis_stage_ids[action])
            if analysis_started_callback is not None:
                analysis_started_callback(action)
            if pinned_analyses is not None:
                if action not in pinned_analyses:
                    raise ValueError(f"pinned cycle analysis is missing {action}")
                periodic_exports[action] = Path(pinned_analyses[action]).resolve()
                from .cycle_review import selected_cycle_records

                selected_cycle_records(
                    periodic_exports[action], (cycle_selections or {}).get(action)
                )
                if json.loads(
                    (periodic_exports[action] / "summary.json").read_text()
                ).get("source", {}).get("sha256") != sha256_file(
                    ordered_videos[action]
                ):
                    raise ValueError(
                        f"pinned cycle analysis source differs for {action}"
                    )
            elif analysis_cache_root is not None:
                from .cycle_review import ensure_cycle_analysis

                periodic_exports[action] = ensure_cycle_analysis(
                    ordered_videos[action],
                    Path(analysis_cache_root),
                    frame_count=frame_counts[action],
                    server=server,
                    config=config,
                    timeout=timeout,
                    poll_interval=poll_interval,
                )
            else:
                _worker(
                    SimpleNamespace(
                        input=str(ordered_videos[action]),
                        output=str(export),
                        crop=None,
                        views=4,
                        view_index=3,
                        server=server,
                        config=config,
                        timeout=timeout,
                        poll_interval=poll_interval,
                        min_period=min_period,
                        max_period=max_period,
                        frame_count=frame_counts[action],
                        sprite_height=height,
                        frames_only=True,
                        directions=",".join(directions),
                        split_algorithm=split_algorithm,
                    )
                )
            if analysis_callback is not None:
                analysis_callback(action, periodic_exports[action])
        if periodic_exports:
            from .execution_hooks import set_activity_stage

            set_activity_stage(None)
        manifest = _pack_selected_character_animations(
            ordered_videos,
            poses,
            periodic_exports,
            package,
            frame_counts=frame_counts,
            action_policies=policies,
            conceptual_loops=conceptual_loops,
            webp_loops=webp_loops,
            action_order=tuple(order),
            height=height,
            directions=directions,
            split_algorithm=split_algorithm,
            server=server,
            config=config,
            timeout=timeout,
            poll_interval=poll_interval,
            cycle_selections=cycle_selections,
            mask_cache_root=mask_cache_root,
        )
        for action, export in periodic_exports.items():
            directory = action.replace("_", "-")
            selected_summary = json.loads((export / "summary.json").read_text())
            selected_id = (cycle_selections or {}).get(
                action, selected_summary.get("system_candidate_id")
            )
            selected_candidate = next(
                (
                    item
                    for item in selected_summary.get("cycle_candidates", [])
                    if item["id"] == selected_id
                ),
                None,
            )
            source_frames = export / (
                Path(selected_candidate["frames"][0]["path"]).parent
                if selected_candidate
                else Path("frames")
            )
            shutil.copytree(source_frames, package / f"{directory}-frames")
            shutil.copytree(
                export, package / "timing-evidence" / f"{directory}-extraction"
            )
            evidence_summary = copy.deepcopy(selected_summary)
            if selected_candidate:
                evidence_summary["six_frame_cycle"] = {
                    "candidate_id": selected_candidate["id"],
                    "start_time_seconds": selected_candidate["start_time_seconds"],
                    "sample_times_seconds": selected_candidate["sample_times_seconds"],
                    "frames": selected_candidate["frames"],
                }
            atomic_write_json(
                package
                / "timing-evidence"
                / f"{directory}-extraction"
                / "summary.json",
                evidence_summary,
            )
            manifest.setdefault("cycle_selections", {})[action] = {
                "analysis_id": selected_summary.get("analysis_id"),
                "sample_set_id": selected_summary.get("sample_set_id"),
                "analysis_path": str(export),
                "candidate_id": selected_id,
                "system_candidate_id": selected_summary.get("system_candidate_id"),
                "origin": (cycle_selection_origins or {}).get(
                    action,
                    "user" if (cycle_selections or {}).get(action) else "automatic",
                ),
            }
        manifest["request"] = request
        manifest["execution_status"] = "exported"
        manifest["quality_evaluated"] = False
        manifest["source_videos"] = {
            action: {"path": str(path), "sha256": request["videos"][action]["sha256"]}
            for action, path in ordered_videos.items()
        }
        manifest["source_poses"] = {
            pose: {"path": str(path), "sha256": request["poses"][pose]["sha256"]}
            for pose, path in poses.items()
        }
        atomic_write_json(package / "manifest.json", manifest)
        atomic_write_json(package / f"character-sheet-{height}h.json", manifest)
        output.parent.mkdir(parents=True, exist_ok=True)
        os.replace(package, output)
        return manifest
    finally:
        shutil.rmtree(stage, ignore_errors=True)


def build_character_animations(
    run_video: Path,
    idle_video: Path,
    output: Path,
    *,
    jump_video: Path | None = None,
    crouch_video: Path | None = None,
    crouch_walk_video: Path | None = None,
    walk_video: Path | None = None,
    run_frames: int = 8,
    walk_frames: int = 8,
    idle_frames: int = 4,
    jump_frames: int = 8,
    crouch_walk_frames: int = 8,
    height: int = 128,
    directions=("right", "left", "back", "front"),
    split_algorithm: str = "blobs",
    server=None,
    config=None,
    timeout: float = 7200.0,
    poll_interval: float = 2.0,
):
    from .extract_frames import _worker

    run_video = Path(run_video).resolve()
    idle_video = Path(idle_video).resolve()
    output = Path(output).resolve()
    full_inputs = (jump_video, crouch_video, crouch_walk_video, walk_video)
    if any(value is not None for value in full_inputs) and not all(
        value is not None for value in full_inputs
    ):
        raise ValueError(
            "jump, crouch, crouch-walk, and walk videos must be supplied together"
        )
    full = all(value is not None for value in full_inputs)
    animated_actions = (
        ("idle", "run", "jump", "crouch_walk", "walk") if full else ("idle", "run")
    )
    expected = [
        output / f"{a}-{d}-{height}h.webp" for d in directions for a in animated_actions
    ]
    settings = postprocess_settings(config)
    videos = {"run": run_video, "idle": idle_video}
    if full:
        videos.update(
            {
                "jump": Path(jump_video).resolve(),
                "crouch": Path(crouch_video).resolve(),
                "crouch_walk": Path(crouch_walk_video).resolve(),
                "walk": Path(walk_video).resolve(),
            }
        )
    request = {
        "videos": {
            action: {"path": str(path), "sha256": sha256_file(path)}
            for action, path in videos.items()
        },
        "run_frames": run_frames,
        "walk_frames": walk_frames if full else None,
        "idle_frames": idle_frames,
        "jump_frames": jump_frames if full else None,
        "crouch_walk_frames": crouch_walk_frames if full else None,
        "height": height,
        "directions": list(directions),
        "split_algorithm": split_algorithm,
        "sdpose_checkpoint": settings["sdpose_checkpoint"],
        "background_removal_model": settings["background_removal_model"],
    }
    if (
        output.is_dir()
        and (output / "manifest.json").is_file()
        and (output / f"character-sheet-{height}h.png").is_file()
        and all(path.is_file() for path in expected)
    ):
        existing = json.loads((output / "manifest.json").read_text())
        if existing.get("request") == request:
            return existing
        raise FileExistsError(
            f"complete output exists for different inputs or settings: {output}"
        )
    if output.exists():
        raise FileExistsError(f"output exists but is incomplete: {output}")
    if (
        run_frames < 2
        or walk_frames < 2
        or idle_frames < 2
        or jump_frames < 2
        or crouch_walk_frames < 2
    ):
        raise ValueError("animation frame counts must be at least 2")
    stage = output.with_name(output.name + f".working-{os.getpid()}")
    run_export = stage / "run-extraction"
    crouch_walk_export = stage / "crouch-walk-extraction"
    walk_export = stage / "walk-extraction"
    package = stage / "package"
    try:
        _worker(
            SimpleNamespace(
                input=str(run_video),
                output=str(run_export),
                crop=None,
                views=4,
                view_index=3,
                server=server,
                config=config,
                timeout=timeout,
                poll_interval=poll_interval,
                min_period=0.35,
                max_period=3.0,
                frame_count=run_frames,
                sprite_height=height,
                frames_only=True,
                directions=",".join(directions),
                split_algorithm=split_algorithm,
            )
        )
        if full:
            _worker(
                SimpleNamespace(
                    input=str(videos["crouch_walk"]),
                    output=str(crouch_walk_export),
                    crop=None,
                    views=4,
                    view_index=3,
                    server=server,
                    config=config,
                    timeout=timeout,
                    poll_interval=poll_interval,
                    min_period=0.35,
                    max_period=3.0,
                    frame_count=crouch_walk_frames,
                    sprite_height=height,
                    frames_only=True,
                    directions=",".join(directions),
                    split_algorithm=split_algorithm,
                )
            )
            _worker(
                SimpleNamespace(
                    input=str(videos["walk"]),
                    output=str(walk_export),
                    crop=None,
                    views=4,
                    view_index=3,
                    server=server,
                    config=config,
                    timeout=timeout,
                    poll_interval=poll_interval,
                    min_period=0.35,
                    max_period=3.0,
                    frame_count=walk_frames,
                    sprite_height=height,
                    frames_only=True,
                    directions=",".join(directions),
                    split_algorithm=split_algorithm,
                )
            )
        manifest = _pack_character_animations(
            run_export,
            idle_video,
            package,
            idle_frames=idle_frames,
            walk_frames=walk_frames,
            jump_frames=jump_frames,
            crouch_walk_frames=crouch_walk_frames,
            jump_video=videos.get("jump"),
            crouch_video=videos.get("crouch"),
            crouch_walk_export=crouch_walk_export if full else None,
            walk_export=walk_export if full else None,
            height=height,
            directions=directions,
            split_algorithm=split_algorithm,
            server=server,
            config=config,
            timeout=timeout,
            poll_interval=poll_interval,
        )
        shutil.copytree(run_export / "frames", package / "run-frames")
        shutil.copytree(run_export, package / "timing-evidence" / "run-extraction")
        if full:
            shutil.copytree(
                crouch_walk_export / "frames", package / "crouch-walk-frames"
            )
            shutil.copytree(
                crouch_walk_export,
                package / "timing-evidence" / "crouch-walk-extraction",
            )
            shutil.copytree(walk_export / "frames", package / "walk-frames")
            shutil.copytree(
                walk_export, package / "timing-evidence" / "walk-extraction"
            )
        manifest["request"] = request
        manifest["execution_status"] = "exported"
        manifest["quality_evaluated"] = False
        manifest["source_videos"] = {
            action: {"path": str(path), "sha256": request["videos"][action]["sha256"]}
            for action, path in videos.items()
        }
        atomic_write_json(package / "manifest.json", manifest)
        atomic_write_json(package / f"character-sheet-{height}h.json", manifest)
        output.parent.mkdir(parents=True, exist_ok=True)
        os.replace(package, output)
        return manifest
    finally:
        shutil.rmtree(stage, ignore_errors=True)


def main(argv=None):
    p = argparse.ArgumentParser()
    p.add_argument("run_video")
    p.add_argument("idle_video")
    p.add_argument("--output", required=True)
    p.add_argument("--run-frames", type=int)
    p.add_argument("--idle-frames", type=int)
    p.add_argument("--sprite-box-height", "--height", dest="height", type=int)
    p.add_argument("--directions", default="right,left,back,front")
    p.add_argument("--split-algorithm", choices=SPLIT_ALGORITHMS, default="blobs")
    p.add_argument("--server")
    p.add_argument("--config", action="append", metavar="PATH")
    a = p.parse_args(argv)
    config = [Path(path).resolve() for path in a.config] if a.config else None
    height = configured_sprite_box_height(config) if a.height is None else a.height
    frames = configured_animation_frame_counts(config)
    timeout = configured_generation_timeout(config)
    return build_character_animations(
        Path(a.run_video),
        Path(a.idle_video),
        Path(a.output),
        run_frames=frames["run"] if a.run_frames is None else a.run_frames,
        idle_frames=frames["idle"] if a.idle_frames is None else a.idle_frames,
        height=height,
        directions=tuple(x.strip() for x in a.directions.split(",")),
        split_algorithm=a.split_algorithm,
        server=a.server,
        config=config,
        timeout=timeout,
    )


if __name__ == "__main__":
    main()
