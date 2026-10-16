$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$private=Join-Path $root '.team-comfy-private'
$frpc=Join-Path $env:USERPROFILE 'Downloads/frp_0.71.0_windows_amd64/frpc.exe'
$config=Join-Path $private 'host.toml'
$terminal=Join-Path $root 'godot-ai-workbench/start-comfy-terminal.ps1'
$shell=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
$imageReady=$false
try {$null=Invoke-RestMethod 'http://127.0.0.1:9315/system_stats' -TimeoutSec 3; $imageReady=$true}catch{}
if(!$imageReady){
    Start-Process -FilePath $shell -ArgumentList ('-NoProfile -NoExit -ExecutionPolicy Bypass -File "'+$terminal+'" -Service Image') -WorkingDirectory $root -WindowStyle Normal
}
$frpTerminal=Join-Path $root 'godot-ai-workbench/start-frpc-terminal.ps1'
if((Test-Path -LiteralPath $config) -and (Test-Path -LiteralPath $frpc)){
    Start-Process -FilePath $shell -ArgumentList ('-NoProfile -NoExit -ExecutionPolicy Bypass -File "'+$frpTerminal+'"') -WorkingDirectory $root -WindowStyle Normal
}else{
    Write-Host 'Team tunnel is not configured; local ComfyUI still starts normally.'
}
& $terminal -Service Video
