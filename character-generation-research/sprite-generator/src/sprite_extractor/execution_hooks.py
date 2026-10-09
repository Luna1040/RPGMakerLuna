"""Optional context-local progress and cooperative-stop callbacks."""

from __future__ import annotations

import contextvars
from contextlib import contextmanager

_progress = contextvars.ContextVar("sprite_progress", default=None)
_stop = contextvars.ContextVar("sprite_stop", default=None)
_activity = contextvars.ContextVar("sprite_activity", default=None)
_activity_stage = contextvars.ContextVar("sprite_activity_stage", default=None)
_activity_operation = contextvars.ContextVar(
    "sprite_activity_operation", default="comfy"
)
_last_activity = contextvars.ContextVar("sprite_last_activity", default=None)


@contextmanager
def execution_hooks(progress=None, should_stop=None, activity=None):
    progress_token = _progress.set(progress)
    stop_token = _stop.set(should_stop)
    activity_token = _activity.set(activity)
    stage_token = _activity_stage.set(None)
    operation_token = _activity_operation.set("comfy")
    last_token = _last_activity.set(None)
    try:
        yield
    finally:
        _last_activity.reset(last_token)
        _activity_stage.reset(stage_token)
        _activity_operation.reset(operation_token)
        _activity.reset(activity_token)
        _progress.reset(progress_token)
        _stop.reset(stop_token)


def set_activity_stage(stage_id):
    """Set the catalog stage associated with subsequent ComfyUI operations."""
    _activity_stage.set(stage_id)


def set_activity_operation(operation):
    _activity_operation.set(operation)


def graph_operation(graph):
    classes = {
        node.get("class_type") for node in graph.values() if isinstance(node, dict)
    }
    if "SDPoseKeypointExtractor" in classes:
        return "sdpose"
    if "RemoveBackground" in classes:
        return "background_removal"
    return "generation"


def report_activity(state, *, operation=None, prompt_id=None, message=None, error=None):
    """Report a sanitized ComfyUI lifecycle transition to the durable job log."""
    callback = _activity.get()
    if callback is None:
        return
    payload = {
        "state": state,
        "operation": operation or _activity_operation.get(),
        "stage_id": _activity_stage.get(),
        "prompt_id": prompt_id,
        "message": message,
        "error": error,
    }
    identity = (state, payload["operation"], payload["stage_id"], prompt_id, message)
    if identity == _last_activity.get():
        return
    _last_activity.set(identity)
    try:
        callback(payload)
    except Exception:
        # Activity is an observational projection. It must never change whether
        # durable inference is submitted, recovered, or completed.
        return


def activity_enabled():
    return _activity.get() is not None


def before_submission(graph):
    """Apply batch hooks only where stopping cannot corrupt generation intent."""
    classes = {
        node.get("class_type") for node in graph.values() if isinstance(node, dict)
    }
    postprocess = bool(classes & {"SDPoseKeypointExtractor", "RemoveBackground"})
    stop = _stop.get()
    if postprocess and stop and stop():
        from .application import CooperativeStop

        raise CooperativeStop("stopped before the next postprocess batch")

    progress = _progress.get()
    if not progress:
        return
    if "SDPoseKeypointExtractor" in classes:
        progress("extracting", {"operation": "sdpose_batch"})
    elif "RemoveBackground" in classes:
        progress("removing_backgrounds", {"operation": "background_batch"})
