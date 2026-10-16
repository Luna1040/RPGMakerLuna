from pathlib import Path
import concurrent.futures
import hashlib
import json
import urllib.request

DEST = Path(__file__).resolve().parent / 'h3-community-workflows'
def request(url):
    req=urllib.request.Request(url,headers={'User-Agent':'H3-workflow-research','Accept':'application/json'})
    return urllib.request.urlopen(req,timeout=90).read()

def fetch(item):
    name,url=item
    body=request(url)
    if name.endswith('.json'): json.loads(body)
    target=DEST/name
    target.parent.mkdir(parents=True,exist_ok=True)
    target.write_bytes(body)
    return {'file':name,'url':url,'bytes':len(body),'sha256':hashlib.sha256(body).hexdigest()}

if __name__=='__main__':
    DEST.mkdir(exist_ok=True)
    hf=json.loads(request('https://huggingface.co/api/models/joeygambino/MiniMax-H3-Multishot-Workflow'))
    gh=json.loads(request('https://api.github.com/repos/mdkberry/comfyui_workflows/commits/main'))
    files=[]
    for name in ['workflows/H3_Seamless_Chain_CORE.json','workflows/H3_Seamless_Chain_v2.json','workflows/H3_Keyframes.json','README.md','SETTINGS.md','INSTALL.md','PROMPTING.md']:
        files.append(('Seamless-Chain/'+name,'https://huggingface.co/joeygambino/MiniMax-H3-Multishot-Workflow/resolve/'+hf['sha']+'/'+name))
    for name in ['MBEDIT - MH3-r2v_2Pass-LatentUpscaler_v5.json','MBEDIT - MH3-rv2v_PixelSpace-Upscaler-CtxtWndws_v3.json','MBEDIT - MH3_rv2v_PixelSpace_Upscaler_v18.json','ReadMe.md']:
        from urllib.parse import quote
        files.append(('MBEDIT/'+name,'https://raw.githubusercontent.com/mdkberry/comfyui_workflows/'+gh['sha']+'/workflows_by_model/Minimax-H3/'+quote(name)))
    results=[]
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for future in concurrent.futures.as_completed([pool.submit(fetch,item) for item in files]):
            try:
                result=future.result()
                results.append(result)
                print('SAVED',result['file'],result['bytes'],flush=True)
            except Exception as e:
                print('FAILED',repr(e),flush=True)
    manifest={'hf_revision':hf['sha'],'github_revision':gh['sha'],'files':results}
    (DEST/'provenance.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
