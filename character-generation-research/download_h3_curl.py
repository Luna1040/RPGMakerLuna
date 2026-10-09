from download_h3 import ROOT,MODELS,FILES
import concurrent.futures,json,subprocess,time,hashlib
from pathlib import Path
manifest=json.loads((ROOT.parent/'h3-sprite-workflow/model-manifest.json').read_text(encoding='utf-8-sig'))
entries={e['rfilename']:e for e in manifest['siblings']}
tasks=[]
block=8*1024*1024
for name in FILES:
 e=entries[name]; dest=MODELS/name;dest.parent.mkdir(parents=True,exist_ok=True)
 if dest.exists() and dest.stat().st_size==e['size']:continue
 for a in range(0,e['size'],block):tasks.append((name,a,min(a+block,e['size'])-1))
def get(t):
 name,a,b=t;p=MODELS/(name+'.curlparts')/str(a);p.parent.mkdir(parents=True,exist_ok=True)
 if p.exists() and p.stat().st_size==b-a+1:return b-a+1
 url='https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/'+manifest['sha']+'/'+name+'?download=true&part='+str(a)
 for retry in range(5):
  r=subprocess.run(['curl.exe','-f','-sS','-L','--range',f'{a}-{b}','--connect-timeout','20','--max-time','180','-o',str(p),url],capture_output=True)
  if r.returncode==0 and p.stat().st_size==b-a+1:return b-a+1
 raise RuntimeError(str(t)+' '+r.stderr.decode(errors='replace')[-300:])
if __name__=='__main__':
 start=time.time();done=0;last=0;total=sum(b-a+1 for _,a,b in tasks)
 with concurrent.futures.ThreadPoolExecutor(max_workers=128) as pool:
  for f in concurrent.futures.as_completed([pool.submit(get,t) for t in tasks]):
   done+=f.result()
   if time.time()-last>15:
    print(f'{done/1e9:.2f}/{total/1e9:.2f} GB; {done/(time.time()-start)/1e6:.2f} MB/s',flush=True);last=time.time()
 for name in FILES:
  e=entries[name];dest=MODELS/name
  if dest.exists():continue
  temp=dest.with_suffix('.assembling');h=hashlib.sha256()
  with temp.open('wb') as out:
   for a in range(0,e['size'],block):
    p=MODELS/(name+'.curlparts')/str(a)
    with p.open('rb') as inp:
     while data:=inp.read(4*1024*1024):out.write(data);h.update(data)
  assert h.hexdigest()==e['lfs']['sha256'],name
  temp.rename(dest)
  print('VERIFIED',name,flush=True)
