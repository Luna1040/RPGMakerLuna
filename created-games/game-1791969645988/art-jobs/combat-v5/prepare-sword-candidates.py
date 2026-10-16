from pathlib import Path
import shutil
root=Path(r'Z:\RPGMakerLuna\created-games\game-1791969645988');out=root/'art-jobs/sword-matte-candidates-v5';out.mkdir(exist_ok=False)
for i in [8,16,22,27,34,40,65,85]: shutil.copyfile(root/'art-jobs/sword-padded-source-v5'/f'{i:05d}.png',out/f'{i:05d}.png')
(out/'candidate-selection.txt').write_text('Complete 124-frame source retained in sword-padded-source-v5. Candidate frames span load, raise, swing, hit, follow-through and ready stance. Final selection is made after semantic matte/alpha boundary review.',encoding='utf-8')
