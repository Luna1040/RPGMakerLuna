from pathlib import Path
import json
import subprocess
import time
import urllib.request
import urllib.error

HERE = Path(__file__).resolve().parent
RUNTIME = HERE.parent / 'h3-runtime'
URL = 'http://127.0.0.1:9316'
MODELS = [RUNTIME / 'models/diffusion_models/minimax_h3_ref2va_pruned_fp8_scaled.safetensors',
          RUNTIME / 'models/loras/minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors']

def api(route, data=None):
    req = urllib.request.Request(URL + route, data=None if data is None else json.dumps(data).encode(), headers={'Content-Type': 'application/json'})
    try:
        raw = urllib.request.urlopen(req, timeout=60).read()
        return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raise RuntimeError(e.read().decode()) from e

if __name__ == '__main__':
    while not all(p.exists() for p in MODELS):
        print('WAITING_FOR_VERIFIED_I2V_MODELS', flush=True)
        time.sleep(15)
    q = api('/queue')
    if q['queue_running'] or q['queue_pending']:
        raise SystemExit('ComfyUI busy; no test jobs submitted.')
    api('/object_info/UNETLoader')
    api('/object_info/LoraLoaderModelOnly')
    for f in sorted(HERE.glob('*.api.json')):
        graph = json.loads(f.read_text(encoding='utf-8'))
        job = api('/prompt', {'prompt': graph, 'client_id': 'guofeng-opening-verification'})
        (HERE / (f.stem + '.job.json')).write_text(json.dumps(job, indent=2), encoding='utf-8')
        print('QUEUED', f.name, job, flush=True)
        while True:
            history = api('/history/' + job['prompt_id'])
            if job['prompt_id'] in history:
                record = history[job['prompt_id']]
                (HERE / (f.stem + '.history.json')).write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf-8')
                if record['status']['status_str'] != 'success':
                    raise RuntimeError(record['status'])
                print('SUCCESS', f.name, flush=True)
                videos = record['outputs']['14'].get('images', [])
                for video in videos:
                    source = RUNTIME / 'output' / video.get('subfolder', '') / video['filename']
                    if source.suffix == '.mp4':
                        output = HERE / (('preview' if f.name.startswith('01') else 'quality') + '-contact.jpg')
                        subprocess.run(['C:/ffmpeg/bin/ffmpeg.exe', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(source),
                                        '-vf', 'select=eq(n\\,0)+eq(n\\,40)+eq(n\\,80)+eq(n\\,120),scale=256:-2,tile=4x1',
                                        '-frames:v', '1', str(output)], check=True)
                break
            time.sleep(15)
