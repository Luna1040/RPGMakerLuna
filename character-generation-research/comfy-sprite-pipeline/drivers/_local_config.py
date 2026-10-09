import os
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
COMFYUI_ROOT = Path(
    os.environ.get("COMFYUI_ROOT", str(PROJECT_ROOT.parent / "ComfyUI"))
).expanduser().resolve()
COMFY_URL = os.environ.get("COMFY_URL", "http://127.0.0.1:8000")

INPUT_DIR = COMFYUI_ROOT / "input"
OUTPUT_DIR = COMFYUI_ROOT / "output"

DEFAULT_IMAGE_SIZE = int(os.environ.get("CG_IMAGE_SIZE", "384"))
DEFAULT_NUM_FRAMES = int(os.environ.get("CG_NUM_FRAMES", "9"))
DEFAULT_CELL_SIZE = int(os.environ.get("CG_CELL_SIZE", "128"))

W1_UNET_NAME = os.environ.get("CG_W1_UNET", "Qwen-Image-Edit-2509-Q4_0.gguf")
W1_CLIP_NAME = os.environ.get("CG_W1_CLIP", "Qwen2.5-VL-7B-Instruct-Q4_0.gguf")
W1_VAE_NAME = os.environ.get("CG_W1_VAE", "qwen_image_vae.safetensors")
W1_LORA_NAME = os.environ.get(
    "CG_W1_LORA",
    "Qwen-Image-Edit-2509-Lightning-4steps-V1.0-bf16.safetensors",
)
W1_CONTROLNET_NAME = os.environ.get(
    "CG_W1_CONTROLNET",
    "Qwen-Image-InstantX-ControlNet-Union.safetensors",
)

W2_HIGH_UNET_NAME = os.environ.get(
    "CG_W2_HIGH_UNET",
    "wan2.2_i2v_A14b_high_noise_lightx2v_4step-Q4_0.gguf",
)
W2_LOW_UNET_NAME = os.environ.get(
    "CG_W2_LOW_UNET",
    "wan2.2_i2v_A14b_low_noise_lightx2v_4step-Q4_0.gguf",
)
W2_CLIP_NAME = os.environ.get("CG_W2_CLIP", "umt5-xxl-encoder-Q4_K_M.gguf")
W2_VAE_NAME = os.environ.get("CG_W2_VAE", "wan_2.1_vae.safetensors")

W4_UNET_NAME = os.environ.get("CG_W4_UNET", "Wan2.1_14B_VACE-Q4_0.gguf")
W4_CLIP_NAME = os.environ.get("CG_W4_CLIP", W2_CLIP_NAME)
W4_VAE_NAME = os.environ.get("CG_W4_VAE", W2_VAE_NAME)
W4_LORA_NAME = os.environ.get(
    "CG_W4_LORA",
    "Wan21_CausVid_14B_T2V_lora_rank32_v2.safetensors",
)
