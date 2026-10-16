"""Import original treecity PUZZLE2 layout and unchanged native DDS tiles."""
from pathlib import Path
import sys,json,struct,re,hashlib
from PIL import Image
sys.path.insert(0,str(Path(__file__).parent))
from client_map_assets import ROOT,extract
P=Path(__file__).resolve().parents[1];JOB=P/'art-jobs/client-recovery-20261015';OUT=P/'assets/client_treecity';OUT.mkdir(exist_ok=True)
b=(JOB/'treecity.pul').read_bytes();assert b[:8]==b'PUZZLE2\0'
w,h=struct.unpack_from('<II',b,264);cells=list(struct.unpack_from('<'+'H'*(w*h),b,272))
ani=(ROOT/'ani/treecity.ani').read_text(encoding='gb18030')
lookup={int(n):path.strip().lower().replace('\\','/') for n,path in re.findall(r'\[Puzzle(\d+)\]\s*FrameAmount=\d+\s*Frame0=([^\r\n]+)',ani)}
records=json.loads((P/'art-jobs/client-canosa-20261015/asset-index.json').read_text(encoding='utf-8'))
overview=Image.new('RGBA',(w*32,h*32),(25,39,34,255));manifest=[];tiles={}
for tile_id in sorted(set(cells)-{65535}):
 source=lookup[tile_id];record=records[source];record[0]=Path(record[0]);data=extract(record)
 filename=f'{tile_id}.dds';(OUT/filename).write_bytes(data)
 image=Image.open(OUT/filename).convert('RGBA');assert image.size==(128,128),(source,image.size)
 tiles[tile_id]=image.resize((32,32))
 manifest.append(dict(id=tile_id,source=source,sha256=hashlib.sha256(data).hexdigest()))
for i,tile in enumerate(cells):
 if tile!=65535:overview.alpha_composite(tiles[tile],((i%w)*32,(i//w)*32))
overview.convert('RGB').save(OUT/'overview.jpg',quality=95)
overview.save(JOB/'treecity-layout-review.png')
layout=dict(map_id=2000,name='\u6811\u5fc3\u57ce',columns=w,rows=h,tile_size=128,size=[w*128,h*128],cells=cells)
(OUT/'layout.json').write_text(json.dumps(layout,separators=(',',':')),encoding='utf-8')
(JOB/'treecity-manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('Imported original city layout',w,h,'tiles',len(manifest),'world',layout['size'])
