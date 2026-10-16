"""Read-only extraction of explicitly selected local role/NPC asset resources."""
import sys,json,re,struct
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from client_map_assets import ROOT,index,extract
JOB=Path(__file__).resolve().parent/'client-roles-20261015'
JOB.mkdir(exist_ok=True)
wanted={f'c3/npc/{n}/{f}.c3' for n in [738,701,331,707,728,714,729] for f in [1,100,101]}
wanted|={f'c3/select/{n}.{ext}' for n in ['061000000','061000001','069000000','069000001'] for ext in ['c3','dds']}
wanted|={f'c3/select/{n}.{ext}' for n in ['410970','440990'] for ext in ['c3','dds']}
wanted|={f'c3/select/{n}.{ext}' for n in ['061119001','069119001'] for ext in ['c3','dds']}
records={}
for package in sorted(ROOT.glob('c3*.tpi')):
    found=index(package)
    records.update({k:v for k,v in found.items() if k in wanted or any(k.startswith(f'c3/npc/{n}/') for n in [738,701,331,707,728,714,729])})
for name,record in records.items():
    dest=JOB/'source'/name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(extract(record))
    if name.endswith('.c3') and (name.endswith('/1.c3') or '/select/' in name):
        b=dest.read_bytes();p=16;chunks=[]
        while p+8<=len(b):
            tag=b[p:p+4].decode('ascii',errors='replace');size=struct.unpack_from('<I',b,p+4)[0];chunks.append((tag,size));p+=8+size
        print(name,len(b),repr(b[:16]),chunks[:20])
(JOB/'resource-index.json').write_text(json.dumps({k:[str(v[0]),v[1],v[2]] for k,v in records.items()},ensure_ascii=False),encoding='utf-8')
print('extracted',len(records))
