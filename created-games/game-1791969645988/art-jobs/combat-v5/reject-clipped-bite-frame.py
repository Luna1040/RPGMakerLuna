from pathlib import Path
import json
p=Path('art-jobs/combat-v5/bite-selection.json');d=json.loads(p.read_text());d['frames']=[f for f in d['frames'] if f['source_frame']!=24]
for frame in d['frames']:
 if frame['source_frame']==16:frame['duration_ms']+=70
d['excluded_frames']=[{'source_frame':24,'reason':'Tail intersects right canvas edge; excluded from final animation'}]
p.write_text(json.dumps(d,indent=2),encoding='utf-8')
