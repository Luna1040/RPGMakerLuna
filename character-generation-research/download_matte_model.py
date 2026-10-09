from pathlib import Path
import json,subprocess,concurrent.futures,hashlib
r=Path(__file__).resolve().parent/'h3-runtime/matte-v2';m=json.loads((r/'model-manifest.json').read_text(encoding='utf-8-sig'));e=next(x for x in m['siblings'] if x['rfilename']=='onnx/model.onnx')
def get(a):
 b=min(a+8*1024*1024,e['size'])-1;p=r/('part-'+str(a))
 if p.exists() and p.stat().st_size==b-a+1:return p
 url='https://huggingface.co/onnx-community/BiRefNet_lite-ONNX/resolve/'+m['sha']+'/onnx/model.onnx?part='+str(a)
 subprocess.run(['curl.exe','-f','-sS','-L','--retry','3','--max-time','180','--range',f'{a}-{b}','-o',str(p),url],check=True)
 assert p.stat().st_size==b-a+1
 return p
spans=list(range(0,e['size'],8*1024*1024))
with concurrent.futures.ThreadPoolExecutor(max_workers=28) as pool:list(pool.map(get,spans))
h=hashlib.sha256()
with (r/'birefnet-lite.onnx').open('wb') as f:
 for a in spans:
  data=(r/('part-'+str(a))).read_bytes();f.write(data);h.update(data)
assert h.hexdigest()==e['lfs']['sha256']
print('VERIFIED',e['size'],flush=True)
