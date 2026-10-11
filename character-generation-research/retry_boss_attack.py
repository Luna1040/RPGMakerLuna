"""Archive the rejected illuminated attack before a clean physical rehearsal."""
import sys,shutil
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import npc_roster_v1 as n
archive=n.OUT/'archive'/'boss-attack-background-light-v1'
archive.mkdir(parents=True,exist_ok=False)
for source,name in [(n.OUT/'jobs'/'boss'/'attack','job'),(n.OUT/'export'/'boss'/'attack','frames')]:
    target=archive/name
    assert source.resolve().is_relative_to(n.OUT.resolve()) and target.resolve().is_relative_to(n.OUT.resolve())
    shutil.move(str(source),str(target))
for source in [n.SPECS,n.CONFIG,n.OUT/'export'/'boss'/'animation.json']:
    shutil.copyfile(source,archive/source.name)
manifest=n.read_json(n.OUT/'export'/'boss'/'animation.json')
del manifest['actions']['attack']
n.write_json(n.OUT/'export'/'boss'/'animation.json',manifest)
spec=n.read_json(n.SPECS)
spec['boss'].pop('attack')
n.write_json(n.SPECS,spec)
config=n.read_json(n.CONFIG)
boss=config['characters']['boss']
boss['seed']=1011391
boss['attack']='The man performs one continuous physical rehearsal with the same solid metal sword. He raises the sword over his shoulder while rotating his chest away, pauses briefly, brings the physical blade diagonally down and forward, then lowers it to the original relaxed stance. His knees bend and his hips shift with the movement, his head follows the direction, and the fabric follows his torso. Show the visible solid blade clearly at every position. Only the man, clothing and metal sword move. Keep the surrounding empty black space completely flat, featureless and unlit throughout. No emitted light or trails.'
n.write_json(n.CONFIG,config)
print('Archived rejected candidate; new physical rehearsal configured.')
