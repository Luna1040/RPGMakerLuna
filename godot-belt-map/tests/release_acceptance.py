#!/usr/bin/env python3
"""Verify a Godot Web release and emit a machine-readable B-14 report.

The gate intentionally uses only Python's standard library. It checks the
export policy, required artifacts, binary signatures, hashes, accidental test
or credential leakage, optional HTTP serving, and an optional Godot PCK boot.
It never prints or stores the configured provider credential.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from typing import Iterable, Mapping, Optional
from urllib.error import URLError
from urllib.parse import urljoin
from urllib.request import Request, urlopen


PROJECT_ROOT = Path(__file__).resolve().parent.parent
REPO_ROOT = PROJECT_ROOT.parent
DEFAULT_WEB_ROOT = REPO_ROOT / "releases" / "knight-web"
REQUIRED_ARTIFACTS = {
    "game.html": 1024,
    "game.js": 100_000,
    "game.pck": 1_000_000,
    "game.wasm": 1_000_000,
}
REQUIRED_EXCLUDES = (
    "captures/*",
    "tests/*",
    "test-results/*",
    "*.log",
    "*_test.gd",
    "*_review.gd",
)
FORBIDDEN_PCK_MARKERS = (
    b"res://tests/",
    b"res://captures/",
    b"res://test-results/",
    b"RPG_AGENT_API_KEY=",
)
KEY_PATTERN = re.compile(rb"(?:sk|key|token)-[A-Za-z0-9_-]{20,}", re.IGNORECASE)
ENGINE_ERROR_PATTERN = re.compile(r"^\s*(?:SCRIPT ERROR:|ERROR:|FATAL:)", re.MULTILINE)


def check(name: str, ok: bool, detail: str, **evidence: object) -> dict:
    row = {"name": name, "status": "pass" if ok else "fail", "detail": detail}
    row.update(evidence)
    return row


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def contains_bytes(path: Path, needles: Iterable[bytes]) -> list[str]:
    requested = [needle for needle in needles if needle]
    if not requested:
        return []
    overlap = max(map(len, requested)) - 1
    found: set[bytes] = set()
    tail = b""
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            haystack = tail + chunk
            for needle in requested:
                if needle in haystack:
                    found.add(needle)
            tail = haystack[-overlap:] if overlap > 0 else b""
    # Only safe, hard-coded labels are returned. Provider credentials are
    # represented by the caller as the neutral label "configured_secret".
    return [needle.decode("utf-8", "replace") for needle in requested if needle in found]


def inspect_export_policy(project_root: Path) -> list[dict]:
    preset = project_root / "export_presets.cfg"
    if not preset.is_file():
        return [check("export_policy", False, "export_presets.cfg is missing")]
    text = preset.read_text(encoding="utf-8")
    missing = [pattern for pattern in REQUIRED_EXCLUDES if pattern not in text]
    release_template = re.search(r'^custom_template/release="([^"]+)"', text, re.MULTILINE)
    ok = not missing and release_template is not None and "web_nothreads_release.zip" in release_template.group(1)
    return [check(
        "export_policy",
        ok,
        "test/capture/log sources are excluded and the no-threads release template is pinned" if ok
        else "export policy is incomplete",
        missing_excludes=missing,
        release_template_configured=release_template is not None,
    )]


def inspect_artifacts(web_root: Path, environment: Optional[Mapping[str, str]] = None) -> tuple[list[dict], list[dict]]:
    results: list[dict] = []
    manifest: list[dict] = []
    environment = environment if environment is not None else os.environ
    for name, minimum_size in REQUIRED_ARTIFACTS.items():
        path = web_root / name
        size = path.stat().st_size if path.is_file() else 0
        ok = path.is_file() and size >= minimum_size
        results.append(check(name + "_present", ok, f"{size} bytes", minimum_bytes=minimum_size))
        if path.is_file():
            manifest.append({"name": name, "bytes": size, "sha256": sha256_file(path)})
    if any(row["status"] == "fail" for row in results):
        return results, manifest

    html = (web_root / "game.html").read_bytes()
    results.append(check(
        "html_bootstrap",
        b'<canvas id="canvas">' in html and b"new Engine(GODOT_CONFIG)" in html and b"GODOT_THREADS_ENABLED = false" in html,
        "canvas and no-threads Godot bootstrap are present",
    ))
    with (web_root / "game.pck").open("rb") as stream:
        pck_header = stream.read(4)
    with (web_root / "game.wasm").open("rb") as stream:
        wasm_header = stream.read(4)
    results.append(check("pck_signature", pck_header == b"GDPC", "Godot pack signature"))
    results.append(check("wasm_signature", wasm_header == b"\x00asm", "WebAssembly signature"))

    forbidden_files = []
    for path in web_root.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(web_root).as_posix().lower()
        if any(part in {"tests", "captures", "test-results", "__pycache__"} for part in Path(relative).parts):
            forbidden_files.append(relative)
        if path.name.startswith(".env") or path.suffix.lower() in {".gd", ".tscn", ".log", ".py"}:
            forbidden_files.append(relative)
    results.append(check(
        "distribution_surface",
        not forbidden_files,
        "no tests, captures, source scripts, logs, or environment files are adjacent to the release",
        forbidden_files=sorted(set(forbidden_files)),
    ))

    pck_markers = contains_bytes(web_root / "game.pck", FORBIDDEN_PCK_MARKERS)
    results.append(check(
        "packed_development_artifacts",
        not pck_markers,
        "no known test, capture, report, or credential-assignment marker is embedded in the PCK",
        matched_markers=pck_markers,
    ))

    text_payload = b"".join(
        path.read_bytes()
        for path in web_root.iterdir()
        if path.is_file() and path.suffix.lower() in {".html", ".js", ".txt", ".json"}
    )
    generic_key = KEY_PATTERN.search(text_payload) is not None
    configured = environment.get("RPG_AGENT_API_KEY", "")
    configured_leaked = False
    if len(configured) >= 8:
        secret = configured.encode("utf-8")
        configured_leaked = secret in text_payload or bool(contains_bytes(web_root / "game.pck", [secret]))
    results.append(check(
        "credential_isolation",
        not generic_key and not configured_leaked,
        "no provider credential pattern or configured session secret is embedded",
        generic_key_pattern_found=generic_key,
        configured_secret_found=configured_leaked,
    ))
    return results, manifest


def inspect_http(base_url: str, web_root: Path) -> list[dict]:
    results = []
    base = base_url.rstrip("/") + "/"
    try:
        with urlopen(urljoin(base, "game.html"), timeout=10) as response:
            payload = response.read(16_384)
            html_ok = response.status == 200 and b'<canvas id="canvas">' in payload
            results.append(check("http_game_html", html_ok, f"HTTP {response.status}", content_type=response.headers.get_content_type()))
        for name in ("game.pck", "game.wasm"):
            request = Request(urljoin(base, name), method="HEAD")
            with urlopen(request, timeout=10) as response:
                actual = int(response.headers.get("Content-Length", "0"))
                expected = (web_root / name).stat().st_size
                results.append(check(
                    "http_" + name.replace(".", "_"),
                    response.status == 200 and actual == expected,
                    f"HTTP {response.status}; {actual} bytes",
                    expected_bytes=expected,
                    content_type=response.headers.get_content_type(),
                ))
    except (OSError, URLError, ValueError) as error:
        results.append(check("http_serving", False, f"HTTP verification failed: {error}"))
    return results


def inspect_pck_boot(godot: Path, pck: Path) -> list[dict]:
    command = [str(godot), "--headless", "--main-pack", str(pck), "--quit-after", "30"]
    try:
        completed = subprocess.run(
            command,
            cwd=str(pck.parent),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=30,
            check=False,
        )
        engine_errors = [line.strip() for line in completed.stdout.splitlines() if ENGINE_ERROR_PATTERN.search(line)]
        ok = completed.returncode == 0 and not engine_errors
        return [check(
            "godot_pck_boot",
            ok,
            "exported pack booted without engine/script errors" if ok else "exported pack boot failed",
            returncode=completed.returncode,
            error_lines=engine_errors[:12],
        )]
    except (OSError, subprocess.TimeoutExpired) as error:
        return [check("godot_pck_boot", False, f"could not complete PCK boot: {error}")]


def build_report(
    project_root: Path,
    web_root: Path,
    *,
    environment: Optional[Mapping[str, str]] = None,
    base_url: Optional[str] = None,
    godot: Optional[Path] = None,
) -> dict:
    results = inspect_export_policy(project_root)
    artifact_results, manifest = inspect_artifacts(web_root, environment)
    results.extend(artifact_results)
    if base_url:
        results.extend(inspect_http(base_url, web_root))
    if godot:
        results.extend(inspect_pck_boot(godot, web_root / "game.pck"))
    failed = sum(row["status"] == "fail" for row in results)
    return {
        "schema_version": "release-acceptance/1",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "status": "pass" if failed == 0 else "fail",
        "project_root": str(project_root.resolve()),
        "web_root": str(web_root.resolve()),
        "summary": {"passed": len(results) - failed, "failed": failed},
        "results": results,
        "artifacts": manifest,
    }


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=PROJECT_ROOT)
    parser.add_argument("--web-root", type=Path, default=DEFAULT_WEB_ROOT)
    parser.add_argument("--url", help="Optional served base URL, e.g. http://127.0.0.1:8765/")
    parser.add_argument("--godot", type=Path, help="Optional Godot executable for an exported PCK boot smoke")
    parser.add_argument("--output", type=Path, help="Write the JSON report to this path")
    args = parser.parse_args(argv)
    if args.godot and not args.godot.is_file():
        parser.error(f"Godot executable does not exist: {args.godot}")
    report = build_report(args.project_root, args.web_root, base_url=args.url, godot=args.godot)
    for row in report["results"]:
        print(f"[{row['status'].upper():4}] {row['name']:<32} {row['detail']}")
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"Report: {args.output.resolve()}")
    print(f"{report['status'].upper()}: {report['summary']['passed']} passed, {report['summary']['failed']} failed.")
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
