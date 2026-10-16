import json,urllib.request,zipfile,hashlib
from pathlib import Path
root=Path('art-jobs/classes-v14')
meta=json.load(urllib.request.urlopen('https://pypi.org/pypi/onnxruntime-directml/json',timeout=30))
files=[x for x in meta['urls'] if 'cp312-cp312-win_amd64.whl' in x['filename']]
if not files: raise RuntimeError('No CPython 3.12 Windows x64 DirectML wheel')
record=files[0]
path=root/record['filename']
with urllib.request.urlopen(record['url'],timeout=60) as response: path.write_bytes(response.read())
if hashlib.sha256(path.read_bytes()).hexdigest()!=record['digests']['sha256']: raise RuntimeError('Wheel checksum mismatch')
out=root/'dml-runtime'
out.mkdir(exist_ok=False)
with zipfile.ZipFile(path) as archive: archive.extractall(out)
(root/'dml-wheel.json').write_text(json.dumps({'version':meta['info']['version'],'filename':record['filename'],'sha256':record['digests']['sha256'],'url':record['url']},indent=2),encoding='utf-8')
print(record['filename'],path.stat().st_size)
