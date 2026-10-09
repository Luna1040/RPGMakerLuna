"""Prevent contract tests from accidentally contacting a live ComfyUI server."""
import urllib.request

import pytest


@pytest.fixture(autouse=True)
def block_network_transport(monkeypatch):
    def blocked(*_args, **_kwargs):
        raise AssertionError("test attempted an unmocked HTTP request")

    monkeypatch.setattr(urllib.request, "urlopen", blocked)
