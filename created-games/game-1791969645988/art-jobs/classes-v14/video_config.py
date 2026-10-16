import json,sys
from pathlib import Path
sys.path.insert(0,r'Z:\RPGMakerLuna\shareable-skills\game-production\scripts')
from comfy_client import api
schema=api('http://127.0.0.1:9316','/object_info')['MiniMaxH3ReferenceToVideo']['input']['required']
print({k:v for k,v in schema.items() if k in ['width','height','length']})
graph=json.loads(Path(r'Z:\RPGMakerLuna\shareable-skills\game-production\assets\h3-reference-api.json').read_text(encoding='utf-8'))
graph['6']['inputs']['length']=44
Path('art-jobs/classes-v14/h3-44-api.json').write_text(json.dumps(graph,indent=2),encoding='utf-8')
