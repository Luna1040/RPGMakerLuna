"""User-invoked recovery after a Windows restart; completed jobs are reused."""
from pathlib import Path
import sys,json,subprocess,time,urllib.request,urllib.error
ROOT=Path(__file__).resolve().parent
DEST=ROOT/'h3-comparison'

def stats():return json.load(urllib.request.urlopen('http://127.0.0.1:9317/system_stats',timeout=5))

if __name__=='__main__':
    if (DEST/'render-hold.json').exists():
        raise SystemExit('Rendering held after a Windows bugcheck. No server or render will be started; see h3-comparison/render-hold.json.')
    try:s=stats()
    except (urllib.error.URLError,TimeoutError):
        out=(DEST/'resume-server.log').open('wb');err=(DEST/'resume-server-error.log').open('wb')
        process=subprocess.Popen([sys.executable,'-u',str(ROOT/'start_h3_comparison.py')],cwd=ROOT.parent,stdout=out,stderr=err,creationflags=subprocess.CREATE_NO_WINDOW)
        for _ in range(90):
            if process.poll() is not None:raise RuntimeError('Server failed: see resume-server-error.log')
            try:s=stats();break
            except (urllib.error.URLError,TimeoutError):time.sleep(2)
        else:raise RuntimeError('Server readiness timeout')
    if '+cu130' not in s['system']['pytorch_version']:raise RuntimeError('Port 9317 is using another runtime. Start the comparison CUDA13 service first.')
    (DEST/'cuda13-ready.json').write_text(json.dumps(s,ensure_ascii=False,indent=2),encoding='utf-8')
    (DEST/'node-schema.json').write_bytes(urllib.request.urlopen('http://127.0.0.1:9317/object_info').read())
    subprocess.run([sys.executable,str(ROOT/'adapt_community_workflows.py')],cwd=ROOT.parent,check=True)
    subprocess.run([sys.executable,str(ROOT/'export_h3_comparison_ui.py')],cwd=ROOT.parent,check=True)
    subprocess.run([sys.executable,'-u',str(ROOT/'run_h3_comparison.py'),'--phase','all'],cwd=ROOT.parent,check=True)
