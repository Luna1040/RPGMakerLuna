"""Local Flux image generation with optional reference and resumable ComfyUI jobs."""
import argparse
import json
import os
import secrets
from pathlib import Path
import time
import uuid
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from comfy_client import api, save, upload, wait


def build(prompt, width, height, seed, reference=None):
    graph = {
        '1': {'class_type': 'UNETLoader', 'inputs': {'unet_name': 'flux-2-klein-9b-fp8.safetensors', 'weight_dtype': 'default'}},
        '2': {'class_type': 'CLIPLoader', 'inputs': {'clip_name': 'qwen_3_8b_fp8mixed.safetensors', 'type': 'flux2', 'device': 'default'}},
        '3': {'class_type': 'VAELoader', 'inputs': {'vae_name': 'flux2-vae.safetensors'}},
        '4': {'class_type': 'CLIPTextEncode', 'inputs': {'clip': ['2', 0], 'text': prompt}},
        '5': {'class_type': 'ConditioningZeroOut', 'inputs': {'conditioning': ['4', 0]}},
        '6': {'class_type': 'EmptyFlux2LatentImage', 'inputs': {'width': width, 'height': height, 'batch_size': 1}},
        '7': {'class_type': 'RandomNoise', 'inputs': {'noise_seed': seed}},
        '8': {'class_type': 'KSamplerSelect', 'inputs': {'sampler_name': 'euler'}},
        '9': {'class_type': 'Flux2Scheduler', 'inputs': {'steps': 4, 'width': width, 'height': height}},
        '10': {'class_type': 'CFGGuider', 'inputs': {'model': ['1', 0], 'positive': ['4', 0], 'negative': ['5', 0], 'cfg': 1}},
        '11': {'class_type': 'SamplerCustomAdvanced', 'inputs': {'noise': ['7', 0], 'guider': ['10', 0], 'sampler': ['8', 0], 'sigmas': ['9', 0], 'latent_image': ['6', 0]}},
        '12': {'class_type': 'VAEDecode', 'inputs': {'samples': ['11', 0], 'vae': ['3', 0]}},
        '13': {'class_type': 'SaveImage', 'inputs': {'images': ['12', 0], 'filename_prefix': 'game-art/' + uuid.uuid4().hex}},
    }
    if reference:
        graph['14'] = {'class_type': 'LoadImage', 'inputs': {'image': reference}}
        graph['4'] = {'class_type': 'TextEncodeQwenImageEditPlus', 'inputs': {'clip': ['2', 0], 'vae': ['3', 0], 'prompt': prompt, 'image1': ['14', 0]}}
    return graph


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default=os.environ.get('GAME_IMAGE_COMFY_URL', 'http://127.0.0.1:9315'))
    sub = parser.add_subparsers(dest='command', required=True)
    submit = sub.add_parser('submit')
    submit.add_argument('--prompt-file', type=Path, required=True)
    submit.add_argument('--reference', type=Path)
    submit.add_argument('--width', type=int, default=768)
    submit.add_argument('--height', type=int, default=768)
    submit.add_argument('--seed', type=int, help='Fixed seed for reproduction; omitted means a fresh random seed')
    submit.add_argument('--out', type=Path, required=True)
    resume = sub.add_parser('wait')
    resume.add_argument('--out', type=Path, required=True)
    resume.add_argument('--timeout', type=int, default=1800)
    args = parser.parse_args()
    if args.command == 'wait':
        wait(args.url, args.out, args.timeout)
        return
    if any(n < 256 or n > 2048 or n % 16 for n in (args.width, args.height)):
        parser.error('Dimensions must be multiples of 16 between 256 and 2048')
    prompt = args.prompt_file.read_text(encoding='utf-8-sig').strip()
    if not prompt:
        parser.error('Prompt is empty')
    api(args.url, '/system_stats')
    args.out.mkdir(parents=True, exist_ok=False)
    reference = upload(args.url, args.reference) if args.reference else None
    seed = args.seed if args.seed is not None else secrets.randbits(53)
    graph = build(prompt, args.width, args.height, seed, reference)
    save(args.out / 'workflow.json', graph)
    client_id = 'game-image-' + uuid.uuid4().hex
    save(args.out / 'submission.json', {'client_id': client_id, 'url': args.url, 'time': time.time(), 'status': 'sending'})
    job = api(args.url, '/prompt', {'prompt': graph, 'client_id': client_id})
    save(args.out / 'job.json', job)
    print('Submitted:', job['prompt_id'], flush=True)


if __name__ == '__main__':
    main()
