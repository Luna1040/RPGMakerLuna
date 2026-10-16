"""Switch the idle comparison server to isolated CUDA13, then run the rest."""
from pathlib import Path
import json,sys,subprocess,time,urllib.request,argparse

ROOT=Path(__file__).resolve().parent
DEST=ROOT/'h3-comparison'
URL='http://127.0.0.1:9317'

def get(path):return json.load(urllib.request.urlopen(URL+path,timeout=10))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--server-pid',type=int,required=True);a=p.parse_args()
    while not (DEST/'final/01_validation.json').exists():
        print('WAIT baseline master',time.strftime('%H:%M:%S'),flush=True);time.sleep(30)
    q=get('/queue')
    if q['queue_running'] or q['queue_pending']:raise RuntimeError('Server is busy; refusing restart')
    subprocess.run(['powershell.exe','-NoProfile','-Command',f'Stop-Process -Id {a.server_pid}'],check=True)
    time.sleep(3)
    out=(DEST/'cuda13-server.log').open('wb');err=(DEST/'cuda13-server-error.log').open('wb')
    server=subprocess.Popen([sys.executable,'-u',str(ROOT/'start_h3_comparison.py')],cwd=ROOT.parent,stdout=out,stderr=err,creationflags=subprocess.CREATE_NO_WINDOW)
    (DEST/'cuda13-server.pid').write_text(str(server.pid))
    for _ in range(90):
        if server.poll() is not None:raise RuntimeError('CUDA13 server failed; inspect cuda13-server-error.log')
        try:
            stats=get('/system_stats')
            if '+cu130' not in stats['system']['pytorch_version']:raise RuntimeError('Wrong Torch runtime '+str(stats))
            break
        except (urllib.error.URLError,TimeoutError,ConnectionError):time.sleep(2)
    else:raise RuntimeError('Server readiness timeout')
    (DEST/'cuda13-ready.json').write_text(json.dumps(stats,ensure_ascii=False,indent=2),encoding='utf-8')
    (DEST/'node-schema.json').write_text(json.dumps(get('/object_info'),ensure_ascii=False),encoding='utf-8')
    print('CUDA13_READY',server.pid,flush=True)
    subprocess.run([sys.executable,str(ROOT/'adapt_community_workflows.py')],cwd=ROOT.parent,check=True)
    subprocess.run([sys.executable,str(ROOT/'export_h3_comparison_ui.py')],cwd=ROOT.parent,check=True)
    subprocess.run([sys.executable,'-u',str(ROOT/'run_h3_comparison.py'),'--phase','rest'],cwd=ROOT.parent,check=True)
