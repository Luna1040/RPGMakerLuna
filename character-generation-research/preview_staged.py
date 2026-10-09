from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
root=Path(__file__).resolve().parent/'comfy-results'
names=['A','AC','C','CD','D']
labels=['蓄力','过渡 1','击出','过渡 2','收势']
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',21)
sheet=Image.new('RGB',(1600,358),'#14202b');d=ImageDraw.Draw(sheet)
frames=[]
for i,(n,label) in enumerate(zip(names,labels)):
 im=Image.open(root/f'v3b-attack-{n}.png').convert('RGB')
 frame=im.resize((384,384),Image.Resampling.LANCZOS)
 ImageDraw.Draw(frame).text((12,10),label,font=font,fill='#182b40')
 frames.append(frame)
 sheet.paste(im.resize((320,320),Image.Resampling.LANCZOS),(i*320,38));d.text((i*320+10,8),label,font=font,fill='white')
sheet.save(root/'v3b-contact.png')
# Forward action with deliberate end holds; no reversed frames or optical-flow fabrication.
frames[0].save(root/'v3b-attack.gif',save_all=True,append_images=frames[1:],duration=[400,160,160,180,700],loop=0)
Image.open(root/'v3b-attack-A.png').resize((512,512),Image.Resampling.LANCZOS).save(root/'v3b-anticipation-preview.png')
print('PREVIEW_READY')
