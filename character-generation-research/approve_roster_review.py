"""Record an explicit completed visual review, then losslessly pack game copies.

This command does not perform visual review. Call only after inspecting the
source motion and every selected frame on light and dark backgrounds.
"""
import argparse,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import npc_roster_v1 as n

def approve(key, actions, note):
    path=n.OUT/'export'/key/'animation.json'
    manifest=n.read_json(path)
    specs=n.read_json(n.SPECS)
    review_path=n.OUT/'review-notes'/f'{key}-resume.json'
    review=n.read_json(review_path,{'id':key,'actions':{}})
    for action in actions:
        clip=manifest['actions'][action]
        spec=specs.setdefault(key,{}).setdefault(action,{})
        indices=[f['source_frame'] for f in clip['frames']]
        durations=[f['duration_ms'] for f in clip['frames']]
        if 'indices' in spec and (indices!=spec['indices'] or durations!=spec['durations']):
            raise ValueError(f'Unexported selection change: {key}/{action}')
        evidence=[f'{key}-{action}-all-{bg}.jpg' for bg in ('dark','light')]
        assert all((n.OUT/'review'/f).is_file() for f in evidence)
        spec.update(indices=indices,durations=durations,review_status='visually_reviewed')
        clip['review_status']='visually_reviewed'
        review['actions'][action]={'verdict':'accept','note':note,'indices':indices,'evidence':evidence}
        check_path=n.OUT/'review'/f'{key}-{action}-checks.json'
        checks=n.read_json(check_path)
        checks['review_status']='visually_reviewed'
        n.write_json(check_path,checks)
        n.write_json(n.OUT/'jobs'/key/action/'export-selection.json',spec)
    n.write_json(n.SPECS,specs)
    n.write_json(path,manifest)
    n.write_json(review_path,review)
    n.publish_reviewed([key])

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('id',choices=n.IDS)
    p.add_argument('--actions',nargs='+',required=True,choices=n.ACTION_ORDER)
    p.add_argument('--note',required=True)
    a=p.parse_args()
    approve(a.id,a.actions,a.note)
