from pathlib import Path
import sys,json,shutil
sys.path.insert(0,r'Z:\RPGMakerLuna\map-generation-research')
import layered_map_trial as existing
root=Path(r'Z:\RPGMakerLuna\created-games\game-1791969645988');out=root/'art-jobs/cast-alpha-v2';out.mkdir(exist_ok=False)
index=json.loads((root/'art-jobs/cast-crops-v2/output-index.json').read_text())
(root/'assets/characters').mkdir(exist_ok=True)
for entry in index:
 i=int(entry['node'])-30
 folder=out/str(i);folder.mkdir();shutil.copyfile(root/'art-jobs/cast-crops-v2/outputs'/entry['file'],folder/'raw.png')
 existing.key_asset(folder)
 shutil.copyfile(folder/'rgba.png',root/'assets/characters'/f'{i}.png')
 print('ALPHA PASS',i)
