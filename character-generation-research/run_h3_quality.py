from run_h3_smoke import graph,api,ROOT
import sys,json,time
action=sys.argv[1];name=action+'-hq';g=graph(action)
g['1']['inputs']['image']='knight-green-reference.png'
g.pop('5');g['7']['inputs']['model']=['3',0];g['10']['inputs'].update(model=['3',0],steps=20,scheduler='normal')
g['6']['inputs'].update(width=768,height=768)
g['6']['inputs']['prompt']+=' The knight occupies only the central 60 percent of the canvas height, with broad empty green margins on all four sides. Keep her entire sword, hair and cape within the frame throughout. The background is a perfectly flat solid RGB green screen with no texture, pattern, grid or gradients. No sword glow, no magical effects, no trails.'
g['14']['inputs']['filename_prefix']='h3-'+name;g['15']['inputs']['filename_prefix']='frames/'+name
(ROOT/(name+'-api.json')).write_text(json.dumps(g,indent=2))
job=api('/prompt',{'prompt':g,'client_id':'h3-quality-test'});(ROOT/(name+'-job.json')).write_text(json.dumps(job));print('QUEUED',name,job,flush=True)
while True:
 h=api('/history/'+job['prompt_id'])
 if job['prompt_id'] in h:
  record=h[job['prompt_id']];(ROOT/(name+'-history.json')).write_text(json.dumps(record,indent=2));print(name,record['status'],flush=True);break
 time.sleep(15)
