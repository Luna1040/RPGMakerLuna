"""Prepare one local video for the 512x640 / 124-frame H3 workflows."""
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
CORE = next((HERE.parent / 'h3-runtime').glob('ComfyUI-*'))
if len(sys.argv) < 2:
    raise SystemExit('Drag a source video onto prepare-video.cmd, or run: python prepare_video.py video.mp4')
source = Path(sys.argv[1]).resolve(strict=True)
destination = CORE / 'input/guofeng-user-source.mp4'
subprocess.run([
    'C:/ffmpeg/bin/ffmpeg.exe', '-hide_banner', '-y', '-i', str(source),
    '-vf', 'fps=24,scale=512:640:force_original_aspect_ratio=increase,crop=512:640,tpad=stop_mode=clone:stop_duration=6',
    '-frames:v', '124', '-an', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', str(destination)
], check=True)
print('Prepared:', destination)
print('In workflow 02 or 03 select guofeng-user-source.mp4 in Load Video.')
