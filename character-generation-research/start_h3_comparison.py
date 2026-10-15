from pathlib import Path
import os
import runpy
import sys

# Community nodes print Unicode status marks; Windows redirected pipes default
# to GBK and can otherwise terminate the prompt worker during a valid render.
sys.stdout.reconfigure(encoding='utf-8',errors='replace')
sys.stderr.reconfigure(encoding='utf-8',errors='replace')

ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT / 'h3-runtime'
CORE = next(RUNTIME.glob('ComfyUI-*'))
for path in (ROOT/'h3-plugin-deps', RUNTIME/'deps', ROOT/'h3-comparison-deps', CORE):
    sys.path.insert(0, str(path))
config = ROOT/'h3-comparison/models.yaml'
config.write_text('h3_comparison:\n  base_path: '+str(RUNTIME).replace('\\','/')+'\n'
                  '  diffusion_models: models/diffusion_models\n'
                  '  text_encoders: models/text_encoders\n'
                  '  vae: models/vae\n'
                  '  loras: models/loras\n'
                  '  latent_upscale_models: models/latent_upscale_models\n'
                  '  custom_nodes: ../h3-community-nodes\n', encoding='utf-8')
allowed = ['ComfyUI-KJNodes','Comfyui_Minimax_h3_latent_Upscaler','ComfyUI-MMH3Tools',
           'ComfyUI-H3-Multishot','ComfyUI-H3-Motion-Context','ComfyUI-VideoHelperSuite',
           'RES4LYF','Nvidia_RTX_Nodes_ComfyUI','ComfyUI-Easy-Use','ComfyUI-Custom-Scripts',
           'ComfyUI-H3-ComparisonIO']
cpu = '--cpu' in sys.argv
os.chdir(CORE)
sys.argv = [str(CORE/'main.py'),'--listen','127.0.0.1','--port','9317',
            '--extra-model-paths-config',str(config),'--disable-all-custom-nodes',
            '--whitelist-custom-nodes',*allowed,'--disable-partner-nodes','--disable-auto-launch',
            '--reserve-vram','2','--vram-headroom','3','--disable-comfy-compiler',
            '--output-directory',str(RUNTIME/'output'),
            *(['--cpu'] if cpu else [])]
runpy.run_path(str(CORE/'main.py'),run_name='__main__')
