"""Resumable, isolated ComfyUI jobs -> ground chunks + keyed props -> layered map."""
import json,time,hashlib,sys
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
from scipy.ndimage import label,distance_transform_edt,binary_dilation
sys.path.insert(0,str(Path(__file__).resolve().parent))
import generate_map_trial as api
ROOT=Path(__file__).resolve().parent;OUT=ROOT/'comfy-map-trials'/'desert-layered-v1'
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2),encoding='utf-8')
def prepare():
    OUT.mkdir(parents=True,exist_ok=True)
    source=ROOT/'comfy-map-trials'/'desert-town-v1'/'location-source.json'
    m=json.loads(source.read_text(encoding='utf-8'));write(OUT/'location-source.json',m)
    blueprint=Image.new('RGB',(768,768),'#ff00ff');d=ImageDraw.Draw(blueprint)
    d.rectangle((96,220,672,476),fill='#a77344',outline='#563f2d',width=8)
    d.line((96,348,672,348),fill='#d29f66',width=12)
    d.rectangle((108,476,660,526),fill='#c4a479');d.rectangle((352,475,416,526),fill='#3b3028')
    blueprint.save(OUT/'building-blueprint.png')
    style='Authentic crisp pixel-art RPG asset, orthographic overhead with only a narrow south-facing facade, hand-placed square pixel clusters, controlled warm ochre and terracotta palette, no smooth painterly brushstrokes, no photorealism, no blur, no text, no watermark. '
    ground='A single continuous tileable desert sand ground texture seen straight from above, warm golden ochre sand, subtle sparse dune ripples, tiny mineral grains and very occasional tiny pebbles, quiet readable ground for an RPG. Absolutely no buildings, vegetation, characters, roads, interface or border. Even soft daylight with no cast shadows. '
    tasks=[{'id':f'ground-{r}-{c}','kind':'ground','width':640,'height':512,'seed':202610100+r*2+c,'tile':{'row':r,'column':c,'core':[512,384],'overlap':64},'prompt':style+ground+f'Variation {r*2+c+1}: slightly different ripple pattern but exactly the same overall sand palette and scale.'} for r in range(2) for c in range(2)]
    building='Use the input only as the size and placement blueprint. Render exactly ONE entire charming desert adobe building in the center, including a detailed terracotta tiled roof, chimney, small south-facing facade, wooden door at bottom center and shutters. Keep the roof inside the broad horizontal reference rectangle. Complete silhouette, generous empty margin all sides, no clipped edges. No floor, no terrain, no plants, no loose props, no characters, no cast shadow. Background must be completely flat saturated magenta RGB(255,0,255), including all empty gaps. No magenta or pink anywhere on the building, no rim light or color spill, no gradient background. '
    for i,kind in enumerate(['inn','workshop','supply']):
        detail={'inn':'A cozy inn with two shuttered windows and a cream fabric sunshade attached to its facade.','workshop':'A workshop with stone walls, copper chimney and wooden double doors.','supply':'A small provisions store with sun-bleached plaster walls and a simple tiled roof.'}[kind]
        tasks.append({'id':'building-'+kind,'kind':'keyed-building','width':768,'height':768,'seed':202610110+i,'reference':'building-blueprint.png','prompt':style+building+detail})
    for i,(kind,desc) in enumerate([('cactus','ONE cactus with three branching arms and small natural spines, full silhouette, no pot'),('crate','ONE closed weathered wooden supply crate with metal corner brackets')]):
        tasks.append({'id':'prop-'+kind,'kind':'keyed-prop','width':512,'height':512,'seed':202610120+i,'prompt':style+'Isolated game object: '+desc+'. Object centered occupying about 60 percent of image, ample margin, no terrain, no floor, no shadow. Entire empty background is perfectly uniform saturated magenta RGB(255,0,255), including every internal gap. Object contains no magenta or pink. No other objects.'})
    spec={'version':1,'worldLocationId':m['worldLocationId'],'mapId':m['id'],'biome':m['biome'],'pipeline':['world context + layout contract','four overlapping ground chunks','three independent architecture assets','two independent small props','background compliance gate','key and enclosed background removal','fringe color recovery','fixed-canvas/pivot manifest','separate ground/buildings/props/shadows','composite preview + matte QA'],'groundGrid':{'columns':2,'rows':2,'tileSize':[640,512],'coreSize':[512,384],'overlapPixels':128,'assembledSize':[1024,768]},'tasks':tasks,'mattePolicy':{'background':'magenta','rejectNonUniformCorners':True,'removeEnclosedKeyIslands':True,'noBlanketWhiteOrBlackRemoval':True,'noCharacterSpecificBlueRescue':True,'neuralMaskIsNotGroundTruth':True,'preserveSourceCanvas':True,'separateShadows':True},'status':'planned'}
    write(OUT/'layered-workflow.json',spec);print('PREPARED',len(tasks),'isolated generation jobs',flush=True)
def run():
    spec=json.loads((OUT/'layered-workflow.json').read_text(encoding='utf-8'))
    for task in spec['tasks']:
        folder=OUT/task['id'];folder.mkdir(exist_ok=True)
        if (folder/'raw.png').exists():print('SKIP',task['id'],flush=True);continue
        if (folder/'job.json').exists():pid=json.loads((folder/'job.json').read_text())['prompt_id']
        else:
            for port in [9315,9316]:
                q=json.load(api.urllib.request.urlopen(f'http://127.0.0.1:{port}/queue',timeout=10))
                if q['queue_running'] or q['queue_pending']:raise RuntimeError(f'Port {port} busy. Resume later; no foreign jobs interrupted.')
            w=json.loads((api.BASE/'Flux2Klein_edit.json').read_text(encoding='utf-8-sig'))
            for n in ['352','357','364','371','370','346','355']:w.pop(n,None)
            w['325']['inputs']['model']=['329',0];enc=w['365']['inputs'];enc['prompt']=task['prompt']
            for n in ['image1','image2','image3']:enc.pop(n,None)
            ref=OUT/task['reference'] if task.get('reference') else (OUT/'ground-0-0'/'raw.png' if task['kind']=='ground' and task['id']!='ground-0-0' else None)
            if ref:
                w['355']={'class_type':'LoadImage','inputs':{'image':api.upload(ref)}};enc['image1']=['355',0]
            for n in ['327','328']:w[n]['inputs']['width'],w[n]['inputs']['height']=task['width'],task['height']
            w['354']['inputs']['noise_seed']=task['seed'];w['341']['inputs']['filename_prefix']='CodexMapLayers/'+task['id']
            write(folder/'workflow.json',w);job=api.post('/prompt',{'prompt':w,'client_id':'codex-map-layers'});write(folder/'job.json',job);pid=job['prompt_id'];print('SUBMITTED',task['id'],pid,flush=True)
        start=time.time()
        while time.time()-start<900:
            h=api.get('/history/'+pid)
            if pid in h:
                entry=h[pid];write(folder/'history.json',entry)
                if entry.get('status',{}).get('status_str')=='error':raise RuntimeError(str(entry['status']))
                images=entry.get('outputs',{}).get('341',{}).get('images',[])
                if images:
                    folder.joinpath('raw.png').write_bytes(api.urllib.request.urlopen(api.URL+'/view?'+api.urllib.parse.urlencode(images[0]),timeout=60).read());print('COMPLETE',task['id'],flush=True);break
            time.sleep(4)
        else:raise TimeoutError('Resume same job, do not resubmit')
    spec['status']='generated-raw';write(OUT/'layered-workflow.json',spec)
def key_asset(folder):
    im=Image.open(folder/'raw.png').convert('RGB');rgb=np.array(im).astype(np.float32);h,w=rgb.shape[:2]
    corners=np.concatenate([rgb[:24,:24].reshape(-1,3),rgb[:24,-24:].reshape(-1,3),rgb[-24:,:24].reshape(-1,3),rgb[-24:,-24:].reshape(-1,3)])
    key=np.median(corners,axis=0);dist=np.linalg.norm(rgb-key,axis=2)
    # Only accept the requested chroma, never silently substitute a white/black key.
    good_key=key[0]>180 and key[2]>110 and key[1]<70 and key[0]-key[1]>110 and key[2]-key[1]>80
    spread=float(np.percentile(np.linalg.norm(corners-key,axis=1),95))
    if not good_key or spread>24:
        write(folder/'matte-qa.json',{'accepted':False,'reason':'Background non-compliance; regenerate or use independently reviewed neural mask','cornerColor':key.tolist(),'cornerSpread95':spread});raise RuntimeError(folder.name+' nonuniform/nonmagenta background')
    border=np.concatenate([dist[0],dist[-1],dist[:,0],dist[:,-1]])
    key_radius=max(28,min(65,float(np.percentile(border,99.9))+5))
    # Calibrate within the verified saturated pink/magenta family; never key white/black.
    family=(rgb[:,:,0]>180)&(rgb[:,:,2]>110)&(rgb[:,:,1]<70)&(np.abs((rgb[:,:,0]-rgb[:,:,2])-(key[0]-key[2]))<45)
    pure=(dist<key_radius)|family
    # This removes enclosed magenta gaps as well as outside background, without touching pale walls.
    labels,n=label(pure);border_ids=np.unique(np.concatenate([labels[0],labels[-1],labels[:,0],labels[:,-1]]));islands=[i for i in range(1,n+1) if i not in border_ids]
    fg_candidate=(dist>110)&(~pure)
    # Do not treat contaminated silhouette pixels as certain foreground colors.
    # Interior color seeds let the edge solver recover RGB from mixed chroma.
    fg_seed=fg_candidate&(~binary_dilation(pure,iterations=2))
    if not fg_seed.any():fg_seed=fg_candidate
    if not fg_seed.any():raise RuntimeError('No foreground')
    _,nearest=distance_transform_edt(~fg_seed,return_indices=True);foreground=rgb[nearest[0],nearest[1]]
    vec=foreground-key;alpha=np.clip(np.sum((rgb-key)*vec,axis=2)/np.maximum(np.sum(vec*vec,axis=2),1),0,1)
    alpha[fg_seed]=1;alpha[pure]=0
    components,count=label(alpha>.02)
    supported=set(np.unique(components[fg_candidate]))-{0}
    unsupported=[i for i in range(1,count+1) if i not in supported]
    if unsupported:alpha[np.isin(components,unsupported)]=0
    # Edge unmixing removes magenta spill rather than drawing opaque purple rims.
    recovered=np.clip((rgb-(1-alpha[:,:,None])*key)/np.maximum(alpha[:,:,None],.02),0,255)
    recovered[alpha<.02]=0;alpha[alpha<.02]=0
    rgba=Image.fromarray(np.dstack([recovered,alpha*255]).astype(np.uint8),'RGBA')
    if (folder/'rgba.png').exists() and not (folder/'rgba-key-v1.png').exists():(folder/'rgba-key-v1.png').write_bytes((folder/'rgba.png').read_bytes())
    rgba.save(folder/'rgba.png')
    a=np.asarray(rgba)[:,:,3];bbox=rgba.getchannel('A').getbbox();opaque_border=int(np.count_nonzero(np.concatenate([a[0],a[-1],a[:,0],a[:,-1]])>8))
    retained_key=int(np.count_nonzero((a>220)&pure));accepted=opaque_border==0 and retained_key==0 and bbox is not None
    qa={'accepted':accepted,'sourceSha256':hashlib.sha256((folder/'raw.png').read_bytes()).hexdigest(),'canvas':[w,h],'alphaBBox':bbox,'pivot':[w//2,bbox[3] if bbox else h],'cornerColor':key.tolist(),'cornerSpread95':spread,'calibratedKeyRadius':key_radius,'enclosedKeyComponentsRemoved':len(islands),'unsupportedNoiseIslandsRemoved':len(unsupported),'opaqueBorderPixels':opaque_border,'opaqueKeyPixels':retained_key,'softAlphaPixels':int(((a>0)&(a<255)).sum()),'method':'validated pink/magenta family + enclosed holes + local edge color unmixing + unsupported chroma-noise removal','limits':'For opaque pixel assets, not transparent glass/glow. Color math does not verify semantic foreground completeness; inspect QA sheet.'};write(folder/'matte-qa.json',qa)
    sheet=Image.new('RGB',(w*3,h),'#171f2b')
    for i,bg in enumerate(['#f3efe3','#142338','#667966']):
        panel=Image.new('RGBA',im.size,bg);panel.alpha_composite(rgba);sheet.paste(panel.convert('RGB'),(i*w,0))
    sheet.save(folder/'matte-contact-sheet.png')
    if not accepted:raise RuntimeError('Failed alpha gate '+folder.name)
    return qa
def build():
    spec=json.loads((OUT/'layered-workflow.json').read_text(encoding='utf-8'));m=json.loads((OUT/'location-source.json').read_text(encoding='utf-8'))
    accum=np.zeros((768,1024,3),np.float64);weight=np.zeros((768,1024),np.float64)
    for task in spec['tasks'][:4]:
        rgb=np.asarray(Image.open(OUT/task['id']/'raw.png').convert('RGB'),dtype=float);th,tw=rgb.shape[:2];row,col=task['tile']['row'],task['tile']['column'];ox=col*512-64;oy=row*384-64
        wx=np.minimum(np.minimum((np.arange(tw)+1)/128,(tw-np.arange(tw))/128),1);wy=np.minimum(np.minimum((np.arange(th)+1)/128,(th-np.arange(th))/128),1);ww=wy[:,None]*wx[None,:]
        x0,y0=max(0,ox),max(0,oy);x1,y1=min(1024,ox+tw),min(768,oy+th);sl=np.s_[y0-oy:y1-oy,x0-ox:x1-ox];accum[y0:y1,x0:x1]+=rgb[sl]*ww[sl][:,:,None];weight[y0:y1,x0:x1]+=ww[sl]
    ground=Image.fromarray((accum/weight[:,:,None]).clip(0,255).astype('uint8'),'RGB')
    gd=ImageDraw.Draw(ground)
    # Roads remain deterministic and independently editable, rather than asking AI to hallucinate connectivity.
    roads=Image.new('RGBA',ground.size);rd=ImageDraw.Draw(roads)
    for y in range(m['height']):
        for x in range(m['width']):
            if m['layers']['ground'][y*m['width']+x]=='path':rd.rectangle((x*16,y*16,x*16+15,y*16+15),fill=(224,191,125,175))
    ground.save(OUT/'ground.png');roads.save(OUT/'roads.png')
    buildings=Image.new('RGBA',ground.size);props=Image.new('RGBA',ground.size);shadows=Image.new('RGBA',ground.size);placements=[];visible=[];road_mask=np.array(roads)[:,:,3]>0
    assets={}
    for task in spec['tasks'][4:]:assets[task['id']]=key_asset(OUT/task['id'])
    kinds={'旅店':'inn','工坊':'workshop','补给站':'supply'}
    for o in m['layers']['objects']:
        if o.get('footprint'):
            asset='building-'+kinds[o['kind']];f=o['footprint'];target=[f['x']*16,f['y']*16,f['width']*16,f['height']*16];layer=buildings
        elif o['kind']=='仙人掌':asset='prop-cactus';target=[o['x']*16-7,o['y']*16-22,30,38];layer=props
        else:continue
        source=Image.open(OUT/asset/'rgba.png');bbox=tuple(assets[asset]['alphaBBox']);cut=source.crop(bbox);cut.thumbnail((target[2],target[3]),Image.Resampling.NEAREST);x=target[0]+(target[2]-cut.width)//2;y=target[1]+target[3]-cut.height
        if layer is props and road_mask[max(0,y):min(768,y+cut.height),max(0,x):min(1024,x+cut.width)].any():continue
        layer.alpha_composite(cut,(x,y));visible.append({**o,'assetRef':'/layered-assets/'+asset+'/rgba.png','renderBounds':[x,y,cut.width,cut.height]});shadow=Image.new('RGBA',cut.size,(48,33,20,0));shadow.putalpha(cut.getchannel('A').point(lambda a:int(a*.23)));shadows.alpha_composite(shadow,(x+4,y+4));placements.append({'objectId':o['id'],'assetId':asset,'sourceCanvas':source.size,'sourceCrop':bbox,'targetBounds':[x,y,cut.width,cut.height],'anchor':'bottom-center','worldLocationId':m['worldLocationId']})
    # Add independently generated crates only near the shop, clear of the entry path.
    source=Image.open(OUT/'prop-crate'/'rgba.png');bbox=tuple(assets['prop-crate']['alphaBBox']);cut=source.crop(bbox);cut.thumbnail((22,22),Image.Resampling.NEAREST)
    for i,(x,y) in enumerate([(38*16,17*16),(39*16,17*16),(25*16,29*16)]):props.alpha_composite(cut,(x,y));visible.append({'id':'crate-'+str(i),'x':x//16,'y':y//16,'kind':'物资箱','assetRef':'/layered-assets/prop-crate/rgba.png','renderBounds':[x,y,cut.width,cut.height]});placements.append({'assetId':'prop-crate','sourceCanvas':source.size,'sourceCrop':bbox,'targetBounds':[x,y,cut.width,cut.height],'anchor':'bottom-center'})
    for name,layer in [('buildings',buildings),('props',props),('shadows',shadows)]:layer.save(OUT/(name+'.png'))
    result=ground.convert('RGBA')
    for layer in [roads,shadows,buildings,props]:result.alpha_composite(layer)
    result.save(OUT/'scene.png');write(OUT/'placement-manifest.json',{'mapId':m['id'],'layers':['ground.png','roads.png','shadows.png','buildings.png','props.png'],'previewSize':[1024,768],'pixelsPerMapCell':16,'nativeTilePixels':32,'placements':placements,'assetQA':assets,'collisionStatus':'procedural object bases; not extracted from artwork','shadowMethod':'separate procedural approximate shadow, not recovered baked lighting'})
    collision=[int(x==0 or y==0 or x==m['width']-1 or y==m['height']-1) for y in range(m['height']) for x in range(m['width'])]
    for o in visible:
        f=o.get('footprint')
        if f:
            for yy in range(f['y'],f['y']+f['height']):
                for xx in range(f['x'],f['x']+f['width']):collision[yy*m['width']+xx]=1
        else:collision[o['y']*m['width']+o['x']]=1
    for k,b in enumerate(m['layers']['ground']):
        if b=='path':collision[k]=0
    m['layers']['objects']=visible;m['layers']['collision']=collision;m['assetStatus']='ai-layered-preview';m['art']={'imageUrl':'/layered-assets/scene.png','layerUrls':{n:'/layered-assets/'+n+'.png' for n in ['ground','roads','shadows','buildings','props']},'workflow':'/layered-assets/layered-workflow.json','previewOnly':True,'collisionVerified':False,'pixelsPerCell':16};write(OUT/'location-assembled.json',m)
    spec['status']='composited-matte-gates-passed';write(OUT/'layered-workflow.json',spec);print('BUILT',str(OUT/'scene.png'),flush=True)
if __name__=='__main__':{'prepare':prepare,'run':run,'build':build}[sys.argv[1]]()
