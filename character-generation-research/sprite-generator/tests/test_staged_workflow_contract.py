import json
from pathlib import Path

import pytest
from PIL import Image

from sprite_extractor import staged_workflow
from sprite_extractor import extract_frames
from sprite_extractor import character_animations
from sprite_extractor import definition_runtime


STAGES = {
    "run": ("92", "Running Animation"),
    "stop": ("309", "Stopping animation"),
    "idle": ("341", "Idle Animation"),
    "jump": ("362", "Jumping animation"),
    "crouch": ("379", "Crouch animation"),
    "crouch_start": ("394", "Stationary crouch to crouch walk"),
    "crouch_walk": ("424", "Crouch walk"),
    "walk_start": ("441", "Idle to walk"),
    "walk": ("456", "Walk loop"),
}

BASELINE_POSE_NODES = {"run": "300", "stop": "319", "idle": "342", "jump": "363", "crouch": "380", "crouch_start": "395", "crouch_walk": "425", "walk_start": "442", "walk": "457"}


def _source_stage_path(stage: str) -> Path:
    return Path(__file__).resolve().parents[1] / "workflows" / "staged" / f"{stage}.json"


def _links(value):
    if isinstance(value, list):
        if len(value) == 2 and isinstance(value[0], str) and isinstance(value[1], int):
            yield value[0]
        for item in value:
            yield from _links(item)
    elif isinstance(value, dict):
        for item in value.values():
            yield from _links(item)


@pytest.mark.parametrize(("stage", "output"), STAGES.items())
def test_each_staged_graph_is_a_self_contained_single_generation(stage, output):
    """A stage is independently queueable, with exactly one video generator."""
    path = _source_stage_path(stage)
    graph = json.loads(path.read_text())

    assert graph[output[0]]["class_type"] == "SaveVideo"
    assert graph[output[0]]["_meta"]["title"] == output[1]
    assert sum(node["class_type"] == "SamplerCustomAdvanced" for node in graph.values()) == 1
    assert sum(node["class_type"] == "MiniMaxH3ReferenceToVideo" for node in graph.values()) == 1
    assert all(link in graph for node in graph.values() for link in _links(node.get("inputs", {})))


def test_legacy_stage_baseline_preserves_video_audio_and_pose_export_contracts():
    """Literal pre-catalog facts used to detect semantic template drift."""
    for stage, (video_node, _title) in STAGES.items():
        graph=json.loads(_source_stage_path(stage).read_text())
        pose_node=BASELINE_POSE_NODES[stage]
        assert graph[pose_node]["class_type"] == "SaveImage"
        create=next(node for node in graph.values() if node["class_type"] == "CreateVideo")
        assert create["inputs"]["fps"] == 24
        assert isinstance(create["inputs"]["images"],list) and isinstance(create["inputs"]["audio"],list)
        assert graph[video_node]["inputs"]["video"][0] in graph
    run=json.loads(_source_stage_path("run").read_text())
    reference=next(node for node in run.values() if node["class_type"] == "MiniMaxH3ReferenceToVideo")
    assert reference["inputs"]["ref_images.ref_image_0"] == ["114",0]
    assert reference["inputs"]["ref_images.ref_image_1"] == ["283",0]
    assert len([node for node in run.values() if node["class_type"] == "VAEDecode"]) == 2


def test_selection_dependency_closures_preserve_only_required_stages():
    assert staged_workflow.dependency_plan(poses=("standing",)) == ("run", "stop")
    assert staged_workflow.dependency_plan(actions=("jump",)) == ("run", "jump")
    assert staged_workflow.dependency_plan(actions=("walk",)) == ("run", "stop", "walk_start", "walk")
    assert staged_workflow.dependency_plan(actions=("crouch_walk",)) == (
        "run", "stop", "crouch", "crouch_start", "crouch_walk",
    )
    assert staged_workflow.parse_selection("walk,run,walk", staged_workflow.ACTION_ORDER, "--actions") == ("run", "walk")
    with pytest.raises(ValueError, match="--actions contains unknown names: fly"):
        staged_workflow.parse_selection("run,fly", staged_workflow.ACTION_ORDER, "--actions")


def test_rendered_dependency_inputs_use_the_documented_source_pose_nodes():
    graph = staged_workflow.render_stage_workflow(
        "jump", "character.png", "dummy.png", {"run_first": "uploaded-run.png"},
        width=400, height=512, neutral_idle=True, seed=17,
    )
    assert graph["359"]["inputs"]["image"] == "uploaded-run.png"
    assert graph["114"]["inputs"]["image"] == "character.png"
    assert "283" not in graph


def test_staged_graphs_are_declared_as_package_data_and_match_resources():
    project = (Path(__file__).resolve().parents[1] / "pyproject.toml").read_text()
    assert "workflows/staged/*.json" in project
    for stage in STAGES:
        assert staged_workflow.staged_workflow_path(stage).read_bytes() == _source_stage_path(stage).read_bytes()


class _StagedClient:
    events = []
    fail_submit = False
    recover = None

    def __init__(self, _server):
        pass

    def upload_image(self, path):
        call = len([event for event in self.events if event[0] == "upload"])
        name = f"{call}-{Path(path).name}"
        self.events.append(("upload", name))
        return {"name": name, "subfolder": "input", "type": "input"}

    def submit(self, graph, *, client_id=None):
        self.events.append(("submit", next(node["_meta"]["title"] for node in graph.values() if node["class_type"] == "SaveVideo"), client_id))
        if self.fail_submit:
            raise OSError("connection dropped after request")
        return f"prompt-{len([event for event in self.events if event[0] == 'submit'])}"

    def find_prompt_by_client_id(self, client_id):
        self.events.append(("recover", client_id))
        return self.recover

    def wait(self, prompt_id, *, required_nodes, **_kwargs):
        self.events.append(("wait", prompt_id, tuple(sorted(required_nodes))))
        return {"outputs": {node: {"gifs": [{"filename": f"{node}.mp4"}]} for node in required_nodes}}

    def output_descriptor(self, _history, node):
        self.events.append(("descriptor", node))
        return {"filename": f"{node}.{'png' if node not in {'92', '309', '341', '362', '379', '394', '424', '441', '456'} else 'mp4'}", "subfolder": "", "type": "output"}

    def download(self, descriptor, destination):
        if descriptor["filename"].endswith(".png"):
            Image.new("RGBA", (2, 2), "white").save(destination)
        else:
            Path(destination).write_bytes(descriptor["filename"].encode())
        return destination

    def free_if_idle(self):
        return True

    def wait_until_idle(self):
        return True


def test_mocked_execution_submits_only_walk_dependency_closure_and_resumes(monkeypatch, tmp_path):
    source = tmp_path / "character.png"
    Image.new("RGB", (2, 2), "white").save(source)
    _StagedClient.events = []
    monkeypatch.setattr(staged_workflow, "ComfyClient", _StagedClient)

    state = staged_workflow.generate_staged(source, tmp_path / "out", actions=("walk",), seed=3)
    assert [event[1] for event in _StagedClient.events if event[0] == "submit"] == [
        "Running Animation", "Stopping animation", "Idle to walk", "Walk loop",
    ]
    assert set(state["characters"][0]["stages"]) == {"run", "stop", "walk_start", "walk"}
    assert state["generation_complete"] is True

    _StagedClient.events = []
    resumed = staged_workflow.generate_staged(source, tmp_path / "out", actions=("walk",), seed=3)
    assert resumed["generation_complete"] is True
    assert not [event for event in _StagedClient.events if event[0] in {"upload", "submit", "wait", "descriptor"}]

    with pytest.raises(ValueError, match="staged resume workflow, style, or render settings differ"):
        staged_workflow.generate_staged(source, tmp_path / "out", actions=("walk",), seed=3, idle_style="feminine")


def test_mocked_stage_wave_queues_every_character_before_polling(monkeypatch, tmp_path):
    source = tmp_path / "characters"
    source.mkdir()
    for name in ("a.png", "b.png"):
        Image.new("RGB", (2, 2), "white").save(source / name)
    _StagedClient.events = []
    monkeypatch.setattr(staged_workflow, "ComfyClient", _StagedClient)

    staged_workflow.generate_staged(source, tmp_path / "out", actions=("run",), seed=3)
    events = [event[0] for event in _StagedClient.events]
    first_wait = events.index("wait")
    assert events[:first_wait].count("submit") == 2


def test_resume_requeues_a_stage_when_a_recorded_artifact_is_missing(monkeypatch, tmp_path):
    source = tmp_path / "character.png"
    Image.new("RGB", (2, 2), "white").save(source)
    _StagedClient.events = []
    monkeypatch.setattr(staged_workflow, "ComfyClient", _StagedClient)
    output = tmp_path / "out"
    state = staged_workflow.generate_staged(source, output, actions=("run",), seed=3)
    character = state["characters"][0]
    stage = character["stages"]["run"]
    (output / character["name"] / "generated" / "stages" / "run" / stage["artifacts"]["video"]["path"]).unlink()

    _StagedClient.events = []
    recovered = staged_workflow.generate_staged(source, output, actions=("run",), seed=3)
    assert recovered["generation_complete"] is True
    assert not [event for event in _StagedClient.events if event[0] == "submit"]
    assert [event[0] for event in _StagedClient.events].count("wait") == 1
    assert [event[0] for event in _StagedClient.events].count("descriptor") == 2


def test_ambiguous_submission_is_recovered_without_a_duplicate_prompt(monkeypatch, tmp_path):
    source = tmp_path / "character.png"
    Image.new("RGB", (2, 2), "white").save(source)
    _StagedClient.events = []
    _StagedClient.fail_submit = True
    _StagedClient.recover = None
    monkeypatch.setattr(staged_workflow, "ComfyClient", _StagedClient)
    with pytest.raises(OSError, match="connection dropped"):
        staged_workflow.generate_staged(source, tmp_path / "out", actions=("run",), seed=3)

    _StagedClient.fail_submit = False
    state = staged_workflow.generate_staged(source, tmp_path / "out", actions=("run",), seed=3)
    assert state["generation_complete"] is False
    assert [event[0] for event in _StagedClient.events].count("submit") == 1
    assert [event[0] for event in _StagedClient.events].count("recover") == 1


def test_cli_dry_run_resolves_jump_and_walk_without_contacting_comfyui(tmp_path, capsys):
    source = tmp_path / "character.png"
    Image.new("RGB", (2, 2), "white").save(source)
    output = tmp_path / "output"

    assert extract_frames.main([
        str(source), "--output", str(output), "--workflow", "staged",
        "--actions", "jump,walk", "--poses", "standing", "--dry-run",
    ]) == 0

    plan = json.loads(capsys.readouterr().out)
    assert plan["actions"] == ["jump", "walk"]
    assert plan["poses"] == ["standing"]
    assert [stage["name"] for stage in plan["stages"]] == ["run", "jump", "stop", "walk_start", "walk"]
    assert not output.exists()


def test_selected_package_origin_fallback_uses_alpha_from_every_selected_frame(monkeypatch, tmp_path):
    paths = []
    for index in range(2):
        path = tmp_path / f"jump-{index}.png"
        Image.new("RGB", (400, 100), "white").save(path)
        paths.append(path)

    def masks(_paths, *_args, **_kwargs):
        result = []
        for index in range(2):
            mask = __import__("numpy").zeros((100, 400), dtype="float32")
            for view in range(4):
                mask[10 if index == 0 else 20 : 30 if index == 0 else 80, view * 100 + 10 : view * 100 + 90] = 1
            result.append(mask)
        return result, {"model": "mock"}

    monkeypatch.setattr(character_animations, "_background_masks", masks)
    output = tmp_path / "package"
    output.mkdir()
    records = [{"frame_id": index, "pts": index, "time_seconds": float(index), "path": str(path)} for index, path in enumerate(paths)]
    manifest = character_animations._pack_selected_frames(
        {"jump": records}, {}, output, action_seconds={"jump": 1},
        action_sources={"jump": {"sha256": "jump", "time_base": {"numerator": 1, "denominator": 1}}},
        action_directories={"jump": "jump-frames"}, pose_sources={}, pose_directories={},
        height=128, split_algorithm="quarters",
    )

    assert manifest["origin_evidence"]["method"] == "selected_alpha_bottom"
    assert manifest["origin_evidence"]["sample_count"] == 8
    assert manifest["origin"]["y"] > 90


def test_staged_packaging_forwards_only_selected_action_and_pose_artifacts(monkeypatch, tmp_path):
    character = {"name": "hero", "stages": {}}
    for stage, artifact in (("walk", "video"), ("stop", "standing")):
        folder = tmp_path / "hero" / "generated" / "stages" / stage
        folder.mkdir(parents=True)
        path = folder / f"{artifact}.png"
        Image.new("RGBA", (2, 2), "white").save(path)
        character["stages"][stage] = {"request_sha256": stage, "prompt_id": f"prompt-{stage}", "artifacts": {artifact: {"path": path.name}}}
    state = {"seed": 3, "seed_mode": "fixed", "generation_complete": True, "models_unloaded": True, "characters": [character]}
    captured = {}

    def pack(videos, poses, package, **kwargs):
        captured.update(videos=videos, poses=poses, package=package, kwargs=kwargs)
        package.mkdir(parents=True)
        return {"actions": {"walk": {"frame_count": 8}}, "poses": {"standing": {"frame_count": 1}}, "webps": {"walk:right": "walk.webp"}}

    monkeypatch.setattr(character_animations, "build_selected_character_animations", pack)
    result = staged_workflow.package_staged(
        state, tmp_path, actions=("walk",), poses=("standing",), frame_counts={"walk": 8}, height=128,
    )

    assert set(captured["videos"]) == {"walk"}
    assert set(captured["poses"]) == {"standing"}
    assert result["complete"] is True
    assert next(iter(character["packages"].values()))["status"] == "complete"


def test_pose_only_real_selected_packer_makes_sheet_without_webps_or_sdpose(monkeypatch, tmp_path):
    pose = tmp_path / "standing.png"
    Image.new("RGB", (400, 100), "white").save(pose)

    def masks(paths, *_args, **_kwargs):
        return [__import__("numpy").ones((100, 400), dtype="float32") for _ in paths], {"model": "mock"}

    monkeypatch.setattr(character_animations, "_background_masks", masks)
    monkeypatch.setattr(extract_frames, "_worker", lambda *_args, **_kwargs: pytest.fail("pose-only packaging must not run SDPose"))
    manifest = character_animations.build_selected_character_animations(
        {}, {"standing": pose}, tmp_path / "package", frame_counts={}, height=64, split_algorithm="quarters",
    )

    assert manifest["actions"] == {}
    assert set(manifest["poses"]) == {"standing"}
    assert manifest["webps"] == {}
    assert (tmp_path / "package" / manifest["sheet"]).is_file()


def test_cli_staged_generation_only_succeeds_before_packaging(monkeypatch, tmp_path):
    source = tmp_path / "character.png"
    Image.new("RGB", (2, 2), "white").save(source)
    captured = {}

    def generate(*_args, **kwargs):
        captured.update(kwargs)
        return {"generation_complete": True, "complete": False}

    monkeypatch.setattr(definition_runtime, "generate_definitions", generate)
    assert extract_frames.main([
        str(source), "--output", str(tmp_path / "output"), "--workflow", "staged",
        "--actions", "run", "--generation-only",
    ]) == 0
    assert captured["actions"] == ("run",)


def test_jump_only_real_packer_writes_requested_frames_and_four_webps(monkeypatch, tmp_path):
    video = tmp_path / "jump.mp4"; video.write_bytes(b"video")
    frames = []
    for index in range(3):
        path = tmp_path / f"source-{index}.png"; Image.new("RGB", (400, 100), "white").save(path); frames.append(path)
    def sample(_video, count, destination):
        destination.mkdir(exist_ok=True)
        records=[]
        for index,path in enumerate(frames[:count]):
            target=destination/f"jump-{index}.png"; Image.open(path).save(target)
            records.append({"frame_id":index,"pts":index,"duration_ticks":1,"time_seconds":float(index),"path":str(target)})
        return {"sha256":"jump","time_base":{"numerator":1,"denominator":1}},1.0,records
    monkeypatch.setattr(character_animations,"_sample_frames",lambda video,count,destination,**_kwargs: sample(video,count,destination))
    monkeypatch.setattr(character_animations,"_background_masks",lambda paths,*_a,**_k: ([__import__("numpy").ones((100,400),dtype="float32") for _ in paths],{}))
    manifest=character_animations.build_selected_character_animations({"jump":video},{},tmp_path/"package",frame_counts={"jump":3},height=64,split_algorithm="quarters")
    assert manifest["actions"]["jump"]["frame_count"] == 3
    assert len(manifest["webps"]) == 4
    assert all((tmp_path/"package"/name).is_file() for name in manifest["webps"].values())


def test_generic_attack_uniform_policy_writes_four_loop_configured_webps(monkeypatch,tmp_path):
    video=tmp_path/"attack.mp4"; video.write_bytes(b"video")
    sources=[]
    for index,color in enumerate(("red","green","blue")):
        path=tmp_path/f"attack-{index}.png"; Image.new("RGB",(400,100),color).save(path); sources.append(path)
    def sample(_v,count,dest,**_k):
        dest.mkdir(exist_ok=True); records=[]
        for i,path in enumerate(sources[:count]):
            target=dest/f"f{i}.png"; Image.open(path).save(target); records.append({"frame_id":i,"pts":i,"duration_ticks":1,"time_seconds":float(i),"path":str(target)})
        return {"sha256":"attack","time_base":{"numerator":1,"denominator":1}},1.0,records
    monkeypatch.setattr(character_animations,"_sample_frames",sample)
    monkeypatch.setattr(character_animations,"_background_masks",lambda paths,*_a,**_k: ([__import__("numpy").ones((100,400),dtype="float32") for _ in paths],{}))
    manifest=character_animations.build_selected_character_animations({"attack":video},{},tmp_path/"attack-package",frame_counts={"attack":3},action_policies={"attack":{"method":"uniform","frames":3,"include_last":True}},conceptual_loops={"attack":False},webp_loops={"attack":2},action_order=("attack",),height=64,split_algorithm="quarters")
    assert manifest["actions"]["attack"]["frame_count"]==3 and len(manifest["webps"])==4
    for name in manifest["webps"].values():
        with Image.open(tmp_path/"attack-package"/name) as webp:
            assert webp.info["loop"] == 2 and webp.n_frames == 3


def test_staged_resume_rejects_style_and_dimension_changes_before_client(monkeypatch, tmp_path):
    source=tmp_path/"character.png"; Image.new("RGB",(2,2),"white").save(source)
    _StagedClient.events=[]; monkeypatch.setattr(staged_workflow,"ComfyClient",_StagedClient)
    staged_workflow.generate_staged(source,tmp_path/"out",actions=("run",),seed=3)
    _StagedClient.events=[]
    with pytest.raises(ValueError,match="staged resume workflow, style, or render settings differ"):
        staged_workflow.generate_staged(source,tmp_path/"out",actions=("run",),seed=3,sprite_render_width=401)
    assert not _StagedClient.events
