from pathlib import Path
import json
import shutil

ROOT=Path(__file__).resolve().parent
DEST=ROOT/'h3-community-workflows'
RUNTIME=ROOT/'h3-runtime'
CORE=next(RUNTIME.glob('ComfyUI-*'))
schema=json.loads((RUNTIME/'current-node-schema.json').read_text(encoding='utf-8-sig'))
reports=[]
for path in DEST.rglob('*.json'):
    try: w=json.loads(path.read_text(encoding='utf-8-sig'))
    except Exception: continue
    if 'nodes' not in w: continue
    kinds=sorted(set(n['type'] for n in w['nodes']))
    missing=[k for k in kinds if k not in schema and k not in ('Note','MarkdownNote','Reroute')]
    reports.append({'file':str(path.relative_to(DEST)),'node_count':len(w['nodes']),'missing_node_types':missing,'render_tested':False})
    folder=CORE/'user/default/workflows/社区H3原版_依赖待补齐'/path.parent.name
    folder.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(path,folder/path.name)
(DEST/'compatibility.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2),encoding='utf-8')
print('Saved',len(reports),'original workflows and local compatibility reports. No custom code installed or service restarted.')
