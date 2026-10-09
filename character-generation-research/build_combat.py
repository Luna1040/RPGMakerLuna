from pathlib import Path
import sys,json
sys.path.insert(0,str(Path(__file__).resolve().parent))
from biref_h3_matte import ROOT,session,extract
from PIL import Image,ImageDraw
import numpy as np
from scipy import ndimage as ndi
from improve_h3_matte import matte

# Preserve anticipation, accelerate the strike, hold impact, then recover.
timeline=[(8,35),(14,35),(20,40),(25,45),(28,50),
 (30,20),(33,20),(36,20),(39,20),(42,55),
 (45,25),(48,30),(52,35),(57,40),(63,40),(70,45),
 (78,45),(90,40)]
out=ROOT/'combat-v1';out.mkdir(exist_ok=True)
s=session();previews={False:[],True:[]};audit=[]
for n,(idx,ms) in enumerate(timeline):
 im=Image.open(ROOT/'output/frames'/f'attack-hq_{idx+1:05d}_.png').convert('RGB')
 cut,body_probability=extract(s,im,return_mask=True)
 rgb=np.asarray(im).astype(np.float32)
 blue=(rgb[:,:,2]>45)&(rgb[:,:,2]-rgb[:,:,0]>18)&(rgb[:,:,2]-rgb[:,:,1]>7)
 # Keep body-model foreground (especially the navy cape) out of the effect.
 yy,xx=np.indices(rgb.shape[:2])
 # Conservative spatial protection for this fixed-camera clip, not a generic
 # character separator: do not erase blue fabric inside the body envelope.
 protection=Image.new('L',im.size,0)
 polygon=[(170,485),(210,360),(365,280),(403,355),(440,425),(335,510)] if idx<36 else [(95,310),(370,265),(405,350),(330,450),(145,410)]
 ImageDraw.Draw(protection).polygon(polygon,fill=255)
 ImageDraw.Draw(protection).polygon([(365,345),(430,340),(455,430),(415,460),(325,430)],fill=255)
 exterior=np.asarray(protection)==0
 seeds=blue&(body_probability<.65)&exterior
 candidates=exterior&(body_probability<.8)&(rgb[:,:,2]>20)&(rgb[:,:,2]>=rgb[:,:,0])&(rgb[:,:,2]>=rgb[:,:,1])
 mask=ndi.binary_propagation(seeds,mask=candidates)
 labels,count=ndi.label(mask)
 sizes=np.bincount(labels.ravel());sizes[0]=0
 mask=np.isin(labels,np.flatnonzero(sizes>30))
 if idx<30 or idx>48:mask[:]=False
 rgba=np.array(cut)
 fabric=blue&(~exterior)
 keyed=np.asarray(matte(im,True))
 rgba[fabric]=keyed[fabric]
 rgba[:,:,3][mask]=0
 fx=np.zeros_like(rgb,dtype=np.uint8);fx[mask]=rgb[mask].astype(np.uint8)
 Image.fromarray(rgba).save(out/f'body_{n:02d}.png')
 Image.fromarray(fx).save(out/f'fx_{n:02d}.png')
 audit.append({'source_frame':idx,'duration_ms':ms,'fx_pixels':int(mask.sum())})
 for light in previews:
  bg=Image.new('RGBA',im.size,'#d6e1eb' if light else '#182536');bg.alpha_composite(Image.fromarray(rgba))
  composite=np.clip(np.asarray(bg)[:,:,:3].astype(np.uint16)+fx,0,255).astype(np.uint8)
  previews[light].append(Image.fromarray(composite).resize((512,512),Image.Resampling.LANCZOS))
 print(n,idx,ms,int(mask.sum()),flush=True)
durations=[ms for _,ms in timeline]
for light,pics in previews.items():
 # A pause between demonstrations is not part of the attack duration.
 pics[0].save(out/('light.webp' if light else 'dark.webp'),save_all=True,append_images=pics[1:]+[pics[-1]],duration=durations+[650],loop=0,lossless=True)
sheet=Image.new('RGB',(1280,640),'#182536')
for j,n in enumerate([4,6,8,9,10]):
 for row,light in enumerate([False,True]):
  pic=previews[light][n].resize((256,256));sheet.paste(pic,(j*256,row*320+30))
  ImageDraw.Draw(sheet).text((j*256+8,row*320+8),f'frame {timeline[n][0]} / {timeline[n][1]} ms',fill='white')
sheet.save(out/'contact.png')
(out/'timing.json').write_text(json.dumps({'duration_ms':sum(durations),'idle_ms':650,'frames':audit},indent=2))
print('DONE',sum(durations),'ms',flush=True)
