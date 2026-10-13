"""Pack reviewed, fixed-canvas RGBA frames. Requires Pillow."""
import argparse
import json
import math
from pathlib import Path
import shutil
from PIL import Image


def pack(source, selection, out):
    spec = json.loads(selection.read_text(encoding='utf-8'))
    canvas = spec['canvas']
    assert len(canvas) == 2 and all(type(v) is int and v > 0 for v in canvas), 'Invalid canvas'
    assert len(spec['pivot']) == 2 and all(isinstance(v, (int, float)) and math.isfinite(v) for v in spec['pivot']), 'Invalid pivot'
    assert isinstance(spec['scale'], (int, float)) and math.isfinite(spec['scale']) and spec['scale'] > 0, 'Invalid scale'
    frames = spec['frames']
    assert frames, 'Empty selection'
    checked = []
    for frame in frames:
        name = frame['file']
        assert '\\' not in name and ':' not in name and not Path(name).is_absolute() and '..' not in Path(name).parts, 'Unsafe frame path'
        path = (source / name).resolve()
        assert path.is_relative_to(source.resolve()), 'Frame escapes source'
        assert type(frame['source_frame']) is int and frame['source_frame'] >= 0, 'Invalid source frame'
        assert type(frame['duration_ms']) is int and frame['duration_ms'] > 0, 'Invalid timing'
        with Image.open(path) as im:
            assert im.mode == 'RGBA' and list(im.size) == canvas, 'Expected fixed canvas RGBA'
            a = im.getchannel('A')
            assert a.getextrema()[0] == 0 and a.getbbox(), 'Missing transparency or empty frame'
            w, h = im.size
            assert all(a.crop(box).getbbox() is None for box in ((0, 0, w, 1), (0, h-1, w, h), (0, 0, 1, h), (w-1, 0, w, h))), 'Opaque canvas edge'
        checked.append(path)
    duration = sum(f['duration_ms'] for f in frames)
    event = spec.get('event_ms')
    assert event is None or (type(event) is int and 0 <= event < duration), 'Event outside action'
    out.mkdir(parents=True, exist_ok=False)
    exported = []
    for i, (frame, path) in enumerate(zip(frames, checked)):
        name = f'{i:04d}.png'
        shutil.copyfile(path, out / name)
        exported.append(dict(frame, file=name))
    result = dict(spec, frames=exported, duration_ms=duration)
    (out / 'action.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    images = [Image.open(p).convert('RGBA') for p in checked]
    images[0].save(out / 'review.webp', save_all=True, append_images=images[1:], duration=[f['duration_ms'] for f in frames], loop=0, lossless=True)
    for im in images:
        im.close()
    return result


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--selection', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    args = p.parse_args()
    print(json.dumps(pack(args.source, args.selection, args.out), ensure_ascii=False))
