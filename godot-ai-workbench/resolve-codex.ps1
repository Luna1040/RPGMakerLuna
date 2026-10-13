function Resolve-CodexExecutable {
    if ($env:CODEX_BIN -and (Test-Path -LiteralPath $env:CODEX_BIN -PathType Leaf)) {
        return (Resolve-Path -LiteralPath $env:CODEX_BIN).Path
    }
    $command = Get-Command codex.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    # Explorer does not inherit the Codex desktop process's PATH.
    $folders = @(
        (Join-Path $env:LOCALAPPDATA 'OpenAI/Codex/bin'),
        (Join-Path $env:USERPROFILE 'AppData/Local/OpenAI/Codex/bin')
    ) | Select-Object -Unique
    foreach ($folder in $folders) {
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }
        $candidate = Get-ChildItem -LiteralPath $folder -Filter codex.exe -Recurse -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($candidate) { return $candidate.FullName }
    }
    throw 'Cannot locate codex.exe. Open/update the Codex desktop app, or set CODEX_BIN to the full executable path.'
}
