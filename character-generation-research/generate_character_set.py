from pathlib import Path
import sys,json,time
sys.path.insert(0,str(Path(__file__).resolve().parent))
from run_h3_smoke import graph,api,ROOT

MOTIONS={
 'stand':'A relaxed combat-ready standing breathing loop. Feet stay planted. Her chest rises and falls gently, weight shifts subtly through hips, her shoulders and head respond naturally. Small gentle ponytail and cape movement. Sword held comfortably downward. Return to the initial stance. No walking and no attack.',
 'idle':'One charming restrained idle gesture: from a relaxed ready stance she glances sideways, gently brushes a loose strand of hair near her temple with her free hand, then lowers that hand and returns to her ready stance. The sword remains in her other hand. Natural coordinated head, shoulders, torso and hip movement, cape and ponytail follow. No walking, no sword slash.',
 'thrust':'One complete powerful straight sword thrust to the right. Start ready, draw the sword back near her hip while winding shoulders and hips, step into a sharp forward lunge extending the blade horizontally to the right, then withdraw the sword and recover to ready. Clear anticipation, fast extension, full body weight transfer, knees bend, head follows. Keep the same full-length sword throughout.',
 'uppercut':'One complete rising sword slash from low left to high right. Start ready, lower the sword and bend knees to load the hips, drive upward through legs and torso and sweep the blade upward to a high finishing pose, then settle and recover to ready. Feet remain near the same ground location, no jump. Strong shoulder rotation, hair and cape follow through.',
 'cast':'One complete magic casting action while holding her sword in her right hand pointed downward. From ready stance raise the free left hand near her chest to gather magic, turn torso and extend the left palm toward the right to release the spell, then lower the hand and recover to ready. Clear expressive fingers, natural head tracking, balanced weight transfer and coordinated whole-body movement. Draw only the character, no magic particles or light or glowing effects; effects will be added separately in the game.',
 'hurt':'One brief non-graphic combat hit reaction. From a ready stance she recoils backward from an unseen impact from the right, shoulders and head rock back, knees flex to absorb force, then she regains her balance and returns to ready. Keep feet in the same small area. No blood, no wound, no fall and no second character.'
}
if __name__=='__main__':
 out=ROOT/'character-set';out.mkdir(exist_ok=True)
 for k,(action,motion) in enumerate(MOTIONS.items()):
  name='set-'+action;record_path=out/(action+'-history.json')
  if record_path.exists() and json.loads(record_path.read_text())['status']['status_str']=='success' and len(list((ROOT/'output/frames').glob(name+'_*.png')))==124:
   print('REUSE',action,flush=True);continue
  g=graph('attack');g['1']['inputs']['image']='knight-green-reference.png'
  g.pop('5');g['7']['inputs']['model']=['3',0]
  g['10']['inputs'].update(model=['3',0],steps=20,scheduler='normal')
  g['8']['inputs']['noise_seed']=731430+k
  g['6']['inputs'].update(width=768,height=768,prompt='The adult female fantasy knight in <Picture 1>. Preserve the same beautiful illustrated face, blonde ponytail, blue cape, silver and gold armor, boots and long sword, with exactly the same outfit and body proportions. '+motion+' Fixed side view facing right, fixed camera, entire body visible, centered in the same place, broad empty margins around sword, hair, cape and feet. Character occupies the central 60 percent of canvas height. Crisp detailed hand drawn illustration, consistent anatomy from frame to frame. Perfectly uniform solid black background. No floor, no ground shadow, no scenery, no text, no cuts, no camera movement. Silent.')
  g['14']['inputs']['filename_prefix']='h3-'+name
  g['15']['inputs']['filename_prefix']='frames/'+name
  (out/(action+'-api.json')).write_text(json.dumps(g,indent=2))
  job=api('/prompt',{'prompt':g,'client_id':'first-character-set'})
  (out/(action+'-job.json')).write_text(json.dumps(job));print('QUEUED',action,job,flush=True)
  while True:
   h=api('/history/'+job['prompt_id'])
   if job['prompt_id'] in h:
    record=h[job['prompt_id']];record_path.write_text(json.dumps(record,indent=2));print('RESULT',action,record['status'],flush=True)
    if record['status']['status_str']!='success':raise RuntimeError(action+' generation failed')
    break
   time.sleep(10)
 print('ALL GENERATIONS COMPLETE',flush=True)
