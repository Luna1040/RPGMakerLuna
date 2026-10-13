param([switch]$HomePage)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
. (Join-Path $root 'godot-ai-workbench/resolve-codex.ps1')
$node=Join-Path $root '.tools/node-v22.17.0-win-x64/node.exe'
$server=Join-Path $root 'godot-ai-workbench/bridge/game-server.mjs'
$connection=Join-Path $root '.game-assistant/connection.json'
if(Test-Path -LiteralPath $connection) {
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
$env:CODEX_BIN=Resolve-CodexExecutable
New-Item -ItemType Directory -Force $private | Out-Null
$serverArguments='"'+$server+'"'
if($HomePage){$serverArguments+=' --home'}
Start-Process -FilePath $node -ArgumentList $serverArguments -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput (Join-Path $private 'bridge.log') -RedirectStandardError (Join-Path $private 'bridge-error.log')
Write-Host 'Starting Codex and Godot. Press F1 inside the game.'
