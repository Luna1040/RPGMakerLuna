@echo off
"%~dp0.tools\art-python\python.exe" "%~dp0godot-ai-workbench\art_cli.py" check
if errorlevel 1 pause
