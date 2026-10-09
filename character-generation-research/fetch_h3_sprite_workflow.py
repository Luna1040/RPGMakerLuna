from pathlib import Path
import urllib.request,urllib.parse,json,hashlib
OUT=Path(__file__).parent/'h3-sprite-workflow';OUT.mkdir(exist_ok=True)
repo='envy-ai/sprite-generator'
def fetch(url):
 return urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'Codex-local-research'}),timeout=60).read()
sha=json.loads(fetch('https://api.github.com/repos/'+repo+'/commits/main'))['sha']
paths=['README.md','LICENSE','config.default.yaml','workflows/Minimax H3 r2v Simplified - Full Sprite Animation.json','workflows/Minimax H3 Running and Idle - 4 directions.json']
paths += ['workflows/dummy-views-pixel-art/'+str(i)+'-'+d+'.png' for i,d in enumerate(['right','left','back','front'],1)]
manifest={'repository':'https://github.com/'+repo,'commit':sha,'files':[]}
for path in paths:
 data=fetch('https://raw.githubusercontent.com/'+repo+'/'+sha+'/'+urllib.parse.quote(path,safe='/'))
 dest=OUT/path;dest.parent.mkdir(exist_ok=True,parents=True);dest.write_bytes(data)
 if path.endswith('.json'):json.loads(data)
 manifest['files'].append({'path':path,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
 print('DOWNLOADED',path,flush=True)
(OUT/'source-manifest.json').write_text(json.dumps(manifest,indent=2))
nodes=json.loads(fetch('http://127.0.0.1:9315/object_info'))
report={}
for path in paths:
 if not path.endswith('.json'):continue
 graph=json.loads((OUT/path).read_bytes());classes=sorted({n['class_type'] for n in graph.values()})
 roots=[i for i,n in graph.items() if n['class_type'] in ['SaveVideo','SaveImage']]
 reachable=set()
 def visit(i):
  if i in reachable:return
  reachable.add(i)
  for value in graph[i]['inputs'].values():
   if isinstance(value,list) and len(value)==2 and str(value[0]) in graph:visit(str(value[0]))
 for i in roots:visit(i)
 models=[]
 for node_id,node in graph.items():
  for key,value in node['inputs'].items():
   if isinstance(value,str) and value.endswith(('.safetensors','.gguf')):models.append({'node':node_id,'class_type':node['class_type'],'input':key,'filename':value,'connected_to_saved_output':node_id in reachable})
 required_classes=sorted({graph[i]['class_type'] for i in reachable})
 report[path]={'nodes':len(graph),'connected_nodes':len(reachable),'missing_connected_node_types':[c for c in required_classes if c not in nodes],'missing_node_types_including_unused':[c for c in classes if c not in nodes],'model_inputs':models}
(OUT/'compatibility-audit.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps(report,indent=2,ensure_ascii=False))
