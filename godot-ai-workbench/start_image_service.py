"""Start the existing local Flux models on loopback; no weights are downloaded."""
import json, os, runpy, sys, urllib.request
from pathlib import Path

root = Path(__file__).resolve().parents[1]
runtime = root / 'character-generation-research/h3-runtime'
base = Path(os.environ.get('GAME_FLUX_HOME', str(Path.home() / 'Downloads/Flux2_klein_v1.0_普通版/Flux2_klein')))
try:
    with urllib.request.urlopen('http://127.0.0.1:9315/system_stats', timeout=3) as response:
        json.load(response)
    print('Image service already running on 9315')
    raise SystemExit(0)
except OSError:
    pass
models = base / 'ComfyUI/models'
if not (models / 'unet/flux-2-klein-9b-fp8.safetensors').is_file():
    raise SystemExit('Missing Flux 9B model; set GAME_FLUX_HOME to existing installation')
core = next(runtime.glob('ComfyUI-*'))
data = root / '.game-assistant'
data.mkdir(exist_ok=True)
config = data / 'image-models.yaml'
config.write_text('flux:\n  base_path: ' + json.dumps(str(models), ensure_ascii=False) + '\n  diffusion_models: unet\n  text_encoders: text_encoders\n  vae: vae\n', encoding='utf-8')
sys.path[:0] = [str(runtime / 'deps'), str(core)]
os.chdir(core)
sys.argv = [str(core / 'main.py'), '--listen', '127.0.0.1', '--port', '9315', '--extra-model-paths-config', str(config), '--disable-all-custom-nodes', '--disable-partner-nodes', '--disable-auto-launch', '--lowvram', '--output-directory', str(data / 'image-output')]
runpy.run_path(str(core / 'main.py'), run_name='__main__')
