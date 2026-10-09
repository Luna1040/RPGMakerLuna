from comfy_trials import *
import numpy as np
im=Image.open(OUT/'knight-reference.png').convert('RGBA');a=np.array(im)
rgb=a[:,:,:3].astype(int);mask=(rgb[:,:,2]>rgb[:,:,0]*1.2)&(rgb[:,:,2]>rgb[:,:,1]*1.15)&(rgb[:,:,0]<120)
a[:,:,3]=np.where(mask,0,255).astype('uint8');Image.fromarray(a).save(OUT/'masked-reference.png')
ref=upload(OUT/'knight-reference.png');masked=upload(OUT/'masked-reference.png')
w=json.loads((OUT/'05-outfit-only-workflow.json').read_text())
w['355']['inputs']['image']=ref
w['352']={'class_type':'LoadImage','inputs':{'image':masked}}
w['365']['inputs']['prompt']='Replace the blue fabric with richly shaded crimson red fabric with gold trim. Keep identical folds and silhouette. Original detailed pixel art knight. Change only the blue cape and blue skirt fabric, preserve every other element.'
w['380']={'class_type':'VAEEncode','inputs':{'pixels':['355',0],'vae':['331',0]}}
w['381']={'class_type':'SetLatentNoiseMask','inputs':{'samples':['380',0],'mask':['352',1]}}
w['336']['inputs']['latent_image']=['381',0]
w['382']={'class_type':'ImageCompositeMasked','inputs':{'destination':['355',0],'source':['350',0],'x':0,'y':0,'resize_source':False,'mask':['352',1]}}
w['341']['inputs']={'filename_prefix':'CodexCharacterTrial/06-masked-outfit','images':['382',0]}
(OUT/'06-masked-outfit-workflow.json').write_text(json.dumps(w,indent=2))
job=post('/prompt',{'prompt':w,'client_id':'codex-character-trial'})['prompt_id'];print('SUBMITTED',job,flush=True)
start=time.time()
while time.time()-start<600:
 h=get('/history/'+job)
 if job in h:
  entry=h[job]
  if entry.get('status',{}).get('status_str')=='error':raise RuntimeError(str(entry['status']))
  imgs=entry.get('outputs',{}).get('341',{}).get('images',[])
  if imgs:
   data=urllib.request.urlopen(URL+'/view?'+urllib.parse.urlencode(imgs[0])).read();(OUT/'06-masked-outfit.png').write_bytes(data)
   result=np.array(Image.open(io.BytesIO(data)).convert('RGB'));original=np.array(im.convert('RGB'))
   report={'seconds':round(time.time()-start,1),'pixels_changed_outside_mask':int(np.any(result!=original,axis=2)[~mask].sum()),'mask_pixels':int(mask.sum())}
   (OUT/'06-verification.json').write_text(json.dumps(report,indent=2));print(report);break
 time.sleep(3)
else:raise TimeoutError(job)
