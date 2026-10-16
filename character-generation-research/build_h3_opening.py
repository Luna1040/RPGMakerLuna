from pathlib import Path
import json
import build_guofeng_workflows as base

ROOT = Path(__file__).resolve().parent
DEST = ROOT / 'guofeng-opening'
DEST.mkdir(exist_ok=True)
PROMPT = '''Animate the supplied first frame into a cinematic opening shot for a Chinese historical fantasy film. Preserve the characters, faces, costumes, architecture, lighting and visual style already present in the image. Keep the scene recognizable throughout.

One continuous elegant shot. Begin with a brief calm hold. The camera then makes a very slow, smooth dolly forward, creating subtle natural depth and parallax. If a person is present, use only natural breathing, a subtle blink, and a very small head movement; keep the face stable. Hair, silk sleeves and ribbons move gently in a light breeze. If present in the image, mist drifts softly, leaves sway subtly and water has faint ripples. Do not add objects or people that are absent from the original scene. Let the camera gently settle near the end, leaving a calm moment suitable for adding a title in post-production.

Restrained poetic motion, cinematic atmosphere, consistent anatomy and composition, natural temporal continuity. No walking cycle, running, combat, exaggerated gestures, rapid camera movement, cuts, scene changes, text, logos, or watermarks. Silent.'''

def make(fast):
    g = base.graph(1)
    g['1']['inputs']['image'] = 'guofeng-hanfu-reference.png'
    base.node(g, 20, 'ImageScaleToTotalPixels', image=['1', 0], upscale_method='lanczos',
              megapixels=0.33 if fast else 0.59, resolution_steps=32)
    base.node(g, 21, 'GetImageSize', image=['20', 0])
    base.node(g, 6, 'MiniMaxH3ReferenceToVideo', clip=['2', 0], vae=['4', 0], prompt=PROMPT,
              width=['21', 0], height=['21', 1], length=124, ref_image_size='match', **{'ref_images.ref_image_0':['20', 0]})
    base.node(g, 22, 'MiniMaxH3AddGuide', positive=['6', 0], latent=['6', 1], vae=['4', 0], image=['20', 0], frame_idx=0)
    g['7']['inputs']['conditioning'] = ['22', 0]
    if fast:
        g['10']['inputs'].update(steps=4, scheduler='simple')
    else:
        g.pop('5')
        g['7']['inputs']['model'] = ['3', 0]
        g['10']['inputs'].update(model=['3', 0], steps=20, scheduler='normal')
    g['14']['inputs']['filename_prefix'] = 'guofeng-opening/' + ('preview' if fast else 'quality')
    return g

if __name__ == '__main__':
    saved = base.CORE / 'user/default/workflows/古风开场动画'
    saved.mkdir(parents=True, exist_ok=True)
    for fast, title in [(True, '01_一张图生成古风开场_快速预览'), (False, '02_一张图生成古风开场_精细成片')]:
        g = make(fast)
        w = base.workflow(g, 1)
        labels = {1: '上传你的开场原图（人物图或场景图均可）', 6: '开场镜头：运镜、微动作、环境动态',
                  10: '采样：保持denoise=1', 20: '自动适配原图比例（按32像素对齐）', 21: '从图片自动读取画幅',
                  22: '把上传原图锚定到首帧（frame_idx=0）'}
        for n in w['nodes']:
            if n['id'] in labels:
                n['title'] = labels[n['id']]
            if n['id'] == 20:
                n['pos'] = [450, 0]
            if n['id'] == 21:
                n['pos'] = [450, 320]
            if n['id'] == 22:
                n['pos'] = [900, 720]
            if n['id'] == 6:
                n['widgets_values'] = [PROMPT, 1024, 576, 124, 'match']
                n['widgets_values_named'] = {'prompt': PROMPT, 'width': 1024, 'height': 576, 'length': 124, 'ref_image_size': 'match'}
                for inp in n['inputs']:
                    if inp['name'] in ('width', 'height'):
                        inp['widget'] = {'name': inp['name']}
        payload = json.dumps(w, ensure_ascii=False, indent=2)
        (saved / (title + '.json')).write_text(payload, encoding='utf-8')
        (DEST / (title + '.json')).write_text(payload, encoding='utf-8')
        (DEST / (title + '.api.json')).write_text(json.dumps(g, ensure_ascii=False, indent=2), encoding='utf-8')
    print(DEST)
