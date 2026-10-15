from pathlib import Path
import sys
sys.path[:0]=[str(Path('character-generation-research/h3-runtime/matte-deps').resolve()),str(Path('character-generation-research/h3-runtime/deps').resolve())]
from PIL import Image
root=Path('created-games/moontide-bistro/art-jobs')
out=root/'v2-static-source'; out.mkdir(exist_ok=True)
for name,job,rect in [('server','server-clean',(300,20,760,1010)),('guest','guest',(290,25,670,1010)),('chef','chef',(320,35,760,1005)),('table','table',(80,145,980,930))]:
 im=Image.open(root/f'v2-{job}/outputs/00000.png').convert('RGB').crop(rect)
 canvas=Image.new('RGB',(1024,1024),'black'); im.thumbnail((780,850),Image.Resampling.LANCZOS)
 canvas.paste(im,((1024-im.width)//2,930-im.height)); canvas.save(out/f'{name}.png')
im=Image.open(root/'v2-food/outputs/00000.png').convert('RGB')
for name,rect in [('salmon',(25,160,495,450)),('maki',(540,155,1005,450)),('yuzu',(70,540,415,990)),('water',(540,610,1005,990))]:
 crop=im.crop(rect);crop.thumbnail((800,800),Image.Resampling.LANCZOS)
 canvas=Image.new('RGB',(1024,1024),'black');canvas.paste(crop,((1024-crop.width)//2,(1024-crop.height)//2));canvas.save(out/f'{name}.png')
