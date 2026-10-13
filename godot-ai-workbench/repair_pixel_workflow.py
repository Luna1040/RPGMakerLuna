"""Replace the incompatible saved UI graph with the validated Flux2 API graph."""
import json
from pathlib import Path
import shutil
import sys
import time
import urllib.request

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'shareable-skills/game-production/scripts'))
from image_client import build

target=next((ROOT/'character-generation-research/h3-runtime').glob('ComfyUI-*/user/default/workflows/AI像素生图工程.json'))
original=json.loads(target.read_text(encoding='utf-8'))
prompt=next(n['widgets_values'][0] for n in original['nodes'] if n['type']=='CLIPTextEncode')
graph=build(prompt,1024,1024,42)
graph['13']['inputs']['filename_prefix']='PixelArt/Flux2'
schema=json.load(urllib.request.urlopen('http://127.0.0.1:9315/object_info',timeout=20))
positions={1:[0,0],2:[0,220],3:[0,470],4:[380,0],5:[780,230],6:[380,340],7:[380,570],8:[780,400],9:[780,540],10:[780,0],11:[1160,50],12:[1500,50],13:[1800,50]}
nodes=[];links=[];next_link=0
for key,api_node in graph.items():
    info=schema[api_node['class_type']]
    fields=dict(info['input'].get('required',{}),**info['input'].get('optional',{}))
    node={'id':int(key),'type':api_node['class_type'],'pos':positions[int(key)],'size':[320,220] if key!='4' else [360,260],'flags':{},'order':int(key)-1,'mode':0,'inputs':[],'outputs':[],'properties':{'Node name for S&R':api_node['class_type']},'widgets_values':[],'widgets_values_named':{}}
    for name,value in api_node['inputs'].items():
        spec=fields[name];kind=spec[0];options=spec[1] if len(spec)>1 else {}
        if isinstance(value,list):
            next_link+=1
            node['inputs'].append({'name':name,'type':kind,'link':next_link})
            links.append([next_link,int(value[0]),value[1],int(key),len(node['inputs'])-1,kind])
        else:
            node['inputs'].append({'name':name,'type':'COMBO' if isinstance(kind,list) else kind,'widget':{'name':name},'link':None})
            node['widgets_values'].append(value)
            node['widgets_values_named'][name]=value
            if options.get('control_after_generate'):
                node['widgets_values'].append('randomize')
                node['widgets_values_named']['control_after_generate']='randomize'
    for slot,kind in enumerate(info.get('output',[])):
        names=info.get('output_name',info['output'])
        node['outputs'].append({'name':names[slot],'type':kind,'links':[],'slot_index':slot})
    if key=='13':node['size']=[360,450]
    nodes.append(node)
by_id={n['id']:n for n in nodes}
for link in links:by_id[link[1]]['outputs'][link[2]]['links'].append(link[0])
workflow={'id':original['id'],'revision':original.get('revision',0)+1,'last_node_id':13,'last_link_id':next_link,'nodes':nodes,'links':links,'groups':[],'config':{},'extra':{'ds':{'scale':.65,'offset':[80,100]}},'version':.4}
backup=ROOT/'.game-assistant/workflow-backups'/str(time.time_ns())
backup.mkdir(parents=True)
shutil.copy2(target,backup/target.name)
target.write_text(json.dumps(workflow,ensure_ascii=False,indent=2),encoding='utf-8')
out=ROOT/'.game-assistant/pixel-workflow-repair'
out.mkdir(exist_ok=True)
(out/'workflow.json').write_text(json.dumps(graph,ensure_ascii=False,indent=2),encoding='utf-8')
request=urllib.request.Request('http://127.0.0.1:9315/prompt',data=json.dumps({'prompt':graph,'client_id':'pixel-workflow-repair','extra_data':{'extra_pnginfo':{'workflow':workflow}}}).encode(),headers={'Content-Type':'application/json'})
job=json.load(urllib.request.urlopen(request,timeout=30))
(out/'job.json').write_text(json.dumps(job),encoding='utf-8')
print(json.dumps({'saved':str(target),'backup':str(backup),'prompt_id':job['prompt_id']},ensure_ascii=False))
