from pathlib import Path
from PIL import Image,ImageDraw
root=Path(r'Z:\RPGMakerLuna\created-games\game-1791969645988')
frames=[0,8,16,22,27,30,34,40,50,65,85,110]
sheet=Image.new('RGB',(4*256,3*276),'#142030')
for j,i in enumerate(frames):
 im=Image.open(root/'art-jobs/bite-source-v5'/f'{i:05d}.png').convert('RGB');im.thumbnail((256,256));sheet.paste(im,(j%4*256,j//4*276));ImageDraw.Draw(sheet).text((j%4*256+6,j//4*276+256),f'SOURCE {i}',fill='white')
sheet.save(root/'art-jobs/combat-v5/bite-source-contact.jpg')
