param([switch]$HomePage,[switch]$CheckOnly,[switch]$ReloadBridge)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
. (Join-Path $root 'godot-ai-workbench/resolve-codex.ps1')
. (Join-Path $root 'godot-ai-workbench/resolve-runtime.ps1')
$server=Join-Path $root 'godot-ai-workbench/bridge/game-server.mjs'
$connection=Join-Path $root '.game-assistant/connection.json'
$expectedVersion=(Get-Content -LiteralPath (Join-Path $root 'godot-ai-workbench/bridge/bridge-version.json') -Raw | ConvertFrom-Json).version
if(!$CheckOnly -and (Test-Path -LiteralPath $connection)) {
    $config=Get-Content -LiteralPath $connection -Raw | ConvertFrom-Json
    $running=$false
    try {
        $state=Invoke-RestMethod ($config.url+'/state') -Headers @{Authorization=('Bearer '+$config.token)} -TimeoutSec 2
        $running=$true
    } catch {}
    if($running) {
        if($ReloadBridge -or $state.bridgeVersion -ne $expectedVersion) {
            $state=Invoke-RestMethod ($config.url+'/state') -Headers @{Authorization=('Bearer '+$config.token)} -TimeoutSec 3
            if($state.status -in @('running','validating')){throw 'Wait for the current creation task to finish before restarting the assistant.'}
            $port=([uri]$config.url).Port
            $listener=@(netstat.exe -ano -p tcp | Where-Object {$_ -match "^\s*TCP\s+127\.0\.0\.1:$port\s+\S+\s+LISTENING\s+\d+\s*$"})
            if($listener.Count -ne 1){throw 'Cannot identify the authenticated bridge listener. No process was stopped.'}
            $bridgeProcessId=[int](($listener[0].Trim() -split '\s+')[-1])
            $bridgeProcess=Get-Process -Id $bridgeProcessId -ErrorAction Stop
            if($bridgeProcess.ProcessName -ne 'node'){throw 'Bridge listener is not Node.js. No process was stopped.'}
            if($state.processId -and $state.processId -ne $bridgeProcessId){throw 'Bridge process identity changed. Retry the launcher.'}
            Write-Host "Replacing old assistant (PID $bridgeProcessId)."
            Stop-Process -Id $bridgeProcessId -ErrorAction Stop
            if(!$bridgeProcess.WaitForExit(5000)){throw 'The old assistant did not stop.'}
        } else {
        $route=if($HomePage){'/home'}else{'/restart'}
        $null=Invoke-WebRequest -UseBasicParsing ($config.url+$route) -Method Post -Body '{}' -ContentType 'application/json' -Headers @{Authorization=('Bearer '+$config.token)} -TimeoutSec 10
        Write-Host 'Existing assistant restarted the game.'
        exit 0
        }
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
$started=Start-Process -FilePath $node -ArgumentList $serverArguments -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput (Join-Path $private 'bridge.log') -RedirectStandardError (Join-Path $private 'bridge-error.log') -PassThru
Write-Host 'Starting assistant; checking the live service version...'
$deadline=(Get-Date).AddSeconds(60)
do {
    $started.Refresh()
    if($started.HasExited){throw "Assistant exited with code $($started.ExitCode). See .game-assistant/bridge-error.log."}
    try {
        $liveConfig=Get-Content -LiteralPath $connection -Raw | ConvertFrom-Json
        $liveState=Invoke-RestMethod ($liveConfig.url+'/state') -Headers @{Authorization=('Bearer '+$liveConfig.token)} -TimeoutSec 2
        if($liveState.bridgeVersion -eq $expectedVersion -and $liveState.processId -eq $started.Id -and $liveState.status -eq 'ready'){
            Write-Host "VERIFIED: $expectedVersion (PID $($started.Id)), started $($liveState.startedAt)."
            exit 0
        }
        if($liveState.processId -eq $started.Id -and $liveState.status -eq 'failed'){throw $liveState.error}
    } catch { $lastStartupError=$_.Exception.Message }
    Start-Sleep -Seconds 1
} while((Get-Date) -lt $deadline)
throw "Assistant version was not verified. Last error: $lastStartupError. See .game-assistant/bridge-error.log."
