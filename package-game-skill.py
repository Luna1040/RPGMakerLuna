#!/usr/bin/env python3
"""Build the public game-production skill archive without private credentials."""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import re
import sys
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


REPOSITORY_ROOT = Path(__file__).resolve().parent
DEFAULT_SOURCE = REPOSITORY_ROOT / "game-production-skill"
DEFAULT_OUTPUT = REPOSITORY_ROOT / "releases" / "game-production-skill.zip"
REQUIRED_FILES = (
    "分享说明.md",
    "game-production/SKILL.md",
    "game-production/agents/openai.yaml",
    "game-production/assets/h3-reference-api.json",
    "game-production/assets/selection.example.json",
    "game-production/references/art-production.md",
    "game-production/references/gameplay.md",
    "game-production/references/team-api.md",
    "game-production/references/verification.md",
    "game-production/scripts/comfy_client.py",
    "game-production/scripts/matte_frames.py",
    "game-production/scripts/pack_frames.py",
    "game-production/scripts/test_tools.py",
)
IGNORED_PARTS = {".DS_Store", "__pycache__"}
FORBIDDEN_SUFFIXES = {
    ".ckpt", ".dll", ".env", ".exe", ".onnx", ".part", ".pth", ".pt",
    ".safetensors", ".tmp", ".toml", ".whl", ".zip",
}
SECRET_ASSIGNMENT = re.compile(
    rb"(?i)(?:secret(?:key)?|auth[_-]?token|api[_-]?key|password|passwd|"
    rb"access[_-]?token)\s*[:=]\s*[\"']?[^\s\"'\r\n]{6,}"
)
IPV4 = re.compile(rb"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])")
URL = re.compile(rb"https?://[^\s)\]`\"']+")
ALLOWED_URLS = {
    "http://127.0.0.1:19316",
    "http://127.0.0.1:9316",
    "https://gofrp.org/en/docs/examples/stcp/",
}


def collect_files(source: Path) -> list[Path]:
    if not source.is_dir():
        raise ValueError(f"source directory does not exist: {source}")
    missing = [name for name in REQUIRED_FILES if not (source / name).is_file()]
    if missing:
        raise ValueError("missing required public files: " + ", ".join(missing))
    files = []
    for path in source.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(source)
        if any(part in IGNORED_PARTS for part in relative.parts) or path.suffix == ".pyc":
            continue
        files.append(path)
    return sorted(files, key=lambda item: item.relative_to(source).as_posix())


def audit_public_files(source: Path, files: list[Path]) -> None:
    failures: list[str] = []
    for path in files:
        relative = path.relative_to(source).as_posix()
        lowered_parts = {part.lower() for part in path.relative_to(source).parts}
        if ".team-comfy-private" in lowered_parts or path.suffix.lower() in FORBIDDEN_SUFFIXES:
            failures.append(f"forbidden public-package file: {relative}")
            continue
        data = path.read_bytes()
        if SECRET_ASSIGNMENT.search(data):
            failures.append(f"secret-like assignment detected: {relative}")
        for raw in IPV4.findall(data):
            address = raw.decode("ascii", errors="ignore")
            if not (address.startswith("127.") or address == "0.0.0.0"):
                failures.append(f"non-loopback IPv4 literal detected: {relative}")
                break
        for raw in URL.findall(data):
            url = raw.decode("utf-8", errors="replace")
            if url not in ALLOWED_URLS:
                failures.append(f"unapproved URL detected in {relative}: {url}")
    if failures:
        raise ValueError("public-package audit failed:\n- " + "\n- ".join(failures))


def write_archive(source: Path, output: Path, files: list[Path]) -> str:
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".part")
    if temporary.exists():
        temporary.unlink()
    try:
        with ZipFile(temporary, "w", ZIP_DEFLATED, compresslevel=9) as archive:
            for path in files:
                relative = path.relative_to(source).as_posix()
                archive_name = "INSTALL.md" if relative == "分享说明.md" else relative
                info = ZipInfo(archive_name, date_time=(2026, 1, 1, 0, 0, 0))
                info.compress_type = ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                info.flag_bits |= 0x800
                archive.writestr(info, path.read_bytes(), compress_type=ZIP_DEFLATED, compresslevel=9)
        temporary.replace(output)
    finally:
        if temporary.exists():
            temporary.unlink()
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    checksum = output.with_suffix(".sha256.txt")
    checksum.write_text(f"{digest}  {output.name}\n", encoding="utf-8")
    return digest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    source = args.source.expanduser().resolve()
    output = args.output.expanduser().resolve()
    files = collect_files(source)
    audit_public_files(source, files)
    print(f"Public audit passed: {len(files)} files; no credentials or external endpoints detected.")
    if args.check_only:
        return 0
    digest = write_archive(source, output, files)
    print(f"Created: {output}")
    print(f"SHA-256: {digest}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
