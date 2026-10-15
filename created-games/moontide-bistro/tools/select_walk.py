from pathlib import Path
import sys,json,shutil
sys.path[:0]=[str(Path('character-generation-research/h3-runtime/matte-deps').resolve()),str(Path('character-generation-research/h3-runtime/deps').resolve())]
from PIL import Image
import numpy as np
root=Path('created-games/moontide-bistro/art-jobs');job=root/'v2-server-walk'
records=[r for r in json.loads((job/'output-index.json').read_text()) if r['file'].endswith('.png')]
base=np.asarray(Image.open(job/'outputs'/records[30]['file']).convert('RGB').resize((96,96))).astype(float)
res=[]
for i in range(50,120):
 a=np.asarray(Image.open(job/'outputs'/records[i]['file']).convert('RGB').resize((96,96))).astype(float)
 res.append((float(np.mean((a[48:]-base[48:])**2)),i))
print('Loop candidates',sorted(res)[:8])
end=sorted(res)[0][1]
source=root/'v2-walk-selected-source';source.mkdir(exist_ok=True)
chosen=list(range(30,end,2))
for i in chosen: shutil.copyfile(job/'outputs'/records[i]['file'],source/f'{i:05d}.png')
selection={'canvas':[768,768],'pivot':[384,728],'scale':0.16,'review_status':'candidate','frames':[{'file':f'{i:05d}.png','source_frame':i,'duration_ms':83} for i in chosen],'event_ms':None}
(root/'v2-walk-selection.json').write_text(json.dumps(selection,indent=2),encoding='utf-8')
print('Selected',chosen)
