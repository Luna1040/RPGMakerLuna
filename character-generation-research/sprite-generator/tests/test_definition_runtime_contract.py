from pathlib import Path

from PIL import Image
import yaml

from sprite_extractor import definition_runtime
from sprite_extractor.animation_definitions import load_registry
from sprite_extractor.io_utils import sha256_file
from sprite_extractor.workflow_templates import render_stage_workflow


class Client:
    events=[]
    def __init__(self,*_): pass
    def upload_image(self,path): return {"name":Path(path).name,"subfolder":"input","type":"input"}
    def submit(self,graph,*,client_id=None):
        prompt=next(n["inputs"]["value"] for n in graph.values() if n.get("class_type")=="PrimitiveStringMultiline")
        self.events.append(("submit",prompt)); return f"p{len(self.events)}"
    def find_prompt_by_client_id(self,_): return None
    def wait(self,*_,required_nodes,**__): return {"outputs":{n:{"gifs":[{"filename":"video.mp4"}]} for n in required_nodes}}
    def output_descriptor(self,*_): return {"filename":"video.mp4","subfolder":"","type":"output"}
    def output_descriptors(self,*_): return [{"filename":"frame.png","subfolder":"","type":"output"}]
    def download(self,d,target):
        Path(target).parent.mkdir(parents=True,exist_ok=True)
        if d["filename"].endswith(".png"): Image.new("RGBA",(2,2),"white").save(target,format="PNG")
        else: Path(target).write_bytes(b"video")
        return target
    def wait_until_idle(self): return True
    def free_if_idle(self): return True


def _attack(tmp_path, text="attack"):
    p=tmp_path/"attack.yaml"; p.write_text(f'''version: 1
stages:
  attack:
    template: reference_video
    inputs: {{character: source, pose: {{stage: stop, output: standing}}, dimensions: {{stage: stop, output: standing}}}}
    prompt: {{inline: {text}}}
    generation: {{duration_seconds: 1}}
    outputs: {{animation: {{name: attack, selection: {{method: uniform, frames: 2, include_last: true}}, conceptual_loop: false, webp_loop: 0}}, poses: {{attack_end: {{frame: last}}}}}}
'''); return p


def test_yaml_attack_revisions_and_pose_reuse(monkeypatch,tmp_path):
    source=tmp_path/"hero.png"; Image.new("RGB",(2,2),"white").save(source)
    monkeypatch.setattr(definition_runtime,"ComfyClient",Client)
    Client.events=[]; reg=load_registry([_attack(tmp_path)])
    state=definition_runtime.generate_definitions(source,tmp_path/"out",reg,actions=("attack",),seed=3)
    assert set(state["characters"][0]["stages"]) == {"run", "stop", "attack"}
    assert len(Client.events) == 3 and Client.events[-1][1] == "attack"
    Client.events=[]; definition_runtime.generate_definitions(source,tmp_path/"out",reg,actions=("attack",),seed=3)
    assert not Client.events
    reg2=load_registry([_attack(tmp_path,"attack_changed")])
    Client.events=[]; definition_runtime.generate_definitions(source,tmp_path/"out",reg2,actions=("attack",),seed=3)
    assert len(Client.events) == 1 and Client.events[0][1] == "attack_changed"


def test_frame_cache_sink_uses_final_createvideo_image_decoder():
    registry=load_registry()
    graph=render_stage_workflow(registry,"run",character_image="c.png",dummy_image="d.png",artifact_images={},width=320,height=512,seed=366)
    cache=definition_runtime._install_frame_cache(graph)
    video=next(node for node in graph.values() if node.get("class_type")=="CreateVideo")
    assert graph[cache]["inputs"]["images"] == video["inputs"]["images"]


def test_adding_pose_export_reuses_completed_attack_without_submission(monkeypatch,tmp_path):
    source=tmp_path/"hero.png"; Image.new("RGB",(2,2),"white").save(source)
    monkeypatch.setattr(definition_runtime,"ComfyClient",Client)
    # Use real pose extraction: the mocked client supplies a lossless cached PNG.
    Client.events=[]; registry=load_registry([_attack(tmp_path)])
    state=definition_runtime.generate_definitions(source,tmp_path/"out",registry,actions=("attack",),seed=3)
    assert state["generation_complete"]
    attack_bucket=state["characters"][0]["stages"]["attack"]; attack_revision=attack_bucket["revisions"][attack_bucket["active_revision"]]
    cached=tmp_path/"out"/state["characters"][0]["name"]/attack_revision["artifacts"]["frames"][0]["path"]
    cached.write_bytes(b"corrupt")
    Client.events=[]; state=definition_runtime.generate_definitions(source,tmp_path/"out",registry,actions=("attack",),seed=3)
    assert state["generation_complete"] and not Client.events
    overlay=_attack(tmp_path,"attack")
    document=yaml.safe_load(overlay.read_text())
    document["stages"]["attack"]["outputs"]["poses"].update(attack_first={"frame":"first"}, attack_zero={"frame":0})
    overlay.write_text(yaml.safe_dump(document,sort_keys=False))
    registry2=load_registry([overlay]); Client.events=[]
    state=definition_runtime.generate_definitions(source,tmp_path/"out",registry2,actions=(),poses=("attack_first","attack_zero"),seed=3)
    assert state["generation_complete"] and not Client.events


def test_package_count_revisions_update_current_completion(monkeypatch,tmp_path):
    source=tmp_path/"hero.png"; Image.new("RGB",(2,2),"white").save(source)
    monkeypatch.setattr(definition_runtime,"ComfyClient",Client); reg=load_registry([_attack(tmp_path)])
    state=definition_runtime.generate_definitions(source,tmp_path/"out",reg,actions=("attack",),seed=3)
    def builder(_v,_p,path,**_k):
        if _k["frame_counts"]["attack"]==4: raise RuntimeError("pack failed")
        path.mkdir(parents=True); return {"sheet":"sheet.png","actions":{},"webps":{}}
    import sprite_extractor.character_animations as animations
    monkeypatch.setattr(animations,"build_selected_character_animations",builder)
    for count in (2,3):
        state=definition_runtime.package_definitions(state,tmp_path/"out",reg,actions=("attack",),poses=(),frame_counts={"attack":count},height=64)
        assert state["complete"]
    assert len(state["characters"][0]["packages"])==2
    state=definition_runtime.package_definitions(state,tmp_path/"out",reg,actions=("attack",),poses=(),frame_counts={"attack":4},height=64)
    assert state["complete"] is False


def test_frame_cache_wrong_hash_recovery_preserves_record(monkeypatch,tmp_path):
    source=tmp_path/"hero.png"; Image.new("RGB",(2,2),"white").save(source)
    monkeypatch.setattr(definition_runtime,"ComfyClient",Client); reg=load_registry([_attack(tmp_path)])
    state=definition_runtime.generate_definitions(source,tmp_path/"out",reg,actions=("attack",),seed=3)
    char=state["characters"][0]; rev=char["stages"]["attack"]["revisions"][char["stages"]["attack"]["active_revision"]]; item=rev["artifacts"]["frames"][0]; expected=item["sha256"]
    (tmp_path/"out"/char["name"]/item["path"]).write_bytes(b"bad")
    original=Client.download
    def black(self,d,target):
        Path(target).parent.mkdir(parents=True,exist_ok=True)
        if d["filename"].endswith(".png"): Image.new("RGBA",(2,2),"black").save(target,format="PNG"); return target
        return original(self,d,target)
    monkeypatch.setattr(Client,"download",black); Client.events=[]
    state=definition_runtime.generate_definitions(source,tmp_path/"out",reg,actions=("attack",),seed=3)
    current=state["characters"][0]["stages"]["attack"]; recorded=current["revisions"][current["active_revision"]]["artifacts"]["frames"][0]
    assert state["generation_complete"] is False and not Client.events and recorded["sha256"]==expected


def test_dry_run_reports_cached_attack_without_client_or_writes(monkeypatch,tmp_path):
    source=tmp_path/"hero.png"; Image.new("RGB",(2,2),"white").save(source)
    monkeypatch.setattr(definition_runtime,"ComfyClient",Client); registry=load_registry([_attack(tmp_path)])
    definition_runtime.generate_definitions(source,tmp_path/"out",registry,actions=("attack",),seed=3)
    before={(p.relative_to(tmp_path/"out"),p.read_bytes()) for p in (tmp_path/"out").rglob("*") if p.is_file()}
    monkeypatch.setattr(definition_runtime,"ComfyClient",lambda *_a,**_k: (_ for _ in ()).throw(AssertionError("network")))
    plan=definition_runtime.plan_definitions(registry,("attack",),(),{"attack":2},output=tmp_path/"out",image=source,width=400,base_height=512,seed=3)
    assert all(stage["cache"]["decision"]=="hit" for stage in plan["stages"])
    changed=load_registry([_attack(tmp_path,"attack_changed")])
    changed_plan=definition_runtime.plan_definitions(changed,("attack",),(),{"attack":2},output=tmp_path/"out",image=source,width=400,base_height=512,seed=3)
    assert {stage["name"]:stage["cache"]["decision"] for stage in changed_plan["stages"]} == {"run":"hit","stop":"hit","attack":"miss"}
    assert before=={(p.relative_to(tmp_path/"out"),p.read_bytes()) for p in (tmp_path/"out").rglob("*") if p.is_file()}
