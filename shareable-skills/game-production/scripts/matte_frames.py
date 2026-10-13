"""BiRefNet candidates for solid-black source frames; inspect previews before use."""
import argparse
from pathlib import Path
import numpy as np
from PIL import Image
import onnxruntime as ort


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--model', type=Path, required=True)
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    args = p.parse_args()
    files = sorted(args.source.glob('*.png'))
    if not files:
        p.error('Source contains no PNG frames; refusing an empty successful export')
    if not args.model.is_file():
        p.error('BiRefNet model does not exist')
    args.out.mkdir(parents=True, exist_ok=False)
    session = ort.InferenceSession(str(args.model), providers=['CPUExecutionProvider'])
    for file in files:
        im = Image.open(file).convert('RGB')
        rgb = np.asarray(im).astype(np.float32) / 255
        small = np.asarray(im.resize((1024, 1024), Image.Resampling.BILINEAR)).astype(np.float32) / 255
        x = (small - np.array([.485, .456, .406], np.float32)) / np.array([.229, .224, .225], np.float32)
        y = session.run(None, {session.get_inputs()[0].name: x.transpose(2, 0, 1)[None]})[-1].squeeze()
        if y.min() < 0 or y.max() > 1:
            y = 1 / (1 + np.exp(-np.clip(y, -30, 30)))
        a = np.clip(np.asarray(Image.fromarray(y.astype('float32')).resize(im.size, Image.Resampling.BILINEAR)), 0, 1)
        # RGB was composited over black: undo only for nonzero candidate coverage.
        color = np.clip(rgb / np.maximum(a[:, :, None], .08), 0, 1)
        result = Image.fromarray(np.dstack((color * 255, a * 255)).astype('uint8'), 'RGBA')
        result.save(args.out / file.name)
        preview = Image.new('RGB', (im.width * 2, im.height))
        for i, bg in enumerate(('#142030', '#f2f2f2')):
            layer = Image.new('RGBA', im.size, bg)
            layer.alpha_composite(result)
            preview.paste(layer.convert('RGB'), (i * im.width, 0))
        reviews = args.out / 'review'
        reviews.mkdir(exist_ok=True)
        preview.save(reviews / (file.stem + '.jpg'))
        print(file.name, flush=True)


if __name__ == '__main__':
    main()
