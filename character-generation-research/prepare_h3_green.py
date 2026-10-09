from pathlib import Path
from PIL import Image
import numpy as np
from scipy.ndimage import binary_propagation
root=Path(__file__).resolve().parent/'h3-runtime'
im=Image.open(root.parent/'comfy-results/v2-master.png').convert('RGB');a=np.asarray(im).astype(float)
candidate=(np.max(a,axis=2)-np.min(a,axis=2)<27)&(a.mean(axis=2)>165)
seed=np.zeros(candidate.shape,bool);seed[0,:]=seed[-1,:]=True;seed[:,0]=seed[:,-1]=True
bg=binary_propagation(seed&candidate,mask=candidate)
rgba=np.dstack([a,255*(~bg)]).astype('uint8');cut=Image.fromarray(rgba,'RGBA')
canvas=Image.new('RGBA',(1024,1024),(0,255,0,255));cut=cut.resize((640,640),Image.Resampling.LANCZOS)
canvas.alpha_composite(cut,(192,192));canvas.convert('RGB').save(next(root.glob('ComfyUI-*'))/'input/knight-green-reference.png')
canvas.save(root/'padded-green-reference.png')
