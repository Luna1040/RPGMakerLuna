@echo off
chcp 65001 >nul
cd /d "%~dp0.."
"C:\Users\11043\Downloads\Flux2_klein_v1.0_普通版\Flux2_klein\python_embeded\python.exe" -u "%~dp0..\resume_h3_comparison.py"
pause
