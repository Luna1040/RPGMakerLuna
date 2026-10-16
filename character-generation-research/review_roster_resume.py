"""Contact sheets and explicit review selections for resumed roster production."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from PIL import Image, ImageDraw
import npc_roster_v1 as n

def contact(key, action, indices, suffix='dense'):
    paths = n.source_paths(key, action)
    out = Image.new('RGB', (1536, ((len(indices)+3)//4)*400), '#162536')
    d = ImageDraw.Draw(out)
    for pos, index in enumerate(indices):
        x, y = pos%4*384, pos//4*400
        out.paste(Image.open(paths[index]).resize((384,384)), (x,y+16))
        d.text((x+5,y), f'{key}/{action} {index}', fill='white')
    target=n.OUT/'review'/f'{key}-{action}-{suffix}.jpg'
    out.save(target,quality=96)

if __name__ == '__main__':
    contact('elite','attack',[20,24,28,32,36,40,48,54,58,60,62,64,66,70,76,84])
    contact('boss','attack',[28,32,36,40,44,48,54,58,60,62,64,66,68,70,76,84])
    contact('caster','attack',[21,24,28,34,38,40,42,46,50,66,82,88,94,102])
    contact('caster','hurt',[8,10,12,14,16,20,24,28,32,100,104,108,112,116,120,123])
