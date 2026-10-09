from pathlib import Path
import concurrent.futures, json, urllib.request, zipfile
from install_pose_models import download
ROOT=Path(__file__).resolve().parent/'h3-runtime'
MODELS=ROOT/'models'
FILES=['diffusion_models/minimax_h3_ref2va_pruned_fp8_scaled.safetensors','text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors','loras/minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors','vae/minimax_h3_audio_vae_fp32.safetensors','vae/minimax_h3_video_vae_fp16.safetensors']
def core():
 ROOT.mkdir(parents=True,exist_ok=True)
 url='https://api.github.com/repos/Comfy-Org/ComfyUI/commits/master'
 info=json.load(urllib.request.urlopen(url,timeout=60)); sha=info['sha']
 (ROOT/'core-commit.txt').write_text(sha)
 target=ROOT/'comfyui.zip'
 urllib.request.urlretrieve('https://codeload.github.com/Comfy-Org/ComfyUI/zip/'+sha,target)
 with zipfile.ZipFile(target) as z:z.extractall(ROOT)
 print('CORE_READY',ROOT/('ComfyUI-'+sha),flush=True)
if __name__=='__main__':
 with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
  jobs=[pool.submit(download,('Comfy-Org/MiniMax-H3',f,MODELS/f)) for f in FILES]
  jobs.append(pool.submit(core))
  for future in concurrent.futures.as_completed(jobs):
   try:print(future.result(),flush=True)
   except Exception as e:print('DOWNLOAD_ERROR',repr(e),flush=True)
