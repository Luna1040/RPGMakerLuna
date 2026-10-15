from pathlib import Path
import json, hashlib
base=Path(__file__).resolve().parent
for name in ['deal','payout','idle']:
    folder=base/name
    index=folder/'output-index.json'
    if not index.exists(): continue
    outputs=json.loads(index.read_text(encoding='utf-8-sig'))
    frames=[x for x in outputs if x['node']=='15' and x['file'].endswith('.png')]
    assert len(frames)==124, (name,len(frames))
    records=[{'source_frame':i,'file':'outputs/'+entry['file'],'duration_ms':1000/24} for i,entry in enumerate(frames)]
    sequence=list(range(124))+(list(reversed(range(124))) if name=='idle' else [])
    data={'canvas':[1024,576],'fps':24,'source_frames':records,'runtime_sequence':sequence,'release_frame':{'deal':40,'payout':67}.get(name),'full_scene':True,'alpha':False}
    (folder/'selection.json').write_text(json.dumps(data,indent=2),encoding='utf-8')
    print(name, 'source frames:',len(frames),'runtime frames:',len(sequence))
