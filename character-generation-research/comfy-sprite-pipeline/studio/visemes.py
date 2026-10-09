"""Viseme timing, Rhubarb adaptation, and atlas helpers for Studio W9.

The module is intentionally independent from the HTTP server and GPU runner.
It defines the integration contract shared by an eventual W9 driver, offline
Rhubarb/TTS adapters, and a realtime renderer. All public manifests are JSON
compatible and all subprocess commands are returned as argv lists (never as a
shell command string).
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Iterable, Mapping, Sequence

from PIL import Image, ImageOps


VISEME_TIMELINE_SCHEMA = "studio.viseme_timeline.v1"
VISEME_ATLAS_SCHEMA = "studio.viseme_atlas.v1"
RHUBARB_RESULT_SCHEMA = "studio.rhubarb_result.v1"

STUDIO_VISEMES: tuple[str, ...] = (
    "closed",
    "rest",
    "A_AI",
    "E",
    "I",
    "O",
    "U",
    "FV",
    "L",
    "MBP",
)
RHUBARB_SHAPES: tuple[str, ...] = ("A", "B", "C", "D", "E", "F", "G", "H", "X")

# Rhubarb documents A/C/D/E/F/G/H/X using Preston-Blair names. Studio has no
# generic "etc" pose for Rhubarb B, so its clenched-teeth/EE shape maps to I.
RHUBARB_TO_STUDIO: dict[str, str] = {
    "A": "MBP",
    "B": "I",
    "C": "E",
    "D": "A_AI",
    "E": "O",
    "F": "U",
    "G": "FV",
    "H": "L",
    "X": "rest",
}
STUDIO_TO_RHUBARB: dict[str, str] = {
    "closed": "X",
    "rest": "X",
    "A_AI": "D",
    "E": "C",
    "I": "B",
    "O": "E",
    "U": "F",
    "FV": "G",
    "L": "H",
    "MBP": "A",
}

VISEME_PROMPTS: dict[str, str] = {
    "closed": "fully closed relaxed lips for silence, no visible teeth",
    "rest": "neutral relaxed resting mouth, lips barely touching",
    "A_AI": "wide vertical open mouth for A and AI sounds",
    "E": "medium open mouth for E sound",
    "I": "wide horizontal mouth with slightly separated clenched teeth for I or EE",
    "O": "rounded open lips for O sound",
    "U": "small forward puckered lips for U or OO sound",
    "FV": "upper teeth gently touching the lower lip for F or V",
    "L": "open mouth with the tongue raised behind the upper teeth for L",
    "MBP": "closed lips with slight pressure for M, B, or P",
}

_DEFAULT_PROTECTED_SHORT_VISEMES = frozenset({"MBP", "FV", "L"})
_TIME_TOLERANCE = 1e-6


@dataclass(frozen=True, slots=True)
class VisemeCue:
    start: float
    end: float
    viseme: str
    source_shape: str | None = None

    @property
    def duration(self) -> float:
        return self.end - self.start

    def to_dict(self) -> dict[str, Any]:
        result: dict[str, Any] = {
            "start": _round_time(self.start),
            "end": _round_time(self.end),
            "viseme": self.viseme,
        }
        if self.source_shape is not None:
            result["source_shape"] = self.source_shape
        return result


@dataclass(frozen=True, slots=True)
class RhubarbResult:
    duration: float
    cues: tuple[VisemeCue, ...]
    sound_file: str | None
    metadata: dict[str, Any]

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": RHUBARB_RESULT_SCHEMA,
            "duration_seconds": _round_time(self.duration),
            "sound_file": self.sound_file,
            "metadata": dict(self.metadata),
            "cues": [cue.to_dict() for cue in self.cues],
        }


def _round_time(value: float) -> float:
    return round(float(value), 6)


def _number(value: Any, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{name} must be a finite number")
    result = float(value)
    if not math.isfinite(result):
        raise ValueError(f"{name} must be a finite number")
    return result


def _positive(value: Any, name: str, *, allow_zero: bool = False) -> float:
    result = _number(value, name)
    if result < 0 or (not allow_zero and result == 0):
        comparator = "non-negative" if allow_zero else "positive"
        raise ValueError(f"{name} must be {comparator}")
    return result


def _coerce_cue(value: VisemeCue | Mapping[str, Any], index: int) -> VisemeCue:
    if isinstance(value, VisemeCue):
        cue = value
    elif isinstance(value, Mapping):
        cue = VisemeCue(
            start=_number(value.get("start"), f"cue[{index}].start"),
            end=_number(value.get("end"), f"cue[{index}].end"),
            viseme=str(value.get("viseme", "")),
            source_shape=(str(value["source_shape"]) if value.get("source_shape") is not None else None),
        )
    else:
        raise ValueError(f"cue[{index}] must be a VisemeCue or object")
    if cue.viseme not in STUDIO_VISEMES:
        raise ValueError(f"cue[{index}] has unknown Studio viseme: {cue.viseme}")
    if cue.start < 0 or cue.end <= cue.start:
        raise ValueError(f"cue[{index}] must satisfy 0 <= start < end")
    return cue


def map_rhubarb_shape(shape: str) -> str:
    normalized = str(shape).strip().upper()
    try:
        return RHUBARB_TO_STUDIO[normalized]
    except KeyError as exc:
        raise ValueError(f"unknown Rhubarb mouth shape: {shape}") from exc


def map_studio_viseme(viseme: str) -> str:
    try:
        return STUDIO_TO_RHUBARB[str(viseme)]
    except KeyError as exc:
        raise ValueError(f"unknown Studio viseme: {viseme}") from exc


def viseme_prompt(viseme: str) -> str:
    try:
        return VISEME_PROMPTS[str(viseme)]
    except KeyError as exc:
        raise ValueError(f"unknown Studio viseme: {viseme}") from exc


def _load_json_source(source: Mapping[str, Any] | str | bytes | Path) -> dict[str, Any]:
    if isinstance(source, Mapping):
        return dict(source)
    if isinstance(source, Path):
        try:
            raw = source.read_text(encoding="utf-8")
        except OSError as exc:
            raise ValueError(f"cannot read Rhubarb JSON: {source}") from exc
    elif isinstance(source, bytes):
        try:
            raw = source.decode("utf-8-sig")
        except UnicodeDecodeError as exc:
            raise ValueError("Rhubarb JSON must be UTF-8") from exc
    elif isinstance(source, str):
        candidate = Path(source)
        stripped = source.lstrip("\ufeff \t\r\n")
        try:
            is_file = not stripped.startswith(("{", "[")) and candidate.is_file()
        except OSError:
            is_file = False
        if is_file:
            try:
                raw = candidate.read_text(encoding="utf-8")
            except OSError as exc:
                raise ValueError(f"cannot read Rhubarb JSON: {candidate}") from exc
        else:
            raw = source
    else:
        raise ValueError("Rhubarb JSON source must be an object, string, bytes, or Path")
    try:
        payload = json.loads(raw.lstrip("\ufeff"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"invalid Rhubarb JSON at line {exc.lineno}, column {exc.colno}") from exc
    if not isinstance(payload, dict):
        raise ValueError("Rhubarb JSON root must be an object")
    return payload


def parse_rhubarb_json(
    source: Mapping[str, Any] | str | bytes | Path,
    *,
    max_cues: int = 100_000,
    require_contiguous: bool = True,
    tolerance: float = 0.011,
) -> RhubarbResult:
    """Parse and validate Rhubarb's JSON export.

    Rhubarb truncates timestamps to centiseconds, hence the default 11 ms
    contiguity tolerance. Unknown shapes, overlaps, unsorted cues, invalid
    numbers, and cues outside metadata duration are rejected explicitly.
    """

    if max_cues <= 0:
        raise ValueError("max_cues must be positive")
    tolerance = _positive(tolerance, "tolerance", allow_zero=True)
    payload = _load_json_source(source)
    metadata_raw = payload.get("metadata", {})
    if not isinstance(metadata_raw, Mapping):
        raise ValueError("Rhubarb metadata must be an object")
    metadata = dict(metadata_raw)
    raw_cues = payload.get("mouthCues")
    if not isinstance(raw_cues, list):
        raise ValueError("Rhubarb mouthCues must be an array")
    if len(raw_cues) > max_cues:
        raise ValueError(f"Rhubarb mouthCues exceeds limit {max_cues}")

    cues: list[VisemeCue] = []
    previous_end = 0.0
    for index, raw in enumerate(raw_cues):
        if not isinstance(raw, Mapping):
            raise ValueError(f"mouthCues[{index}] must be an object")
        start = _number(raw.get("start"), f"mouthCues[{index}].start")
        end = _number(raw.get("end"), f"mouthCues[{index}].end")
        shape = str(raw.get("value", "")).strip().upper()
        if start < 0 or end <= start:
            raise ValueError(f"mouthCues[{index}] must satisfy 0 <= start < end")
        if index and start < previous_end - tolerance:
            raise ValueError(f"mouthCues[{index}] overlaps or is not sorted")
        if require_contiguous and abs(start - previous_end) > tolerance:
            raise ValueError(f"mouthCues[{index}] is not contiguous with the previous cue")
        cues.append(VisemeCue(start, end, map_rhubarb_shape(shape), source_shape=shape))
        previous_end = end

    raw_duration = metadata.get("duration")
    if raw_duration is None:
        if not cues:
            raise ValueError("Rhubarb metadata.duration is required when mouthCues is empty")
        duration = cues[-1].end
    else:
        duration = _positive(raw_duration, "metadata.duration", allow_zero=not cues)
    if cues and cues[-1].end > duration + tolerance:
        raise ValueError("last Rhubarb cue extends beyond metadata.duration")
    if require_contiguous and cues:
        if cues[0].start > tolerance:
            raise ValueError("first Rhubarb cue must start at zero")
        if abs(cues[-1].end - duration) > tolerance:
            raise ValueError("last Rhubarb cue must end at metadata.duration")

    sound_file = metadata.get("soundFile")
    if sound_file is not None and not isinstance(sound_file, str):
        raise ValueError("metadata.soundFile must be a string")
    return RhubarbResult(duration, tuple(cues), sound_file, metadata)


def build_rhubarb_command(
    executable: str | Path,
    audio_file: str | Path,
    *,
    output_file: str | Path | None = None,
    dialog_file: str | Path | None = None,
    language: str = "ru",
    recognizer: str | None = None,
    extended_shapes: str = "GHX",
    quiet: bool = True,
    machine_readable: bool = False,
    threads: int | None = None,
) -> list[str]:
    """Build safe Rhubarb argv; the input audio is always the final argument."""

    executable_text = str(executable).strip()
    audio_text = str(audio_file).strip()
    if not executable_text or not audio_text:
        raise ValueError("Rhubarb executable and audio_file are required")
    if Path(audio_text).suffix.lower() not in {".wav", ".ogg"}:
        raise ValueError("Rhubarb audio_file must be WAVE (.wav) or Ogg Vorbis (.ogg)")
    requested_shapes = str(extended_shapes).upper()
    if len(set(requested_shapes)) != len(requested_shapes) or any(item not in "GHX" for item in requested_shapes):
        raise ValueError("extended_shapes must contain unique characters from G, H, X")
    if recognizer is None:
        normalized_language = str(language).strip().lower().replace("_", "-")
        recognizer = "pocketSphinx" if normalized_language in {"en", "en-us", "en-gb", "english"} else "phonetic"
    if recognizer not in {"pocketSphinx", "phonetic"}:
        raise ValueError("recognizer must be pocketSphinx or phonetic")
    if threads is not None and (isinstance(threads, bool) or not isinstance(threads, int) or threads <= 0):
        raise ValueError("threads must be a positive integer")

    command = [
        executable_text,
        "--recognizer",
        recognizer,
        "--exportFormat",
        "json",
        "--extendedShapes",
        requested_shapes,
    ]
    if dialog_file is not None:
        dialog_text = str(dialog_file).strip()
        if not dialog_text:
            raise ValueError("dialog_file must not be empty")
        command.extend(["--dialogFile", dialog_text])
    if output_file is not None:
        output_text = str(output_file).strip()
        if not output_text:
            raise ValueError("output_file must not be empty")
        command.extend(["--output", output_text])
    if quiet:
        command.append("--quiet")
    if machine_readable:
        command.append("--machineReadable")
    if threads is not None:
        command.extend(["--threads", str(threads)])
    command.append(audio_text)
    return command


def validate_cues(
    cues: Sequence[VisemeCue | Mapping[str, Any]],
    *,
    duration: float,
    require_contiguous: bool = True,
    tolerance: float = _TIME_TOLERANCE,
) -> tuple[VisemeCue, ...]:
    duration = _positive(duration, "duration")
    tolerance = _positive(tolerance, "tolerance", allow_zero=True)
    normalized = tuple(_coerce_cue(item, index) for index, item in enumerate(cues))
    if not normalized:
        raise ValueError("viseme timeline must contain at least one cue")
    previous_end = 0.0
    for index, cue in enumerate(normalized):
        if cue.start < previous_end - tolerance:
            raise ValueError(f"cue[{index}] overlaps or is not sorted")
        if require_contiguous and abs(cue.start - previous_end) > tolerance:
            raise ValueError(f"cue[{index}] is not contiguous")
        if cue.end > duration + tolerance:
            raise ValueError(f"cue[{index}] extends beyond duration")
        previous_end = cue.end
    if require_contiguous:
        if normalized[0].start > tolerance:
            raise ValueError("timeline must start at zero")
        if abs(normalized[-1].end - duration) > tolerance:
            raise ValueError("timeline must end at duration")
    return normalized


def _merge_adjacent(cues: Sequence[VisemeCue], tolerance: float = _TIME_TOLERANCE) -> list[VisemeCue]:
    merged: list[VisemeCue] = []
    for cue in cues:
        if merged and merged[-1].viseme == cue.viseme and abs(merged[-1].end - cue.start) <= tolerance:
            previous = merged[-1]
            merged[-1] = VisemeCue(previous.start, cue.end, cue.viseme, previous.source_shape or cue.source_shape)
        else:
            merged.append(cue)
    return merged


def smooth_cues(
    cues: Sequence[VisemeCue | Mapping[str, Any]],
    *,
    duration: float,
    default_viseme: str = "rest",
    min_duration: float = 0.03,
    protected_visemes: Iterable[str] = _DEFAULT_PROTECTED_SHORT_VISEMES,
    tolerance: float = _TIME_TOLERANCE,
) -> tuple[VisemeCue, ...]:
    """Fill silence gaps, merge duplicates, and absorb unstable micro-cues.

    Short closure/consonant cues are protected by default because deleting
    MBP/FV/L usually hurts intelligibility more than a brief visual hold.
    """

    duration = _positive(duration, "duration")
    min_duration = _positive(min_duration, "min_duration", allow_zero=True)
    tolerance = _positive(tolerance, "tolerance", allow_zero=True)
    if default_viseme not in STUDIO_VISEMES:
        raise ValueError(f"unknown default viseme: {default_viseme}")
    protected = frozenset(str(item) for item in protected_visemes)
    unknown_protected = protected - set(STUDIO_VISEMES)
    if unknown_protected:
        raise ValueError(f"unknown protected visemes: {', '.join(sorted(unknown_protected))}")

    ordered = sorted((_coerce_cue(item, index) for index, item in enumerate(cues)), key=lambda item: item.start)
    if not ordered:
        return (VisemeCue(0.0, duration, default_viseme),)
    contiguous: list[VisemeCue] = []
    cursor = 0.0
    for index, cue in enumerate(ordered):
        if cue.start < cursor - tolerance:
            raise ValueError(f"cue[{index}] overlaps the previous cue")
        start = max(cursor, cue.start)
        if start > cursor + tolerance:
            contiguous.append(VisemeCue(cursor, start, default_viseme))
        end = min(cue.end, duration)
        if end > start + tolerance:
            contiguous.append(VisemeCue(start, end, cue.viseme, cue.source_shape))
        cursor = max(cursor, end)
        if cursor >= duration - tolerance:
            break
    if cursor < duration - tolerance:
        contiguous.append(VisemeCue(cursor, duration, default_viseme))
    if not contiguous:
        contiguous = [VisemeCue(0.0, duration, default_viseme)]
    contiguous[0] = VisemeCue(0.0, contiguous[0].end, contiguous[0].viseme, contiguous[0].source_shape)
    contiguous[-1] = VisemeCue(contiguous[-1].start, duration, contiguous[-1].viseme, contiguous[-1].source_shape)
    result = _merge_adjacent(contiguous, tolerance)

    if min_duration > 0:
        while len(result) > 1:
            short_index = next(
                (
                    index
                    for index, cue in enumerate(result)
                    if cue.duration + tolerance < min_duration and cue.viseme not in protected
                ),
                None,
            )
            if short_index is None:
                break
            index = short_index
            if 0 < index < len(result) - 1 and result[index - 1].viseme == result[index + 1].viseme:
                replacement = result[index - 1].viseme
            elif index == 0:
                replacement = result[1].viseme
            elif index == len(result) - 1:
                replacement = result[-2].viseme
            else:
                left = result[index - 1]
                right = result[index + 1]
                replacement = left.viseme if left.duration >= right.duration else right.viseme
            current = result[index]
            result[index] = VisemeCue(current.start, current.end, replacement)
            result = _merge_adjacent(result, tolerance)

    validated = validate_cues(result, duration=duration, require_contiguous=True, tolerance=tolerance)
    return tuple(
        VisemeCue(
            0.0 if index == 0 else cue.start,
            duration if index == len(validated) - 1 else cue.end,
            cue.viseme,
            cue.source_shape,
        )
        for index, cue in enumerate(validated)
    )


def _event_list(payload: Mapping[str, Any] | Sequence[Mapping[str, Any]]) -> tuple[list[Mapping[str, Any]], Mapping[str, Any]]:
    if isinstance(payload, Mapping):
        for key in ("mouthCues", "cues", "visemes", "timings", "events"):
            candidate = payload.get(key)
            if candidate is not None:
                if not isinstance(candidate, list) or any(not isinstance(item, Mapping) for item in candidate):
                    raise ValueError(f"TTS {key} must be an array of objects")
                return list(candidate), payload
        raise ValueError("TTS payload has no mouthCues/cues/visemes/timings/events array")
    if isinstance(payload, Sequence) and not isinstance(payload, (str, bytes, bytearray)):
        if any(not isinstance(item, Mapping) for item in payload):
            raise ValueError("TTS events must be objects")
        return list(payload), {}
    raise ValueError("TTS timings must be an object or array of objects")


def _time_value(event: Mapping[str, Any], names: Sequence[str], *, unit: str, ticks_per_second: float) -> float | None:
    for name in names:
        if name not in event or event[name] is None:
            continue
        value = _number(event[name], name)
        if name.endswith("_seconds"):
            return value
        if name.endswith("_ms") or name == "time_ms":
            return value / 1000.0
        effective_unit = "ticks" if name == "audio_offset" and unit == "auto" else unit
        if effective_unit in {"seconds", "second", "s", "auto"}:
            return value
        if effective_unit in {"milliseconds", "millisecond", "ms"}:
            return value / 1000.0
        if effective_unit in {"ticks", "tick"}:
            return value / ticks_per_second
        raise ValueError(f"unsupported TTS time unit: {unit}")
    return None


def _map_tts_value(
    raw: Any,
    value_map: Mapping[Any, str] | Callable[[Any], str] | None,
) -> str:
    if value_map is not None:
        if callable(value_map):
            mapped = value_map(raw)
        else:
            try:
                mapped = value_map[raw]
            except KeyError:
                try:
                    mapped = value_map[str(raw)]
                except KeyError as exc:
                    raise ValueError(f"TTS value has no viseme mapping: {raw}") from exc
        viseme = str(mapped)
    else:
        text = str(raw)
        if text in STUDIO_VISEMES:
            viseme = text
        elif text.upper() in RHUBARB_TO_STUDIO:
            viseme = map_rhubarb_shape(text)
        else:
            raise ValueError(f"TTS value requires an explicit mapping: {raw}")
    if viseme not in STUDIO_VISEMES:
        raise ValueError(f"TTS mapping returned unknown Studio viseme: {viseme}")
    return viseme


def normalize_tts_timings(
    payload: Mapping[str, Any] | Sequence[Mapping[str, Any]],
    *,
    duration: float | None = None,
    unit: str = "auto",
    ticks_per_second: float = 10_000_000.0,
    value_map: Mapping[Any, str] | Callable[[Any], str] | None = None,
    default_viseme: str = "rest",
    min_duration: float = 0.03,
) -> tuple[VisemeCue, ...]:
    """Normalize generic TTS events expressed in seconds, ms, or clock ticks.

    Supported start aliases include start/offset/time/audio_offset and their
    ``_seconds``/``_ms`` variants. Missing ends are inferred from the next
    event and the declared audio duration. Numeric provider viseme IDs require
    an explicit ``value_map``.
    """

    ticks_per_second = _positive(ticks_per_second, "ticks_per_second")
    events, envelope = _event_list(payload)
    if unit == "auto":
        declared_unit = envelope.get("time_unit", envelope.get("unit"))
        if declared_unit is not None:
            unit = str(declared_unit).strip().lower()
    if duration is None:
        for key in ("duration_seconds", "audio_duration_seconds", "duration", "audio_duration"):
            if envelope.get(key) is not None:
                candidate_unit = "seconds" if key.endswith("_seconds") else unit
                duration = _time_value({key: envelope[key]}, (key,), unit=candidate_unit, ticks_per_second=ticks_per_second)
                break
        metadata = envelope.get("metadata")
        if duration is None and isinstance(metadata, Mapping) and metadata.get("duration") is not None:
            duration = _time_value(metadata, ("duration",), unit=unit, ticks_per_second=ticks_per_second)

    provisional: list[tuple[float, float | None, str, str]] = []
    for index, event in enumerate(events):
        start = _time_value(
            event,
            ("start_seconds", "start_ms", "start", "offset_seconds", "offset_ms", "offset", "audio_offset", "time_ms", "time"),
            unit=unit,
            ticks_per_second=ticks_per_second,
        )
        if start is None:
            raise ValueError(f"TTS event[{index}] has no start/offset/time")
        if start < 0:
            raise ValueError(f"TTS event[{index}] starts before zero")
        end = _time_value(
            event,
            ("end_seconds", "end_ms", "end"),
            unit=unit,
            ticks_per_second=ticks_per_second,
        )
        if end is None:
            event_duration = _time_value(
                event,
                ("duration_seconds", "duration_ms", "duration"),
                unit=unit,
                ticks_per_second=ticks_per_second,
            )
            if event_duration is not None:
                end = start + event_duration
        raw_value = next(
            (event[key] for key in ("viseme", "value", "shape", "viseme_id", "phoneme") if event.get(key) is not None),
            None,
        )
        if raw_value is None:
            raise ValueError(f"TTS event[{index}] has no viseme/value/shape/viseme_id/phoneme")
        provisional.append((start, end, _map_tts_value(raw_value, value_map), str(raw_value)))

    provisional.sort(key=lambda item: item[0])
    if duration is None:
        explicit_ends = [item[1] for item in provisional if item[1] is not None]
        if len(explicit_ends) != len(provisional) or not explicit_ends:
            raise ValueError("audio duration is required when the last TTS event has no end")
        duration = max(float(item) for item in explicit_ends)
    duration = _positive(duration, "duration")

    cues: list[VisemeCue] = []
    for index, (start, explicit_end, viseme, source_shape) in enumerate(provisional):
        next_start = provisional[index + 1][0] if index + 1 < len(provisional) else duration
        end = explicit_end if explicit_end is not None else next_start
        if end > next_start + _TIME_TOLERANCE:
            raise ValueError(f"TTS event[{index}] overlaps the next event")
        if end <= start:
            raise ValueError(f"TTS event[{index}] has non-positive duration")
        cues.append(VisemeCue(start, min(end, duration), viseme, source_shape=source_shape))
    return smooth_cues(
        cues,
        duration=duration,
        default_viseme=default_viseme,
        min_duration=min_duration,
    )


def plan_viseme_atlas(
    visemes: Sequence[str] = STUDIO_VISEMES,
    *,
    cell_width: int,
    cell_height: int,
    columns: int = 5,
    padding: int = 0,
) -> dict[str, Any]:
    if not visemes:
        raise ValueError("atlas requires at least one viseme")
    if len(set(visemes)) != len(visemes):
        raise ValueError("atlas viseme ids must be unique")
    unknown = set(visemes) - set(STUDIO_VISEMES)
    if unknown:
        raise ValueError(f"atlas contains unknown visemes: {', '.join(sorted(unknown))}")
    for name, value in (("cell_width", cell_width), ("cell_height", cell_height), ("columns", columns)):
        if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
            raise ValueError(f"{name} must be a positive integer")
    if isinstance(padding, bool) or not isinstance(padding, int) or padding < 0:
        raise ValueError("padding must be a non-negative integer")
    rows = math.ceil(len(visemes) / columns)
    width = columns * cell_width + (columns + 1) * padding
    height = rows * cell_height + (rows + 1) * padding
    cells: list[dict[str, Any]] = []
    for index, viseme in enumerate(visemes):
        column = index % columns
        row = index // columns
        x = padding + column * (cell_width + padding)
        y = padding + row * (cell_height + padding)
        cells.append(
            {
                "index": index,
                "viseme": viseme,
                "x": x,
                "y": y,
                "width": cell_width,
                "height": cell_height,
                "uv": {
                    "u0": round(x / width, 8),
                    "v0": round(y / height, 8),
                    "u1": round((x + cell_width) / width, 8),
                    "v1": round((y + cell_height) / height, 8),
                },
            }
        )
    return {
        "schema_version": VISEME_ATLAS_SCHEMA,
        "width": width,
        "height": height,
        "cell_width": cell_width,
        "cell_height": cell_height,
        "columns": columns,
        "rows": rows,
        "padding": padding,
        "cells": cells,
    }


ImageInput = Image.Image | str | Path


def _load_rgba(source: ImageInput) -> Image.Image:
    if isinstance(source, Image.Image):
        return source.convert("RGBA").copy()
    with Image.open(Path(source)) as image:
        return ImageOps.exif_transpose(image).convert("RGBA").copy()


def pack_viseme_atlas(
    images: Mapping[str, ImageInput],
    *,
    visemes: Sequence[str] = STUDIO_VISEMES,
    cell_size: tuple[int, int] | None = None,
    columns: int = 5,
    padding: int = 0,
    target: str | Path | None = None,
) -> tuple[Image.Image, dict[str, Any]]:
    if set(images) != set(visemes):
        missing = set(visemes) - set(images)
        extra = set(images) - set(visemes)
        details = []
        if missing:
            details.append(f"missing={','.join(sorted(missing))}")
        if extra:
            details.append(f"extra={','.join(sorted(extra))}")
        raise ValueError("atlas image set does not match visemes: " + " ".join(details))
    loaded = {viseme: _load_rgba(images[viseme]) for viseme in visemes}
    if cell_size is None:
        cell_width = max(image.width for image in loaded.values())
        cell_height = max(image.height for image in loaded.values())
    else:
        cell_width, cell_height = cell_size
    plan = plan_viseme_atlas(
        visemes,
        cell_width=cell_width,
        cell_height=cell_height,
        columns=columns,
        padding=padding,
    )
    atlas = Image.new("RGBA", (plan["width"], plan["height"]), (0, 0, 0, 0))
    for cell in plan["cells"]:
        image = ImageOps.contain(
            loaded[cell["viseme"]],
            (cell_width, cell_height),
            Image.Resampling.LANCZOS,
        )
        x = cell["x"] + (cell_width - image.width) // 2
        y = cell["y"] + (cell_height - image.height) // 2
        atlas.alpha_composite(image, (x, y))
    if target is not None:
        output = Path(target)
        output.parent.mkdir(parents=True, exist_ok=True)
        atlas.save(output, format="PNG")
        plan["image_path"] = str(output.resolve())
    return atlas, plan


def validate_mouth_roi(roi: Mapping[str, Any], *, canvas_width: int, canvas_height: int) -> dict[str, int]:
    if not isinstance(roi, Mapping):
        raise ValueError("mouth_roi must be an object")
    for name, value in (("canvas_width", canvas_width), ("canvas_height", canvas_height)):
        if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
            raise ValueError(f"{name} must be a positive integer")
    values: dict[str, int] = {}
    for key in ("x", "y", "width", "height"):
        value = roi.get(key)
        if isinstance(value, bool) or not isinstance(value, int):
            raise ValueError(f"mouth_roi.{key} must be an integer")
        values[key] = value
    if values["x"] < 0 or values["y"] < 0 or values["width"] <= 0 or values["height"] <= 0:
        raise ValueError("mouth_roi must have non-negative origin and positive size")
    if values["x"] + values["width"] > canvas_width or values["y"] + values["height"] > canvas_height:
        raise ValueError("mouth_roi extends outside the anchor canvas")
    return values


def build_runtime_timeline(
    cues: Sequence[VisemeCue | Mapping[str, Any]],
    *,
    duration: float,
    fps: float,
    atlas: Mapping[str, Any],
    audio: Mapping[str, Any] | None = None,
    default_viseme: str = "rest",
) -> dict[str, Any]:
    """Build a frame-addressable runtime manifest backed by a W9 atlas."""

    duration = _positive(duration, "duration")
    fps = _positive(fps, "fps")
    if default_viseme not in STUDIO_VISEMES:
        raise ValueError(f"unknown default viseme: {default_viseme}")
    normalized = validate_cues(cues, duration=duration, require_contiguous=True)
    if atlas.get("schema_version") != VISEME_ATLAS_SCHEMA:
        raise ValueError("atlas has an unsupported schema_version")
    raw_cells = atlas.get("cells")
    if not isinstance(raw_cells, list):
        raise ValueError("atlas.cells must be an array")
    cell_by_viseme: dict[str, dict[str, Any]] = {}
    for cell in raw_cells:
        if not isinstance(cell, Mapping) or str(cell.get("viseme", "")) not in STUDIO_VISEMES:
            raise ValueError("atlas contains an invalid cell")
        viseme = str(cell["viseme"])
        if viseme in cell_by_viseme:
            raise ValueError(f"atlas contains duplicate viseme cell: {viseme}")
        cell_by_viseme[viseme] = dict(cell)
    needed = {cue.viseme for cue in normalized} | {default_viseme}
    missing = needed - set(cell_by_viseme)
    if missing:
        raise ValueError(f"atlas is missing timeline visemes: {', '.join(sorted(missing))}")

    frame_count = max(1, math.ceil(duration * fps))
    frame_visemes: list[str] = []
    cue_index = 0
    for frame_index in range(frame_count):
        timestamp = min((frame_index + 0.5) / fps, math.nextafter(duration, 0.0))
        while cue_index + 1 < len(normalized) and timestamp >= normalized[cue_index].end:
            cue_index += 1
        frame_visemes.append(normalized[cue_index].viseme)

    segments: list[dict[str, Any]] = []
    for frame_index, viseme in enumerate(frame_visemes):
        if segments and segments[-1]["viseme"] == viseme:
            segments[-1]["end_frame"] = frame_index + 1
            segments[-1]["end_seconds"] = _round_time(min((frame_index + 1) / fps, duration))
            continue
        cell = cell_by_viseme[viseme]
        segments.append(
            {
                "start_frame": frame_index,
                "end_frame": frame_index + 1,
                "start_seconds": _round_time(frame_index / fps),
                "end_seconds": _round_time(min((frame_index + 1) / fps, duration)),
                "viseme": viseme,
                "atlas_index": int(cell["index"]),
                "uv": dict(cell.get("uv", {})),
            }
        )
    return {
        "schema_version": VISEME_TIMELINE_SCHEMA,
        "runtime_ready": True,
        "duration_seconds": _round_time(duration),
        "fps": float(fps),
        "frame_count": frame_count,
        "default_viseme": default_viseme,
        "audio": dict(audio or {}),
        "mapping": {
            "rhubarb_to_studio": dict(RHUBARB_TO_STUDIO),
            "studio_to_rhubarb": dict(STUDIO_TO_RHUBARB),
        },
        "atlas": dict(atlas),
        "cues": [cue.to_dict() for cue in normalized],
        "segments": segments,
    }


def timeline_to_json(manifest: Mapping[str, Any], *, indent: int = 2) -> str:
    return json.dumps(dict(manifest), ensure_ascii=False, indent=indent, sort_keys=True)


def write_timeline(manifest: Mapping[str, Any], target: str | Path) -> Path:
    output = Path(target).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(timeline_to_json(manifest) + "\n", encoding="utf-8")
    return output
