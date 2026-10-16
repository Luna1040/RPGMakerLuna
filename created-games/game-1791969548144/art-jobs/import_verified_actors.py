"""Import visually audited native families; do not derive look from monster ID."""
from pathlib import Path
import sys,json,re,hashlib
import numpy as np
sys.path.insert(0,str(Path(__file__).parent))
from client_map_assets import ROOT,extract
from convert_client_c3 import parse
P=Path(__file__).resolve().parents[1];JOB=P/'art-jobs/client-recovery-20261015';OUT=P/'assets/client_roles'
records=json.loads((JOB/'c3-resource-index.json').read_text());objects={int(k):v.strip().lower().replace('\\','/') for k,v in re.findall(r'^(\d+)=(.+)',(ROOT/'ini/3dobj.ini').read_text(encoding='gb18030'),re.M)}
textures={int(k):v.strip().lower().replace('\\','/') for k,v in re.findall(r'^(\d+)=(.+)',(ROOT/'ini/3dtexture.ini').read_text(encoding='gb18030'),re.M)}
def skin(part,matrices):
 vertices=np.asarray(part['vertices']);v=np.c_[vertices,np.ones(len(vertices))]@np.asarray(part['matrix']).reshape(4,4);pose=np.asarray(matrices).reshape(-1,4,4);result=np.zeros((len(v),3))
 for col in range(2):
  bones=np.asarray(part['bones'])[:,col];weights=np.asarray(part['weights'])[:,col];valid=bones<len(pose)
  result[valid]+=np.einsum('vi,vij->vj',v[valid],pose[bones[valid]])[:,:3]*weights[valid,None]
 return np.round(result,4).tolist()
manifest=[]
for look,name in [(400,'mob400'),(401,'mob401'),(402,'mob402'),(121,'petwarrior'),(220,'petmage')]:
 source=objects[look*1000000];texture=textures[look*1000000]
 for key in [source,texture]+[str(Path(source).with_name(str(a)+'.c3')).replace('\\','/') for a in [100,101,110]]:
  rec=records[key];rec[0]=Path(rec[0]);data=extract(rec);dest=JOB/'source'/key;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
  manifest.append(dict(actor=name,look=look,source=key,sha256=hashlib.sha256(data).hexdigest()))
 parts=parse(JOB/'source'/source);texname=hashlib.sha256(texture.encode()).hexdigest()[:12]+'.dds';(OUT/texname).write_bytes((JOB/'source'/texture).read_bytes());clips={}
 for action,number in [('idle',100),('walk',101),('attack',110)]:
  motions=parse(JOB/'source'/Path(source).with_name(str(number)+'.c3'),True);motion=max(motions,key=lambda m:m['bones']);keys=motion['keys'];frames=[];indices=[]
  for t in np.linspace(0,motion['frames']-1,min(20,len(keys))):
   key=min(keys,key=lambda k:abs(k['frame']-t));indices.append(key['frame']);pose=[]
   for part in parts:
    matching=next((m for m in motions if m['bones']==part['motion']['bones']),motion)
    own=min(matching['keys'],key=lambda k:abs(k['frame']-t));pose.append(skin(part,own['matrices']))
   frames.append(pose)
  clips[action]=dict(duration=max(.3,motion['frames']/30),frames=frames,source_frames=indices,source=str(Path(source).with_name(str(number)+'.c3')))
 for i,part in enumerate(parts):part['posed_vertices']=clips['idle']['frames'][0][i];part['texture_file']=texname;part['texture']=texture
 (OUT/f'{name}.json').write_text(json.dumps(parts,separators=(',',':')),encoding='utf-8');(OUT/f'{name}-actions.json').write_text(json.dumps(clips,separators=(',',':')),encoding='utf-8')
defs=json.loads((OUT/'field-monsters.json').read_text(encoding='utf-8'))
for kind,record in enumerate(defs):record['model']=f'mob{400+kind}';record['client_look']=400+kind;record['model_mapping']='visually checked against original monster1000/1010/1020 icons; original INI mesh and texture mapping'
(OUT/'field-monsters.json').write_text(json.dumps(defs,ensure_ascii=False,indent=2),encoding='utf-8')
(JOB/'verified-actors-manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('Imported three verified field families and two native attack/defense pet families with original action keys.')
