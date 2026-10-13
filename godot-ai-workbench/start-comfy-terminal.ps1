param([ValidateSet('Image','Video')][string]$Service='Video')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$port=if($Service -eq 'Image'){9315}else{9316}
$label=if($Service -eq 'Image'){'Flux image'}else{'H3 video'}
$Host.UI.RawUI.WindowTitle="ComfyUI - $label - $port"
$python=if($env:GAME_ART_PYTHON){$env:GAME_ART_PYTHON}else{Join-Path $env:USERPROFILE 'Downloads/Flux2_klein_v1.0_普通版/Flux2_klein/python_embeded/python.exe'}
$script=if($Service -eq 'Image'){Join-Path $root 'godot-ai-workbench/start_image_service.py'}else{Join-Path $root 'character-generation-research/start_h3.py'}
$ready=$false
try { $null=Invoke-RestMethod "http://127.0.0.1:$port/system_stats" -TimeoutSec 3; $ready=$true } catch {}
if($ready){
    Write-Host "ComfyUI already running on $port. Use its existing terminal; no duplicate process started."
    return
}
$loading=Get-CimInstance Win32_Process | Where-Object {$_.Name -like 'python*' -and $_.CommandLine -and $_.CommandLine.Contains($script)}
if($loading){
    Write-Host "ComfyUI $port is already loading. Check its existing terminal."
    return
}
if(!(Test-Path -LiteralPath $python)){throw "Python missing: $python"}
$env:PYTHONIOENCODING='utf-8'
$env:PYTHONUNBUFFERED='1'
Set-Location -LiteralPath $root
Write-Host "ComfyUI $label : http://127.0.0.1:$port"
Write-Host 'Live terminal. Ctrl+C stops this service; closing this window ends its console process.'
& $python -u -X utf8 $script
if($LASTEXITCODE -ne 0){throw "ComfyUI exited with code $LASTEXITCODE"}
