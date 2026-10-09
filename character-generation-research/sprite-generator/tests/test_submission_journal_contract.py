"""Protocol-level regression coverage for durable Comfy submissions.

These tests use the real HTTP client and journal, with its transport boundary
stubbed.  They never contact a Comfy server.
"""

from __future__ import annotations

import io
import json
import urllib.error

import pytest

from sprite_extractor.comfy_workflow import ComfyAPIError, ComfyClient, ComfyPromptRejected
from sprite_extractor.execution_hooks import execution_hooks
from sprite_extractor.submission_journal import SubmissionRecoveryRequired, cached_upload, use_submission_journal


def _journal(path):
    return json.loads(path.read_text())


def test_http_400_node_errors_is_retryable_rejection(monkeypatch, tmp_path):
    journal = tmp_path / "journal.json"

    def rejected(*_args, **_kwargs):
        raise urllib.error.HTTPError("http://test/prompt", 400, "bad", {}, io.BytesIO(b'{"node_errors":{"3":"bad"}}'))

    monkeypatch.setattr("urllib.request.urlopen", rejected)
    with use_submission_journal(journal), pytest.raises(ComfyPromptRejected):
        ComfyClient("http://127.0.0.1:8188").submit({"3": {"class_type": "KSampler"}})
    record = next(iter(_journal(journal)["submissions"].values()))
    assert record["status"] == "rejected"
    assert record["attempted"] is False


def test_prompt_id_is_accepted_even_when_response_also_has_node_errors(monkeypatch, tmp_path):
    monkeypatch.setattr(ComfyClient, "_json", lambda *_args: {"prompt_id": "prompt-ok", "node_errors": {"old": "ignored"}})
    with use_submission_journal(tmp_path / "journal.json"):
        assert ComfyClient("http://127.0.0.1:8188").submit({"3": {"class_type": "KSampler"}}) == "prompt-ok"


def test_missing_prompt_id_becomes_unknown_and_is_never_resubmitted(monkeypatch, tmp_path):
    journal = tmp_path / "journal.json"
    calls: list[str] = []

    def malformed(_self, path, *_args):
        calls.append(path)
        return {"accepted": True}

    monkeypatch.setattr(ComfyClient, "_json", malformed)
    client = ComfyClient("http://127.0.0.1:8188")
    graph = {"3": {"class_type": "KSampler"}}
    with use_submission_journal(journal), pytest.raises(ComfyAPIError, match="unknown"):
        client.submit(graph)
    with use_submission_journal(journal), pytest.raises(SubmissionRecoveryRequired):
        client.submit(graph)
    assert calls == ["/prompt", "/queue", "/history?max_items=1000"]
    assert next(iter(_journal(journal)["submissions"].values()))["status"] == "submission_unknown"


def test_upload_cache_is_replayed_only_for_the_same_server(monkeypatch, tmp_path):
    source = tmp_path / "source.png"
    source.write_bytes(b"not an image; upload transport only")
    calls: list[str] = []

    def upload(self, path, **_kwargs):
        calls.append(self.base_url + path)
        return b'{"name":"remote.png","subfolder":"input","type":"input"}'

    monkeypatch.setattr(ComfyClient, "_request", upload)
    journal = tmp_path / "journal.json"
    with use_submission_journal(journal):
        assert ComfyClient("http://127.0.0.1:8188").upload_image(source)["name"] == "remote.png"
        ComfyClient("http://127.0.0.1:8188").upload_image(source)
        ComfyClient("http://127.0.0.1:8189").upload_image(source)
        assert cached_upload(__import__("hashlib").sha256(source.read_bytes()).hexdigest(), "http://127.0.0.1:8188")
    assert len(calls) == 2
    assert calls[0].startswith("http://127.0.0.1:8188") and calls[1].startswith("http://127.0.0.1:8189")


def test_postprocess_stop_blocks_submission_but_main_generation_is_submitted(monkeypatch):
    submitted: list[dict] = []
    monkeypatch.setattr(ComfyClient, "_json", lambda _self, _path, payload=None: submitted.append(payload) or {"prompt_id": "ok"})
    client = ComfyClient("http://127.0.0.1:8188")
    main = {"3": {"class_type": "KSampler"}}
    with execution_hooks(should_stop=lambda: True):
        assert client.submit(main) == "ok"
        from sprite_extractor.application import CooperativeStop
        with pytest.raises(CooperativeStop):
            client.submit({"3": {"class_type": "RemoveBackground"}})
    assert len(submitted) == 1
