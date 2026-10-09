from pathlib import Path
import json,time,urllib.request,shutil
ROOT=Path(__file__).resolve().parent/'h3-runtime'
URL='http://127.0.0.1:9316'
def api(route,data=None):
 req=urllib.request.Request(URL+route,data=json.dumps(data).encode() if data is not None else None,headers={'Content-Type':'application/json'})
 return json.load(urllib.request.urlopen(req,timeout=60))
def graph(action):
 g={}
 def n(i,t,**v):g[str(i)]={'class_type':t,'inputs':v}
 n(1,'LoadImage',image='knight-reference.png')
 n(2,'CLIPLoader',clip_name='qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors',type='minimax',device='default')
 n(3,'UNETLoader',unet_name='minimax_h3_ref2va_pruned_fp8_scaled.safetensors',weight_dtype='default')
 n(4,'VAELoader',vae_name='minimax_h3_video_vae_fp16.safetensors')
 n(5,'LoraLoaderModelOnly',model=['3',0],lora_name='minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors',strength_model=1.0)
 motion={'walk':'She walks briskly in place facing right. Alternating full steps with heel strike and toe off, natural weight transfer through hips, subtle torso rotation and vertical bounce, head follows the torso naturally. Arms counter-swing, ponytail and cape lag and sway. Repeat several coherent walking cycles.', 'attack':'She performs one complete sword slash facing right: settles her weight, bends her knees, winds her torso and lifts the sword, then drives with her hips and shoulders into a diagonal downwards slash, follows through and returns to a ready stance. Her head, torso, hips, arms and legs coordinate as one whole body. Hair and cape follow through.'}[action]
 prompt='The adult female fantasy knight in <Picture 1>, preserve her illustrated art style, face, blonde ponytail, blue cape, silver and gold armor, boots and full length sword. '+motion+' Fixed side view camera, full body visible with ample margin around her hair, feet and sword. Single character centered on perfectly uniform bright green chroma key background. Flat illustrated colors and crisp edges. Each frame is sharply drawn without motion blur. No camera movement, no scene changes, no text, no floor shadow. Silent.'
 n(6,'MiniMaxH3ReferenceToVideo',clip=['2',0],vae=['4',0],prompt=prompt,width=512,height=640,length=124,ref_image_size='match',**{'ref_images.ref_image_0':['1',0]})
 n(7,'BasicGuider',model=['5',0],conditioning=['6',0])
 n(8,'RandomNoise',noise_seed=731420)
 n(9,'KSamplerSelect',sampler_name='res_multistep')
 n(10,'BasicScheduler',model=['5',0],scheduler='simple',steps=4,denoise=1.0)
 n(11,'SamplerCustomAdvanced',noise=['8',0],guider=['7',0],sampler=['9',0],sigmas=['10',0],latent_image=['6',1])
 n(12,'VAEDecodeTiled',samples=['11',0],vae=['4',0],tile_size=384,overlap=64,temporal_size=32,temporal_overlap=8)
 n(13,'CreateVideo',images=['12',0],fps=24.0)
 n(14,'SaveVideo',video=['13',0],filename_prefix='h3-'+action,format='mp4',**{'format.codec':'h264'})
 n(15,'SaveImage',images=['12',0],filename_prefix='frames/'+action)
 return g
if __name__=='__main__':
 import sys
 action=sys.argv[1] if len(sys.argv)>1 else 'walk'
 core=next(ROOT.glob('ComfyUI-*'));(core/'input').mkdir(exist_ok=True)
 shutil.copyfile(ROOT.parent/'comfy-results/v2-master.png',core/'input/knight-reference.png')
 g=graph(action);(ROOT/(action+'-api.json')).write_text(json.dumps(g,indent=2),encoding='utf-8')
 try:result=api('/prompt',{'prompt':g,'client_id':'h3-local-test'})
 except urllib.error.HTTPError as e:print(e.read().decode(),flush=True);raise
 (ROOT/(action+'-job.json')).write_text(json.dumps(result,indent=2))
 print('QUEUED',result,flush=True);pid=result['prompt_id'];start=time.time()
 while True:
  history=api('/history/'+pid)
  if pid in history:
   record=history[pid];(ROOT/(action+'-history.json')).write_text(json.dumps(record,indent=2))
   print('RESULT',json.dumps(record),flush=True);break
  print('RUNNING',round(time.time()-start),'seconds',flush=True);time.sleep(20)
