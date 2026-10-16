from pathlib import Path
import sys,uuid
sys.path.insert(0,r'Z:\RPGMakerLuna\shareable-skills\game-production\scripts')
from comfy_client import api,save,upload,wait
root=Path(r'Z:\RPGMakerLuna\created-games\game-1791969645988');out=root/'art-jobs/sword-padded-reference-v5';out.mkdir(exist_ok=False);url='http://127.0.0.1:9315'
ref=upload(url,root/'assets/characters/0.png')
g={'1':{'class_type':'LoadImage','inputs':{'image':ref}},'2':{'class_type':'ImageScale','inputs':{'image':['1',0],'upscale_method':'lanczos','width':384,'height':480,'crop':'disabled'}},'3':{'class_type':'ImagePadForOutpaint','inputs':{'image':['2',0],'left':192,'right':192,'top':144,'bottom':144,'feathering':0}},'4':{'class_type':'SaveImage','inputs':{'images':['3',0],'filename_prefix':'game-art/sword-padded-'+uuid.uuid4().hex}}}
save(out/'workflow.json',g);save(out/'submission.json',{'client_id':'sword-padded-ref-v5'});save(out/'job.json',api(url,'/prompt',{'prompt':g,'client_id':'sword-padded-ref-v5'}));wait(url,out,180)
