"""Download only two public safetensors, verify publisher LFS SHA256."""
from pathlib import Path
import urllib.request,json,hashlib,time,concurrent.futures
BASE=Path('C:/Users/11043/Downloads/Flux2_klein_v1.0_普通版/Flux2_klein/ComfyUI/models')
JOBS=[('cagliostrolab/animagine-xl-3.1','animagine-xl-3.1.safetensors',BASE/'checkpoints/animagine-xl-3.1.safetensors'),('xinsir/controlnet-openpose-sdxl-1.0','diffusion_pytorch_model.safetensors',BASE/'controlnet/xinsir-openpose-sdxl-1.0.safetensors')]
def download(job):
 repo,name,dest=job
 info=json.load(urllib.request.urlopen('https://huggingface.co/api/models/'+repo+'?blobs=true',timeout=40))
 entry=next(s for s in info['siblings'] if s['rfilename']==name)
 expected=entry['lfs']['sha256'];size=entry['size'];part=dest.with_suffix('.download')
 dest.parent.mkdir(exist_ok=True,parents=True)
 if dest.exists():
  if hashlib.file_digest(dest.open('rb'),'sha256').hexdigest()==expected:return str(dest)+' already verified'
  raise RuntimeError('Existing file differs; will not overwrite '+str(dest))
 print('DOWNLOAD',name,'bytes',size,flush=True)
 url='https://huggingface.co/'+repo+'/resolve/'+info['sha']+'/'+name
 completed=part.stat().st_size if part.exists() else 0
 # Parallel ranges are separate files until every block has passed length checks.
 block=64*1024*1024
 spans=[(a,min(a+block,size)-1) for a in range(completed,size,block)]
 def chunk(span):
  a,b=span;target=part.with_name(part.name+'.'+str(a));length=b-a+1
  if target.exists() and target.stat().st_size==length:return target
  for attempt in range(3):
   try:
    req=urllib.request.Request(url+'?download=true&offset='+str(a),headers={'Range':f'bytes={a}-{b}'})
    with urllib.request.urlopen(req,timeout=120) as r,target.open('wb') as f:
     if r.status!=206 or not r.headers.get('Content-Range','').startswith(f'bytes {a}-{b}/'):raise RuntimeError('Server did not honor requested range')
     while True:
      data=r.read(2*1024*1024)
      if not data:break
      f.write(data)
    if target.stat().st_size!=length:raise RuntimeError('Short block')
    return target
   except Exception:
    if attempt==2:raise
    time.sleep(2)
 with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
  done=0;last=time.time()
  futures=[pool.submit(chunk,s) for s in spans]
  for future in concurrent.futures.as_completed(futures):
   done+=future.result().stat().st_size
   if time.time()-last>15:print(name,round((completed+done)/size*100,1),'%',flush=True);last=time.time()
 with part.open('ab') as f:
  for a,b in spans:
   target=part.with_name(part.name+'.'+str(a))
   with target.open('rb') as src:
    while True:
     data=src.read(4*1024*1024)
     if not data:break
     f.write(data)
   target.unlink()
 if part.stat().st_size!=size or hashlib.file_digest(part.open('rb'),'sha256').hexdigest()!=expected:raise RuntimeError('Integrity failure '+name)
 part.rename(dest)
 return 'VERIFIED '+str(dest)
if __name__=='__main__':
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
  for result in pool.map(download,JOBS): print(result,flush=True)
