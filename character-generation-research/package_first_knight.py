from pathlib import Path
from zipfile import ZipFile,ZIP_DEFLATED
root=Path(__file__).resolve().parent.parent
project=root/'godot-first-knight'
files=[project/'knight.gd',project/'knight.tscn',project/'dummy_reactions.gd',project/'INTEGRATION.md']
files+=sorted(p for p in (project/'assets').rglob('*') if p.suffix in ['.png','.json'])
with ZipFile(root/'first-knight-character.zip','w',ZIP_DEFLATED) as z:
 for p in files:z.write(p,'first_knight/'+p.relative_to(project).as_posix())
print('PACKAGED',len(files),'files', (root/'first-knight-character.zip').stat().st_size,'bytes')
