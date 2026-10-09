from pathlib import Path
import sys
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parent/'h3-runtime'
out=root/'map-combat-motion'
for action in sys.argv[1:] or ['run','dash_attack','air_slash']:
 files=sorted((root/'output/frames').glob('map-'+action+'_*.png'))
 if len(files)!=124:continue
 sheet=Image.new('RGB',(1536,1152),'#182536');d=ImageDraw.Draw(sheet)
 for i,idx in enumerate(range(0,124,4)):
  im=Image.open(files[idx]).convert('RGB').resize((192,192))
  x=(i%8)*192;y=(i//8)*256
  sheet.paste(im,(x,y));d.text((x+5,y+193),str(idx),fill='white')
 sheet.save(out/(action+'-raw-sheet.jpg'))
