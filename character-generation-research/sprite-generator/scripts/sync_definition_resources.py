#!/usr/bin/env python3
"""Synchronize portable definition resources into the Python package."""
from __future__ import annotations

import filecmp
import shutil
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "src" / "sprite_extractor"
FILES = (Path("animation-definitions.yaml"), Path("config.default.yaml"))
DIRECTORIES = (Path("prompts"), Path("workflows/templates"))


def _pairs():
    for relative in FILES:
        yield ROOT / relative, PACKAGE / relative
    for directory in DIRECTORIES:
        for source in sorted((ROOT / directory).glob("*")):
            if source.is_file():
                yield source, PACKAGE / source.relative_to(ROOT)


def main() -> int:
    check = "--check" in sys.argv[1:]
    mismatches = []
    for source, destination in _pairs():
        if not destination.is_file() or not filecmp.cmp(source, destination, shallow=False):
            mismatches.append(str(destination.relative_to(ROOT)))
            if not check:
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, destination)
    if mismatches:
        if check:
            print("definition resources are out of sync: " + ", ".join(mismatches), file=sys.stderr)
            return 1
        print("synchronized: " + ", ".join(mismatches))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
