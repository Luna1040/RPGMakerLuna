$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$private = Join-Path $root '.team-comfy-private'
$python = Join-Path $env:USERPROFILE 'Downloads/Flux2_klein_v1.0_普通版/Flux2_klein/python_embeded/python.exe'
$frpc = Join-Path $env:USERPROFILE 'Downloads/frp_0.71.0_windows_amd64/frpc.exe'
$config = Join-Path $private 'host.toml'
if (!(Test-Path -LiteralPath $config)) { throw 'Private host.toml missing. Run setup-team-comfy.py once.' }
$ready = $false
try { $null = Invoke-WebRequest 'http://127.0.0.1:9316/system_stats' -TimeoutSec 3; $ready = $true } catch {}
if (!$ready) {
    $script = Join-Path $root 'character-generation-research/start_h3.py'
    $existing = Get-CimInstance Win32_Process | Where-Object { $_.Name -like 'python*' -and $_.CommandLine -like '*character-generation-research*start_h3.py*' }
    if (!$existing) {
        Start-Process -FilePath $python -ArgumentList ('"'+$script+'"') -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput (Join-Path $private 'comfy.log') -RedirectStandardError (Join-Path $private 'comfy-error.log')
    }
}
$tunnel = Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'frpc.exe' -and $_.CommandLine -like '*team-comfy-private*host.toml*' }
if (!$tunnel) {
    Start-Process -FilePath $frpc -ArgumentList @('-c', ('"'+$config+'"')) -WorkingDirectory $private -WindowStyle Hidden -RedirectStandardOutput (Join-Path $private 'host.log') -RedirectStandardError (Join-Path $private 'host-error.log')
}
Write-Host 'Team tunnel started. ComfyUI may still be loading. Logs: .team-comfy-private'
