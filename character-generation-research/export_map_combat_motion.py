"""Export reviewed H3 frame selections, with fixed scale and authored root offsets.

Run only after the generation queue finishes and H3 weights are released. The
export spec is the record of artistic selection and gameplay timing, independent
of the original 24 fps video duration. No per-frame resizing or tight cropping.
"""
from pathlib import Path
import sys,json
sys.path.insert(0,str(Path(__file__).resolve().parent))
from biref_h3_matte import ROOT,session,extract
from improve_h3_matte import matte
from PIL import Image,ImageDraw
import numpy as np
from scipy import ndimage

out=ROOT/'map-combat-motion'
dest=ROOT.parent.parent/'godot-belt-map/characters/first_knight/assets'
spec=json.loads((out/'export-spec.json').read_text())
s=session(use_gpu=True)
clips={}
for action,clip in spec['clips'].items():
 files=sorted((ROOT/'output/frames').glob('map-'+action+'_*.png'))
 assert len(files)==124,(action,len(files))
 folder=dest/'combat-motion'/action;folder.mkdir(parents=True,exist_ok=True)
 records=[];previews=[]
 for i,frame in enumerate(clip['frames']):
  idx=frame['source_frame'];im=Image.open(files[idx]).convert('RGB');cut=extract(s,im)
  rgb=np.asarray(im).astype(float);a=np.array(cut);key=np.array(matte(im,True))
  navy=(rgb[:,:,2]>18)&(rgb[:,:,2]-rgb[:,:,0]>8)&(rgb[:,:,2]-rgb[:,:,1]>3)&(rgb.max(2)<125)
  a[navy]=key[navy]
  if action=='air_slash':
   # H3 added a detached arc despite the no-effects prompt. The precise AI
   # foreground mask already separates that arc from the knight and sword;
   # retain the largest connected character component, including its soft edge.
   labels,count=ndimage.label(a[:,:,3]>10)
   sizes=np.bincount(labels.ravel());sizes[0]=0
   keep=ndimage.binary_dilation(labels==int(sizes.argmax()),iterations=1)
   a[:,:,3][~keep]=0
  cut=Image.fromarray(a)
  name=f'combat-motion/{action}/{i:03d}.png';cut.save(dest/name)
  records.append(dict(frame,file=name))
  bg=Image.new('RGBA',(768,768),'#182536');bg.alpha_composite(cut)
  previews.append(bg.convert('RGB').resize((384,384)))
  print('EXPORTED',action,i,idx,flush=True)
 job=json.loads((out/(action+'-job.json')).read_text())
 clips[action]=dict(clip,frames=records,source='H3 '+job['prompt_id'])
 sheet=Image.new('RGB',(1536,256*((len(records)+7)//8)),'#182536');d=ImageDraw.Draw(sheet)
 for i,pic in enumerate(previews):
  x=(i%8)*192;y=(i//8)*256;sheet.paste(pic.resize((192,192)),(x,y))
  d.text((x+4,y+194),f"{i}: src {records[i]['source_frame']}",fill='white')
 sheet.save(out/(action+'-matte-review.jpg'))
 previews[0].save(out/(action+'-preview.webp'),save_all=True,append_images=previews[1:],duration=[f['duration_ms'] for f in records],loop=0,lossless=True)
(dest/'combat-motion.json').write_text(json.dumps(dict(spec,clips=clips),indent=2))
print('MANIFEST',dest/'combat-motion.json',flush=True)
