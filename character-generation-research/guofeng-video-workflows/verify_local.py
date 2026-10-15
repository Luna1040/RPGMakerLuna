from pathlib import Path
import json
import time
import urllib.request
import urllib.error
import sys

ROOT = Path(__file__).resolve().parent
URL = 'http://127.0.0.1:9316'

def api(route, data=None, base=URL):
    req = urllib.request.Request(base + route, data=None if data is None else json.dumps(data).encode(), headers={'Content-Type': 'application/json'})
    try:
        raw = urllib.request.urlopen(req, timeout=60).read()
        return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raise RuntimeError(e.read().decode()) from e

if __name__ == '__main__':
    q = api('/queue')
    if q['queue_running'] or q['queue_pending']:
        raise SystemExit('H3 queue busy; no test jobs submitted.')
    q = api('/queue', base='http://127.0.0.1:9315')
    if not q['queue_running'] and not q['queue_pending']:
        api('/free', {'unload_models': True, 'free_memory': True}, base='http://127.0.0.1:9315')
    jobs = []
    for f in sorted(ROOT.glob('*.api.json')):
        if len(sys.argv) > 1 and f.name[:2] not in sys.argv[1:]:
            continue
        graph = json.loads(f.read_text(encoding='utf-8'))
        job = api('/prompt', {'prompt': graph, 'client_id': 'guofeng-local-verification'})
        jobs.append({'file': f.name, **job})
        print('QUEUED', f.name, job, flush=True)
    (ROOT / 'verification-jobs.json').write_text(json.dumps(jobs, ensure_ascii=False, indent=2), encoding='utf-8')
    pending = {j['prompt_id']: j for j in jobs}
    while pending:
        for pid, job in list(pending.items()):
            h = api('/history/' + pid)
            if pid in h:
                record = h[pid]
                (ROOT / (job['file'] + '.history.json')).write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf-8')
                print('FINISHED', job['file'], record['status'], flush=True)
                pending.pop(pid)
        if pending:
            print('WAITING', len(pending), flush=True)
            time.sleep(15)
