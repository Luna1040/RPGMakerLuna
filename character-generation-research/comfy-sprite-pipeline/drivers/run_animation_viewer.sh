#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
comfy_root="${COMFYUI_ROOT:-$(dirname "$repo_root")/ComfyUI}"
python_exe="${PIPELINE_PYTHON:-$comfy_root/.venv/bin/python}"

if [[ ! -x "$python_exe" ]]; then
  echo "Python not found: $python_exe" >&2
  exit 1
fi

export COMFYUI_ROOT="$comfy_root"
export PIPELINE_PYTHON="$python_exe"
exec "$python_exe" "$repo_root/viewer/server.py" \
  --host 127.0.0.1 \
  --port 8010 \
  --output-root "$comfy_root/output/character_pipeline"
