"""Recover atlas parts across old tile boundaries without repainting pixels."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json
ROOT = Path(__file__).resolve().parent
A = ROOT / 'assets'
atlas = Image.open(A/'knight-parts-v1.png').convert('RGBA')
old = json.loads((A/'parts.json').read_text(encoding='utf-8'))['parts']
metadata_path = A/'corrections.json'
metadata = json.loads(metadata_path.read_text(encoding='utf-8')) if metadata_path.exists() else {}
for name, roi, world_height, pivot in [
    ('hair',(627,0,940,374),108,(.86,.10)),
    ('cape_blue',(940,0,1254,375),116,(.94,.07)),
    ('torso_blue',(313,0,627,374),78,(.5,.02)),
    ('head',(0,0,313,374),60,(.51,.94)),
]:
    region = atlas.crop(roi)
    bounds = region.getchannel('A').point(lambda a:255 if a>140 else 0).getbbox()
    assert bounds and bounds[3] < region.height, 'ROI still cuts source contour'
    x,y,w,h = old[name]['source_rect']
    gx,gy = roi[0]+bounds[0],roi[1]+bounds[1]
    piece = region.crop(bounds)
    pad = 4
    out = Image.new('RGBA',(piece.width+pad*2,piece.height+pad*2))
    out.paste(piece,(pad,pad))
    out.save(A/(name+'-v2.png'))
    # Preserve the original pixel scale and attachment in atlas coordinates.
    anchor=(x+pivot[0]*w, y+pivot[1]*h)
    metadata[name]={'asset':name+'-v2','height':world_height*out.height/h,
      'pivot':[(anchor[0]-gx+pad)/out.width,(anchor[1]-gy+pad)/out.height],
      'source_rect':[gx,gy,piece.width,piece.height], 'size':list(out.size),
      'recovered_rows':gy+piece.height-(y+h),'empty_border':pad,
      'original_pixel_scale':world_height/h}
(A/'corrections.json').write_text(json.dumps(metadata,indent=2),encoding='utf-8')
print(json.dumps(metadata,indent=2))
