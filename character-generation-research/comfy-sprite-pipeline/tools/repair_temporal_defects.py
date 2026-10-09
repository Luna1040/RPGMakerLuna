"""Conservative optical-flow repair for white-background character videos.

The tool repairs only regions that disappeared relative to the first frame.
It prefers warped reference pixels and deliberately leaves uncertain regions
untouched instead of regenerating an otherwise good frame.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np


def _read_video(path: Path) -> tuple[list[np.ndarray], float]:
    capture = cv2.VideoCapture(str(path))
    fps = capture.get(cv2.CAP_PROP_FPS) or 12.0
    frames: list[np.ndarray] = []
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        frames.append(frame)
    capture.release()
    if not frames:
        raise RuntimeError(f"could not decode video: {path}")
    return frames, fps


def _background_connected_mask(frame: np.ndarray) -> np.ndarray:
    """Return character mask while preserving real exterior-connected gaps."""
    background_like = np.all(frame >= 242, axis=2).astype(np.uint8)
    count, labels = cv2.connectedComponents(background_like, connectivity=8)
    border_labels = np.unique(
        np.concatenate((labels[0], labels[-1], labels[:, 0], labels[:, -1]))
    )
    border_labels = border_labels[border_labels != 0]
    connected_background = np.isin(labels, border_labels) if count > 1 else background_like > 0
    return (~connected_background).astype(np.uint8)


def _warp(source: np.ndarray, backward_flow: np.ndarray, interpolation: int) -> np.ndarray:
    height, width = source.shape[:2]
    grid_x, grid_y = np.meshgrid(
        np.arange(width, dtype=np.float32), np.arange(height, dtype=np.float32)
    )
    return cv2.remap(
        source,
        grid_x + backward_flow[..., 0],
        grid_y + backward_flow[..., 1],
        interpolation,
        borderMode=cv2.BORDER_CONSTANT,
        borderValue=255 if source.ndim == 3 else 0,
    )


def _flow_pair(reference: np.ndarray, current: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    ref_gray = cv2.cvtColor(reference, cv2.COLOR_BGR2GRAY)
    cur_gray = cv2.cvtColor(current, cv2.COLOR_BGR2GRAY)
    params = dict(
        pyr_scale=0.5,
        levels=5,
        winsize=31,
        iterations=5,
        poly_n=7,
        poly_sigma=1.5,
        flags=cv2.OPTFLOW_FARNEBACK_GAUSSIAN,
    )
    forward = cv2.calcOpticalFlowFarneback(ref_gray, cur_gray, None, **params)
    backward = cv2.calcOpticalFlowFarneback(cur_gray, ref_gray, None, **params)
    return forward, backward


def _flow_reliability(forward: np.ndarray, backward: np.ndarray) -> np.ndarray:
    warped_forward = _warp(forward, backward, cv2.INTER_LINEAR)
    error = np.linalg.norm(backward + warped_forward, axis=2)
    return np.exp(-(error * error) / (2.0 * 2.25 * 2.25)).astype(np.float32)


def _candidate_mask(
    current: np.ndarray,
    warped_reference: np.ndarray,
    warped_mask: np.ndarray,
    reliability: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    # The dilated ROI supplies a margin for hair, cape edges, and weapons.
    roi = cv2.dilate(warped_mask, np.ones((7, 7), np.uint8), iterations=1)
    ref_ink = np.max(255 - warped_reference, axis=2)
    current_whiteness = np.min(current, axis=2)
    surface_loss = (ref_ink >= 24) & (current_whiteness >= 244)

    # Automatic compositing is intentionally restricted to the interior.
    # Flow is least reliable on hair/cape/weapon borders; repairing those
    # eagerly creates the same detached fragments we are trying to remove.
    interior_depth = cv2.distanceTransform((warped_mask > 0).astype(np.uint8), cv2.DIST_L2, 5)
    stable_interior = interior_depth >= 2.4
    candidate = surface_loss & stable_interior & (roi > 0) & (reliability >= 0.68)
    candidate = cv2.morphologyEx(candidate.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))
    return candidate, ref_ink.astype(np.float32) / 255.0


def _filter_components(
    candidate: np.ndarray,
    reliability: np.ndarray,
    reference_strength: np.ndarray,
    temporal_support: np.ndarray,
    character_area: int,
) -> tuple[np.ndarray, list[dict[str, float]]]:
    accepted = np.zeros_like(candidate)
    reports: list[dict[str, float]] = []
    count, labels, stats, _ = cv2.connectedComponentsWithStats(candidate, 8)
    max_area = max(12, int(character_area * 0.035))
    for label in range(1, count):
        area = int(stats[label, cv2.CC_STAT_AREA])
        if area < 4 or area > max_area:
            continue
        region = labels == label
        flow_score = float(reliability[region].mean())
        visual_score = float(reference_strength[region].mean())
        temporal_score = float(temporal_support[region].mean())
        # Temporal evidence raises confidence but is not mandatory for a
        # strong, reliable single-frame defect.
        confidence = 0.50 * flow_score + 0.35 * visual_score + 0.15 * temporal_score
        strong_single_frame = flow_score >= 0.84 and visual_score >= 0.42
        if confidence >= 0.72 or strong_single_frame:
            accepted[region] = 1
            reports.append(
                {
                    "area": area,
                    "flow": round(flow_score, 3),
                    "visual": round(visual_score, 3),
                    "temporal": round(temporal_score, 3),
                    "confidence": round(confidence, 3),
                }
            )
    return accepted, reports


def repair_video(source: Path, output: Path, report_path: Path) -> int:
    frames, fps = _read_video(source)
    frame_masks = [_background_connected_mask(frame) for frame in frames]
    character_area = int(np.median([mask.sum() for mask in frame_masks]))

    warped_frames: list[np.ndarray] = []
    reliability_maps: list[np.ndarray] = []
    candidates: list[np.ndarray] = []
    strengths: list[np.ndarray] = []

    for index, current in enumerate(frames):
        analyses: list[tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]] = []
        for neighbor_index in (index - 1, index + 1):
            if neighbor_index < 0 or neighbor_index >= len(frames):
                continue
            neighbor = frames[neighbor_index]
            forward, backward = _flow_pair(neighbor, current)
            warped_neighbor = _warp(neighbor, backward, cv2.INTER_LINEAR)
            warped_mask = _warp(frame_masks[neighbor_index], backward, cv2.INTER_NEAREST)
            reliability = _flow_reliability(forward, backward)
            candidate, strength = _candidate_mask(
                current, warped_neighbor, warped_mask, reliability
            )
            analyses.append((warped_neighbor, reliability, candidate, strength))

        if not analyses:
            warped_frames.append(current)
            reliability_maps.append(np.ones(current.shape[:2], np.float32))
            candidates.append(np.zeros(current.shape[:2], np.uint8))
            strengths.append(np.zeros(current.shape[:2], np.float32))
        elif len(analyses) == 1:
            warped, reliability, candidate, strength = analyses[0]
            warped_frames.append(warped)
            reliability_maps.append(reliability)
            candidates.append(candidate)
            strengths.append(strength)
        else:
            first, second = analyses
            # Both adjacent frames must agree spatially. This prevents normal
            # breathing deformation from being mistaken for a missing part.
            kernel = np.ones((5, 5), np.uint8)
            agreed = (
                (first[2] > 0) & (cv2.dilate(second[2], kernel) > 0)
            ) | (
                (second[2] > 0) & (cv2.dilate(first[2], kernel) > 0)
            )
            warped_frames.append(
                ((first[0].astype(np.uint16) + second[0].astype(np.uint16)) // 2).astype(np.uint8)
            )
            reliability_maps.append(np.minimum(first[1], second[1]))
            candidates.append(agreed.astype(np.uint8))
            strengths.append(np.maximum(first[3], second[3]))

    repaired: list[np.ndarray] = []
    report: dict[str, object] = {"source": str(source), "frames": []}
    total_repaired_area = 0
    for index, current in enumerate(frames):
        neighbor = np.zeros_like(candidates[index], np.float32)
        if index > 0:
            neighbor += candidates[index - 1]
        if index + 1 < len(candidates):
            neighbor += candidates[index + 1]
        neighbor = np.clip(cv2.dilate(neighbor, np.ones((5, 5), np.uint8)), 0, 1)
        accepted, components = _filter_components(
            candidates[index],
            reliability_maps[index],
            strengths[index],
            neighbor,
            character_area,
        )

        if accepted.any():
            alpha = cv2.GaussianBlur(accepted.astype(np.float32), (0, 0), 0.7)
            alpha = np.clip(alpha[..., None], 0.0, 1.0)
            result = (
                current.astype(np.float32) * (1.0 - alpha)
                + warped_frames[index].astype(np.float32) * alpha
            ).astype(np.uint8)
        else:
            result = current
        repaired.append(result)
        total_repaired_area += int(accepted.sum())
        report["frames"].append(
            {
                "index": index,
                "candidate_area": int(candidates[index].sum()),
                "repaired_area": int(accepted.sum()),
                "components": components,
            }
        )

    report["total_repaired_area"] = total_repaired_area
    report["output"] = str(output) if total_repaired_area else None
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    if not total_repaired_area:
        return 0

    height, width = repaired[0].shape[:2]
    output.parent.mkdir(parents=True, exist_ok=True)
    writer = cv2.VideoWriter(
        str(output), cv2.VideoWriter_fourcc(*"mp4v"), fps, (width, height)
    )
    if not writer.isOpened():
        raise RuntimeError(f"could not open output video: {output}")
    for frame in repaired:
        writer.write(frame)
    writer.release()
    return total_repaired_area


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    report = args.report or args.output.with_suffix(".repair.json")
    repaired_area = repair_video(args.source, args.output, report)
    if repaired_area:
        print(f"repaired {repaired_area} px -> {args.output}")
    else:
        print("no validated defects; original video remains unchanged")
    print(f"repair report -> {report}")


if __name__ == "__main__":
    main()
