from pathlib import Path
import sys
sys.path[:0]=[str(Path('character-generation-research/h3-runtime/matte-deps').resolve()),str(Path('character-generation-research/h3-runtime/deps').resolve())]
from PIL import Image,ImageDraw
root=Path('created-games/moontide-bistro');files=sorted((root/'evidence/motion').glob('*.png'))
canvas=Image.new('RGB',(1120,700),'#10282b');d=ImageDraw.Draw(canvas)
frames=[]
for i,p in enumerate(files):
 im=Image.open(p).crop((575,465,725,630)).resize((210,231));frames.append(im)
 if i%2==0:
  j=i//2;canvas.paste(im,(j%4*280+30,j//4*350+30));d.text((j%4*280+30,j//4*350+275),str(i),fill='white')
canvas.save(root/'evidence/v2-motion-contact.jpg')
frames[0].save(root/'evidence/v2-motion-preview.gif',save_all=True,append_images=frames[1:],duration=81,loop=0)
