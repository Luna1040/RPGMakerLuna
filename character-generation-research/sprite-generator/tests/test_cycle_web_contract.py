from contextlib import nullcontext
from pathlib import Path

from sprite_extractor.web.worker import Scheduler


def test_cycle_revision_incomplete_package_never_publishes_old_selected_package(monkeypatch, tmp_path):
    """A stale selected_package_id cannot turn a failed child rebuild into Ready."""
    import sprite_extractor.cycle_review as review
    import sprite_extractor.definition_runtime as runtime
    import sprite_extractor.execution_hooks as hooks
    import sprite_extractor.execution_lock as lock
    import sprite_extractor.submission_journal as journal
    import sprite_extractor.web.worker as worker

    published = []
    monkeypatch.setattr(review, "resolve_pinned_sources", lambda *_: {"run": {"generation_id": "pinned"}})
    monkeypatch.setattr(review, "resolve_pinned_analyses", lambda *_: {"run": object()})
    monkeypatch.setattr(review, "load_cycle_index", lambda *_args, **_kwargs: ({"groups": [{"action": "run", "analysis_id": "analysis", "analysis_path": str(tmp_path), "generation_id": "pinned", "selected_candidate_id": "candidate"}]}, "parent"))
    monkeypatch.setattr(runtime, "package_definitions", lambda *_args, **_kwargs: {"complete": False, "characters": [{"selected_package_id": "old-package", "packages": {"old-package": {"status": "complete"}, "new": {"status": "failed", "error": "split failed"}}}]})
    monkeypatch.setattr(lock, "output_tree_lock", lambda *_: nullcontext())
    monkeypatch.setattr(journal, "use_submission_journal", lambda *_: nullcontext())
    monkeypatch.setattr(hooks, "execution_hooks", lambda *_: nullcontext())
    monkeypatch.setattr(worker, "publish_package", lambda *_args, **_kwargs: published.append(True))
    (tmp_path / "staged-generation-state.json").write_text("{}")
    scheduler = Scheduler(object(), tmp_path)
    job = {"id": "child", "parent_job_id": "parent", "workspace_id": "ws", "kind": "cycle_revision", "request": {"actions": ["run"], "frame_counts": {"run": 8}, "sprite_size": 256, "split_method": "blobs", "_cycle_selections": {"run": {"analysis_id": "analysis", "candidate_id": "candidate"}}, "_cycle_pins": {"sources": {"run": {"generation_id": "pinned"}}, "analyses": {"run": {"analysis_id": "analysis"}}}}}
    class Config:
        def as_dict(self): return {"comfyui_url": "mock", "generation_timeout": 1}
    with __import__("pytest").raises(RuntimeError, match="split failed"):
        scheduler.run_cycle_child(job, Config(), object(), tmp_path, lambda *_: None, lambda: False, lambda *_: None)
    assert published == []

def test_cycle_api_reads_durable_asset_and_idempotent_revision_without_models(monkeypatch, tmp_path):
    import json
    import hashlib
    from fastapi.testclient import TestClient
    from sprite_extractor.web.app import create_app
    from sprite_extractor.web.settings import WebSettings
    from sprite_extractor.cycle_review import register_cycle_analysis
    import sprite_extractor.cycle_review as review
    settings = WebSettings(
        data_root=tmp_path / "data", config_path=tmp_path / "cfg.yaml", scheduler=False
    )
    app = create_app(settings)
    store = app.state.store
    definition = {
        "stages": {
            "run": {
                "inputs": {},
                "outputs": {
                    "animation": {
                        "name": "run", "label": "Run", "selection": {"method": "cycle"}
                    }
                },
            }
        }
    }
    request = {
        "workspace_id": "ws", "actions": ["run"], "frame_counts": {"run": 8},
        "style": "neutral", "seed": {"mode": "fixed", "value": "1"},
        "sprite_size": 256, "generation": {"width": 400, "height": 512, "pad_top_percent": 0},
        "split_method": "blobs", "animation_overrides": {},
    }
    store.insert_json("workspaces", "ws", {"id": "ws", "upload_id": "up"})
    store.insert_json("uploads", "up", {"id": "up", "path": str(tmp_path / "source.png")})
    parent, _ = store.create_job("ws", request, {"model": "pinned"}, definition, "parent-key")
    store.update_job(parent["id"], status="ready")

    analysis = settings.data_root / "analysis"
    frames = {
        "candidate": (analysis / "frames" / "safe.png", b"safe"),
        "corrupt": (analysis / "corrupt" / "corrupt.png", b"corrupt-original"),
        "missing": (analysis / "missing" / "missing.png", b"missing"),
    }
    candidates = []
    for ordinal, (candidate_id, (frame, payload)) in enumerate(frames.items()):
        frame.parent.mkdir(parents=True, exist_ok=True)
        frame.write_bytes(payload)
        candidates.append({
            "id": candidate_id,
            "start_time_seconds": ordinal,
            "end_time_seconds": ordinal + 1,
            "period_seconds": 1,
            "frames": [{
                "path": str(frame.relative_to(analysis)), "frame_id": ordinal,
                "pts": ordinal, "time_seconds": ordinal,
                "sha256": hashlib.sha256(payload).hexdigest(),
            }],
        })
    summary = {
        "analysis_id": "analysis", "sample_set_id": "sample", "selected_frame_count": 8,
        "period": {"seconds": 1}, "system_candidate_id": "candidate",
        "cycle_candidates": candidates,
    }
    (analysis / "summary.json").write_text(json.dumps(summary))
    (analysis / "manifest.json").write_text("{}")
    register_cycle_analysis(store, "ws", parent["id"], analysis)

    def write_index(job_id):
        index = settings.data_root / "workspaces/ws/cycle-job-index"
        index.mkdir(parents=True, exist_ok=True)
        (index / f"{job_id}.json").write_text(json.dumps({"groups": [{
            "action": "run", "analysis_path": str(analysis), "analysis_id": "analysis",
            "sample_set_id": "sample", "selected_candidate_id": "candidate",
            "system_candidate_id": "candidate", "selection_origin": "automatic",
            "generation_id": "pinned",
        }]}))

    write_index(parent["id"])
    sources = lambda *_: {"run": {"generation_id": "pinned"}}
    monkeypatch.setattr(review, "pinned_action_sources", sources)
    monkeypatch.setattr(review, "ensure_cycle_analysis", lambda *_a, **_k: __import__("pytest").fail("revision unexpectedly started model analysis"))
    with TestClient(app) as client:
        jobs_before = len(store.jobs(100))
        cycles = client.get(f"/api/jobs/{parent['id']}/cycles")
        assert cycles.status_code == 200
        document = cycles.json()
        assert document["can_revise"] is True
        assert len(store.jobs(100)) == jobs_before
        assets = {
            candidate["id"]: candidate["frames"][0]["url"]
            for candidate in document["groups"][0]["candidates"]
        }
        assert client.get(assets["candidate"]).content == b"safe"
        session = client.get("/api/session")
        assert session.status_code == 200
        headers = {
            "Idempotency-Key": "revision-key-123",
            "X-CSRF-Token": session.json()["csrf_token"],
        }
        body = {"selections": {"run": {"analysis_id": "analysis", "candidate_id": "candidate"}}}
        one = client.post(f"/api/jobs/{parent['id']}/cycle-revisions", headers=headers, json=body)
        two = client.post(f"/api/jobs/{parent['id']}/cycle-revisions", headers=headers, json=body)
        assert one.status_code == two.status_code == 202
        assert one.json()["id"] == two.json()["id"]
        child = store.job(one.json()["id"])
        assert child["kind"] == "cycle_revision"
        assert child["parent_job_id"] == parent["id"]
        assert child["request"]["_cycle_selections"] == body["selections"]
        with store.connect() as db:
            snapshot = db.execute(
                "SELECT config_snapshot, definition_snapshot FROM jobs WHERE id=?", (child["id"],)
            ).fetchone()
        assert json.loads(snapshot["config_snapshot"]) == {"model": "pinned"}
        assert json.loads(snapshot["definition_snapshot"]) == definition
        bad = client.post(
            f"/api/jobs/{parent['id']}/cycle-revisions",
            headers=headers | {"Idempotency-Key": "revision-key-456"},
            json={"selections": {"run": {"analysis_id": "analysis", "candidate_id": "bad"}}},
        )
        assert bad.status_code == 409

        other, _ = store.create_job("ws", request, {}, definition, "other-parent-key")
        store.update_job(other["id"], status="ready")
        write_index(other["id"])
        conflict = client.post(f"/api/jobs/{other['id']}/cycle-revisions", headers=headers, json=body)
        assert conflict.status_code == 409

    # A process with no warmed in-memory index can serve the DB-backed opaque URL.
    with TestClient(create_app(settings)) as fresh:
        assert fresh.get(assets["candidate"]).content == b"safe"
        frames["corrupt"][0].write_bytes(b"changed")
        assert fresh.get(assets["corrupt"]).status_code == 404
        frames["missing"][0].unlink()
        assert fresh.get(assets["missing"]).status_code == 404
        safe = frames["candidate"][0]
        outside = tmp_path / "outside"
        outside.mkdir()
        (outside / safe.name).write_bytes(b"safe")
        safe.unlink()
        safe.parent.rmdir()
        safe.parent.symlink_to(outside, target_is_directory=True)
        assert fresh.get(assets["candidate"]).status_code == 404
