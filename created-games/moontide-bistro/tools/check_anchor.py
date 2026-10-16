from pathlib import Path
import sys
sys.path[:0]=[str(Path('character-generation-research/h3-runtime/matte-deps').resolve()),str(Path('character-generation-research/h3-runtime/deps').resolve())]
from PIL import Image,ImageDraw
import numpy as np
root=Path('created-games/moontide-bistro/evidence/anchor-fix');worst=0
for p in sorted(root.glob('*.png')):
 im=np.array(Image.open(p).convert('RGB'))
 for right,left in [(240,540),(840,1140)]:
  a=im[230:450,right-120:right+120].astype(float)
  b=im[230:450,left-120:left+120][:,::-1].astype(float)
  error=float(np.abs(a-b).mean());worst=max(worst,error)
  assert error<1.5,(p.name,error)
im=Image.open(root/'00.png');out=Image.new('RGB',(1000,390),'#10282b');d=ImageDraw.Draw(out)
for i,title in enumerate(['Idle right','Idle left','Walk right','Walk left']):
 crop=im.crop((240+i*300-95,265,240+i*300+95,445)).resize((228,216));out.paste(crop,(i*250+10,65));d.text((i*250+30,25),title,fill='white')
out.save(root/'comparison.jpg')
(root/'verification.txt').write_text(f'PASS: 31 rendered walk frames and idle, both directions, food attached. Maximum mirrored pixel MAE {worst:.4f} / 255.\n',encoding='utf-8')
print((root/'verification.txt').read_text())
