@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0restart-after-repair.ps1"
if errorlevel 1 pause
