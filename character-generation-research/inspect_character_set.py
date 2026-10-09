from pathlib import Path
import time
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parent/'h3-runtime'
for action in ['stand','idle','thrust','uppercut','cast','hurt']:
 files=[]
 while len(files)<124:
  files=sorted((ROOT/'output/frames').glob('set-'+action+'_*.png'))
  time.sleep(3)
 # Wait for the last PNG write to finish before reading it.
 time.sleep(2)
 sheet=Image.new('RGB',(1536,768),'#182536');d=ImageDraw.Draw(sheet)
 for j,idx in enumerate([0,10,20,30,40,50,60,70,80,90,110,123]):
  im=Image.open(files[idx]).convert('RGB').resize((256,256))
  x=(j%6)*256;y=(j//6)*384
  sheet.paste(im,(x,y+30));d.text((x+8,y+8),action+' '+str(idx),fill='white')
 (ROOT/'character-set').mkdir(exist_ok=True)
 sheet.save(ROOT/'character-set'/(action+'-raw.jpg'),quality=94)
 print('CONTACT READY',action,flush=True)
