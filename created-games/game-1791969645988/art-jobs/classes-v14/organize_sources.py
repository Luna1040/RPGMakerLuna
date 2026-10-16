import json,shutil,sys
from pathlib import Path
sys.path.insert(0,r'Z:\RPGMakerLuna\shareable-skills\game-production\scripts')
from comfy_client import api
for url in ['http://127.0.0.1:9315','http://127.0.0.1:9316']:
 q=api(url,'/queue'); print(url,'running',len(q.get('queue_running',[])),'pending',len(q.get('queue_pending',[])))
for role in ['sword','yinyang','shadow','celestial']:
 job=Path('art-jobs')/f'class-{role}-attack-v14'
 index=json.loads((job/'output-index.json').read_text(encoding='utf-8'))
 sources=[r for r in index if r['node']=='15' and r['file'].endswith('.png')]
 out=Path('art-jobs')/f'class-{role}-source-v14'; out.mkdir(exist_ok=False)
 frames=[]
 for i,record in enumerate(sources):
  name=f'{i:05d}.png'; shutil.copy2(job/'outputs'/record['file'],out/name)
  frames.append({'file':name,'source_frame':i,'node':record['node'],'original_file':record['file']})
 (out/'source-index.json').write_text(json.dumps({'fps':24,'canvas':[768,768],'frames':frames},indent=2),encoding='utf-8')
 print(role,len(frames),'complete native source frames')
