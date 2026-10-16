from pathlib import Path
import numpy as np
from PIL import Image
root=Path('created-games/game-1791881399844');out=root/'assets/h3-v1/explosion'
a=np.asarray(Image.open(out/'atlas.png').convert('RGB')).astype(np.float32)
# H3 emits a faint grey floor even for requested black backgrounds. Remove it before additive compositing.
for i in range(40):
 x=i%8*384;y=i//8*384
 tile=a[y:y+384,x:x+384]
 yy,xx=np.indices((384,384)); edge=np.minimum.reduce([xx,yy,383-xx,383-yy])
 fade=np.clip(edge/28,0,1);fade=fade*fade*(3-2*fade)
 a[y:y+384,x:x+384]=np.clip(tile-14,0,255)*fade[:,:,None]
Image.fromarray(a.astype('uint8'),'RGB').save(out/'atlas.png')
