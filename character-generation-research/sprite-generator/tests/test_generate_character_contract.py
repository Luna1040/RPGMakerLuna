import json
from pathlib import Path

import pytest
from PIL import Image, ImageChops

from sprite_extractor import comfy_postprocess, comfy_workflow, generate_character
from sprite_extractor import extract_frames
from sprite_extractor.io_utils import load_json


WORKFLOW = comfy_workflow.original_workflow_path()
FULL_WORKFLOW = comfy_workflow.bundled_workflow_path()


def test_actual_workflow_changes_only_approved_reference_and_idle_style_leaves():
    source, rendered = comfy_workflow.load_and_render_workflow(
        WORKFLOW, "video-to-sprites/uploaded.webp", uploaded_dummy="video-to-sprites/dummy.png",
        render_width=400, render_height=600, neutral_idle=False, seed=123456
    )

    # The supplied workflow already sets the feminine/false value.  The
    # renderer must still set it explicitly, without treating an unchanged
    # value as an unauthorized graph mutation.
    assert comfy_workflow.graph_change_paths(source, rendered) <= {
        ("114", "inputs", "image"),
        ("283", "inputs", "image"),
        ("244", "inputs", "value"),
        ("245", "inputs", "value"),
        ("343", "inputs", "value"),
        ("124", "inputs", "seed"),
    }
    assert rendered["114"]["inputs"]["image"] == "video-to-sprites/uploaded.webp"
    assert rendered["283"]["inputs"]["image"] == "video-to-sprites/dummy.png"
    assert rendered["244"]["inputs"]["value"] == 1600
    assert rendered["245"]["inputs"]["value"] == 600
    assert rendered["343"]["inputs"]["value"] is False
    assert rendered["124"]["inputs"]["seed"] == 123456


def test_model_config_covers_and_overrides_every_safetensors_workflow_input(monkeypatch, tmp_path):
    monkeypatch.setattr(comfy_workflow, "user_workflow_config_path", lambda: tmp_path / "absent.yaml")
    raw_models = comfy_workflow._configured_model_inputs(load_json(WORKFLOW))
    default_models = comfy_workflow._configured_model_inputs(comfy_workflow.load_configured_workflow(WORKFLOW))
    assert default_models.keys() == raw_models.keys()
    assert default_models["154", "unet_name"] == "DasiwaMinimaxH3_dasiwaREF2VAHybridV1.safetensors"

    config = tmp_path / "config.yaml"
    config.write_text('workflow_models:\n  "149":\n    clip_name: alternate-clip.safetensors\n')

    source, _rendered = comfy_workflow.load_and_render_workflow(
        WORKFLOW, "video-to-sprites/uploaded.webp", neutral_idle=False, seed=7, config_path=config
    )

    assert source["149"]["inputs"]["clip_name"] == "alternate-clip.safetensors"
    assert len(comfy_workflow._configured_model_inputs(source)) == 5


def test_full_workflow_reuses_models_and_exports_only_requested_animation_outputs(monkeypatch, tmp_path):
    monkeypatch.setattr(comfy_workflow, "user_workflow_config_path", lambda: tmp_path / "absent.yaml")
    graph = comfy_workflow.load_configured_workflow(FULL_WORKFLOW)
    original = comfy_workflow.load_configured_workflow(WORKFLOW)

    assert comfy_workflow.workflow_output_nodes(graph) == {
        "run": "92",
        "idle": "341",
        "jump": "362",
        "crouch": "379",
        "crouch_walk": "424",
        "walk": "456",
    }
    assert {"394", "441"}.isdisjoint(comfy_workflow.workflow_output_nodes(graph).values())
    assert graph["316"]["inputs"]["on_false"] == ["426", 0]
    assert graph["316"]["inputs"]["on_true"] == ["427", 0]
    assert original["313"]["inputs"]["value"] == graph["426"]["inputs"]["value"]
    assert original["314"]["inputs"]["value"] == graph["427"]["inputs"]["value"]
    assert comfy_workflow._configured_model_inputs(graph) == comfy_workflow._configured_model_inputs(
        comfy_workflow.load_configured_workflow(WORKFLOW)
    )


def test_dummy_workflow_reference_is_bundled_and_valid():
    path = comfy_workflow.bundled_dummy_reference_path()

    assert path.name == "dummy_rembg_quarters_75_888888.png"
    assert path.is_file()
    with Image.open(path) as image:
        image.verify()
    with Image.open(path) as image:
        assert image.mode == "RGB"
        assert image.size == (1616, 640)
        combined = image.copy()

    views = comfy_workflow.bundled_dummy_view_paths()
    assert [item.name for item in views] == ["1-right.png", "2-left.png", "3-back.png", "4-front.png"]
    for index, view in enumerate(views):
        with Image.open(view) as image:
            assert image.mode == "RGB"
            assert image.size == (404, 640)
            background = Image.new("RGB", image.size, image.getpixel((0, 0)))
            top_padding = Image.new("RGB", (404, 48), image.getpixel((0, 0)))
            assert ImageChops.difference(image.crop((0, 0, 404, 48)), top_padding).getbbox() is None
            bounds = ImageChops.difference(image, background).getbbox()
            assert bounds is not None
            assert (bounds[0] + bounds[2]) / 2 == pytest.approx(202, abs=1)
            assert (bounds[1] + bounds[3]) / 2 == pytest.approx(368, abs=1)
            quarter = combined.crop((index * 404, 0, (index + 1) * 404, 640))
            assert ImageChops.difference(image, quarter).getbbox() is None


def test_source_assets_match_packaged_workflow_resources():
    source_root = Path(__file__).resolve().parents[1] / "workflows"
    packaged_root = comfy_workflow.bundled_workflow_path().parent

    names = [
        comfy_workflow.bundled_workflow_path().name,
        comfy_workflow.bundled_dummy_reference_path().name,
    ]
    for name in names:
        assert (source_root / name).read_bytes() == (packaged_root / name).read_bytes()
    for packaged_view in comfy_workflow.bundled_dummy_view_paths():
        assert (source_root / "dummy-views" / packaged_view.name).read_bytes() == packaged_view.read_bytes()


def test_dummy_views_are_scaled_center_fitted_and_joined_for_each_render(tmp_path):
    target = comfy_workflow.render_dummy_reference(tmp_path / "dummy.png", 320, 512)

    with Image.open(target) as image:
        assert image.mode == "RGB"
        assert image.size == (1280, 512)
        assert image.getpixel((0, 0)) == (136, 136, 136)

    fitted = comfy_workflow.render_dummy_reference(tmp_path / "fitted.png", 400, 600)
    with Image.open(fitted) as image:
        assert image.size == (1600, 600)
        assert image.getpixel((0, 0)) == (136, 136, 136)

    base = comfy_workflow.render_dummy_reference(tmp_path / "base.png", 400, 512)
    padded = comfy_workflow.render_dummy_reference(tmp_path / "padded.png", 400, 512, 15)
    with Image.open(base) as base_image, Image.open(padded) as padded_image:
        assert padded_image.size == (1600, 589)
        top = Image.new("RGB", (1600, 77), padded_image.getpixel((0, 0)))
        assert ImageChops.difference(padded_image.crop((0, 0, 1600, 77)), top).getbbox() is None
        assert ImageChops.difference(padded_image.crop((0, 77, 1600, 589)), base_image).getbbox() is None


def test_postprocess_workflows_batch_inputs_and_apply_configured_models(monkeypatch, tmp_path):
    monkeypatch.setattr(comfy_workflow, "user_workflow_config_path", lambda: tmp_path / "absent.yaml")
    settings = comfy_postprocess.postprocess_settings()
    uploads = [
        {"name": "first.png", "subfolder": "sprite-extractor", "type": "input"},
        {"name": "second.png", "subfolder": "sprite-extractor", "type": "input"},
    ]

    pose = comfy_postprocess.render_sdpose_workflow(uploads, settings)
    background = comfy_postprocess.render_background_workflow(uploads, settings)

    assert pose["2"]["inputs"]["ckpt_name"] == "sdpose_wholebody_fp16.safetensors"
    assert pose["3"]["inputs"]["batch_size"] == 8
    assert pose["3"]["inputs"]["image"] == ["1003", 0]
    assert pose["1002"]["inputs"]["image"] == "sprite-extractor/second.png"
    assert background["2"]["inputs"]["bg_removal_name"] == "BiRefNet.safetensors"
    assert background["3"]["inputs"]["image"] == ["1003", 0]


def test_postprocess_workflow_model_paths_are_loaded_from_config(monkeypatch, tmp_path):
    monkeypatch.setattr(comfy_workflow, "user_workflow_config_path", lambda: tmp_path / "absent.yaml")
    config = tmp_path / "config.yaml"
    config.write_text('''postprocess_workflow_models:
  sdpose:
    "2":
      ckpt_name: custom-sdpose.safetensors
  background-removal:
    "2":
      bg_removal_name: custom-birefnet.safetensors
''')

    settings = comfy_postprocess.postprocess_settings(config)
    uploads = [{"name": "input.png", "subfolder": "", "type": "input"}]
    pose = comfy_postprocess.render_sdpose_workflow(uploads, settings)
    background = comfy_postprocess.render_background_workflow(uploads, settings)

    assert pose["2"]["inputs"]["ckpt_name"] == "custom-sdpose.safetensors"
    assert background["2"]["inputs"]["bg_removal_name"] == "custom-birefnet.safetensors"


def test_postprocess_config_must_cover_every_connected_safetensors_input(monkeypatch, tmp_path):
    config = tmp_path / "config.default.yaml"
    text = comfy_workflow.default_workflow_config_path().read_text()
    config.write_text(text.replace("      bg_removal_name: BiRefNet.safetensors\n", ""))
    monkeypatch.setattr(comfy_workflow, "default_workflow_config_path", lambda: config)
    monkeypatch.setattr(comfy_workflow, "user_workflow_config_path", lambda: tmp_path / "absent.yaml")

    with pytest.raises(ValueError, match="missing background-removal.2.bg_removal_name"):
        comfy_postprocess.postprocess_settings(config)


def test_config_layers_deep_merge_and_explicit_overrides_win(monkeypatch, tmp_path):
    user = tmp_path / "config.yaml"
    user.write_text('sprite_box_height: 160\nworkflow_models:\n  "154":\n    unet_name: local-unet.safetensors\n')
    first = tmp_path / "first.yaml"
    first.write_text('sprite_box_height: 192\nworkflow_models:\n  "154":\n    unet_name: first-unet.safetensors\n')
    second = tmp_path / "second.yaml"
    second.write_text('workflow_models:\n  "154":\n    unet_name: final-unet.safetensors\n')
    monkeypatch.setattr(comfy_workflow, "user_workflow_config_path", lambda: user)

    _path, document = comfy_workflow._load_config_document([first, second])

    assert document["sprite_box_height"] == 192
    assert document["workflow_models"]["154"]["unet_name"] == "final-unet.safetensors"
    assert document["workflow_models"]["149"]["clip_name"] == "qwen3vl_32b_minimax_h3_int8_convrot.safetensors"


def test_sdpose_history_text_is_parsed_as_json():
    frames = [{"canvas_width": 100, "canvas_height": 200, "people": []}]
    record = {"outputs": {"4": {"text": [json.dumps(frames)]}}}

    assert comfy_postprocess._parse_pose_output(record) == frames


def test_prompt_submission_preserves_workflow_in_extra_pnginfo(monkeypatch):
    client = comfy_workflow.ComfyClient("http://localhost:8188")
    captured = {}
    monkeypatch.setattr(client, "_json", lambda path, payload: captured.update(path=path, payload=payload) or {"prompt_id": "p-1"})
    graph = {"114": {"class_type": "LoadImage", "inputs": {"image": "input.webp"}}}

    assert client.submit(graph, client_id="fixed") == "p-1"
    assert captured["path"] == "/prompt"
    assert captured["payload"]["prompt"] is graph
    assert captured["payload"]["extra_data"]["extra_pnginfo"]["workflow"] is graph
    assert captured["payload"]["client_id"] == "fixed"


class _Client:
    events = []

    def __init__(self, server):
        self.server = server
        self.events.append(("client", server))

    def upload_image(self, source):
        self.events.append(("upload", Path(source).name))
        return {"name": Path(source).name, "subfolder": "video-to-sprites", "type": "input"}

    def submit(self, graph, *, client_id=None):
        self.events.append(("submit", graph["114"]["inputs"]["image"], graph["343"]["inputs"]["value"], graph["283"]["inputs"]["image"], graph["244"]["inputs"]["value"], graph["245"]["inputs"]["value"], graph["124"]["inputs"]["seed"]))
        return "prompt-{}".format(len([event for event in self.events if event[0] == "submit"]))

    def wait(self, prompt_id, **kwargs):
        self.events.append(("wait", prompt_id))
        return {"outputs": {"92": {"gifs": [{"filename": "run.mp4"}]}, "341": {"gifs": [{"filename": "idle.mp4"}]}}}

    def output_descriptor(self, record, node):
        self.events.append(("descriptor", node))
        return {"filename": "{}.mp4".format("run" if node == "92" else "idle"), "subfolder": "", "type": "output"}

    def download(self, descriptor, destination):
        self.events.append(("download", descriptor["filename"]))
        destination = Path(destination)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(b"mock-video")
        return destination

    def free_if_idle(self):
        self.events.append(("free",))
        return True

    def wait_until_idle(self):
        self.events.append(("idle",))
        return True


def test_generation_queues_every_input_before_polling_and_downloads_only_run_idle(monkeypatch, tmp_path):
    source = tmp_path / "images"
    source.mkdir()
    for name in ("a.png", "b.png"):
        Image.new("RGBA", (2, 2), (10, 20, 30, 255)).save(source / name)
    _Client.events = []
    monkeypatch.setattr(generate_character, "ComfyClient", _Client)
    monkeypatch.setattr(generate_character.random, "randrange", lambda _limit: 123456)

    state = generate_character.generate_videos(
        source, tmp_path / "out", WORKFLOW, idle_style="feminine", poll_interval=0.001
    )

    event_names = [event[0] for event in _Client.events]
    assert event_names.index("wait") > max(i for i, name in enumerate(event_names) if name == "submit")
    assert [event[2] for event in _Client.events if event[0] == "submit"] == [False, False]
    assert [event[3:] for event in _Client.events if event[0] == "submit"] == [("video-to-sprites/workflow-dummy-reference.png", 1600, 512, 123456)] * 2
    assert [event[1] for event in _Client.events if event[0] == "upload"][0] == "workflow-dummy-reference.png"
    assert [event[1] for event in _Client.events if event[0] == "descriptor"] == ["92", "341", "92", "341"]
    assert [event[1] for event in _Client.events if event[0] == "client"] == ["http://localhost:8188"]
    assert state["generation_complete"] is True
    assert state["seed"] == 123456
    assert state["seed_mode"] == "random"
    assert state["dummy_reference"]["pad_top_percent"] == 0
    assert state["dummy_reference"]["pad_top_pixels"] == 0
    assert state["dummy_reference"]["combined_height"] == 512
    assert all(character["status"] == "downloaded" for character in state["characters"])
    saved = json.loads((tmp_path / "out" / "generation-state.json").read_text())
    assert [set(item["videos"]) for item in saved["characters"]] == [{"run", "idle"}, {"run", "idle"}]

    _Client.events = []
    resumed = generate_character.generate_videos(
        source, tmp_path / "out", WORKFLOW, idle_style="feminine", poll_interval=0.001
    )
    assert resumed["generation_complete"] is True
    assert not [event for event in _Client.events if event[0] in {"upload", "submit", "wait", "download"}]

    with pytest.raises(ValueError, match="resume seed differs"):
        generate_character.generate_videos(
            source, tmp_path / "out", WORKFLOW, idle_style="feminine", seed=654321,
            poll_interval=0.001,
        )


def test_legacy_state_recovers_seed_from_rendered_workflow(monkeypatch, tmp_path):
    source = tmp_path / "reference.png"
    Image.new("RGBA", (2, 2), (10, 20, 30, 255)).save(source)
    output = tmp_path / "out"
    _Client.events = []
    monkeypatch.setattr(generate_character, "ComfyClient", _Client)

    generate_character.generate_videos(source, output, WORKFLOW, seed=366, poll_interval=0.001)
    state_path = output / "generation-state.json"
    legacy = json.loads(state_path.read_text())
    legacy.pop("seed")
    legacy.pop("seed_mode")
    state_path.write_text(json.dumps(legacy))
    monkeypatch.setattr(generate_character.random, "randrange", lambda _limit: pytest.fail("legacy resume generated a new seed"))

    resumed = generate_character.generate_videos(source, output, WORKFLOW, poll_interval=0.001)

    assert resumed["seed"] == 366
    assert resumed["seed_mode"] == "legacy"
    saved = json.loads(state_path.read_text())
    assert saved["seed"] == 366
    assert saved["seed_mode"] == "legacy"


def test_full_image_cli_uses_default_action_counts_and_single_orchestrator(monkeypatch, tmp_path):
    source = tmp_path / "images"
    source.mkdir()
    Image.new("RGBA", (2, 2), (1, 2, 3, 255)).save(source / "reference.png")
    captured = {}

    def fake_process(image, output, workflow, **kwargs):
        captured.update(image=Path(image), output=Path(output), workflow=Path(workflow), kwargs=kwargs)
        return {"complete": True}

    monkeypatch.setattr(generate_character, "process_characters", fake_process)
    output = tmp_path / "output"
    assert extract_frames.main([
        str(source), "--output", str(output), "--workflow", str(WORKFLOW), "--idle-style", "feminine"
    ]) == 0
    assert captured["image"] == source.resolve()
    assert captured["output"] == output.resolve()
    assert captured["workflow"] == WORKFLOW.resolve()
    assert captured["kwargs"]["run_frames"] == 8
    assert captured["kwargs"]["walk_frames"] == 8
    assert captured["kwargs"]["idle_frames"] == 4
    assert captured["kwargs"]["jump_frames"] == 8
    assert captured["kwargs"]["crouch_walk_frames"] == 8
    assert captured["kwargs"]["sprite_height"] == 256
    assert captured["kwargs"]["sprite_render_width"] == 400
    assert captured["kwargs"]["sprite_render_height"] == 512
    assert captured["kwargs"]["pad_top_percent"] == 0
    assert captured["kwargs"]["timeout"] == 7200
    assert captured["kwargs"]["seed"] == -1
    assert captured["kwargs"]["idle_style"] == "feminine"
    assert captured["kwargs"]["postprocess_options"]["directions"] == ["right", "left", "back", "front"]
    assert captured["kwargs"]["postprocess_options"]["split_algorithm"] == "blobs"


def test_full_image_cli_allows_sprite_box_height_override(monkeypatch, tmp_path):
    source = tmp_path / "reference.png"
    Image.new("RGBA", (2, 2), (1, 2, 3, 255)).save(source)
    captured = {}

    def fake_process(_image, _output, _workflow, **kwargs):
        captured.update(kwargs)
        return {"complete": True}

    monkeypatch.setattr(generate_character, "process_characters", fake_process)
    assert extract_frames.main([
        str(source), "--output", str(tmp_path / "output"), "--workflow", str(WORKFLOW),
        "--sprite-box-height", "192", "--split-algorithm", "quarters",
    ]) == 0
    assert captured["sprite_height"] == 192
    assert captured["postprocess_options"]["split_algorithm"] == "quarters"


def test_full_image_cli_allows_sprite_render_size_override(monkeypatch, tmp_path):
    source = tmp_path / "reference.png"
    Image.new("RGBA", (2, 2), (1, 2, 3, 255)).save(source)
    captured = {}

    def fake_process(_image, _output, _workflow, **kwargs):
        captured.update(kwargs)
        return {"complete": True}

    monkeypatch.setattr(generate_character, "process_characters", fake_process)
    assert extract_frames.main([
        str(source), "--output", str(tmp_path / "output"), "--workflow", str(WORKFLOW),
        "--sprite-render-width", "384", "--sprite-render-height", "576", "--pad-top-percent", "15",
    ]) == 0
    assert captured["sprite_render_width"] == 384
    assert captured["sprite_render_height"] == 576
    assert captured["pad_top_percent"] == 15


def test_full_image_cli_allows_animation_frame_overrides(monkeypatch, tmp_path):
    source = tmp_path / "reference.png"
    Image.new("RGBA", (2, 2), (1, 2, 3, 255)).save(source)
    captured = {}

    def fake_process(_image, _output, _workflow, **kwargs):
        captured.update(kwargs)
        return {"complete": True}

    monkeypatch.setattr(generate_character, "process_characters", fake_process)
    assert extract_frames.main([
        str(source), "--output", str(tmp_path / "output"), "--workflow", str(WORKFLOW),
        "--seed", "42", "--idle-frames", "3", "--run-frames", "6", "--walk-frames", "7", "--jump-frames", "10",
        "--crouch-walk-frames", "5",
    ]) == 0
    assert {name: captured[name] for name in ("idle_frames", "run_frames", "walk_frames", "jump_frames", "crouch_walk_frames")} == {
        "idle_frames": 3, "run_frames": 6, "walk_frames": 7, "jump_frames": 10, "crouch_walk_frames": 5,
    }
    assert captured["seed"] == 42


def test_full_image_cli_accepts_repeatable_config_overrides(monkeypatch, tmp_path):
    source = tmp_path / "reference.png"
    Image.new("RGBA", (2, 2), (1, 2, 3, 255)).save(source)
    first = tmp_path / "first.yaml"
    first.write_text("sprite_box_height: 160\nanimation_frames:\n  jump: 9\n")
    second = tmp_path / "second.yaml"
    second.write_text("sprite_box_height: 224\ngeneration_timeout: 9000\nseed: 73\nanimation_frames:\n  walk: 7\n  jump: 10\n  crouch_walk: 6\n")
    captured = {}

    def fake_process(_image, _output, _workflow, **kwargs):
        captured.update(kwargs)
        return {"complete": True}

    monkeypatch.setattr(generate_character, "process_characters", fake_process)
    assert extract_frames.main([
        str(source), "--output", str(tmp_path / "output"), "--workflow", str(WORKFLOW),
        "--config", str(first), "--config", str(second),
    ]) == 0
    assert captured["sprite_height"] == 224
    assert captured["timeout"] == 9000
    assert captured["seed"] == 73
    assert captured["postprocess_options"]["timeout"] == 9000
    assert captured["jump_frames"] == 10
    assert captured["walk_frames"] == 7
    assert captured["crouch_walk_frames"] == 6
    assert captured["workflow_config"] == [first.resolve(), second.resolve()]


def test_workflow_aliases_select_full_and_original(monkeypatch, tmp_path):
    source = tmp_path / "reference.png"
    Image.new("RGBA", (2, 2), (1, 2, 3, 255)).save(source)
    selected = []

    def fake_process(_image, _output, workflow, **_kwargs):
        selected.append(Path(workflow))
        return {"complete": True}

    monkeypatch.setattr(generate_character, "process_characters", fake_process)
    assert extract_frames.main([str(source), "--output", str(tmp_path / "full"), "--workflow", "bundled"]) == 0
    assert extract_frames.main([str(source), "--output", str(tmp_path / "old"), "--workflow", "original"]) == 0
    assert selected == [FULL_WORKFLOW.resolve(), WORKFLOW.resolve()]


def test_sprite_box_height_comes_from_config_and_defaults_to_256(tmp_path):
    assert comfy_workflow.configured_sprite_box_height() == 256
    config = tmp_path / "config.yaml"
    config.write_text("sprite_box_height: 256\n")
    assert comfy_workflow.configured_sprite_box_height(config) == 256

    config.write_text("sprite_box_height: false\n")
    with pytest.raises(ValueError, match="positive integer"):
        comfy_workflow.configured_sprite_box_height(config)


def test_generation_timeout_comes_from_config_and_defaults_to_120_minutes(tmp_path):
    assert comfy_workflow.configured_generation_timeout() == 7200
    config = tmp_path / "config.yaml"
    config.write_text("generation_timeout: 9000.5\n")
    assert comfy_workflow.configured_generation_timeout(config) == 9000.5

    config.write_text("generation_timeout: false\n")
    with pytest.raises(ValueError, match="positive finite number of seconds"):
        comfy_workflow.configured_generation_timeout(config)


def test_seed_comes_from_config_and_defaults_to_random_sentinel(tmp_path):
    assert comfy_workflow.configured_seed() == -1
    config = tmp_path / "config.yaml"
    config.write_text("seed: 123456789\n")
    assert comfy_workflow.configured_seed(config) == 123456789

    for value in ("true", "-2", str(comfy_workflow.MAX_SEED + 1)):
        config.write_text(f"seed: {value}\n")
        with pytest.raises(ValueError, match="seed must be -1 or an integer"):
            comfy_workflow.configured_seed(config)


def test_sprite_render_size_comes_from_config_and_defaults_to_400_by_512(tmp_path):
    assert comfy_workflow.configured_sprite_render_size() == (400, 512)
    config = tmp_path / "config.yaml"
    config.write_text("sprite_render_width: 384\nsprite_render_height: 576\n")
    assert comfy_workflow.configured_sprite_render_size(config) == (384, 576)

    config.write_text("sprite_render_width: false\n")
    with pytest.raises(ValueError, match="positive integers"):
        comfy_workflow.configured_sprite_render_size(config)


def test_dummy_top_padding_comes_from_config_and_defaults_to_zero(tmp_path):
    assert comfy_workflow.configured_pad_top_percent() == 0
    assert comfy_workflow.dummy_top_padding_pixels(512, 15) == 77
    config = tmp_path / "config.yaml"
    config.write_text("pad_top_percent: 12.5\n")
    assert comfy_workflow.configured_pad_top_percent(config) == 12.5

    for value in ("false", "-1", ".nan"):
        config.write_text(f"pad_top_percent: {value}\n")
        with pytest.raises(ValueError, match="nonnegative finite number"):
            comfy_workflow.configured_pad_top_percent(config)


def test_animation_frame_counts_come_from_config_and_jump_defaults_to_eight(tmp_path):
    assert comfy_workflow.configured_animation_frame_counts() == {
        "idle": 4, "run": 8, "walk": 8, "jump": 8, "crouch_walk": 8,
    }
    config = tmp_path / "config.yaml"
    config.write_text("animation_frames:\n  idle: 3\n  jump: 10\n")
    assert comfy_workflow.configured_animation_frame_counts(config) == {
        "idle": 3, "run": 8, "walk": 8, "jump": 10, "crouch_walk": 8,
    }

    config.write_text("animation_frames:\n  run: false\n")
    with pytest.raises(ValueError, match="integers of at least 2"):
        comfy_workflow.configured_animation_frame_counts(config)
