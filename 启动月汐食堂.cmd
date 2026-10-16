@echo off

setlocal

cd /d "%~dp0"

set "APPDATA=%~dp0created-games\moontide-bistro\.runtime"

start "" "%~dp0.tools\godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0created-games\moontide-bistro"
