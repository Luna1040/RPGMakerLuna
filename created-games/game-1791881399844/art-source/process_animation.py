from pathlib import Path
import json,sys,time,hashlib
ROOT=next(p for p in Path(__file__).resolve().parents if (p/'character-generation-research').is_dir())
sys.path.insert(0,str(ROOT/'character-generation-research/h3-runtime/matte-deps'))
import numpy as np
from PIL import Image,ImageDraw
import onnxruntime as ort
kind=sys.argv[1]
job=ROOT/'.game-assistant/starfall-art'/(kind+'-v1')
records=json.loads((job/'output-index.json').read_text())
files=[job/'outputs'/x['file'] for x in records if x['file'].endswith('.png')]
out=ROOT/'created-games/game-1791881399844/assets/h3-v1'/kind
out.mkdir(parents=True,exist_ok=True)
raw=ROOT/'created-games/game-1791881399844/art-source'/kind/'rgba-frames'
raw.mkdir(parents=True,exist_ok=True)
opts=ort.SessionOptions();opts.intra_op_num_threads=6
session=ort.InferenceSession(str(ROOT/'character-generation-research/h3-runtime/matte-v2/birefnet-lite.onnx'),sess_options=opts,providers=['CPUExecutionProvider'])
indices=np.linspace(4,len(files)-5,40,dtype=int).tolist()
frames=[];start=time.time()
for count,index in enumerate(indices):
 im=Image.open(files[index]).convert('RGB');rgb=np.asarray(im).astype(np.float32)/255
 x=np.asarray(im.resize((1024,1024),Image.Resampling.BILINEAR)).astype(np.float32)/255
 x=(x-np.array([.485,.456,.406],np.float32))/np.array([.229,.224,.225],np.float32)
 y=session.run(None,{session.get_inputs()[0].name:x.transpose(2,0,1)[None]})[-1].squeeze()
 if y.min()<0 or y.max()>1: y=1/(1+np.exp(-np.clip(y,-30,30)))
 a=np.clip(np.asarray(Image.fromarray(y.astype('float32')).resize(im.size,Image.Resampling.BILINEAR)),0,1)
 yy,xx=np.indices(a.shape)
 if kind in ('gate','station','gate-open'):
  # The portal's dark inner universe is part of the opaque object, not an alpha hole.
  a[(xx-384)**2+(yy-384)**2<175**2]=1
 lum=rgb.max(axis=2)
 a=np.minimum(a,np.clip((lum-.008)/.055,0,1))
 if kind=='ship':
  # Separate cyan ion light from dark ship material. Preserve low-opacity exhaust.
  glow=(xx<350)&(rgb[:,:,1]>rgb[:,:,0]*1.4)&(rgb[:,:,2]>rgb[:,:,0]*1.4)&(lum>.018)
  a[glow]=np.maximum(a[glow],lum[glow])
 color=np.clip(rgb/np.maximum(a[:,:,None],.04),0,1)
 rgba=Image.fromarray(np.dstack((color*255,a*255)).astype('uint8'),'RGBA')
 rgba.save(raw/f'{count:03d}.png');frames.append(rgba)
 if count%8==0: print(kind,count,'seconds',round(time.time()-start),flush=True)
# Fixed source canvas and pivot across all frames. No per-frame bbox recentering.
size=384;atlas=Image.new('RGBA',(8*size,5*size))
for i,im in enumerate(frames): atlas.alpha_composite(im.resize((size,size),Image.Resampling.LANCZOS),(i%8*size,i//8*size))
atlas.save(out/'atlas.png')
# Crossfade end/start at runtime; preserve chronological video frames rather than reverse playback.
manifest={'kind':kind,'canvas':[768,768],'pivot':[384,384],'tile':size,'columns':8,'frames':len(frames),'fps':8,'source_indices':indices,'duration_ms':125,'loop_crossfade_frames':4,'method':'BiRefNet CPU + black-edge correction; portal interior retained; ion exhaust alpha restored','source_video_sha256':hashlib.sha256((job/'outputs/00124.mp4').read_bytes()).hexdigest()}
(out/'manifest.json').write_text(json.dumps(manifest,indent=2))
review=Image.new('RGB',(1200,600),'#10202b')
for j,idx in enumerate([0,8,16,24,32,39]):
 for row,bg in enumerate(['#10202b','#e5e7eb']):
  layer=Image.new('RGBA',(768,768),bg);layer.alpha_composite(frames[idx]);layer.thumbnail((200,200));review.paste(layer.convert('RGB'),(j*200,row*300))
review.save(raw/'contact.jpg',quality=94)
frames[0].resize((384,384)).save(raw/'loop.webp',save_all=True,append_images=[f.resize((384,384)) for f in frames[1:]],duration=125,loop=0,lossless=True)
print('DONE',kind,round(time.time()-start),flush=True)
