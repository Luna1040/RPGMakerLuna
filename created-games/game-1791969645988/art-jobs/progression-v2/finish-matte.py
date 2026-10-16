from pathlib import Path
import sys,shutil
sys.path.insert(0,r'Z:\RPGMakerLuna\map-generation-research')
import layered_map_trial as existing
root=Path(r'Z:\RPGMakerLuna\created-games\game-1791969645988')
for foldername,source,index in [('courier-alpha-v2','courier-crop-v2',4),('wolf-alpha-v2','wolf-key-v2',7)]:
 folder=root/'art-jobs'/foldername;folder.mkdir(exist_ok=False);shutil.copyfile(root/'art-jobs'/source/'outputs/00000.png',folder/'raw.png')
 existing.key_asset(folder);shutil.copyfile(folder/'rgba.png',root/'assets/characters'/f'{index}.png');print('ALPHA PASS',index)
