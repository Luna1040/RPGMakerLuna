"""Import four more evidenced Canosa NPC appearances; client remains read-only."""
from pathlib import Path
import sys,json,hashlib,re
sys.path.insert(0,str(Path(__file__).parent))
from client_map_assets import ROOT,index,extract
from convert_client_c3 import parse
P=Path(__file__).resolve().parents[1]
JOB=P/'art-jobs/client-npcs-extended-20261015';JOB.mkdir(exist_ok=True)
OUT=P/'assets/client_roles'
models=[603,721,704,719]
wanted={f'c3/npc/{n}/{f}.c3' for n in models for f in [1,100]}
wanted|={f'c3/texture/{n}000000.dds' for n in models}
records={}
for package in ROOT.glob('c3*.tpi'):
 records.update({k:v for k,v in index(package).items() if k in wanted})
manifest=[]
for key,record in records.items():
 data=extract(record);dest=JOB/'source'/key;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
 manifest.append(dict(source=key,sha256=hashlib.sha256(data).hexdigest()))
for n in models:
 parts=parse(JOB/f'source/c3/npc/{n}/1.c3')
 tex=f'c3/texture/{n}000000.dds';name=hashlib.sha256(tex.encode()).hexdigest()[:12]+'.dds'
 (OUT/name).write_bytes((JOB/'source'/tex).read_bytes())
 for part in parts:part['texture']=tex;part['texture_file']=name
 (OUT/f'{n}.json').write_text(json.dumps(parts,separators=(',',':')),encoding='utf-8')
text=(ROOT/'ini/npc.ini').read_text(encoding='gb18030')
coords=(ROOT/'ini/aitalknpc.ini').read_text(encoding='gb18030')
data=json.loads((OUT/'npcs.json').read_text(encoding='utf-8'))
for npc_id in [1052,1060,1823,1055]:
 if any(n['id']==npc_id for n in data):continue
 section=re.search(r'\[NpcType'+str(npc_id)+r'\](.*?)(?=\[|$)',text,re.S).group(1)
 fields={k:v.strip() for k,v in re.findall(r'^([^\r\n=]+)=(.*)',section,re.M)}
 m=re.search(r'npc='+str(npc_id)+r'\s+map=1000\s+x=(\d+)\s+y=(\d+)',coords);x,y=map(int,m.groups())
 data.append(dict(id=npc_id,name=fields['Name'],note=fields.get('Note',''),client_model=fields['SimpleObjID'],client_grid=[x,y],map=1000,pos=[(x-y)*10+4200,(x+y)*5-1900],position_status='provisional isometric origin, nearest clear road correction',dialog_status='role description adapted; original server branches unavailable'))
(OUT/'npcs.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
(JOB/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(JOB/'npc-evidence.json').write_text(json.dumps(data[-4:],ensure_ascii=False,indent=2),encoding='utf-8')
print('Imported four original NPC meshes, rest poses and DDS textures; four source grid records.')
