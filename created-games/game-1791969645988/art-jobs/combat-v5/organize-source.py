from pathlib import Path
import json,shutil,sys
root=Path(r'Z:\RPGMakerLuna\created-games\game-1791969645988');kind=sys.argv[1];job=root/'art-jobs'/f'{kind}-motion-v5';out=root/'art-jobs'/f'{kind}-source-v5';out.mkdir(exist_ok=False)
records=[]
for entry in json.loads((job/'output-index.json').read_text()):
 if entry['node']!='15' or not entry['file'].endswith('.png'):continue
 i=len(records);name=f'{i:05d}.png';shutil.copyfile(job/'outputs'/entry['file'],out/name);records.append({'file':name,'source_frame':i,'output_node':entry['node'],'download_file':entry['file'],'remote':entry['remote']})
assert len(records)==124
(out/'source-index.json').write_text(json.dumps({'fps':24,'canvas':[768,768],'frames':records},indent=2),encoding='utf-8')
print('FULL SOURCE MAPPING',kind,len(records))
