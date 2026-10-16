from pathlib import Path
import sys,json,uuid
sys.path.insert(0,r'Z:\RPGMakerLuna\shareable-skills\game-production\scripts')
from comfy_client import api,upload,save,wait
root=Path(r'Z:\RPGMakerLuna\created-games\game-1791969645988');out=root/'art-jobs/cast-crops-v2';out.mkdir(exist_ok=False)
url='http://127.0.0.1:9315';ref=upload(url,root/'art-jobs/cast-key-v2/outputs/00000.png');graph={'1':{'class_type':'LoadImage','inputs':{'image':ref}}}
for i in range(7):
 graph[str(10+i)]={'class_type':'ImageCrop','inputs':{'image':['1',0],'width':308,'height':388,'x':(i%4)*320+6,'y':(i//4)*400+6}}
 graph[str(30+i)]={'class_type':'SaveImage','inputs':{'images':[str(10+i),0],'filename_prefix':'game-art/alpha-source-'+str(i)+'-'+uuid.uuid4().hex}}
save(out/'workflow.json',graph);save(out/'submission.json',{'client_id':'cast-crops-v2','source':'cast-key-v2'})
save(out/'job.json',api(url,'/prompt',{'prompt':graph,'client_id':'cast-crops-v2'}))
print('CROPS SUBMITTED')
