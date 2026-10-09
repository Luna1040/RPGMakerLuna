from pathlib import Path
import json,subprocess,concurrent.futures,hashlib
r=Path(__file__).resolve().parent/'h3-runtime/matte-v2';m=json.loads((r/'ort-pypi.json').read_text(encoding='utf-8-sig'));e=next(x for x in m['urls'] if 'cp312-cp312-win_amd64' in x['filename'])
def get(a):
 b=min(a+8*1024*1024,e['size'])-1;p=r/('ort-part-'+str(a))
 subprocess.run(['curl.exe','-f','-sS','-L','--retry','3','--max-time','180','--range',f'{a}-{b}','-o',str(p),e['url']],check=True)
 assert p.stat().st_size==b-a+1
spans=list(range(0,e['size'],8*1024*1024))
with concurrent.futures.ThreadPoolExecutor(max_workers=32) as pool:list(pool.map(get,spans))
h=hashlib.sha256()
with (r/e['filename']).open('wb') as f:
 for a in spans:
  data=(r/('ort-part-'+str(a))).read_bytes();f.write(data);h.update(data)
assert h.hexdigest()==e['digests']['sha256'];print('VERIFIED',e['filename'],flush=True)
