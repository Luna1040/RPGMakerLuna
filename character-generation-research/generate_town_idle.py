"""Local H3 town idle clips; preserve source art, export constant-canvas RGBA."""
from pathlib import Path
import sys, json, time, urllib.request
sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_h3_smoke import ROOT, api, graph
from PIL import Image, ImageDraw
OUT = ROOT/'town-idle-v1'
DEST = ROOT.parent.parent/'godot-belt-map/assets/npcs'
OUT.mkdir(exist_ok=True)
NPCS = {
 'innkeeper': 'The adult auburn-haired innkeeper woman in <Picture 1>, wearing the same white blouse and green and cream long dress. She performs a relaxed welcoming idle gesture: smiles at an arriving guest, raises her right hand to shoulder height and waves a clear friendly greeting twice, then extends an open palm toward the side inviting the guest inside her inn, gives a small welcoming nod and returns her hand to its original resting position. Her shoulders, elbows, head and torso participate naturally; skirt and hair sway gently. Both feet stay planted in the same place. She ends in the same relaxed pose as the beginning.',
 'smith': 'The adult male blacksmith in <Picture 1>, preserve his exact face, hair, beard, work apron, clothing and tools. He performs a relaxed workshop idle gesture: lifts the hammer already held in his right hand up in front of his chest, looks down at the metal hammer head and wipes it twice with the cloth from his left hand, checks the cleaned head with a small wrist turn, then lowers the hammer and cloth back to their original resting positions and looks toward the visitor. The hammer remains a rigid solid object with the same handle and head throughout; the cloth stays in the other hand. His head, shoulders, chest and elbows participate naturally. Both feet stay planted in the same place. He ends in the same relaxed pose as the beginning.'
}

def generate():
 core = next(ROOT.glob('ComfyUI-*'))
 for n,(name,motion) in enumerate(NPCS.items()):
  if (OUT/(name+'-history.json')).exists(): continue
  q=api('/queue')
  if q['queue_running'] or q['queue_pending']: raise RuntimeError('Queue occupied')
  source=Image.open(DEST/(name+'.png')).convert('RGBA')
  crop=source.crop(source.getbbox());crop.thumbnail((440,640),Image.Resampling.LANCZOS)
  ref=Image.new('RGBA',(768,768),(0,0,0,255));ref.alpha_composite(crop,((768-crop.width)//2,704-crop.height))
  ref.convert('RGB').save(core/'input'/('town-'+name+'.png'))
  g=graph('walk');g.pop('5')
  g['1']['inputs']['image']='town-'+name+'.png'
  g['7']['inputs']['model']=['3',0]
  g['10']['inputs'].update(model=['3',0],steps=20,scheduler='normal')
  g['8']['inputs']['noise_seed']=910301+n
  g['6']['inputs'].update(width=768,height=768,length=124,prompt=motion+' Preserve the detailed hand-painted illustrated game character design. Full body, fixed camera and scale, all hair hands and feet visible throughout. A single cohesive character, natural anatomy, crisp details. Uniform pure black background, no floor, no scenery, no shadows, no text, no camera movement or zoom, no walking away, no extra people. Silent.')
  g['14']['inputs']['filename_prefix']='town-idle-'+name
  g['15']['inputs']['filename_prefix']='frames/town-idle-'+name
  (OUT/(name+'-workflow.json')).write_text(json.dumps(g,indent=2))
  job=api('/prompt',{'prompt':g,'client_id':'town-idle-v1'})
  (OUT/(name+'-job.json')).write_text(json.dumps(job))
  print('QUEUED',name,job,flush=True)
  while True:
   h=api('/history/'+job['prompt_id'])
   if job['prompt_id'] in h:
    result=h[job['prompt_id']]
    if result['status']['status_str']!='success': raise RuntimeError(result['status'])
    (OUT/(name+'-history.json')).write_text(json.dumps(result))
    print('GENERATED',name,flush=True);break
   time.sleep(10)
 req=urllib.request.Request('http://127.0.0.1:9316/free',data=b'{"unload_models":true,"free_memory":true}',headers={'Content-Type':'application/json'})
 urllib.request.urlopen(req,timeout=60).read()

def export():
 import numpy as np
 from biref_h3_matte import session,extract
 s=session()
 for name in NPCS:
  files=sorted((ROOT/'output/frames').glob('town-idle-'+name+'_*.png'))
  assert len(files)==124,(name,len(files))
  folder=DEST/(name+'-idle');folder.mkdir(exist_ok=True)
  frames=[];images=[];bounds=[]
  for i,source in enumerate(range(0,124,3)):
   raw=Image.open(files[source]).convert('RGB');cut=extract(s,raw)
   path=folder/f'{i:03d}.png';cut.save(path)
   bounds.append(cut.getbbox());images.append(cut)
   frames.append({'file':name+'-idle/'+path.name,'source_frame':source})
  b=np.median(np.array(bounds),axis=0)
  info={'frames':frames,'frame_ms':125,'pivot':[float((b[0]+b[2])/2),float(b[3])], 'scale':264.0/float(b[3]-b[1]),'source':'H3 local HQ 20 steps'}
  (DEST/(name+'-idle.json')).write_text(json.dumps(info,indent=2))
  sheet=Image.new('RGB',(1536,384*3),'#172536');draw=ImageDraw.Draw(sheet)
  for n,i in enumerate(range(0,len(images),4)):
   bg=Image.new('RGBA',(768,768),'#172536');bg.alpha_composite(images[i]);bg=bg.resize((384,384))
   sheet.paste(bg,(n%4*384,n//4*384));draw.text((n%4*384+5,n//4*384+5),str(i),fill='white')
  sheet.save(OUT/(name+'-review.jpg'))
  previews=[]
  for cut in images:
   bg=Image.new('RGBA',(768,768),'#172536');bg.alpha_composite(cut);previews.append(bg.resize((384,384)))
  previews[0].save(OUT/(name+'-preview.webp'),save_all=True,append_images=previews[1:],duration=125,loop=0)
  print('EXPORTED',name,info['pivot'],info['scale'],flush=True)

if __name__=='__main__':
 generate();export()
