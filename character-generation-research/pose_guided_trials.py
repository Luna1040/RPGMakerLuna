from comfy_trials import *
from PIL import ImageDraw
# Geometric joint diagrams: pose controls, not replacement character artwork.
def guide(name,points):
 im=Image.new('RGB',(1024,1024),'#d4d7dc');d=ImageDraw.Draw(im)
 for a,b in [('hip','rear_knee'),('rear_knee','rear_foot'),('hip','front_knee'),('front_knee','front_foot'),('hip','chest'),('chest','head'),('chest','elbow'),('elbow','hand'),('chest','elbow2'),('elbow2','hand')]:
  width=100 if (a,b)==('hip','chest') else 44
  d.line([points[a],points[b]],fill='#54687c',width=width)
 for k,p in points.items():
  if k=='tip':continue
  r=48 if k=='head' else 24
  d.ellipse((p[0]-r,p[1]-r,p[0]+r,p[1]+r),fill='#8aa1b4',outline='#344352',width=4)
 d.line([points['hand'],points['tip']],fill='#b68436',width=15)
 p=OUT/(name+'.png');im.save(p);return upload(p)
master=upload(OUT/'v2-master.png')
poses={
 'strike':dict(hip=(470,590),chest=(610,425),head=(705,335),rear_knee=(295,710),rear_foot=(165,890),front_knee=(680,660),front_foot=(715,905),elbow=(670,490),elbow2=(630,520),hand=(740,555),tip=(950,800)),
 'recovery':dict(hip=(485,635),chest=(630,485),head=(730,395),rear_knee=(280,740),rear_foot=(165,890),front_knee=(680,690),front_foot=(715,905),elbow=(650,570),elbow2=(575,605),hand=(680,690),tip=(925,920))}
for name,p in poses.items():
 g=guide('v3c-guide-'+name,p)
 run('v3c-'+name,'把图1的几何人偶替换成图2的成年金发女骑士。必须采用图1的全身姿势、头部位置、躯干倾斜、骨盆位置、膝盖位置和脚的位置，图1金色直线代表唯一一把剑。图2只用于脸、头发、银金铠甲、蓝裙和蓝披风的设计及精美二维画风，不能照搬图2站姿。双手握同一把剑，只有两只手两条腿。画出连贯自然的人体和服装，头发披风向左后方飘。全身，灰色背景，完整剑身。不要画人偶线条。',g,master,size=(1024,1024))
