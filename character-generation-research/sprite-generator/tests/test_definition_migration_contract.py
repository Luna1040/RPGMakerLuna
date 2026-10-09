from sprite_extractor.definition_runtime import STATE_VERSION, _migrate_state
from sprite_extractor import staged_workflow, definition_runtime
from sprite_extractor.animation_definitions import load_registry
from test_staged_workflow_contract import _StagedClient
from test_definition_runtime_contract import Client
from PIL import Image


def test_v2_completed_records_are_retained_for_evidence_based_import():
    legacy={"version":"2.0-staged","seed":3,"generation_identity":{"x":1},"characters":[{"name":"hero","stages":{"run":{"status":"complete","client_id":"c","prompt_id":"p","artifacts":{"video":{"path":"video.mp4","sha256":"a"},"run_first":{"path":"first.png","sha256":"b"}}}}}]}
    migrated=_migrate_state(legacy)
    assert migrated["version"] == STATE_VERSION
    character=migrated["characters"][0]
    assert character["stages"] == {}
    assert character["legacy_stages"]["run"]["artifacts"]["run_first"]["sha256"] == "b"
    assert migrated["generation_complete"] is False


def test_completed_v2_run_stop_imports_without_new_submission(monkeypatch,tmp_path):
    source=tmp_path/"hero.png"; Image.new("RGB",(2,2),"white").save(source)
    _StagedClient.events=[]; _StagedClient.fail_submit=False; _StagedClient.recover=None; monkeypatch.setattr(staged_workflow,"ComfyClient",_StagedClient)
    legacy=staged_workflow.generate_staged(source,tmp_path/"out",actions=(),poses=("standing",),seed=3)
    old_sha=legacy["characters"][0]["stages"]["stop"]["artifacts"]["standing"]["sha256"]
    Client.events=[]; monkeypatch.setattr(definition_runtime,"ComfyClient",Client)
    state=definition_runtime.generate_definitions(source,tmp_path/"out",load_registry(),actions=(),poses=("standing",),seed=3)
    assert state["generation_complete"] and not Client.events
    revision=state["characters"][0]["stages"]["stop"]["revisions"][state["characters"][0]["stages"]["stop"]["active_revision"]]
    assert revision["migration"] == "verified-2.0-staged"
    assert revision["poses"]["standing"]["sha256"] == old_sha
    assert state["characters"][0]["stages"]["run"]["revisions"][state["characters"][0]["stages"]["run"]["active_revision"]]["migration"] == "verified-2.0-staged"


def test_unknown_legacy_submission_never_resubmits_without_evidence(monkeypatch,tmp_path):
    source=tmp_path/"hero.png"; Image.new("RGB",(2,2),"white").save(source)
    _StagedClient.events=[]; _StagedClient.fail_submit=False; _StagedClient.recover=None; monkeypatch.setattr(staged_workflow,"ComfyClient",_StagedClient)
    staged_workflow.generate_staged(source,tmp_path/"out",actions=(),poses=("standing",),seed=3)
    state_path=tmp_path/"out"/"staged-generation-state.json"
    import json
    legacy=json.loads(state_path.read_text()); run=legacy["characters"][0]["stages"]["run"]
    run.update(status="submission_unknown",client_id="legacy-client"); run.pop("prompt_id",None)
    state_path.write_text(json.dumps(legacy))
    Client.events=[]; monkeypatch.setattr(definition_runtime,"ComfyClient",Client)
    for _ in range(2): definition_runtime.generate_definitions(source,tmp_path/"out",load_registry(),actions=(),poses=("standing",),seed=3)
    assert not [item for item in Client.events if item[0]=="submit"]


def test_submitted_legacy_timeout_keeps_original_prompt(monkeypatch,tmp_path):
    source=tmp_path/"hero.png"; Image.new("RGB",(2,2),"white").save(source)
    _StagedClient.events=[]; _StagedClient.fail_submit=False; _StagedClient.recover=None; monkeypatch.setattr(staged_workflow,"ComfyClient",_StagedClient)
    staged_workflow.generate_staged(source,tmp_path/"out",actions=(),poses=("standing",),seed=3)
    import json
    path=tmp_path/"out"/"staged-generation-state.json"; legacy=json.loads(path.read_text()); run=legacy["characters"][0]["stages"]["run"]
    run.update(status="submitted",client_id="legacy-client",prompt_id="old-prompt"); path.write_text(json.dumps(legacy))
    monkeypatch.setattr(definition_runtime,"ComfyClient",Client)
    monkeypatch.setattr(Client,"wait",lambda *_a,**_k: (_ for _ in ()).throw(TimeoutError("wait")))
    Client.events=[]
    for _ in range(2): definition_runtime.generate_definitions(source,tmp_path/"out",load_registry(),actions=(),poses=("standing",),seed=3)
    assert not [x for x in Client.events if x[0]=="submit"]
