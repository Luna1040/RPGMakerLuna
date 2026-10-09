$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$comfyRoot = if ($env:COMFYUI_ROOT) { $env:COMFYUI_ROOT } else { Join-Path (Split-Path -Parent $repoRoot) "ComfyUI" }
$outputRoot = Join-Path $comfyRoot "output\character_pipeline"
$viewerScript = Join-Path $repoRoot "viewer\server.py"
$pythonExe = Join-Path $comfyRoot ".venv\Scripts\python.exe"

if (-not (Test-Path $pythonExe)) {
    throw "Python not found: $pythonExe"
}

Write-Host "Viewer output root: $outputRoot"
Write-Host "Starting legacy viewer on http://127.0.0.1:8010"
Write-Host "Starting Animation Studio on http://127.0.0.1:8010/studio"

& $pythonExe $viewerScript --host 127.0.0.1 --port 8010 --output-root $outputRoot
