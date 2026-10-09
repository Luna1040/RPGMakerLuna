from pathlib import Path
import json
root=Path(__file__).resolve().parent.parent
for path in [root/'godot-first-knight/assets/animations.json',root/'character-generation-research/h3-runtime/character-set/export-specs.json']:
 data=json.loads(path.read_text())
 for action,reach in [('attack1',220),('attack2',235),('attack3',180)]:data[action]['range']=reach
 path.write_text(json.dumps(data,indent=2),encoding='utf-8')
print('Melee visual reach saved; runtime adds a 24px margin and scales with character.')
