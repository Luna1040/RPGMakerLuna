import sys,json
sys.path.insert(0,r'Z:\RPGMakerLuna\shareable-skills\game-production\scripts')
from comfy_client import api
for port in [9315,9316]:
 info=api(f'http://127.0.0.1:{port}','/object_info')
 nodes={k:v for k,v in info.items() if any(x in k.lower() for x in ['rmbg','biref','removebackground','rembg','backgroundremov'])}
 print(port,list(nodes))
 from pathlib import Path
 Path(f'art-jobs/classes-v14/matte-nodes-{port}.json').write_text(json.dumps(nodes,indent=2),encoding='utf-8')
