"""Check failure modes seen in character cutouts, without invoking generation."""
import sys,json
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import layered_map_trial as trial
from PIL import Image,ImageDraw
import numpy as np
folder=trial.OUT/'matte-unit-check';folder.mkdir(parents=True,exist_ok=True)
im=Image.new('RGB',(128,128),'#ff00ff');d=ImageDraw.Draw(im)
d.rectangle((30,25,98,105),fill='#f0eee8') # white walls must survive
d.rectangle((35,30,92,44),fill='#345b99') # blue must survive without character rescue rules
d.rectangle((48,60,70,79),fill='#ff00ff') # enclosed background must disappear
d.line((98,25,98,70),fill=(246,119,244)) # antialias/contamination fringe
im.save(folder/'raw.png');q=trial.key_asset(folder);a=np.asarray(Image.open(folder/'rgba.png'))
assert a[85,45,3]==255,'White walls were removed'
assert a[35,45,3]==255,'Blue foreground was removed'
assert a[67,58,3]==0,'Enclosed key island retained'
assert a[0,0,3]==0 and q['canvas']==[128,128],'Canvas/border failure'
assert q['enclosedKeyComponentsRemoved']>=1
bad=trial.OUT/'matte-rejection-check';bad.mkdir(exist_ok=True)
Image.new('RGB',(128,128),'white').save(bad/'raw.png')
try:trial.key_asset(bad)
except RuntimeError:pass
else:raise AssertionError('Noncompliant white background accepted')
print('PASS: white/blue preservation, enclosed holes, fringe unmixing, fixed canvas and rejection of nonmagenta background.')
