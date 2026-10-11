"""Recover a complete SaveImage sequence without fabricating backend history."""
import argparse
import hashlib
import json
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from PIL import Image
from npc_roster_v1 import OUT, ROOT, read_json, write_json

def recover(key, action):
    job = OUT / 'jobs' / key / action
    workflow = read_json(job / 'workflow.json')
    prefix = workflow['15']['inputs']['filename_prefix']
    paths = sorted((ROOT / 'output').glob(prefix + '_*.png'))
    if len(paths) != 124:
        raise ValueError(f'Expected exactly 124 frames, found {len(paths)}')
    records = []
    expected = {k: {'class_type': v['class_type'], 'inputs': v['inputs']} for k, v in workflow.items()}
    for index, path in enumerate(paths):
        if path.name != f'{prefix.split("/")[-1]}_{index+1:05d}_.png':
            raise ValueError(f'Non-contiguous sequence: {path}')
        with Image.open(path) as im:
            im.load()
            if im.size != (768, 768):
                raise ValueError(f'Invalid size: {path}')
            prompt = json.loads(im.info['prompt'])
            actual = {k: {'class_type': v['class_type'], 'inputs': v['inputs']} for k, v in prompt.items()}
            if actual != expected:
                raise ValueError(f'Workflow provenance mismatch: {path}')
        records.append({'file': path.relative_to(ROOT / 'output').as_posix(), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    write_json(job / 'recovered-frames.json', {'reason': 'Backend crashed after PNG output; original history unavailable', 'validation': '124 contiguous decoded 768x768 PNGs; each embedded prompt matches saved workflow', 'workflow_sha256': hashlib.sha256((job / 'workflow.json').read_bytes()).hexdigest(), 'frames': records})
    print(f'RECOVERED {key}/{action}: {len(records)} verified frames')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('id')
    parser.add_argument('action')
    args = parser.parse_args()
    recover(args.id, args.action)
