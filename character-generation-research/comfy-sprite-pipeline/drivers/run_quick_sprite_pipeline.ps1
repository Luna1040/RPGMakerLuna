param(
    [Parameter(Mandatory = $false)]
    [string]$Source,

    [Parameter(Mandatory = $false)]
    [string]$Preset = "idle_breathing",

    [Parameter(Mandatory = $false)]
    [string]$Name,

    [switch]$Greyscale,

    [switch]$ListPresets
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$comfyRoot = if ($env:COMFYUI_ROOT) { $env:COMFYUI_ROOT } else { Join-Path (Split-Path -Parent $repoRoot) "ComfyUI" }
$pythonExe = Join-Path $comfyRoot ".venv\Scripts\python.exe"
$script = Join-Path $repoRoot "drivers\run_quick_sprite_pipeline.py"

if (-not (Test-Path $pythonExe)) {
    throw "Python not found: $pythonExe"
}

$args = @($script)
if ($ListPresets) {
    $args += "--list-presets"
} else {
    if (-not $Source) {
        throw "Use -Source <image-path> or -ListPresets"
    }
    $args += @("--source", $Source, "--preset", $Preset)
    if ($Name) {
        $args += @("--name", $Name)
    }
    if ($Greyscale) {
        $args += "--greyscale"
    }
}

& $pythonExe @args
