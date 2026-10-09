"""Assemble generated keyframes for inspection, without synthetic inbetweening."""
from pathlib import Path
from PIL import Image, ImageOps, ImageDraw
p=Path(__file__).parent/'comfy-results'
names=['v3b-attack-A.png','gpt-between-50.png','gpt-key-B.png']
frames=[Image.open(p/n).convert('RGB').resize((512,512),Image.Resampling.LANCZOS) for n in names]
frames[0].save(p/'gpt-three-key-review.gif',save_all=True,append_images=frames[1:],duration=[600,250,900],loop=0)
sheet=Image.new('RGB',(1536,550),'#202632')
d=ImageDraw.Draw(sheet)
for i,(frame,label) in enumerate(zip(frames,['A - START (local Flux)','M - INBETWEEN (GPT image)','B - END (GPT image)'])):
    sheet.paste(frame,(i*512,38)); d.text((i*512+15,12),label,fill='white')
sheet.save(p/'gpt-three-key-review.png')
print(p/'gpt-three-key-review.gif')
