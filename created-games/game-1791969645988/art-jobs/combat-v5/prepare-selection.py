from pathlib import Path
import json,shutil
from PIL import Image
root=Path(r'Z:\RPGMakerLuna\created-games\game-1791969645988')
specs={
 'sword':{'canvas':[768,768],'pivot':[384,610],'scale':0.36,'event_ms':240,'review_status':'pending_alpha_review','indices':[8,16,22,27,34,40,65,85],'durations':[40,60,70,70,30,70,100,100]},
 'bite':{'canvas':[768,768],'pivot':[384,545],'scale':0.20,'event_ms':230,'review_status':'pending_alpha_review','indices':[0,8,16,24,32,40,60,85],'durations':[40,60,60,70,40,60,100,100]}}
for name,spec in specs.items():
 spec['frames']=[{'file':f'{i:05d}.png','source_frame':i,'duration_ms':d} for i,d in zip(spec.pop('indices'),spec.pop('durations'))]
 (root/'art-jobs/combat-v5'/f'{name}-selection.json').write_text(json.dumps(spec,indent=2),encoding='utf-8')
source=root/'art-jobs/bite-alpha-v5/00000.png'
if source.exists():
 target=root/'art-jobs/bite-alpha-selected-v5/00000.png';shutil.copyfile(source,target)
 review=root/'art-jobs/bite-alpha-v5/review/00000.jpg'
 if review.exists():shutil.copyfile(review,target.parent/'review/00000.jpg')
for p in (root/'art-jobs/bite-alpha-selected-v5').glob('*.png'):
 im=Image.open(p);print(p.name,im.getchannel('A').getbbox(),im.getpixel((0,0))[-1])
