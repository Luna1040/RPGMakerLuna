"""Game assistant entry point: image, video, extract, matte, pack, check.

Use the existing embedded Python. Each subcommand forwards --help to its tool.
No model downloads, global queue cancellation, or automatic artwork approval.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import runpy
import sys

ROOT = Path(__file__).resolve().parents[1]
# Machine-local settings are ignored by Git; explicit environment takes priority.
_local_art_config = ROOT / '.game-assistant/art-config.json'
if _local_art_config.is_file():
    for _key, _value in json.loads(_local_art_config.read_text(encoding='utf-8-sig')).items():
        if _key in ('GAME_IMAGE_COMFY_URL', 'GAME_VIDEO_COMFY_URL', 'GAME_ART_PYTHON', 'GAME_MATTE_MODEL'):
            os.environ.setdefault(_key, str(_value))
SKILL = ROOT / 'shareable-skills/game-production'
RUNTIME = ROOT / 'character-generation-research/h3-runtime'
# Embedded Python ignores PYTHONPATH: expose the existing local dependencies.
sys.path[:0] = [str(SKILL / 'scripts'), str(RUNTIME / 'matte-deps'), str(RUNTIME / 'deps')]
os.environ.setdefault('COMFY_URL', os.environ.get('GAME_VIDEO_COMFY_URL', 'http://127.0.0.1:9316'))


def extract(arguments):
    p = argparse.ArgumentParser(description='Decode original video frames without cropping, resizing or recentering.')
    p.add_argument('--video', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--limit', type=int, help='Optional positive frame limit for inspection only')
    a = p.parse_args(arguments)
    if a.limit is not None and a.limit <= 0:
        p.error('--limit must be positive')
    import av
    records = []
    with av.open(str(a.video)) as video:
        stream = video.streams.video[0]
        rate = float(stream.average_rate or 24)
        a.out.mkdir(parents=True, exist_ok=False)
        canvas = None
        for i, frame in enumerate(video.decode(stream)):
            if a.limit is not None and i >= a.limit:
                break
            im = frame.to_image()
            if canvas is None:
                canvas = list(im.size)
            if list(im.size) != canvas:
                raise RuntimeError('Video changes dimensions; fixed canvas required')
            name = f'{i:05d}.png'
            im.save(a.out / name)
            records.append({'file': name, 'source_frame': i, 'time_seconds': frame.time})
    if not records:
        raise RuntimeError('No video frames decoded')
    (a.out / 'source-index.json').write_text(json.dumps({'source': str(a.video.resolve()), 'fps': rate, 'canvas': canvas, 'frames': records}, indent=2), encoding='utf-8')
    print(f'EXTRACT PASS: {len(records)} frames, canvas {canvas}', flush=True)


def check():
    from comfy_client import api
    from image_client import build
    results = {}
    graphs = [('image', os.environ.get('GAME_IMAGE_COMFY_URL', 'http://127.0.0.1:9315'), build('check',512,512,1)),
              ('video', os.environ['COMFY_URL'], json.loads((SKILL/'assets/h3-reference-api.json').read_text(encoding='utf-8')))]
    for kind, url, graph in graphs:
        try:
            schema = api(url, '/object_info')
            missing = []
            for node in graph.values():
                if node['class_type'] not in schema:
                    missing.append(node['class_type'])
                    continue
                inputs = schema[node['class_type']].get('input', {})
                fields = dict(inputs.get('required', {}), **inputs.get('optional', {}))
                for key, value in node['inputs'].items():
                    if key.endswith('_name') and key in fields and isinstance(fields[key][0], list) and value not in fields[key][0]:
                        missing.append(str(value))
            results[kind] = {'ok': not missing, 'url': url, 'missing': missing}
        except Exception as e:
            results[kind] = {'ok': False, 'url': url, 'error': str(e)}
    for name in ['av', 'PIL', 'numpy', 'onnxruntime']:
        try:
            __import__(name)
            results[name] = {'ok': True}
        except Exception as e:
            results[name] = {'ok': False, 'error': str(e)}
    model = Path(os.environ.get('GAME_MATTE_MODEL', str(RUNTIME/'matte-v2/birefnet-lite.onnx')))
    results['matte_model'] = {'ok': model.is_file(), 'path': str(model)}
    print(json.dumps(results, ensure_ascii=False, indent=2))
    return 0 if all(r['ok'] for r in results.values()) else 1


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ['-h','--help']:
        print(__doc__)
        return 0
    command, args = sys.argv[1], sys.argv[2:]
    if command == 'check':
        return check()
    if command == 'extract':
        extract(args)
        return 0
    scripts = {'image': 'image_client.py', 'video': 'comfy_client.py', 'matte': 'matte_frames.py', 'pack': 'pack_frames.py'}
    if command not in scripts:
        raise SystemExit('Unknown art command: '+command)
    if command == 'video' and 'submit' in args and '--workflow' not in args:
        args += ['--workflow', str(SKILL/'assets/h3-reference-api.json')]
    if command == 'matte' and '--model' not in args and '--help' not in args:
        args += ['--model', os.environ.get('GAME_MATTE_MODEL', str(RUNTIME/'matte-v2/birefnet-lite.onnx'))]
    target = SKILL/'scripts'/scripts[command]
    sys.argv = [str(target), *args]
    runpy.run_path(str(target), run_name='__main__')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
