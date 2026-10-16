"""Ask the active server to validate graphs, then remove queued validation jobs."""
import json,urllib.request,urllib.error,shutil
from build_h3_comparison import DEST,base

def request(path,payload):
    req=urllib.request.Request('http://127.0.0.1:9317'+path,json.dumps(payload).encode(),{'Content-Type':'application/json'})
    try:
        data=urllib.request.urlopen(req,timeout=120).read()
        return json.loads(data) if data else {}
    except urllib.error.HTTPError as e:return {'validation_error':json.loads(e.read())}

if __name__=='__main__':
    results={}
    # Existing clip is used only for input-file validation, never submitted to render.
    existing=next((base.RUNTIME/'output/guofeng-drama/preview').glob('shot1*.mp4'))
    shutil.copy2(existing,base.CORE/'input/validation-only-input.mp4')
    for name in ['02_Post_shot1','03_Post_shot1','04_Keyframes_shot1','05_Chain','06_Chain']:
        graph=json.loads((DEST/(name+'.api.json')).read_text(encoding='utf-8'))
        if '898' in graph:graph['898']['inputs']['file']='validation-only-input.mp4'
        r=request('/prompt',{'prompt':graph,'client_id':'validation-only-delete-immediately'})
        if 'prompt_id' in r:request('/queue',{'delete':[r['prompt_id']]})
        results[name]=r
        print(name,json.dumps(r,ensure_ascii=False),flush=True)
    (DEST/'validation-results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
