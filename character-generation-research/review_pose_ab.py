"""Technical alpha QA, chroma-key postprocessing and unretouched frame previews."""
from pose_ab_test import OUT,LIMBS,COLORS
from PIL import Image,ImageDraw
import numpy as np,json,base64

def key_green(path):
 im=Image.open(path).convert('RGB');rgb=np.asarray(im).astype(np.float32)
 r,g,b=rgb[:,:,0],rgb[:,:,1],rgb[:,:,2]
 excess=g-np.maximum(r,b)
 # Our knight has no green materials. Ramp suppresses antialiased green edges.
 removal=np.clip((excess-6)/22,0,1)*np.clip((g-5)/25,0,1)
 alpha=1-removal
 cleaned=rgb.copy();cleaned[:,:,1]=np.minimum(g,np.maximum(r,b)+15+65*alpha)
 rgba=np.dstack([cleaned,alpha*255]).clip(0,255).astype(np.uint8)
 result=Image.fromarray(rgba,'RGBA');target=path.with_name(path.name.replace('-green','-rgba'));result.save(target)
 return target

def checker(size,dark=True):
 im=Image.new('RGBA',(size,size),'#202735' if dark else '#fafafa');d=ImageDraw.Draw(im)
 for y in range(0,size,24):
  for x in range(0,size,24):
   if (x//24+y//24)%2:d.rectangle((x,y,x+23,y+23),fill='#2c3545' if dark else '#dddddd')
 return im

def review():
 for f in OUT.glob('*-green.png'):key_green(f)
 stats={};poses=json.loads((OUT/'poses.json').read_text())
 for route in ['gpt','controlnet','refined']:
  files=[OUT/(f'gpt-{x}.png' if route=='gpt' else f'local-refined-{x}-rgba.png' if route=='refined' else f'controlnet-{x}-rgba.png') for x in ['A','M','B']]
  if not all(f.exists() for f in files):continue
  frames=[];sheet=Image.new('RGB',(1536,552),'#171e2a');d=ImageDraw.Draw(sheet)
  for i,(phase,f) in enumerate(zip(['A','M','B'],files)):
   im=Image.open(f).convert('RGBA');a=np.array(im.getchannel('A'))
   stats[f.name]={'size':im.size,'alpha_min':int(a.min()),'alpha_max':int(a.max()),'transparent_fraction':float((a==0).mean()),'partial_alpha_fraction':float(((a>0)&(a<255)).mean()),'alpha_bbox':im.getchannel('A').getbbox(),'alpha_bbox_above_32':Image.fromarray((a>32).astype(np.uint8)*255).getbbox(),'edge_pixels_alpha_above_32':int((a[0,:]>32).sum()+(a[-1,:]>32).sum()+(a[:,0]>32).sum()+(a[:,-1]>32).sum())}
   small=im.resize((512,512),Image.Resampling.LANCZOS);bg=checker(512);bg.alpha_composite(small);frames.append(bg.convert('RGB'))
   sheet.paste(bg.convert('RGB'),(i*512,40));d.text((i*512+16,12),route+' / '+phase,fill='white')
   overlay=bg.copy();od=ImageDraw.Draw(overlay);j=np.array(poses[phase]['openpose18'])*.5
   for (u,v),color in zip(LIMBS,COLORS):od.line([tuple(j[u]),tuple(j[v])],fill=color,width=2)
   for q in j:od.ellipse((q[0]-3,q[1]-3,q[0]+3,q[1]+3),fill='white')
   overlay.save(OUT/f'{route}-{phase}-overlay.png')
   light=checker(512,False);light.alpha_composite(small);light.save(OUT/f'{route}-{phase}-light.png')
  sheet.save(OUT/f'{route}-contact.png')
  frames[0].save(OUT/f'{route}-keyframes.gif',save_all=True,append_images=frames[1:],duration=[550,220,800],loop=0)
 (OUT/'alpha-audit.json').write_text(json.dumps(stats,indent=2))
 print(json.dumps(stats,indent=2))
if __name__=='__main__':review()
