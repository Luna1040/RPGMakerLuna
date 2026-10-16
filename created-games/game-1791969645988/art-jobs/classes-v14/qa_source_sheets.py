from PIL import Image,ImageDraw
from pathlib import Path
for role in ['sword','yinyang','shadow','celestial']:
 source=Path('art-jobs')/f'class-{role}-source-v14'
 sheet=Image.new('RGB',(1536,820),'#18242c'); draw=ImageDraw.Draw(sheet)
 for i,frame in enumerate([0,8,16,24,32,40,48,55]):
  with Image.open(source/f'{frame:05d}.png') as image:
   tile=image.convert('RGB').resize((384,384))
   x=i%4*384; y=i//4*410
   sheet.paste(tile,(x,y)); draw.text((x+8,y+385),f'{role} source {frame}',fill='white')
 sheet.save(Path('art-jobs/classes-v14')/(role+'-source-review.jpg'))
