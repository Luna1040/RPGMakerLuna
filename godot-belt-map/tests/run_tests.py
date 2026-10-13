#!/usr/bin/env python3
"""Run the Godot regression suites on Windows/macOS/Linux using only Python's stdlib.

Examples:
  python tests/run_tests.py --godot /absolute/path/to/godot --suite all
  GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot python3 tests/run_tests.py
  python tests/run_tests.py --suite core --skip-import

Godot sometimes returns zero after a script/assertion error. A test passes only if
the process exits successfully, prints its explicit PASS marker, and has no engine
or script errors. Logs and a machine-readable report are kept for every run.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from typing import Optional

PROJECT_ROOT = Path(__file__).resolve().parent.parent
ERROR_PATTERN = re.compile(
    r"^\s*(?:SCRIPT ERROR:|ERROR:|FATAL:)|"
    r"\bAssertion\s+(?:failed|failure)\b|"
    r"^\s*(?:FAIL|FAILED|FAILURE)\b|"
    r"\b(?:[A-Z0-9_]*_TEST|TEST)\s+(?:FAIL|FAILED)\b",
    re.IGNORECASE | re.MULTILINE,
)


@dataclass(frozen=True)
class TestSpec:
    name: str
    suite: str
    arguments: tuple[str, ...]
    pass_pattern: str


def script(name: str, path: str, marker: str, suite: str = "gameplay", *, foundations: bool = False) -> TestSpec:
    arguments = ("--script", "res://" + path)
    if foundations:
        arguments += ("--", "--foundations")
    return TestSpec(name, suite, arguments, re.escape(marker) + r"\b")


TESTS = (
    script("journey", "tests/journey_test.gd", "JOURNEY_TEST PASS", foundations=True),
    script("roster_atlas", "tests/roster_atlas_test.gd", "ROSTER_ATLAS_TEST PASS", "core"),
    script("roster_animation", "tests/roster_animation_test.gd", "ROSTER_ANIMATION_TEST PASS", "core"),
    script("core_foundations", "tests/core_foundations_test.gd", "CORE_FOUNDATIONS_TEST PASS", "core"),
    script("core_talents", "tests/core_talents_test.gd", "CORE_TALENTS_TEST PASS", "core"),
    script("core_runtime_validation", "tests/core_runtime_validation_test.gd", "CORE_RUNTIME_VALIDATION_TEST PASS", "core"),
    script("content_patch_foundation", "tests/content_patch_foundation_test.gd", "CONTENT_PATCH_FOUNDATION_TEST PASS", "core"),
    script("content_draft_pipeline", "tests/content_draft_pipeline_test.gd", "CONTENT_DRAFT_PIPELINE_TEST PASS", "core"),
    script("campaign_import_pipeline", "tests/campaign_import_pipeline_test.gd", "CAMPAIGN_IMPORT_PIPELINE_TEST PASS", "core"),
    script("campaign_session_pipeline", "tests/campaign_session_pipeline_test.gd", "CAMPAIGN_SESSION_PIPELINE_TEST PASS", "core", foundations=True),
    script("campaign_manager_ui", "tests/campaign_manager_ui_test.gd", "CAMPAIGN_MANAGER_UI_TEST PASS", "core", foundations=True),
    script("authoring_orchestrator", "tests/authoring_orchestrator_test.gd", "AUTHORING_ORCHESTRATOR_TEST PASS", "core", foundations=True),
    script("agent_transport_service", "tests/agent_transport_service_test.gd", "AGENT_TRANSPORT_SERVICE_TEST PASS", "core", foundations=True),
    script("authoring_persistence_service", "tests/authoring_persistence_service_test.gd", "AUTHORING_PERSISTENCE_SERVICE_TEST PASS", "core", foundations=True),
    script("agent_provider_acceptance", "tests/agent_provider_acceptance_test.gd", "AGENT_PROVIDER_ACCEPTANCE_TEST PASS", "core", foundations=True),
    script("world_blueprint_compiler", "tests/world_blueprint_compiler_test.gd", "WORLD_BLUEPRINT_COMPILER_TEST PASS", "core", foundations=True),
    script("generated_campaign_runtime", "tests/generated_campaign_runtime_test.gd", "GENERATED_CAMPAIGN_RUNTIME_TEST PASS", "core", foundations=True),
    script("npc_asset_registry", "tests/npc_asset_registry_test.gd", "NPC_ASSET_REGISTRY_TEST PASS", "core"),
    script("adventure_state", "tests/adventure_state_test.gd", "ADVENTURE_STATE_TEST PASS", "core"),
    script("runtime_foundations", "tests/runtime_foundations_test.gd", "RUNTIME_FOUNDATIONS_TEST PASS", foundations=True),
    script("adventure_integration", "tests/adventure_integration_test.gd", "ADVENTURE_INTEGRATION_TEST PASS", foundations=True),
    script("roster_integration", "tests/roster_integration_test.gd", "ROSTER_INTEGRATION_TEST PASS", foundations=True),
    script("menu_input", "tests/menu_input_test.gd", "MENU INPUT PASS", foundations=True),
    script("encounters", "tests/encounters_test.gd", "ENCOUNTERS_TEST PASS"),
    script("encounters_integration", "tests/encounters_integration_test.gd", "ENCOUNTERS_INTEGRATION_TEST PASS", foundations=True),
    script("combat_actor", "combat_actor_test.gd", "COMBAT_ACTOR_TEST PASS"),
    script("jump", "characters/first_knight/jump_test.gd", "JUMP TEST PASS"),
    script("world_loot", "world_loot_test.gd", "WORLD_LOOT_TEST PASS"),
    script("inventory_panel", "inventory_panel_test.gd", "INVENTORY_PANEL_TEST PASS"),
    script("atlas", "atlas_test.gd", "ATLAS_TEST PASS"),
    script("fountain_collision", "fountain_collision_test.gd", "FOUNTAIN_COLLISION_TEST PASS"),
    script("developer_tools", "developer_tools_test.gd", "DEVELOPER_TOOLS_TEST PASS"),
    script("town_animation", "town_animation_test.gd", "TOWN_ANIMATION_TEST PASS"),
    script("courtyard_fixes", "courtyard_fixes_test.gd", "COURTYARD_FIXES_TEST PASS"),
    TestSpec("map_smoke", "gameplay", ("--", "--smoke-map"), r"PASS: crate sides/top\b"),
    TestSpec("interaction_smoke", "gameplay", ("--", "--smoke-interactions"), r"INTERACTION_TEST PASS\b"),
    TestSpec("combat_smoke", "gameplay", ("--", "--smoke-combat"), r"COMBAT_STAGE_TEST PASS\b"),
)


def inspect_output(returncode: Optional[int], output: str, pass_pattern: Optional[str], *, timed_out: bool = False) -> list[str]:
    """Keep this independent of launching Godot so the false-success guard is testable."""
    reasons = []
    if timed_out:
        reasons.append("process exceeded its time limit")
    if returncode != 0:
        reasons.append(f"process exit code: {returncode}")
    errors = [line.strip() for line in output.splitlines() if ERROR_PATTERN.search(line)]
    if errors:
        reasons.extend(errors[:8])
        if len(errors) > 8:
            reasons.append(f"{len(errors) - 8} more errors in the full log")
    if pass_pattern is not None and re.search(pass_pattern, output) is None:
        reasons.append("explicit test PASS marker was not printed")
    return reasons


def run_process(name: str, command: list[str], cwd: Path, log_path: Path, timeout: int, pass_pattern: Optional[str]) -> dict:
    started = time.monotonic()
    output = ""
    returncode = None
    timed_out = False
    process = None
    launch_error = ""
    try:
        options = {}
        if os.name == "nt":
            options["creationflags"] = subprocess.CREATE_NO_WINDOW
        process = subprocess.Popen(
            command, cwd=str(cwd), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace",
            **options,
        )
        try:
            output, _ = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            process.kill()
            output, _ = process.communicate(timeout=5)
        returncode = process.returncode
    except OSError as error:
        launch_error = f"could not launch process: {error}"
    except BaseException:
        # Ctrl+C must not leave a headless Godot instance running in the background.
        if process is not None and process.poll() is None:
            process.kill()
            process.communicate(timeout=5)
        raise
    elapsed = round(time.monotonic() - started, 3)
    reasons = inspect_output(returncode, output, pass_pattern, timed_out=timed_out)
    if launch_error:
        reasons.insert(0, launch_error)
    log_path.write_text(
        "Command (argument array): " + json.dumps(command, ensure_ascii=False) + "\n"
        + f"Exit: {returncode}; elapsed: {elapsed:.3f}s; timeout: {timed_out}\n\n"
        + (launch_error + "\n" if launch_error else "") + output,
        encoding="utf-8",
    )
    return {
        "name": name, "status": "fail" if reasons else "pass", "seconds": elapsed,
        "returncode": returncode, "timed_out": timed_out, "reasons": reasons,
        "log": str(log_path), "command": command,
    }


def resolve_godot(value: Optional[str]) -> Path:
    configured = value or os.environ.get("GODOT_BIN")
    if configured:
        candidate = Path(configured).expanduser()
        if not candidate.is_file():
            located = shutil.which(configured)
            if located:
                candidate = Path(located)
    else:
        located = next((path for name in ("godot", "godot4", "godot-mono") if (path := shutil.which(name))), None)
        if not located:
            raise ValueError("Godot not found. Pass --godot /absolute/path/to/executable or set GODOT_BIN.")
        candidate = Path(located)
    if not candidate.is_file():
        raise ValueError(f"Godot executable does not exist: {candidate}")
    if os.name != "nt" and not os.access(candidate, os.X_OK):
        raise ValueError(f"Godot file is not executable: {candidate}")
    return candidate.resolve()


def print_result(result: dict) -> None:
    print(f"[{result['status'].upper():4}] {result['name']:<27} {result['seconds']:7.3f}s", flush=True)
    for reason in result["reasons"]:
        print("       " + reason, flush=True)


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--godot", help="Godot executable; otherwise GODOT_BIN or PATH is used")
    parser.add_argument("--suite", choices=("core", "gameplay", "all"), default="all")
    parser.add_argument("--only", action="append", choices=tuple(test.name for test in TESTS), help="Run this named test only; repeat for multiple tests")
    parser.add_argument("--output", type=Path, help="Log/report root; defaults to project/test-results")
    parser.add_argument("--timeout", type=int, default=60, help="Per-process limit in seconds, 1..60 (default 60)")
    parser.add_argument("--skip-import", action="store_true", help="Skip the headless asset-import preflight on an already imported checkout")
    parser.add_argument("--list", action="store_true", help="List selected tests without starting Godot")
    args = parser.parse_args(argv)
    if not 1 <= args.timeout <= 60:
        parser.error("--timeout must be between 1 and 60 seconds")
    selected = [test for test in TESTS if (args.suite == "all" or test.suite == args.suite) and (not args.only or test.name in args.only)]
    if not selected:
        parser.error("No tests match the selected suite and --only filters")
    if args.list:
        for test in selected:
            print(f"{test.name:<27} {test.suite:<8} {' '.join(test.arguments)}")
        return 0
    try:
        engine = resolve_godot(args.godot)
    except ValueError as error:
        parser.error(str(error))
    output_root = (args.output.expanduser() if args.output else PROJECT_ROOT / "test-results").resolve()
    started_at = datetime.now(timezone.utc)
    run_directory = output_root / (started_at.strftime("%Y%m%dT%H%M%SZ") + f"-{os.getpid()}")
    run_directory.mkdir(parents=True, exist_ok=False)
    # An output directory inside the project must not become an imported game asset.
    (run_directory / ".gdignore").write_text("", encoding="utf-8")
    report = {
        "started_at": started_at.isoformat(), "project": str(PROJECT_ROOT), "godot": str(engine),
        "suite": args.suite, "timeout_seconds": args.timeout, "selected": [test.name for test in selected],
        "results": [], "status": "running",
    }
    print(f"Godot: {engine}\nProject: {PROJECT_ROOT}\nReports: {run_directory}", flush=True)
    command_base = [str(engine), "--headless", "--path", str(PROJECT_ROOT), "--quit-after", "600"]
    interrupted = False
    try:
        if not args.skip_import:
            import_command = command_base + ["--editor", "--import", "--log-file", str(run_directory / "import.engine.log")]
            result = run_process("asset_import", import_command, PROJECT_ROOT, run_directory / "import.log", args.timeout, None)
            report["results"].append(result)
            print_result(result)
            if result["status"] == "fail":
                print("Asset import failed; test processes are skipped until the project can import cleanly.", flush=True)
                selected = []
        for test in selected:
            command = command_base + ["--log-file", str(run_directory / (test.name + ".engine.log"))] + list(test.arguments)
            result = run_process(test.name, command, PROJECT_ROOT, run_directory / (test.name + ".log"), args.timeout, test.pass_pattern)
            report["results"].append(result)
            print_result(result)
    except KeyboardInterrupt:
        interrupted = True
        print("\nInterrupted; the active Godot process was stopped.", flush=True)
    except Exception as error:
        result = {"name": "runner", "status": "fail", "seconds": 0.0,
                  "returncode": None, "timed_out": False,
                  "reasons": [f"Runner infrastructure error: {error}"], "log": "", "command": []}
        report["results"].append(result)
        print_result(result)
    finally:
        report["finished_at"] = datetime.now(timezone.utc).isoformat()
        report["passed"] = sum(result["status"] == "pass" for result in report["results"])
        report["failed"] = sum(result["status"] == "fail" for result in report["results"])
        report["status"] = "interrupted" if interrupted else ("fail" if report["failed"] else "pass")
        report_path = run_directory / "report.json"
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        summary = f"{report['status'].upper()}: {report['passed']} passed, {report['failed']} failed.\nReport: {report_path}\n"
        (run_directory / "summary.txt").write_text(summary, encoding="utf-8")
        print(summary, flush=True)
    return 130 if interrupted else (1 if report["failed"] else 0)


if __name__ == "__main__":
    raise SystemExit(main())
