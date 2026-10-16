from pathlib import Path
import sys,subprocess,shutil,json,importlib.util
from PIL import Image
root=Path.cwd(); project=root/'created-games/game-1791881399844'; jobs=root/'.game-assistant/starfall-art'
spec=importlib.util.spec_from_file_location('client',root/'shareable-skills/game-production/scripts/comfy_client.py');client=importlib.util.module_from_spec(spec);spec.loader.exec_module(client)
for kind in ['boss','explosion']:
 job=jobs/(kind+'-v1')
 print('Waiting for submitted job',kind,flush=True)
 client.wait('http://127.0.0.1:9316',job,1800)
 source=project/'art-source'/kind;source.mkdir(exist_ok=True)
 for name in ['workflow.json','job.json','history.json','output-index.json']: shutil.copy2(job/name,source/name)
 shutil.copy2(jobs/(kind+'-prompt.txt'),source/'prompt.txt');shutil.copy2(jobs/'boss-reference.png',source/'reference.png')
 videos=list((job/'outputs').glob('*.mp4'));shutil.copy2(videos[0],source/'source.mp4')
 if kind=='boss':
  for script in ['process_animation.py','finalize_animation.py']:subprocess.run([sys.executable,'-X','utf8',str(project/'art-source'/script),kind],check=True)
 else:
  records=json.loads((job/'output-index.json').read_text());files=[job/'outputs'/x['file'] for x in records if x['file'].endswith('.png')]
  # Luminous effects use a separate ADD canvas layer, never character alpha blending.
  indices=[int(30+i*85/39) for i in range(40)]
  out=project/'assets/h3-v1/explosion';out.mkdir(exist_ok=True)
  atlas=Image.new('RGB',(3072,1920),'black');contact=Image.new('RGB',(1200,400),'black')
  for i,idx in enumerate(indices):
   im=Image.open(files[idx]).convert('RGB');im.thumbnail((384,384));atlas.paste(im,(i%8*384,i//8*384))
  for j,idx in enumerate([0,7,15,23,31,39]):
   im=Image.open(files[indices[idx]]).convert('RGB');im.thumbnail((200,200));contact.paste(im,(j*200,100))
  atlas.save(out/'atlas.png');contact.save(source/'contact.jpg')
  (out/'manifest.json').write_text(json.dumps({'frames':40,'columns':8,'tile':384,'fps':20,'loop':False,'blend':'add','source_indices':indices,'duration_ms':2000},indent=2))
 if kind=='explosion': subprocess.run([sys.executable,'-X','utf8',str(project/'art-source/clean_explosion_glow.py')],check=True)
 print('COMPLETE',kind,flush=True)
