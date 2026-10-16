"""Import a fresh source package without changing its project configuration."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--godot", help="Godot 4.7.2 executable path")
parser.add_argument("--log-dir", type=Path, help="Directory for import diagnostics")
args = parser.parse_args()
root = Path(__file__).resolve().parent
godot = args.godot or shutil.which("godot") or shutil.which("godot4")
if not godot and Path("/Applications/Godot.app/Contents/MacOS/Godot").is_file():
    godot = "/Applications/Godot.app/Contents/MacOS/Godot"
if not godot:
    parser.error("Godot not found; supply --godot with the executable path")
logs = (args.log_dir or Path(tempfile.mkdtemp(prefix="really-working-import-"))).resolve()
logs.mkdir(parents=True, exist_ok=True)
original = hashlib.sha256((root / "project.godot").read_bytes()).hexdigest()
# Godot initializes this global font before cold import. Allow only these known
# first-pass messages; every other error and every second-pass error is fatal.
known = [
    r"ERROR: Cannot open file 'res://\.godot/imported/font\.ttf-[0-9a-f]+\.fontdata'\.",
    r"ERROR: Failed loading resource: res://\.godot/imported/font\.ttf-[0-9a-f]+\.fontdata\.",
    r"ERROR: Failed loading resource: res://font\.ttf\.",
    r"ERROR: No loader found for resource: res://font\.ttf \(expected type: unknown\)",
    r"ERROR: Error loading custom project font 'res://font\.ttf'",
]
results = {}
for attempt in [1, 2]:
    name = "initial" if attempt == 1 else "confirmed"
    command = [str(godot), "--headless", "--editor", "--import", "--path", str(root),
               "--audio-driver", "Dummy", "--log-file", str(logs / (name + "-engine.log"))]
    result = subprocess.run(command, capture_output=True, text=True, timeout=180)
    output = result.stdout + result.stderr
    (logs / (name + ".log")).write_text(output, encoding="utf-8")
    errors = [line.strip() for line in output.splitlines()
              if re.match(r"\s*(ERROR|SCRIPT ERROR|FATAL):", line)]
    unexpected = [line for line in errors if attempt == 2 or
                  not any(re.fullmatch(pattern, line) for pattern in known)]
    font_ready = any(f.is_file() and f.stat().st_size > 0
                     for f in (root / ".godot/imported").glob("font.ttf-*.fontdata"))
    passed = result.returncode == 0 and not unexpected and font_ready
    results[name] = {"passed": passed, "exit": result.returncode, "errors": errors,
                     "unexpected_errors": unexpected, "font_imported": font_ready,
                     "log_sha256": hashlib.sha256(output.encode()).hexdigest()}
    (logs / "IMPORT_CHECKS.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    if not passed:
        print(output)
        raise SystemExit("Import failed. Diagnostics: " + str(logs))
    if errors:
        print("Initial font cache generated; confirming import with the original configuration.")
if hashlib.sha256((root / "project.godot").read_bytes()).hexdigest() != original:
    raise SystemExit("Project configuration changed during import")
print("IMPORT_PROJECT_PASS - open project.godot and press F5. Diagnostics: " + str(logs))
