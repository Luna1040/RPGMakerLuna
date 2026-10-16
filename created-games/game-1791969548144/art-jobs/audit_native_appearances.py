"""Audit native geometry against actual client portrait references, read-only."""
from pathlib import Path
import sys,json,re,hashlib
import numpy as np
sys.path.insert(0,str(Path(__file__).parent))
from client_map_assets import ROOT,index,extract
from convert_client_c3 import parse
P=Path(__file__).resolve().parents[1];JOB=P/'art-jobs/client-recovery-20261015';OUT=JOB/'candidates';OUT.mkdir(exist_ok=True)
objects={int(k):v.lower().replace('\\','/') for k,v in re.findall(r'^(\d+)=(.+)',(ROOT/'ini/3dobj.ini').read_text(encoding='gb18030'),re.M)}
textures={int(k):v.lower().replace('\\','/') for k,v in re.findall(r'^(\d+)=(.+)',(ROOT/'ini/3dtexture.ini').read_text(encoding='gb18030'),re.M)}
looks=[121,122,221,222]
resources=json.loads((JOB/'c3-resource-index.json').read_text(encoding='utf-8'))
for value in resources.values():value[0]=Path(value[0])
def skin(part,matrices):
 vertices=np.asarray(part['vertices']);vec=np.c_[vertices,np.ones(len(vertices))]@np.asarray(part['matrix']).reshape(4,4)
 pose=np.asarray(matrices).reshape(-1,4,4);out=np.zeros((len(vertices),3));weights=np.asarray(part['weights']);bones=np.asarray(part['bones'])
 for col in range(2):
  valid=bones[:,col]<len(pose);out[valid]+=np.einsum('vi,vij->vj',vec[valid],pose[bones[valid,col]])[:,:3]*weights[valid,col,None]
 return np.round(out,4).tolist()
manifest=[];ids=[]
for look in looks:
 key=look*1000000;model=objects.get(key);texture=textures.get(key)
 if not model or model not in resources or not texture or texture not in resources:continue
 files=[model,texture]+[str(Path(model).with_name(str(a)+'.c3')).replace('\\','/') for a in [100,101,110]]
 for source in files:
  if source not in resources:continue
  data=extract(resources[source]);dest=JOB/'source'/source;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
  manifest.append(dict(look=look,source=source,sha256=hashlib.sha256(data).hexdigest()))
 try:
  parts=parse(JOB/'source'/model)
  external=JOB/'source'/Path(model).with_name('100.c3')
  motions=parse(external,True) if external.exists() else []
  for part in parts:
   matches=[m for m in motions if m['bones']==part['motion']['bones']]
   if matches:part['posed_vertices']=skin(part,matches[0]['keys'][0]['matrices'])
   part['texture_file']=f'{look}.dds'
  (OUT/f'{look}.dds').write_bytes((JOB/'source'/texture).read_bytes())
  (OUT/f'audit{look}.json').write_text(json.dumps(parts,separators=(',',':')),encoding='utf-8')
  ids.append('audit'+str(look))
 except Exception as e:print('FAILED',look,str(e))
(JOB/'candidate-ids.json').write_text(json.dumps(ids),encoding='utf-8')
(JOB/'candidate-manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('candidate count',len(ids),ids)
