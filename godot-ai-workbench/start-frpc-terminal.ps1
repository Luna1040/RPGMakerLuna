$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$config=Join-Path $root '.team-comfy-private/host.toml'
$frpc=Join-Path $env:USERPROFILE 'Downloads/frp_0.71.0_windows_amd64/frpc.exe'
$Host.UI.RawUI.WindowTitle='FRP - Team Image 19315 / Video 19316'
$existing=Get-CimInstance Win32_Process | Where-Object {$_.Name -eq 'frpc.exe' -and $_.CommandLine -and $_.CommandLine.Contains($config)}
if($existing){Write-Host 'Team frpc already running. Use its existing terminal.'; return}
if(!(Test-Path -LiteralPath $frpc)){throw 'frpc.exe missing'}
Write-Host 'Live FRP terminal. Keep open for team access. Ctrl+C stops this tunnel.'
& $frpc -c $config
Write-Host "frpc exited ($LASTEXITCODE). Review errors above; restart the launcher to reconnect."
