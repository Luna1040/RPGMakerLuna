from pathlib import Path
import shutil
root=Path(r'Z:\RPGMakerLuna\created-games\game-1791969645988');out=root/'art-jobs/bite-matte-candidates-v5';out.mkdir(exist_ok=False)
for i in [8,16,24,32,40,60,85]: shutil.copyfile(root/'art-jobs/bite-source-v5'/f'{i:05d}.png',out/f'{i:05d}.png')
(out/'candidate-selection.txt').write_text('124 complete original source frames retained in bite-source-v5. These candidates span anticipation, jaw opening, bite, follow-through and recovery. Final alpha-approved selection follows matting.',encoding='utf-8')
