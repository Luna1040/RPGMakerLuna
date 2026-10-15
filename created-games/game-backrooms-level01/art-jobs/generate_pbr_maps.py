"""Derive subtle tileable normal and roughness maps for the Level 0 prototype textures."""
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1] / "assets" / "textures"
MATERIALS = {
    "wallpaper_yellowed": (0.22, 0.74),
    "carpet_office_worn": (0.48, 0.94),
    "ceiling_acoustic_tiles": (0.32, 0.91),
    "desk_walnut": (0.55, 0.48),
    "doorframe_oxidized_steel": (0.38, 0.62),
    "photopaper_ivory": (0.10, 0.82),
}

for stem, (normal_strength, base_roughness) in MATERIALS.items():
    image = Image.open(ROOT / f"{stem}.jpg").convert("RGB")
    rgb = np.asarray(image, dtype=np.float32) / 255.0
    gray = np.asarray(image.convert("L").filter(ImageFilter.GaussianBlur(1.1)), dtype=np.float32) / 255.0
    # Remove broad lighting gradients so the normal map describes surface detail only.
    broad = np.asarray(Image.fromarray((gray * 255).astype("uint8")).filter(ImageFilter.GaussianBlur(18)), dtype=np.float32) / 255.0
    height = (gray - broad)
    height /= max(float(np.std(height)), 1e-4)
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5 * normal_strength
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5 * normal_strength
    nx, ny = -dx, -dy
    inv_len = 1.0 / np.sqrt(nx * nx + ny * ny + 1.0)
    normal = np.stack(((nx * inv_len + 1) * 127.5, (ny * inv_len + 1) * 127.5, (inv_len + 1) * 127.5), axis=-1)
    Image.fromarray(np.uint8(np.clip(normal, 0, 255))).save(ROOT / f"{stem}_normal.png", optimize=True)
    local = np.abs(gray - broad)
    roughness = np.clip(base_roughness + local * 0.24, 0.08, 1.0)
    rough_rgb = np.repeat((roughness * 255).astype("uint8")[:, :, None], 3, axis=2)
    Image.fromarray(rough_rgb, "RGB").save(ROOT / f"{stem}_roughness.png", optimize=True)
