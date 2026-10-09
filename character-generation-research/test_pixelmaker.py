from pathlib import Path
import sys, io, json
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'pixelmaker/addons/pixelmaker/server'))
from app.animations import make_animation
out=ROOT/'results';out.mkdir(exist_ok=True)
source=ROOT.parent/'godot-cutout-wardrobe/preview/armor_blue_idle_00.png'
im=Image.open(source).convert('RGBA')
box=im.getchannel('A').getbbox()
im=im.crop(box)
im.thumbnail((160,160),Image.Resampling.NEAREST)
canvas=Image.new('RGBA',(im.width+32,im.height+32));canvas.paste(im,(16,16))
buf=io.BytesIO();canvas.save(buf,format='PNG');canvas.save(out/'input.png')
report={}
for action in ['walk','attack']:
    r=make_animation(buf.getvalue(),action=action,frames=4,fps_ms=220)
    (out/(action+'.png')).write_bytes(r['sheet_png'])
    frames=[]
    for data in r['frames']:
        f=Image.open(io.BytesIO(data)).convert('RGBA')
        bg=Image.new('RGBA',f.size,'#14202b');bg.alpha_composite(f)
        frames.append(bg.convert('RGB').resize((f.width*2,f.height*2),Image.Resampling.NEAREST))
    frames[0].save(out/(action+'.gif'),save_all=True,append_images=frames[1:],duration=220,loop=0)
    report[action]={k:r[k] for k in ['width','height','frame_count']}
(out/'pixelmaker-test.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report))
