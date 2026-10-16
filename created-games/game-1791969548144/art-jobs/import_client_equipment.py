"""Read-only client item database and original icon reuse; no client code executed."""
from pathlib import Path
import struct,json,sys,hashlib,collections
sys.path.insert(0,str(Path(__file__).parent))
from client_map_assets import ROOT,extract
P=Path(__file__).resolve().parents[1]
JOB=P/'art-jobs/client-equipment-20261015';JOB.mkdir(exist_ok=True)
OUT=P/'assets/client_equipment';OUT.mkdir(exist_ok=True)
b=(ROOT/'ini/itemtype.fdb').read_bytes();nf,nr,ns=struct.unpack_from('<III',b,20);st=len(b)-ns
string=lambda off:b[st+off:b.index(0,st+off)].decode('gb18030')
fields=[string(struct.unpack_from('<I',b,33+i*5)[0]) for i in range(nf)]
fmt='<'+''.join({1:'B',2:'h',3:'H',4:'i',5:'I',8:'Q',10:'I'}[b[32+i*5]] for i in range(nf))
rows=[];crystals=[]
slots={111:'头盔',115:'头盔',121:'项链',125:'项链',131:'护甲',135:'护甲',141:'手镯',145:'手镯',161:'鞋子',165:'鞋子',410:'武器',420:'武器',440:'武器'}
for i in range(nr):
 key,off=struct.unpack_from('<II',b,32+nf*5+i*8);r=dict(zip(fields,struct.unpack_from(fmt,b,off)))
 if key in [1037160,1037170]:
  crystals.append(dict(id=key,name=string(r['szName']),description=string(r['szDesc']),kind='material'))
 if key//1000 not in slots or r['ucRequiredProfession'] not in [10,20] or not 1<=r['ucRequiredLevel']<=35 or r['ucBagType']!=7:continue
 rows.append(dict(id=key,name=string(r['szName']),description=string(r['szDesc']),profession='战士' if r['ucRequiredProfession']==20 else '法师',level=r['ucRequiredLevel'],quality=key%10,family=key//1000,slot=slots[key//1000],physical_min=r['dwMinAttack'],physical_max=r['dwMaxAttack'],magic=r['dwMagicAttack'],defense=r['dwDefense'],magic_defense=r['dwMagicDefence'],source='ini/itemtype.fdb'))
idx=json.loads((JOB.parent/'client-canosa-20261015/asset-index.json').read_text(encoding='utf-8'))
manifest=[];missing=[]
for r in rows+crystals:
 icon_id=r['id']//10*10 if 'quality' in r else r['id']
 names=[f'data/itemminicon/{icon_id}.dds',f'data/itemminicon/{r["id"]}.dds',f'data/mapitemicon/{icon_id}.dds',f'data/itemminicon/{r.get("family",0)*1000}.dds']
 name=next((n for n in names if n in idx),None)
 if name is None:missing.append(r['id']);continue
 dest=OUT/Path(name).name
 if name!=names[0]: r['icon_note']='Original same-family fallback; exact icon absent'
 if not dest.exists():
  record=idx[name];data=extract((Path(record[0]),record[1],record[2]));dest.write_bytes(data)
  (JOB/'source').mkdir(exist_ok=True);(JOB/'source'/dest.name).write_bytes(data)
 if not any(entry['source']==name for entry in manifest): manifest.append(dict(source=name,asset=str(dest.relative_to(P)),sha256=hashlib.sha256(dest.read_bytes()).hexdigest()))
 r['icon']='res://assets/client_equipment/'+dest.name
(OUT/'catalog.json').write_text(json.dumps({'equipment':rows,'materials':crystals},ensure_ascii=False,indent=2),encoding='utf-8')
(JOB/'source-manifest.json').write_text(json.dumps({'database_sha256':hashlib.sha256(b).hexdigest(),'schema':list(zip(fields,[b[32+i*5] for i in range(nf)])),'icons':manifest,'missing_icons':missing,'scope':'1..35 level, profession 10/20, common wearable bag type 7; cosmetic/event appearances excluded'},ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'equipment':len(rows),'base_styles':len({r['id']//10 for r in rows}),'classes':dict(collections.Counter(r['profession'] for r in rows)),'materials':crystals,'missing':missing},ensure_ascii=True))
