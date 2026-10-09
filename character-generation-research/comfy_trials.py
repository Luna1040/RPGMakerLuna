import json,time,urllib.request,urllib.parse,uuid,io
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parent
OUT=ROOT/'comfy-results';OUT.mkdir(exist_ok=True)
BASE=Path('C:/Users/11043/Downloads/Flux2_klein_v1.0_普通版/Flux2_klein')
URL='http://127.0.0.1:9315'
def get(route):return json.load(urllib.request.urlopen(URL+route,timeout=30))
def post(route,data):
 req=urllib.request.Request(URL+route,json.dumps(data).encode(),{'Content-Type':'application/json'})
 try:return json.load(urllib.request.urlopen(req,timeout=30))
 except urllib.error.HTTPError as e:raise RuntimeError(e.read().decode())
def upload(p):
 boundary=uuid.uuid4().hex
 body=(f'--{boundary}\r\nContent-Disposition: form-data; name="image"; filename="{p.name}"\r\nContent-Type: image/png\r\n\r\n').encode()+p.read_bytes()+f'\r\n--{boundary}--\r\n'.encode()
 req=urllib.request.Request(URL+'/upload/image',body,{'Content-Type':'multipart/form-data; boundary='+boundary})
 return json.load(urllib.request.urlopen(req,timeout=30))['name']
def reference(filename,name):
 im=Image.open(ROOT.parent/'godot-cutout-wardrobe/preview'/filename).convert('RGBA')
 im=im.crop(im.getchannel('A').getbbox());im.thumbnail((640,640),Image.Resampling.NEAREST)
 canvas=Image.new('RGB',(768,768),'#d8e0e8')
 canvas.paste(im,((768-im.width)//2,680-im.height),im)
 p=OUT/name;canvas.save(p);return upload(p)
def run(name,text,ref,guide=None,size=(768,768),small=False,end=None):
 w=json.loads((BASE/'Flux2Klein_edit.json').read_text(encoding='utf-8'))
 for n in ['352','357','364','371','370','346']:w.pop(n,None)
 w['325']['inputs']['model']=['329',0]
 if small:
  w['329']['inputs']['unet_name']='flux-2-klein-4b-fp8.safetensors'
  w['330']['inputs']['clip_name']='qwen3_4b_fp8_scaled.safetensors'
 w['355']['inputs']['image']=ref
 enc=w['365']['inputs'];enc['prompt']=text;enc['image1']=['355',0];enc.pop('image2',None);enc.pop('image3',None)
 if guide:w['352']={'class_type':'LoadImage','inputs':{'image':guide}};enc['image2']=['352',0]
 if end:w['357']={'class_type':'LoadImage','inputs':{'image':end}};enc['image3']=['357',0]
 for n in ['327','328']:w[n]['inputs']['width'],w[n]['inputs']['height']=size
 w['354']['inputs']['noise_seed']=731420
 w['341']['inputs']['filename_prefix']='CodexCharacterTrial/'+name
 (OUT/(name+'-workflow.json')).write_text(json.dumps(w,indent=2),encoding='utf-8')
 start=time.time();job=post('/prompt',{'prompt':w,'client_id':'codex-character-trial'})['prompt_id']
 (OUT/(name+'-job.json')).write_text(json.dumps({'prompt_id':job}))
 print('SUBMITTED',name,job,flush=True)
 while time.time()-start<600:
  h=get('/history/'+job)
  if job in h:
   entry=h[job]
   if entry.get('status',{}).get('status_str')=='error':raise RuntimeError(str(entry['status']))
   outputs=entry.get('outputs',{}).get('341',{}).get('images',[])
   if outputs:
    for i,img in enumerate(outputs):
     data=urllib.request.urlopen(URL+'/view?'+urllib.parse.urlencode(img),timeout=30).read();(OUT/(name+('.png' if i==0 else f'-{i}.png'))).write_bytes(data)
    print('COMPLETE',name,round(time.time()-start,1),flush=True);return
  time.sleep(3)
 raise TimeoutError('Job remains on ComfyUI; inspect saved prompt_id before retry')
if __name__=='__main__':
 q=get('/queue')
 if q['queue_running'] or q['queue_pending']:raise RuntimeError('Existing user jobs; do not queue experiments yet')
 ref=reference('armor_blue_idle_00.png','knight-reference.png')
 guide=reference('armor_blue_slash_01.png','attack-pose-reference.png')
 style='Same original adult female knight, blonde ponytail, gold crown, silver armor, blue cape, gold trim, same sword length. Detailed crisp pixel art, full body side view facing right, plain solid pale gray background, no text, no motion blur. '
 run('01-direct-pose',style+'Redraw the character in a clearly different attack anticipation pose: sword raised vertically above her head, right arm bent and lifted, left arm naturally bent close to torso, feet spread. Preserve her face and outfit.',ref)
 run('02-four-frame-walk',style+'Create a horizontal four-frame walking sprite strip. Exactly four separate complete figures evenly spaced in four equal columns. Frame1 near leg forward far leg back. Frame2 legs passing. Frame3 near leg back far leg forward. Frame4 opposite passing pose. Same head size and foot baseline throughout. The sword is held low. Do not repeat the same pose. All hair cape sword and feet completely inside each cell.',ref,size=(1536,768))
 run('03-guided-pose',style+'Use image1 for character identity and rendering style. Use image2 only for the raised sword pose and body proportions. Redraw as a coherent single character, with anatomically natural shoulder elbow wrist connections. Keep the sword above the head. Do not copy cutout seams or disconnected limbs from image2.',ref,guide)
