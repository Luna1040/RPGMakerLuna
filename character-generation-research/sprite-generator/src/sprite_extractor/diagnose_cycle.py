"""Bounded DWPose cadence diagnostic for the synchronized four-view fixture.

`extract` performs model inference and writes reusable raw observations.
`analyze` is model-free: it fits one shared period to the two named ankle Y
waveforms and exports original source frames for inspection.
"""

from __future__ import annotations

import argparse
import importlib
import json
import math
import shutil
import sys
import hashlib
from pathlib import Path
from typing import Any

from .io_utils import atomic_write_json, sha256_file
from .media import decode_frames, probe_media

RIGHT_ANKLE, LEFT_ANKLE = 10, 13
BODY_NAMES = (
    "nose",
    "neck",
    "right_shoulder",
    "right_elbow",
    "right_wrist",
    "left_shoulder",
    "left_elbow",
    "left_wrist",
    "right_hip",
    "right_knee",
    "right_ankle",
    "left_hip",
    "left_knee",
    "left_ankle",
    "right_eye",
    "left_eye",
    "right_ear",
    "left_ear",
)
EXTRA_FOOT_NAMES = (
    "left_big_toe",
    "left_small_toe",
    "left_heel",
    "right_big_toe",
    "right_small_toe",
    "right_heel",
)


def _model(repo: Path, detector: Path | None, pose: Path, device: str):
    import_root = (
        repo / "src" if (repo / "src" / "custom_controlnet_aux").is_dir() else repo
    )
    sys.path.insert(0, str(import_root.resolve()))
    wholebody = importlib.import_module(
        "custom_controlnet_aux.dwpose.wholebody"
    ).Wholebody
    return (
        wholebody(
            str(detector) if detector else None, str(pose), torchscript_device=device
        ),
        import_root,
    )


def extract(args: argparse.Namespace) -> None:
    import numpy as np
    from PIL import Image

    source = probe_media(args.source)
    output = Path(args.output).resolve()
    if output.exists():
        raise FileExistsError(f"diagnostic output already exists: {output}")
    decoded = output / "decoded"
    frames = decode_frames(source, decoded)
    detector = None if args.no_detector else Path(args.detector)
    model, import_root = _model(Path(args.repo), detector, Path(args.pose), args.device)
    x0, x1, y0, y1 = args.crop
    observations = []
    try:
        inference_mode = importlib.import_module("torch").inference_mode
    except ImportError:
        from contextlib import nullcontext

        inference_mode = nullcontext
    for frame in frames:
        with Image.open(frame.decode_path) as image:
            crop = np.asarray(image.convert("RGB"))[y0:y1, x0:x1]
        with inference_mode():
            result = model(crop.copy())
        people = [] if result is None else list(result)
        person = (
            max(people, key=lambda points: float(np.nansum(np.asarray(points)[:18, 2])))
            if people
            else None
        )
        points = []
        raw_points = []
        if person is not None:
            array = np.asarray(person)
            for index, row in enumerate(array):
                px, py, score = (float(v) for v in row[:3])
                raw_points.append(
                    {
                        "index": index,
                        "crop_x": px,
                        "crop_y": py,
                        "full_x": px + x0,
                        "full_y": py + y0,
                        "raw_score": score,
                    }
                )
            for index, name in enumerate(BODY_NAMES + EXTRA_FOOT_NAMES):
                px, py, score = (float(v) for v in array[index, :3])
                points.append(
                    {
                        "index": index,
                        "name": name,
                        "crop_x": px,
                        "crop_y": py,
                        "full_x": px + x0,
                        "full_y": py + y0,
                        "raw_score": score,
                    }
                )
        observations.append(
            {
                "frame_id": frame.frame_id,
                "pts": frame.pts,
                "time_seconds": source.time_base.seconds(frame.pts),
                "duration_ticks": frame.duration,
                "points": points,
                "raw_points": raw_points,
            }
        )
    atomic_write_json(
        output / "raw_pose.json",
        {
            "version": "1.0",
            "source": {
                "path": source.path,
                "sha256": source.content_sha256,
                "width": source.width,
                "height": source.height,
                "time_base": {
                    "numerator": source.time_base.numerator,
                    "denominator": source.time_base.denominator,
                },
                "frame_count": len(source.frames),
            },
            "crop": {
                "x0": x0,
                "x1": x1,
                "y0": y0,
                "y1": y1,
                "coordinate_basis": "canonical full-image pixels",
            },
            "model": {
                "name": "DWPose Wholebody",
                "repo": str(Path(args.repo).resolve()),
                "import_root": str(import_root.resolve()),
                "detector": str(detector.resolve()) if detector else None,
                "detector_sha256": sha256_file(detector) if detector else None,
                "detector_mode": (
                    "configured_yolox" if detector else "known_single_subject_full_crop"
                ),
                "pose": str(Path(args.pose).resolve()),
                "pose_sha256": sha256_file(args.pose),
                "device": args.device,
            },
            "landmark_contract": {
                "right_ankle": RIGHT_ANKLE,
                "left_ankle": LEFT_ANKLE,
                "identity_rule": "named DWPose outputs; never sorted by X",
            },
            "observations": observations,
        },
    )


def extract_sdpose(args: argparse.Namespace) -> None:
    """Run SDPose through the configured ComfyUI API workflow."""
    from PIL import Image
    from .comfy_postprocess import extract_sdpose as extract_sdpose_via_comfy
    from .comfy_workflow import (
        ComfyClient,
        configured_comfyui_url,
        configured_generation_timeout,
    )

    source = probe_media(args.source)
    output = Path(args.output).resolve()
    if output.exists():
        raise FileExistsError(f"diagnostic output already exists: {output}")
    frames = decode_frames(source, output / "decoded")
    x0, x1, y0, y1 = args.crop
    crop_dir = output / "sdpose-inputs"
    crop_dir.mkdir()
    crops = []
    for frame in frames:
        target = crop_dir / f"frame-{frame.frame_id:06d}.png"
        with Image.open(frame.decode_path) as image:
            image.convert("RGB").crop((x0, y0, x1, y1)).save(target)
        crops.append(target)
    config_path = getattr(args, "config", None)
    server = getattr(args, "server", None) or configured_comfyui_url(config_path)
    timeout = getattr(args, "timeout", None)
    if timeout is None:
        timeout = configured_generation_timeout(config_path)
    if not math.isfinite(timeout) or timeout <= 0:
        raise ValueError("timeout must be finite and positive")
    client = ComfyClient(server)
    try:
        openpose, provenance = extract_sdpose_via_comfy(
            client,
            crops,
            config_path=config_path,
            timeout=timeout,
            poll_interval=getattr(args, "poll_interval", 2.0),
        )
    finally:
        client.free_if_idle()
    if len(openpose) != len(frames):
        raise RuntimeError(
            f"SDPose returned {len(openpose)} frames for {len(frames)} inputs"
        )
    observations = []
    for timing, pose_frame in zip(frames, openpose):
        people = pose_frame.get("people", [])
        person = people[0] if people else None
        points = []
        raw_points = []
        if person:
            groups = (
                ("pose_keypoints_2d", 18),
                ("foot_keypoints_2d", 6),
                ("face_keypoints_2d", 70),
                ("hand_right_keypoints_2d", 21),
                ("hand_left_keypoints_2d", 21),
            )
            index = 0
            for key, count in groups:
                flat = person.get(key, [])
                if not isinstance(flat, list) or len(flat) != count * 3:
                    raise ValueError(
                        f"SDPose returned {len(flat) if isinstance(flat,list) else 0} {key} values; expected {count*3}"
                    )
                values = [
                    flat[offset : offset + 3] for offset in range(0, len(flat), 3)
                ]
                for px, py, score in values:
                    raw_points.append(
                        {
                            "index": index,
                            "group": key,
                            "crop_x": float(px),
                            "crop_y": float(py),
                            "full_x": float(px) + x0,
                            "full_y": float(py) + y0,
                            "raw_score": float(score),
                        }
                    )
                    index += 1
            named = [
                person["pose_keypoints_2d"][offset : offset + 3]
                for offset in range(0, 54, 3)
            ] + [
                person["foot_keypoints_2d"][offset : offset + 3]
                for offset in range(0, 18, 3)
            ]
            for index, name in enumerate(BODY_NAMES + EXTRA_FOOT_NAMES):
                px, py, score = named[index]
                points.append(
                    {
                        "index": index,
                        "name": name,
                        "crop_x": float(px),
                        "crop_y": float(py),
                        "full_x": float(px) + x0,
                        "full_y": float(py) + y0,
                        "raw_score": float(score),
                    }
                )
        observations.append(
            {
                "frame_id": timing.frame_id,
                "pts": timing.pts,
                "time_seconds": source.time_base.seconds(timing.pts),
                "duration_ticks": timing.duration,
                "points": points,
                "raw_points": raw_points,
            }
        )
    atomic_write_json(
        output / "raw_pose.json",
        {
            "version": "1.0",
            "source": {
                "path": source.path,
                "sha256": source.content_sha256,
                "width": source.width,
                "height": source.height,
                "time_base": {
                    "numerator": source.time_base.numerator,
                    "denominator": source.time_base.denominator,
                },
                "frame_count": len(source.frames),
            },
            "crop": {
                "x0": x0,
                "x1": x1,
                "y0": y0,
                "y1": y1,
                "coordinate_basis": "canonical full-image pixels",
            },
            "model": {
                "name": "SDPose-OOD",
                "implementation": "ComfyUI API workflow",
                "server": server,
                "detector": None,
                "detector_mode": "known_single_subject_full_crop",
                **provenance,
            },
            "landmark_contract": {
                "right_ankle": RIGHT_ANKLE,
                "left_ankle": LEFT_ANKLE,
                "layout": "native SDPose OpenPose conversion",
                "identity_rule": "named SDPose outputs; never sorted by X",
            },
            "observations": observations,
        },
    )


def _series(raw: dict[str, Any], name: str):
    rows = []
    for obs in raw["observations"]:
        point = next((p for p in obs["points"] if p["name"] == name), None)
        if point and all(
            math.isfinite(float(point[k])) for k in ("full_x", "full_y", "raw_score")
        ):
            rows.append(
                (
                    float(obs["time_seconds"]),
                    float(point["full_x"]),
                    float(point["full_y"]),
                    max(0.0, float(point["raw_score"])),
                    int(obs["frame_id"]),
                )
            )
    return rows


def _design(t, period, harmonics=2):
    import numpy as np

    phase = 2 * np.pi * t / period
    columns = [np.ones(len(t))]
    for harmonic in range(1, harmonics + 1):
        columns.extend((np.sin(harmonic * phase), np.cos(harmonic * phase)))
    return np.column_stack(columns)


def _robust_fit(rows, period, harmonics=2):
    import numpy as np

    t = np.array([r[0] for r in rows])
    y = np.array([r[2] for r in rows])
    confidence = np.clip(np.array([r[3] for r in rows]), 0.01, 1)
    x = _design(t, period, harmonics)
    weights = confidence.copy()
    beta = np.zeros(x.shape[1])
    for _ in range(5):
        beta = np.linalg.lstsq(
            x * weights[:, None] ** 0.5, y * weights**0.5, rcond=None
        )[0]
        residual = y - x @ beta
        scale = max(1e-6, 1.4826 * np.median(np.abs(residual - np.median(residual))))
        weights = confidence * np.minimum(
            1, 1.5 * scale / np.maximum(np.abs(residual), 1e-9)
        )
    normalized = float(
        np.sum(weights * (y - x @ beta) ** 2) / max(np.sum(weights) * np.var(y), 1e-9)
    )
    return normalized, beta


def _autocorrelation_candidates(right, left, min_period, max_period):
    import numpy as np

    all_rows = right + left
    cadence = np.median(np.diff(sorted({r[0] for r in all_rows})))
    candidates = []
    for period in np.arange(min_period, max_period + cadence / 2, cadence):
        lag = max(1, round(period / cadence))
        values = []
        for rows in (right, left):
            t = np.array([r[0] for r in rows])
            y = np.array([r[2] for r in rows])
            grid = np.arange(t[0], t[-1] + cadence / 2, cadence)
            signal = np.interp(grid, t, y)
            signal -= signal.mean()
            if len(signal) > lag + 4 and signal.std() > 0:
                values.append(float(np.corrcoef(signal[:-lag], signal[lag:])[0, 1]))
        if values:
            candidates.append((float(period), float(np.mean(values))))
    return sorted(candidates, key=lambda item: item[1], reverse=True), float(cadence)


def _nearest_frames(raw, times):
    observations = raw["observations"]
    used = set()
    result = []
    for target in times:
        chosen = min(
            observations, key=lambda item: abs(float(item["time_seconds"]) - target)
        )
        frame_id = int(chosen["frame_id"])
        if frame_id in used:
            raise ValueError(
                "predicted timestamps map to duplicate source frames; temporal resolution is insufficient"
            )
        used.add(frame_id)
        result.append(chosen)
    return result


def _lower_median(values):
    """Choose the median value, preferring the lower neighbor for even counts."""
    if not values:
        raise ValueError("cannot choose a cycle from an empty sequence")
    return values[(len(values) - 1) // 2]


def _identity_evidence(right, left, confidence_threshold, overlap_fraction, crop_width):
    import numpy as np

    right_by = {r[4]: r for r in right}
    left_by = {r[4]: r for r in left}
    shared = sorted(set(right_by) & set(left_by))
    confident = [
        right_by[f][1] - left_by[f][1]
        for f in shared
        if min(right_by[f][3], left_by[f][3]) >= confidence_threshold
    ]
    scale = (
        max(1.0, float(np.median(np.abs(confident))))
        if confident
        else float(crop_width)
    )
    tolerance = overlap_fraction * scale
    separated = [value for value in confident if abs(value) > tolerance]
    expected = 1 if separated and np.median(separated) > 0 else -1 if separated else 0
    issues = []
    rejected = set()
    overlaps = set()
    for frame in shared:
        delta = right_by[frame][1] - left_by[frame][1]
        if abs(delta) <= tolerance:
            classification = "overlap_uncertain"
            overlaps.add(frame)
        elif (
            expected
            and delta * expected < 0
            and min(right_by[frame][3], left_by[frame][3]) >= confidence_threshold
        ):
            classification = "confident_opposite_sign"
            rejected.add(frame)
        else:
            continue
        issues.append(
            {
                "frame_id": frame,
                "right_minus_left_x": delta,
                "classification": classification,
            }
        )

    def filtered(rows):
        return [
            (t, x, y, confidence * 0.2 if frame in overlaps else confidence, frame)
            for t, x, y, confidence, frame in rows
            if frame not in rejected
        ]

    return filtered(right), filtered(left), expected, tolerance, issues, rejected


def _contact_sheet(paths, destination, title):
    from PIL import Image, ImageDraw

    images = [Image.open(path).convert("RGB") for path in paths]
    thumb_w = 320
    thumb_h = max(1, round(images[0].height * thumb_w / images[0].width))
    margin = 24
    sheet = Image.new(
        "RGB",
        (thumb_w * 3 + margin * 4, (thumb_h + 40) * math.ceil(len(images) / 3) + 70),
        (30, 30, 30),
    )
    draw = ImageDraw.Draw(sheet)
    draw.text((margin, 18), title, fill="white")
    for i, (path, image) in enumerate(zip(paths, images)):
        image.thumbnail((thumb_w, thumb_h))
        x = margin + (i % 3) * (thumb_w + margin)
        y = 55 + (i // 3) * (thumb_h + 40)
        sheet.paste(image, (x, y))
        draw.text((x, y + thumb_h + 6), path.stem, fill="white")
    destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(destination)
    [image.close() for image in images]


def _waveform_svg(destination, right, left, period, right_beta, left_beta, contacts):
    width, height, pad = 1200, 620, 60
    times = [r[0] for r in right + left]
    values = [r[2] for r in right + left]
    lo, hi = min(times), max(times)
    ymin, ymax = min(values), max(values)
    yr = max(1, ymax - ymin)
    sx = lambda value: pad + (value - lo) / max(hi - lo, 1e-9) * (width - 2 * pad)
    sy = lambda value: pad + (ymax - value) / yr * (height - 2 * pad)

    def points(rows):
        return " ".join(f"{sx(r[0]):.1f},{sy(r[2]):.1f}" for r in rows)

    import numpy as np

    grid = np.linspace(lo, hi, 1000)
    right_fit = _design(grid, period) @ right_beta
    left_fit = _design(grid, period) @ left_beta
    fitted = lambda values: " ".join(
        f"{sx(t):.1f},{sy(v):.1f}" for t, v in zip(grid, values)
    )
    contact_lines = "".join(
        f'<line x1="{sx(t):.1f}" x2="{sx(t):.1f}" y1="{pad}" y2="{height-pad}" stroke="#999" stroke-dasharray="5 5"/>'
        for t in contacts
    )
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}"><rect width="100%" height="100%" fill="white"/><text x="{pad}" y="30" font-family="sans-serif">Named ankle Y: raw observations and shared-period robust fit ({period:.6f} s)</text>{contact_lines}<polyline fill="none" stroke="#d62728" stroke-opacity=".35" points="{points(right)}"/><polyline fill="none" stroke="#1f77b4" stroke-opacity=".35" points="{points(left)}"/><polyline fill="none" stroke="#d62728" stroke-width="3" points="{fitted(right_fit)}"/><polyline fill="none" stroke="#1f77b4" stroke-width="3" points="{fitted(left_fit)}"/><text x="{pad}" y="{height-18}" font-family="sans-serif" fill="#d62728">right ankle</text><text x="{pad+120}" y="{height-18}" font-family="sans-serif" fill="#1f77b4">left ankle</text></svg>"""
    destination.write_text(svg)


def analyze(args: argparse.Namespace) -> None:
    import numpy as np

    frame_count = int(getattr(args, "frame_count", 6))
    if frame_count < 2:
        raise ValueError("frame_count must be at least 2")
    raw = json.loads(Path(args.raw_pose).read_text())
    right = _series(raw, "right_ankle")
    left = _series(raw, "left_ankle")
    right, left, expected, tolerance, sign_issues, rejected = _identity_evidence(
        right,
        left,
        args.sign_confidence,
        args.overlap_tolerance,
        int(raw["crop"]["x1"]) - int(raw["crop"]["x0"]),
    )
    if min(len(right), len(left)) < 12:
        raise ValueError("insufficient named ankle observations for cadence analysis")
    duration = max(r[0] for r in right + left) - min(r[0] for r in right + left)
    maximum = min(args.max_period, duration / 2)
    autocorr, cadence = _autocorrelation_candidates(
        right, left, args.min_period, maximum
    )
    seeds = [p for p, _ in autocorr[:8]]
    candidates = []
    for seed in seeds:
        for period in np.linspace(
            max(args.min_period, seed - 2 * cadence),
            min(maximum, seed + 2 * cadence),
            81,
        ):
            re, rb = _robust_fit(right, float(period))
            le, lb = _robust_fit(left, float(period))
            rf, _ = _robust_fit(right, float(period), 1)
            lf, _ = _robust_fit(left, float(period), 1)
            candidates.append(
                (re + le + 0.5 * (rf + lf), float(period), re, le, rf, lf, rb, lb)
            )
    candidates.sort(key=lambda item: item[0])
    best = candidates[0]
    period = best[1]
    alternatives = []
    for factor in (0.5, 1, 2):
        trial = period * factor
        if args.min_period <= trial <= maximum:
            re, _ = _robust_fit(right, trial)
            le, _ = _robust_fit(left, trial)
            rf, _ = _robust_fit(right, trial, 1)
            lf, _ = _robust_fit(left, trial, 1)
            alternatives.append(
                {
                    "factor": factor,
                    "period_seconds": trial,
                    "normalized_fit_error": re + le + 0.5 * (rf + lf),
                    "fundamental_fit_error": rf + lf,
                }
            )
    phase_grid = np.linspace(0, 1, 4096, endpoint=False)
    prediction = _design(phase_grid * period, period) @ best[6]
    contact_phase = float(phase_grid[int(np.argmax(prediction))])
    origin = contact_phase * period
    start = min(r[0] for r in right + left)
    end = max(r[0] for r in right + left)
    k0 = math.ceil((start - origin) / period)
    contacts = [
        origin + k * period for k in range(k0, math.floor((end - origin) / period) + 1)
    ]
    complete = [time for time in contacts if time >= start and time + period <= end]
    if not complete:
        raise ValueError(
            "no complete predicted right-foot cycle is contained in the observations"
        )
    selected = _lower_median(complete)
    analysis_identity = {
        "version": 1,
        "source_sha256": raw["source"]["sha256"],
        "raw_pose_sha256": sha256_file(args.raw_pose),
        "crop": raw["crop"],
        "model": raw.get("model", {}),
        "min_period": args.min_period,
        "max_period": args.max_period,
        "sign_confidence": args.sign_confidence,
        "overlap_tolerance": args.overlap_tolerance,
        "algorithm": "named-ankle-cycle-v1",
    }
    analysis_id = (
        "cya_"
        + hashlib.sha256(
            json.dumps(
                analysis_identity, sort_keys=True, separators=(",", ":")
            ).encode()
        ).hexdigest()
    )
    temporal_candidates = []
    rejected_candidates = []
    for ordinal, candidate_start in enumerate(complete):
        sample_times = [
            candidate_start + i * period / frame_count for i in range(frame_count)
        ]
        try:
            frames = _nearest_frames(raw, sample_times)
        except ValueError as exc:
            if candidate_start == selected:
                raise
            rejected_candidates.append(
                {
                    "ordinal": ordinal,
                    "start_time_seconds": candidate_start,
                    "reason": str(exc),
                }
            )
            continue
        identity = {
            "version": 1,
            "analysis_id": analysis_id,
            "period_seconds": period,
            "start_time_seconds": candidate_start,
            "ordinal": ordinal,
        }
        candidate_id = (
            "cyc_"
            + hashlib.sha256(
                json.dumps(identity, sort_keys=True, separators=(",", ":")).encode()
            ).hexdigest()
        )
        temporal_candidates.append(
            {
                "id": candidate_id,
                "ordinal": ordinal,
                "start_time_seconds": candidate_start,
                "end_time_seconds": candidate_start + period,
                "period_seconds": period,
                "sample_times_seconds": sample_times,
                "_frames": frames,
            }
        )
    system_candidate = next(
        item for item in temporal_candidates if item["start_time_seconds"] == selected
    )
    cycle_frames = system_candidate["_frames"]
    cycle_times = system_candidate["sample_times_seconds"]
    contact_frames = _nearest_frames(raw, contacts)
    output = Path(args.output).resolve()
    if output.exists():
        raise FileExistsError(f"diagnostic output already exists: {output}")
    originals = output / "original_frames"
    originals.mkdir(parents=True, exist_ok=True)
    source = probe_media(raw["source"]["path"])
    if source.content_sha256 != raw["source"]["sha256"]:
        raise ValueError("source content changed since raw pose extraction")
    chosen_ids = {
        int(item["frame_id"])
        for candidate in temporal_candidates
        for item in candidate["_frames"]
    } | {int(item["frame_id"]) for item in contact_frames}
    decoded = decode_frames(source, output / "decoded_selected", chosen_ids)
    by_id = {frame.frame_id: Path(frame.decode_path) for frame in decoded}

    def export_group(name, items):
        root = originals / name
        root.mkdir(parents=True, exist_ok=True)
        paths = []
        for index, item in enumerate(items):
            target = (
                root
                / f"{index:02d}-frame-{int(item['frame_id']):06d}-pts-{int(item['pts'])}.png"
            )
            shutil.copy2(by_id[int(item["frame_id"])], target)
            paths.append(target)
        title = (
            f"{len(items)} frame complete cycle"
            if name == "six_frame_complete_cycle"
            else name.replace("_", " ")
        )
        _contact_sheet(paths, output / f"{name}-contact-sheet.png", title)
        return [
            {
                "frame_id": int(item["frame_id"]),
                "pts": int(item["pts"]),
                "time_seconds": float(item["time_seconds"]),
                "path": str(path.relative_to(output)),
            }
            for item, path in zip(items, paths)
        ]

    cycle_start_records = export_group("predicted_cycle_starts", contact_frames)
    candidate_records = []
    for candidate in temporal_candidates:
        exported = export_group(
            "complete_cycles/" + candidate["id"], candidate.pop("_frames")
        )
        candidate_records.append({**candidate, "frames": exported})
    crop_paths = []
    crop_root = output / "crop_predicted_cycle_starts"
    crop_root.mkdir()
    x0, x1, y0, y1 = (int(raw["crop"][key]) for key in ("x0", "x1", "y0", "y1"))
    from PIL import Image

    for record in cycle_start_records:
        source_path = output / record["path"]
        target = crop_root / Path(record["path"]).name
        with Image.open(source_path) as image:
            image.crop((x0, y0, x1, y1)).save(target)
        crop_paths.append(target)
    _contact_sheet(
        crop_paths,
        output / "predicted_cycle_starts-crop-contact-sheet.png",
        "predicted cycle starts: analysis crop",
    )
    _waveform_svg(
        output / "ankle-y-waveforms.svg",
        right,
        left,
        period,
        best[6],
        best[7],
        contacts,
    )
    objective = np.array([item[0] for item in candidates])
    near = np.array([item[1] for item in candidates])[
        objective <= best[0] * 1.05 + 1e-6
    ]
    uncertainty = max(
        cadence / 2, float((near.max() - near.min()) / 2) if len(near) else cadence / 2
    )
    system_frames = next(
        item["frames"]
        for item in candidate_records
        if item["id"] == system_candidate["id"]
    )
    summary = {
        "version": "1.1",
        "analysis_id": analysis_id,
        "rejected_cycle_candidates": rejected_candidates,
        "source": raw["source"],
        "model": raw.get("model", {}),
        "selected_frame_count": frame_count,
        "analysis_view": {
            "crop": raw["crop"],
            "description": "configured analysis crop",
        },
        "period": {
            "seconds": period,
            "uncertainty_seconds_heuristic": uncertainty,
            "normalized_fit_error": best[0],
            "right_fit_error": best[2],
            "left_fit_error": best[3],
            "fundamental_fit_error": best[4] + best[5],
            "autocorrelation_candidates": [
                {"period_seconds": p, "score": s} for p, s in autocorr[:12]
            ],
            "half_full_double": alternatives,
            "constant_period_contract": True,
        },
        "right_ground_phase": {
            "phase": contact_phase,
            "semantics": "maximum fitted right-ankle image Y; estimated low-foot interval center, not measured physical contact",
            "frame_zero_assumed_boundary": False,
            "predicted_times_seconds": contacts,
        },
        "foot_identity": {
            "right_landmark_index": RIGHT_ANKLE,
            "left_landmark_index": LEFT_ANKLE,
            "expected_sign": expected,
            "tolerance_pixels": tolerance,
            "issues": sign_issues,
            "rejected_frame_ids": sorted(rejected),
            "sorting_used": False,
        },
        "cycle_starts": cycle_start_records,
        "cycle_candidates": candidate_records,
        "system_candidate_id": system_candidate["id"],
        "system_selection_policy": "lower_median_complete_cycle",
        "six_frame_cycle": {
            "candidate_id": system_candidate["id"],
            "start_time_seconds": selected,
            "sample_times_seconds": cycle_times,
            "frames": system_frames,
        },
        "evidence_files": {
            "waveform_plot": "ankle-y-waveforms.svg",
            "cycle_start_crop_sheet": "predicted_cycle_starts-crop-contact-sheet.png",
            "cycle_start_full_sheet": "predicted_cycle_starts-contact-sheet.png",
        },
        "raw_pose": str(Path(args.raw_pose).resolve()),
    }
    atomic_write_json(
        output / "period_candidates.json",
        {
            "period_candidates": [
                {
                    "period_seconds": item[1],
                    "normalized_fit_error": item[0],
                    "right_fit_error": item[2],
                    "left_fit_error": item[3],
                    "right_fundamental_fit_error": item[4],
                    "left_fundamental_fit_error": item[5],
                }
                for item in candidates[:100]
            ],
            "sign_issues": sign_issues,
        },
    )
    atomic_write_json(output / "summary.json", summary)


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)
    comfy_aux = Path.home() / "ComfyUI/custom_nodes/comfyui_controlnet_aux"
    extract_parser = commands.add_parser("extract")
    extract_parser.add_argument("--source", default="tmp/MiniMax_H3_00988_.mp4")
    extract_parser.add_argument("--output", required=True)
    extract_parser.add_argument(
        "--crop",
        type=int,
        nargs=4,
        default=(1212, 1616, 0, 640),
        metavar=("X0", "X1", "Y0", "Y1"),
    )
    extract_parser.add_argument("--repo", default=str(comfy_aux))
    extract_parser.add_argument(
        "--detector", default=str(comfy_aux / "ckpts/yzd-v/DWPose/yolox_l.onnx")
    )
    extract_parser.add_argument(
        "--no-detector",
        action="store_true",
        help="known single subject fills the prescribed crop; bypass person detection and run pose directly",
    )
    extract_parser.add_argument(
        "--pose",
        default=str(
            comfy_aux
            / "ckpts/hr16/DWPose-TorchScript-BatchSize5/dw-ll_ucoco_384_bs5.torchscript.pt"
        ),
    )
    extract_parser.add_argument("--device", default="cuda")
    sdpose_parser = commands.add_parser("extract-sdpose")
    sdpose_parser.add_argument("--source", default="tmp/MiniMax_H3_00988_.mp4")
    sdpose_parser.add_argument("--output", required=True)
    sdpose_parser.add_argument(
        "--crop",
        type=int,
        nargs=4,
        default=(1212, 1616, 0, 640),
        metavar=("X0", "X1", "Y0", "Y1"),
    )
    sdpose_parser.add_argument("--server")
    sdpose_parser.add_argument("--config", action="append", metavar="PATH")
    sdpose_parser.add_argument("--timeout", type=float)
    sdpose_parser.add_argument("--poll-interval", type=float, default=2.0)
    analyze_parser = commands.add_parser("analyze")
    analyze_parser.add_argument("--raw-pose", required=True)
    analyze_parser.add_argument("--output", required=True)
    analyze_parser.add_argument("--frame-count", type=int, default=6)
    analyze_parser.add_argument("--min-period", type=float, default=0.35)
    analyze_parser.add_argument("--max-period", type=float, default=3.0)
    analyze_parser.add_argument("--sign-confidence", type=float, default=0.35)
    analyze_parser.add_argument("--overlap-tolerance", type=float, default=0.12)
    return root


def main(argv=None):
    command_parser = parser()
    args = command_parser.parse_args(argv)
    if args.command == "analyze" and args.frame_count < 2:
        command_parser.error("--frame-count must be at least 2")
    if args.command == "extract":
        extract(args)
    elif args.command == "extract-sdpose":
        extract_sdpose(args)
    else:
        analyze(args)


if __name__ == "__main__":
    main()
