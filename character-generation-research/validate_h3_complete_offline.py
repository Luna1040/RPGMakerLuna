"""Validate the six complete graphs without enqueuing or running a render."""
from pathlib import Path
import os, sys, asyncio, json, faulthandler

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
sys.stderr.reconfigure(encoding='utf-8', errors='replace')
faulthandler.dump_traceback_later(90, repeat=True)
ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT / 'h3-runtime'
CORE = next(RUNTIME.glob('ComfyUI-*'))
for p in (ROOT/'h3-plugin-deps', RUNTIME/'deps', ROOT/'h3-comparison-deps', CORE):
    sys.path.insert(0, str(p))
allowed = ['ComfyUI-KJNodes','Comfyui_Minimax_h3_latent_Upscaler','ComfyUI-MMH3Tools',
           'ComfyUI-H3-Multishot','ComfyUI-H3-Motion-Context','ComfyUI-VideoHelperSuite',
           'RES4LYF','Nvidia_RTX_Nodes_ComfyUI','ComfyUI-Easy-Use','ComfyUI-Custom-Scripts',
           'ComfyUI-H3-ComparisonIO']
os.chdir(CORE)
sys.argv = ['validate', '--cpu', '--disable-all-custom-nodes', '--whitelist-custom-nodes',
            *allowed, '--disable-partner-nodes', '--disable-auto-launch',
            '--extra-model-paths-config', str(ROOT/'h3-comparison/models.yaml')]
import main, nodes, execution, server

async def validate_all():
    server.PromptServer(asyncio.get_running_loop(), main.default_asset_manager())
    await nodes.init_extra_nodes(init_custom_nodes=True, init_api_nodes=False)
    results = {}
    for p in sorted((ROOT/'h3-comparison/complete-workflows').glob('*.api.json')):
        graph = json.loads(p.read_text(encoding='utf-8'))
        result = await execution.validate_prompt(p.stem, graph, None)
        results[p.name] = result
        print('VALIDATED', p.name, result, flush=True)
    (ROOT/'h3-comparison/complete-validation.json').write_text(
        json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
    if len(results) != 6 or not all(r[0] for r in results.values()):
        raise SystemExit('Complete workflow validation failed')

asyncio.run(validate_all())
