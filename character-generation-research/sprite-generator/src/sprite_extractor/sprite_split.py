"""Foreground-aware splitting for four-character montage frames."""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np

ALPHA_NOISE_THRESHOLD = 0.05
SPLIT_ALGORITHMS = ("blobs", "quarters")


@dataclass(frozen=True)
class Blob:
    area: int
    x0: int
    y0: int
    x1: int
    y1: int


def clean_alpha(alpha: np.ndarray, threshold: float = ALPHA_NOISE_THRESHOLD) -> np.ndarray:
    """Return float alpha with sub-threshold background noise removed."""
    result = np.asarray(alpha, dtype=np.float32).copy()
    result[result < threshold] = 0.0
    return result


def quarter_edges(width: int) -> list[int]:
    if width < 4:
        raise ValueError("source image is too narrow for four nonempty views")
    return [round(index * width / 4) for index in range(5)]


def _largest_blobs(alpha: np.ndarray) -> list[Blob]:
    """Label 8-connected foreground efficiently using horizontal runs."""
    foreground = np.asarray(alpha) > 0
    if foreground.ndim != 2:
        raise ValueError("alpha mask must be two-dimensional")
    parent: list[int] = []
    runs: list[tuple[int, int, int, int]] = []

    def find(label: int) -> int:
        while parent[label] != label:
            parent[label] = parent[parent[label]]
            label = parent[label]
        return label

    def union(left: int, right: int) -> None:
        left_root, right_root = find(left), find(right)
        if left_root != right_root:
            parent[right_root] = left_root

    previous: list[tuple[int, int, int]] = []
    for y, row in enumerate(foreground):
        padded = np.pad(row.astype(np.int8), (1, 1))
        changes = np.diff(padded)
        starts = np.flatnonzero(changes == 1)
        ends = np.flatnonzero(changes == -1)
        current: list[tuple[int, int, int]] = []
        previous_index = 0
        for x0, x1 in zip(starts.tolist(), ends.tolist()):
            label = len(parent)
            parent.append(label)
            while previous_index < len(previous) and previous[previous_index][1] < x0:
                previous_index += 1
            candidate = previous_index
            while candidate < len(previous) and previous[candidate][0] <= x1:
                union(label, previous[candidate][2])
                candidate += 1
            current.append((x0, x1, label))
            runs.append((y, x0, x1, label))
        previous = current

    aggregates: dict[int, list[int]] = {}
    for y, x0, x1, label in runs:
        root = find(label)
        if root not in aggregates:
            aggregates[root] = [0, x0, y, x1, y + 1]
        item = aggregates[root]
        item[0] += x1 - x0
        item[1] = min(item[1], x0)
        item[2] = min(item[2], y)
        item[3] = max(item[3], x1)
        item[4] = max(item[4], y + 1)
    return sorted((Blob(*values) for values in aggregates.values()), key=lambda blob: blob.area, reverse=True)


def blob_edges(alpha: np.ndarray) -> tuple[list[int], list[Blob]]:
    """Split midway through gaps between the four largest foreground blobs."""
    height, width = alpha.shape
    blobs = _largest_blobs(alpha)
    if len(blobs) < 4:
        raise ValueError(
            f"blob splitting found {len(blobs)} foreground components; expected at least four "
            "(try a wider render by increasing sprite_render_width in config or passing "
            "--sprite-render-width PIXELS; alternatively, use --split-algorithm quarters "
            "for the legacy splitter)"
        )
    selected = sorted(blobs[:4], key=lambda blob: (blob.x0 + blob.x1) / 2)
    edges = [0]
    for left, right in zip(selected, selected[1:]):
        if left.x1 >= right.x0:
            raise ValueError(
                "blob splitting could not find horizontal space between the four largest components "
                "(try a wider render by increasing sprite_render_width in config or passing "
                "--sprite-render-width PIXELS; alternatively, use --split-algorithm quarters "
                "for the legacy splitter)"
            )
        edges.append((left.x1 + right.x0) // 2)
    edges.append(width)
    if any(left >= right for left, right in zip(edges, edges[1:])):
        raise ValueError("blob splitting produced an empty view")
    return edges, selected


def split_edges(alpha: np.ndarray, algorithm: str) -> tuple[np.ndarray, list[int], list[Blob]]:
    if algorithm not in SPLIT_ALGORITHMS:
        raise ValueError(f"split algorithm must be one of {', '.join(SPLIT_ALGORITHMS)}")
    if algorithm == "quarters":
        return np.asarray(alpha, dtype=np.float32), quarter_edges(alpha.shape[1]), []
    cleaned = clean_alpha(alpha)
    edges, blobs = blob_edges(cleaned)
    return cleaned, edges, blobs


def shared_split_edges(masks: list[np.ndarray] | np.ndarray, algorithm: str) -> tuple[list[np.ndarray], np.ndarray, list[int], list[Blob]]:
    """Clean masks and derive one set of cuts from their combined foreground."""
    if algorithm not in SPLIT_ALGORITHMS:
        raise ValueError(f"split algorithm must be one of {', '.join(SPLIT_ALGORITHMS)}")
    items = [np.asarray(mask, dtype=np.float32) for mask in masks]
    if not items:
        raise ValueError("at least one alpha mask is required")
    if any(mask.ndim != 2 for mask in items):
        raise ValueError("alpha masks must be two-dimensional")
    if any(mask.shape != items[0].shape for mask in items[1:]):
        raise ValueError("combined-mask splitting requires every selected frame to have the same dimensions")
    if algorithm == "quarters":
        combined = np.maximum.reduce(items)
        return items, combined, quarter_edges(items[0].shape[1]), []
    prepared = [clean_alpha(mask) for mask in items]
    combined = np.maximum.reduce(prepared)
    edges, blobs = blob_edges(combined)
    return prepared, combined, edges, blobs


def scale_edges(edges: list[int], source_width: int, target_width: int) -> list[int]:
    scaled = [round(edge * target_width / source_width) for edge in edges]
    scaled[0], scaled[-1] = 0, target_width
    if any(left >= right for left, right in zip(scaled, scaled[1:])):
        raise ValueError("scaled split contains an empty view")
    return scaled
