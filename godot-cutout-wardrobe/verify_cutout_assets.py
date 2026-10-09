"""Validate source extraction separately from rendered-frame clipping."""
from pathlib import Path
from PIL import Image
import json
ROOT = Path(__file__).resolve().parent
A = ROOT/'assets'
fixes=json.loads((A/'corrections.json').read_text(encoding='utf-8'))
atlas=Image.open(A/'knight-parts-v1.png').convert('RGBA')
checks=[]
for name,fix in fixes.items():
    img=Image.open(A/(fix['asset']+'.png')).convert('RGBA')
    box=img.getchannel('A').getbbox()
    assert box and min(box[0],box[1],img.width-box[2],img.height-box[3])>=4, name
    assert img.width!=img.height, 'Parts must retain their native rectangular bounds'
    if 'recovered_rows' in fix:
        x,y,w,h=fix['source_rect']
        assert img.crop((4,4,4+w,4+h)).tobytes()==atlas.crop((x,y,x+w,y+h)).tobytes()
        assert fix['recovered_rows']>0
    checks.append({'part':name,'empty_border':True,'native_size':list(img.size),
                   'source_pixels_preserved': 'recovered_rows' in fix})
(ROOT/'preview/asset-verification.json').write_text(json.dumps(checks,indent=2),encoding='utf-8')
print('ASSET_VERIFY_PASS',len(checks))
