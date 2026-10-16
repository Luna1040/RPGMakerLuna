from pathlib import Path
import sys,json,numpy as np
from PIL import Image
root=next(p for p in Path(__file__).resolve().parents if (p/'character-generation-research').is_dir())
kind=sys.argv[1];out=root/'created-games/game-1791881399844/assets/h3-v1'/kind
raw=root/'created-games/game-1791881399844/art-source'/kind/'rgba-frames'
source=[Image.open(raw/f'{i:03d}.png').convert('RGBA') for i in range(40)]
# Remove sub-7% segmentation haze with a continuous alpha remap, not a hard black key.
for im in source:
 a=np.asarray(im.getchannel('A'),dtype=np.float32)
 im.putalpha(Image.fromarray(np.clip((a-18)*255/237,0,255).astype('uint8')))
frames=source
mapping=list(range(40))
if kind!='gate-open':
 frames=[];mapping=[]
 for i in range(4):
  t=(i+1)/5
  a=np.asarray(source[36+i],dtype=np.float32)/255;b=np.asarray(source[i],dtype=np.float32)/255
  alpha=a[:,:,3:]*(1-t)+b[:,:,3:]*t
  rgb=(a[:,:,:3]*a[:,:,3:]*(1-t)+b[:,:,:3]*b[:,:,3:]*t)/np.maximum(alpha,.00001)
  frames.append(Image.fromarray((np.concatenate([rgb,alpha],2)*255).clip(0,255).astype('uint8'),'RGBA'));mapping.append({'tail':36+i,'head':i,'weight':t})
 frames+=source[4:36];mapping+=list(range(4,36))
tile=384;atlas=Image.new('RGBA',(8*tile,5*tile))
for i,im in enumerate(frames): atlas.alpha_composite(im.resize((tile,tile),Image.Resampling.LANCZOS),(i%8*tile,i//8*tile))
atlas.save(out/'atlas.png')
manifest=json.loads((out/'manifest.json').read_text());manifest.update({'frames':len(frames),'loop':kind!='gate-open','loop_crossfade_frames':0 if kind=='gate-open' else 4,'playback_mapping':mapping})
(out/'manifest.json').write_text(json.dumps(manifest,indent=2))
frames[0].resize((384,384)).save(raw/'loop.webp',save_all=True,append_images=[f.resize((384,384)) for f in frames[1:]],duration=125,loop=0,lossless=True)
coverage=[];centers=[]
for im in frames:
 a=np.asarray(im.getchannel('A'));y,x=np.where(a>128)
 assert len(x)>0 and a[0,:].max()==0 and a[-1,:].max()==0 and a[:,0].max()==0 and a[:,-1].max()==0,'Frame clips boundary'
 centers.append([float(x.mean()),float(y.mean())]);coverage.append(float((a>0).mean()))
metrics={'frames':len(frames),'transparent_fraction_min':1-max(coverage),'centroid_range':np.ptp(np.array(centers),axis=0).tolist(),'alpha_edges_clear':True}
(out/'qa.json').write_text(json.dumps(metrics,indent=2));print(kind,metrics)
