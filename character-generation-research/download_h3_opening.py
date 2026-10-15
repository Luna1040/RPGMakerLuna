from pathlib import Path
import concurrent.futures
import hashlib
import json
import subprocess
import time
import urllib.request
import threading
import argparse

ROOT = Path(__file__).resolve().parent
MODELS = ROOT / 'h3-runtime/models'
MANIFEST = json.loads((ROOT / 'h3-sprite-workflow/model-manifest.json').read_text(encoding='utf-8-sig'))
FILES = ['diffusion_models/minimax_h3_fl2va_pruned_fp8_scaled.safetensors',
         'loras/minimax_h3_fl2v_turbo_8step_v1.0_comfyui_bf16.safetensors']
BLOCK = 8 * 1024 * 1024
ENTRIES = {e['rfilename']: e for e in MANIFEST['siblings']}
ENDPOINTS = {}
FIRST_ERROR = threading.Event()

def get(task):
    name, start, end = task
    part = MODELS / (name + '.opening-parts') / str(start)
    part.parent.mkdir(parents=True, exist_ok=True)
    if part.exists() and part.stat().st_size == end - start + 1:
        return end - start + 1
    url = f"https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/{MANIFEST['sha']}/{name}?download=true&part={start}"
    for attempt in range(5):
        result = subprocess.run(['curl.exe', '-f', '-sS', '-L', '--range', f'{start}-{end}',
                                 '--connect-timeout', '20', '--max-time', '180', '-o', str(part), url], capture_output=True)
        if result.returncode == 0 and part.stat().st_size == end - start + 1:
            return end - start + 1
        if not FIRST_ERROR.is_set():
            FIRST_ERROR.set()
            print('DOWNLOAD_RETRY', result.returncode, result.stderr.decode(errors='replace')[-250:], flush=True)
    raise RuntimeError(name + ': ' + result.stderr.decode(errors='replace')[-300:])

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--fl2va-only', action='store_true')
    parser.add_argument('--workers', type=int, default=16)
    args = parser.parse_args()
    if args.fl2va_only:
        FILES = FILES[:1]
    tasks = [(name, start, min(start + BLOCK, ENTRIES[name]['size']) - 1)
             for name in FILES if not (MODELS / name).exists()
             for start in range(0, ENTRIES[name]['size'], BLOCK)]
    total = sum(end - start + 1 for _, start, end in tasks)
    begun = time.time()
    completed = 0
    last = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        for result in concurrent.futures.as_completed([pool.submit(get, task) for task in tasks]):
            completed += result.result()
            if time.time() - last > 15:
                print(f'{completed/1e9:.2f}/{total/1e9:.2f} GB; {completed/max(1,time.time()-begun)/1e6:.1f} MB/s', flush=True)
                last = time.time()
    for name in FILES:
        destination = MODELS / name
        if destination.exists():
            continue
        temporary = destination.with_suffix('.opening-assembling')
        digest = hashlib.sha256()
        with temporary.open('wb') as output:
            for start in range(0, ENTRIES[name]['size'], BLOCK):
                with (MODELS / (name + '.opening-parts') / str(start)).open('rb') as source:
                    while chunk := source.read(4 * 1024 * 1024):
                        output.write(chunk)
                        digest.update(chunk)
        if digest.hexdigest() != ENTRIES[name]['lfs']['sha256']:
            raise RuntimeError('SHA256 mismatch: ' + name)
        temporary.rename(destination)
        print('VERIFIED', name, flush=True)
