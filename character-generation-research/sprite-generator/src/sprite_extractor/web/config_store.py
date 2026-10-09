from __future__ import annotations
import copy, os, shutil
from pathlib import Path
from typing import Any
import yaml
from ..comfy_workflow import _deep_merge, default_workflow_config_path
from ..execution_lock import output_tree_lock
from ..io_utils import atomic_write_bytes, sha256_bytes
from ..runtime_config import resolve_config, ResolvedConfig

FIELDS = {
    ("comfyui_url",): (
        "ComfyUI address",
        "string",
        None,
        None,
        "URL resolved by the backend server",
    ),
    ("generation_timeout",): ("Generation timeout", "number", 1, None, "seconds"),
    ("seed",): ("Default seed", "seed", -1, 9223372036854775807, "-1 selects random"),
    ("sprite_box_height",): ("Sprite size", "integer", 1, None, "pixels"),
    ("sprite_render_width",): (
        "Generation width",
        "integer",
        1,
        None,
        "pixels per view",
    ),
    ("sprite_render_height",): (
        "Generation height",
        "integer",
        1,
        None,
        "pixels per view",
    ),
    ("pad_top_percent",): ("Top padding", "number", 0, None, "percent"),
    ("dummy_image_folder",): (
        "Dummy image folder",
        "string",
        None,
        None,
        "Folder containing 1-right.png, 2-left.png, 3-back.png, and 4-front.png",
    ),
    ("postprocess", "sdpose_batch_size"): (
        "SDPose batch size",
        "integer",
        1,
        None,
        "images",
    ),
}


def _at(doc, path):
    for key in path:
        doc = doc[key]
    return doc


def _set(doc, path, value, reset=False):
    node = doc
    for key in path[:-1]:
        node = node.setdefault(key, {})
    if reset:
        node.pop(path[-1], None)
    else:
        node[path[-1]] = value


class ConfigStore:
    def __init__(self, path: Path):
        self.path = path.resolve()

    def override(self) -> dict[str, Any]:
        if not self.path.is_file():
            return {}
        value = yaml.safe_load(self.path.read_text())
        if not isinstance(value, dict):
            raise ValueError("configuration must contain a mapping")
        return value

    def resolved(self) -> ResolvedConfig:
        default = yaml.safe_load(default_workflow_config_path().read_text())
        return resolve_config(_deep_merge(default, self.override()))

    def revision(self) -> str:
        return sha256_bytes(self.path.read_bytes() if self.path.is_file() else b"")

    def document(self) -> dict[str, Any]:
        override = self.override()
        resolved = self.resolved().as_dict()
        defaults = yaml.safe_load(default_workflow_config_path().read_text())
        fields = []
        all_fields = list(FIELDS)
        for group in (
            "animation_frames",
            "workflow_models",
            "postprocess_workflow_models",
        ):

            def walk(value, prefix):
                for k, v in value.items():
                    (
                        walk(v, prefix + (str(k),))
                        if isinstance(v, dict)
                        else all_fields.append(prefix + (str(k),))
                    )

            walk(resolved.get(group, {}), (group,))
        for path in all_fields:
            meta = FIELDS.get(
                path,
                (
                    path[-1].replace("_", " ").title(),
                    "model" if "models" in path[0] else "integer",
                    None,
                    None,
                    "",
                ),
            )
            try:
                value = _at(resolved, path)
            except KeyError:
                continue
            try:
                default = _at(defaults, path)
            except KeyError:
                default = None
            try:
                _at(override, path)
                overridden = True
            except KeyError:
                overridden = False
            if path == ("seed",):
                value = str(value)
                default = str(default)
            fields.append(
                {
                    "path": list(path),
                    "label": meta[0],
                    "kind": meta[1],
                    "value": value,
                    "default": default,
                    "overridden": overridden,
                    "required": True,
                    "minimum": meta[2],
                    "maximum": meta[3],
                    "unit": (
                        meta[4]
                        if meta[4] in {"seconds", "pixels", "percent", "images"}
                        else None
                    ),
                    "help": meta[4],
                }
            )
        return {"revision": self.revision(), "path": self.path.name, "fields": fields}

    def patch(self, revision: str, changes: list[dict[str, Any]]) -> dict[str, Any]:
        with output_tree_lock(str(self.path) + ".config"):
            if revision != self.revision():
                raise RuntimeError("config_conflict")
            doc = self.override()
            for change in changes:
                path = tuple(change.get("path", ()))
                if path not in FIELDS and not path[:1] in {
                    ("animation_frames",),
                    ("workflow_models",),
                    ("postprocess_workflow_models",),
                }:
                    raise ValueError(f"setting {'.'.join(path)} is not editable")
                value = change.get("value")
                if path == ("seed",) and isinstance(value, str):
                    try:
                        value = int(value)
                    except ValueError as exc:
                        raise ValueError("seed must be a decimal string") from exc
                _set(doc, path, value, bool(change.get("reset")))
            default = yaml.safe_load(default_workflow_config_path().read_text())
            resolve_config(_deep_merge(default, doc))
            if self.path.is_file():
                shutil.copyfile(
                    self.path, self.path.with_suffix(self.path.suffix + ".bak")
                )
            atomic_write_bytes(self.path, yaml.safe_dump(doc, sort_keys=False).encode())
            return self.document()
