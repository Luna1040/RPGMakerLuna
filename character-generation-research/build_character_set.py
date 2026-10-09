from pathlib import Path
import sys,time,json,shutil
sys.path.insert(0,str(Path(__file__).resolve().parent))
from biref_h3_matte import ROOT,session,extract
from improve_h3_matte import matte
from PIL import Image,ImageDraw
import numpy as np

DEST=ROOT.parent.parent/'godot-first-knight/assets';DEST.mkdir(parents=True,exist_ok=True)
SPECS=ROOT/'character-set/export-specs.json'

def best_loop(files,min_span,max_span):
 # Match pose and its local direction of movement, not just a static silhouette.
 small=np.stack([np.asarray(Image.open(p).convert('RGB').resize((96,96)),dtype=np.float32) for p in files])
 best=(1e30,0,min_span)
 for start in range(4,min(45,len(files)-max_span-1)):
  for span in range(min_span,max_span+1):
   end=start+span
   pose=np.mean((small[start]-small[end])**2)
   velocity=np.mean(((small[start+1]-small[start])-(small[end+1]-small[end]))**2)
   score=pose+velocity*.3
   if score<best[0]:best=(float(score),start,end)
 return {'start':best[1],'end':best[2],'seam_score':best[0]}

def main():
 actions=[arg for arg in sys.argv[1:] if not arg.startswith('--')] or ['stand','walk','attack1','idle','attack2','attack3','cast','hurt']
 manifest_path=DEST/'animations.json'
 manifest=json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
 s=None
 for action in actions:
  spec=json.loads(SPECS.read_text())[action]
  out=DEST/action;out.mkdir(exist_ok=True)
  pics=[];records=[]
  if action=='attack1':
   timing=json.loads((ROOT/'combat-v1/timing.json').read_text())
   for i,frame in enumerate(timing['frames']):
    filename=f'{action}/{i:03d}.png';fxname=f'{action}/fx_{i:03d}.png'
    shutil.copyfile(ROOT/'combat-v1'/f'body_{i:02d}.png',DEST/filename)
    shutil.copyfile(ROOT/'combat-v1'/f'fx_{i:02d}.png',DEST/fxname)
    records.append(dict(frame,file=filename,fx=fxname));pics.append(Image.open(DEST/filename).convert('RGBA'))
   first=Image.open(ROOT/'matte-v2/attack-hq/0000.png').convert('RGBA')
  else:
   files=sorted((ROOT/'output/frames').glob(spec['source']+'_*.png'))
   if len(files)!=124:raise RuntimeError(f'{action}: expected 124 source frames, got {len(files)}')
   if 'loop' in spec:
    loop=best_loop(files,*spec['loop']);print('LOOP',action,loop,flush=True)
    indices=list(range(loop['start'],loop['end'],spec.get('stride',2)))
    durations=[spec['frame_ms']]*len(indices)
    spec['loop_selection']=loop
   else:
    indices=spec['indices'];durations=spec['durations']
   suffix='-v3' if action=='cast' else ('-v2' if action=='hurt' else '')
   cache=ROOT/'character-set/mattes'/(spec['source']+suffix);cache.mkdir(parents=True,exist_ok=True)
   def cut_frame(idx):
    nonlocal s
    cached=cache/f'{idx:04d}.png'
    if cached.exists():return Image.open(cached).convert('RGBA')
    if action=='walk':return Image.open(ROOT/'matte-v2/walk-hq'/f'{idx:04d}.png').convert('RGBA')
    if s is None:s=session(use_gpu='--gpu' in sys.argv)
    im=Image.open(files[idx]).convert('RGB');cut,body_probability=extract(s,im,return_mask=True)
    # No detached glow is requested for these character clips. Retain navy
    # fabric where the original alpha model would make blue cloth translucent.
    rgb=np.asarray(im).astype(np.float32);rgba=np.array(cut)
    blue=(rgb[:,:,2]>40)&(rgb[:,:,2]-rgb[:,:,0]>18)&(rgb[:,:,2]-rgb[:,:,1]>7)
    yy,xx=np.indices(rgb.shape[:2])
    dark_fabric=blue&(rgb.max(axis=2)<125)&(xx<450)&(yy>280)&(yy<510)
    if action=='hurt':
     dark_fabric|=(rgb[:,:,2]>18)&(rgb[:,:,2]-rgb[:,:,0]>8)&(rgb[:,:,2]-rgb[:,:,1]>3)&(rgb.max(axis=2)<125)&(xx<405)&(yy>300)&(yy<570)
    key=np.asarray(matte(im,True));rgba[dark_fabric]=key[dark_fabric]
    if action=='cast' and 43<=idx<=64:
     # The generator added a bolt despite the no-effects prompt. Keep the hand
     # glow but remove the detached bolt; the game launches it independently.
     distance=np.sqrt((xx-535)**2+(yy-270)**2)
     region=((xx>550)&(yy<360))|((xx>500)&(body_probability<.8)&blue)
     remove=np.clip((distance-20)/50,0,1)*region
     rgba[:,:,3]=(rgba[:,:,3]*(1-remove)).astype(np.uint8)
    cut=Image.fromarray(rgba);cut.save(cached);return cut
   first=cut_frame(0)
   start=time.time()
   for i,(idx,ms) in enumerate(zip(indices,durations)):
    cut=cut_frame(idx);filename=f'{action}/{i:03d}.png';cut.save(DEST/filename)
    records.append({'source_frame':idx,'duration_ms':ms,'file':filename});pics.append(cut)
    if i%8==0:print('MATTE',action,i,'/',len(indices),'seconds',round(time.time()-start),flush=True)
  alpha=np.asarray(first)[:,:,3]
  yy,xx=np.where(alpha>180)
  floor=int(np.percentile(yy,99.7));top=int(yy.min())
  foot_x=float(np.median(xx[yy>floor-30]))
  # One fixed transform per action. Never resize or recenter each frame.
  pivot=spec.get('pivot',[round(foot_x,2),floor])
  scale=spec.get('scale',420/max(1,floor-top))
  manifest[action]={'frames':records,'duration_ms':sum(r['duration_ms'] for r in records),'pivot':pivot,'scale':scale,'source':spec.get('source','combat-v1')}
  if action=='cast':
   bolt=np.asarray(Image.open(ROOT/'output/frames/set-cast_00046_.png').convert('RGB').crop((550,200,725,330))).astype(np.float32)
   by,bx=np.indices(bolt.shape[:2]);edge=np.minimum.reduce([bx,by,bolt.shape[1]-1-bx,bolt.shape[0]-1-by])
   bolt*=np.clip(edge/16,0,1)[:,:,None]
   Image.fromarray(bolt.astype(np.uint8)).save(DEST/'magic_bolt.png')
  for key in ['event_ms','damage','range','loop_selection','release_offset']:
   if key in spec:manifest[action][key]=spec[key]
  manifest_path.write_text(json.dumps(manifest,indent=2))
  preview=[]
  for i,pic in enumerate(pics):
   bg=Image.new('RGBA',pic.size,'#182536');bg.alpha_composite(pic)
   if 'fx' in records[i]:
    color=np.asarray(bg)[:,:,:3].astype(np.uint16)
    fx=np.asarray(Image.open(DEST/records[i]['fx']).convert('RGB')).astype(np.uint16)
    bg=Image.fromarray(np.clip(color+fx,0,255).astype(np.uint8))
   preview.append(bg.convert('RGB').resize((384,384),Image.Resampling.LANCZOS))
  preview[0].save(ROOT/'character-set'/(action+'.webp'),save_all=True,append_images=preview[1:],duration=[r['duration_ms'] for r in records],loop=0,lossless=True)
  sheet=Image.new('RGB',(1536,512),'#d2deea');draw=ImageDraw.Draw(sheet)
  for j,i in enumerate(np.linspace(0,len(pics)-1,6,dtype=int)):
   bg=Image.new('RGBA',pics[i].size,'#d2deea');bg.alpha_composite(pics[i]);bg=bg.resize((256,256))
   sheet.paste(bg,(j*256,40));draw.text((j*256+5,12),f'{action} src {records[i]["source_frame"]}',fill='black')
  sheet.save(ROOT/'character-set'/(action+'-matte.jpg'),quality=95)
  print('EXPORTED',action,len(records),manifest[action]['duration_ms'],'ms',pivot,scale,flush=True)
if __name__=='__main__':main()
