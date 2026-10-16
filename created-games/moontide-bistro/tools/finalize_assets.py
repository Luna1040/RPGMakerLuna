from pathlib import Path
import sys,json
sys.path[:0]=[str(Path('character-generation-research/h3-runtime/matte-deps').resolve()),str(Path('character-generation-research/h3-runtime/deps').resolve())]
from PIL import Image,ImageDraw
import numpy as np
root=Path('created-games/moontide-bistro');assets=root/'assets/v2'
for p in (root/'art-jobs/v2-refined-alpha').glob('*.png'):
 im=Image.open(p).convert('RGBA');box=im.getchannel('A').point(lambda v:255 if v>12 else 0).getbbox()
 im=im.crop((max(0,box[0]-4),max(0,box[1]-4),min(im.width,box[2]+4),min(im.height,box[3]+4)))
 im.save(assets/p.name)
out=root/'art-jobs/v2-walk-clean-alpha';out.mkdir(exist_ok=True)
maxborder=0
for p in (root/'art-jobs/v2-walk-alpha').glob('*.png'):
 a=np.array(Image.open(p).convert('RGBA'))
 maxborder=max(maxborder,int(max(a[0,:,3].max(),a[-1,:,3].max(),a[:,0,3].max(),a[:,-1,3].max())))
 a[:,:,3][a[:,:,3]<8]=0
 assert a[0,:,3].max()==0 and a[-1,:,3].max()==0 and a[:,0,3].max()==0 and a[:,-1,3].max()==0
 Image.fromarray(a).save(out/p.name)
print('Removed background alpha noise; max canvas border alpha:',maxborder)
contact=Image.new('RGB',(1200,600),'#e8e3d9')
for j,i in enumerate([30,36,42,48,54,62,70,78]):
 im=Image.open(out/f'{i:05d}.png');im.thumbnail((280,270));contact.paste(im,((j%4)*300,(j//4)*300),im)
contact.save(root/'evidence/v2-walk-alpha.jpg')
