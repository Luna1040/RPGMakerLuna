"""Run the authorized local smoke tests as soon as verified weights exist."""
from pathlib import Path
import time,subprocess,sys,json,urllib.request
from download_h3 import ROOT,MODELS,FILES
REVIEW_PYTHON='C:/Users/11043/Downloads/Flux2_klein_v1.0_普通版/Flux2_klein/python_embeded/python.exe'
def original_free():
 try:
  base='http://127.0.0.1:9315'
  queue=json.load(urllib.request.urlopen(base+'/queue',timeout=5))
  if not queue.get('queue_running') and not queue.get('queue_pending'):
   req=urllib.request.Request(base+'/free',data=json.dumps({'unload_models':True,'free_memory':True}).encode(),headers={'Content-Type':'application/json'})
   urllib.request.urlopen(req,timeout=20).read();print('Released idle original ComfyUI model cache',flush=True)
 except Exception as e:print('Original cache check:',str(e),flush=True)
if __name__=='__main__':
 while not all((MODELS/f).exists() for f in FILES):time.sleep(10)
 print('ALL_MODELS_READY',flush=True);original_free()
 for action in ['walk','attack']:
  result=subprocess.run([sys.executable,'-u',str(ROOT.parent/'run_h3_smoke.py'),action])
  if result.returncode:raise SystemExit(result.returncode)
  record=json.loads((ROOT/(action+'-history.json')).read_text())
  if record.get('status',{}).get('status_str')!='success':raise SystemExit('Generation failed; inspect history')
  subprocess.run([REVIEW_PYTHON,str(ROOT.parent/'review_h3.py'),action],check=True)
 subprocess.run([REVIEW_PYTHON,str(ROOT.parent/'review_h3.py'),'walk','attack'],check=True)
 print('SUITE_FINISHED',flush=True)
