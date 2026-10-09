from pathlib import Path
import sys,os,runpy
root=Path(__file__).resolve().parent/'h3-runtime'
core=next(root.glob('ComfyUI-*'))
sys.path.insert(0,str(root/'deps'));sys.path.insert(0,str(core))
os.chdir(core)
config=root/'models.yaml'
config.write_text('h3:\n  base_path: '+str(root).replace('\\','/')+'\n  diffusion_models: models/diffusion_models\n  text_encoders: models/text_encoders\n  vae: models/vae\n  loras: models/loras\n',encoding='utf-8')
sys.argv=[str(core/'main.py'),'--listen','127.0.0.1','--port','9316','--extra-model-paths-config',str(config),'--disable-all-custom-nodes','--disable-partner-nodes','--disable-auto-launch','--reserve-vram','2','--output-directory',str(root/'output')]
runpy.run_path(str(core/'main.py'),run_name='__main__')
