"""Format generated isolated cutouts, retaining alpha and rectangular bounds."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json,shutil
ROOT=Path(__file__).resolve().parent
A=ROOT/'assets'
jobs=json.loads((ROOT/'correction-jobs.json').read_text(encoding='utf-8'))
fixes=json.loads((A/'corrections.json').read_text(encoding='utf-8'))
for job in jobs:
    name=job['name']
    source=Path(job['path'])
    local_source=A/(name+'-generated-v2.png')
    if source.exists(): shutil.copyfile(source,local_source)
    else: source=local_source
    img=Image.open(source).convert('RGBA')
    bbox=img.getchannel('A').point(lambda a:255 if a>140 else 0).getbbox()
    assert bbox and bbox[0]>0 and bbox[1]>0 and bbox[2]<img.width and bbox[3]<img.height
    img=img.crop(bbox)
    old=Image.open(A/(name+'.png'))
    target_h=old.height
    img=img.resize((round(img.width*target_h/img.height),target_h),Image.Resampling.NEAREST)
    pad=4
    out=Image.new('RGBA',(img.width+pad*2,img.height+pad*2))
    out.paste(img,(pad,pad))
    out.save(A/(name+'-v2.png'))
    world_h=43/.78 if 'thigh' in name else 34/.82
    pivot_y=.1 if 'thigh' in name else .09
    fixes[name]={'asset':name+'-v2','height':world_h*out.height/target_h,
      'pivot':[(img.width*.5+pad)/out.width,(target_h*pivot_y+pad)/out.height],
      'size':list(out.size),'empty_border':pad,'source':str(source),
      'view':'inner leg, knee forward/right' if 'thigh' in name else 'palm toward camera'}
(A/'corrections.json').write_text(json.dumps(fixes,indent=2),encoding='utf-8')
# Large actual-asset before/after comparison; no illustrative substitutes.
canvas=Image.new('RGBA',(1600,820),(24,29,42,255))
d=ImageDraw.Draw(canvas)
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',18)
labels=['发梢','蓝披风','铠甲远手','日常远手','泳装远手','日常远腿','泳装远腿','铠甲远腿']
for col,(name,label) in enumerate(zip(fixes,labels)):
    x=col*200
    d.text((x+10,10),label,font=font,fill='white')
    for row,suffix in enumerate(['','-v2']):
        im=Image.open(A/(name+suffix+'.png')).convert('RGBA')
        scale=min(180/im.width,330/im.height)
        im=im.resize((round(im.width*scale),round(im.height*scale)),Image.Resampling.NEAREST)
        y=55+row*395
        d.text((x+10,y-24),'原版' if row==0 else '修正',font=font,fill=(157,206,225))
        canvas.alpha_composite(im,(x+(200-im.width)//2,y))
canvas.convert('RGB').save(ROOT/'preview/cutout-corrections.png')
prompts='Mode: built-in imagegen, precise-object-edit, transparent background.\n'
for job in jobs: prompts+='\n'+job['name']+'\n'+job['prompt']+'\nFinal: assets/'+job['name']+'-v2.png\n'
(ROOT/'CORRECTION-PROMPTS.txt').write_text(prompts,encoding='utf-8')
print('CORRECTIONS_INSTALLED',len(fixes))
