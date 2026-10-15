from pathlib import Path
import sys,json,shutil
sys.path[:0]=[str(Path('character-generation-research/h3-runtime/matte-deps').resolve()),str(Path('character-generation-research/h3-runtime/deps').resolve())]
from PIL import Image,ImageDraw
root=Path('created-games/moontide-bistro')
assets=root/'assets/v2'
for p in (root/'art-jobs/v2-static-alpha').glob('*.png'):
 im=Image.open(p).convert('RGBA'); a=im.getchannel('A'); box=a.point(lambda v:255 if v>12 else 0).getbbox()
 im=im.crop((max(0,box[0]-4),max(0,box[1]-4),min(im.width,box[2]+4),min(im.height,box[3]+4)))
 im.save(assets/p.name)
shutil.copyfile(root/'art-jobs/v2-room-isometric/outputs/00000.png',assets/'room.png')
preview=Image.new('RGB',(1200,600),'#23363a');d=ImageDraw.Draw(preview)
for i,name in enumerate(['server','guest','chef','table','salmon','maki','yuzu','water']):
 im=Image.open(assets/(name+'.png')); im.thumbnail((260,240)); x=(i%4)*300+(300-im.width)//2;y=(i//4)*300+30
 preview.paste(im,(x,y),im);d.text(((i%4)*300+12,(i//4)*300+8),name,fill='white')
preview.save(root/'evidence/v2-assets.jpg')
job=root/'art-jobs/v2-server-walk'; records=json.loads((job/'output-index.json').read_text())
frames=[r for r in records if r['file'].endswith('.png')]
print('source frames',len(frames))
contact=Image.new('RGB',(1200,800),'#111111');d=ImageDraw.Draw(contact)
for j,i in enumerate(range(0,len(frames),max(1,len(frames)//12))):
 if j>=12:break
 im=Image.open(job/'outputs'/frames[i]['file']);im.thumbnail((280,245))
 x=(j%4)*300;y=(j//4)*266;contact.paste(im,(x,y));d.text((x+8,y+245),str(i),fill='white')
contact.save(root/'evidence/v2-walk-source.jpg')
