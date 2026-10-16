from pathlib import Path
import sys
sys.path[:0]=[str(Path('character-generation-research/h3-runtime/matte-deps').resolve()),str(Path('character-generation-research/h3-runtime/deps').resolve())]
from PIL import Image
p=Path('created-games/moontide-bistro')
im=Image.open(p/'assets/v2/server.png').convert('RGBA');im.thumbnail((500,480),Image.Resampling.LANCZOS)
canvas=Image.new('RGB',(768,768),'black');canvas.paste(im,((768-im.width)//2,620-im.height),im)
canvas.save(p/'art-jobs/v2-prompts/walk-reference-padded.png')
