from __future__ import annotations

import importlib.util
import json
import tempfile
import time
import urllib.request
from functools import lru_cache
from pathlib import Path
from typing import Any

from .catalog import POSE_GUIDE_MOTIONS


CANONICAL_MODELS = (
    ("unet", "Qwen-Image-Edit-2509-Q4_0.gguf"),
    ("clip", "Qwen2.5-VL-7B-Instruct-Q4_0.gguf"),
    ("clip", "Qwen2.5-VL-7B-Instruct-mmproj-F16.gguf"),
    ("controlnet", "Qwen-Image-InstantX-ControlNet-Union.safetensors"),
    ("loras", "Qwen-Image-Edit-2509-Lightning-4steps-V1.0-bf16.safetensors"),
    ("vae", "qwen_image_vae.safetensors"),
)

LOOP_MODELS = (
    ("unet", "wan2.2_i2v_A14b_high_noise_lightx2v_4step-Q4_0.gguf"),
    ("unet", "wan2.2_i2v_A14b_low_noise_lightx2v_4step-Q4_0.gguf"),
    ("clip", "umt5-xxl-encoder-Q4_K_M.gguf"),
    ("vae", "wan_2.1_vae.safetensors"),
)

POSE_MODELS = (
    ("unet", "Wan2.1_14B_VACE-Q4_0.gguf"),
    ("clip", "umt5-xxl-encoder-Q4_K_M.gguf"),
    ("vae", "wan_2.1_vae.safetensors"),
    ("loras", "Wan21_CausVid_14B_T2V_lora_rank32_v2.safetensors"),
)

VISEME_ATLAS_MODELS = (
    ("unet", "Qwen-Image-Edit-2509-Q4_0.gguf"),
    ("clip", "Qwen2.5-VL-7B-Instruct-Q4_0.gguf"),
    ("clip", "Qwen2.5-VL-7B-Instruct-mmproj-F16.gguf"),
    ("loras", "Qwen-Image-Edit-2509-Lightning-4steps-V1.0-bf16.safetensors"),
    ("vae", "qwen_image_vae.safetensors"),
)

RUNTIME_EXPORT_MODELS = (
    ("RMBG/BiRefNet", "birefnet.py"),
    ("RMBG/BiRefNet", "BiRefNet_config.py"),
    ("RMBG/BiRefNet", "BiRefNet_toonout.safetensors"),
    ("RMBG/BiRefNet", "config.json"),
)

CANONICAL_NODES = {
    "UnetLoaderGGUF",
    "CLIPLoaderGGUF",
    "TextEncodeQwenImageEditPlus",
    "SetUnionControlNetType",
    "ControlNetApplyAdvanced",
    "VRAMUnloadClip",
    "VRAMUnloadModel",
}
LOOP_NODES = {
    "UnetLoaderGGUF",
    "CLIPLoaderGGUF",
    "WanFirstLastFrameToVideo",
    "VRAMUnloadClip",
    "VRAMUnloadModel",
    "CreateVideo",
    "SaveVideo",
    "VAEDecodeTiled",
}
POSE_NODES = {
    "WanVaceToVideo",
    "LoadVideo",
    "GetVideoComponents",
    "ImageToMask",
    "RepeatImageBatch",
    "ImageCompositeMasked",
    "TrimVideoLatent",
    "VAEDecodeTiled",
}
REPAIR_NODES = {
    "WanVaceToVideo",
    "LoadVideo",
    "GetVideoComponents",
    "ImageToMask",
    "ImageCompositeMasked",
    "TrimVideoLatent",
    "VAEDecodeTiled",
    "CreateVideo",
    "SaveVideo",
}
VISEME_ATLAS_NODES = {
    "UnetLoaderGGUF",
    "LoraLoaderModelOnly",
    "ModelSamplingAuraFlow",
    "CFGNorm",
    "CLIPLoaderGGUF",
    "VAELoader",
    "LoadImage",
    "ImageCrop",
    "ImageScale",
    "TextEncodeQwenImageEditPlus",
    "VAEEncode",
    "VRAMUnloadClip",
    "KSampler",
    "VRAMUnloadModel",
    "VAEDecode",
    "SaveImage",
}
RUNTIME_EXPORT_NODES = {
    "LoadVideo",
    "GetVideoComponents",
    "ImageFromBatch",
    "BiRefNetRMBG",
    "SaveImage",
}


def _fetch_json(url: str, timeout: float = 3.0) -> dict[str, Any]:
    with urllib.request.urlopen(url, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def _model_state(models_root: Path, requirements: tuple[tuple[str, str], ...]) -> tuple[list[str], list[str]]:
    present: list[str] = []
    missing: list[str] = []
    for folder, name in requirements:
        if (models_root / folder / name).is_file():
            present.append(name)
        else:
            missing.append(name)
    return present, missing


def _node_state(comfy_url: str, names: set[str]) -> tuple[list[str], list[str]]:
    present: list[str] = []
    missing: list[str] = []
    for name in sorted(names):
        try:
            payload = _fetch_json(f"{comfy_url}/object_info/{name}")
        except Exception:
            payload = {}
        (present if name in payload else missing).append(name)
    return present, missing


@lru_cache(maxsize=1)
def _ffv1_encoder_available() -> bool:
    """Probe the local OpenCV build used to stage W12 lossless frames."""

    try:
        import cv2
        import numpy as np

        with tempfile.TemporaryDirectory(prefix="studio-ffv1-probe-") as temporary:
            target = str(Path(temporary) / "probe.mkv")
            writer = cv2.VideoWriter(target, cv2.VideoWriter_fourcc(*"FFV1"), 1.0, (16, 16))
            try:
                if not writer.isOpened():
                    return False
                writer.write(np.zeros((16, 16, 3), dtype=np.uint8))
            finally:
                writer.release()
            return Path(target).is_file() and Path(target).stat().st_size > 0
    except Exception:
        return False


def inspect_capabilities(
    *,
    project_root: Path,
    comfyui_root: Path,
    comfy_url: str,
) -> dict[str, Any]:
    models_root = comfyui_root / "models"
    online = False
    system: dict[str, Any] = {}
    try:
        stats = _fetch_json(f"{comfy_url}/system_stats")
        system = stats.get("system", {})
        devices = stats.get("devices", [])
        online = True
    except Exception as exc:
        devices = []
        system = {"error": str(exc)}

    canonical_present, canonical_missing = _model_state(models_root, CANONICAL_MODELS)
    loop_present, loop_missing = _model_state(models_root, LOOP_MODELS)
    pose_present, pose_missing = _model_state(models_root, POSE_MODELS)
    viseme_present, viseme_missing = _model_state(models_root, VISEME_ATLAS_MODELS)
    runtime_export_present, runtime_export_missing = _model_state(models_root, RUNTIME_EXPORT_MODELS)
    ffv1_available = _ffv1_encoder_available()

    if online:
        canonical_nodes, missing_canonical_nodes = _node_state(comfy_url, CANONICAL_NODES)
        loop_nodes, missing_loop_nodes = _node_state(comfy_url, LOOP_NODES)
        pose_nodes, missing_pose_nodes = _node_state(comfy_url, POSE_NODES)
        repair_nodes, missing_repair_nodes = _node_state(comfy_url, REPAIR_NODES)
        viseme_nodes, missing_viseme_nodes = _node_state(comfy_url, VISEME_ATLAS_NODES)
        runtime_export_nodes, missing_runtime_export_nodes = _node_state(comfy_url, RUNTIME_EXPORT_NODES)
    else:
        canonical_nodes = loop_nodes = pose_nodes = repair_nodes = viseme_nodes = runtime_export_nodes = []
        missing_canonical_nodes = sorted(CANONICAL_NODES)
        missing_loop_nodes = sorted(LOOP_NODES)
        missing_pose_nodes = sorted(POSE_NODES)
        missing_repair_nodes = sorted(REPAIR_NODES)
        missing_viseme_nodes = sorted(VISEME_ATLAS_NODES)
        missing_runtime_export_nodes = sorted(RUNTIME_EXPORT_NODES)

    w6_exists = (project_root / "workflows" / "w6-character-canonicalize" / "workflow_api.json").is_file()
    w7_exists = (project_root / "workflows" / "w7-seamless-loop" / "workflow_api.json").is_file()
    w8_exists = (project_root / "workflows" / "w8-vace-pose-control" / "workflow_api.json").is_file()
    w10_exists = (project_root / "workflows" / "w10-temporal-repair" / "workflow_api.json").is_file()
    w9_root = project_root / "workflows" / "w9-viseme-atlas"
    w9_exists = (w9_root / "workflow_api.json").is_file()
    w9_requirements_exist = (w9_root / "requirements.json").is_file()
    w11_root = project_root / "workflows" / "w11-face-layer"
    w11_exists = (w11_root / "workflow_api.json").is_file()
    w11_requirements_exist = (w11_root / "requirements.json").is_file()
    w12_root = project_root / "workflows" / "w12-runtime-export"
    w12_exists = (w12_root / "workflow_api.json").is_file()
    w12_requirements_exist = (w12_root / "requirements.json").is_file()
    canonical_ready = online and not canonical_missing and not missing_canonical_nodes and w6_exists
    loop_ready = online and not loop_missing and not missing_loop_nodes and w7_exists
    pose_stack_installed = online and not pose_missing and not missing_pose_nodes
    pose_ready = pose_stack_installed and w8_exists
    temporal_repair_ready = online and not pose_missing and not missing_repair_nodes and w10_exists
    viseme_atlas_ready = (
        online
        and not viseme_missing
        and not missing_viseme_nodes
        and w9_exists
        and w9_requirements_exist
    )
    face_layer_ready = viseme_atlas_ready and w11_exists and w11_requirements_exist
    runtime_export_ready = (
        online
        and not runtime_export_missing
        and not missing_runtime_export_nodes
        and w12_exists
        and w12_requirements_exist
        and ffv1_available
    )
    viseme_timing_contract_ready = (
        (project_root / "studio" / "visemes.py").is_file()
        and (project_root / "tools" / "rhubarb_adapter.py").is_file()
    )
    rhubarb_path = (
        project_root
        / "tools"
        / "bin"
        / "rhubarb"
        / "Rhubarb-Lip-Sync-1.14.0-Windows"
        / "rhubarb.exe"
    )
    rhubarb_ready = rhubarb_path.is_file()
    lipsync_stack_ready = viseme_atlas_ready and viseme_timing_contract_ready and rhubarb_ready
    continuity_qc_ready = (
        importlib.util.find_spec("PIL") is not None
        and importlib.util.find_spec("cv2") is not None
        and (project_root / "studio" / "qc.py").is_file()
    )

    return {
        "checked_at": int(time.time()),
        "comfy": {
            "online": online,
            "url": comfy_url,
            "version": system.get("comfyui_version"),
            "python_version": system.get("python_version"),
        },
        "hardware": {
            "ram_total": system.get("ram_total"),
            "devices": devices,
            "recommended_profile": "local_12gb",
        },
        "features": {
            "canonicalize": canonical_ready,
            "prompt_loop": loop_ready,
            "pose_control": pose_ready,
            "pose_control_stack_installed": pose_stack_installed,
            "face_layer": face_layer_ready,
            "viseme_atlas": viseme_atlas_ready,
            "viseme_atlas_stack": viseme_atlas_ready,
            "viseme_control": True,
            "continuity_qc": continuity_qc_ready,
            "temporal_repair": temporal_repair_ready,
            "rhubarb_timing": rhubarb_ready,
            "offline_lipsync": lipsync_stack_ready,
            "runtime_export": runtime_export_ready,
        },
        "motion_support": {
            "pose_control": sorted(POSE_GUIDE_MOTIONS) if pose_ready else [],
        },
        "stacks": {
            "canonicalize": {
                "ready": canonical_ready,
                "models_present": canonical_present,
                "models_missing": canonical_missing,
                "nodes_present": canonical_nodes,
                "nodes_missing": missing_canonical_nodes,
                "workflow_present": w6_exists,
            },
            "prompt_loop": {
                "ready": loop_ready,
                "models_present": loop_present,
                "models_missing": loop_missing,
                "nodes_present": loop_nodes,
                "nodes_missing": missing_loop_nodes,
                "workflow_present": w7_exists,
            },
            "pose_control": {
                "ready": pose_ready,
                "stack_installed": pose_stack_installed,
                "models_present": pose_present,
                "models_missing": pose_missing,
                "nodes_present": pose_nodes,
                "nodes_missing": missing_pose_nodes,
                "workflow_present": w8_exists,
                "implemented_guides": sorted(POSE_GUIDE_MOTIONS),
                "implementation": "deterministic OpenPose guide + regional VACE polish + exact zero-mask endpoints",
            },
            "temporal_repair": {
                "ready": temporal_repair_ready,
                "models_present": pose_present,
                "models_missing": pose_missing,
                "nodes_present": repair_nodes,
                "nodes_missing": missing_repair_nodes,
                "workflow_present": w10_exists,
                "implementation": "QC-planned local FFV1 window repair with feathered merge and mandatory re-QC",
            },
            "viseme_atlas": {
                "ready": viseme_atlas_ready,
                "scope": "local_generation_stack",
                "models_present": viseme_present,
                "models_missing": viseme_missing,
                "nodes_present": viseme_nodes,
                "nodes_missing": missing_viseme_nodes,
                "workflow_present": w9_exists,
                "requirements_present": w9_requirements_exist,
                "timing_contract_present": viseme_timing_contract_ready,
                "note": "ready means the W9 stack can be invoked; it does not imply that any project has a reviewed atlas.",
            },
            "face_layer": {
                "ready": face_layer_ready,
                "models_present": viseme_present,
                "models_missing": viseme_missing,
                "nodes_present": viseme_nodes,
                "nodes_missing": missing_viseme_nodes,
                "workflow_present": w11_exists,
                "requirements_present": w11_requirements_exist,
                "implementation": "Qwen expression tile + deterministic ROI envelope + exact anchor endpoints",
            },
            "runtime_export": {
                "ready": runtime_export_ready,
                "models_present": runtime_export_present,
                "models_missing": runtime_export_missing,
                "nodes_present": runtime_export_nodes,
                "nodes_missing": missing_runtime_export_nodes,
                "workflow_present": w12_exists,
                "requirements_present": w12_requirements_exist,
                "ffv1_encoder_available": ffv1_available,
                "implementation": "lossless QC master -> sequential BiRefNet toon alpha -> review-gated color RGBA sheet",
            },
            "lipsync": {
                "ready": lipsync_stack_ready,
                "primary_mode": "viseme_atlas",
                "atlas_stack_available": viseme_atlas_ready,
                "timing_contract_available": viseme_timing_contract_ready,
                "rhubarb_available": rhubarb_ready,
                "rhubarb_path": str(rhubarb_path) if rhubarb_ready else None,
                "missing": [] if lipsync_stack_ready else [
                    item
                    for item, present in (
                        ("W9 atlas generation stack", viseme_atlas_ready),
                        ("timing/runtime contract", viseme_timing_contract_ready),
                        ("Rhubarb 1.14.0 executable", rhubarb_ready),
                    )
                    if not present
                ],
                "note": "System stack readiness is separate from the per-project gates: accepted anchor ROI, reviewed atlas, uploaded audio and validated timeline.",
            },
        },
    }
