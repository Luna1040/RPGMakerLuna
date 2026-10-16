$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'resolve-runtime.ps1')
$root=Split-Path -Parent $PSScriptRoot
$fixture=Join-Path $root ('.game-assistant/path-test-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path (Join-Path $fixture 'folder with spaces') -Force
$exe=Join-Path $fixture 'folder with spaces/runtime-probe.exe'
[IO.File]::WriteAllText($exe,'resolver fixture; never execute')
$savedPath=$env:PATH
try {
    $env:PATH=''
    $found=Resolve-GameExecutable -Label 'Probe' -Variable 'PROBE_BIN' -Override $exe -Names @('absent.exe') -Candidates @()
    if($found -ne $exe){throw 'Explicit path with spaces failed'}
    $found=Resolve-GameExecutable -Label 'Probe' -Variable 'PROBE_BIN' -Names @('absent.exe') -Candidates @((Join-Path $fixture 'folder with spaces/*.exe'))
    if($found -ne $exe){throw 'Portable wildcard failed'}
    $env:PATH=Split-Path -Parent $exe
    $found=Resolve-GameExecutable -Label 'Probe' -Variable 'PROBE_BIN' -Names @('runtime-probe.exe') -Candidates @()
    if($found -ne $exe){throw 'PATH lookup failed'}
    $env:PATH=''
    $failed=$false
    try {Resolve-GameExecutable -Label 'Probe' -Variable 'PROBE_BIN' -Names @('absent.exe') -Candidates @() | Out-Null} catch {$failed=$_.Exception.Message.Contains('PROBE_BIN')}
    if(!$failed){throw 'Missing dependency must name the configuration variable'}
    $failed=$false
    try {Resolve-GameExecutable -Label 'Probe' -Variable 'PROBE_BIN' -Override (Join-Path $fixture 'missing.exe') -Candidates @($exe) | Out-Null} catch {$failed=$_.Exception.Message.Contains('missing file')}
    if(!$failed){throw 'Invalid explicit override must not silently fall back'}
    Write-Host 'LAUNCHER PATH TEST PASS'
} finally {$env:PATH=$savedPath}
