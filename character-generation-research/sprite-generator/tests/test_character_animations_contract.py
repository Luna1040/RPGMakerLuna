import json
import struct
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pytest
from PIL import Image

from sprite_extractor import character_animations, extract_frames


def _durations_from_webp(path):
    data = path.read_bytes()
    values = []
    offset = 12
    while offset + 8 <= len(data):
        tag = data[offset : offset + 4]
        size = struct.unpack_from("<I", data, offset + 4)[0]
        payload = data[offset + 8 : offset + 8 + size]
        if tag == b"ANMF":
            values.append(payload[12] | payload[13] << 8 | payload[14] << 16)
        offset += 8 + size + (size & 1)
    return values


class _OpaqueMasks:
    def masks(self, arrays):
        return np.stack([np.ones(array.shape[:2], dtype=np.float32) for array in arrays])


class _FirstViewOnlyMasks:
    def masks(self, arrays):
        output = []
        for array in arrays:
            mask = np.zeros(array.shape[:2], dtype=np.float32)
            mask[:, : array.shape[1] // 4] = 1.0
            output.append(mask)
        return np.stack(output)


class _FrameVaryingMasks:
    def masks(self, arrays):
        output = []
        for index, array in enumerate(arrays):
            mask = np.zeros(array.shape[:2], dtype=np.float32)
            for left, right in ((10, 45 + index), (80, 135), (190, 225), (280, 370)):
                mask[20:80, left:right] = 1.0
            output.append(mask)
        return np.stack(output)


class _AnimationShiftMasks:
    def masks(self, arrays):
        output = []
        for index, array in enumerate(arrays):
            mask = np.zeros(array.shape[:2], dtype=np.float32)
            left, right = (10, 30) if index < 4 else (60, 90)
            for view in range(4):
                mask[20:80, view * 100 + left:view * 100 + right] = 1.0
            output.append(mask)
        return np.stack(output)


def _run_export(tmp_path, count=8, name="run-export"):
    root = tmp_path / name
    frames = root / "frames"
    frames.mkdir(parents=True)
    records = []
    for index in range(count):
        name = f"frames/run-{index}.png"
        Image.new("RGB", (400, 100), (20 + index, 70, 120)).save(root / name)
        records.append({"frame_id": index, "pts": index * 100, "time_seconds": index / 10, "path": name})
    (root / "summary.json").write_text(json.dumps({
        "source": {"sha256": "run-source"},
        "period": {"seconds": 0.75},
        "six_frame_cycle": {"frames": records},
    }))
    (root / "raw_pose.json").write_text(json.dumps({"unused": True}))
    return root


def _fake_idle_frames(video, count, destination):
    records = []
    for index in range(count):
        path = destination / f"frame-{index:04d}-source-{index:06d}.png"
        Image.new("RGB", (400, 100), (120, 30 + index, 40)).save(path)
        records.append({"frame_id": index, "pts": index * 100, "duration_ticks": 100, "time_seconds": index / 4, "path": str(path)})
    source = SimpleNamespace(content_sha256="idle-source", time_base=SimpleNamespace(numerator=1, denominator=1000))
    return source, 1.0, records


def _pack(monkeypatch, tmp_path, masks=_OpaqueMasks, split_algorithm="quarters"):
    run = _run_export(tmp_path)
    monkeypatch.setattr(character_animations, "_idle_frames", _fake_idle_frames)
    def fake_background_masks(paths, *_args, **_kwargs):
        arrays = []
        for path in paths:
            with Image.open(path) as image:
                arrays.append(np.asarray(image.convert("RGB"), np.float32) / 255.0)
        return list(masks().masks(arrays)), {"background_removal_model": "mock.safetensors"}
    monkeypatch.setattr(character_animations, "_background_masks", fake_background_masks)
    monkeypatch.setattr(character_animations, "_ground", lambda *_args: (75.0, {"method": "mock"}))
    return character_animations._pack_character_animations(
        run, tmp_path / "idle.mp4", tmp_path / "sprites", idle_frames=4, height=128,
        split_algorithm=split_algorithm,
    )


def test_pack_combines_idle_and_run_into_four_by_twelve_sheet_and_eight_webps(monkeypatch, tmp_path):
    manifest = _pack(monkeypatch, tmp_path)
    output = tmp_path / "sprites"

    assert manifest["layout"]["rows"] == 4
    assert manifest["layout"]["columns"] == 12
    assert manifest["layout"]["animation_ranges"] == {"idle": [0, 4], "run": [4, 12]}
    assert len(manifest["cells"]) == 48
    assert manifest["origin"] == {"x": 64.0, "y": 96.0, "coordinate_basis": "cell_top_left_pixels"}
    assert set(manifest["animation_horizontal_offsets"]) == {"idle", "run"}
    assert all(len(offsets) == 4 for offsets in manifest["animation_horizontal_offsets"].values())
    assert all(entry["rect"]["width"] == 128 and entry["rect"]["height"] == 128 for entry in manifest["cells"])
    assert all(entry["path"].startswith("idle-frames/") for entry in manifest["actions"]["idle"]["frames"])
    assert all(entry["path"].startswith("run-frames/") for entry in manifest["actions"]["run"]["frames"])
    with Image.open(output / manifest["sheet"]) as sheet:
        assert sheet.mode == "RGBA"
        assert sheet.size == (1536, 512)
    assert len(manifest["webps"]) == 8
    for key, name in manifest["webps"].items():
        with Image.open(output / name) as image:
            assert image.size == (128, 128)
            assert image.n_frames == (4 if key.startswith("idle:") else 8)
            assert image.info["loop"] == 0
        durations = _durations_from_webp(output / name)
        assert all(value > 0 for value in durations)
        assert sum(durations) == (1000 if key.startswith("idle:") else 750)


def test_pack_rejects_empty_direction_row(monkeypatch, tmp_path):
    with pytest.raises(ValueError, match="has no foreground alpha"):
        _pack(monkeypatch, tmp_path, masks=_FirstViewOnlyMasks)


def test_pack_uses_one_combined_mask_cut_for_every_action_frame(monkeypatch, tmp_path):
    manifest = _pack(monkeypatch, tmp_path, masks=_FrameVaryingMasks, split_algorithm="blobs")

    assert manifest["splitting"]["basis"] == "combined-selected-frame-alpha"
    assert manifest["splitting"]["source_edges"] == [0, 68, 162, 252, 400]
    assert {tuple(frame["source_edges"]) for frame in manifest["splitting"]["frames"]} == {(0, 68, 162, 252, 400)}


def test_pack_centers_each_whole_animation_from_its_combined_alpha_masks(monkeypatch, tmp_path):
    manifest = _pack(monkeypatch, tmp_path, masks=_AnimationShiftMasks, split_algorithm="quarters")

    assert manifest["horizontal_centering"]["basis"] == "per-animation-direction-combined-alpha"
    assert manifest["animation_horizontal_offsets"]["idle"] != manifest["animation_horizontal_offsets"]["run"]
    with Image.open(tmp_path / "sprites" / manifest["sheet"]) as sheet:
        alpha = np.asarray(sheet.getchannel("A"))
    cell = manifest["layout"]["cell_size"]
    for row in range(4):
        for start, end in manifest["layout"]["animation_ranges"].values():
            combined = np.maximum.reduce([
                alpha[row * cell:(row + 1) * cell, column * cell:(column + 1) * cell]
                for column in range(start, end)
            ])
            columns = np.flatnonzero(np.any(combined > 0, axis=0))
            assert (columns[0] + columns[-1] + 1) / 2 == pytest.approx(cell / 2, abs=0.5)


def test_pinned_cycle_candidate_feeds_packer_without_analysis_and_reuses_masks(monkeypatch, tmp_path):
    """A revision packs the chosen immutable samples and only masks newly selected pixels."""
    source = tmp_path / "run.mp4"
    source.write_bytes(b"immutable generated video")
    analysis = tmp_path / "analysis"
    frames = analysis / "frames"
    frames.mkdir(parents=True)

    def frame(name, color, frame_id):
        path = frames / name
        Image.new("RGB", (400, 100), color).save(path)
        return {
            "frame_id": frame_id,
            "pts": frame_id * 100,
            "time_seconds": frame_id / 10,
            "path": f"frames/{name}",
            "sha256": __import__("hashlib").sha256(path.read_bytes()).hexdigest(),
        }

    shared = frame("shared.png", (20, 70, 120), 1)
    automatic = frame("automatic.png", (30, 70, 120), 2)
    chosen = frame("chosen.png", (40, 70, 120), 3)
    summary = {
        "analysis_id": "analysis-id",
        "sample_set_id": "sample-id",
        "source": {"sha256": __import__("hashlib").sha256(source.read_bytes()).hexdigest()},
        "period": {"seconds": 0.5},
        "selected_frame_count": 2,
        "system_candidate_id": "automatic",
        "cycle_candidates": [
            {"id": "automatic", "start_time_seconds": 0, "sample_times_seconds": [0, .25], "frames": [shared, automatic]},
            {"id": "chosen", "start_time_seconds": .1, "sample_times_seconds": [.1, .35], "frames": [shared, chosen]},
        ],
    }
    (analysis / "summary.json").write_text(json.dumps(summary))
    (analysis / "raw_pose.json").write_text("{}")

    mask_calls = []

    def fake_masks(_client, paths, destination, **_kwargs):
        paths = list(paths)
        mask_calls.append([Path(path).name for path in paths])
        destination.mkdir(parents=True, exist_ok=True)
        generated = []
        for index, path in enumerate(paths):
            with Image.open(path) as image:
                target = destination / f"mask-{index}.png"
                Image.new("L", image.size, 255).save(target)
                generated.append(target)
        return generated, {"background_removal_model": "mock"}

    monkeypatch.setattr(character_animations, "postprocess_settings", lambda _config: {"background_removal_model": "mock", "sdpose_checkpoint": "mock-pose"})
    monkeypatch.setattr(character_animations, "remove_background_masks", fake_masks)
    monkeypatch.setattr(character_animations, "ComfyClient", lambda *_args: SimpleNamespace(free_if_idle=lambda: True))
    monkeypatch.setattr(character_animations, "_ground", lambda *_args: (75.0, {"method": "mock"}))
    monkeypatch.setattr(extract_frames, "_worker", lambda *_args: pytest.fail("pinned analysis must not run SDPose or extraction"))
    common = {
        "videos": {"run": source}, "poses": {}, "frame_counts": {"run": 2},
        "action_policies": {"run": {"method": "cycle"}}, "action_order": ("run",),
        "height": 64, "split_algorithm": "quarters", "pinned_analyses": {"run": analysis},
        "mask_cache_root": tmp_path / "mask-cache", "config": {}, "server": "http://mock.invalid",
    }
    first = character_animations.build_selected_character_animations(
        output=tmp_path / "automatic-package", cycle_selections={"run": "automatic"}, **common
    )
    second = character_animations.build_selected_character_animations(
        output=tmp_path / "chosen-package", cycle_selections={"run": "chosen"}, **common
    )

    assert first["cycle_selections"]["run"]["candidate_id"] == "automatic"
    assert second["cycle_selections"]["run"]["candidate_id"] == "chosen"
    assert [Path(item["path"]).name for item in second["actions"]["run"]["frames"]] == ["shared.png", "chosen.png"]
    assert json.loads((tmp_path / "chosen-package" / "timing-evidence/run-extraction/summary.json").read_text())["six_frame_cycle"]["candidate_id"] == "chosen"
    assert mask_calls == [["shared.png", "automatic.png"], ["chosen.png"]]


def test_full_pack_adds_jump_crouch_crouch_walk_and_walk(monkeypatch, tmp_path):
    run = _run_export(tmp_path)
    crouch_walk = _run_export(tmp_path, count=5, name="crouch-walk-export")
    walk = _run_export(tmp_path, count=6, name="walk-export")
    monkeypatch.setattr(character_animations, "_idle_frames", _fake_idle_frames)
    monkeypatch.setattr(character_animations, "_jump_frames", lambda video,count,destination: _fake_idle_frames(video,count,destination))
    monkeypatch.setattr(character_animations, "_crouch_frame", lambda video,destination: _fake_idle_frames(video,1,destination))

    def fake_background_masks(paths, *_args, **_kwargs):
        arrays = []
        for path in paths:
            with Image.open(path) as image:
                arrays.append(np.asarray(image.convert("RGB"), np.float32) / 255.0)
        return [np.ones(array.shape[:2], dtype=np.float32) for array in arrays], {"background_removal_model": "mock.safetensors"}

    monkeypatch.setattr(character_animations, "_background_masks", fake_background_masks)
    monkeypatch.setattr(character_animations, "_ground", lambda *_args: (75.0, {"method": "mock"}))
    output = tmp_path / "sprites"
    manifest = character_animations._pack_character_animations(
        run,
        tmp_path / "idle.mp4",
        output,
        idle_frames=4,
        jump_frames=7,
        crouch_walk_frames=5,
        walk_frames=6,
        jump_video=tmp_path / "jump.mp4",
        crouch_video=tmp_path / "crouch.mp4",
        crouch_walk_export=crouch_walk,
        walk_export=walk,
        height=128,
        split_algorithm="quarters",
    )

    assert manifest["layout"]["columns"] == 31
    assert manifest["layout"]["animation_ranges"] == {
        "idle": [0, 4], "run": [4, 12], "jump": [12, 19], "crouch": [19, 20], "crouch_walk": [20, 25], "walk": [25, 31]
    }
    assert {name for name in manifest["actions"]} == {"idle", "run", "jump", "crouch", "crouch_walk", "walk"}
    assert manifest["actions"]["jump"]["frame_count"] == 7
    assert manifest["actions"]["jump"]["looping"] is True
    assert manifest["actions"]["crouch"]["frame_count"] == 1
    assert manifest["actions"]["crouch"]["looping"] is False
    assert manifest["actions"]["crouch_walk"]["frame_count"] == 5
    assert manifest["actions"]["walk"]["frame_count"] == 6
    assert manifest["actions"]["run"]["frame_count"] == 8
    assert len(manifest["webps"]) == 20
    assert not any(key.startswith("crouch:") for key in manifest["webps"])
    for direction in ("right", "left", "back", "front"):
        with Image.open(output / manifest["webps"][f"jump:{direction}"]) as image:
            assert image.n_frames == 7
            assert image.info["loop"] == 0
        with Image.open(output / manifest["webps"][f"crouch_walk:{direction}"]) as image:
            assert image.n_frames == 5
            assert image.info["loop"] == 0
        with Image.open(output / manifest["webps"][f"walk:{direction}"]) as image:
            assert image.n_frames == 6
            assert image.info["loop"] == 0


def test_full_build_runs_cycle_extraction_for_walk(monkeypatch, tmp_path):
    videos = {}
    for action in ("run", "idle", "jump", "crouch", "crouch_walk", "walk"):
        path = tmp_path / f"{action}.mp4"
        path.write_bytes(action.encode())
        videos[action] = path

    calls = []

    def fake_worker(args):
        target = Path(args.output)
        (target / "frames").mkdir(parents=True)
        (target / "frames" / "frame.png").write_bytes(b"frame")
        (target / "summary.json").write_text("{}")
        (target / "raw_pose.json").write_text("{}")
        calls.append((Path(args.input).name, target.name, args.frame_count))

    packed = {}

    def fake_pack(run_export, idle_video, output, **kwargs):
        Path(output).mkdir(parents=True)
        packed.update(run_export=Path(run_export), idle_video=Path(idle_video), kwargs=kwargs)
        return {"version": "1.0"}

    monkeypatch.setattr(extract_frames, "_worker", fake_worker)
    monkeypatch.setattr(character_animations, "_pack_character_animations", fake_pack)
    monkeypatch.setattr(character_animations, "postprocess_settings", lambda _config: {
        "sdpose_checkpoint": "pose.safetensors",
        "background_removal_model": "background.safetensors",
    })

    output = tmp_path / "sprites"
    character_animations.build_character_animations(
        videos["run"], videos["idle"], output,
        jump_video=videos["jump"], crouch_video=videos["crouch"],
        crouch_walk_video=videos["crouch_walk"], walk_video=videos["walk"],
        run_frames=6, walk_frames=7, jump_frames=8, crouch_walk_frames=5,
    )

    assert calls == [
        ("run.mp4", "run-extraction", 6),
        ("crouch_walk.mp4", "crouch-walk-extraction", 5),
        ("walk.mp4", "walk-extraction", 7),
    ]
    assert packed["kwargs"]["walk_export"].name == "walk-extraction"
    assert packed["kwargs"]["walk_frames"] == 7
    assert (output / "walk-frames" / "frame.png").is_file()
    assert (output / "timing-evidence" / "walk-extraction" / "summary.json").is_file()


def test_positive_duration_guard():
    with pytest.raises(ValueError, match="too short"):
        character_animations._durations(3, 4)
