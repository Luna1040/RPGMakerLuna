"""Export unretouched raw preview and technical green-screen alpha frames."""
from pathlib import Path
import json,sys
import numpy as np
from PIL import Image,ImageDraw
from scipy.ndimage import binary_propagation,binary_dilation
ROOT=Path(__file__).resolve().parent/'h3-runtime'
def export(action):
 files=sorted((ROOT/'output/frames').glob(action+'_*.png'))
 if not files:raise RuntimeError('No rendered frames for '+action)
 out=ROOT/'review'/action;out.mkdir(parents=True,exist_ok=True)
 raw=[];rgba=[];stats=[]
 for i,path in enumerate(files):
  im=Image.open(path).convert('RGB');rgb=np.array(im).astype(np.float32)
  r,g,b=rgb[:,:,0],rgb[:,:,1],rgb[:,:,2]
  excess=g-np.maximum(r,b);remove=np.clip((excess-12)/45,0,1)*np.clip((g-40)/70,0,1)
  alpha=1-remove;clean=rgb.copy();clean[:,:,1]=np.minimum(g,np.maximum(r,b)+20+75*alpha)
  method='green chroma key'
  if np.median(rgb[:40,:40])<15:
   candidate=np.max(rgb,axis=2)<16
   seed=np.zeros(candidate.shape,bool);seed[0,:]=seed[-1,:]=True;seed[:,0]=seed[:,-1]=True
   background=binary_propagation(seed&candidate,mask=candidate)
   alpha=binary_dilation(~background,iterations=1).astype(float)
   clean=rgb;method='edge-connected black removal, one-pixel outline retained'
  cut=Image.fromarray(np.dstack([clean,alpha*255]).clip(0,255).astype('uint8'),'RGBA')
  cut.save(out/f'{i:04d}.png');rgba.append(cut);raw.append(im)
  stats.append({'frame':i,'transparent_fraction':float((alpha==0).mean()),'bbox':cut.getbbox()})
 raw[0].save(out/'raw.webp',save_all=True,append_images=raw[1:],duration=1000/24,loop=0,quality=85)
 rgba[0].save(out/'transparent.webp',save_all=True,append_images=rgba[1:],duration=1000/24,loop=0,lossless=True)
 indices=np.linspace(0,len(raw)-1,12,dtype=int);sheet=Image.new('RGB',(256*6,344*2),'#1c2330');d=ImageDraw.Draw(sheet)
 for j,i in enumerate(indices):
  thumb=raw[i].copy();thumb.thumbnail((256,320));x=(j%6)*256;y=(j//6)*344
  sheet.paste(thumb,(x,y+24));d.text((x+8,y+5),f'frame {i} / {i/24:.2f}s',fill='white')
 sheet.save(out/'contact.jpg',quality=95)
 (out/'audit.json').write_text(json.dumps({'quality_evaluated':False,'frames':len(raw),'fps':24,'alpha_method':method+', preserves original canvas and coordinates','stats':stats},indent=2))
 return action
if __name__=='__main__':
 actions=[export(a) for a in sys.argv[1:] or ['walk']]
 html='''<!doctype html><meta charset="utf-8"><title>H3 角色动作实测</title><style>body{background:#111925;color:#eee;font:16px sans-serif;margin:32px}section{display:flex;gap:24px}img{max-height:70vh;max-width:45vw}figure{margin:0;background:repeating-conic-gradient(#243044 0% 25%,#172131 0% 50%) 0/32px 32px}h2{margin-top:32px}</style><h1>H3 角色动作实测</h1><p>左：原始生成；右：背景移除后的 RGBA。按原始 24fps 播放，未补帧、未修形，也未保证首尾能无缝循环。</p>'''
 for a in actions:html+=f'<h2>{a}</h2><section><figure><img src="{a}/raw.webp"></figure><figure><img src="{a}/transparent.webp"></figure></section><p><a href="{a}/contact.jpg">12 帧对照</a> · <a href="{a}/audit.json">透明度记录</a></p>'
 (ROOT/'review/index.html').write_text(html,encoding='utf-8')
