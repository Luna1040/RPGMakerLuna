"""Recover one already-submitted PNG by its unique output prefix; never submits or cancels jobs.
Standard-library download only. Use art_cli image wait first; retain missing-history evidence.
"""
import argparse
import json
from pathlib import Path
import struct
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parent

def fetch(url, route):
    return urllib.request.urlopen(url.rstrip('/') + route, timeout=20).read()

def save(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--job', type=Path, required=True)
    parser.add_argument('--url', default='http://127.0.0.1:19315')
    args = parser.parse_args()
    folder = args.job.resolve()
    if not folder.is_relative_to((ROOT/'art-jobs').resolve()):
        raise ValueError('Job must be inside this project art-jobs')
    job = json.loads((folder/'job.json').read_text(encoding='utf-8'))
    graph = json.loads((folder/'workflow.json').read_text(encoding='utf-8'))
    pid = job['prompt_id']
    queue = json.loads(fetch(args.url, '/queue'))
    own = [item for key in ('queue_running','queue_pending') for item in queue.get(key,[]) if len(item)>1 and item[1]==pid]
    if own:
        raise RuntimeError('Job is still queued/running. Resume art_cli wait; do not resubmit.')
    history_response = json.loads(fetch(args.url, '/history/'+urllib.parse.quote(pid,safe='')))
    save(folder/'history-response.json',history_response)
    history = history_response.get(pid)
    if history is not None:
        save(folder/'history.json',history)
    else:
        save(folder/'history.json',history_response)
    prefix = graph['13']['inputs']['filename_prefix']
    subfolder, leaf = prefix.rsplit('/',1)
    remote = {'filename':leaf+'_00001_.png','subfolder':subfolder,'type':'output'}
    raw = fetch(args.url, '/view?'+urllib.parse.urlencode(remote))
    if not raw.startswith(b'\x89PNG\r\n\x1a\n'):
        raise ValueError('Own output response is not a PNG')
    width,height = struct.unpack('>II',raw[16:24])
    expected = graph['6']['inputs']
    if (width,height)!=(expected['width'],expected['height']):
        raise ValueError('PNG dimensions differ from the submitted workflow')
    (folder/'outputs').mkdir(exist_ok=True)
    (folder/'outputs/00000.png.part').write_bytes(raw)
    (folder/'outputs/00000.png.part').replace(folder/'outputs/00000.png')
    save(folder/'output-index.json',[{'file':'00000.png','node':'13','kind':'images','remote':remote,'recovery':'Exact unique submitted SaveImage prefix; verified PNG dimensions'}])
    save(folder/'recovery-status.json',{'status':'actual_image_recovered','prompt_id':pid,'history_available':history is not None,'resubmitted':False,'width':width,'height':height,'missing_quality_check':None if history is not None else 'Original execution history not retained by service'})
    print('RECOVERED actual PNG:',folder/'outputs/00000.png','history_available:',history is not None)

if __name__=='__main__':
    main()
