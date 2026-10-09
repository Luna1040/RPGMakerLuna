from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import numpy as np
from collections import deque
ROOT=Path(__file__).resolve().parent/'comfy-results'
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20)
labels={'walk':'走路','slash':'挥剑'}
for action in ['walk','slash']:
 frames=[];smallframes=[]
 sheet=Image.new('RGB',(1536,420),'#14202b');draw=ImageDraw.Draw(sheet)
 for i in range(4):
  im=Image.open(ROOT/f'v2-{action}-{i}.png').convert('RGB')
  # Border-connected gray background only; no recoloring or generated-pose repair.
  a=np.asarray(im);bg=np.median(np.concatenate([a[0],a[-1],a[:,0],a[:,-1]]),axis=0)
  eligible=np.max(np.abs(a.astype(float)-bg),axis=2)<38
  flood=Image.fromarray((eligible*255).astype('uint8'))
  for x,y in [(x,edge) for x in range(im.width) for edge in [0,im.height-1]]+[(edge,y) for y in range(im.height) for edge in [0,im.width-1]]:
   if flood.getpixel((x,y))==255:ImageDraw.floodfill(flood,(x,y),128)
  background=np.asarray(flood)==128
  rgba=im.convert('RGBA');rgba.putalpha(Image.fromarray((~background*255).astype('uint8')))
  bbox=rgba.getbbox();scaled=rgba.crop(bbox).resize((round((bbox[2]-bbox[0])*.32),round((bbox[3]-bbox[1])*.32)),Image.Resampling.LANCZOS)
  canvas=Image.new('RGBA',(384,384),'#14202b');canvas.alpha_composite(scaled,((384-scaled.width)//2,365-scaled.height))
  frames.append(canvas.convert('RGB'));sheet.paste(canvas,(384*i,36));draw.text((384*i+16,8),f'{labels[action]} {i+1}',font=font,fill='white')
  # Explicit low-resolution preview, not a claim of hand-authored pixel art.
  small=canvas.resize((128,128),Image.Resampling.LANCZOS).convert('RGB').quantize(colors=48).convert('RGB').resize((384,384),Image.Resampling.NEAREST)
  smallframes.append(small)
 sheet.save(ROOT/f'v2-{action}-contact.png')
 for suffix,seq in [('',frames),('-128px',smallframes)]:seq[0].save(ROOT/f'v2-{action}{suffix}.gif',save_all=True,append_images=seq[1:],duration=240 if action=='walk' else 200,loop=0)
print('PREVIEWS_READY')
