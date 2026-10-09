"""Reproducible serial H3 full-body motion generation for the map knight."""
from pathlib import Path
import sys,json,time
sys.path.insert(0,str(Path(__file__).resolve().parent))
from run_h3_smoke import ROOT,api,graph

out=ROOT/'map-combat-motion';out.mkdir(exist_ok=True)
motions={
 'run': 'She RUNS FAST IN PLACE facing right through several seamless repeating sprint cycles. Strong forward lean from her whole torso, vigorous alternating high knee drives and powerful backward leg extension, clearly visible airborne stride phases, the left and right feet alternate naturally. Her hips and shoulders counter rotate, her head follows the subtle whole body rise and fall, her ponytail and cape stream behind her. Her sword arm holds the full length sword safely angled backward while the other arm pumps. She keeps running at a steady fast pace throughout. The character stays in the same location on the canvas; treadmill running, no camera tracking.',
 'dash_attack': 'She performs ONE rapid powerful forward sword dash attack facing right. First compress her legs and lean forward with the sword drawn back. Then explosively push off the rear foot into a low forward lunge, extend the sword arm and full length sword horizontally toward the right into a strong piercing thrust while her torso and head follow through. Finish in a deep forward lunge with front knee bent, then recover to her original ready standing stance. Her hips, shoulders, head, arms and legs move together with clear anticipation, explosive release and recovery; ponytail and cape trail behind. Her body remains near the center of the canvas with only a small forward displacement; keep the complete sword tip visible.',
 'air_slash': 'She performs ONE aerial descending sword strike facing right. First jump straight upward with knees tucked and raise her full length sword high above her head with both arms. At the jump apex wind her torso backward with the sword overhead. Then forcefully swing the long sword down in front of her in a vertical chopping motion while descending, lean her whole torso and head into the powerful downward slash. Land with knees deeply bent and sword tip low toward the right, then recover to her standing ready stance. Her hips, shoulders, head, arms and legs coordinate naturally, ponytail and cape follow through. Clearly show overhead anticipation, downward strike and crouched landing. No energy trails or sparks.'
}
for k in sys.argv[1:] or list(motions):
 g=graph('walk');g.pop('5');g['1']['inputs']['image']='knight-clean-green.png'
 g['7']['inputs']['model']=['3',0]
 g['10']['inputs'].update(model=['3',0],steps=20,scheduler='normal')
 g['8']['inputs']['noise_seed']=dict(run=831421,dash_attack=831422,air_slash=831423)[k]
 g['6']['inputs'].update(width=768,height=768,prompt='The adult female knight in <Picture 1>. '+motions[k]+' Preserve her beautiful detailed illustrated face, blonde ponytail, silver and gold armor, blue cape, boots and FULL LENGTH sword exactly. Fixed side three quarter view facing right, fixed camera, no zoom. Whole body, hair, cape and sword always visible with ample empty space above and on both sides. Character occupies central 55 percent of canvas height. Clean detailed illustrated game sprite animation with crisp edges. Solid uniform pure black background, no floor, no ground shadow, no scenery, no text, no lighting changes, no motion blur, no magical effects or sword trails. Silent.')
 g['14']['inputs']['filename_prefix']='map-'+k
 g['15']['inputs']['filename_prefix']='frames/map-'+k
 (out/(k+'-workflow.json')).write_text(json.dumps(g,indent=2))
 job=api('/prompt',{'prompt':g,'client_id':'map-combat-motion'});(out/(k+'-job.json')).write_text(json.dumps(job));print('QUEUED',k,job,flush=True)
 while True:
  h=api('/history/'+job['prompt_id'])
  if job['prompt_id'] in h:
   r=h[job['prompt_id']];(out/(k+'-history.json')).write_text(json.dumps(r,indent=2));print('FINISHED',k,r['status'],flush=True)
   if r['status']['status_str']!='success':raise RuntimeError(k+' failed')
   break
  time.sleep(10)
# /free returns an empty successful HTTP response, unlike the JSON routes.
import urllib.request
req=urllib.request.Request('http://127.0.0.1:9316/free',data=json.dumps({'unload_models':True,'free_memory':True}).encode(),headers={'Content-Type':'application/json'})
with urllib.request.urlopen(req,timeout=60) as response:response.read()
print('ALL DONE; H3 released',flush=True)
