from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import numpy as np,json
ROOT=Path(__file__).resolve().parent
project=ROOT.parent/'godot-first-knight';out=ROOT/'h3-runtime/character-set'
clips=json.loads((project/'assets/animations.json').read_text())
names={'stand':'站立 · 呼吸','idle':'闲置 · 整理头发','walk':'移动 · 步行','attack1':'一段 · 下劈','attack2':'二段 · 突刺','attack3':'三段 · 上挑','cast':'施法 · 掌心释放','hurt':'受击 · 恢复'}
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',23)
small=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',16)
prepared={}
for name in names:
 clip=clips[name];prepared[name]=[]
 for rec in clip['frames']:
  im=Image.open(project/'assets'/rec['file']).convert('RGBA')
  bg=Image.new('RGBA',im.size,'#142133');bg.alpha_composite(im)
  if 'fx' in rec:
   fx=np.asarray(Image.open(project/'assets'/rec['fx']).convert('RGB')).astype(np.uint16)
   bg=Image.fromarray(np.clip(np.asarray(bg)[:,:,:3].astype(np.uint16)+fx,0,255).astype('uint8'))
  prepared[name].append(bg.convert('RGB').resize((320,320),Image.Resampling.LANCZOS))
frames=[]
for t in range(0,4000,50):
 sheet=Image.new('RGB',(1280,820),'#0c1522');d=ImageDraw.Draw(sheet)
 d.text((24,15),'首个角色 · 八种动作',font=font,fill='#ecf3fa')
 d.text((820,23),'H3 → 透明帧 → 动作时序 → Godot',font=small,fill='#89adc6')
 for j,(name,title) in enumerate(names.items()):
  clip=clips[name];pause=0 if name in ['stand','walk','idle'] else 650
  elapsed=t%(clip['duration_ms']+pause);cursor=elapsed;index=len(clip['frames'])-1
  for i,rec in enumerate(clip['frames']):
   cursor-=rec['duration_ms']
   if cursor<0:index=i;break
  x=j%4*320;y=j//4*380+60
  sheet.paste(prepared[name][index],(x,y+40))
  d.text((x+16,y+5),title,font=font,fill='#dceaf6')
  d.line((x+18,y+360,x+302,y+360),fill='#294259',width=3)
  d.line((x+18,y+360,x+18+284*min(1,elapsed/clip['duration_ms']),y+360),fill='#73c8ed',width=3)
 frames.append(sheet)
frames[0].save(out/'complete-character.webp',save_all=True,append_images=frames[1:],duration=50,loop=0,quality=85,method=4)
frames[7].save(out/'complete-character.jpg',quality=95)
cards=''.join(f'<article><h2>{title}</h2><img src="{name}.webp"><p>{clips[name]["duration_ms"]/1000:.3f} 秒 · {len(clips[name]["frames"])} 帧</p></article>' for name,title in names.items())
html='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>首个角色 · 完整动作</title><style>body{font:16px system-ui;background:#0c1522;color:#edf4fa;max-width:1400px;margin:32px auto;padding:0 24px}p{color:#a3bfd1}section{display:grid;grid-template-columns:repeat(4,1fr);gap:16px}article{background:#182536;border-radius:12px;overflow:hidden}h2,article p{padding:0 16px;font-size:18px}img{width:100%}@media(max-width:800px){section{grid-template-columns:repeat(2,1fr)}}</style><h1>首个角色 · 动作与战斗机制</h1><p>同一参考角色，本地 H3 生成全身动作，透明帧导入 Godot。攻击按独立帧时长播放。</p><p>游戏：A/D 移动 · J 三段连击 · K 施法 · H 受击 · R 重置 · Tab 自动展示。角色完整流程见工作区 CHARACTER_PIPELINE.md。</p><section>'''+cards+'</section></html>'
(out/'index.html').write_text(html,encoding='utf-8')
print('SHOWCASE READY',out/'complete-character.webp')
