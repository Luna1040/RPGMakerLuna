from pathlib import Path
import sys,json,urllib.parse,concurrent.futures
sys.path.insert(0,r'Z:\RPGMakerLuna\shareable-skills\game-production\scripts')
import comfy_client as client
folder=Path(sys.argv[1]);base='http://127.0.0.1:9316';job=json.loads((folder/'job.json').read_text());record=client.api(base,'/history/'+job['prompt_id'])[job['prompt_id']]
assert record['status']['completed']
client.save(folder/'history.json',record)
items=[]
for outputs in record['outputs'].values():
 for kind,values in outputs.items():
  if not isinstance(values,list):continue
  for item in values:
   if not isinstance(item,dict) or 'filename' not in item:continue
   suffix=Path(item['filename']).suffix.lower()
   if suffix not in {'.png','.jpg','.jpeg','.webp','.mp4','.webm','.gif','.wav','.flac'}:continue
   query=urllib.parse.urlencode({k:item[k] for k in ('filename','subfolder','type') if k in item})
   items.append(('/view?'+query,folder/'outputs'/f'{len(items):05d}{suffix}'))
original=client.request
cache={}
def fetch(pair):
 route,path=pair
 return route,path.read_bytes() if path.exists() else original(base,route)
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
 for route,data in pool.map(fetch,items):cache[route]=data
client.request=lambda url,route,data=None,content_type='application/json':cache[route]
client.download(base,folder,record)
print('EXISTING CLIENT DOWNLOAD COMPLETE',folder,len(items),flush=True)
