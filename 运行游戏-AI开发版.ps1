param([switch]$HomePage,[switch]$CheckOnly)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
. (Join-Path $root 'godot-ai-workbench/resolve-codex.ps1')
. (Join-Path $root 'godot-ai-workbench/resolve-runtime.ps1')
$server=Join-Path $root 'godot-ai-workbench/bridge/game-server.mjs'
$connection=Join-Path $root '.game-assistant/connection.json'
if(!$CheckOnly -and (Test-Path -LiteralPath $connection)) {
    $config=Get-Content -LiteralPath $connection -Raw | ConvertFrom-Json
    $running=$false
    try {
        $null=Invoke-WebRequest -UseBasicParsing ($config.url+'/state') -Headers @{Authorization=('Bearer '+$config.token)} -TimeoutSec 2
        $running=$true
    } catch {}
    if($running) {
        $route=if($HomePage){'/home'}else{'/restart'}
        $null=Invoke-WebRequest -UseBasicParsing ($config.url+$route) -Method Post -Body '{}' -ContentType 'application/json' -Headers @{Authorization=('Bearer '+$config.token)} -TimeoutSec 10
        Write-Host 'Existing assistant restarted the game.'
        exit 0
    }
}
$private=Join-Path $root '.game-assistant'
$runtime=Resolve-GameRuntimes -Root $root
$node=$runtime.Node
$env:GODOT_BIN=$runtime.Godot
$env:CODEX_BIN=Resolve-CodexExecutable
$nodeVersion=(& $node --version | Out-String).Trim()
if($LASTEXITCODE -ne 0 -or $nodeVersion -notmatch '^v(\d+)' -or [int]$Matches[1] -lt 20){throw 'Node.js 20+ is required; this project is tested with Node.js 22.x.'}
$godotVersion=(& $env:GODOT_BIN --version | Out-String).Trim()
if($LASTEXITCODE -ne 0 -or $godotVersion -notmatch '^4\.'){throw 'Godot 4 is required; this project is tested with Godot 4.7.2.'}
Write-Host "Node: $node ($nodeVersion)"
Write-Host "Godot: $env:GODOT_BIN ($godotVersion)"
Write-Host "Codex: $env:CODEX_BIN"
if($CheckOnly){Write-Host 'Launcher dependencies OK.'; exit 0}
New-Item -ItemType Directory -Force $private | Out-Null
$serverArguments='"'+$server+'"'
if($HomePage){$serverArguments+=' --home'}
Start-Process -FilePath $node -ArgumentList $serverArguments -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput (Join-Path $private 'bridge.log') -RedirectStandardError (Join-Path $private 'bridge-error.log')
Write-Host 'Starting Codex and Godot. Press F1 inside the game.'
