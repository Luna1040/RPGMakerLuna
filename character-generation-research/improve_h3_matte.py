from pathlib import Path
import numpy as np,json
from PIL import Image,ImageDraw
from scipy.ndimage import binary_propagation,binary_dilation,distance_transform_edt
ROOT=Path(__file__).resolve().parent/'h3-runtime'
OUT=ROOT/'matte-v2';OUT.mkdir(exist_ok=True)
def matte(rgb,soft=True):
 a=np.asarray(rgb).astype(np.float32);v=a.max(axis=2)
 seed=np.zeros(v.shape,bool);seed[0,:]=seed[-1,:]=True;seed[:,0]=seed[:,-1]=True
 bg=binary_propagation(seed&(v<16),mask=v<16,structure=np.ones((3,3)))
 # Black gaps near an external contour can be isolated by a one-pixel bridge.
 near=distance_transform_edt(~bg)<7
 bg|=(v<4)&near
 alpha=(~bg).astype(np.float32)
 if soft:
  outer=binary_dilation(~bg,structure=np.ones((3,3)))&bg
  alpha[outer]=np.clip((v[outer]-4)/20,0,0.6)
  # Undo black premultiplication only for the new fractional silhouette edge.
  frac=(alpha>0)&(alpha<1)
  a[frac]=np.minimum(a[frac]/np.maximum(alpha[frac,None],0.25),255)
 return Image.fromarray(np.dstack([a,alpha*255]).clip(0,255).astype('uint8'),'RGBA')
def compare():
 sheet=Image.new('RGB',(1440,740),'#dbe2eb');d=ImageDraw.Draw(sheet)
 for row,(action,idx,box) in enumerate([('walk-hq',40,(230,140,440,290)),('attack-hq',60,(145,180,450,340))]):
  raw=Image.open(ROOT/'output/frames'/f'{action}_{idx+1:05d}_.png').convert('RGB')
  ims=[Image.open(ROOT/'review'/action/f'{idx:04d}.png'),matte(raw,False),matte(raw,True)]
  for col,(im,title) in enumerate(zip(ims,['OLD: expanded mask','V2: gaps + no expansion','V2: soft outer edge'])):
   bg=Image.new('RGBA',im.size,'#c7d5e7');bg.alpha_composite(im)
   crop=bg.crop(box);crop.thumbnail((470,320));crop=crop.resize((470,320),Image.Resampling.NEAREST)
   sheet.paste(crop,(col*480,row*370+40));d.text((col*480+8,row*370+10),action+' / '+title,fill='#132338')
 sheet.save(OUT/'comparison.png')
if __name__=='__main__':compare()
