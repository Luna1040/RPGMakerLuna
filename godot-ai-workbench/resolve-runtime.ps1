function Resolve-GameExecutable {
    param([string]$Label,[string]$Override,[string]$Variable,[string[]]$Names,[string[]]$Candidates)
    if($Override){
        if(Test-Path -LiteralPath $Override -PathType Leaf){return (Resolve-Path -LiteralPath $Override).Path}
        throw "$Variable points to a missing file: $Override"
    }
    foreach($name in $Names){
        $command=Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if($command){return $command.Source}
    }
    foreach($candidate in $Candidates){
        if(!$candidate){continue}
        $file=Get-Item -Path $candidate -ErrorAction SilentlyContinue | Where-Object {!$_.PSIsContainer} | Sort-Object FullName -Descending | Select-Object -First 1
        if($file){return $file.FullName}
    }
    throw "$Label was not found. Install it and add it to PATH, or set $Variable to its full .exe path. The repository does not include local .tools binaries."
}
function Resolve-GameRuntimes {
    param([string]$Root)
    $nodeCandidates=@((Join-Path $Root '.tools/node*/node.exe'),(Join-Path $Root 'tools/node*/node.exe'))
    foreach($folder in @($env:ProgramFiles,${env:ProgramFiles(x86)},$env:LOCALAPPDATA)){
        if($folder){$nodeCandidates+=Join-Path $folder 'nodejs/node.exe'}
    }
    $node=Resolve-GameExecutable -Label 'Node.js (tested with 22.x)' -Override $env:NODE_BIN -Variable 'NODE_BIN' -Names @('node.exe') -Candidates $nodeCandidates
    $godotCandidates=@((Join-Path $Root '.tools/godot/Godot*_win64.exe'),(Join-Path $Root 'tools/godot/Godot*_win64.exe'),(Join-Path $Root 'Godot*_win64.exe'))
    # Publishing checkouts share the developer workspace's portable engine.
    $parent=Split-Path -Parent $Root
    if((Split-Path -Leaf $parent) -eq '.publish'){
        $workspace=Split-Path -Parent $parent
        $godotCandidates+=Join-Path $workspace '.tools/godot/Godot*_win64.exe'
    }
    $godot=Resolve-GameExecutable -Label 'Godot 4 (tested with 4.7.2)' -Override $env:GODOT_BIN -Variable 'GODOT_BIN' -Names @('godot.exe','godot4.exe') -Candidates $godotCandidates
    return @{Node=$node;Godot=$godot}
}
