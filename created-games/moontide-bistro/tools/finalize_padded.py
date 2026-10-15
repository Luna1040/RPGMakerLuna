from pathlib import Path
import sys,json
sys.path[:0]=[str(Path('character-generation-research/h3-runtime/matte-deps').resolve()),str(Path('character-generation-research/h3-runtime/deps').resolve())]
from PIL import Image
import numpy as np
root=Path('created-games/moontide-bistro');out=root/'art-jobs/v2-walk-padded-clean';out.mkdir(exist_ok=True)
for p in (root/'art-jobs/v2-walk-padded-alpha').glob('*.png'):
 a=np.array(Image.open(p).convert('RGBA'))
 original=np.array(Image.open(root/'art-jobs/v2-walk-padded-selected'/p.name).convert('RGB'))
 border=np.zeros(a.shape[:2],dtype=bool);border[:8]=True;border[-8:]=True;border[:,:8]=True;border[:,-8:]=True
 assert original[border].max()<8,'Actual content reaches border; reject rather than trim'
 a[:,:,3][border]=0;a[:,:,3][a[:,:,3]<4]=0
 Image.fromarray(a).save(out/p.name)
sel=json.loads((root/'art-jobs/v2-walk-padded-selection.json').read_text())
assert len(list(out.glob('*.png')))==len(sel['frames'])
print('PASS fixed canvas and transparent margin',len(sel['frames']))
for job,name in [('v2-woman-alpha','woman'),('v2-woman-standing-alpha','woman_standing')]:
 paths=list((root/'art-jobs'/job).glob('*.png'))
 if not paths:continue
 im=Image.open(paths[0]).convert('RGBA');box=im.getchannel('A').point(lambda v:255 if v>12 else 0).getbbox()
 im=im.crop((max(0,box[0]-4),max(0,box[1]-4),min(im.width,box[2]+4),min(im.height,box[3]+4)));im.save(root/'assets/v2'/(name+'.png'))
