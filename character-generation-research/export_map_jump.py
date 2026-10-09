"""Export manually reviewed jump timing/root offsets; no frame is resized separately."""
from pathlib import Path
import sys,json,time
sys.path.insert(0,str(Path(__file__).resolve().parent))
from biref_h3_matte import ROOT,session,extract
from improve_h3_matte import matte
from PIL import Image,ImageDraw
import numpy as np

out=ROOT/'map-jump'
dest=ROOT.parent.parent/'godot-belt-map/characters/first_knight/assets'
(dest/'jump').mkdir(exist_ok=True)
spec=json.loads((out/'export-spec.json').read_text())
files=sorted((ROOT/'output/frames').glob('map-jump_*.png'))
assert len(files)==124
s=session(use_gpu=True)
records=[];preview=[]
for i,frame in enumerate(spec['frames']):
 idx=frame['source_frame'];im=Image.open(files[idx]).convert('RGB')
 cut=extract(s,im)
 # No spell/trail was requested: blue navy fabric is opaque body material.
 rgb=np.asarray(im).astype(float);a=np.array(cut);key=np.array(matte(im,True))
 navy=(rgb[:,:,2]>18)&(rgb[:,:,2]-rgb[:,:,0]>8)&(rgb[:,:,2]-rgb[:,:,1]>3)&(rgb.max(2)<125)
 a[navy]=key[navy];cut=Image.fromarray(a)
 name=f'jump/{i:03d}.png';cut.save(dest/name)
 records.append(dict(frame,file=name))
 bg=Image.new('RGBA',(768,768),'#182536');bg.alpha_composite(cut)
 preview.append(bg.convert('RGB').resize((384,384)))
 print('EXPORTED',i,idx,flush=True)
result=dict(spec,frames=records,source='H3 map-jump 9b62b447-7fe8-4605-8586-383b124695de')
(dest/'jump.json').write_text(json.dumps(result,indent=2))
sheet=Image.new('RGB',(1536,384*((len(records)+7)//8)),'#182536');d=ImageDraw.Draw(sheet)
for i,pic in enumerate(preview):
 x=(i%8)*192;y=(i//8)*384
 sheet.paste(pic.resize((192,192)),(x,y))
 d.text((x+4,y+190),f"{i}: src {records[i]['source_frame']}",fill='white')
sheet.save(out/'matte-review.jpg')
preview[0].save(out/'jump-preview.webp',save_all=True,append_images=preview[1:],duration=70,loop=0,lossless=True)
