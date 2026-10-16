from pathlib import Path
import json
import shutil
import uuid

ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT / 'h3-runtime'
CORE = next(RUNTIME.glob('ComfyUI-*'))
DEST = ROOT / 'guofeng-video-workflows'
SCHEMA = json.loads((RUNTIME / 'current-node-schema.json').read_text(encoding='utf-8-sig'))
DEST.mkdir(exist_ok=True)

def node(g, i, kind, **inputs):
    g[str(i)] = {'class_type': kind, 'inputs': inputs}

def graph(mode):
    g = {}
    node(g, 1, 'LoadImage', image='guofeng-demo-reference.png')
    node(g, 2, 'CLIPLoader', clip_name='qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors', type='minimax', device='default')
    node(g, 3, 'UNETLoader', unet_name='minimax_h3_ref2va_pruned_fp8_scaled.safetensors', weight_dtype='default')
    node(g, 4, 'VAELoader', vae_name='minimax_h3_video_vae_fp16.safetensors')
    prompt = ('Use the adult character in <Picture 1> as the identity reference. Chinese historical fantasy cinema, '
              'an adult swordswoman wearing flowing ivory and pale blue hanfu, traditional tied long hair, '
              'standing in a misty bamboo forest beside an ancient wooden pavilion. She slowly turns her head '
              'and raises a sheathed sword. Sleeves and hair move gently in the wind. Elegant restrained motion, '
              'consistent face and anatomy, cinematic soft light, detailed silk fabric. One continuous shot, '
              'slow camera push in. No modern clothes, no modern buildings, no text or watermark. Silent.')
    refs = {'ref_images.ref_image_0': ['1', 0]}
    model = ['3', 0]
    if mode != 3:
        node(g, 5, 'LoraLoaderModelOnly', model=model, lora_name='minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors', strength_model=1.0)
        model = ['5', 0]
    if mode >= 2:
        node(g, 20, 'LoadVideo', file='guofeng-demo-source.mp4')
        node(g, 21, 'GetVideoComponents', video=['20', 0])
        node(g, 22, 'ImageFromBatch', image=['21', 0], batch_index=0, length=124)
        node(g, 23, 'ImageScale', image=['22', 0], upscale_method='lanczos', width=512, height=640, crop='center')
        if mode == 2:
            node(g, 27, 'ImageScale', image=['23', 0], upscale_method='area', width=256, height=320, crop='center')
            refs['ref_videos.ref_video_0'] = ['27', 0]
        prompt = ('Recreate the action in <Video 1> with the adult character identity and Chinese historical costume '
                  'design from <Picture 1>. Preserve the order and timing of the body movements and the camera angle '
                  'from <Video 1>. Transform the character into an elegant Chinese wuxia swordswoman in flowing ivory '
                  'and pale blue hanfu, tied long black hair, silk sleeves. Replace the scene with a misty bamboo '
                  'forest and ancient pavilion. Chinese historical fantasy film, coherent face, hands and clothing '
                  'throughout the shot, soft cinematic light, no text, no watermark. Silent.')
        if mode == 3:
            prompt = ('Restyle the source shot as a Chinese historical fantasy film. Use <Picture 1> as the '
                      'adult character identity reference, with flowing ivory and pale blue hanfu, tied long '
                      'black hair, silk sleeves, and a sheathed sword. A misty bamboo forest and ancient wooden '
                      'pavilion replace the background. Preserve coherent body motion, composition and camera '
                      'view, consistent face, hands and clothing. Soft cinematic light. No modern clothes, '
                      'no text, no watermark. Silent.')
    node(g, 6, 'MiniMaxH3ReferenceToVideo', clip=['2', 0], vae=['4', 0], prompt=prompt,
         width=512, height=640, length=124, ref_image_size='match', **refs)
    node(g, 7, 'BasicGuider', model=model, conditioning=['6', 0])
    node(g, 8, 'RandomNoise', noise_seed=731429)
    node(g, 9, 'KSamplerSelect', sampler_name='res_multistep')
    node(g, 10, 'BasicScheduler', model=model, scheduler='normal' if mode == 3 else 'simple',
         steps=20 if mode == 3 else 4, denoise=0.6 if mode == 3 else 1.0)
    latent = ['6', 1]
    if mode == 3:
        g['1']['inputs']['image'] = 'guofeng-hanfu-reference.png'
        node(g, 24, 'VAEEncode', pixels=['23', 0], vae=['4', 0])
        node(g, 25, 'LTXVSeparateAVLatent', av_latent=['6', 1])
        node(g, 26, 'LTXVConcatAVLatent', video_latent=['24', 0], audio_latent=['25', 1])
        latent = ['26', 0]
        g['10']['inputs']['denoise'] = 0.75
    node(g, 11, 'SamplerCustomAdvanced', noise=['8', 0], guider=['7', 0], sampler=['9', 0], sigmas=['10', 0], latent_image=latent)
    node(g, 12, 'VAEDecodeTiled', samples=['11', 0], vae=['4', 0], tile_size=384, overlap=64, temporal_size=32, temporal_overlap=8)
    node(g, 13, 'CreateVideo', images=['12', 0], fps=24.0)
    node(g, 14, 'SaveVideo', video=['13', 0], filename_prefix=f'guofeng/{mode:02d}', format='mp4', **{'format.codec': 'h264'})
    return g

TITLES = {1: '01_古风参考图生成', 2: '02_视频动作参考转古风', 3: '03_视频潜空间重绘'}
LABELS = {1: '替换为古风角色或场景参考图（内置图仅供测试）', 6: '古风提示词 / 尺寸 / 帧数',
          10: '重绘强度 denoise（03 推荐 0.45–0.75）', 20: '源视频：请先处理为24fps、124帧',
          22: '前124帧（必须与节点6的length一致）', 23: '源视频尺寸（必须与节点6一致）',
          24: '源视频VAE编码', 25: '取出H3音频潜空间', 26: '合并源视频与H3音频潜空间'}
LABELS[27] = '动作参考降采样（降低显存，保留时序）'

def workflow(g, mode):
    nodes, links = [], []
    positions = {1: (0, 0), 2: (0, 450), 3: (0, 650), 4: (0, 850), 5: (450, 700),
                 6: (900, 0), 7: (1450, 0), 8: (1450, 170), 9: (1450, 340), 10: (1450, 510),
                 11: (1900, 0), 12: (1900, 330), 13: (2300, 0), 14: (2700, 0),
                 20: (0, 1100), 21: (450, 1100), 22: (450, 1300), 23: (900, 1100),
                 24: (900, 1430), 25: (900, 1650), 26: (1450, 1100), 27: (450, 1650)}
    for key, item in g.items():
        i, kind, values = int(key), item['class_type'], item['inputs']
        schema = SCHEMA[kind]
        ins, widgets, named = [], [], {}
        for name, spec in {**schema['input'].get('required', {}), **schema['input'].get('optional', {})}.items():
            typ = spec[0]
            if typ == 'COMFY_AUTOGROW_V3':
                for field, val in values.items():
                    if field.startswith(name + '.'):
                        ins.append({'name': field, 'label': field.split('.')[-1], 'type': 'IMAGE', 'link': None, 'shape': 7})
                continue
            if name not in values:
                if isinstance(typ, str) and typ not in ('INT', 'FLOAT', 'BOOLEAN', 'STRING', 'COMBO', 'COMFY_DYNAMICCOMBO_V3'):
                    ins.append({'name': name, 'type': typ, 'link': None})
                continue
            val = values[name]
            if isinstance(val, list):
                ins.append({'name': name, 'type': typ, 'link': None})
            else:
                widgets.append(val)
                named[name] = val
                if len(spec) > 1 and isinstance(spec[1], dict) and spec[1].get('control_after_generate'):
                    widgets.append('fixed')
        if kind == 'LoadImage':
            widgets.append('image')
        if kind == 'SaveVideo':
            widgets = [values['filename_prefix'], 'mp4', 'h264']
            named = {'filename_prefix': values['filename_prefix'], 'format': 'mp4', 'codec': 'h264'}
        outs = [{'name': name, 'type': typ, 'links': []} for name, typ in zip(schema['output_name'], schema['output'])]
        nodes.append({'id': i, 'type': kind, 'pos': positions[i], 'size': [470 if i == 6 else 350, 600 if i in (6, 14) else 260],
                      'flags': {}, 'order': len(nodes), 'mode': 0, 'inputs': ins, 'outputs': outs,
                      'title': LABELS.get(i, schema.get('display_name') or kind),
                      'properties': {'cnr_id': 'comfy-core', 'ver': '0.39.0', 'Node name for S&R': kind},
                      'widgets_values': widgets, 'widgets_values_named': named})
    by_id = {n['id']: n for n in nodes}
    for key, item in g.items():
        dest = by_id[int(key)]
        for name, value in item['inputs'].items():
            if not isinstance(value, list):
                continue
            src, slot = int(value[0]), value[1]
            target_slot = next(j for j, inp in enumerate(dest['inputs']) if inp['name'] == name)
            link_id = len(links) + 1
            dest['inputs'][target_slot]['link'] = link_id
            by_id[src]['outputs'][slot]['links'].append(link_id)
            links.append([link_id, src, slot, int(key), target_slot, by_id[src]['outputs'][slot]['type']])
    return {'id': str(uuid.uuid4()), 'revision': 0, 'last_node_id': max(by_id), 'last_link_id': len(links),
            'nodes': nodes, 'links': links, 'groups': [], 'config': {}, 'extra': {'ds': {'scale': 0.55, 'offset': [100, 100]}}, 'version': 0.4}

if __name__ == '__main__':
    user = CORE / 'user/default/workflows/古风视频'
    user.mkdir(parents=True, exist_ok=True)
    for mode, title in TITLES.items():
        g = graph(mode)
        (DEST / (title + '.api.json')).write_text(json.dumps(g, ensure_ascii=False, indent=2), encoding='utf-8')
        data = json.dumps(workflow(g, mode), ensure_ascii=False, indent=2)
        (DEST / (title + '.json')).write_text(data, encoding='utf-8')
        (user / (title + '.json')).write_text(data, encoding='utf-8')
    source = CORE / 'input/knight-reference.png'
    if source.exists():
        shutil.copyfile(source, CORE / 'input/guofeng-demo-reference.png')
    print(DEST)
