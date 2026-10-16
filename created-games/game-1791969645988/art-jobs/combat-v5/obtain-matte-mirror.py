from pathlib import Path
import json,ssl,urllib.request,hashlib
from pip._vendor import certifi
folder=Path(r'Z:\RPGMakerLuna\created-games\game-1791969645988\art-jobs\combat-v5')
manifest=json.loads(Path(r'Z:\RPGMakerLuna\character-generation-research\h3-runtime\matte-v2\model-manifest.json').read_text(encoding='utf-8-sig'))
entry=next(e for e in manifest['siblings'] if e['rfilename']=='onnx/model.onnx')
(folder/'model-manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
url='https://hf-mirror.com/onnx-community/BiRefNet_lite-ONNX/resolve/'+manifest['sha']+'/onnx/model.onnx?download=1'
ctx=ssl.create_default_context(cafile=certifi.where());h=hashlib.sha256();n=0
with urllib.request.urlopen(url,context=ctx,timeout=60) as response,(folder/'birefnet-lite.onnx.part').open('wb') as target:
 while True:
  data=response.read(1024*1024)
  if not data:break
  target.write(data);h.update(data);n+=len(data)
assert n==entry['size'] and h.hexdigest()==entry['lfs']['sha256'],(n,h.hexdigest())
(folder/'birefnet-lite.onnx.part').replace(folder/'birefnet-lite.onnx')
print('MODEL VERIFIED',n,flush=True)
