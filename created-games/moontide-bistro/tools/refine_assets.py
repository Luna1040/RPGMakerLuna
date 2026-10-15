from pathlib import Path
import sys,shutil
sys.path[:0]=[str(Path('character-generation-research/h3-runtime/matte-deps').resolve()),str(Path('character-generation-research/h3-runtime/deps').resolve())]
from PIL import Image
root=Path('created-games/moontide-bistro/art-jobs');out=root/'v2-refined-source';out.mkdir(exist_ok=True)
shutil.copyfile(root/'v2-guest-seated/outputs/00000.png',out/'seated.png')
im=Image.open(root/'v2-food-clean/outputs/00000.png').convert('RGB')
for i,name in enumerate(['salmon','maki','yuzu','water']):
 crop=im.crop(((i%2)*512,(i//2)*512,(i%2+1)*512,(i//2+1)*512))
 canvas=Image.new('RGB',(768,768),'black'); canvas.paste(crop,(128,128));canvas.save(out/(name+'.png'))
