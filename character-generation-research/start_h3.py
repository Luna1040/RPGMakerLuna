from pathlib import Path
import sys,os,runpy
root=Path(__file__).resolve().parent/'h3-runtime'
core=next(root.glob('ComfyUI-*'))
for path in (root.parent/'h3-plugin-deps', root/'deps', root.parent/'h3-comparison-deps', core):
    sys.path.insert(0,str(path))
sys.stdout.reconfigure(encoding='utf-8',errors='replace')
sys.stderr.reconfigure(encoding='utf-8',errors='replace')
os.chdir(core)
config=root/'models.yaml'
config.write_text('h3:\n  base_path: '+str(root).replace('\\','/')+'\n  diffusion_models: models/diffusion_models\n  text_encoders: models/text_encoders\n  vae: models/vae\n  loras: models/loras\n  latent_upscale_models: models/latent_upscale_models\n  custom_nodes: ../h3-community-nodes\n',encoding='utf-8')
sys.argv=[str(core/'main.py'),'--listen','127.0.0.1','--port','9316','--extra-model-paths-config',str(config),'--disable-all-custom-nodes','--disable-partner-nodes','--disable-auto-launch','--reserve-vram','2','--vram-headroom','3','--disable-comfy-compiler','--output-directory',str(root/'output')]
# These two installed plugins are required by the single-image MBEDIT workflow.
sys.argv.extend(['--whitelist-custom-nodes','ComfyUI-VideoHelperSuite','Comfyui_Minimax_h3_latent_Upscaler'])
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'godot-ai-workbench'))
from gpu_job_guard import run_comfy
run_comfy(core / 'main.py')
