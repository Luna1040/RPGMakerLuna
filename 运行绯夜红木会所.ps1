$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'godot-ai-workbench/resolve-runtime.ps1')
$runtime=Resolve-GameRuntimes -Root $PSScriptRoot
$project=Join-Path $PSScriptRoot 'created-games/velvet-mahogany'
& $runtime.Godot --path $project
