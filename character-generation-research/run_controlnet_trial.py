from comfy_trials import get,post,upload,URL
from pose_ab_test import OUT
import json,time,urllib.request,urllib.parse,sys

def workflow(phase,strength=1.0):
 image=upload(OUT/f'pose-{phase}.png')
 action={'A':'arms up, sword held overhead pointing upper left, wide stance, bent knees','M':'leaning forward, holding sword with both hands in front of chest, sword pointing upper right, bent knees','B':'leaning forward, crouching, both hands low in front of body, downward sword slash, sword pointing lower right'}[phase]
 positive='1girl, adult woman, solo, full body, side view, facing right, blonde hair, high ponytail, blue eyes, small gold crown, female knight, silver plate armor, gold trim, blue pleated skirt, black undersuit, silver armored boots, blue cape, holding one longsword with both hands, '+action+', isolated, (solid bright green background:1.4), chroma key, flat green backdrop, anime illustration, clean lineart, masterpiece, best quality, very aesthetic'
 negative='nsfw, nude, child, multiple people, extra arms, extra legs, extra weapons, missing limbs, cropped, close-up, text, watermark, logo, scenery, grass, trees, green clothing, green hair, ground, floor, cast shadow, gradient background, blurry, worst quality, low quality, bad anatomy'
 def n(t,**kw):return {'class_type':t,'inputs':kw}
 return {'1':n('CheckpointLoaderSimple',ckpt_name='animagine-xl-3.1.safetensors'),
 '2':n('CLIPTextEncode',text=positive,clip=['1',1]),'3':n('CLIPTextEncode',text=negative,clip=['1',1]),
 '4':n('LoadImage',image=image),'5':n('ControlNetLoader',control_net_name='xinsir-openpose-sdxl-1.0.safetensors'),
 '6':n('ControlNetApplyAdvanced',positive=['2',0],negative=['3',0],control_net=['5',0],image=['4',0],strength=strength,start_percent=0.0,end_percent=1.0,vae=['1',2]),
 '7':n('EmptyLatentImage',width=1024,height=1024,batch_size=1),
 '8':n('KSampler',model=['1',0],positive=['6',0],negative=['6',1],latent_image=['7',0],seed=731420,steps=28,cfg=6.0,sampler_name='euler_ancestral',scheduler='normal',denoise=1.0),
 '9':n('VAEDecode',samples=['8',0],vae=['1',2]),'10':n('SaveImage',images=['9',0],filename_prefix='CodexPoseAB/controlnet-'+phase)}
def run(phase,strength=1.0):
 q=get('/queue')
 if q['queue_running'] or q['queue_pending']:raise RuntimeError('ComfyUI busy; existing jobs left alone')
 w=workflow(phase,strength);name='controlnet-'+phase
 (OUT/(name+'-api.json')).write_text(json.dumps(w,indent=2))
 job=post('/prompt',{'prompt':w,'client_id':'codex-pose-ab'})['prompt_id']
 (OUT/(name+'-job.json')).write_text(json.dumps({'prompt_id':job}))
 print('SUBMITTED',phase,job,flush=True);start=time.time()
 while time.time()-start<900:
  h=get('/history/'+job)
  if job in h:
   item=h[job]
   if item.get('status',{}).get('status_str')=='error':raise RuntimeError(str(item['status']))
   images=item.get('outputs',{}).get('10',{}).get('images',[])
   if images:
    data=urllib.request.urlopen(URL+'/view?'+urllib.parse.urlencode(images[0]),timeout=30).read()
    (OUT/(name+'-green.png')).write_bytes(data)
    print('COMPLETE',phase,round(time.time()-start,1),flush=True);return
  time.sleep(3)
 raise TimeoutError('Check saved job id; do not resubmit blindly')
if __name__=='__main__':
 import argparse
 parser=argparse.ArgumentParser();parser.add_argument('phases',nargs='*',default=['A','M','B']);parser.add_argument('--strength',type=float,default=1.0)
 args=parser.parse_args()
 for phase in args.phases:run(phase,args.strength)
