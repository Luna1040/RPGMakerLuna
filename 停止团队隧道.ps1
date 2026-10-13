$ErrorActionPreference = 'Stop'
$config = Join-Path $PSScriptRoot '.team-comfy-private\host.toml'
Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'frpc.exe' -and $_.CommandLine -and $_.CommandLine.Contains($config) } | ForEach-Object { Stop-Process -Id $_.ProcessId }
Write-Host 'Team tunnel stopped. ComfyUI and unrelated frp services were left running.'
