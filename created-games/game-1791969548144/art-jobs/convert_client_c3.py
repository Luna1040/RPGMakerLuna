"""Convert selected unencrypted C3 geometry into engine-neutral scene data.
Format cross-check: C3Studio C3Phy/C3Motion source, inspected 2026-10-15.
Only local geometry/texture resources are read; no client binaries executed.
"""
import json,struct,sys,hashlib
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parent))
from client_map_assets import ROOT,index,extract
JOB=Path(__file__).resolve().parent/'client-roles-20261015'
OUT=JOB.parents[1]/'assets/client_roles'
OUT.mkdir(exist_ok=True)

class Reader:
 def __init__(self,data): self.data=data;self.p=0
 def read(self,fmt):
  result=struct.unpack_from('<'+fmt,self.data,self.p);self.p+=struct.calcsize('<'+fmt);return result
 def text(self):
  n,=self.read('I');value=self.data[self.p:self.p+n];self.p+=n;return value.rstrip(b'\0').decode('gb18030')

def parse(path,return_motion=False):
 data=path.read_bytes();assert data[:16]==b'MAXFILE C3 00001';p=16;meshes=[];motions=[]
 while p+8<=len(data):
  tag=data[p:p+4];size=struct.unpack_from('<I',data,p+4)[0];r=Reader(data[p+8:p+8+size]);p+=8+size
  if tag in [b'PHY ',b'PHY3',b'PHY4',b'PHY5']:
   name=r.text();blend,nv,av=r.read('III');morph=4 if tag==b'PHY ' else 1
   vertices=[];uv=[];bones=[];weights=[]
   for v in range(nv+av):
    positions=r.read('f'*(morph*3));vertices.append(list(positions[:3]));uv.append(list(r.read('ff')));r.read('I');bones.append(list(r.read('II')));weights.append(list(r.read('ff')))
    if tag==b'PHY3':r.read('fff')
    elif tag==b'PHY5':r.read('fffff')
   nt,at=r.read('II');indices=list(r.read('H'*((nt+at)*3)));texture=r.text();r.read('ffffff');matrix=list(r.read('f'*16))
   meshes.append(dict(name=name,vertices=vertices,uv=uv,bones=bones,weights=weights,indices=indices,texture=texture,matrix=matrix))
  elif tag==b'MOTI':
   nb,nf=r.read('II');kind=r.data[r.p:r.p+4];r.p+=4;frames=[]
   if kind==b'KKEY':
    count,=r.read('I')
    for i in range(count):
     frame,=r.read('I');matrices=[list(r.read('f'*16)) for j in range(nb)];frames.append(dict(frame=frame,matrices=matrices))
   elif kind==b'XKEY':
    count,=r.read('I')
    for i in range(count):
     frame,=r.read('H');matrices=[]
     for j in range(nb):
      values=r.read('f'*12)
      matrices.append([*values[0:3],0,*values[3:6],0,*values[6:9],0,*values[9:12],1])
     frames.append(dict(frame=frame,matrices=matrices))
   elif kind==b'ZKEY':
    count,=r.read('I')
    for i in range(count):
     frame,=r.read('H');matrices=[]
     for j in range(nb):
      qx,qy,qz,qw,tx,ty,tz=r.read('fffffff')
      length=max(1e-12,(qx*qx+qy*qy+qz*qz+qw*qw)**0.5)
      x,y,z,w=[v/length for v in [qx,qy,qz,qw]]
      matrices.append([1-2*(y*y+z*z),2*(x*y+z*w),2*(x*z-y*w),0,2*(x*y-z*w),1-2*(x*x+z*z),2*(y*z+x*w),0,2*(x*z+y*w),2*(y*z-x*w),1-2*(x*x+y*y),0,tx,ty,tz,1])
     frames.append(dict(frame=frame,matrices=matrices))
   else:
    # Current selected models use matrix keys. Refuse unknown compression.
    raise ValueError(f'Unsupported motion {kind!r}: {path}')
   motions.append(dict(bones=nb,frames=nf,keys=frames))
 if return_motion:return motions
 assert len(meshes)==len(motions),(path,len(meshes),len(motions))
 if '/npc/' in path.as_posix() and path.with_name('100.c3').exists():
  external=parse(path.with_name('100.c3'),True)
  if external: motions=[external[0]]*len(meshes)
 result=[];attachments={}
 for mesh,motion in zip(meshes,motions):
  pose=np.asarray(motion['keys'][0]['matrices'],dtype=np.float32).reshape(-1,4,4);initial=np.asarray(mesh['matrix']).reshape(4,4);vertices=np.asarray(mesh['vertices']);vec=np.c_[vertices,np.ones(len(vertices))];transformed=np.zeros((len(vertices),3))
  if mesh['name'].lower() in ['v_head','v_r_weapon','v_l_weapon']:attachments[mesh['name'].lower()]=(initial@pose[0]).reshape(-1).tolist()
  if not mesh['indices'] or mesh['name'].lower()!='v_body' and len(mesh['vertices'])<30:continue
  for i in range(len(vertices)):
   total=0
   for bone,weight in zip(mesh['bones'][i],mesh['weights'][i]):
    if weight>0 and bone<len(pose):transformed[i]+=(vec[i]@initial@pose[bone])[:3]*weight;total+=weight
   if total==0:transformed[i]=vertices[i]
  mesh['posed_vertices']=transformed.tolist();mesh['motion']=motion
  result.append(mesh)
 for mesh in result:mesh['attachments']=attachments
 return result

if __name__=='__main__':
 models={}
 for name,file in [('warrior','c3/select/069000000.c3'),('warrior_head','c3/select/069000001.c3'),('warrior_hair','c3/select/069119001.c3'),('mage','c3/select/061000000.c3'),('mage_head','c3/select/061000001.c3'),('mage_hair','c3/select/061119001.c3'),('warrior_weapon','c3/select/410970.c3'),('mage_weapon','c3/select/440990.c3')]+[(str(n),f'c3/npc/{n}/1.c3') for n in [738,701,707,728,714,729]]:
  parts=parse(JOB/'source'/file)
  configured=('c3/select/'+Path(file).stem+'.dds') if '/select/' in file else f'c3/texture/{name}000000.dds'
  for part in parts: part['texture']=configured
  models[name]=parts;print(name,[(m['name'],len(m['vertices']),m['texture']) for m in parts],flush=True)
 textures={m['texture'].replace('\\','/').lower() for parts in models.values() for m in parts}
 # Texture paths embedded by exporters may be absolute; resolve by exact virtual
 # path first, then a unique matching filename in the original asset index.
 found={}
 for package in sorted(ROOT.glob('c3*.tpi')):
  for key,record in index(package).items():
   if key in textures or key.endswith(('.dds','.tga','.png')) and any(key.endswith('/'+Path(t).name) for t in textures): found[key]=record
 manifest=[]
 for name,parts in models.items():
  for part in parts:
   texture=part['texture'].replace('\\','/').lower();matches=[k for k in found if k==texture] or [k for k in found if k.endswith('/'+Path(texture).name)]
   assert len(matches)==1,(name,texture,matches)
   source=matches[0];data=extract(found[source]);dest=hashlib.sha256(source.encode()).hexdigest()[:12]+Path(source).suffix
   (OUT/dest).write_bytes(data);part['texture_file']=dest
   manifest.append(dict(model=name,client_texture=source,runtime=dest,sha256=hashlib.sha256(data).hexdigest()))
  (OUT/(name+'.json')).write_text(json.dumps(parts,separators=(',',':')),encoding='utf-8')
 (JOB/'model-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
