from __future__ import annotations

import json
import math
import subprocess
from dataclasses import replace
from pathlib import Path
from typing import Any, Callable, Iterable, Sequence

from .contracts import CoordinateTransform, FrameTiming, Rational, SourceManifest
from .io_utils import sha256_file

CommandRunner = Callable[[Sequence[str]], subprocess.CompletedProcess[str]]


class MediaError(RuntimeError):
    """A structured FFprobe/FFmpeg failure suitable for a stage diagnostic."""

    def __init__(self, tool: str, message: str, command: Sequence[str], stderr: str = ""):
        super().__init__(message)
        self.tool = tool
        self.command = tuple(command)
        self.stderr = stderr


def _run(command: Sequence[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, text=True, capture_output=True, check=False)


def _checked(command: Sequence[str], runner: CommandRunner) -> subprocess.CompletedProcess[str]:
    result = runner(command)
    if result.returncode:
        raise MediaError(Path(command[0]).name, f"{Path(command[0]).name} exited with status {result.returncode}", command, result.stderr)
    return result


def _rotation(stream: dict[str, Any]) -> int:
    raw: Any = stream.get("tags", {}).get("rotate")
    for side_data in stream.get("side_data_list", []):
        if "rotation" in side_data:
            raw = side_data["rotation"]
            break
    try:
        # FFmpeg reports display-matrix rotation counter-clockwise. Normalize to
        # the clockwise transform applied when creating canonical decoded frames.
        return int(round(-float(raw) / 90.0) * 90) % 360
    except (TypeError, ValueError):
        return 0


def _orientation_transform(width: int, height: int, degrees: int) -> CoordinateTransform:
    matrices = {
        0: (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0),
        90: (0.0, -1.0, float(height - 1), 1.0, 0.0, 0.0, 0.0, 0.0, 1.0),
        180: (-1.0, 0.0, float(width - 1), 0.0, -1.0, float(height - 1), 0.0, 0.0, 1.0),
        270: (0.0, 1.0, 0.0, -1.0, 0.0, float(width - 1), 0.0, 0.0, 1.0),
    }
    return CoordinateTransform("encoded_pixels", "full_image_pixels", matrices[degrees])


def _multiply(a: tuple[float, ...], b: tuple[float, ...]) -> tuple[float, ...]:
    return tuple(sum(a[row * 3 + k] * b[k * 3 + col] for k in range(3)) for row in range(3) for col in range(3))


def probe_media(path: str | Path, ffprobe_bin: str = "ffprobe", runner: CommandRunner = _run) -> SourceManifest:
    source = Path(path).resolve()
    command = [ffprobe_bin, "-v", "error", "-select_streams", "v:0", "-show_streams", "-show_frames", "-show_entries",
        "stream=index,width,height,time_base,sample_aspect_ratio,color_space,color_transfer,color_primaries,color_range:stream_tags=rotate:stream_side_data=rotation:frame=best_effort_timestamp,pkt_duration,key_frame",
        "-of", "json", str(source)]
    result = _checked(command, runner)
    try:
        data = json.loads(result.stdout)
        stream = data["streams"][0]
    except (json.JSONDecodeError, KeyError, IndexError) as error:
        raise MediaError(ffprobe_bin, f"invalid FFprobe response: {error}", command, result.stderr) from error
    time_base = Rational.parse(stream["time_base"])
    warnings: list[str] = []
    raw_timings: list[tuple[int, int, int, bool]] = []
    last_pts: int | None = None
    for index, raw in enumerate(data.get("frames", [])):
        pts_raw = raw.get("best_effort_timestamp")
        if pts_raw is None:
            raise MediaError(ffprobe_bin, f"decoded frame {index} has no presentation timestamp; exact mapping is impossible", command, result.stderr)
        pts = int(pts_raw)
        duration = int(raw.get("pkt_duration") or 0)
        if last_pts is not None and pts < last_pts:
            warnings.append(f"non-monotonic presentation timestamp at frame {index}")
        raw_timings.append((index, pts, duration, bool(int(raw.get("key_frame", 0)))))
        last_pts = pts
    if not raw_timings:
        raise MediaError(ffprobe_bin, "selected video stream contains no timestamped frames", command, result.stderr)
    positive_durations = [duration for _, _, duration, _ in raw_timings if duration > 0]
    positive_deltas = [raw_timings[i + 1][1] - item[1] for i, item in enumerate(raw_timings[:-1]) if raw_timings[i + 1][1] > item[1]]
    terminal_estimate = positive_durations[-1] if positive_durations else (positive_deltas[-1] if positive_deltas else 1)
    frames: list[FrameTiming] = []
    for i, (frame_id, pts, duration, keyframe) in enumerate(raw_timings):
        if duration <= 0:
            duration = raw_timings[i + 1][1] - pts if i + 1 < len(raw_timings) and raw_timings[i + 1][1] > pts else terminal_estimate
            warnings.append(f"frame {frame_id} duration inferred from {'next PTS' if i + 1 < len(raw_timings) else 'last known cadence'}")
        frames.append(FrameTiming(frame_id, pts, duration, keyframe))
    rotation = _rotation(stream)
    encoded_width, encoded_height = int(stream["width"]), int(stream["height"])
    sar_raw = stream.get("sample_aspect_ratio") or "1:1"
    sar = Rational.parse(sar_raw) if sar_raw not in {"N/A", "0:1"} else Rational(1, 1)
    square_width = max(1, round(encoded_width * sar.numerator / sar.denominator))
    width, height = ((encoded_height, square_width) if rotation in (90, 270) else (square_width, encoded_height))
    orient = _orientation_transform(square_width, encoded_height, rotation)
    encoded_to_square = (square_width / encoded_width, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)
    color = {key: str(stream[key]) for key in ("color_space", "color_transfer", "color_primaries", "color_range") if stream.get(key)}
    return SourceManifest(sha256_file(source), str(source), width, height, time_base, frames,
        stream_index=int(stream.get("index", 0)), orientation_degrees=rotation, pixel_aspect_ratio=sar,
        color_metadata=color, decode_tool=_tool_version(ffprobe_bin, runner),
        transforms=[CoordinateTransform("encoded_pixels", "full_image_pixels", _multiply(orient.matrix, encoded_to_square))], warnings=warnings)


def _tool_version(binary: str, runner: CommandRunner) -> str:
    result = runner([binary, "-version"])
    return (result.stdout.splitlines() or [binary])[0].strip() if result.returncode == 0 else binary


def _vf_for_orientation(degrees: int) -> list[str]:
    return {0: [], 90: ["transpose=clock"], 180: ["hflip", "vflip"], 270: ["transpose=cclock"]}[degrees]


def decode_frames(
    manifest: SourceManifest,
    output_dir: str | Path,
    frame_ids: Iterable[int] | None = None,
    *,
    max_dimension: int | None = None,
    ffmpeg_bin: str = "ffmpeg",
    runner: CommandRunner = _run,
) -> list[FrameTiming]:
    """Decode a bounded set without deriving time from nominal frame rate.

    FFmpeg's decoded-frame ordinal is selected, while every output remains tied
    to the exact PTS previously reported for that ordinal by FFprobe. A single
    process decodes the minimal enclosing interval and emits only requested
    frames, avoiding seek-to-nearest-frame ambiguity.
    """
    available = {frame.frame_id: frame for frame in manifest.frames}
    requested = sorted(set(available if frame_ids is None else frame_ids))
    if not requested:
        return []
    if any(frame_id not in available for frame_id in requested):
        raise IndexError("requested frame ID is outside the probed stream")
    destination = Path(output_dir)
    destination.mkdir(parents=True, exist_ok=True)
    base_filters: list[str] = []
    if manifest.pixel_aspect_ratio != Rational(1, 1):
        base_filters.extend([f"scale={manifest.width if manifest.orientation_degrees not in (90, 270) else manifest.height}:ih:flags=lanczos", "setsar=1"])
    base_filters.extend(_vf_for_orientation(manifest.orientation_degrees))
    proxy_transform: CoordinateTransform | None = None
    if max_dimension is not None:
        if max_dimension <= 0:
            raise ValueError("max_dimension must be positive")
        scale = min(1.0, max_dimension / max(manifest.width, manifest.height))
        out_w = max(1, int(math.floor(manifest.width * scale / 2) * 2))
        out_h = max(1, int(math.floor(manifest.height * scale / 2) * 2))
        base_filters.append(f"scale={out_w}:{out_h}:flags=lanczos")
        proxy_transform = CoordinateTransform("full_image_pixels", "analysis_pixels", (out_w / manifest.width, 0, 0, 0, out_h / manifest.height, 0, 0, 0, 1))
    for batch_start in range(0, len(requested), 128):
        batch = requested[batch_start:batch_start + 128]
        selected = "+".join(f"eq(n\\,{frame_id})" for frame_id in batch)
        filters = [f"select='{selected}'", *base_filters]
        pattern = destination / "frame-%08d.png"
        command = [ffmpeg_bin, "-v", "error", "-y", "-noautorotate", "-i", manifest.path, "-map", f"0:{manifest.stream_index}",
            "-vf", ",".join(filters), "-fps_mode", "passthrough", "-frames:v", str(len(batch)), "-start_number", str(batch_start), str(pattern)]
        _checked(command, runner)
    decoded: list[FrameTiming] = []
    for output_index, frame_id in enumerate(requested):
        path = destination / f"frame-{output_index:08d}.png"
        if not path.is_file():
            raise MediaError(ffmpeg_bin, f"expected decoded frame was not written: {path}", command)
        decoded.append(replace(available[frame_id], decode_path=str(path)))
    if proxy_transform is not None and proxy_transform not in manifest.transforms:
        manifest.transforms.append(proxy_transform)
    return decoded
