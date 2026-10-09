"""Local Flux2 image-edit trial from the saved world/location contract."""
import argparse,json,time,uuid,urllib.request,urllib.parse,urllib.error
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parent
BASE=Path('C:/Users/11043/Downloads/Flux2_klein_v1.0_普通版/Flux2_klein')
OUT=ROOT/'comfy-map-trials'/'desert-town-v1'
URL='http://127.0.0.1:9315'
def get(route):
    return json.load(urllib.request.urlopen(URL+route,timeout=30))
def post(route,data):
    try:
        return json.load(urllib.request.urlopen(urllib.request.Request(URL+route,json.dumps(data).encode(),{'Content-Type':'application/json'}),timeout=30))
    except urllib.error.HTTPError as e:
        raise RuntimeError(e.read().decode()) from e
def upload(p):
    boundary=uuid.uuid4().hex
    b=(f'--{boundary}\r\nContent-Disposition: form-data; name="image"; filename="atlas-{p.name}"\r\nContent-Type: image/png\r\n\r\n').encode()+p.read_bytes()+f'\r\n--{boundary}--\r\n'.encode()
    d=json.load(urllib.request.urlopen(urllib.request.Request(URL+'/upload/image',b,{'Content-Type':'multipart/form-data; boundary='+boundary}),timeout=30))
    return '/'.join(filter(None,[d.get('subfolder',''),d['name']]))
def prepare():
    OUT.mkdir(parents=True,exist_ok=True)
    world=json.loads((ROOT/'local-atlas'/'world-state.json').read_text(encoding='utf-8-sig'))
    p=next(p for p in world['places'] if p['name']=='青苔镇')
    m=world['maps'][p['mapId']]
    (OUT/'world-source.json').write_text(json.dumps(world,ensure_ascii=False),encoding='utf-8')
    (OUT/'location-source.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
    scale=16
    im=Image.new('RGB',(m['width']*scale,m['height']*scale),'#cba264');d=ImageDraw.Draw(im)
    for y in range(m['height']):
        for x in range(m['width']):
            if m['layers']['ground'][y*m['width']+x]=='path':d.rectangle((x*scale,y*scale,(x+1)*scale-1,(y+1)*scale-1),fill='#e4cb92')
    for o in m['layers']['objects']:
        x,y=o['x']*scale,o['y']*scale
        if o.get('footprint'):
            f=o['footprint'];box=(f['x']*scale,f['y']*scale,(f['x']+f['width'])*scale-1,(f['y']+f['height'])*scale-1)
            d.rectangle(box,fill='#704e38',outline='#3e3029',width=3)
            d.line((box[0],(box[1]+box[3])//2,box[2],(box[1]+box[3])//2),fill='#ae8153',width=5)
        else:
            rock=o['kind'] in ['风蚀岩','沙丘'];d.ellipse((x+3,y+3,x+13,y+13),fill='#9e774d' if rock else '#567346')
    for e in m['entrances']:
        if e['kind']=='door':d.rectangle((e['x']*scale,e['y']*scale,(e['x']+1)*scale-1,(e['y']+1)*scale-1),fill='#493328')
    im.save(OUT/'layout-reference.png')
    sx,sy=round(p['x']),round(p['y']);cw,ch=48,32
    crop=Image.new('RGB',(cw,ch));pixels=crop.load()
    for y in range(ch):
        for x in range(cw):
            wx=max(0,min(world['width']-1,sx+x-cw//2));wy=max(0,min(world['height']-1,sy+y-ch//2));k=wy*world['width']+wx
            pixels[x,y]=tuple(bytes.fromhex(world['biomeCatalog'][world['biomes'][k]]['color'][1:]))
    crop=crop.resize((768,512),Image.Resampling.NEAREST);d=ImageDraw.Draw(crop);cx,cy=cw//2*16,ch//2*16;d.ellipse((cx-8,cy-8,cx+8,cy+8),fill='#f56854',outline='white',width=2);crop.save(OUT/'world-context.png')
    prompt="""Use image 1 as the exact overhead settlement layout blueprint. Image 2 is ONLY the surrounding world biome context, with a red dot marking this settlement; do NOT copy image 2 as a panel or add a red dot. Transform image 1 into a beautiful finished top-down pixel-art RPG desert settlement map, one continuous edge-to-edge landscape, 1024x768, coherent square pixel grid, crisp small pixel clusters, rich handcrafted game environment detail. This town lies in an arid sandy part of the world. Warm ochre sand, subtle dune ridges, weathered sandstone boulders, sparse cactus and desert scrub, small clay pots, crates, market supplies, awnings and charming adobe architecture, warm sun and delicate short shadows. Preserve exactly the three large building footprints, their positions, dimensions and south-facing entrances: inn at upper left, workshop at upper right, supply house below center. Preserve the existing pale sandy footpaths and their connectivity to the south-center map entrance. Upgrade brown blocks to richly detailed terracotta roofs and adobe facades in those same rectangles. Replace small dots with natural desert props at approximately those positions without blocking paths. Do not add any large new buildings. The bottom-center approach must remain open and walkable. No ocean or large water body inside this local map. Roof visibility, strictly overhead orthographic camera, no horizon, no angled isometric view. No people, no text, no labels, no user interface, no frames, no collage, no grid lines, no watermark. The result is a game scene illustration; preserve blueprint layout, enrich only the artwork."""
    (OUT/'prompt.txt').write_text(prompt,encoding='utf-8')
    print(json.dumps({'location':p,'reference':str(OUT/'layout-reference.png'),'context':str(OUT/'world-context.png')},ensure_ascii=False),flush=True)
def submit():
    if (OUT/'job.json').exists():raise RuntimeError('Existing job.json; resume it rather than duplicate submission')
    for port in [9315,9316]:
        q=json.load(urllib.request.urlopen(f'http://127.0.0.1:{port}/queue',timeout=10))
        if q['queue_running'] or q['queue_pending']:raise RuntimeError(f'ComfyUI {port} busy; no submission')
    w=json.loads((BASE/'Flux2Klein_edit.json').read_text(encoding='utf-8-sig'))
    for n in ['357','364','371','370','346']:w.pop(n,None)
    w['325']['inputs']['model']=['329',0]
    w['355']['inputs']['image']=upload(OUT/'layout-reference.png')
    w['352']['inputs']['image']=upload(OUT/'world-context.png')
    enc=w['365']['inputs'];enc['prompt']=(OUT/'prompt.txt').read_text(encoding='utf-8');enc['image1']=['355',0];enc['image2']=['352',0];enc.pop('image3',None)
    for n in ['327','328']:w[n]['inputs']['width'],w[n]['inputs']['height']=1024,768
    w['354']['inputs']['noise_seed']=202610091
    w['341']['inputs']['filename_prefix']='CodexMapTrial/desert-town-v1'
    (OUT/'workflow.json').write_text(json.dumps(w,ensure_ascii=False,indent=2),encoding='utf-8')
    job=post('/prompt',{'prompt':w,'client_id':'codex-map-trial'})
    (OUT/'job.json').write_text(json.dumps(job,indent=2),encoding='utf-8');print('SUBMITTED',job['prompt_id'],flush=True)
def resume():
    pid=json.loads((OUT/'job.json').read_text())['prompt_id'];start=time.time()
    while time.time()-start<900:
        h=get('/history/'+pid)
        if pid in h:
            entry=h[pid];(OUT/'history.json').write_text(json.dumps(entry,ensure_ascii=False,indent=2),encoding='utf-8')
            if entry.get('status',{}).get('status_str')=='error':raise RuntimeError(str(entry['status']))
            images=entry.get('outputs',{}).get('341',{}).get('images',[])
            if images:
                for i,img in enumerate(images):
                    with urllib.request.urlopen(URL+'/view?'+urllib.parse.urlencode(img),timeout=60) as r:(OUT/('scene.png' if i==0 else f'scene-{i}.png')).write_bytes(r.read())
                print('COMPLETE',str(OUT/'scene.png'),flush=True);return
        time.sleep(4)
    raise TimeoutError('Still pending; resume existing prompt_id')
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['prepare','submit','resume']);a=parser.parse_args()
    {'prepare':prepare,'submit':submit,'resume':resume}[a.action]()
