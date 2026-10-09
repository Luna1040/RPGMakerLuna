import json
import struct
from types import SimpleNamespace

import numpy as np
import pytest
from PIL import Image

from sprite_extractor import animate_frames, diagnose_cycle, extract_frames, sprite_sheet, sprite_split


class _FixedMasks:
    """A deterministic non-binary full-frame matte provider for packing tests."""

    def masks(self, arrays):
        output = []
        for array in arrays:
            height, width = array.shape[:2]
            mask = np.zeros((height, width), dtype=np.float32)
            # Four equally sized source views, each with a non-square matte
            # strip.  The half-alpha interior detects accidental binary alpha.
            for view in range(4):
                left = view * width // 4 + width // 20
                right = (view + 1) * width // 4 - width // 20
                mask[height // 5 : height * 4 // 5, left:right] = 0.5
            output.append(mask)
        return np.stack(output)


class _UnevenMasks:
    def masks(self, arrays):
        output = []
        for frame_index, array in enumerate(arrays):
            height, width = array.shape[:2]
            mask = np.zeros((height, width), dtype=np.float32)
            bounds = ((10, 45 + frame_index), (75, 135), (190, 225), (280, 370))
            for left, right in bounds:
                mask[height // 5 : height * 4 // 5, left:right] = 0.5
            mask[0, 160:162] = 0.04
            output.append(mask)
        return np.stack(output)


def _fixture_root(tmp_path, size=(400, 100), frame_count=6):
    root = tmp_path / "sequence"
    frames = root / "frames"
    frames.mkdir(parents=True)
    records = []
    for frame_id in range(frame_count):
        # Deliberately non-square, four-view source dimensions.
        image = Image.new("RGB", size, (30 + frame_id, 70, 120))
        name = f"frames/{frame_id:02d}.png"
        image.save(root / name)
        records.append({"path": name, "frame_id": frame_id, "pts": frame_id * 1000})
    (root / "summary.json").write_text(json.dumps({
        "period": {"seconds": 0.75},
        "six_frame_cycle": {"frames": records},
    }))
    (root / "raw_pose.json").write_text(json.dumps({"unused": True}))
    return root


def _anmf_durations(path):
    data = path.read_bytes()
    assert data[:4] == b"RIFF" and data[8:12] == b"WEBP"
    offset = 12
    durations = []
    while offset + 8 <= len(data):
        tag = data[offset : offset + 4]
        size = struct.unpack_from("<I", data, offset + 4)[0]
        payload = data[offset + 8 : offset + 8 + size]
        if tag == b"ANMF":
            durations.append(payload[12] | payload[13] << 8 | payload[14] << 16)
        offset += 8 + size + (size & 1)
    return durations


def test_premultiplied_resize_preserves_normalized_rgb_and_soft_alpha():
    rgb = np.full((2, 3, 3), [0.2, 0.4, 0.8], dtype=np.float32)
    alpha = np.full((2, 3), 0.5, dtype=np.float32)

    output = np.asarray(sprite_sheet._premultiplied_resize(rgb, alpha, (3, 2)))

    assert output[0, 0].tolist() == [51, 102, 204, 128]


def test_blob_split_removes_low_alpha_noise_and_uses_gap_midpoints():
    mask = _UnevenMasks().masks([np.zeros((100, 400, 3), dtype=np.float32)])[0]

    cleaned, edges, blobs = sprite_split.split_edges(mask, "blobs")

    assert cleaned[0, 160] == 0
    assert edges == [0, 60, 162, 252, 400]
    assert [(blob.x0, blob.x1) for blob in blobs] == [(10, 45), (75, 135), (190, 225), (280, 370)]


def test_blob_split_requires_four_usable_components():
    mask = np.zeros((20, 100), dtype=np.float32)
    mask[2:18, 10:30] = 1

    with pytest.raises(ValueError, match="--sprite-render-width PIXELS"):
        sprite_split.split_edges(mask, "blobs")


def test_blob_split_centers_uneven_views_in_fixed_cells(monkeypatch, tmp_path):
    root = _fixture_root(tmp_path)
    monkeypatch.setattr(sprite_sheet, "_ground", lambda summary, raw: (75.0, {"method": "mock"}))

    result = sprite_sheet.build(root, 128, ["right", "left", "back", "front"], _UnevenMasks())

    assert result["splitting"]["algorithm"] == "blobs"
    assert result["splitting"]["alpha_noise_threshold"] == 0.05
    assert result["splitting"]["basis"] == "combined-selected-frame-alpha"
    assert result["splitting"]["source_edges"] == [0, 62, 162, 252, 400]
    assert {tuple(frame["source_edges"]) for frame in result["splitting"]["frames"]} == {(0, 62, 162, 252, 400)}
    with Image.open(root / "sprite-sheet-128h.png") as sheet:
        alpha = sheet.getchannel("A")
        cell = result["layout"]["cell_size"]
        for row in range(4):
            bounds = [alpha.crop((column * cell, row * cell, (column + 1) * cell, (row + 1) * cell)).getbbox() for column in range(6)]
            valid = [box for box in bounds if box is not None]
            assert valid
            assert (min(box[0] for box in valid) + max(box[2] for box in valid)) / 2 == pytest.approx(cell / 2, abs=1)


def test_sheet_packs_four_rows_and_six_columns_with_stable_origin(monkeypatch, tmp_path):
    root = _fixture_root(tmp_path)
    monkeypatch.setattr(sprite_sheet, "_ground", lambda summary, raw: (75.0, {"method": "mock"}))

    result = sprite_sheet.build(
        root, 128, ["right", "left", "back", "front"], _FixedMasks(), "quarters"
    )

    with Image.open(root / "sprite-sheet-128h.png") as sheet:
        assert sheet.size == (768, 512)  # six 128px cells by four rows
        alpha = np.asarray(sheet.getchannel("A"))
    assert np.any((alpha > 0) & (alpha < 255)), "matte alpha must not be squared/binarized"
    assert result["layout"] == {
        "rows": 4,
        "columns": 6,
        "cell_size": 128,
        "direction_order": ["right", "left", "back", "front"],
    }
    assert len(result["cells"]) == 24
    assert {cell["row"] for cell in result["cells"]} == {0, 1, 2, 3}
    assert {cell["column"] for cell in result["cells"]} == set(range(6))
    assert len(set(result["row_horizontal_offsets"])) == 1
    assert result["origin"]["x"] == 64
    assert result["origin"]["y"] == pytest.approx(96.0)
    assert result["vertical_padding"] == {"top": 0, "bottom": 0}
    assert result["source_paths"] == [f"frames/{frame_id:02d}.png" for frame_id in range(6)]

    with pytest.raises(FileExistsError):
        sprite_sheet.build(root, 128, ["right", "left", "back", "front"], _FixedMasks(), "quarters")


def test_wide_source_uses_vertical_padding_and_scaled_ground_origin(monkeypatch, tmp_path):
    root = _fixture_root(tmp_path, size=(1000, 100))
    monkeypatch.setattr(sprite_sheet, "_ground", lambda summary, raw: (75.0, {"method": "mock"}))

    result = sprite_sheet.build(
        root, 128, ["right", "left", "back", "front"], _FixedMasks(), "quarters"
    )

    # A 10:1 source becomes 1280px wide, so every 320px view needs a
    # 320px square cell and a 96px vertical top/bottom pad.
    assert result["layout"]["cell_size"] == 320
    assert result["vertical_padding"] == {"top": 96, "bottom": 96}
    assert result["origin"]["x"] == 160
    assert result["origin"]["y"] == pytest.approx(192.0)
    with Image.open(root / "sprite-sheet-128h.png") as sheet:
        assert sheet.size == (1920, 1280)


@pytest.mark.parametrize("frame_count", [4, 8])
def test_variable_count_keeps_uniform_chronological_cells_and_exact_webp_timing(monkeypatch, tmp_path, frame_count):
    root = _fixture_root(tmp_path, frame_count=frame_count)
    monkeypatch.setattr(sprite_sheet, "_ground", lambda summary, raw: (75.0, {"method": "mock"}))

    packed = sprite_sheet.build(root, 128, ["right", "left", "back", "front"], _FixedMasks(), "quarters")
    encoded = animate_frames.encode(root, 128)

    assert packed["layout"]["columns"] == frame_count
    assert len(packed["cells"]) == 4 * frame_count
    assert [cell["source_frame_id"] for cell in packed["cells"] if cell["row"] == 0] == list(range(frame_count))
    assert packed["cycle"] == {"seconds": 0.75, "milliseconds": 750}
    assert packed["origin"]["x"] == 64
    assert packed["origin"]["y"] == pytest.approx(96.0)
    with Image.open(root / "sprite-sheet-128h.png") as sheet:
        assert sheet.size == (128 * frame_count, 512)
    assert encoded["frame_count"] == frame_count
    assert len(encoded["frame_durations_ms"]) == frame_count
    assert all(duration > 0 for duration in encoded["frame_durations_ms"])
    assert sum(encoded["frame_durations_ms"]) == 750
    assert _anmf_durations(root / "cycle-128h.webp") == encoded["frame_durations_ms"]


def test_uniform_nearest_samples_are_chronological_and_overdense_samples_fail():
    raw = {"observations": [
        {"frame_id": frame_id, "time_seconds": frame_id / 10}
        for frame_id in range(12)
    ]}
    selected = diagnose_cycle._nearest_frames(raw, [0.1 + index * 0.8 / 4 for index in range(4)])
    assert [item["frame_id"] for item in selected] == [1, 3, 5, 7]
    selected = diagnose_cycle._nearest_frames(raw, [0.1 + index * 0.8 / 8 for index in range(8)])
    assert [item["frame_id"] for item in selected] == list(range(1, 9))
    with pytest.raises(ValueError, match="duplicate source frames"):
        diagnose_cycle._nearest_frames(raw, [0.01, 0.02])


def test_cycle_selection_uses_lower_median():
    assert diagnose_cycle._lower_median([1.0, 2.0, 3.0]) == 2.0
    assert diagnose_cycle._lower_median([1.0, 2.0, 3.0, 4.0]) == 2.0
    with pytest.raises(ValueError, match="empty sequence"):
        diagnose_cycle._lower_median([])


@pytest.mark.parametrize("count", ["0", "1", "-1", "not-an-integer"])
def test_extract_cli_rejects_invalid_frame_count_before_inference(tmp_path, count):
    output = tmp_path / "must-not-exist"
    with pytest.raises(SystemExit):
        extract_frames.main(["tmp/test-sprite-videos", "--output", str(output), "--frame-count", count])
    assert not output.exists()


@pytest.mark.parametrize(("requested", "expected"), [(None, "8"), ("7", "7")])
def test_directory_cli_forwards_frame_count_to_each_worker(monkeypatch, tmp_path, requested, expected):
    source_dir = tmp_path / "sources"
    source_dir.mkdir()
    (source_dir / "single.mp4").write_bytes(b"not decoded: subprocess is mocked")
    captured = []

    def fake_run(command, **kwargs):
        captured.append(command)
        return SimpleNamespace(returncode=0)

    monkeypatch.setattr(extract_frames.subprocess, "run", fake_run)
    argv = [str(source_dir), "--output", str(tmp_path / "out")]
    if requested is not None:
        argv.extend(["--frame-count", requested])
    assert extract_frames.main(argv) == 0
    assert len(captured) == 1
    command = captured[0]
    assert command[command.index("--frame-count") + 1] == expected
    assert command[command.index("--split-algorithm") + 1] == "blobs"


def test_analyze_rejects_invalid_count_before_reading_raw_pose(tmp_path):
    with pytest.raises(ValueError, match="frame_count must be at least 2"):
        diagnose_cycle.analyze(SimpleNamespace(
            frame_count=1,
            raw_pose=str(tmp_path / "does-not-exist.json"),
            output=str(tmp_path / "output"),
        ))


def test_sheet_rejects_cycle_too_short_for_positive_frame_holds(monkeypatch, tmp_path):
    root = _fixture_root(tmp_path, frame_count=4)
    summary_path = root / "summary.json"
    summary = json.loads(summary_path.read_text())
    summary["period"]["seconds"] = 0.003
    summary_path.write_text(json.dumps(summary))
    monkeypatch.setattr(sprite_sheet, "_ground", lambda summary, raw: (75.0, {"method": "mock"}))
    with pytest.raises(ValueError, match="too short"):
        sprite_sheet.build(root, 128, ["right", "left", "back", "front"], _FixedMasks(), "quarters")
