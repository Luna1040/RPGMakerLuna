"""Trusted-team ComfyUI client. Python 3.10+, no third-party dependencies."""
import argparse
import copy
import json
import os
import secrets
from pathlib import Path
import time
import urllib.request
import urllib.parse
import uuid


def request(base, route, data=None, content_type='application/json'):
    body = json.dumps(data).encode() if isinstance(data, dict) else data
    req = urllib.request.Request(base.rstrip('/') + route, data=body,
                                 headers={'Content-Type': content_type})
    with urllib.request.urlopen(req, timeout=120) as response:
        return response.read()


def api(base, route, data=None):
    return json.loads(request(base, route, data))


def save(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')


def upload(base, path):
    image = path.read_bytes()
    if not image.startswith(b'\x89PNG\r\n\x1a\n'):
        raise ValueError('Reference must be PNG')
    if len(image) > 32 * 1024 * 1024:
        raise ValueError('Reference exceeds 32 MiB')
    name = 'team-' + uuid.uuid4().hex + '.png'
    boundary = uuid.uuid4().hex
    body = (f'--{boundary}\r\nContent-Disposition: form-data; name="image"; filename="{name}"\r\n'
            'Content-Type: image/png\r\n\r\n').encode() + image + f'\r\n--{boundary}--\r\n'.encode()
    result = json.loads(request(base, '/upload/image', body, 'multipart/form-data; boundary=' + boundary))
    return '/'.join(filter(None, [result.get('subfolder'), result['name']]))


def wait(base, folder, timeout):
    job = json.loads((folder / 'job.json').read_text(encoding='utf-8'))
    pid = job['prompt_id']
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        history = api(base, '/history/' + urllib.parse.quote(pid, safe=''))
        if pid in history:
            record = history[pid]
            save(folder / 'history.json', record)
            if record.get('status', {}).get('status_str') == 'error':
                raise RuntimeError('Generation failed; inspect history.json')
            if record.get('status', {}).get('completed'):
                download(base, folder, record)
                print('Completed:', folder)
                return
        time.sleep(5)
    raise TimeoutError('Still pending; use wait --out SAME_DIRECTORY. Do not submit again.')


def download(base, folder, record):
    outputs = folder / 'outputs'
    outputs.mkdir(exist_ok=True)
    index = []
    for node, value in record.get('outputs', {}).items():
        for kind, items in value.items():
            if not isinstance(items, list):
                continue
            for item in items:
                if not isinstance(item, dict) or 'filename' not in item:
                    continue
                # Never trust a remote filename as a local filesystem path.
                original = str(item['filename']).replace('\\', '/')
                leaf = original.rsplit('/', 1)[-1]
                suffix = Path(leaf).suffix.lower()
                if suffix not in {'.png', '.jpg', '.jpeg', '.webp', '.mp4', '.webm', '.gif', '.wav', '.flac'}:
                    continue
                local = f'{len(index):05d}{suffix}'
                query = urllib.parse.urlencode({k: item[k] for k in ('filename', 'subfolder', 'type') if k in item})
                data = request(base, '/view?' + query)
                temp = outputs / (local + '.part')
                temp.write_bytes(data)
                temp.replace(outputs / local)
                index.append({'file': local, 'node': node, 'kind': kind, 'remote': item})
    save(folder / 'output-index.json', index)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--url', default=os.environ.get('COMFY_URL', 'http://127.0.0.1:19316'))
    sub = p.add_subparsers(dest='command', required=True)
    check = sub.add_parser('check')
    check.add_argument('--workflow', type=Path)
    submit = sub.add_parser('submit')
    submit.add_argument('--workflow', type=Path, required=True)
    submit.add_argument('--reference', type=Path, required=True)
    submit.add_argument('--prompt-file', type=Path, required=True)
    submit.add_argument('--seed', type=int, help='Fixed seed for reproduction; omitted means a fresh random seed')
    submit.add_argument('--out', type=Path, required=True)
    resume = sub.add_parser('wait')
    resume.add_argument('--out', type=Path, required=True)
    resume.add_argument('--timeout', type=int, default=7200)
    args = p.parse_args()
    if args.command == 'check':
        stats = api(args.url, '/system_stats')
        print('ComfyUI reachable; devices:', len(stats.get('devices', [])))
        if args.workflow:
            graph = json.loads(args.workflow.read_text(encoding='utf-8'))
            schema = api(args.url, '/object_info')
            missing = sorted({n['class_type'] for n in graph.values()} - schema.keys())
            if missing:
                raise RuntimeError('Missing nodes: ' + ', '.join(missing))
            for node in graph.values():
                inputs = schema[node['class_type']].get('input', {})
                fields = dict(inputs.get('required', {}), **inputs.get('optional', {}))
                for key, value in node['inputs'].items():
                    if key.endswith('_name') and key in fields and isinstance(fields[key][0], list):
                        if value not in fields[key][0]:
                            raise RuntimeError(f'Missing or unsupported {key}: {value}')
            print('All workflow node classes and listed model/sampler choices available.')
    elif args.command == 'submit':
        # One folder per submission; an ambiguous HTTP timeout must not duplicate a GPU job.
        args.out.mkdir(parents=True, exist_ok=False)
        graph = copy.deepcopy(json.loads(args.workflow.read_text(encoding='utf-8')))
        graph['1']['inputs']['image'] = upload(args.url, args.reference)
        graph['6']['inputs']['prompt'] = args.prompt_file.read_text(encoding='utf-8')
        graph['8']['inputs']['noise_seed'] = args.seed if args.seed is not None else secrets.randbits(53)
        job_id = 'team/' + uuid.uuid4().hex
        graph['14']['inputs']['filename_prefix'] = job_id + '/video'
        graph['15']['inputs']['filename_prefix'] = job_id + '/frames'
        save(args.out / 'workflow.json', graph)
        save(args.out / 'submission.json', {'client_id': job_id, 'time': time.time(), 'status': 'sending'})
        job = api(args.url, '/prompt', {'prompt': graph, 'client_id': job_id})
        save(args.out / 'job.json', job)
        print('Submitted:', job['prompt_id'], '\nResume with wait --out', args.out)
    else:
        wait(args.url, args.out, args.timeout)


if __name__ == '__main__':
    main()
