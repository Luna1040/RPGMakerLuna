from pathlib import Path
import sys,json
sys.path[:0]=[str(Path('character-generation-research/h3-runtime/matte-deps').resolve()),str(Path('character-generation-research/h3-runtime/deps').resolve())]
from PIL import Image,ImageDraw
root=Path('created-games/moontide-bistro');job=root/'art-jobs/v2-walk-padded'
frames=[r for r in json.loads((job/'output-index.json').read_text()) if r['file'].endswith('.png')]
contact=Image.new('RGB',(1200,800),'#111111');d=ImageDraw.Draw(contact)
for j,i in enumerate(range(0,120,10)):
 im=Image.open(job/'outputs'/frames[i]['file']);im.thumbnail((280,245));x=j%4*300;y=j//4*266;contact.paste(im,(x,y));d.text((x+8,y+245),str(i),fill='white')
contact.save(root/'evidence/v2-walk-padded-source.jpg')
