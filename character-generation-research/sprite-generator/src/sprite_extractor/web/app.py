import asyncio
import hashlib
import hmac
import json
import os
import secrets
import shutil
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit


def _leaf_strings(value):
    if isinstance(value, dict):
        for item in value.values():
            yield from _leaf_strings(item)
    elif isinstance(value, str):
        yield value


def create_app(settings=None, *, runner=None):
    from fastapi import (
        FastAPI,
        File,
        Header,
        HTTPException,
        Request,
        Response,
        UploadFile,
    )
    from fastapi.exceptions import RequestValidationError
    from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
    from PIL import Image, UnidentifiedImageError
    from .settings import WebSettings
    from .store import Store, ident, now
    from .config_store import ConfigStore
    from .worker import Scheduler
    from .artifacts import artifact, safe_managed, zip_file
    from .previews import job_previews, resolve_preview
    from ..cycle_review import (
        cycle_asset,
        job_cycles,
        load_cycle_index,
        pinned_action_sources,
    )
    from ..animation_definitions import load_registry
    from ..application import normalize_request, plan_request
    from ..io_utils import sha256_file

    settings = settings or WebSettings.from_env()
    settings.data_root.mkdir(parents=True, exist_ok=True)
    if settings.base_path and (
        not settings.base_path.startswith("/") or settings.base_path.endswith("/")
    ):
        raise ValueError(
            "base path must be empty or start with one slash and have no trailing slash"
        )
    if settings.upload_limit <= 0 or settings.pixel_limit <= 0:
        raise ValueError("upload and pixel limits must be positive")
    if not settings.no_auth and (
        (settings.username is None) != (settings.password is None)
        or settings.username == ""
        or settings.password == ""
    ):
        raise ValueError("both web username and password are required and nonempty")
    if (
        settings.username is not None
        and not settings.no_auth
        and (
            settings.secret == "development-only-change-me" or len(settings.secret) < 32
        )
    ):
        raise ValueError(
            "authenticated deployments require a secret of at least 32 characters"
        )
    prefix = settings.base_path
    store = Store(settings.data_root / "jobs.sqlite3", prefix)
    configs = ConfigStore(settings.config_path)
    app = FastAPI(
        title="Sprite Extractor",
        docs_url=None,
        redoc_url=None,
        openapi_url=prefix + "/api/openapi.json" if prefix else "/api/openapi.json",
    )
    app.state.settings = settings
    app.state.store = store
    app.state.config_store = configs
    session_secret = (
        secrets.token_bytes(32)
        if settings.no_auth and settings.secret == "development-only-change-me"
        else settings.secret.encode()
    )

    @app.middleware("http")
    async def request_size_boundary(request, call_next):
        if request.url.path == prefix + "/api/uploads":
            try:
                await guard(request)
            except HTTPException as exc:
                return error(exc.status_code, "http_error", str(exc.detail))
            length = request.headers.get("content-length")
            # Multipart framing is small but variable; enforce a narrow transport cap
            # before Starlette asks python-multipart to parse the body.
            if length and int(length) > settings.upload_limit + 1024 * 1024:
                return JSONResponse(
                    {
                        "error": {
                            "code": "upload_too_large",
                            "message": "Upload exceeds configured size limit",
                            "fields": [],
                        }
                    },
                    status_code=413,
                )
            received = 0
            original_receive = request._receive

            async def limited_receive():
                nonlocal received
                message = await original_receive()
                received += len(message.get("body", b""))
                if received > settings.upload_limit + 1024 * 1024:
                    raise HTTPException(413, "upload exceeds configured size limit")
                return message

            request._receive = limited_receive
        return await call_next(request)

    def token(user: str) -> str:
        signature = hmac.new(session_secret, user.encode(), hashlib.sha256).hexdigest()
        return user + "." + signature

    def session(request: Request) -> dict[str, Any]:
        if settings.no_auth:
            return {
                "operator": "network",
                "csrf_token": token("network-csrf"),
                "auth_required": False,
            }
        if settings.username is None and settings.password is None:
            host = request.client.host if request.client else ""
            raw_authority = request.headers.get("host") or ""
            authority = (
                raw_authority[1:].split("]", 1)[0]
                if raw_authority.startswith("[")
                else raw_authority.split(":", 1)[0]
            )
            if host not in {
                "127.0.0.1",
                "::1",
                "localhost",
                "testclient",
            } or authority not in {"127.0.0.1", "::1", "localhost", "testserver"}:
                raise HTTPException(
                    401, "authentication must be configured for network access"
                )
            return {
                "operator": "local",
                "csrf_token": token("local-csrf"),
                "auth_required": False,
            }
        raw = request.cookies.get("sprite_extractor_session", "")
        user, sep, sig = raw.rpartition(".")
        if (
            not sep
            or user != settings.username
            or not hmac.compare_digest(
                sig, hmac.new(session_secret, user.encode(), hashlib.sha256).hexdigest()
            )
        ):
            raise HTTPException(401, "authentication required")
        return {
            "operator": user,
            "csrf_token": token(user + "-csrf"),
            "auth_required": True,
        }

    async def guard(request: Request):
        current = session(request)
        if request.method not in {"GET", "HEAD", "OPTIONS"}:
            if request.headers.get("x-csrf-token") != current["csrf_token"]:
                raise HTTPException(403, "invalid CSRF token")
            origin = request.headers.get("origin")
            if origin:
                parsed = urlsplit(origin)
                expected = request.headers.get("host")
                if parsed.netloc != expected or parsed.scheme != request.url.scheme:
                    raise HTTPException(403, "cross-origin mutation rejected")
        return current

    def error(status: int, code: str, message: str, fields=[]):
        return JSONResponse(
            {"error": {"code": code, "message": message, "fields": fields}},
            status_code=status,
        )

    @app.exception_handler(RequestValidationError)
    async def validation(_request, exc):
        return error(
            422,
            "validation_error",
            "Invalid request",
            [{"path": list(x["loc"]), "message": x["msg"]} for x in exc.errors()],
        )

    @app.exception_handler(HTTPException)
    async def http_error(_request, exc):
        return error(exc.status_code, "http_error", str(exc.detail))

    @app.post(prefix + "/api/session")
    async def login(request: Request, response: Response):
        body = await request.json()
        origin = request.headers.get("origin")
        if origin:
            parsed = urlsplit(origin)
            if (
                parsed.netloc != request.headers.get("host")
                or parsed.scheme != request.url.scheme
            ):
                raise HTTPException(403, "cross-origin mutation rejected")
        if settings.username is None or not (
            secrets.compare_digest(str(body.get("username", "")), settings.username)
            and secrets.compare_digest(
                str(body.get("password", "")), settings.password or ""
            )
        ):
            raise HTTPException(401, "invalid credentials")
        response.set_cookie(
            "sprite_extractor_session",
            token(settings.username),
            httponly=True,
            samesite="strict",
            secure=request.url.scheme == "https",
            path=prefix + "/" or "/",
        )
        return {
            "authenticated": True,
            "operator": settings.username,
            "csrf_token": token(settings.username + "-csrf"),
            "auth_required": True,
        }

    @app.get(prefix + "/api/session")
    async def get_session(request: Request):
        value = session(request)
        return {"authenticated": True, **value}

    @app.delete(prefix + "/api/session")
    async def logout(request: Request, response: Response):
        await guard(request)
        response.delete_cookie("sprite_extractor_session", path=prefix + "/" or "/")
        return {"authenticated": False}

    @app.post(prefix + "/api/uploads", status_code=201)
    async def upload(request: Request, file: UploadFile = File(...)):
        await guard(request)
        upload_id = ident("up_")
        folder = settings.data_root / "uploads" / upload_id
        folder.mkdir(parents=True)
        original = folder / "original"
        size = 0
        try:
            with original.open("xb") as out:
                while chunk := await file.read(1024 * 1024):
                    size += len(chunk)
                    if size > settings.upload_limit:
                        raise HTTPException(413, "upload exceeds configured size limit")
                    out.write(chunk)
            if size == 0:
                raise HTTPException(422, "uploaded file is empty")
            Image.MAX_IMAGE_PIXELS = settings.pixel_limit
            with Image.open(original) as image:
                image.verify()
            with Image.open(original) as image:
                width, height = image.size
                if width * height > settings.pixel_limit:
                    raise HTTPException(413, "decoded image exceeds pixel limit")
                media = Image.MIME.get(image.format)
                if media not in {"image/png", "image/jpeg", "image/webp"}:
                    raise HTTPException(422, "unsupported image format")
                thumb = image.convert("RGBA")
                thumb.thumbnail((512, 512))
                thumb.save(folder / "thumbnail.png")
        except Image.DecompressionBombError as exc:
            shutil.rmtree(folder, ignore_errors=True)
            raise HTTPException(413, "decoded image exceeds pixel limit") from exc
        except HTTPException:
            shutil.rmtree(folder, ignore_errors=True)
            raise
        except (UnidentifiedImageError, OSError, ValueError) as exc:
            shutil.rmtree(folder, ignore_errors=True)
            raise HTTPException(422, "corrupt or unsupported image") from exc
        suffix = {"image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp"}[
            media
        ]
        source = folder / ("original" + suffix)
        os.replace(original, source)
        aid = ident("ar_")
        record = {
            "id": upload_id,
            "filename": Path(file.filename or "image").name,
            "media_type": media,
            "width": width,
            "height": height,
            "bytes": size,
            "sha256": sha256_file(source),
            "path": str(source),
            "thumbnail_path": str(folder / "thumbnail.png"),
            "thumbnail_url": prefix + f"/api/artifacts/{aid}",
        }
        store.insert_json("uploads", upload_id, record)
        with store.connect() as db:
            db.execute(
                "INSERT INTO artifacts VALUES(?,?,?,?,?,?,?,?,?)",
                (
                    aid,
                    "",
                    None,
                    record["thumbnail_path"],
                    "thumbnail.png",
                    "image/png",
                    (folder / "thumbnail.png").stat().st_size,
                    sha256_file(folder / "thumbnail.png"),
                    "thumbnail",
                ),
            )
        return {k: v for k, v in record.items() if not k.endswith("path")}

    @app.post(prefix + "/api/workspaces", status_code=201)
    async def workspace(request: Request):
        await guard(request)
        body = await request.json()
        upload = store.get_json("uploads", str(body.get("upload_id", "")))
        if not upload:
            raise HTTPException(404, "upload not found")
        workspace_id = ident("ws_")
        record = {
            "id": workspace_id,
            "name": str(body.get("name") or upload["filename"]),
            "upload_id": upload["id"],
            "source": {k: v for k, v in upload.items() if not k.endswith("path")},
            "created_at": now(),
            "storage_bytes": upload["bytes"],
        }
        with store.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            if db.execute(
                "SELECT 1 FROM workspaces WHERE json_extract(record,'$.upload_id')=?",
                (upload["id"],),
            ).fetchone():
                raise HTTPException(409, "upload already belongs to a workspace")
            db.execute(
                "INSERT INTO workspaces(id,record) VALUES(?,?)",
                (workspace_id, json.dumps(record)),
            )
            db.execute(
                "UPDATE artifacts SET workspace_id=? WHERE path=?",
                (workspace_id, upload["thumbnail_path"]),
            )
        return record

    @app.get(prefix + "/api/workspaces/{workspace_id}")
    async def get_workspace(workspace_id: str, request: Request):
        await guard(request)
        record = store.get_json("workspaces", workspace_id)
        if not record:
            raise HTTPException(404, "workspace not found")
        return record | {
            "jobs": [x for x in store.jobs(1000) if x["workspace_id"] == workspace_id]
        }

    @app.delete(prefix + "/api/workspaces/{workspace_id}")
    async def delete_workspace(workspace_id: str, request: Request):
        await guard(request)
        body = await request.json()
        workspace_record = store.get_json("workspaces", workspace_id)
        if not workspace_record:
            raise HTTPException(404, "workspace not found")
        if not workspace_id.startswith("ws_") or not workspace_id[3:].isalnum():
            raise HTTPException(404, "workspace not found")
        if body.get("confirmation") != workspace_id:
            raise HTTPException(422, "confirmation must equal workspace ID")
        with store.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            active = db.execute(
                "SELECT 1 FROM jobs WHERE workspace_id=? AND status NOT IN ('ready','failed','stopped') LIMIT 1",
                (workspace_id,),
            ).fetchone()
            if active:
                raise HTTPException(409, "workspace has active work")
            job_ids = [
                row[0]
                for row in db.execute(
                    "SELECT id FROM jobs WHERE workspace_id=?", (workspace_id,)
                )
            ]
            package_ids = [
                row[0]
                for row in db.execute(
                    "SELECT p.id FROM packages p JOIN jobs j ON j.id=p.job_id WHERE j.workspace_id=?",
                    (workspace_id,),
                )
            ]
            db.execute("DELETE FROM artifacts WHERE workspace_id=?", (workspace_id,))
            db.execute(
                "DELETE FROM packages WHERE job_id IN (SELECT id FROM jobs WHERE workspace_id=?)",
                (workspace_id,),
            )
            db.execute(
                "DELETE FROM events WHERE job_id IN (SELECT id FROM jobs WHERE workspace_id=?)",
                (workspace_id,),
            )
            db.execute("DELETE FROM jobs WHERE workspace_id=?", (workspace_id,))
            db.execute("DELETE FROM workspaces WHERE id=?", (workspace_id,))
            db.execute(
                "DELETE FROM uploads WHERE id=?", (workspace_record["upload_id"],)
            )
        for path in (
            settings.data_root / "workspaces" / workspace_id,
            settings.data_root / "uploads" / workspace_record["upload_id"],
            settings.data_root / "publications",
        ):
            if path.name == "publications":
                continue
            safe_managed(settings.data_root, path)
            shutil.rmtree(path, ignore_errors=True)
        for package_id in package_ids:
            for candidate in (settings.data_root / "downloads").glob(
                package_id + "*.zip"
            ):
                safe_managed(settings.data_root, candidate).unlink(missing_ok=True)
        for prior_job_id in job_ids:
            shutil.rmtree(
                safe_managed(
                    settings.data_root,
                    settings.data_root / "publications" / prior_job_id,
                ),
                ignore_errors=True,
            )
        return Response(status_code=204)

    @app.get(prefix + "/api/catalog")
    async def catalog(request: Request):
        await guard(request)
        config = configs.resolved()
        registry = load_registry()
        frames = config.as_dict()["animation_frames"]
        actions = []
        for name in registry.actions:
            stage = registry.stages[registry.action_stages[name]]
            policy = stage.animation.selection
            value = (
                policy.frames or 1
                if policy.method == "single"
                else frames.get(name, policy.frames)
            )
            actions.append(
                {
                    "id": name,
                    "label": stage.animation.label or name.replace("_", " ").title(),
                    "description": stage.animation.description or "",
                    "stage": stage.name,
                    "selection": policy.to_document(),
                    "frame_count": {
                        "value": value,
                        "editable": policy.method != "single",
                        "minimum": 1 if policy.method == "single" else 2,
                    },
                    "conceptual_loop": stage.animation.conceptual_loop,
                    "animated_file": stage.animation.webp_loop is not None,
                    "generation": {
                        **stage.generation.to_document(),
                        "frame_length": stage.generation.frame_length,
                        "effective_duration_seconds": stage.generation.effective_duration_seconds,
                    },
                }
            )
        return {
            "revision": hashlib.sha256(
                json.dumps(registry.provenance(), sort_keys=True).encode()
            ).hexdigest(),
            "actions": actions,
            "poses": registry.list_document()["poses"],
            "capabilities": {
                "directions": ["right", "left", "back", "front"],
                "prompt_styles": ["neutral", "feminine"],
                "split_methods": ["blobs", "quarters"],
                "animation_authoring": False,
            },
        }

    @app.get(prefix + "/api/config")
    async def get_config(request: Request):
        await guard(request)
        return configs.document()

    @app.patch(prefix + "/api/config")
    async def patch_config(request: Request):
        await guard(request)
        body = await request.json()
        try:
            return configs.patch(str(body.get("revision", "")), body.get("changes", []))
        except RuntimeError:
            return error(
                409, "config_conflict", "Configuration changed; reload before saving"
            )
        except (ValueError, TypeError, KeyError) as exc:
            return error(
                422,
                "validation_error",
                str(exc),
                [{"path": ["body", "changes"], "message": str(exc)}],
            )

    @app.post(prefix + "/api/connection-check")
    async def connection(request: Request):
        await guard(request)
        from ..comfy_workflow import ComfyClient

        config = configs.resolved().as_dict()
        client = ComfyClient(config["comfyui_url"])
        try:
            data = client._json("/object_info")
            if not isinstance(data, dict):
                raise ValueError("ComfyUI object_info is not an object")
            from ..staged_workflow import STAGE_ORDER, _configured_stage_graph
            from ..comfy_postprocess import workflow_path
            from ..io_utils import load_json

            graphs = [_configured_stage_graph(name, config) for name in STAGE_ORDER] + [
                load_json(workflow_path(name))
                for name in ("sdpose", "background-removal")
            ]
            required = {
                node.get("class_type")
                for graph in graphs
                for node in graph.values()
                if isinstance(node, dict)
            }
            missing = sorted(str(name) for name in required if name not in data)
            encoded = json.dumps(data)
            models = sorted(
                {
                    value
                    for group in (
                        config.get("workflow_models", {}),
                        config.get("postprocess_workflow_models", {}),
                    )
                    for value in _leaf_strings(group)
                    if value.endswith(".safetensors")
                }
            )
            missing_models = [name for name in models if name not in encoded]
            ok = not missing and not missing_models
            discovered = sorted(
                {
                    value
                    for value in _leaf_strings(data)
                    if value.endswith(".safetensors")
                }
            )
            return {
                "ok": ok,
                "url": config["comfyui_url"],
                "message": (
                    "Connected" if ok else "Required nodes or models are unavailable"
                ),
                "models": models,
                "available_models": discovered,
                "missing_nodes": missing,
                "missing_models": missing_models,
                "node_count": len(data),
            }
        except Exception as exc:
            return {
                "ok": False,
                "url": config["comfyui_url"],
                "message": str(exc),
                "models": [],
            }

    @app.post(prefix + "/api/plans")
    async def plan(request: Request):
        await guard(request)
        body = await request.json()
        ws = store.get_json("workspaces", str(body.get("workspace_id", "")))
        if not ws:
            raise HTTPException(404, "workspace not found")
        upload_record = store.get_json("uploads", ws["upload_id"])
        seed = (
            body.get("seed", {}).get("value")
            if isinstance(body.get("seed"), dict)
            else None
        )
        engine = (
            settings.data_root / "workspaces" / ws["id"] / "generation-sets" / str(seed)
            if seed is not None
            else None
        )
        try:
            return plan_request(
                body,
                configs.resolved(),
                image=Path(upload_record["path"]),
                output=engine,
            )
        except (ValueError, TypeError, KeyError) as exc:
            return error(
                422,
                "validation_error",
                str(exc),
                [{"path": ["body"], "message": str(exc)}],
            )

    @app.post(prefix + "/api/jobs", status_code=202)
    async def create_job(request: Request, idempotency_key: str | None = Header(None)):
        await guard(request)
        if (
            not idempotency_key
            or not 8 <= len(idempotency_key) <= 200
            or not idempotency_key.isascii()
        ):
            raise HTTPException(422, "Idempotency-Key must be 8-200 ASCII characters")
        body = await request.json()
        raw = body.get("request", body)
        ws = store.get_json("workspaces", str(raw.get("workspace_id", "")))
        if not ws:
            raise HTTPException(404, "workspace not found")
        config = configs.resolved()
        try:
            normalized, registry = normalize_request(raw, config, resolve_random=True)
        except (ValueError, TypeError, KeyError) as exc:
            return error(
                422,
                "validation_error",
                str(exc),
                [{"path": ["body", "request"], "message": str(exc)}],
            )
        try:
            job, _ = store.create_job(
                ws["id"],
                normalized,
                config.snapshot(),
                registry.provenance(),
                idempotency_key,
                raw,
                require_workspace=True,
            )
        except ValueError as exc:
            if str(exc) == "idempotency_conflict":
                return error(
                    409,
                    "idempotency_conflict",
                    "Idempotency key was already used for a different request",
                )
            if str(exc) == "workspace_missing":
                return error(
                    404,
                    "workspace_not_found",
                    "Workspace was deleted before the job could be created",
                )
            raise
        return job

    @app.get(prefix + "/api/jobs")
    async def jobs(request: Request, limit: int = 50):
        await guard(request)
        return {"jobs": store.jobs(min(max(limit, 1), 200)), "next": None}

    @app.get(prefix + "/api/jobs/{job_id}")
    async def job(job_id: str, request: Request):
        await guard(request)
        value = store.job(job_id)
        if not value:
            raise HTTPException(404, "job not found")
        return value

    @app.get(prefix + "/api/jobs/{job_id}/previews")
    async def previews(job_id: str, request: Request):
        await guard(request)
        value = job_previews(store, settings.data_root, job_id)
        if value is None:
            raise HTTPException(404, "job not found")
        return value

    @app.get(prefix + "/api/jobs/{job_id}/cycles")
    async def cycles(job_id: str, request: Request):
        await guard(request)
        value = job_cycles(store, settings.data_root, job_id)
        if value is None:
            raise HTTPException(404, "job not found")
        return value

    @app.get(prefix + "/api/cycle-assets/{asset_id}")
    async def cycle_media(asset_id: str, request: Request):
        await guard(request)
        value = cycle_asset(store, settings.data_root, asset_id)
        if value is None:
            raise HTTPException(404, "cycle asset not found")
        return FileResponse(
            value["path"],
            media_type=value["media_type"],
            filename=value["filename"],
            content_disposition_type="inline",
        )

    def validate_idempotency_key(value: str | None) -> str:
        if not value or not 8 <= len(value) <= 200 or not value.isascii():
            raise HTTPException(422, "Idempotency-Key must be 8-200 ASCII characters")
        return value

    def cycle_parent(job_id: str):
        value = store.job(job_id)
        if value is None:
            raise HTTPException(404, "job not found")
        if value["status"] == "recovery_required":
            return None, error(
                409,
                "cycle_unavailable",
                "Cycle work cannot start while recovery is required",
            )
        if value["status"] not in {"ready", "failed", "stopped"}:
            return None, error(
                409,
                "cycle_unavailable",
                "The source job must finish before cycle work can start",
            )
        return value, None

    def create_cycle_child(parent, kind, child_request, key, base_package_id=None):
        try:
            child, _created = store.create_child_job(
                parent["id"],
                kind,
                child_request,
                key,
                base_package_id=base_package_id,
            )
            return child
        except ValueError as exc:
            if str(exc) == "idempotency_conflict":
                return error(
                    409,
                    "idempotency_conflict",
                    "Idempotency key was already used for a different request",
                )
            if str(exc) == "parent_missing":
                return error(404, "job_not_found", "Parent job no longer exists")
            if str(exc) == "parent_not_terminal":
                return error(
                    409,
                    "cycle_unavailable",
                    "The source job must finish before cycle work can start",
                )
            if str(exc) == "workspace_missing":
                return error(404, "workspace_not_found", "Workspace no longer exists")
            raise

    def prior_cycle_submission(
        key: str,
        parent_id: str,
        kind: str,
        base_package_id: str | None,
        child_request: dict[str, Any] | None,
    ):
        with store.connect() as database:
            prior = database.execute(
                "SELECT id FROM jobs WHERE idempotency_key=?",
                (key,),
            ).fetchone()
        if prior is None:
            return None
        value = store.job(prior["id"])
        stored_request = dict(value.get("request") or {})
        stored_request.pop("_cycle_pins", None)
        intended_request = dict(child_request or {})
        intended_request.pop("_cycle_pins", None)
        if (
            value.get("parent_job_id") != parent_id
            or value.get("kind") != kind
            or value.get("base_package_id") != base_package_id
            or (child_request is not None and stored_request != intended_request)
        ):
            return error(
                409,
                "idempotency_conflict",
                "Idempotency key was already used for a different request",
            )
        return store.job(prior["id"])

    def cycle_pins(job_id: str, actions: list[str]) -> dict[str, Any]:
        sources = pinned_action_sources(store, settings.data_root, job_id)
        source_pins = {
            action: {
                "generation_id": sources[action]["generation_id"],
                "sha256": sources[action]["sha256"],
                "stage_id": sources[action]["stage_id"],
            }
            for action in actions
            if action in sources
        }
        inherited = load_cycle_index(store, settings.data_root, job_id, inherit=True)
        groups = inherited[0].get("groups", []) if inherited else []
        analysis_pins = {
            item["action"]: {
                "analysis_id": item.get("analysis_id"),
                "sample_set_id": item.get("sample_set_id"),
                "selected_candidate_id": item.get("selected_candidate_id"),
                "system_candidate_id": item.get("system_candidate_id"),
                "selection_origin": item.get("selection_origin"),
            }
            for item in groups
            if item.get("action") in actions
        }
        return {"sources": source_pins, "analyses": analysis_pins}

    @app.post(prefix + "/api/jobs/{job_id}/cycle-analysis", status_code=202)
    async def create_cycle_analysis(
        job_id: str, request: Request, idempotency_key: str | None = Header(None)
    ):
        await guard(request)
        key = validate_idempotency_key(idempotency_key)
        parent, failure = cycle_parent(job_id)
        if failure is not None:
            return failure
        body = await request.json()
        if not isinstance(body, dict):
            return error(422, "validation_error", "Request body must be an object")
        requested = body.get("actions")
        if requested is not None and (
            not isinstance(requested, list)
            or any(not isinstance(item, str) for item in requested)
        ):
            return error(
                422,
                "validation_error",
                "actions must be a list of animation IDs",
                [
                    {
                        "path": ["body", "actions"],
                        "message": "Expected a list of strings",
                    }
                ],
            )
        base_package_id = parent.get("package_id") or parent.get("base_package_id")
        early_request = None
        if requested is not None:
            early_request = dict(parent["request"])
            early_request.pop("_cycle_selections", None)
            early_request["_cycle_actions"] = list(dict.fromkeys(requested))
        prior = prior_cycle_submission(
            key, job_id, "cycle_analysis", base_package_id, early_request
        )
        if prior is not None:
            return prior
        document = job_cycles(store, settings.data_root, job_id)
        if document is None:
            raise HTTPException(404, "job not found")
        sources = pinned_action_sources(store, settings.data_root, job_id)
        eligible = {
            group["action"]
            for group in document["groups"]
            if group["status"] != "ready" and group["action"] in sources
        }
        if requested is None:
            actions = [
                group["action"]
                for group in document["groups"]
                if group["action"] in eligible
            ]
        else:
            actions = list(dict.fromkeys(requested))
        invalid = [action for action in actions if action not in eligible]
        if not actions or invalid:
            return error(
                409,
                "cycle_unavailable",
                "No requested animation has reusable video evidence",
            )
        child_request = dict(parent["request"])
        child_request.pop("_cycle_selections", None)
        child_request["_cycle_actions"] = actions
        child_request["_cycle_pins"] = cycle_pins(
            job_id, list(parent["request"].get("actions", []))
        )
        active_child = next(
            (
                item
                for item in store.jobs(1000)
                if item.get("parent_job_id") == job_id
                and item.get("kind") == "cycle_analysis"
                and item["status"]
                not in {"ready", "failed", "stopped", "recovery_required"}
            ),
            None,
        )
        if active_child is not None:
            return error(409, "cycle_unavailable", "Cycle analysis is already active")
        return create_cycle_child(
            parent, "cycle_analysis", child_request, key, base_package_id
        )

    @app.post(prefix + "/api/jobs/{job_id}/cycle-revisions", status_code=202)
    async def create_cycle_revision(
        job_id: str, request: Request, idempotency_key: str | None = Header(None)
    ):
        await guard(request)
        key = validate_idempotency_key(idempotency_key)
        parent, failure = cycle_parent(job_id)
        if failure is not None:
            return failure
        body = await request.json()
        if not isinstance(body, dict):
            return error(422, "validation_error", "Request body must be an object")
        selections = body.get("selections")
        requested_base = body.get("base_package_id")
        if not isinstance(selections, dict):
            return error(
                422,
                "validation_error",
                "selections must be an object",
                [{"path": ["body", "selections"], "message": "Expected an object"}],
            )
        early_request = dict(parent["request"])
        early_request.pop("_cycle_actions", None)
        early_request["_cycle_selections"] = selections
        early_base = (
            requested_base or parent.get("package_id") or parent.get("base_package_id")
        )
        prior = prior_cycle_submission(
            key, job_id, "cycle_revision", early_base, early_request
        )
        if prior is not None:
            return prior
        document = job_cycles(store, settings.data_root, job_id)
        if document is None:
            raise HTTPException(404, "job not found")
        groups = document["groups"]
        expected = {group["action"] for group in groups}
        if not document.get("can_revise"):
            return error(
                409, "cycle_unavailable", "Cycle choices are not ready for revision"
            )
        if not groups or set(selections) != expected:
            return error(
                422,
                "validation_error",
                "selections must exactly cover every cycle animation",
                [
                    {
                        "path": ["body", "selections"],
                        "message": "Expected one selection for every cycle animation",
                    }
                ],
            )
        normalized = {}
        for group in groups:
            choice = selections.get(group["action"])
            candidates = {candidate["id"] for candidate in group.get("candidates", [])}
            pinned_count = (
                parent["request"].get("frame_counts", {}).get(group["action"])
            )
            if (
                group["status"] != "ready"
                or group.get("frame_count") != pinned_count
                or not isinstance(choice, dict)
                or not isinstance(choice.get("analysis_id"), str)
                or not isinstance(choice.get("candidate_id"), str)
                or choice.get("analysis_id") != group.get("analysis_id")
                or choice.get("candidate_id") not in candidates
            ):
                return error(
                    409,
                    "cycle_unavailable",
                    f"Cycle selection for {group['action']} is stale or unavailable",
                )
            normalized[group["action"]] = {
                "analysis_id": choice["analysis_id"],
                "candidate_id": choice["candidate_id"],
            }
        allowed_bases = {
            value
            for value in (parent.get("package_id"), parent.get("base_package_id"))
            if value
        }
        if requested_base is not None and (
            not isinstance(requested_base, str) or requested_base not in allowed_bases
        ):
            return error(
                409,
                "cycle_unavailable",
                "Base package does not belong to this job lineage",
            )
        base_package_id = (
            requested_base or parent.get("package_id") or parent.get("base_package_id")
        )
        if (
            base_package_id is not None
            and store.get_json("packages", base_package_id) is None
        ):
            return error(409, "cycle_unavailable", "Base package is unavailable")
        child_request = dict(parent["request"])
        child_request.pop("_cycle_actions", None)
        child_request["_cycle_selections"] = normalized
        child_request["_cycle_pins"] = cycle_pins(
            job_id, list(parent["request"].get("actions", []))
        )
        return create_cycle_child(
            parent, "cycle_revision", child_request, key, base_package_id
        )

    @app.get(prefix + "/api/previews/{preview_id}")
    async def preview_media(preview_id: str, request: Request):
        await guard(request)
        value = resolve_preview(store, settings.data_root, preview_id)
        if value is None:
            raise HTTPException(404, "preview not found")
        return FileResponse(
            value["path"],
            media_type=value["media_type"],
            filename=value["filename"],
            content_disposition_type="inline",
        )

    @app.get(prefix + "/api/jobs/{job_id}/activity")
    async def job_activity(
        job_id: str, request: Request, after: int = 0, limit: int = 100
    ):
        await guard(request)
        job_value = store.job(job_id)
        if job_value is None:
            raise HTTPException(404, "job not found")
        if after < 0 or not 1 <= limit <= 250:
            raise HTTPException(
                422, "after must be nonnegative and limit must be from 1 through 250"
            )
        items = store.activities(job_id, after, limit)
        return {
            "job": job_value,
            "current": store.current_activity(job_id),
            "activities": items,
            "next_cursor": items[-1]["sequence"] if items else after,
        }

    @app.get(prefix + "/api/jobs/{job_id}/events")
    async def events(job_id: str, request: Request, cursor: int = 0):
        await guard(request)
        job_initial = store.job(job_id)
        if not job_initial:
            raise HTTPException(404, "job not found")
        header_cursor = request.headers.get("last-event-id")
        if header_cursor:
            try:
                cursor = max(cursor, int(header_cursor))
            except ValueError:
                raise HTTPException(422, "Last-Event-ID must be an integer")

        async def stream():
            current = cursor
            with store.connect() as db:
                oldest = db.execute(
                    "SELECT MIN(sequence) FROM events WHERE job_id=?", (job_id,)
                ).fetchone()[0]
            if oldest is not None and current < oldest - 1:
                snapshot = {
                    "sequence": oldest - 1,
                    "timestamp": now(),
                    "job": store.job(job_id),
                    "message": "Current state",
                }
                yield f"id: {oldest-1}\nevent: snapshot\ndata: {json.dumps(snapshot)}\n\n"
                current = oldest - 1
            while True:
                if await request.is_disconnected():
                    break
                rows = store.events(job_id, current)
                for item in rows:
                    current = item["sequence"]
                    yield f"id: {current}\nevent: {item.pop('event')}\ndata: {json.dumps(item)}\n\n"
                job_value = store.job(job_id)
                if not job_value or job_value["status"] in {
                    "ready",
                    "failed",
                    "stopped",
                    "recovery_required",
                }:
                    break
                if not rows:
                    yield ": keepalive\n\n"
                await asyncio.sleep(0.5)

        return StreamingResponse(
            stream(),
            media_type="text/event-stream",
            headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
        )

    @app.post(prefix + "/api/jobs/{job_id}/stop", status_code=202)
    async def stop_job(job_id: str, request: Request):
        await guard(request)
        value = store.job(job_id)
        if not value:
            raise HTTPException(404, "job not found")
        if value["status"] == "queued":
            store.update_job(
                job_id,
                status="stopped",
                stop_requested=1,
                error="Canceled while queued",
            )
        elif value["status"] not in {"ready", "failed", "stopped", "recovery_required"}:
            store.update_job(job_id, status="stop_requested", stop_requested=1)
        return store.job(job_id)

    @app.post(prefix + "/api/jobs/{job_id}/resume", status_code=202)
    async def resume(job_id: str, request: Request):
        await guard(request)
        value = store.job(job_id)
        if not value:
            raise HTTPException(404, "job not found")
        if value["status"] == "recovery_required":
            from ..comfy_workflow import ComfyClient
            from ..io_utils import atomic_write_json, load_json

            engine = (
                settings.data_root
                / "workspaces"
                / value["workspace_id"]
                / "generation-sets"
                / value["resolved_seed"]
            )
            journal = engine / "submission-journal.json"
            if journal.is_file():
                document = load_json(journal)
                with store.connect() as db:
                    snapshot = json.loads(
                        db.execute(
                            "SELECT config_snapshot FROM jobs WHERE id=?", (job_id,)
                        ).fetchone()[0]
                    )
                client = ComfyClient(snapshot["config"]["comfyui_url"])
                unresolved = []
                for record in document.get("submissions", {}).values():
                    if record.get("attempted") and not record.get("prompt_id"):
                        found = client.find_prompt_by_client_id(record["client_id"])
                        if found:
                            record.update(status="submitted", prompt_id=found)
                        else:
                            unresolved.append(record["client_id"])
                atomic_write_json(journal, document)
                if unresolved:
                    return error(
                        409,
                        "recovery_required",
                        "Prior submission outcome remains unknown",
                    )
                value["status"] = "failed"
            else:
                return error(
                    409, "recovery_required", "No durable recovery journal is available"
                )
        if value["status"] not in {"failed", "stopped"}:
            raise HTTPException(409, "job is not resumable")
        store.update_job(
            job_id, status="queued", stop_requested=0, error=None, worker_id=None
        )
        return store.job(job_id)

    @app.get(prefix + "/api/packages/{package_id}")
    async def package(package_id: str, request: Request):
        await guard(request)
        value = store.get_json("packages", package_id)
        if not value:
            raise HTTPException(404, "package not found")
        return value

    @app.get(prefix + "/api/artifacts/{artifact_id}")
    async def get_artifact(artifact_id: str, request: Request):
        await guard(request)
        item = artifact(store, artifact_id)
        if not item:
            raise HTTPException(404, "artifact not found")
        path = safe_managed(settings.data_root, item["path"])
        if not path.is_file():
            raise HTTPException(404, "artifact unavailable")
        return FileResponse(
            path, media_type=item["media_type"], filename=item["filename"]
        )

    @app.get(prefix + "/api/packages/{package_id}/download")
    async def download(package_id: str, request: Request, action: str | None = None):
        await guard(request)
        value = store.get_json("packages", package_id)
        if not value:
            raise HTTPException(404, "package not found")
        if action is not None and action not in value.get("action_downloads", {}):
            raise HTTPException(404, "unknown or still-only action")
        suffix = "-" + action if action else ""
        target = settings.data_root / "downloads" / f"{package_id}{suffix}.zip"
        if not target.is_file():
            try:
                zip_file(store, value, target, action)
            except ValueError as exc:
                raise HTTPException(404, str(exc))
        return FileResponse(
            target,
            media_type="application/zip",
            filename=f"sprite-extractor{suffix}.zip" if action else "sprite.zip",
        )

    scheduler = Scheduler(store, settings.data_root, runner=runner)
    app.state.scheduler = scheduler

    @app.on_event("startup")
    async def startup():
        if settings.scheduler:
            scheduler.start()

    @app.on_event("shutdown")
    async def shutdown():
        scheduler.stop()

    static = settings.static_root or Path(__file__).resolve().parents[1] / "web_static"
    static = static.resolve()
    if settings.static_root is not None and not (static / "index.html").is_file():
        raise ValueError("static root must contain index.html")
    if static.is_dir():
        from fastapi.staticfiles import StaticFiles

        assets = static / "assets"
        if assets.is_dir():
            app.mount(prefix + "/assets", StaticFiles(directory=assets), name="assets")

        @app.get(prefix + "/{path:path}", include_in_schema=False)
        async def spa(path: str):
            candidate = (static / path).resolve()
            if static.resolve() in candidate.parents and candidate.is_file():
                return FileResponse(candidate)
            return FileResponse(static / "index.html")

    return app


def main() -> None:
    import argparse
    import uvicorn
    from .settings import WebSettings

    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--data-root")
    parser.add_argument("--config")
    parser.add_argument("--base-path", default=None)
    parser.add_argument("--upload-limit", type=int)
    parser.add_argument("--pixel-limit", type=int)
    parser.add_argument(
        "--no-auth",
        action="store_true",
        help="explicitly allow unauthenticated network access (CSRF protection remains enabled)",
    )
    parser.add_argument(
        "--no-scheduler",
        action="store_true",
        help="serve API/UI without claiming or executing queued jobs",
    )
    parser.add_argument(
        "--static-root",
        help="serve a compiled frontend from this directory",
    )
    args = parser.parse_args()
    settings = WebSettings.from_env()
    if (
        args.data_root
        or args.config
        or args.base_path is not None
        or args.upload_limit
        or args.pixel_limit
        or args.no_auth
        or args.no_scheduler
        or args.static_root
    ):
        from dataclasses import replace

        new_root = (
            Path(args.data_root).resolve() if args.data_root else settings.data_root
        )
        new_config = (
            Path(args.config).resolve()
            if args.config
            else (new_root / "config.yaml" if args.data_root else settings.config_path)
        )
        settings = replace(
            settings,
            data_root=new_root,
            config_path=new_config,
            base_path=(args.base_path or "").rstrip("/"),
            upload_limit=args.upload_limit or settings.upload_limit,
            pixel_limit=args.pixel_limit or settings.pixel_limit,
            no_auth=args.no_auth or settings.no_auth,
            scheduler=False if args.no_scheduler else settings.scheduler,
            static_root=(
                Path(args.static_root).resolve()
                if args.static_root
                else settings.static_root
            ),
        )
    uvicorn.run(create_app(settings), host=args.host, port=args.port)


if __name__ == "__main__":
    main()
