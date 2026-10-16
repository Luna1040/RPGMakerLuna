"""Reuse local C3 geometry and skeletal action keys; no generative art scripts."""
from pathlib import Path
import sys,json,struct,hashlib
import numpy as np
sys.path.insert(0,str(Path(__file__).parent))
from client_map_assets import ROOT,index,extract
from convert_client_c3 import parse
P=Path(__file__).resolve().parents[1]
JOB=P/'art-jobs/client-field-monsters-20261015';JOB.mkdir(exist_ok=True)
OUT=P/'assets/client_roles'
wanted={f'c3/monster/{n}/{a}.c3' for n in [100,110,120] for a in [1,100,101,110]}
wanted|={f'c3/texture/{n}000000.dds' for n in [100,110,120]}
resources={}
for package in ROOT.glob('c3*.tpi'):
 resources.update({k:v for k,v in index(package).items() if k in wanted})
manifest=[]
for key,record in resources.items():
 data=extract(record);dest=JOB/'source'/key;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
 manifest.append(dict(source=key,sha256=hashlib.sha256(data).hexdigest()))

def skin(mesh,matrices):
 vertices=np.asarray(mesh['vertices']);initial=np.asarray(mesh['matrix']).reshape(4,4)
 vec=np.c_[vertices,np.ones(len(vertices))]@initial
 bones=np.asarray(mesh['bones']);weights=np.asarray(mesh['weights'])
 pose=np.asarray(matrices).reshape(-1,4,4)
 result=np.zeros((len(vertices),3))
 for column in range(2):
  valid=bones[:,column]<len(pose)
  result[valid]+=np.einsum('vi,vij->vj',vec[valid],pose[bones[valid,column]])[:,:3]*weights[valid,column,None]
 result[weights.sum(axis=1)==0]=vertices[weights.sum(axis=1)==0]
 return np.round(result,4).tolist()

b=(ROOT/'ini/monster.fdb').read_bytes();nf,nr,ns=struct.unpack_from('<III',b,20);st=len(b)-ns
types=[b[32+i*5] for i in range(nf)]
fmt='<'+''.join('Q' if t==8 else 'I' for t in types)
definitions=[]
for kind,(type_id,look) in enumerate([(1000,100),(1010,110),(1020,120)]):
 for i in range(nr):
  key,offset=struct.unpack_from('<II',b,32+nf*5+i*8)
  if key==type_id:
   values=struct.unpack_from(fmt,b,offset);name=b[st+values[1]:].split(b'\0')[0].decode('gb18030');break
 else:raise ValueError(type_id)
 parts=parse(JOB/f'source/c3/monster/{look}/1.c3')
 texture=f'c3/texture/{look}000000.dds';texture_name=hashlib.sha256(texture.encode()).hexdigest()[:12]+'.dds'
 (OUT/texture_name).write_bytes((JOB/'source'/texture).read_bytes())
 clips={}
 for action,number in [('idle',100),('walk',101),('attack',110)]:
  motions=parse(JOB/f'source/c3/monster/{look}/{number}.c3',True)
  motion=max(motions,key=lambda m:m['bones']);keys=motion['keys'];duration=max(.3,motion['frames']/30)
  frames=[];source_frames=[]
  for time in np.linspace(0,max(0,motion['frames']-1),min(18,len(keys)),endpoint=True):
   key=min(keys,key=lambda k:abs(k['frame']-time));source_frames.append(key['frame'])
   frames.append([skin(part,key['matrices']) for part in parts])
  clips[action]=dict(duration=duration,frames=frames,source_frames=source_frames,source=f'c3/monster/{look}/{number}.c3',hit_fraction=.42 if action=='attack' else None)
 for i,part in enumerate(parts):
  part['posed_vertices']=clips['idle']['frames'][0][i];part['texture_file']=texture_name;part['texture']=texture
 (OUT/f'mob{look}.json').write_text(json.dumps(parts,separators=(',',':')),encoding='utf-8')
 (OUT/f'mob{look}-actions.json').write_text(json.dumps(clips,separators=(',',':')),encoding='utf-8')
 definitions.append(dict(kind=kind,type_id=type_id,model=f'mob{look}',name=name,level=values[5],max_hp=values[4],active=kind>0,config_source='ini/monster.fdb',model_mapping='1000/1010/1020 mapped to 100/110/120 family; appearance review required'))
(OUT/'field-monsters.json').write_text(json.dumps(definitions,ensure_ascii=False,indent=2),encoding='utf-8')
(JOB/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(JOB/'definitions.json').write_text(json.dumps(definitions,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(definitions,ensure_ascii=True))
