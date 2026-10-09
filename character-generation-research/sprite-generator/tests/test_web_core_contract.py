"""Web-layer contracts that must remain isolated from ComfyUI inference."""
from __future__ import annotations

from pathlib import Path
import json
import zipfile
import os
import time

import pytest
import yaml

from sprite_extractor.application import normalize_request, plan_request
from sprite_extractor.animation_definitions import load_registry
from sprite_extractor.comfy_workflow import default_workflow_config_path
from sprite_extractor.runtime_config import resolve_config
from sprite_extractor.web.config_store import ConfigStore
from sprite_extractor.web.store import Store
from sprite_extractor.web.artifacts import publish_package, zip_file
from sprite_extractor.web.worker import Scheduler


def _config():
    # A mapping override means the resolver never consults an ignored local config.
    document = yaml.safe_load(default_workflow_config_path().read_text())
    document["comfyui_url"] = "http://mocked.invalid"
    return resolve_config(document)


def _draft(**changes):
    draft = {
        "workspace_id": "ws_test",
        "actions": ["walk"],
        "frame_counts": {"walk": 4},
        "style": "neutral",
        "seed": {"mode": "fixed", "value": "9223372036854775807"},
        "sprite_size": 256,
        "generation": {"width": 400, "height": 512, "pad_top_percent": 0},
        "split_method": "blobs",
        "animation_overrides": {},
    }
    draft.update(changes)
    return draft


def test_plan_is_read_only_and_walk_includes_its_dependencies(monkeypatch, tmp_path):
    config = _config()
    # Planning must not create a client, submit a prompt, or mutate an output tree.
    import sprite_extractor.definition_runtime as runtime
    monkeypatch.setattr(runtime, "ComfyClient", lambda *_a, **_k: pytest.fail("plan contacted ComfyUI"))
    output = tmp_path / "output"
    plan = plan_request(_draft(), config, image=tmp_path / "source.png", output=output)
    assert plan["request"]["seed"] == {"mode": "fixed", "value": "9223372036854775807"}
    assert plan["summary"]["directions"] == 4
    assert any(stage["reason"] == "dependency" for stage in plan["stages"])
    assert not output.exists()


@pytest.mark.parametrize("seed", ["-1", "9223372036854775808", 42])
def test_fixed_seed_requires_a_safe_decimal_string(seed):
    with pytest.raises(ValueError):
        normalize_request(_draft(seed={"mode": "fixed", "value": seed}), _config())


def test_store_idempotency_returns_one_immutable_job(tmp_path):
    store = Store(tmp_path / "web.sqlite")
    config = _config().snapshot()
    first, created = store.create_job("ws_test", _draft(seed={"mode": "fixed", "value": "9"}), config, {"revision": "catalog"}, "idempotency-key-123")
    second, created_again = store.create_job("ws_test", _draft(seed={"mode": "fixed", "value": "9"}), config, {"revision": "catalog"}, "idempotency-key-123")
    assert created is True and created_again is False
    assert second["id"] == first["id"]
    assert second["resolved_seed"] == "9"
    assert second["request"]["seed"]["value"] == "9"
    assert [event["event"] for event in store.events(first["id"], 0)] == ["state"]
    with pytest.raises(ValueError, match="idempotency_conflict"):
        store.create_job("ws_test", _draft(seed={"mode": "fixed", "value": "10"}), config, {"revision": "catalog"}, "idempotency-key-123")


def test_config_save_is_atomic_preserves_unrelated_keys_and_detects_conflict(tmp_path):
    path = tmp_path / "editable.yaml"
    path.write_text("custom_plugin_key: retained\nsprite_box_height: 192\n")
    config = ConfigStore(path)
    initial = config.document()
    saved = config.patch(initial["revision"], [{"path": ["sprite_box_height"], "value": 320}])
    document = yaml.safe_load(path.read_text())
    assert document["custom_plugin_key"] == "retained"
    assert document["sprite_box_height"] == 320
    assert path.with_suffix(".yaml.bak").read_text() == "custom_plugin_key: retained\nsprite_box_height: 192\n"
    with pytest.raises(RuntimeError, match="config_conflict"):
        config.patch(initial["revision"], [{"path": ["sprite_box_height"], "value": 128}])
    config.patch(saved["revision"], [{"path": ["sprite_box_height"], "reset": True}])
    assert "sprite_box_height" not in yaml.safe_load(path.read_text())


def test_publication_selects_exact_request_and_zip_excludes_private_inputs(tmp_path):
    root = tmp_path / "data"; store = Store(root / "jobs.sqlite")
    config = _config().snapshot(); request = _draft(seed={"mode": "fixed", "value": "5"})
    job, _ = store.create_job("ws_test", request, config, {"catalog": "snapshot"}, "package-key-123")
    engine = root / "workspaces" / "ws_test" / "generation-sets" / "5"; package_root = engine / "hero"
    packages = {}
    for key, actions in (("run-old", ["run"]), ("walk", ["walk"]), ("run-final", ["walk"])):
        directory = package_root / key; directory.mkdir(parents=True)
        (directory / "sheet.png").write_bytes(b"sheet-" + key.encode())
        (directory / "walk-right.webp").write_bytes(b"webp")
        (directory / "secret-source.png").write_bytes(b"private")
        (directory / "manifest.json").write_text(json.dumps({"sheet":"sheet.png", "webps":{"walk:right":"walk-right.webp"}, "raw_prompt":"secret", "source":"secret-source.png"}))
        packages[key] = {"status":"complete", "path":key, "request":{"actions":actions, "frame_counts":{"walk":4} if actions == ["walk"] else {"run":4}, "height":256, "split_algorithm":"blobs"}}
    # The engine must publish the exact revision it selected, not merely the last
    # package whose visible action/frame settings happen to match.
    (engine / "staged-generation-state.json").write_text(json.dumps({"characters":[{"name":"hero", "selected_package_id":"run-final", "packages":packages}]}))
    package = publish_package(store, root, job, engine)
    assert package["sheet"]["filename"] == "sheet.png"
    assert (root / "publications" / job["id"] / "manifest.json").read_text().find("secret") == -1
    archive = zip_file(store, package, root / "download.zip")
    with zipfile.ZipFile(archive) as content:
        assert set(content.namelist()) == {"sheet.png", "manifest.json", "character-sheet-256h.json", "walk-right.webp"}
        assert content.read("sheet.png") == b"sheet-run-final"
    # A crash after publication and before the job status write must not produce
    # another public package or violate the packages.job_id uniqueness contract.
    assert publish_package(store, root, job, engine)["id"] == package["id"]


def test_scheduler_runner_records_progress_stops_and_recovers_dead_owner(tmp_path):
    store = Store(tmp_path / "jobs.sqlite"); config = _config().snapshot()
    job, _ = store.create_job("ws_test", _draft(seed={"mode":"fixed","value":"6"}), config, {"catalog":"snapshot"}, "runner-key-123")
    def runner(_job, progress, should_stop):
        progress("generating", {"stage":"walk"})
        assert should_stop() is False
    scheduler = Scheduler(store, tmp_path, runner=runner)
    scheduler.run(job["id"])
    assert store.job(job["id"])["status"] == "ready"
    assert any(event["event"] == "progress" for event in store.events(job["id"], 0))
    store.update_job(job["id"], status="generating", worker_id="999999999:dead")
    scheduler.reconcile()
    assert store.job(job["id"])["status"] == "recovery_required"


def test_worker_captures_each_completed_stage_without_making_preview_index_failures_fatal(monkeypatch, tmp_path):
    from sprite_extractor.web import previews

    store = Store(tmp_path / "jobs.sqlite")
    job, _ = store.create_job(
        "ws_test", _draft(seed={"mode": "fixed", "value": "8"}), _config().snapshot(), {"catalog": "snapshot"}, "preview-hook-key"
    )
    calls = []
    monkeypatch.setattr(previews, "capture_job_revisions", lambda *args: calls.append(args))

    def runner(_job, progress, _should_stop):
        progress("generating", {"completed_stage": "walk", "completed_stages": 1, "total_stages": 2})

    Scheduler(store, tmp_path, runner=runner).run(job["id"])
    assert calls == [(tmp_path, "ws_test", "8", job["id"], {"walk"})]
    assert store.job(job["id"])["status"] == "ready"

    retry, _ = store.create_job(
        "ws_test", _draft(seed={"mode": "fixed", "value": "9"}), _config().snapshot(), {"catalog": "snapshot"}, "preview-hook-retry-key"
    )
    monkeypatch.setattr(previews, "capture_job_revisions", lambda *_args: (_ for _ in ()).throw(OSError("index unavailable")))
    Scheduler(store, tmp_path, runner=runner).run(retry["id"])
    assert store.job(retry["id"])["status"] == "ready"
    assert any("Raw preview index was not updated" in event.get("message", "") for event in store.events(retry["id"], 0))


def test_real_scheduler_subprocess_publishes_a_mocked_package_without_comfy(monkeypatch, tmp_path):
    """Exercise the production Popen worker path; only its child core boundary is faked."""
    root = tmp_path / "data"; store = Store(root / "jobs.sqlite3"); config = _config().snapshot()
    upload = root / "uploads" / "up_test" / "original.png"; upload.parent.mkdir(parents=True); upload.write_bytes(b"source")
    store.insert_json("uploads", "up_test", {"id":"up_test", "path":str(upload)})
    store.insert_json("workspaces", "ws_test", {"id":"ws_test", "upload_id":"up_test"})
    job, _ = store.create_job("ws_test", _draft(seed={"mode":"fixed","value":"7"}), config, load_registry().provenance(), "subprocess-key-123")
    hook = tmp_path / "hook"; hook.mkdir()
    hook.joinpath("sitecustomize.py").write_text('''\
import json
from pathlib import Path
def fake_execute(request, config, image, output, **kwargs):
    pkg = Path(output) / "hero" / "package"; pkg.mkdir(parents=True, exist_ok=True)
    (pkg / "sheet.png").write_bytes(b"sheet")
    (pkg / "walk-right.webp").write_bytes(b"webp")
    (pkg / "manifest.json").write_text(json.dumps({"sheet":"sheet.png","webps":{"walk:right":"walk-right.webp"}}))
    Path(output, "staged-generation-state.json").write_text(json.dumps({"characters":[{"name":"hero","selected_package_id":"selected","packages":{"selected":{"status":"complete","path":"package","request":{"actions":["walk"],"frame_counts":{"walk":4},"height":256,"split_algorithm":"blobs"}}}}]}))
import sprite_extractor.application as application
application.execute_request = fake_execute
''')
    source = str(Path(__file__).resolve().parents[1] / "src")
    monkeypatch.setenv("PYTHONPATH", str(hook) + os.pathsep + source)
    scheduler = Scheduler(store, root); scheduler.start()
    try:
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline and store.job(job["id"])["status"] not in {"ready", "failed", "recovery_required"}:
            time.sleep(.1)
        result = store.job(job["id"])
    finally:
        scheduler.stop()
    assert result["status"] == "ready", result
    assert result["package_id"]
    assert store.get_json("packages", result["package_id"])["animations"][0]["action"] == "walk"
