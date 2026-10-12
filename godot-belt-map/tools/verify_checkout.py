#!/usr/bin/env python3
"""Verify that a cloned RPGMakerLuna Godot project is complete and editable.

The check uses only Python's standard library. It verifies required entry files,
tracked-file presence, unresolved Git LFS pointers, JSON syntax, and the configured
main scene without changing the checkout.
"""
from __future__ import annotations

import json
from pathlib import Path
import re
import subprocess
import sys


PROJECT_ROOT = Path(__file__).resolve().parent.parent
REPOSITORY_ROOT = PROJECT_ROOT.parent
PROJECT_PREFIX = PROJECT_ROOT.relative_to(REPOSITORY_ROOT).as_posix() + "/"
LFS_POINTER_PREFIX = b"version https://git-lfs.github.com/spec/v1"
REQUIRED_PATHS = (
    "project.godot",
    "stage.tscn",
    "stage.gd",
    "map-contract.json",
    "assets/fonts/NotoSansSC-subset.ttf",
    "content/base/npc_asset_catalog.json",
    "content/schemas/agent-task.schema.json",
    "systems/agent/authoring_orchestrator.gd",
    "systems/content/content_registry.gd",
    "tests/run_tests.py",
)


def tracked_project_files() -> tuple[list[Path], str | None]:
    try:
        result = subprocess.run(
            ["git", "-C", str(REPOSITORY_ROOT), "ls-files", "-z", "--", PROJECT_PREFIX],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        return [], f"Git tracked-file inventory unavailable: {error}"
    names = [name for name in result.stdout.decode("utf-8", errors="surrogateescape").split("\0") if name]
    return [REPOSITORY_ROOT / name for name in names], None


def inspect_project() -> list[str]:
    errors: list[str] = []
    warnings: list[str] = []

    for relative in REQUIRED_PATHS:
        path = PROJECT_ROOT / relative
        if not path.is_file():
            errors.append(f"missing required file: {relative}")

    tracked, inventory_warning = tracked_project_files()
    if inventory_warning:
        warnings.append(inventory_warning)
        tracked = [path for path in PROJECT_ROOT.rglob("*") if path.is_file() and ".godot" not in path.parts]
    if not tracked:
        errors.append("no Godot project files were found")

    missing_tracked: list[str] = []
    pointers: list[str] = []
    for path in tracked:
        relative = path.relative_to(REPOSITORY_ROOT).as_posix()
        if not path.is_file():
            missing_tracked.append(relative)
            continue
        try:
            with path.open("rb") as stream:
                if stream.read(len(LFS_POINTER_PREFIX)) == LFS_POINTER_PREFIX:
                    pointers.append(relative)
        except OSError as error:
            errors.append(f"cannot read {relative}: {error}")

    if missing_tracked:
        preview = ", ".join(missing_tracked[:8])
        errors.append(f"{len(missing_tracked)} tracked file(s) are missing: {preview}")
    if pointers:
        preview = ", ".join(pointers[:8])
        errors.append(
            f"{len(pointers)} Git LFS object(s) are still pointers: {preview}. "
            'Run git lfs pull --include="godot-belt-map/**".'
        )

    for path in sorted(PROJECT_ROOT.rglob("*.json")):
        if ".godot" in path.parts or "test-results" in path.parts:
            continue
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            errors.append(f"invalid JSON {path.relative_to(PROJECT_ROOT).as_posix()}: {error}")

    project_file = PROJECT_ROOT / "project.godot"
    if project_file.is_file():
        try:
            project_text = project_file.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as error:
            errors.append(f"cannot read project.godot: {error}")
        else:
            match = re.search(r'^run/main_scene="res://([^"]+)"$', project_text, re.MULTILINE)
            if not match:
                errors.append("project.godot does not define application/run/main_scene")
            elif not (PROJECT_ROOT / match.group(1)).is_file():
                errors.append(f"configured main scene is missing: {match.group(1)}")
            if 'config/name="Knight - 2.5D Courtyard"' not in project_text:
                warnings.append("project display name differs from the expected main project")

    print(f"Project: {PROJECT_ROOT}")
    print(f"Files inspected: {len(tracked)}")
    print(f"JSON documents checked: {sum(1 for p in PROJECT_ROOT.rglob('*.json') if '.godot' not in p.parts and 'test-results' not in p.parts)}")
    for warning in warnings:
        print(f"WARN: {warning}")
    if errors:
        for error in errors:
            print(f"FAIL: {error}")
        return errors
    print("PASS: Godot checkout is complete and contains no unresolved LFS pointers.")
    return []


if __name__ == "__main__":
    raise SystemExit(1 if inspect_project() else 0)
