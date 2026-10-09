from pathlib import Path
import json
from PIL import Image
import numpy as np
root=Path(__file__).resolve().parent.parent/'godot-first-knight'
clips=json.loads((root/'assets/animations.json').read_text())
assert set(clips)=={'stand','idle','walk','attack1','attack2','attack3','cast','hurt'}
report={}
for name,clip in clips.items():
 assert clip['duration_ms']==sum(f['duration_ms'] for f in clip['frames'])
 assert all(f['duration_ms']>0 for f in clip['frames'])
 if 'event_ms' in clip:assert 0<clip['event_ms']<clip['duration_ms']
 counts=[];edge_counts=[]
 for frame in clip['frames']:
  im=Image.open(root/'assets'/frame['file'])
  assert im.mode=='RGBA' and im.size==(768,768),(name,frame)
  a=np.asarray(im)[:,:,3]
  counts.append(int((a>128).sum()))
  edge_counts.append(int((a[0,:]>128).sum()+(a[-1,:]>128).sum()+(a[:,0]>128).sum()+(a[:,-1]>128).sum()))
  assert 2000<counts[-1]<768*768*.65,(name,'bad mask',frame)
  assert edge_counts[-1]<20,(name,'opaque canvas border',frame)
  if 'fx' in frame:
   fx=Image.open(root/'assets'/frame['fx'])
   assert fx.size==im.size
 report[name]={'frames':len(counts),'duration_ms':clip['duration_ms'],'opaque_pixel_range':[min(counts),max(counts)],'border_pixels_max':max(edge_counts),'pivot':clip['pivot'],'scale':clip['scale']}
(root/'asset-verification.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
print('ASSET VALIDATION PASS')
