from pathlib import Path
import sys,json,time
sys.path.insert(0,str(Path(__file__).resolve().parent))
from run_h3_smoke import ROOT,api,graph

out=ROOT/'map-jump';out.mkdir(exist_ok=True)
g=graph('walk');g.pop('5')
g['1']['inputs']['image']='knight-clean-green.png'
g['7']['inputs']['model']=['3',0]
g['10']['inputs'].update(model=['3',0],steps=20,scheduler='normal')
g['8']['inputs']['noise_seed']=831409
g['6']['inputs'].update(width=768,height=768,prompt='The adult female knight in <Picture 1> performs ONE complete vertical jump in place: start standing facing right, bend both knees and lower her hips into a clear anticipation crouch, push off with both feet, rise with bent knees and boots tucked beneath her hips, reach the apex with both feet clearly off the ground, extend her legs to descend, land on both feet bending her knees to absorb the impact, then stand back up. Her head, shoulders, torso, hips, arms, long ponytail and blue cape all respond naturally to the jump. Keep her long sword held diagonally downward in her right hand throughout; no slash, no attack and no magic. Preserve the beautiful illustrated face, blonde ponytail, silver and gold armor, blue cape, boots and full length sword exactly. Fixed side three quarter view facing right, fixed camera. Whole body and sword always visible, ample empty space above and on both sides, character occupies central 55 percent of canvas height. Clean detailed illustrated game sprite animation. Solid uniform pure black background, no floor, no ground shadow, no scenery, no text, no lighting changes. Silent.')
g['14']['inputs']['filename_prefix']='map-jump'
g['15']['inputs']['filename_prefix']='frames/map-jump'
(out/'workflow.json').write_text(json.dumps(g,indent=2))
job=api('/prompt',{'prompt':g,'client_id':'map-jump'});(out/'job.json').write_text(json.dumps(job));print('QUEUED',job,flush=True)
while True:
 h=api('/history/'+job['prompt_id'])
 if job['prompt_id'] in h:
  r=h[job['prompt_id']];(out/'history.json').write_text(json.dumps(r,indent=2));print(r['status'],flush=True);break
 time.sleep(10)
