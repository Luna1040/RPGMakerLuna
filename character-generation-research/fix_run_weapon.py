"""Regenerate the run with continuously visible forward-carried sword.

Generation is separate from publication: review raw frames before exporting.
"""
from pathlib import Path
import sys, json, time, urllib.request
sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_h3_smoke import ROOT, api, graph

OUT = ROOT / 'map-run-weapon-v2'
OUT.mkdir(exist_ok=True)

def generate():
    queue = api('/queue')
    if queue['queue_running'] or queue['queue_pending']:
        raise RuntimeError('H3 queue occupied; no competing generation submitted')
    g = graph('walk')
    g.pop('5')
    g['1']['inputs']['image'] = 'knight-clean-green.png'
    g['7']['inputs']['model'] = ['3', 0]
    g['10']['inputs'].update(model=['3', 0], steps=20, scheduler='normal')
    g['8']['inputs']['noise_seed'] = 831431
    g['6']['inputs'].update(width=768, height=768, length=124, prompt=(
        'The adult female knight in <Picture 1> runs fast IN PLACE facing right through several repeating sprint cycles. '
        'The camera sees her right side in a fixed side three-quarter view. '
        'Her near right hand firmly grips the gold sword hilt in front of her right hip for the ENTIRE video. '
        'She carries the sword forward in a low ready position: the long straight silver blade extends from that hand '
        'toward the right and slightly downward into the empty space IN FRONT of her body. '
        'The complete sword is clearly visible in EVERY frame, including its gold hilt, guard, continuous silver blade and sharp tip. '
        'The blade always stays in front of the knight silhouette and never passes behind her torso, cape, arms or legs. '
        'The right elbow stays bent and the sword-bearing right forearm remains in front of her waist, moving only slightly with her torso. '
        'The sword is one rigid object of constant full length; the hand remains connected to its hilt at all times. '
        'Her other left arm pumps naturally while both legs perform strong alternating high knee drives and powerful rear leg extensions, '
        'with clearly visible airborne running strides. Her whole torso leans forward, hips and shoulders counter-rotate, '
        'head follows the natural body rise and fall, and blonde ponytail and blue cape stream behind her. '
        'Steady fast treadmill running in the same place, several smooth repeating cycles. '
        'Preserve the beautiful detailed illustrated face, blonde ponytail, silver and gold armor, blue cape, boots and full length sword of the reference. '
        'Fixed camera, full body and whole sword visible, ample empty space on all sides, character occupies central 55 percent of canvas height. '
        'Clean detailed illustrated game sprite animation, crisp edges. Uniform pure black background. '
        'No sword sheathing, no changing hands, no backward sword swing, no disappearing weapon, no shortening blade, '
        'no magic, no trails, no motion blur, no floor, no ground shadow, no scenery, no text, no zoom, no lighting changes. Silent.'
    ))
    g['14']['inputs']['filename_prefix'] = 'map-run-weapon-v2'
    g['15']['inputs']['filename_prefix'] = 'frames/map-run-weapon-v2'
    (OUT/'workflow.json').write_text(json.dumps(g, indent=2))
    job = api('/prompt', {'prompt':g, 'client_id':'map-run-weapon-v2'})
    (OUT/'job.json').write_text(json.dumps(job))
    print('QUEUED', job, flush=True)
    while True:
        h = api('/history/'+job['prompt_id'])
        if job['prompt_id'] in h:
            r=h[job['prompt_id']]
            (OUT/'history.json').write_text(json.dumps(r, indent=2))
            print('FINISHED',r['status'],flush=True)
            if r['status']['status_str']!='success': raise RuntimeError('generation failed')
            break
        time.sleep(10)
    req=urllib.request.Request('http://127.0.0.1:9316/free',data=json.dumps({'unload_models':True,'free_memory':True}).encode(),headers={'Content-Type':'application/json'})
    with urllib.request.urlopen(req,timeout=60) as response: response.read()

def sheet():
    from PIL import Image, ImageDraw
    files=sorted((ROOT/'output/frames').glob('map-run-weapon-v2_*.png'))
    assert len(files)==124, len(files)
    for page in range(4):
        indices=list(range(page*32,min((page+1)*32,124)))
        canvas=Image.new('RGB',(1536,1536),'#20252f');d=ImageDraw.Draw(canvas)
        for n,idx in enumerate(indices):
            x=(n%8)*192;y=(n//8)*384
            pic=Image.open(files[idx]).crop((170,110,720,690)).resize((192,203))
            canvas.paste(pic,(x,y));d.text((x+6,y+210),str(idx),fill='white')
        canvas.save(OUT/f'raw-sheet-{page}.jpg')

def export():
    import hashlib
    import numpy as np
    from PIL import Image, ImageDraw
    from biref_h3_matte import session, extract
    from improve_h3_matte import matte
    spec=json.loads((OUT/'selection.json').read_text())
    dest=ROOT.parent.parent/'godot-belt-map/characters/first_knight/assets'
    manifest=dest/'combat-motion.json'
    data=json.loads(manifest.read_text())
    def untouched_hash(value):
        value=json.loads(json.dumps(value)); value['clips'].pop('run')
        return hashlib.sha256(json.dumps(value,sort_keys=True).encode()).hexdigest()
    before=untouched_hash(data)
    (OUT/'manifest-before.json').write_text(json.dumps(data,indent=2))
    files=sorted((ROOT/'output/frames').glob('map-run-weapon-v2_*.png'))
    folder=dest/'combat-motion/run-v2';folder.mkdir(parents=True,exist_ok=True)
    sess=session(use_gpu=True)
    images=[];raws=[];records=[]
    for i,idx in enumerate(spec['indices']):
        raw=Image.open(files[idx]).convert('RGB')
        cut=extract(sess,raw)
        a=np.array(cut);key=np.array(matte(raw,True));rgb=np.asarray(raw).astype(float)
        navy=(rgb[:,:,2]>18)&(rgb[:,:,2]-rgb[:,:,0]>8)&(rgb[:,:,2]-rgb[:,:,1]>3)&(rgb.max(2)<125)
        a[navy]=key[navy]
        # Explicitly reviewed per-frame sword regions use the precision black
        # key rather than AI semantic confidence, which can drop thin blades.
        if 'sword_boxes' in spec:
            x1,y1,x2,y2=spec['sword_boxes'][i]
            a[y1:y2,x1:x2]=key[y1:y2,x1:x2]
        cut=Image.fromarray(a)
        file=f'combat-motion/run-v2/{i:03d}.png';cut.save(dest/file)
        records.append({'source_frame':idx,'duration_ms':spec['frame_duration_ms'],'file':file})
        images.append(cut);raws.append(raw)
        print('EXPORTED',i,idx,flush=True)
    previews=[]
    for theme,color in [('dark','#182536'),('light','#dbe2eb'),('raw','#000000')]:
        canvas=Image.new('RGB',(1536,408*((len(images)+3)//4)),color);d=ImageDraw.Draw(canvas)
        for i,cut in enumerate(images):
            bg=Image.new('RGBA',(768,768),color)
            bg.alpha_composite(cut)
            pic=(raws[i] if theme=='raw' else bg.convert('RGB')).resize((384,384))
            x=(i%4)*384;y=(i//4)*408
            canvas.paste(pic,(x,y));d.text((x+8,y+386),f'{i}: source {records[i]["source_frame"]}',fill='#667788' if theme=='light' else '#ffffff')
            if theme=='dark':previews.append(pic)
        canvas.save(OUT/f'cycle-{theme}.png')
    previews[0].save(OUT/'run-preview.webp',save_all=True,append_images=previews[1:],duration=spec['frame_duration_ms'],loop=0,lossless=True)
    data['clips']['run']=dict(data['clips']['run'],frames=records,pivot=spec['pivot'],scale=spec['scale'],duration_ms=len(records)*spec['frame_duration_ms'],source='H3 '+json.loads((OUT/'job.json').read_text())['prompt_id'])
    after=untouched_hash(data)
    assert before==after
    (OUT/'publication-proof.json').write_text(json.dumps({'untouched_before_sha256':before,'untouched_after_sha256':after,'only_clip_changed':'run'},indent=2))
    manifest.write_text(json.dumps(data,indent=2))
    print('PUBLISHED run only; other manifest data SHA256',after,flush=True)

if __name__=='__main__':
    {'generate':generate,'sheet':sheet,'export':export}[sys.argv[1]]()
