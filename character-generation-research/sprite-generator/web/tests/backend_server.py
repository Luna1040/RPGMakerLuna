"""Ephemeral backend used by the Playwright packaged-UI integration test."""

from __future__ import annotations

import argparse
import hashlib
import json
import tempfile
from pathlib import Path

import uvicorn

import sprite_extractor.comfy_workflow as comfy_workflow
from sprite_extractor.web.app import create_app
from sprite_extractor.web.settings import WebSettings
from sprite_extractor.cycle_review import register_cycle_analysis
import sprite_extractor.cycle_review as cycle_review


class _ReadOnlyComfyClient:
    """Connection-check seam; the scheduler is disabled so no prompt can run."""

    def __init__(self, *_args, **_kwargs):
        pass

    def _json(self, *_args, **_kwargs):
        return {}


def seed_cycle_parent(app, data_root: Path) -> None:
    """Seed a durable, scheduler-free ready render for the real browser cycle path."""
    store = app.state.store
    definition = {"stages": {"run": {"inputs": {}, "outputs": {"animation": {"name": "run", "label": "Run", "selection": {"method": "cycle"}}}}}}
    request = {"workspace_id": "cycle-ws", "actions": ["run"], "frame_counts": {"run": 2}, "style": "neutral", "seed": {"mode": "fixed", "value": "42"}, "sprite_size": 64, "generation": {"width": 400, "height": 512, "pad_top_percent": 0}, "split_method": "quarters", "animation_overrides": {}}
    from PIL import Image
    upload_dir = data_root / "uploads/cycle-upload"; upload_dir.mkdir(parents=True)
    source = upload_dir / "source.png"; thumbnail = upload_dir / "thumbnail.png"
    Image.new("RGB", (2, 2), "white").save(source); Image.new("RGB", (2, 2), "white").save(thumbnail)
    upload = {"id": "cycle-upload", "filename": "source.png", "media_type": "image/png", "width": 2, "height": 2, "bytes": source.stat().st_size, "sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "path": str(source), "thumbnail_path": str(thumbnail), "thumbnail_url": "/sprites/api/artifacts/thumb-cycle"}
    store.insert_json("uploads", "cycle-upload", upload)
    store.insert_json("workspaces", "cycle-ws", {"id": "cycle-ws", "name": "Cycle fixture", "upload_id": "cycle-upload", "source": {k: v for k, v in upload.items() if not k.endswith("path")}, "storage_bytes": upload["bytes"]})
    parent, _ = store.create_job("cycle-ws", request, {}, definition, "cycle-parent-key")
    descriptor = {"artifact_id": "fixture", "filename": "fixture.png", "media_type": "image/png", "bytes": 79, "sha256": "fixture", "url": "/sprites/api/artifacts/fixture"}
    package = {"id": "pkg-cycle", "job_id": parent["id"], "sheet": descriptor, "metadata": {**descriptor, "filename": "fixture.json", "media_type": "application/json"}, "manifest": {**descriptor, "filename": "manifest.json", "media_type": "application/json"}, "actions": ["run"], "still_actions": [], "animations": [], "action_downloads": {"run": "/sprites/api/packages/pkg-cycle/download?action=run"}, "preview": {"layout": {"rows": 4, "columns": 2, "cell_size": 64, "directions": ["right", "left", "back", "front"], "animation_ranges": {"run": [0, 2]}}, "frame_durations_ms": {"run:right": [500, 500]}}, "download_url": "/sprites/api/packages/pkg-cycle/download"}
    with store.connect() as database:
        database.execute("INSERT INTO packages(id,job_id,record) VALUES(?,?,?)", ("pkg-cycle", parent["id"], json.dumps(package)))
    store.update_job(parent["id"], status="ready", package_id="pkg-cycle")
    analysis = data_root / "cycle-analysis"; frames = analysis / "frames"; frames.mkdir(parents=True)
    candidates = []
    for candidate_id, colors in (("system", ((20, 60, 100), (30, 60, 100))), ("alternate", ((40, 60, 100), (50, 60, 100)))):
        records = []
        for index, color in enumerate(colors):
            path = frames / f"{candidate_id}-{index}.png"
            from PIL import Image
            Image.new("RGB", (400, 100), color).save(path)
            records.append({"frame_id": index, "pts": index, "time_seconds": index / 10, "path": str(path.relative_to(analysis)), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
        candidates.append({"id": candidate_id, "start_time_seconds": 0, "end_time_seconds": 1, "period_seconds": 1, "sample_times_seconds": [0, .5], "frames": records})
    (analysis / "summary.json").write_text(json.dumps({"analysis_id": "browser-analysis", "sample_set_id": "browser-samples", "source": {"sha256": "fixture"}, "period": {"seconds": 1}, "selected_frame_count": 2, "system_candidate_id": "system", "cycle_candidates": candidates}))
    (analysis / "manifest.json").write_text("{}")
    register_cycle_analysis(store, "cycle-ws", parent["id"], analysis)
    index = data_root / "workspaces/cycle-ws/cycle-job-index"; index.mkdir(parents=True)
    (index / f"{parent['id']}.json").write_text(json.dumps({"groups": [{"action": "run", "analysis_path": str(analysis), "analysis_id": "browser-analysis", "sample_set_id": "browser-samples", "selected_candidate_id": "system", "system_candidate_id": "system", "selection_origin": "automatic", "generation_id": "fixture"}]}))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--static-root", type=Path, required=True)
    args = parser.parse_args()
    comfy_workflow.ComfyClient = _ReadOnlyComfyClient
    cycle_review.pinned_action_sources = lambda *_args: {"run": {"generation_id": "fixture", "sha256": "fixture", "stage_id": "run"}}
    with tempfile.TemporaryDirectory(prefix="sprite-extractor-playwright-") as root:
        data_root = Path(root)
        app = create_app(
            WebSettings(
                data_root,
                data_root / "config.yaml",
                username="configured-user",
                password="configured-password",
                base_path="/sprites",
                scheduler=False,
                no_auth=True,
                static_root=args.static_root,
            )
        )
        seed_cycle_parent(app, data_root)
        uvicorn.run(app, host="127.0.0.1", port=args.port)


if __name__ == "__main__":
    main()
