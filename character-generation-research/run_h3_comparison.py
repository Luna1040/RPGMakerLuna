"""Sequential benchmark with persisted jobs, histories and completed outputs."""
from pathlib import Path
import json,time,urllib.request,urllib.error,subprocess,shutil,argparse,sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from build_h3_comparison import DEST,ROOT,base,mbedit,save
from adapt_community_workflows import postprocess,keyframes,chain

URL='http://127.0.0.1:9317'
FFMPEG=r'C:\ffmpeg\bin\ffmpeg.exe'
FFPROBE=r'C:\ffmpeg\bin\ffprobe.exe'
INPUT=base.CORE/'input'
OUTPUT=base.RUNTIME/'output'

def api(path,payload=None):
    data=json.dumps(payload).encode() if payload is not None else None
    try:return json.load(urllib.request.urlopen(urllib.request.Request(URL+path,data,{'Content-Type':'application/json'}),timeout=120))
    except urllib.error.HTTPError as e:raise RuntimeError(e.read().decode()) from e

def probe(path):
    return json.loads(subprocess.check_output([FFPROBE,'-v','error','-select_streams','v:0','-show_entries','stream=width,height,nb_frames,r_frame_rate,duration','-of','json',str(path)]))['streams'][0]

def run(name,graph,minimum=240):
    done=DEST/(name+'.done.json')
    if done.exists():
        d=json.loads(done.read_text(encoding='utf-8'));p=Path(d['video'])
        if p.exists() and int(probe(p).get('nb_frames',0))>=minimum:return p
    save(name,graph)
    job=DEST/(name+'.job.json')
    if job.exists():
        response=json.loads(job.read_text());pid=response.get('prompt_id')
        hist=api('/history/'+pid) if pid else {}
        queue=api('/queue')
        active=any(v[1]==pid for v in queue.get('queue_running',[])+queue.get('queue_pending',[]))
        if not hist and not active:pid=None
    else:pid=None
    if not pid:
        response=api('/prompt',{'prompt':graph,'client_id':'h3-comparison-sequential'})
        job.write_text(json.dumps(response,indent=2));pid=response['prompt_id']
    print('RUNNING',name,pid,flush=True)
    last_note=0
    while True:
        history=api('/history/'+pid)
        if pid in history:
            h=history[pid]
            (DEST/(name+'.history.json')).write_text(json.dumps(h,ensure_ascii=False,indent=2),encoding='utf-8')
            if h.get('status',{}).get('status_str')!='success':
                raise RuntimeError(name+' failed: '+json.dumps(h.get('status'),ensure_ascii=False))
            files=[OUTPUT/x.get('subfolder','')/x['filename'] for v in h.get('outputs',{}).values() for x in v.get('images',[])+v.get('gifs',[]) if x['filename'].endswith('.mp4')]
            if not files:raise RuntimeError(name+' produced no MP4')
            p=files[-1];metadata=probe(p)
            if int(metadata.get('nb_frames',0))<minimum:raise RuntimeError(name+' output too short '+str(metadata))
            done.write_text(json.dumps({'video':str(p),'probe':metadata},ensure_ascii=False,indent=2),encoding='utf-8')
            print('DONE',name,str(p),metadata,flush=True)
            return p
        if time.time()-last_note>60:
            print('WAIT',name,time.strftime('%H:%M:%S'),flush=True);last_note=time.time()
        time.sleep(10)

def lastframe(video,name):
    p=INPUT/name
    subprocess.run([FFMPEG,'-y','-v','error','-sseof','-0.05','-i',str(video),'-frames:v','1',str(p)],check=True)
    return name

def combine(index,clips):
    folder=DEST/'final';folder.mkdir(exist_ok=True)
    listing=folder/f'{index:02d}_concat.txt'
    listing.write_text('\n'.join("file '"+str(p).replace('\\','/').replace("'","'\\''")+"'" for p in clips),encoding='utf-8')
    out=folder/f'{index:02d}_full_30s.mp4'
    subprocess.run([FFMPEG,'-y','-v','error','-f','concat','-safe','0','-i',str(listing),'-c','copy',str(out)],check=True)
    metadata=probe(out)
    if int(metadata.get('nb_frames',0))<700:raise RuntimeError('Master too short')
    subprocess.run([FFMPEG,'-v','error','-xerror','-i',str(out),'-map','0:v:0','-f','null','-'],check=True)
    metadata['decode_ok']=True
    (folder/f'{index:02d}_validation.json').write_text(json.dumps(metadata,indent=2))
    print('MASTER',out,metadata,flush=True)

def main():
    if (DEST/'render-hold.json').exists():
        raise SystemExit('Rendering held after a Windows bugcheck. Diagnose system stability before resuming; see h3-comparison/render-hold.json.')
    parser=argparse.ArgumentParser();parser.add_argument('--phase',choices=['baseline','rest','all'],default='all');args=parser.parse_args()
    baseline=[]
    if args.phase in ('baseline','all'):
        previous=None
        for shot in range(3):
            p=run(f'01_MBEDIT_Latent_shot{shot+1}',mbedit(shot,previous))
            baseline.append(p);shutil.copy2(p,INPUT/f'benchmark_baseline_shot{shot+1}.mp4')
            previous=lastframe(p,f'benchmark_01_last{shot+1}.png')
        combine(1,baseline)
    if args.phase=='baseline':return
    if not (DEST/'cuda13-ready.json').exists():raise RuntimeError('CUDA13 service restart must complete before rest phase')
    for index in (2,3):
        clips=[]
        for shot in range(3):clips.append(run(f'{index:02d}_Post_shot{shot+1}',postprocess(index,shot,f'benchmark_baseline_shot{shot+1}.mp4')))
        combine(index,clips)
    fl=base.RUNTIME/'models/diffusion_models/minimax_h3_fl2va_pruned_fp8_scaled.safetensors'
    while not fl.exists():print('WAIT verified native FL model download',flush=True);time.sleep(30)
    clips=[];previous=None
    for shot in range(3):
        p=run(f'04_Keyframes_shot{shot+1}',keyframes(shot,previous));clips.append(p)
        previous=lastframe(p,f'benchmark_04_last{shot+1}.png')
    combine(4,clips)
    for index in (5,6):
        p=run(f'{index:02d}_Chain',chain(index),minimum=700)
        final=DEST/'final'/f'{index:02d}_full_30s.mp4'
        shutil.copy2(p,final)
        subprocess.run([FFMPEG,'-v','error','-xerror','-i',str(final),'-map','0:v:0','-f','null','-'],check=True)
        metadata=probe(final);metadata['decode_ok']=True
        (DEST/'final'/f'{index:02d}_validation.json').write_text(json.dumps(metadata,indent=2))
    print('ALL_SIX_COMPLETE',flush=True)

if __name__=='__main__':main()
