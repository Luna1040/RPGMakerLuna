$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$connection=Join-Path $root '.game-assistant/connection.json'
if(Test-Path -LiteralPath $connection){
 $config=Get-Content -LiteralPath $connection -Raw | ConvertFrom-Json
 $state=$null
 try{$state=Invoke-RestMethod -Uri ($config.url+'/state') -Headers @{Authorization=('Bearer '+$config.token)} -TimeoutSec 3}catch{}
 if($state){
  if($state.status -in @('running','validating')){throw '创作任务仍在运行，请先在首页停止任务再重启。'}
  $bridgePath=Join-Path $root 'godot-ai-workbench\bridge\game-server.mjs'
  $bridges=@(Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object {$_.CommandLine -and $_.CommandLine.Contains($bridgePath)})
  if($bridges.Count -ne 1){throw '无法唯一确认此项目的桥接服务；为避免停止其他程序，已取消重启。'}
  $bridgeId=[int]$bridges[0].ProcessId
  $children=@(Get-CimInstance Win32_Process -Filter "ParentProcessId=$bridgeId" | Where-Object {$_.Name -eq 'codex.exe' -and $_.CommandLine -match 'app-server'})
  Stop-Process -Id $bridgeId
  foreach($child in $children){Stop-Process -Id $child.ProcessId -ErrorAction SilentlyContinue}
 }
}
& (Join-Path $root '运行游戏-AI开发版.ps1') -HomePage
if($LASTEXITCODE -and $LASTEXITCODE -ne 0){throw '启动失败，请查看 .game-assistant/bridge-error.log'}
Write-Host '修复后的创作首页已启动。选择魔域，点击继续创作。'

