import json,shutil
from pathlib import Path
from PIL import Image
root=Path('.')
assets=root/'assets/classes'
assets.mkdir(exist_ok=True)
profiles={}
for role in ['sword','yinyang','shadow','celestial']:
 source=root/'art-jobs/class-portraits-alpha-v14'/f'{role}.png'
 with Image.open(source) as image:
  assert image.mode=='RGBA' and image.size==(768,768)
  box=image.getchannel('A').point(lambda a:255 if a>=32 else 0).getbbox()
  profiles[role]={'height':box[3]-box[1],'pivot':[(box[0]+box[2])/2,box[3]],'canvas':[768,768]}
 shutil.copy2(source,assets/f'{role}.png')
(assets/'profiles.json').write_text(json.dumps(profiles,indent=2),encoding='utf-8')
