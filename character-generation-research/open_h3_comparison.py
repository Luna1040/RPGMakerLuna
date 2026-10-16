"""Open the installed comparison ComfyUI without submitting rendering jobs."""
from pathlib import Path
import sys, subprocess, time, urllib.request, urllib.error, webbrowser

ROOT=Path(__file__).resolve().parent
DEST=ROOT/'h3-comparison'
URL='http://127.0.0.1:9317'

def ready():
    try:
        with urllib.request.urlopen(URL+'/system_stats',timeout=3) as r:
            return r.status==200
    except (urllib.error.URLError,TimeoutError):
        return False

if __name__=='__main__':
    if not ready():
        with (DEST/'open-server.log').open('wb') as out, (DEST/'open-server-error.log').open('wb') as err:
            process=subprocess.Popen([sys.executable,'-u',str(ROOT/'start_h3_comparison.py')],
                cwd=ROOT.parent,stdout=out,stderr=err,creationflags=subprocess.CREATE_NO_WINDOW)
        for _ in range(90):
            if process.poll() is not None:raise RuntimeError('ComfyUI startup failed; see open-server-error.log')
            if ready():break
            time.sleep(2)
        else:raise RuntimeError('ComfyUI startup timed out')
    webbrowser.open(URL)
