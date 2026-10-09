"""Resolved configuration snapshots shared by CLI and web execution."""

from __future__ import annotations

import copy
from dataclasses import dataclass
from pathlib import Path
from types import MappingProxyType
from typing import Any, Mapping

from .comfy_workflow import (
    ConfigOverrides,
    _load_config_document,
    _load_model_config,
    configured_animation_frame_counts,
    configured_comfyui_url,
    configured_dummy_image_folder,
    configured_generation_timeout,
    configured_pad_top_percent,
    configured_seed,
    configured_sprite_box_height,
    configured_sprite_render_size,
)
from .io_utils import canonical_json, sha256_bytes


def _freeze(value: Any) -> Any:
    if isinstance(value, dict):
        return MappingProxyType({str(k): _freeze(v) for k, v in value.items()})
    if isinstance(value, list):
        return tuple(_freeze(v) for v in value)
    return value


def _thaw(value: Any) -> Any:
    if isinstance(value, Mapping):
        return {str(k): _thaw(v) for k, v in value.items()}
    if isinstance(value, tuple):
        return [_thaw(v) for v in value]
    return copy.deepcopy(value)


@dataclass(frozen=True)
class ResolvedConfig:
    source: str
    revision: str
    _document: Mapping[str, Any]

    def as_dict(self) -> dict[str, Any]:
        return _thaw(self._document)

    def snapshot(self) -> dict[str, Any]:
        return {
            "version": 1,
            "source": self.source,
            "revision": self.revision,
            "config": self.as_dict(),
        }


def resolve_config(paths: ConfigOverrides = None) -> ResolvedConfig:
    source, document = _load_config_document(paths)
    # Exercise every accessor now. Later pipeline calls receive only this mapping.
    configured_comfyui_url(document)
    configured_generation_timeout(document)
    configured_seed(document)
    configured_sprite_box_height(document)
    configured_sprite_render_size(document)
    configured_pad_top_percent(document)
    configured_dummy_image_folder(document)
    configured_animation_frame_counts(document)
    _load_model_config(document)
    from .comfy_postprocess import postprocess_settings
    from .staged_workflow import STAGE_ORDER, _configured_stage_graph

    postprocess_settings(document)
    for stage in STAGE_ORDER:
        _configured_stage_graph(stage, document)
    revision = sha256_bytes(canonical_json(document))
    return ResolvedConfig(str(source), revision, _freeze(document))


def load_snapshot(value: Mapping[str, Any]) -> ResolvedConfig:
    if value.get("version") != 1 or not isinstance(value.get("config"), Mapping):
        raise ValueError("unsupported configuration snapshot")
    resolved = resolve_config(dict(value["config"]))
    if value.get("revision") != resolved.revision:
        raise ValueError("configuration snapshot checksum differs")
    return ResolvedConfig(
        str(value.get("source", "<snapshot>")), resolved.revision, resolved._document
    )
