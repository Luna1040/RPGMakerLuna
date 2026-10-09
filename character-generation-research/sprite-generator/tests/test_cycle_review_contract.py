"""Offline contracts for durable candidate-cycle discovery."""

from __future__ import annotations

import json
import math
from pathlib import Path
from types import SimpleNamespace

from PIL import Image

from sprite_extractor import diagnose_cycle
from sprite_extractor import cycle_review


class _TimeBase:
    def seconds(self, pts: int) -> float:
        return pts / 1_000


def _analysis_args(raw_pose: Path, output: Path, count: int) -> SimpleNamespace:
    return SimpleNamespace(
        raw_pose=str(raw_pose), output=str(output), frame_count=count,
        min_period=0.8, max_period=1.2, sign_confidence=0.5,
        overlap_tolerance=0.05,
    )


def _raw_pose(times: list[float]) -> dict:
    observations = []
    for frame_id, time_seconds in enumerate(times):
        # Named ankles preserve their identity; their anti-phase one-second
        # cadence deliberately gives several complete intervals.
        right_y = 64 + 12 * math.sin(2 * math.pi * time_seconds)
        left_y = 64 - 12 * math.sin(2 * math.pi * time_seconds)
        observations.append(
            {
                "frame_id": frame_id,
                "pts": round(time_seconds * 1_000),
                "time_seconds": time_seconds,
                "points": [
                    {"name": "right_ankle", "full_x": 80, "full_y": right_y, "raw_score": 1},
                    {"name": "left_ankle", "full_x": 20, "full_y": left_y, "raw_score": 1},
                ],
            }
        )
    return {
        "source": {"path": "/fixture-vfr.mp4", "sha256": "fixture-video", "width": 400, "height": 64},
        "crop": {"x0": 300, "x1": 400, "y0": 0, "y1": 64},
        "model": {"pose_sha256": "pose", "detector_sha256": "detector", "implementation": "fixture"},
        "observations": observations,
    }


def test_candidate_discovery_preserves_complete_vfr_cycles_and_frame_count_independent_ids(tmp_path, monkeypatch):
    # Alternating intervals make PTS intentionally variable rather than a CFR
    # fixture.  The sampler must retain actual nearest source PTS/time values.
    times = [0.0]
    for index in range(1, 101):
        times.append(times[-1] + (0.043 if index % 2 else 0.057))
    raw_path = tmp_path / "raw_pose.json"
    raw_path.write_text(json.dumps(_raw_pose(times)))
    decoded = tmp_path / "decoded"
    decoded.mkdir()
    frames = []
    for frame_id, time_seconds in enumerate(times):
        image = decoded / f"{frame_id}.png"
        Image.new("RGB", (400, 64), (frame_id % 255, 0, 0)).save(image)
        frames.append(SimpleNamespace(frame_id=frame_id, pts=round(time_seconds * 1_000), decode_path=str(image)))
    media = SimpleNamespace(width=400, height=64, content_sha256="fixture-video", time_base=_TimeBase())
    monkeypatch.setattr(diagnose_cycle, "probe_media", lambda _path: media)
    monkeypatch.setattr(diagnose_cycle, "decode_frames", lambda *_args, **_kwargs: frames)

    output8 = tmp_path / "eight"
    diagnose_cycle.analyze(_analysis_args(raw_path, output8, 8))
    summary8 = json.loads((output8 / "summary.json").read_text())
    candidates8 = summary8["cycle_candidates"]
    assert summary8["version"] == "1.1"
    assert candidates8 == sorted(candidates8, key=lambda item: item["start_time_seconds"])
    assert all(item["start_time_seconds"] < item["end_time_seconds"] <= times[-1] for item in candidates8)
    assert all(len(item["frames"]) == 8 for item in candidates8)
    assert all(len({frame["frame_id"] for frame in item["frames"]}) == 8 for item in candidates8)
    assert all(
        [frame["pts"] for frame in item["frames"]] == sorted(frame["pts"] for frame in item["frames"])
        for item in candidates8
    )
    selected_index = next(index for index, item in enumerate(candidates8) if item["id"] == summary8["system_candidate_id"])
    assert selected_index == (len(candidates8) - 1) // 2
    assert summary8["six_frame_cycle"]["candidate_id"] == summary8["system_candidate_id"]
    assert summary8["six_frame_cycle"]["frames"] == candidates8[selected_index]["frames"]
    assert (output8 / "summary.json").is_file()
    assert (output8 / "predicted_cycle_starts-contact-sheet.png").is_file()
    assert (output8 / "ankle-y-waveforms.svg").is_file()
    assert all((output8 / frame["path"]).is_file() for candidate in candidates8 for frame in candidate["frames"])

    output6 = tmp_path / "six"
    diagnose_cycle.analyze(_analysis_args(raw_path, output6, 6))
    summary6 = json.loads((output6 / "summary.json").read_text())
    assert summary6["analysis_id"] == summary8["analysis_id"]
    assert [item["id"] for item in summary6["cycle_candidates"]] == [item["id"] for item in candidates8]
    assert all(len(item["frames"]) == 6 for item in summary6["cycle_candidates"])

    # A sparse/VFR interval that cannot supply distinct nearest source frames
    # is not allowed to erase the valid lower-median default.  It may be
    # excluded from the gallery, but the legacy automatic result remains the
    # same candidate and frames.
    original_nearest = diagnose_cycle._nearest_frames
    selected_start = candidates8[selected_index]["start_time_seconds"]

    def sparse_alternative(raw, sample_times):
        if len(sample_times) == 8 and not math.isclose(sample_times[0], selected_start):
            raise ValueError("duplicate source frames")
        return original_nearest(raw, sample_times)

    monkeypatch.setattr(diagnose_cycle, "_nearest_frames", sparse_alternative)
    resilient = tmp_path / "resilient"
    diagnose_cycle.analyze(_analysis_args(raw_path, resilient, 8))
    resilient_summary = json.loads((resilient / "summary.json").read_text())
    assert resilient_summary["system_candidate_id"] == summary8["system_candidate_id"]
    assert resilient_summary["six_frame_cycle"]["frames"] == summary8["six_frame_cycle"]["frames"]


def test_seeded_raw_pose_cache_reuses_pose_and_resamples_only_for_new_frame_count(tmp_path, monkeypatch):
    video = tmp_path / "video.mp4"; video.write_bytes(b"video")
    evidence = tmp_path / "raw_pose.json"
    evidence.write_text(json.dumps({"source": {"sha256": "video-sha"}, "observations": []}))
    media = SimpleNamespace(width=400, height=64, content_sha256="video-sha")
    calls: list[int] = []
    monkeypatch.setattr(cycle_review, "probe_media", lambda _path: media)
    monkeypatch.setattr(cycle_review, "postprocess_settings", lambda _config: {"sdpose_checkpoint": "pose"})
    monkeypatch.setattr(cycle_review, "extract_sdpose", lambda *_args: (_ for _ in ()).throw(AssertionError("SDPose must not run")))
    def fake_worker(args):
        calls.append(args.frame_count)
        root = Path(args.output); (root / "frames").mkdir(parents=True)
        frame = root / "frames" / "one.png"; frame.write_bytes(b"frame")
        summary = {"cycle_candidates": [{"id": "candidate", "frames": [{"path": "frames/one.png"}]}], "system_candidate_id": "candidate", "six_frame_cycle": {"frames": []}}
        (root / "summary.json").write_text(json.dumps(summary)); (root / "manifest.json").write_text("{}")
    monkeypatch.setattr(cycle_review, "_worker", fake_worker)
    root = tmp_path / "cache"
    first = cycle_review.ensure_cycle_analysis(video, root, frame_count=8, server=None, config={}, timeout=1, poll_interval=0, raw_pose_evidence=evidence)
    assert calls == [8]
    assert cycle_review.ensure_cycle_analysis(video, root, frame_count=8, server=None, config={}, timeout=1, poll_interval=0, raw_pose_evidence=evidence) == first
    assert calls == [8]
    second = cycle_review.ensure_cycle_analysis(video, root, frame_count=6, server=None, config={}, timeout=1, poll_interval=0, raw_pose_evidence=evidence)
    assert second != first and calls == [8, 6]
