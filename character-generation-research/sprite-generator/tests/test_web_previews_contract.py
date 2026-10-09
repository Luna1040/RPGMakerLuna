"""Offline contracts for read-only raw stage media previews."""

from __future__ import annotations

import hashlib
import json
import os

from fastapi.testclient import TestClient

from sprite_extractor.io_utils import canonical_json, sha256_bytes
from sprite_extractor.web.app import create_app
from sprite_extractor.web.previews import capture_job_revisions
from sprite_extractor.web.previews import job_previews
from sprite_extractor.web.settings import WebSettings
from sprite_extractor.web.worker import process_identity


def _asset(root, relative, payload):
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)
    return {"path": relative, "sha256": hashlib.sha256(payload).hexdigest()}


def _client_with_preview_state(tmp_path):
    settings = WebSettings(
        data_root=tmp_path / "data",
        config_path=tmp_path / "editable.yaml",
        username="operator",
        password="password",
        secret="x" * 32,
        scheduler=False,
    )
    app = create_app(settings)
    definition = {
        "stages": {
            "prepare": {"inputs": {}, "outputs": {}},
            "run": {
                "inputs": {"source": {"stage": "prepare"}},
                "outputs": {"animation": {"name": "run", "label": "Run output"}},
            },
        }
    }
    request = {"actions": ["run"], "seed": {"value": "42"}}
    job, _ = app.state.store.create_job("ws_preview", request, {}, definition, "preview-job-key")
    engine = settings.data_root / "workspaces" / "ws_preview" / "generation-sets" / "42"
    character = engine / "hero"
    archive = sha256_bytes(canonical_json(definition))
    selected_video = _asset(character, "generated/prepare-selected.mp4", b"selected-video")
    old_video = _asset(character, "generated/prepare-old.mp4", b"old-video")
    pose = _asset(character, "generated/run-standing.png", b"selected-pose")
    escaped = _asset(settings.data_root, "outside.mp4", b"outside")
    state = {
        "characters": [
            {
                "name": "hero",
                "stages": {
                    "prepare": {
                        "active_revision": "selected",
                        "revisions": {
                            "selected": {
                                "status": "complete",
                                "definition_archive": archive,
                                "artifacts": {"video": selected_video},
                            },
                            "old": {
                                "status": "complete",
                                "definition_archive": archive,
                                "artifacts": {"video": old_video},
                            },
                        },
                    },
                    "run": {
                        "active_revision": "selected",
                        "revisions": {
                            "selected": {
                                "status": "complete",
                                "definition_archive": archive,
                                "poses": {"standing": pose},
                                "artifacts": {"frames": [escaped]},
                            },
                            "partial": {
                                "status": "running",
                                "definition_archive": archive,
                                "artifacts": {"video": old_video},
                            },
                        },
                    },
                },
            }
        ]
    }
    engine.mkdir(parents=True, exist_ok=True)
    state_path = engine / "staged-generation-state.json"
    state_path.write_text(json.dumps(state))
    # Capture uses the actual job revision helper at the completion boundary.
    capture_job_revisions(settings.data_root, "ws_preview", "42", job["id"])
    # A later job can advance the shared generation state without changing this
    # job's preview projection.
    state["characters"][0]["stages"]["prepare"]["active_revision"] = "old"
    state_path.write_text(json.dumps(state))
    client = TestClient(app)
    login = client.post("/api/session", json={"username": "operator", "password": "password"})
    assert login.status_code == 200
    return client, app, job, selected_video, old_video


def test_previews_use_only_active_complete_revision_and_map_dependencies(tmp_path):
    client, app, job, selected_video, old_video = _client_with_preview_state(tmp_path)
    before = app.state.store.job(job["id"])
    response = client.get(f"/api/jobs/{job['id']}/previews")
    assert response.status_code == 200, response.text
    stages = {stage["stage_id"]: stage for stage in response.json()["stages"]}
    assert set(stages) == {"prepare", "run"}
    assert stages["prepare"]["reason"] == "dependency"
    assert stages["prepare"]["dependency_for"] == ["run"]
    assert stages["run"]["reason"] == "selected"
    assert stages["run"]["action_id"] == "run"
    assert stages["run"]["label"] == "Run output"
    prepare = stages["prepare"]["assets"]
    assert len(prepare) == 1 and prepare[0]["filename"] == "prepare-selected.mp4"
    assert prepare[0]["sha256"] == selected_video["sha256"]
    assert prepare[0]["sha256"] != old_video["sha256"]
    assert stages["run"]["assets"][0]["kind"] == "pose"
    assert app.state.store.job(job["id"]) == before


def test_preview_media_is_authenticated_ranged_and_rejects_invalid_or_hidden_assets(tmp_path):
    client, _app, job, _selected, _old = _client_with_preview_state(tmp_path)
    document = client.get(f"/api/jobs/{job['id']}/previews").json()
    video = next(asset for stage in document["stages"] for asset in stage["assets"] if asset["kind"] == "video")
    media = client.get(video["url"], headers={"Range": "bytes=0-7"})
    assert media.status_code == 206
    assert media.headers["content-type"].startswith("video/mp4")
    assert media.content == b"selected"
    assert client.get("/api/previews/pv_not-an-opaque-id").status_code == 404
    client.cookies.clear()
    assert client.get(video["url"]).status_code == 401


def test_previews_are_empty_until_the_job_records_completed_revision_selection(tmp_path):
    client, app, job, _selected, _old = _client_with_preview_state(tmp_path)
    selection = (
        app.state.settings.data_root
        / "workspaces"
        / "ws_preview"
        / "preview-revisions"
        / f"{job['id']}.json"
    )
    selection.unlink()
    response = client.get(f"/api/jobs/{job['id']}/previews")
    assert response.status_code == 200
    assert response.json() == {
        "job_id": job["id"],
        "stage_owners": {"prepare": "run", "run": "run"},
        "stages": [],
    }


def test_preview_stage_owners_exist_before_artifacts_and_follow_snapshot_plan_order(tmp_path):
    """A shared dependency has one stable consumer before any raw asset exists."""
    settings = WebSettings(
        data_root=tmp_path / "data",
        config_path=tmp_path / "editable.yaml",
        scheduler=False,
    )
    app = create_app(settings)
    definition = {
        # This insertion order is the immutable execution-plan order.  Idle
        # precedes Walk even when the submitted selected-actions order is the
        # reverse, so Idle owns their shared Stop dependency.
        "stages": {
            "stop": {"inputs": {}, "outputs": {}},
            "idle": {
                "inputs": {"source": {"stage": "stop"}},
                "outputs": {"animation": {"name": "idle"}},
            },
            "walk": {
                "inputs": {"source": {"stage": "stop"}},
                "outputs": {"animation": {"name": "walk"}},
            },
            "run": {
                "inputs": {"source": {"stage": "stop"}},
                "outputs": {"animation": {"name": "run"}},
            },
        }
    }
    request = {"actions": ["walk", "idle"], "seed": {"value": "42"}}
    job, _ = app.state.store.create_job("ws_owner", request, {}, definition, "owner-key")
    document = job_previews(app.state.store, settings.data_root, job["id"])
    assert document == {
        "job_id": job["id"],
        "stage_owners": {"stop": "idle", "idle": "idle", "walk": "walk"},
        "stages": [],
    }

    # The root stage remains owned by its selected action rather than being
    # remapped by a draft/request ordering change.
    run_request = {"actions": ["run"], "seed": {"value": "43"}}
    run_job, _ = app.state.store.create_job(
        "ws_owner", run_request, {}, definition, "owner-run-key"
    )
    assert job_previews(app.state.store, settings.data_root, run_job["id"])[
        "stage_owners"
    ] == {"stop": "run", "run": "run"}


def test_unindexed_legacy_active_job_exposes_only_persisted_completed_stages(tmp_path):
    client, app, job, _selected, _old = _client_with_preview_state(tmp_path)
    (
        app.state.settings.data_root
        / "workspaces"
        / "ws_preview"
        / "preview-revisions"
        / f"{job['id']}.json"
    ).unlink()
    app.state.store.update_job(
        job["id"],
        status="generating",
        completed_stages=1,
        worker_id=process_identity(os.getpid()),
    )
    response = client.get(f"/api/jobs/{job['id']}/previews")
    assert response.status_code == 200
    assert [stage["stage_id"] for stage in response.json()["stages"]] == ["prepare"]


def test_preview_server_static_root_and_no_scheduler_flags(tmp_path, monkeypatch):
    from sprite_extractor.web import app as web_app
    from sprite_extractor.web import settings as web_settings

    static = tmp_path / "isolated-static"
    static.mkdir()
    (static / "index.html").write_text("isolated preview build")
    settings = WebSettings(
        data_root=tmp_path / "data",
        config_path=tmp_path / "config.yaml",
        static_root=static,
        scheduler=False,
    )
    with TestClient(create_app(settings)) as browser:
        assert browser.get("/").text == "isolated preview build"
        assert browser.app.state.settings.scheduler is False
    monkeypatch.setenv("SPRITE_EXTRACTOR_NO_SCHEDULER", "true")
    monkeypatch.setenv("SPRITE_EXTRACTOR_STATIC_ROOT", str(static))
    assert web_settings.WebSettings.from_env().scheduler is False
    assert web_settings.WebSettings.from_env().static_root == static.resolve()
    captured = {}
    initial = WebSettings(data_root=tmp_path / "cli", config_path=tmp_path / "cli.yaml")
    monkeypatch.setattr(web_settings.WebSettings, "from_env", classmethod(lambda _cls: initial))
    monkeypatch.setattr(
        "uvicorn.run",
        lambda app, **_kwargs: captured.update(
            scheduler=app.state.settings.scheduler,
            static_root=app.state.settings.static_root,
        ),
    )
    monkeypatch.setattr(
        "sys.argv",
        ["sprite-extractor-web", "--no-scheduler", "--static-root", str(static)],
    )
    web_app.main()
    assert captured == {"scheduler": False, "static_root": static.resolve()}
