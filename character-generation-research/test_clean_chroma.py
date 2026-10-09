from pathlib import Path
import sys,json,time,hashlib
sys.path.insert(0,str(Path(__file__).resolve().parent))
from run_h3_smoke import ROOT,api,graph
from PIL import Image,ImageDraw
import numpy as np
from scipy.ndimage import label,binary_dilation

out=ROOT/'chroma-test';out.mkdir(exist_ok=True)
source=ROOT.parent/'comfy-results/v2-master.png'
im=Image.open(source).convert('RGB');rgb=np.asarray(im).astype(float)
candidate=(rgb.max(2)-rgb.min(2)<27)&(rgb.mean(2)>165)
labels,count=label(candidate)
# These are semantic annotations on ONE master, not per-frame corrections.
# The old edge flood fill could never reach these enclosed background islands.
holes=[(440,169,466,217),(311,232,342,264),(295,327,303,356),(341,346,359,383)]
remove=labels==labels[0,0]
for x0,y0,x1,y1 in holes:
 region=labels[y0:y1,x0:x1];ids,counts=np.unique(region[region>0],return_counts=True)
 chosen=int(ids[np.argmax(counts)]);remove|=labels==chosen
# Remove neutral antialiased contamination immediately adjoining the mask.
fringe=binary_dilation(remove)&(~remove)&((rgb.max(2)-rgb.min(2))<35)&(rgb.mean(2)>120)
alpha=np.where(remove|fringe,0,255).astype(np.uint8)
cut=Image.fromarray(np.dstack([rgb.astype(np.uint8),alpha]));cut.save(out/'clean-master.png')
canvas=Image.new('RGBA',(1024,1024),(0,255,0,255));canvas.alpha_composite(cut.resize((640,640),Image.Resampling.LANCZOS),(192,192))
canvas.convert('RGB').save(out/'clean-green-reference.png')
canvas.convert('RGB').save(next(ROOT.glob('ComfyUI-*'))/'input/knight-clean-green.png')
(out/'master-mask.json').write_text(json.dumps({'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'background_hole_boxes':holes,'removed_pixels':int(remove.sum()),'note':'Single master annotation; never remove all white pixels (silver armor must survive).'},indent=2))
sheet=Image.new('RGB',(1024,512),'#142133')
for col,pic in enumerate([Image.open(ROOT/'padded-green-reference.png').convert('RGB'),canvas.convert('RGB')]):
 sheet.paste(pic.crop((350,240,560,465)).resize((480,480)),(col*512,30))
ImageDraw.Draw(sheet).text((12,8),'OLD MASTER',fill='white');ImageDraw.Draw(sheet).text((524,8),'CLEAN MASTER',fill='white')
sheet.save(out/'reference-comparison.png')
g=graph('walk');g.pop('5');g['1']['inputs']['image']='knight-clean-green.png';g['7']['inputs']['model']=['3',0]
g['10']['inputs'].update(model=['3',0],steps=20,scheduler='normal');g['8']['inputs']['noise_seed']=731430
g['6']['inputs'].update(width=768,height=768,prompt='The adult female fantasy knight in <Picture 1> on the SAME SOLID BRIGHT GREEN BACKGROUND as the reference. Keep this background green in every frame, including every gap between strands of hair and between hair and neck. Single color flat RGB 0,255,0 chroma key backdrop, no black background, no white background, no grey fills in hair gaps. The knight makes a subtle standing breathing loop and gently shifts her head and shoulders; her ponytail and cape sway slightly. Preserve exactly the illustrated face, blonde ponytail, blue cape, silver and gold armor and sword. Entire body, cape and sword within frame, fixed camera, same centered composition. Crisp illustration. No rim lighting, no green lighting on the character, no ground, no shadows, no particles, no magic effects, no text. Silent.')
g['14']['inputs']['filename_prefix']='chroma-clean-green';g['15']['inputs']['filename_prefix']='frames/chroma-clean-green'
(out/'green-api.json').write_text(json.dumps(g,indent=2))
job=api('/prompt',{'prompt':g,'client_id':'clean-chroma-test'});(out/'green-job.json').write_text(json.dumps(job));print('QUEUED',job,flush=True)
while True:
 h=api('/history/'+job['prompt_id'])
 if job['prompt_id'] in h:
  record=h[job['prompt_id']];(out/'green-history.json').write_text(json.dumps(record,indent=2));print(record['status'],flush=True);break
 time.sleep(10)
