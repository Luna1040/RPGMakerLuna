from pathlib import Path
import sys,json,shutil
sys.path[:0]=[str(Path('character-generation-research/h3-runtime/matte-deps').resolve()),str(Path('character-generation-research/h3-runtime/deps').resolve())]
from PIL import Image
import numpy as np
root=Path('created-games/moontide-bistro/art-jobs');job=root/'v2-walk-padded';records=[r for r in json.loads((job/'output-index.json').read_text()) if r['file'].endswith('.png')]
base=np.asarray(Image.open(job/'outputs'/records[30]['file']).convert('RGB').resize((192,192))).astype(float)
res=[]
for i in range(50,66):
 a=np.asarray(Image.open(job/'outputs'/records[i]['file']).convert('RGB').resize((192,192))).astype(float)
 res.append((float(np.mean((a[100:165]-base[100:165])**2)),i))
end=sorted(res)[0][1];print('Loop match',sorted(res)[:3])
source=root/'v2-walk-padded-selected';source.mkdir(exist_ok=True)
chosen=list(range(30,end))
for i in chosen:shutil.copyfile(job/'outputs'/records[i]['file'],source/f'{i:05d}.png')
selection={'canvas':[768,768],'pivot':[384,640],'scale':0.22,'review_status':'candidate','frames':[{'file':f'{i:05d}.png','source_frame':i,'duration_ms':42} for i in chosen],'event_ms':None}
(root/'v2-walk-padded-selection.json').write_text(json.dumps(selection,indent=2),encoding='utf-8')
wsource=root/'v2-woman-source';wsource.mkdir(exist_ok=True);shutil.copyfile(root/'v2-guest-woman/outputs/00000.png',wsource/'woman.png')
