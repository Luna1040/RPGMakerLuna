from pathlib import Path
import math,json
from PIL import Image,ImageDraw
import numpy as np
ROOT=Path(__file__).parent
OUT=ROOT/'pose-ab-test';OUT.mkdir(exist_ok=True)
COLORS=[(255,0,0),(255,85,0),(255,170,0),(255,255,0),(170,255,0),(85,255,0),(0,255,0),(0,255,85),(0,255,170),(0,255,255),(0,170,255),(0,85,255),(0,0,255),(85,0,255),(170,0,255),(255,0,255),(255,0,170),(255,0,85)]
LIMBS=[(1,2),(1,5),(2,3),(3,4),(5,6),(6,7),(1,8),(8,9),(9,10),(1,11),(11,12),(12,13),(1,0),(0,14),(14,16),(0,15),(15,17)]
def ik(a,b,l1,l2,sign=1):
 a=np.array(a,float);b=np.array(b,float);v=b-a;dist=np.linalg.norm(v)
 if not abs(l1-l2)<dist<l1+l2:raise ValueError(('Unreachable limb',dist,l1,l2))
 u=v/dist;x=(l1*l1-l2*l2+dist*dist)/(2*dist);h=math.sqrt(max(0,l1*l1-x*x))
 return a+u*x+sign*np.array([-u[1],u[0]])*h
def make(t):
 hip=np.array([455+45*t,560+55*t]);tilt=0.20+0.43*t
 chest=hip+np.array([math.sin(tilt),-math.cos(tilt)])*210
 head=chest+np.array([math.sin(tilt),-math.cos(tilt)])*80+np.array([12,0])
 wrist=np.array([530+200*t,240+350*t]);angle=math.radians(-150+195*t)
 tip=wrist+290*np.array([math.cos(angle),math.sin(angle)])
 rs=chest+[-10,12];ls=chest+[10,-12];rh=hip+[-14,0];lh=hip+[14,0]
 ra=np.array([205,890]);la=np.array([715,890]);rw=wrist+[-8,8];lw=wrist+[8,-8]
 joints=[head,chest,rs,ik(rs,rw,132,138,1),rw,ls,ik(ls,lw,132,138,1),lw,rh,ik(rh,ra,240,245,-1),ra,lh,ik(lh,la,240,245,-1),la,head+[-5,-8],head+[8,-8],head+[-24,-2],head+[-16,-2]]
 return np.array(joints),wrist,tip
def draw(joints,wrist,tip,path,weapon=False):
 im=Image.new('RGB',(1024,1024),'black');d=ImageDraw.Draw(im)
 for (a,b),c in zip(LIMBS,COLORS):
  a=joints[a];b=joints[b];v=b-a;v=v/np.linalg.norm(v);n=np.array([-v[1],v[0]])*10
  # Thick limb lozenges approximate the model author's OpenPose renderer.
  mid=(a+b)/2;d.polygon([tuple(a),tuple(mid+n),tuple(b),tuple(mid-n)],fill=tuple(int(x*.6) for x in c))
 for p,c in zip(joints,COLORS):d.ellipse((p[0]-10,p[1]-10,p[0]+10,p[1]+10),fill=c)
 if weapon:d.line([tuple(wrist),tuple(tip)],fill='#e6b94f',width=9)
 im.save(path)
if __name__=='__main__':
 poses={}
 for name,t in [('A',0),('M',.5),('B',1)]:
  j,w,s=make(t);draw(j,w,s,OUT/f'pose-{name}.png');draw(j,w,s,OUT/f'guide-{name}.png',True)
  poses[name]={'phase':t,'openpose18':j.tolist(),'wrist':w.tolist(),'sword_tip':s.tolist(),'sword_length':290}
 (OUT/'poses.json').write_text(json.dumps(poses,indent=2))
 print('Saved parameterized poses to',OUT)
