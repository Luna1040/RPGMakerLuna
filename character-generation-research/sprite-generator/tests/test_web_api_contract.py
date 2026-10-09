"""Offline HTTP contracts for the FastAPI operator surface."""
from __future__ import annotations

from io import BytesIO

import pytest
from PIL import Image

from sprite_extractor.web.app import create_app
from sprite_extractor.web.settings import WebSettings


@pytest.fixture
def client(tmp_path):
    from fastapi.testclient import TestClient
    settings = WebSettings(
        data_root=tmp_path / "data", config_path=tmp_path / "editable.yaml", scheduler=False
    )
    with TestClient(create_app(settings)) as value:
        yield value


def _csrf(client):
    response = client.get("/api/session")
    assert response.status_code == 200
    return {"X-CSRF-Token": response.json()["csrf_token"]}


def _image_bytes(mode="RGBA", size=(8, 8)):
    image = Image.new(mode, size, "white")
    payload = BytesIO()
    image.save(payload, "PNG")
    return payload.getvalue()


def _workspace(client):
    headers = _csrf(client)
    upload = client.post("/api/uploads", headers=headers, files={"file": ("hero.png", _image_bytes(), "image/png")})
    assert upload.status_code == 201, upload.text
    workspace = client.post("/api/workspaces", headers=headers, json={"upload_id": upload.json()["id"], "name": "Hero"})
    assert workspace.status_code == 201, workspace.text
    return headers, workspace.json()


def _request(workspace_id, seed="9223372036854775807"):
    return {"workspace_id": workspace_id, "actions": ["walk"], "frame_counts": {"walk": 4}, "style": "neutral", "seed": {"mode": "fixed", "value": seed}, "sprite_size": 256, "generation": {"width": 400, "height": 512, "pad_top_percent": 0}, "split_method": "blobs", "animation_overrides": {}}


def test_upload_plan_and_job_creation_have_no_inference_side_effect(client, monkeypatch):
    headers, workspace = _workspace(client)
    import sprite_extractor.definition_runtime as runtime
    monkeypatch.setattr(runtime, "ComfyClient", lambda *_a, **_k: pytest.fail("HTTP draft flow contacted ComfyUI"))
    request = _request(workspace["id"])
    plan = client.post("/api/plans", headers=headers, json=request)
    assert plan.status_code == 200, plan.text
    assert plan.json()["resolved_seed"] in {None, "9223372036854775807"}
    assert plan.json()["summary"]["directions"] == 4
    assert any(stage["reason"] == "dependency" for stage in plan.json()["stages"])
    first = client.post("/api/jobs", headers=headers | {"Idempotency-Key": "lost-response-key"}, json={"request": request})
    second = client.post("/api/jobs", headers=headers | {"Idempotency-Key": "lost-response-key"}, json={"request": request})
    assert first.status_code == second.status_code == 202
    assert second.json()["id"] == first.json()["id"]
    assert first.json()["resolved_seed"] == "9223372036854775807"
    assert client.get(first.json()["links"]["self"]).json()["status"] == "queued"


def test_mutations_need_csrf_and_cross_origin_is_rejected(client):
    image = {"file": ("hero.png", _image_bytes(), "image/png")}
    assert client.post("/api/uploads", files=image).status_code == 403
    headers = _csrf(client)
    rejected = client.post("/api/uploads", headers=headers | {"Origin": "https://evil.invalid"}, files=image)
    assert rejected.status_code == 403
    assert rejected.json()["error"]["message"] == "cross-origin mutation rejected"


def test_upload_rejects_corrupt_content_and_decoded_pixel_limit(tmp_path):
    from fastapi.testclient import TestClient
    app = create_app(WebSettings(data_root=tmp_path / "data", config_path=tmp_path / "editable.yaml", pixel_limit=16, scheduler=False))
    with TestClient(app) as client:
        headers = _csrf(client)
        corrupt = client.post("/api/uploads", headers=headers, files={"file": ("nope.png", b"not an image", "image/png")})
        huge = client.post("/api/uploads", headers=headers, files={"file": ("many-pixels.png", _image_bytes(size=(8, 8)), "image/png")})
    assert corrupt.status_code == 422
    assert huge.status_code == 413


def test_config_conflict_seed_string_and_stop_resume_recovery_boundary(client):
    headers, workspace = _workspace(client)
    config = client.get("/api/config").json()
    seed = next(field for field in config["fields"] if field["path"] == ["seed"])
    assert isinstance(seed["value"], str)
    saved = client.patch("/api/config", headers=headers, json={"revision": config["revision"], "changes": [{"path": ["sprite_box_height"], "value": 320}]})
    assert saved.status_code == 200
    conflict = client.patch("/api/config", headers=headers, json={"revision": config["revision"], "changes": [{"path": ["sprite_box_height"], "value": 128}]})
    assert conflict.status_code == 409
    job = client.post("/api/jobs", headers=headers | {"Idempotency-Key": "stop-resume-key"}, json={"request": _request(workspace["id"], "8")}).json()
    stopped = client.post(f"/api/jobs/{job['id']}/stop", headers=headers)
    assert stopped.status_code == 202 and stopped.json()["status"] == "stopped"
    resumed = client.post(f"/api/jobs/{job['id']}/resume", headers=headers)
    assert resumed.status_code == 202 and resumed.json()["request"] == job["request"]
    client.app.state.store.update_job(job["id"], status="recovery_required", error="unknown submission")
    recovery = client.post(f"/api/jobs/{job['id']}/resume", headers=headers)
    assert recovery.status_code == 409
    assert recovery.json()["error"]["code"] == "recovery_required"


def test_random_idempotency_reuses_resolved_seed_across_config_change(client):
    headers, workspace = _workspace(client)
    raw = _request(workspace["id"])
    raw["seed"] = {"mode": "random"}
    first = client.post("/api/jobs", headers=headers | {"Idempotency-Key": "random-retry-key"}, json={"request": raw})
    assert first.status_code == 202
    config = client.get("/api/config").json()
    changed = client.patch("/api/config", headers=headers, json={"revision": config["revision"], "changes": [{"path":["seed"], "value":"12"}]})
    assert changed.status_code == 200
    retry = client.post("/api/jobs", headers=headers | {"Idempotency-Key": "random-retry-key"}, json={"request": raw})
    assert retry.status_code == 202
    assert retry.json()["id"] == first.json()["id"]
    assert retry.json()["resolved_seed"] == first.json()["resolved_seed"]
    altered = {**raw, "sprite_size": 320}
    conflict = client.post("/api/jobs", headers=headers | {"Idempotency-Key": "random-retry-key"}, json={"request": altered})
    assert conflict.status_code == 409
    assert conflict.json()["error"]["code"] == "idempotency_conflict"


def test_backend_serves_built_spa_fonts_and_base_path_without_parent_assets(tmp_path):
    from fastapi.testclient import TestClient
    settings = WebSettings(data_root=tmp_path / "data", config_path=tmp_path / "editable.yaml", base_path="/sprites", scheduler=False)
    with TestClient(create_app(settings)) as browser:
        shell = browser.get("/sprites/")
        assert shell.status_code == 200 and "Sprite Extractor" in shell.text
        asset = next(line.split('"')[1] for line in shell.text.splitlines() if "/assets/" in line)
        assert browser.get("/sprites/" + asset.lstrip("/")).status_code == 200
        assert browser.get("/sprites/recent").status_code == 200
        assert browser.get("/assets/not-from-parent").status_code == 404


def test_no_auth_allows_remote_cookie_free_session_but_keeps_csrf_and_origin(tmp_path):
    from fastapi.testclient import TestClient

    settings = WebSettings(
        data_root=tmp_path / "data",
        config_path=tmp_path / "editable.yaml",
        username="configured-user",
        password="configured-password",
        no_auth=True,
        scheduler=False,
    )
    with TestClient(
        create_app(settings),
        base_url="http://192.168.50.8:8787",
        client=("192.168.50.23", 4545),
    ) as remote:
        session = remote.get("/api/session")
        assert session.status_code == 200
        assert session.json()["operator"] == "network"
        assert session.json()["auth_required"] is False
        assert not remote.cookies
        csrf = session.json()["csrf_token"]
        image = {"file": ("hero.png", _image_bytes(), "image/png")}
        accepted = remote.post("/api/uploads", headers={"X-CSRF-Token": csrf}, files=image)
        assert accepted.status_code == 201
        bad_csrf = remote.post("/api/uploads", files=image)
        assert bad_csrf.status_code == 403
        cross_origin = remote.post(
            "/api/uploads",
            headers={"X-CSRF-Token": csrf, "Origin": "http://other.lan"},
            files=image,
        )
        assert cross_origin.status_code == 403

    incomplete_credentials = WebSettings(
        data_root=tmp_path / "incomplete",
        config_path=tmp_path / "incomplete.yaml",
        username="stale",
        password=None,
        no_auth=True,
        scheduler=False,
    )
    with TestClient(
        create_app(incomplete_credentials),
        base_url="http://192.168.50.8:8787",
        client=("192.168.50.23", 4545),
    ) as remote:
        session = remote.get("/api/session")
        assert session.status_code == 200
        assert session.json()["authenticated"] is True
        assert session.json()["auth_required"] is False


def test_remote_default_stays_denied_and_configured_auth_still_needs_login(tmp_path):
    from fastapi.testclient import TestClient

    common = dict(base_url="http://192.168.50.8:8787", client=("192.168.50.23", 4545))
    default = WebSettings(data_root=tmp_path / "default", config_path=tmp_path / "default.yaml", scheduler=False)
    with TestClient(create_app(default), **common) as remote:
        assert remote.get("/api/session").status_code == 401
    protected = WebSettings(
        data_root=tmp_path / "protected",
        config_path=tmp_path / "protected.yaml",
        username="operator",
        password="password",
        secret="x" * 32,
        scheduler=False,
    )
    with TestClient(create_app(protected), **common) as remote:
        assert remote.get("/api/session").status_code == 401
        login = remote.post("/api/session", json={"username": "operator", "password": "password"})
        assert login.status_code == 200
        assert remote.get("/api/session").status_code == 200


def test_no_auth_environment_and_cli_override(tmp_path, monkeypatch):
    from sprite_extractor.web import app as web_app
    from sprite_extractor.web import settings as web_settings

    for key in ("SPRITE_EXTRACTOR_NO_AUTH", "SPRITE_EXTRACTOR_USERNAME", "SPRITE_EXTRACTOR_PASSWORD"):
        monkeypatch.delenv(key, raising=False)
    assert web_settings.WebSettings.from_env().no_auth is False
    monkeypatch.setenv("SPRITE_EXTRACTOR_NO_AUTH", "yes")
    monkeypatch.setenv("SPRITE_EXTRACTOR_USERNAME", "still-configured")
    monkeypatch.setenv("SPRITE_EXTRACTOR_PASSWORD", "still-configured")
    assert web_settings.WebSettings.from_env().no_auth is True
    captured = {}
    initial = WebSettings(data_root=tmp_path / "cli", config_path=tmp_path / "cli.yaml", scheduler=False)
    monkeypatch.setattr(web_settings.WebSettings, "from_env", classmethod(lambda _cls: initial))
    monkeypatch.setattr("uvicorn.run", lambda app, **_kwargs: captured.setdefault("no_auth", app.state.settings.no_auth))
    monkeypatch.setattr("sys.argv", ["sprite-extractor-web", "--no-auth"])
    web_app.main()
    assert captured["no_auth"] is True


def test_activity_feed_is_ordered_restorable_and_never_exposes_submission_graph(client):
    headers, workspace = _workspace(client)
    job = client.post(
        "/api/jobs",
        headers=headers | {"Idempotency-Key": "activity-feed-key"},
        json={"request": _request(workspace["id"], "8")},
    ).json()
    store = client.app.state.store
    store.event(job["id"], "activity", {"state": "submitting", "operation": "generation", "stage_id": "run", "prompt_id": None, "message": "Submitting", "error": None})
    store.event(job["id"], "activity", {"state": "unknown", "operation": "comfy", "stage_id": "run", "prompt_id": None, "message": "Connection outcome unknown", "error": {"code": "submission_unknown", "message": "Do not resubmit", "retryable": False, "recovery_required": True}})
    response = client.get(f"/api/jobs/{job['id']}/activity?after=0&limit=1")
    assert response.status_code == 200
    body = response.json()
    assert len(body["activities"]) == 1
    assert body["next_cursor"] == body["activities"][0]["sequence"]
    restored = client.get(f"/api/jobs/{job['id']}/activity?after={body['next_cursor']}").json()
    assert restored["current"]["state"] == "unknown"
    assert restored["current"]["error"]["recovery_required"] is True
    assert restored["activities"] == []
    assert "graph" not in repr(restored).lower()
    assert client.get(f"/api/jobs/{job['id']}/activity?after=-1").status_code == 422
