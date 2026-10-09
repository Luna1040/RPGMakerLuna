from pathlib import Path
import sys,time,json
sys.path.insert(0,str(Path(__file__).resolve().parent))
from biref_h3_matte import ROOT,session,extract
from PIL import Image,ImageDraw
import numpy as np
s=session();summary={};start=time.time()
for action in ['walk-hq','attack-hq']:
 out=ROOT/'matte-v2'/action;out.mkdir(exist_ok=True);frames=[];stats=[]
 for i,p in enumerate(sorted((ROOT/'output/frames').glob(action+'_*.png'))):
  im=Image.open(p).convert('RGB');cut=extract(s,im);cut.save(out/f'{i:04d}.png');frames.append(cut)
  alpha=np.asarray(cut.getchannel('A'));stats.append({'frame':i,'bbox':cut.getbbox(),'transparent':float((alpha==0).mean()),'partial':float(((alpha>0)&(alpha<255)).mean())})
  if i%20==0:print(action,i,'elapsed',round(time.time()-start),flush=True)
 frames[0].save(out/'transparent.webp',save_all=True,append_images=frames[1:],duration=1000/24,loop=0,lossless=True)
 checks=Image.new('RGB',(1536,600),'#c7d5e7');d=ImageDraw.Draw(checks)
 for j,i in enumerate(np.linspace(0,len(frames)-1,12,dtype=int)):
  bg=Image.new('RGBA',frames[i].size,'#c7d5e7');bg.alpha_composite(frames[i]);bg.thumbnail((256,256));checks.paste(bg.convert('RGB'),((j%6)*256,(j//6)*300+30));d.text(((j%6)*256+8,(j//6)*300+7),f'frame {i}',fill='black')
 checks.save(out/'contact.jpg',quality=95)
 summary[action]={'frames':len(frames),'stats':stats}
(ROOT/'matte-v2/audit.json').write_text(json.dumps(summary,indent=2))
html='''<!doctype html><meta charset="utf-8"><title>抠图升级对照</title><style>body{background:#1c2635;color:white;font:16px sans-serif;margin:24px}section{display:flex;gap:12px}figure{margin:0;width:48%;background:repeating-conic-gradient(#c7d5e7 0% 25%,#eef3f9 0% 50%) 0/24px 24px}img{width:100%}figcaption{background:#263344;padding:8px}button{padding:8px;margin:8px}</style><h1>抠图升级对照</h1><p>左：旧抠图。右：BiRefNet + 细缝清理 + 柔边。原始动作、帧尺寸和坐标保持一致。</p><button onclick="document.querySelectorAll('figure').forEach(x=>x.style.background='#ffffff')">白底</button><button onclick="document.querySelectorAll('figure').forEach(x=>x.style.background='#192538')">深色底</button>'''
for a in summary:html+=f'<h2>{a}</h2><section><figure><figcaption>旧版</figcaption><img src="../review/{a}/transparent.webp"></figure><figure><figcaption>升级版</figcaption><img src="{a}/transparent.webp"></figure></section>'
(ROOT/'matte-v2/index.html').write_text(html,encoding='utf-8');print('DONE',round(time.time()-start),flush=True)
