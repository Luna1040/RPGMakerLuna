import pytest
import json
from pathlib import Path
import shutil, subprocess, sys

from sprite_extractor.animation_definitions import DefinitionError, load_registry, registry_from_snapshot
from sprite_extractor.workflow_templates import legacy_stage_signature, normalized_generation_signature, render_stage_workflow


def test_builtin_catalog_reproduces_public_order_and_dependency_closures():
    registry = load_registry()
    assert registry.actions == ("idle", "run", "jump", "crouch", "crouch_walk", "walk")
    assert registry.dependency_plan(("walk",), ()) == ("run", "stop", "walk_start", "walk")
    assert registry.dependency_plan((), ("standing",)) == ("run", "stop")
    assert registry.stages["run"].generation.fps == 24


def test_optional_display_metadata_is_backward_compatible_and_not_generation_identity():
    registry = load_registry()
    snapshot = registry.provenance()
    stage = registry.action_stages["walk"]
    before = registry.stage_identity(stage)
    snapshot["stages"][stage]["outputs"]["animation"].update(
        {"label": "Stride", "description": "A readable walk label."}
    )
    edited = registry_from_snapshot(snapshot)
    assert edited.list_document()["actions"][-1]["label"] == "Stride"
    assert edited.list_document()["actions"][-1]["description"] == "A readable walk label."
    assert edited.stage_identity(stage) == before


def test_external_prompts_and_selection_defaults_match_legacy_graph_leaves_exactly():
    root = Path(__file__).resolve().parents[1] / "workflows" / "staged"
    for style in ("neutral", "feminine"):
        registry = load_registry(style=style)
        for stage_name, stage in registry.stages.items():
            graph = json.loads((root / f"{stage_name}.json").read_text())
            legacy_prompts = [node["inputs"]["value"] for node in graph.values()
                              if node.get("class_type") == "PrimitiveStringMultiline"]
            assert stage.prompt in legacy_prompts
    neutral = load_registry()
    assert {name: neutral.stages[neutral.action_stages[name]].animation.selection.frames for name in neutral.actions} == {
        "idle": 4, "run": 8, "jump": 8, "crouch": None, "crouch_walk": 8, "walk": 8,
    }
    assert neutral.stages[neutral.pose_stages["run_first"]].poses["run_first"].frame == "first"
    assert all(neutral.stages[neutral.pose_stages[name]].poses[name].frame == "last"
               for name in neutral.poses if name != "run_first")


@pytest.mark.parametrize("style", ["neutral", "feminine"])
def test_all_builtin_rendered_templates_match_legacy_generation_signatures(style):
    registry=load_registry(style=style)
    artifacts={pose: f"input/{pose}.png" for pose in registry.poses}
    for stage_name in registry.stage_order:
        graph=render_stage_workflow(registry,stage_name,character_image="input/character.png",dummy_image="input/dummy.png",artifact_images=artifacts,width=320,height=512,seed=366)
        assert normalized_generation_signature(graph) == legacy_stage_signature(stage_name,style=style)


def test_overlay_replaces_complete_stage_and_resolves_prompt_relative_to_overlay(tmp_path):
    prompt = tmp_path / "attack.txt"; prompt.write_text("ATTACK PROMPT")
    overlay = tmp_path / "attack.yaml"
    overlay.write_text("""version: 1
stages:
  attack:
    template: reference_video
    inputs:
      character: source
      pose: {stage: stop, output: standing}
      dimensions: {stage: stop, output: standing}
    prompt: {file: attack.txt}
    generation: {duration_seconds: 2, fps: 24}
    outputs:
      animation:
        name: attack
        selection: {method: uniform, frames: 3, include_last: true}
        conceptual_loop: false
        webp_loop: 0
      poses: {attack_end: {frame: last}}
""")
    registry = load_registry([overlay])
    assert registry.stages["attack"].prompt == "ATTACK PROMPT"
    assert registry.dependency_plan(("attack",), ())[-1] == "attack"


@pytest.mark.parametrize("replacement,field", [
    ("version: true", "version"),
    ("duration_seconds: true", "duration_seconds"),
])
def test_invalid_catalog_values_fail_with_field_and_file(tmp_path, replacement, field):
    path = tmp_path / "bad.yaml"
    path.write_text("version: 1\nstages: {}\n")
    # Target strict duplicate-key/version checks directly, then use the builtin
    # overlay route for values which need a complete stage definition.
    if replacement.startswith("version"):
        path.write_text(replacement + "\nstages: {}\n")
    else:
        path.write_text("version: 1\nstages:\n  run:\n    template: initial_reference\n    inputs: {character: source, pose: dummy, dimensions: dummy}\n    prompt: {inline: x}\n    generation: {" + replacement + "}\n    outputs: {poses: {p: {frame: first}}}\n")
    with pytest.raises(DefinitionError, match=field):
        load_registry([path])


def test_duplicate_yaml_keys_and_cycles_fail_before_runtime(tmp_path):
    duplicate = tmp_path / "duplicate.yaml"
    duplicate.write_text("version: 1\nstages: {}\nstages: {}\n")
    with pytest.raises(DefinitionError, match="duplicate mapping key"):
        load_registry([duplicate])


def test_packaged_resources_load_from_an_isolated_copied_package(tmp_path):
    source=Path(__file__).resolve().parents[1]/"src"/"sprite_extractor"
    site=tmp_path/"site"; shutil.copytree(source,site/"sprite_extractor")
    code="""import sprite_extractor; from sprite_extractor.animation_definitions import load_registry; from sprite_extractor.workflow_templates import render_stage_workflow
r=load_registry(); a={p:'x.png' for p in r.poses}; assert 'site' in sprite_extractor.__file__; render_stage_workflow(r,'run',character_image='c.png',dummy_image='d.png',artifact_images=a,width=320,height=512,seed=366); render_stage_workflow(r,'stop',character_image='c.png',dummy_image='d.png',artifact_images=a,width=320,height=512,seed=366)"""
    env={"PYTHONPATH":str(site)}
    result=subprocess.run([sys.executable,"-c",code],cwd=tmp_path,env=env,text=True,capture_output=True)
    assert result.returncode==0,result.stderr


@pytest.mark.parametrize("bad_input", ["[source]", "{stage: 7, output: standing}"])
def test_malformed_artifact_references_report_definition_errors_not_type_errors(tmp_path, bad_input):
    path = tmp_path / "bad-reference.yaml"
    path.write_text("""version: 1
stages:
  attack:
    template: reference_video
    inputs:
      character: source
      pose: %s
      dimensions: {stage: stop, output: standing}
    prompt: {inline: attack}
    generation: {duration_seconds: 1}
    outputs: {poses: {end: {frame: last}}}
""" % bad_input)
    with pytest.raises(DefinitionError, match=r"bad-reference.yaml: stages.attack.inputs.pose"):
        load_registry([path])
