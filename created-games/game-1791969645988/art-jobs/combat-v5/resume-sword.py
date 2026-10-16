from pathlib import Path
import shutil
root=Path(r'Z:\RPGMakerLuna\created-games\game-1791969645988');out=root/'art-jobs/sword-matte-remainder-v5';out.mkdir(exist_ok=False)
for i in [16,22,27,34,40,65,85]:shutil.copyfile(root/'art-jobs/sword-matte-candidates-v5'/f'{i:05d}.png',out/f'{i:05d}.png')
