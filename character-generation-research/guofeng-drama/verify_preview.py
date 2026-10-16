from pathlib import Path
import json
import subprocess
import sys
import time
import urllib.request

HERE = Path(__file__).resolve().parent
RUNTIME = HERE.parent / 'h3-runtime'
mode = 'quality' if '--quality' in sys.argv else 'preview'
jobfile = 'quality.job.json' if mode == 'quality' else 'preview-full.job.json'
job = json.loads((HERE / jobfile).read_text(encoding='utf-8'))['prompt_id']
for _ in range(1080):
    with urllib.request.urlopen('http://127.0.0.1:9316/history/' + job, timeout=30) as response:
        data = json.load(response)
    if job not in data:
        time.sleep(10)
        continue
    record = data[job]
    (HERE / f'{mode}.history.json').write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf-8')
    if record['status']['status_str'] != 'success':
        raise RuntimeError(record['status'])
    outputs = {}
    for node in ('14', '114', '214', '351'):
        for item in record['outputs'].get(node, {}).get('images', []):
            source = RUNTIME / 'output' / item.get('subfolder','') / item['filename']
            probe = subprocess.run(['C:/ffmpeg/bin/ffprobe.exe','-v','error','-show_entries','stream=width,height,nb_frames,r_frame_rate:format=duration','-of','json',str(source)], capture_output=True, text=True, check=True)
            outputs[node] = {'path':str(source),'probe':json.loads(probe.stdout)}
            if node != '351':
                subprocess.run(['C:/ffmpeg/bin/ffmpeg.exe','-hide_banner','-loglevel','error','-y','-i',str(source),'-vf','fps=0.5,scale=240:-2,tile=5x1','-frames:v','1',str(HERE / f'{mode}-shot-{node}-contact.jpg')], check=True)
    (HERE / f'{mode}-validation.json').write_text(json.dumps(outputs,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(outputs,ensure_ascii=True),flush=True)
    break
else:
    raise TimeoutError('Preview did not finish within the verification window')
