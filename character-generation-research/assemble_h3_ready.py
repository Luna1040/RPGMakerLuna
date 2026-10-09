from download_h3_curl import MODELS,FILES,entries,block
import hashlib
for name in FILES[:4]:
 dest=MODELS/name;e=entries[name]
 if dest.exists():continue
 parts=[(MODELS/(name+'.curlparts')/str(a),min(block,e['size']-a)) for a in range(0,e['size'],block)]
 if not all(p.exists() and p.stat().st_size==n for p,n in parts):
  print('Not complete:',name,flush=True);continue
 temp=dest.with_suffix('.verified-assembling');h=hashlib.sha256()
 with temp.open('wb') as out:
  for p,n in parts:
   with p.open('rb') as f:
    while data:=f.read(4*1024*1024):out.write(data);h.update(data)
 assert h.hexdigest()==e['lfs']['sha256'],name
 temp.rename(dest);print('VERIFIED',name,flush=True)
