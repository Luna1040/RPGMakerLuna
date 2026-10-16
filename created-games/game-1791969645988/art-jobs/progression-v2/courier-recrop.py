from pathlib import Path
import sys,json,uuid
sys.path.insert(0,r'Z:\RPGMakerLuna\shareable-skills\game-production\scripts')
from comfy_client import api,upload,save
root=Path(r'Z:\RPGMakerLuna\created-games\game-1791969645988');out=root/'art-jobs/courier-crop-v2';out.mkdir(exist_ok=False)
url='http://127.0.0.1:9315';ref=upload(url,root/'art-jobs/cast-key-v2/outputs/00000.png')
g={'1':{'class_type':'LoadImage','inputs':{'image':ref}},'2':{'class_type':'ImageCrop','inputs':{'image':['1',0],'width':308,'height':394,'x':6,'y':404}},'3':{'class_type':'SaveImage','inputs':{'images':['2',0],'filename_prefix':'game-art/courier-recrop-'+uuid.uuid4().hex}}}
save(out/'workflow.json',g);save(out/'submission.json',{'client_id':'courier-recrop-v2','reason':'Keep entire shoe; remove only atlas borders'});save(out/'job.json',api(url,'/prompt',{'prompt':g,'client_id':'courier-recrop-v2'}))
