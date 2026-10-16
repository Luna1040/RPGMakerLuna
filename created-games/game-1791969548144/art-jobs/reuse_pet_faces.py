"""Read-only extraction of the two verified client eudemon portraits."""
from pathlib import Path
import json,sys,hashlib,re
sys.path.insert(0,str(Path(__file__).parent))
from client_map_assets import ROOT,extract
P=Path(__file__).resolve().parents[1]
JOB=P/'art-jobs/client-pets-20261015'
JOB.mkdir(exist_ok=True)
OUT=P/'assets/client_pets';OUT.mkdir(exist_ok=True)
records=json.loads((P/'art-jobs/client-canosa-20261015/asset-index.json').read_text(encoding='utf-8'))
description=(ROOT/'ini/EudBookDes.ini').read_text(encoding='gb18030')
manifest=[]
for kind in [1071020,1071220]:
 name=f'data/petface/128/face{kind}.dds'
 record=records[name];record[0]=Path(record[0]);data=extract(record)
 (OUT/f'{kind}.dds').write_bytes(data)
 section=re.search(r'\['+str(kind)+r'\](.*?)(?=\[|$)',description,re.S).group(1)
 manifest.append(dict(type_id=kind,source=name,sha256=hashlib.sha256(data).hexdigest(),description=section.strip()))
(JOB/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print('Extracted two original DDS portraits, unchanged bytes; no image generation required.')
