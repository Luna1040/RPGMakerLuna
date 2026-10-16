#!/usr/bin/env python3
"""Deterministic original pixel art for the combat vertical slice.

Run from anywhere with Pillow installed:
    python3 assets/combat/generate_combat_assets.py

All drawing is constructed from simple polygons, pixel clusters, and fixed
palettes. No user reference image, remote output, font, or prior game asset is
copied into these files. The heroine's teal hair and burgundy bartender vest
retain the identity established by the existing bar character mother image.
"""

from __future__ import annotations

import hashlib
import json
import random
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent
MAP_SIZE = (320, 180)
PORTRAIT_SIZE = (72, 88)
SPRITE_SIZE = (80, 80)
SPRITE_PIVOT = (40, 72)
SCALE = Image.Resampling.NEAREST

INK = "#070b16"
NAVY = "#0e1729"
MIDNIGHT = "#111d32"
STEEL = "#26374b"
TEAL = "#2ca9ac"
CYAN = "#58e5dc"
PALE = "#b5fff1"
PURPLE = "#653571"
MAGENTA = "#dc5bb9"
RED = "#e16275"
AMBER = "#f2ba6c"


def rect(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], color: str | tuple) -> None:
    draw.rectangle(box, fill=color)


def poly(draw: ImageDraw.ImageDraw, points: list[tuple[int, int]], color: str | tuple, outline: str | None = None) -> None:
    draw.polygon(points, fill=color)
    if outline:
        draw.line(points + [points[0]], fill=outline, width=1)


def line(draw: ImageDraw.ImageDraw, points: list[tuple[int, int]], color: str | tuple, width: int = 1) -> None:
    draw.line(points, fill=color, width=width, joint="curve")


def pixel_noise(draw: ImageDraw.ImageDraw, *, y_min: int, y_max: int, colors: tuple[str, ...], seed: int, count: int = 145) -> None:
    rng = random.Random(seed)
    for _ in range(count):
        x = rng.randrange(16, 304)
        y = rng.randrange(y_min, y_max)
        w = rng.choice((1, 1, 2, 3))
        rect(draw, (x, y, x + w, y), rng.choice(colors))


def panel_wall(draw: ImageDraw.ImageDraw, *, base: str, panel: str, seam: str, light: str, height: int = 42) -> None:
    rect(draw, (0, 0, 319, height), base)
    for x in range(0, 320, 32):
        rect(draw, (x + 1, 4, x + 30, height - 5), panel)
        line(draw, [(x, 3), (x, height - 4)], seam)
        rect(draw, (x + 5, 10, x + 18, 12), seam)
        rect(draw, (x + 5, 10, x + 11, 10), light)
    rect(draw, (0, height - 5, 319, height - 3), seam)
    rect(draw, (0, height - 2, 319, height - 1), light)


def tile_floor(
    draw: ImageDraw.ImageDraw,
    *,
    y0: int,
    colors: tuple[str, str, str],
    seam: str,
    seed: int,
    cracked: bool = False,
) -> None:
    rng = random.Random(seed)
    rect(draw, (0, y0, 319, 179), colors[0])
    for row, y in enumerate(range(y0, 181, 16)):
        for col, x in enumerate(range(0, 321, 16)):
            c = colors[(col * 3 + row * 5 + (col ^ row)) % len(colors)]
            rect(draw, (x + 1, y + 1, x + 15, min(179, y + 15)), c)
            line(draw, [(x, y), (x + 15, y)], seam)
            line(draw, [(x, y), (x, min(179, y + 15))], seam)
            if (col + row * 2) % 5 == 0:
                rect(draw, (x + 3, y + 3, x + 5, y + 3), seam)
            if cracked and rng.randrange(10) == 0:
                line(draw, [(x + 8, y + 5), (x + 5, y + 8), (x + 6, y + 12)], seam)


def stepped_light(draw: ImageDraw.ImageDraw, x0: int, y0: int, x1: int, y1: int, dark: str, mid: str, bright: str) -> None:
    rect(draw, (x0 - 2, y0 - 2, x1 + 2, y1 + 2), dark)
    rect(draw, (x0 - 1, y0 - 1, x1 + 1, y1 + 1), mid)
    rect(draw, (x0, y0, x1, y1), bright)


def draw_security_map() -> Image.Image:
    im = Image.new("RGB", MAP_SIZE, "#080d1b")
    d = ImageDraw.Draw(im)
    tile_floor(d, y0=42, colors=("#12243c", "#162842", "#192b46"), seam="#263853", seed=11, cracked=True)
    panel_wall(d, base="#080e20", panel="#172239", seam="#30415a", light="#b349c2", height=42)

    # Security-side architecture and a continuous, readable central combat lane.
    for x in (17, 78, 242, 302):
        rect(d, (x - 3, 43, x + 3, 65), "#0b1427")
        rect(d, (x - 2, 45, x + 1, 60), "#354660")
        rect(d, (x - 1, 46, x - 1, 54), CYAN)
        rect(d, (x - 3, 62, x + 3, 64), "#6f3b83")
    rect(d, (86, 43, 234, 53), "#0a1427")
    rect(d, (96, 49, 224, 57), "#28425a")
    rect(d, (105, 50, 215, 52), "#59d1dc")
    rect(d, (112, 55, 208, 59), "#0e2037")
    for x in (116, 143, 170, 197):
        rect(d, (x, 46, x + 14, 49), "#445a72")
        rect(d, (x + 3, 46, x + 8, 47), "#c45bd2")

    # Two clear edge doors: canteen (left, inactive) and medical corridor (right).
    rect(d, (0, 69, 29, 129), "#050a15")
    rect(d, (2, 72, 24, 124), "#1b2338")
    rect(d, (7, 76, 21, 120), "#0c1425")
    rect(d, (11, 79, 14, 117), "#704052")
    rect(d, (16, 79, 19, 117), "#704052")
    rect(d, (0, 68, 28, 71), "#573652")
    rect(d, (0, 125, 28, 128), "#573652")
    stepped_light(d, 3, 76, 4, 119, "#3d2536", "#af536c", "#f1a17b")
    rect(d, (22, 89, 27, 105), "#49334c")
    rect(d, (23, 92, 26, 101), AMBER)
    line(d, [(29, 80), (43, 86), (43, 111), (29, 117)], "#374760", 2)

    rect(d, (290, 69, 319, 129), "#050d1b")
    rect(d, (297, 73, 319, 125), "#153a48")
    rect(d, (302, 77, 319, 121), "#061a27")
    rect(d, (290, 68, 319, 71), "#316d76")
    rect(d, (290, 125, 319, 128), "#316d76")
    stepped_light(d, 294, 76, 295, 120, "#153e4a", "#318b97", PALE)
    rect(d, (289, 90, 294, 104), "#285563")
    rect(d, (290, 93, 293, 100), CYAN)
    line(d, [(290, 80), (277, 86), (277, 111), (290, 117)], "#3d6675", 2)

    # Floor lanes, scanner pads and small reflections. The middle stays free.
    for x in range(55, 266, 28):
        rect(d, (x, 77, x + 10, 78), "#2a5471")
        rect(d, (x + 2, 78, x + 7, 78), "#59bfd0")
        rect(d, (x, 137, x + 12, 138), "#324f6b")
    for x in (57, 236):
        rect(d, (x, 58, x + 27, 72), "#0d1b2e")
        rect(d, (x + 2, 60, x + 25, 69), "#263950")
        rect(d, (x + 4, 62, x + 23, 63), "#64437c")
        rect(d, (x + 4, 66, x + 15, 66), "#3b9ca9")
        rect(d, (x + 1, 72, x + 27, 74), "#091322")
    for x in (65, 244):
        rect(d, (x, 145, x + 12, 151), "#0d182a")
        rect(d, (x + 2, 146, x + 10, 147), "#6b496f")
        rect(d, (x + 4, 149, x + 8, 149), "#44b5c4")
    line(d, [(90, 102), (128, 102)], "#31546f")
    line(d, [(192, 102), (230, 102)], "#31546f")
    for x in (145, 160, 175):
        rect(d, (x - 1, 103, x + 1, 104), "#55728d")
    pixel_noise(d, y_min=58, y_max=170, colors=("#27435e", "#304560", "#325474"), seed=719, count=115)

    # A raised scanning gantry gives the first stage a practical purpose.
    # Its feet stop before the central combat lane.
    rect(d, (111, 53, 123, 80), "#060d1d")
    rect(d, (197, 53, 209, 80), "#060d1d")
    rect(d, (113, 55, 121, 77), "#34425e")
    rect(d, (199, 55, 207, 77), "#34425e")
    rect(d, (116, 59, 118, 73), "#8b5099")
    rect(d, (202, 59, 204, 73), "#8b5099")
    rect(d, (117, 61, 117, 70), "#e880d2")
    rect(d, (203, 61, 203, 70), "#e880d2")
    rect(d, (122, 54, 198, 60), "#0a1629")
    rect(d, (125, 55, 195, 57), "#4e607a")
    for sx in range(129, 193, 15):
        rect(d, (sx, 55, sx + 6, 56), "#a858b3")
    rect(d, (113, 79, 123, 81), "#182b42")
    rect(d, (197, 79, 209, 81), "#182b42")
    line(d, [(124, 82), (196, 82)], "#3b506d")
    for sx in (134, 153, 172, 191):
        rect(d, (sx, 83, sx + 7, 84), "#3e5f79")

    # Recessed wall monitoring desks and data screens; one remains on each
    # side of the gate so the two exits do not look interchangeable.
    for sx, screen in ((37, "#2b8294"), (240, "#6e468f")):
        rect(d, (sx - 2, 47, sx + 44, 73), "#07101e")
        rect(d, (sx, 48, sx + 42, 67), "#1a2d43")
        rect(d, (sx + 2, 50, sx + 40, 63), "#0a2032")
        rect(d, (sx + 4, 52, sx + 38, 53), screen)
        line(d, [(sx + 6, 58), (sx + 14, 58), (sx + 17, 55), (sx + 20, 61), (sx + 25, 57), (sx + 37, 57)], "#75dfdf")
        rect(d, (sx + 3, 65, sx + 40, 68), "#39516a")
        for key_x in range(sx + 7, sx + 38, 6):
            rect(d, (key_x, 66, key_x + 3, 66), "#9c628f")
        poly(d, [(sx, 69), (sx + 42, 69), (sx + 48, 75), (sx - 3, 75)], "#101c2e", INK)
        rect(d, (sx + 1, 73, sx + 42, 74), "#405067")

    # Painted wayfinding. Amber crossbars on the left say "closed route";
    # turquoise chevrons continue to the medical exit on the right.
    for sx in (46, 61, 76):
        poly(d, [(sx, 91), (sx + 6, 96), (sx, 101), (sx + 4, 101), (sx + 10, 96), (sx + 4, 91)], "#8c665e")
        rect(d, (sx + 1, 109, sx + 7, 110), "#56445b")
    for sx in (228, 243, 258):
        poly(d, [(sx, 92), (sx + 6, 97), (sx, 102), (sx + 4, 102), (sx + 10, 97), (sx + 4, 92)], "#48a7b7")
        rect(d, (sx + 1, 109, sx + 8, 110), "#306275")
    line(d, [(5, 83), (20, 107)], "#e6a16e", 2)
    line(d, [(6, 106), (20, 82)], "#e6a16e", 2)
    rect(d, (7, 92, 17, 95), "#493348")
    rect(d, (31, 77, 48, 80), "#4e354d")
    rect(d, (33, 78, 45, 78), AMBER)
    rect(d, (273, 77, 289, 80), "#245966")
    rect(d, (275, 78, 287, 78), CYAN)
    # Shallow inspection plates at the lower margins add depth without
    # placing a collision-looking prop inside the fight.
    for sx in (34, 264):
        rect(d, (sx - 3, 144, sx + 23, 154), "#0b1a2d")
        rect(d, (sx, 145, sx + 20, 151), "#2d4058")
        rect(d, (sx + 3, 146, sx + 17, 146), "#674e78")
        for bolt in (sx + 2, sx + 18):
            rect(d, (bolt, 150, bolt + 1, 150), "#aec7c4")
    return im


def medical_bed(draw: ImageDraw.ImageDraw, x: int, y: int, *, occupied: bool = False) -> None:
    rect(draw, (x - 2, y + 3, x + 50, y + 25), "#071b27")
    rect(draw, (x, y, x + 48, y + 24), "#a7d9d7")
    rect(draw, (x + 2, y + 2, x + 46, y + 20), "#537f88")
    rect(draw, (x + 4, y + 4, x + 44, y + 18), "#e0f3e7")
    rect(draw, (x + 5, y + 5, x + 15, y + 16), "#8bc6c4")
    rect(draw, (x + 18, y + 8, x + 41, y + 9), "#a6ded5")
    rect(draw, (x + 18, y + 12, x + 37, y + 13), "#91ccc4")
    if occupied:
        rect(draw, (x + 19, y + 5, x + 30, y + 15), "#214453")
        rect(draw, (x + 20, y + 5, x + 27, y + 7), "#e9b6a8")
    for bx in (x + 3, x + 41):
        rect(draw, (bx, y + 22, bx + 5, y + 26), "#2e7b82")


def draw_medical_map() -> Image.Image:
    im = Image.new("RGB", MAP_SIZE, "#09151e")
    d = ImageDraw.Draw(im)
    tile_floor(d, y0=42, colors=("#17343e", "#1d3b44", "#21434b"), seam="#2d5360", seed=23)
    panel_wall(d, base="#10242e", panel="#2a4650", seam="#57737c", light="#69dccd", height=42)
    rect(d, (0, 41, 319, 45), "#b1dcd4")
    rect(d, (0, 44, 319, 46), "#3e9d9b")

    # Medical monitors and wall pods establish the room's identity.
    for x in (19, 76, 228, 282):
        rect(d, (x, 28, x + 19, 48), "#0b2531")
        rect(d, (x + 2, 30, x + 17, 43), "#1c5661")
        line(d, [(x + 3, 38), (x + 7, 38), (x + 9, 33), (x + 11, 41), (x + 14, 36), (x + 17, 36)], "#90f2d8")
        rect(d, (x + 6, 45, x + 12, 46), "#64b2af")
    medical_bed(d, 35, 55)
    medical_bed(d, 35, 121, occupied=False)
    rect(d, (215, 53, 289, 82), "#092b37")
    rect(d, (218, 55, 286, 79), "#477c84")
    rect(d, (224, 58, 280, 76), "#96c8c4")
    rect(d, (230, 61, 274, 74), "#255362")
    d.arc((238, 58, 266, 78), 20, 160, fill="#b8f9df", width=2)
    d.arc((238, 58, 266, 78), 200, 340, fill="#5ad3c5", width=2)
    rect(d, (220, 81, 284, 84), "#08202d")

    # Sterile cross and subtle diagnosis-ring marks leave a playable center.
    d.ellipse((135, 73, 185, 123), outline="#3d8188", width=2)
    d.arc((138, 76, 182, 120), 205, 330, fill="#73cabf", width=2)
    rect(d, (155, 88, 165, 108), "#356873")
    rect(d, (150, 93, 170, 103), "#356873")
    rect(d, (157, 90, 163, 106), "#81dcd0")
    rect(d, (152, 95, 168, 101), "#81dcd0")
    for x in (118, 202):
        rect(d, (x, 96, x + 13, 99), "#276e79")
        rect(d, (x + 3, 97, x + 9, 97), "#76d6c8")

    # Supply lockers and specimen stations along the edge; no center occlusion.
    for x in (220, 250, 280):
        rect(d, (x, 127, x + 23, 151), "#0e2935")
        rect(d, (x + 2, 129, x + 21, 146), "#47727a")
        rect(d, (x + 5, 133, x + 18, 134), "#9bd4cb")
        rect(d, (x + 6, 138, x + 16, 138), "#275768")
        rect(d, (x + 2, 148, x + 21, 150), "#1a515d")
    for x in (9, 304):
        rect(d, (x, 79, x + 6, 118), "#092630")
        rect(d, (x + 2, 82, x + 3, 115), "#6bd2c5")
    for x in range(16, 305, 64):
        rect(d, (x, 163, x + 21, 164), "#70aaa6")
        rect(d, (x + 3, 165, x + 15, 165), "#356f78")
    pixel_noise(d, y_min=47, y_max=177, colors=("#2f5860", "#386069", "#336a6a"), seed=211, count=75)

    # Three-dimensional overhead instrument rail with hanging lights.
    rect(d, (101, 46, 205, 50), "#0a2734")
    rect(d, (104, 46, 202, 47), "#b5e6d9")
    rect(d, (111, 49, 115, 71), "#245b67")
    rect(d, (192, 49, 196, 71), "#245b67")
    for sx in (123, 146, 169):
        rect(d, (sx, 49, sx + 12, 55), "#407982")
        rect(d, (sx + 2, 51, sx + 10, 52), "#c6fff0")
        rect(d, (sx + 3, 54, sx + 9, 54), "#68babb")
    # Operating displays beside each bed; screen art uses pixel ECG marks.
    for sx, sy in ((88, 56), (88, 124)):
        rect(d, (sx, sy, sx + 17, sy + 17), "#0b2733")
        rect(d, (sx + 2, sy + 2, sx + 15, sy + 11), "#184652")
        line(d, [(sx + 3, sy + 7), (sx + 6, sy + 7), (sx + 8, sy + 4), (sx + 10, sy + 9), (sx + 12, sy + 6), (sx + 15, sy + 6)], "#a8fae1")
        rect(d, (sx + 5, sy + 13, sx + 12, sy + 14), "#5b9e9e")
    # IV stands and pale tubing sit on the margins, clear of the combat circle.
    for sx, sy in ((111, 74), (203, 126)):
        rect(d, (sx, sy - 15, sx + 1, sy + 14), "#7bb7b3")
        rect(d, (sx - 5, sy + 13, sx + 6, sy + 14), "#29525e")
        rect(d, (sx - 3, sy - 17, sx + 4, sy - 15), "#c7ece1")
        rect(d, (sx + 1, sy - 14, sx + 5, sy - 7), "#5aafb2")
        line(d, [(sx + 5, sy - 7), (sx + 7, sy - 2), (sx + 6, sy + 3)], "#80d4c5")
    # Glazed medicine drawers, vials, floor plumbing and sterile light bands.
    for sx in (221, 251, 281):
        rect(d, (sx + 3, 139, sx + 19, 141), "#244a57")
        for vx, vc in ((sx + 5, "#76e5d0"), (sx + 10, "#eaba7e"), (sx + 15, "#ab8cda")):
            rect(d, (vx, 130, vx + 2, 137), vc)
            rect(d, (vx, 129, vx + 2, 129), "#d9eee5")
    line(d, [(116, 75), (116, 83), (128, 83), (128, 91)], "#65a9a9", 2)
    line(d, [(199, 74), (199, 86), (213, 86), (213, 99)], "#63a4a6", 2)
    for sx in (120, 200):
        rect(d, (sx - 5, 119, sx + 5, 121), "#376b73")
        rect(d, (sx - 2, 120, sx + 2, 120), "#a7e8d7")
    for sy in (84, 121):
        rect(d, (23, sy, 26, sy + 13), "#3b8184")
        rect(d, (24, sy + 2, 24, sy + 10), "#d4fff0")
        rect(d, (291, sy, 294, sy + 13), "#3b8184")
        rect(d, (293, sy + 2, 293, sy + 10), "#d4fff0")
    return im


def arc_circuit(draw: ImageDraw.ImageDraw, pts: list[tuple[int, int]], *, outer: str, inner: str) -> None:
    line(draw, pts, outer, 4)
    line(draw, pts, inner, 1)
    for x, y in (pts[0], pts[-1]):
        rect(draw, (x - 2, y - 2, x + 2, y + 2), outer)
        rect(draw, (x - 1, y - 1, x + 1, y + 1), inner)


def draw_root_map() -> Image.Image:
    im = Image.new("RGB", MAP_SIZE, "#0b0a1c")
    d = ImageDraw.Draw(im)
    tile_floor(d, y0=42, colors=("#19182e", "#201a36", "#211c3c"), seam="#3b2b53", seed=37, cracked=True)
    panel_wall(d, base="#0c0b1e", panel="#23182f", seam="#3e2755", light="#cf58ae", height=42)
    for x in (12, 54, 266, 308):
        rect(d, (x - 5, 36, x + 5, 75), "#0a0b1b")
        rect(d, (x - 2, 38, x + 2, 68), "#3f2b56")
        rect(d, (x - 1, 44, x + 1, 62), "#c74eaa")
        rect(d, (x - 7, 70, x + 7, 74), "#251a3c")

    # Neural platform: a distinct ring/core composition, while the floor
    # inside the ring remains usable for character positions.
    d.ellipse((98, 54, 222, 169), fill="#090d20", outline="#221a3b", width=2)
    d.ellipse((102, 47, 218, 163), fill="#161a32", outline="#533a74", width=3)
    d.ellipse((111, 56, 209, 154), outline="#b74e9f", width=2)
    d.arc((115, 60, 205, 150), 18, 78, fill="#e67ccc", width=3)
    d.arc((115, 60, 205, 150), 105, 174, fill="#7a48ad", width=3)
    d.arc((115, 60, 205, 150), 200, 255, fill="#e67ccc", width=3)
    d.arc((115, 60, 205, 150), 289, 349, fill="#6fc9cf", width=3)
    d.ellipse((133, 78, 187, 132), fill="#0b1025", outline="#4b5686", width=3)
    d.ellipse((145, 90, 175, 120), fill="#3e244f", outline="#df5ab2", width=2)
    d.ellipse((152, 97, 168, 113), fill="#9a4396")
    rect(d, (156, 101, 163, 108), "#f5b6e2")
    for x, y in ((160, 56), (204, 104), (160, 151), (116, 104)):
        rect(d, (x - 3, y - 3, x + 3, y + 3), "#423967")
        rect(d, (x - 1, y - 1, x + 1, y + 1), "#e477c8")

    # Radial cables and static electricity are background; combat telegraphs
    # and hit FX are intentionally left to the game.
    arc_circuit(d, [(12, 86), (57, 86), (77, 98), (101, 98)], outer="#49315e", inner="#9e4ba2")
    arc_circuit(d, [(319, 87), (272, 87), (246, 101), (218, 101)], outer="#49315e", inner="#bd55b0")
    arc_circuit(d, [(31, 168), (79, 168), (106, 143)], outer="#382e56", inner="#6b7fb6")
    arc_circuit(d, [(287, 168), (239, 168), (214, 143)], outer="#382e56", inner="#815bb7")
    for chain in (
        [(30, 51), (42, 61), (36, 65), (51, 78), (46, 84)],
        [(251, 51), (265, 61), (259, 67), (274, 77), (268, 82)],
        [(20, 141), (35, 132), (43, 138), (51, 127)],
        [(302, 140), (290, 130), (282, 136), (269, 126)],
    ):
        line(d, chain, "#682e7d", 3)
        line(d, chain, "#e769bf", 1)
    for x in (18, 62, 252, 295):
        rect(d, (x, 115, x + 17, 128), "#0e0d24")
        rect(d, (x + 2, 117, x + 15, 121), "#714072")
        rect(d, (x + 5, 118, x + 11, 119), "#e272c2")
        rect(d, (x + 4, 124, x + 13, 125), "#3e5d7b")
    pixel_noise(d, y_min=47, y_max=179, colors=("#3a3057", "#44385c", "#4a3260"), seed=307, count=85)

    # Thick braces and machined plating sell the neural core as a built
    # object, not a painted circular reticle.
    for sx, sy, w, h in ((151, 48, 18, 10), (204, 98, 16, 13), (151, 152, 18, 9), (100, 98, 16, 13)):
        rect(d, (sx - 2, sy + 3, sx + w + 2, sy + h + 3), "#0b0b21")
        rect(d, (sx, sy, sx + w, sy + h), "#51416b")
        rect(d, (sx + 2, sy + 1, sx + w - 2, sy + 2), "#9b6da7")
        rect(d, (sx + 4, sy + h - 2, sx + w - 4, sy + h - 2), "#30294e")
        for bx in (sx + 2, sx + w - 2):
            rect(d, (bx, sy + 4, bx, sy + 5), "#d492cf")
    d.arc((123, 69, 197, 143), 195, 328, fill="#e57cc9", width=2)
    d.arc((123, 69, 197, 143), 15, 145, fill="#675ca2", width=2)
    # Segmented control desks along all four corners.
    for sx, sy, flip in ((20, 54, 1), (251, 54, -1), (21, 128, 1), (251, 128, -1)):
        rect(d, (sx - 2, sy + 4, sx + 49, sy + 24), "#080b1d")
        poly(d, [(sx, sy), (sx + 42, sy), (sx + 48, sy + 9), (sx + 5, sy + 9)], "#27324a", INK)
        rect(d, (sx + 5, sy + 2, sx + 38, sy + 5), "#502d64")
        for bx in (sx + 8, sx + 17, sx + 26):
            rect(d, (bx, sy + 3, bx + 5, sy + 4), "#bf57a8" if (bx + flip) % 2 else "#6caac4")
        rect(d, (sx + 5, sy + 12, sx + 43, sy + 20), "#1b1a34")
        rect(d, (sx + 9, sy + 13, sx + 39, sy + 14), "#434063")
        for bx in (sx + 11, sx + 20, sx + 29):
            rect(d, (bx, sy + 17, bx + 4, sy + 18), "#e577bf")
    # Branching dendrite traces deliberately stay thin beneath telegraphs.
    for trace in (
        [(72, 91), (83, 91), (88, 84), (99, 84)],
        [(69, 103), (82, 103), (90, 114), (101, 114)],
        [(247, 91), (236, 91), (231, 84), (219, 84)],
        [(250, 103), (237, 103), (230, 115), (219, 115)],
        [(112, 146), (121, 136), (128, 137)],
        [(208, 146), (199, 136), (192, 137)],
    ):
        line(d, trace, "#6e3b86", 2)
        line(d, trace, "#c157aa")
        x, y = trace[-1]
        rect(d, (x - 1, y - 1, x + 1, y + 1), "#e58bcf")
    return im


def portrait_canvas() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    im = Image.new("RGBA", PORTRAIT_SIZE, (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def draw_heroine_portrait() -> Image.Image:
    im, d = portrait_canvas()
    # Long teal hair, burgundy bartender waistcoat and readable electric baton
    # retain the already established protagonist identity.
    poly(d, [(17, 11), (26, 4), (44, 3), (53, 10), (56, 28), (55, 60), (47, 67), (40, 57), (31, 62), (22, 66), (13, 56), (14, 30)], "#092b38", INK)
    poly(d, [(19, 13), (28, 6), (43, 6), (51, 14), (52, 48), (46, 59), (43, 44), (24, 44), (20, 58), (16, 50)], "#087476")
    poly(d, [(18, 22), (22, 11), (31, 6), (27, 23), (22, 43), (18, 54)], "#39c4b5")
    poly(d, [(45, 9), (51, 15), (52, 48), (47, 57), (45, 33)], "#1b9f9b")
    poly(d, [(18, 46), (28, 41), (45, 41), (56, 46), (65, 58), (67, 87), (7, 87), (9, 59)], "#080c19", INK)
    poly(d, [(13, 54), (24, 46), (34, 48), (46, 45), (58, 53), (62, 87), (10, 87)], "#1d2938")
    poly(d, [(22, 46), (30, 44), (35, 54), (40, 44), (49, 46), (55, 58), (51, 87), (19, 87), (17, 57)], "#5b253f", "#260f28")
    poly(d, [(24, 47), (31, 45), (36, 56), (29, 83), (21, 75)], "#833452")
    poly(d, [(42, 45), (49, 47), (54, 75), (44, 84), (37, 56)], "#71304b")
    rect(d, (32, 51, 39, 86), "#111a29")
    rect(d, (34, 53, 36, 80), "#344358")
    for y in (61, 70, 79):
        rect(d, (33, y, 35, y + 1), AMBER)
    # Face and fringe.
    poly(d, [(25, 20), (31, 15), (43, 16), (49, 22), (47, 39), (41, 46), (31, 45), (24, 36)], "#241c26")
    poly(d, [(27, 21), (33, 17), (43, 19), (47, 25), (45, 38), (40, 44), (31, 43), (26, 35)], "#e8aa91")
    rect(d, (29, 32, 32, 33), "#101928")
    rect(d, (40, 31, 43, 32), "#101928")
    rect(d, (30, 32, 31, 32), "#72d9dc")
    rect(d, (41, 31, 42, 31), "#72d9dc")
    rect(d, (34, 40, 39, 40), "#a66462")
    poly(d, [(23, 25), (25, 14), (33, 7), (43, 8), (48, 16), (45, 24), (40, 23), (38, 17), (31, 24), (26, 26)], "#08566b")
    line(d, [(24, 23), (30, 11), (38, 8)], "#3be1d2", 2)
    rect(d, (46, 24, 49, 43), "#0b6675")
    rect(d, (20, 27, 22, 47), "#0b7181")
    # Arms, hands and telescopic stun baton.
    poly(d, [(9, 55), (16, 50), (21, 57), (17, 72), (15, 84), (9, 84), (7, 69)], "#182433", INK)
    poly(d, [(53, 51), (60, 56), (65, 69), (64, 79), (58, 82), (55, 71)], "#182433", INK)
    rect(d, (11, 76, 15, 85), "#daa28b")
    rect(d, (59, 75, 64, 83), "#dda68d")
    line(d, [(62, 77), (66, 51), (68, 31)], "#0b1324", 6)
    line(d, [(62, 76), (66, 50), (68, 31)], "#546479", 3)
    line(d, [(67, 49), (68, 30)], CYAN, 2)
    rect(d, (65, 25, 70, 31), "#23576a")
    rect(d, (66, 25, 69, 27), PALE)
    rect(d, (66, 56, 68, 57), CYAN)
    rect(d, (27, 27, 31, 28), "#895854")
    rect(d, (40, 26, 44, 27), "#895854")
    rect(d, (35, 37, 37, 38), "#f4c4a7")
    rect(d, (22, 36, 23, 50), "#41c9bd")
    rect(d, (48, 36, 49, 49), "#0a555f")
    rect(d, (23, 51, 26, 53), "#ac5670")
    rect(d, (47, 50, 50, 52), "#ac5670")
    poly(d, [(26, 46), (31, 45), (35, 53), (30, 56)], "#1a2331")
    poly(d, [(39, 53), (43, 45), (48, 47), (44, 56)], "#1a2331")
    rect(d, (46, 58, 51, 63), "#e0af5e")
    rect(d, (47, 59, 50, 61), "#6f293f")
    rect(d, (50, 66, 51, 73), "#ad5366")
    rect(d, (15, 59, 16, 70), "#405568")
    return im


def draw_guard_portrait() -> Image.Image:
    im, d = portrait_canvas()
    poly(d, [(14, 38), (26, 34), (48, 34), (61, 41), (68, 86), (5, 86)], "#080e1d", INK)
    poly(d, [(9, 44), (18, 40), (25, 49), (22, 77), (13, 84), (5, 76)], "#273d4b", INK)
    poly(d, [(54, 42), (63, 43), (68, 77), (61, 85), (51, 75), (47, 48)], "#2d4654", INK)
    poly(d, [(19, 42), (53, 42), (56, 80), (36, 87), (16, 79)], "#344b58", INK)
    poly(d, [(23, 46), (50, 46), (49, 73), (36, 80), (22, 73)], "#172838")
    rect(d, (31, 48, 41, 61), "#2b5967")
    rect(d, (34, 50, 38, 57), RED)
    rect(d, (28, 65, 44, 67), "#526779")
    for x in (25, 46):
        rect(d, (x, 70, x + 3, 73), "#8197a4")
    poly(d, [(18, 15), (27, 7), (45, 7), (55, 16), (54, 35), (48, 42), (24, 42), (18, 34)], "#080c17", INK)
    poly(d, [(21, 17), (28, 11), (45, 11), (51, 17), (51, 31), (45, 36), (26, 36), (21, 31)], "#405b68")
    rect(d, (24, 23, 48, 28), "#0b1422")
    rect(d, (26, 24, 46, 26), "#ec687c")
    rect(d, (28, 25, 37, 25), "#ffd99f")
    rect(d, (26, 31, 46, 34), "#172937")
    rect(d, (33, 36, 39, 40), "#697d82")
    rect(d, (21, 13, 24, 17), "#8ba6aa")
    rect(d, (48, 13, 51, 18), "#8ba6aa")
    # Shared simple shock staff silhouette, distinct from captain's firearm.
    line(d, [(61, 78), (65, 34)], "#0a1020", 6)
    line(d, [(61, 78), (65, 34)], "#586e7b", 3)
    rect(d, (62, 30, 67, 35), "#3b9ca5")
    rect(d, (64, 29, 66, 31), PALE)
    rect(d, (26, 30, 29, 32), "#586d78")
    rect(d, (43, 30, 46, 32), "#586d78")
    rect(d, (30, 36, 42, 37), "#a3adb1")
    rect(d, (28, 54, 31, 56), "#60717d")
    rect(d, (42, 54, 45, 56), "#60717d")
    for sy in (59, 72):
        rect(d, (13, sy, 19, sy + 1), "#5d7782")
        rect(d, (54, sy, 60, sy + 1), "#5d7782")
    rect(d, (16, 45, 19, 47), "#b95e72")
    rect(d, (53, 45, 56, 47), "#b95e72")
    rect(d, (33, 76, 40, 77), "#627989")
    return im


def draw_captain_portrait(weapon: str = "gun") -> Image.Image:
    im, d = portrait_canvas()
    poly(d, [(9, 37), (22, 33), (49, 33), (64, 40), (69, 87), (3, 87)], "#070b16", INK)
    poly(d, [(7, 43), (19, 38), (26, 48), (22, 75), (8, 83)], "#314351", INK)
    poly(d, [(49, 40), (62, 42), (68, 76), (61, 83), (49, 70)], "#314755", INK)
    poly(d, [(18, 39), (52, 39), (56, 83), (35, 87), (15, 82)], "#223548")
    poly(d, [(24, 45), (46, 45), (48, 74), (36, 80), (22, 74)], "#526371", INK)
    rect(d, (28, 51, 43, 55), "#162636")
    rect(d, (30, 51, 34, 54), AMBER)
    rect(d, (36, 51, 40, 54), AMBER)
    rect(d, (25, 66, 47, 68), "#8a9aa0")
    rect(d, (20, 43, 29, 47), "#e1ac62")
    rect(d, (44, 43, 54, 47), "#e1ac62")
    poly(d, [(20, 14), (27, 7), (44, 7), (52, 15), (52, 32), (46, 40), (25, 40), (20, 32)], "#0c1421", INK)
    poly(d, [(23, 17), (29, 11), (44, 11), (49, 17), (48, 30), (43, 36), (27, 36), (23, 31)], "#a99c91")
    rect(d, (24, 22, 48, 26), "#121e2a")
    rect(d, (26, 23, 45, 24), "#f27b61")
    rect(d, (29, 30, 43, 34), "#705f5e")
    poly(d, [(18, 16), (25, 5), (46, 5), (54, 15), (52, 21), (20, 21)], "#253344", INK)
    rect(d, (25, 9, 46, 12), "#526a7a")
    rect(d, (31, 8, 39, 10), AMBER)
    rect(d, (17, 21, 21, 33), "#4d5d6a")
    rect(d, (50, 21, 54, 33), "#4d5d6a")
    if weapon == "baton":
        # The first-stage enemy still has the same face and rank markings.
        # His pistol remains in a closed waist holster while he uses melee.
        poly(d, [(11, 69), (23, 66), (25, 76), (22, 85), (11, 84)], "#0d1725", INK)
        rect(d, (14, 69, 21, 72), "#7d8994")
        rect(d, (16, 72, 19, 78), "#435464")
        rect(d, (17, 80, 21, 81), "#b2875e")
        line(d, [(62, 78), (65, 51), (67, 29)], "#0b1322", 6)
        line(d, [(62, 77), (65, 50), (67, 29)], "#748996", 3)
        line(d, [(66, 47), (67, 30)], "#6fdcdb", 2)
        rect(d, (64, 25, 70, 31), "#22576b")
        rect(d, (66, 25, 69, 27), PALE)
    else:
        # Compact pistol in right hand after possession.
        poly(d, [(55, 56), (64, 52), (70, 53), (70, 61), (63, 62), (62, 70), (56, 70), (57, 61)], "#0b111e", INK)
        rect(d, (59, 54, 69, 57), "#798997")
        rect(d, (64, 54, 70, 55), CYAN)
        rect(d, (58, 62, 61, 67), "#394756")
    rect(d, (28, 30, 31, 31), "#d7ad91")
    rect(d, (40, 30, 43, 31), "#d7ad91")
    rect(d, (32, 36, 42, 37), "#3d4049")
    rect(d, (27, 48, 30, 51), "#e9be71")
    rect(d, (43, 48, 46, 51), "#e9be71")
    poly(d, [(35, 59), (38, 62), (35, 65), (32, 62)], "#e9bd73")
    rect(d, (35, 60, 35, 63), "#fff4c2")
    rect(d, (17, 57, 22, 58), "#a34f63")
    rect(d, (49, 57, 54, 58), "#a34f63")
    for sy in (71, 77):
        rect(d, (26, sy, 47, sy + 1), "#697986")
    return im


def draw_medic_portrait() -> Image.Image:
    im, d = portrait_canvas()
    poly(d, [(15, 40), (25, 35), (48, 35), (59, 43), (65, 87), (6, 87)], "#102633", INK)
    poly(d, [(10, 46), (24, 39), (34, 47), (29, 87), (4, 87)], "#c3e7df", INK)
    poly(d, [(48, 39), (62, 46), (68, 87), (40, 87), (37, 47)], "#c9e8e0", INK)
    poly(d, [(22, 43), (35, 51), (49, 43), (50, 87), (21, 87)], "#e9f4e8")
    poly(d, [(25, 46), (35, 56), (31, 85), (18, 85)], "#72b5b5")
    poly(d, [(47, 46), (36, 56), (41, 85), (55, 85)], "#8ccac5")
    rect(d, (31, 55, 40, 87), "#193a4b")
    rect(d, (34, 58, 36, 81), "#4e9da3")
    rect(d, (45, 62, 54, 71), "#2d8994")
    rect(d, (48, 63, 50, 70), "#d3fff2")
    rect(d, (46, 66, 53, 68), "#d3fff2")
    poly(d, [(19, 17), (27, 9), (44, 9), (52, 18), (49, 35), (44, 43), (27, 42), (19, 34)], "#0b2634", INK)
    poly(d, [(23, 20), (29, 15), (43, 15), (48, 21), (46, 34), (41, 39), (29, 39), (23, 33)], "#eac3ad")
    rect(d, (24, 29, 47, 35), "#e3f6eb")
    rect(d, (28, 31, 44, 32), "#93cec8")
    rect(d, (27, 24, 32, 25), "#163e4a")
    rect(d, (40, 24, 45, 25), "#163e4a")
    poly(d, [(18, 17), (25, 8), (39, 5), (51, 12), (52, 20), (44, 18), (37, 12), (25, 20), (20, 28)], "#92ded2", INK)
    line(d, [(22, 14), (31, 9), (39, 8)], "#e0fff1", 2)
    rect(d, (22, 21, 25, 35), "#59abae")
    # Hand-held injector and gloves.
    rect(d, (8, 72, 15, 81), "#66b1ae")
    rect(d, (57, 73, 64, 82), "#66b1ae")
    rect(d, (57, 59, 66, 68), "#17495d")
    rect(d, (60, 55, 63, 61), "#85e5d6")
    rect(d, (66, 61, 68, 66), "#c7fff0")
    rect(d, (26, 21, 46, 22), "#83bbbd")
    rect(d, (29, 21, 38, 21), "#d9ffef")
    rect(d, (30, 37, 42, 38), "#afdee1")
    rect(d, (17, 52, 20, 70), "#effcf2")
    rect(d, (52, 52, 55, 70), "#effcf2")
    rect(d, (24, 72, 27, 77), "#366e7b")
    rect(d, (25, 73, 26, 76), "#b3fff0")
    for sx, vc in ((44, "#72e1cd"), (48, "#e7bb75"), (52, "#bc8de1")):
        rect(d, (sx, 77, sx + 2, 83), vc)
        rect(d, (sx, 76, sx + 2, 76), "#f3fff6")
    rect(d, (59, 55, 63, 56), "#cfffea")
    return im


def draw_corrector_portrait() -> Image.Image:
    im, d = portrait_canvas()
    # Segmented halo is part of the character silhouette, not a gameplay hit FX.
    d.arc((7, 0, 65, 59), 185, 263, fill="#a5499b", width=3)
    d.arc((7, 0, 65, 59), 282, 351, fill="#d35aad", width=3)
    d.arc((13, 7, 59, 53), 12, 75, fill="#673b8c", width=2)
    for x, y in ((13, 20), (57, 11), (61, 39)):
        rect(d, (x - 2, y - 2, x + 2, y + 2), "#ae4d9f")
        rect(d, (x, y, x, y), "#f1b3de")
    poly(d, [(16, 11), (29, 3), (43, 3), (56, 15), (53, 39), (45, 46), (27, 46), (18, 37)], "#08091b", INK)
    poly(d, [(21, 15), (30, 8), (42, 8), (51, 18), (49, 35), (43, 41), (29, 41), (22, 34)], "#3d2858")
    poly(d, [(26, 19), (32, 14), (43, 16), (47, 24), (43, 35), (34, 38), (27, 32)], "#b2b7c5", INK)
    poly(d, [(28, 19), (35, 16), (44, 20), (40, 23), (31, 23)], "#eff3ed")
    rect(d, (29, 26, 44, 29), "#190d2b")
    rect(d, (31, 26, 43, 27), "#e667bd")
    rect(d, (35, 34, 41, 35), "#5c466f")
    poly(d, [(8, 39), (22, 34), (34, 45), (48, 34), (64, 41), (71, 86), (1, 86)], "#080b1e", INK)
    poly(d, [(5, 44), (20, 38), (28, 46), (19, 71), (7, 80), (1, 66)], "#352453")
    poly(d, [(47, 44), (59, 38), (71, 66), (64, 79), (53, 70), (45, 51)], "#39265b")
    poly(d, [(20, 45), (35, 42), (51, 45), (56, 84), (15, 84)], "#352448")
    poly(d, [(26, 48), (46, 48), (49, 75), (36, 83), (23, 76)], "#1a203f")
    poly(d, [(31, 55), (36, 51), (42, 56), (39, 66), (35, 69), (30, 63)], "#ce58ae")
    rect(d, (34, 57, 38, 62), "#ffd4ed")
    for x, y in ((13, 55), (55, 55), (22, 75), (49, 74)):
        rect(d, (x, y, x + 5, y + 1), "#ad4c9b")
        rect(d, (x + 1, y, x + 2, y), "#ed9bd1")
    rect(d, (8, 80, 64, 83), "#18112f")
    for points in (
        [(17, 8), (21, 1), (26, 8)],
        [(47, 8), (52, 1), (56, 11)],
        [(34, 5), (36, 0), (39, 5)],
    ):
        poly(d, points, "#4f3067", INK)
    rect(d, (35, 2, 38, 3), "#d36ebc")
    rect(d, (27, 21, 30, 23), "#eddfdc")
    rect(d, (42, 20, 46, 22), "#eddfdc")
    rect(d, (29, 31, 33, 32), "#464064")
    rect(d, (40, 31, 44, 32), "#464064")
    line(d, [(9, 48), (14, 52), (12, 58)], "#9f52a8")
    line(d, [(64, 48), (59, 53), (61, 59)], "#9f52a8")
    rect(d, (19, 68, 24, 69), "#a151a5")
    rect(d, (47, 67, 53, 68), "#a151a5")
    rect(d, (34, 71, 39, 73), "#4a3c73")
    return im


def sprite_canvas() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    im = Image.new("RGBA", (40, 40), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def upscale_sprite(im: Image.Image) -> Image.Image:
    return im.resize(SPRITE_SIZE, SCALE)


def draw_grounded_legs(draw: ImageDraw.ImageDraw, pose: str, dx: int, left: str, right: str) -> None:
    """Two clear contact poses; the shared floor line remains base y=36."""
    if pose == "walk_a":
        poly(draw, [(14 + dx, 25), (18 + dx, 25), (17, 32), (14, 35), (11, 35)], left, INK)
        poly(draw, [(22 + dx, 25), (26 + dx, 25), (27, 32), (26, 34), (23, 33)], right, INK)
        rect(draw, (10, 35, 17, 36), "#0a111d")
        rect(draw, (23, 33, 28, 34), "#0a111d")
    elif pose == "walk_b":
        poly(draw, [(14 + dx, 25), (18 + dx, 25), (17, 32), (15, 34), (12, 33)], left, INK)
        poly(draw, [(22 + dx, 25), (26 + dx, 25), (27, 33), (29, 35), (26, 35)], right, INK)
        rect(draw, (11, 33, 17, 34), "#0a111d")
        rect(draw, (24, 35, 30, 36), "#0a111d")
    else:
        for x, color in ((14, left), (23, right)):
            poly(draw, [(x + dx, 25), (x + 4 + dx, 25), (x + 5, 35), (x + 2, 36), (x - 1, 35)], color, INK)
            rect(draw, (x - 1, 35, x + 6, 36), "#0a111d")


def heroine_sprite(pose: str) -> Image.Image:
    im, d = sprite_canvas()
    walk = pose in ("walk_a", "walk_b")
    hurt = pose == "hurt"
    lean = -2 if hurt else (1 if pose == "attack_hit" else 0)
    # Hair behind torso; tiny rim clusters echo the portrait.
    poly(d, [(15 + lean, 5), (18 + lean, 2), (23 + lean, 2), (26 + lean, 6), (26 + lean, 24), (23 + lean, 28), (16 + lean, 27), (14 + lean, 20)], "#073c49", INK)
    rect(d, (15 + lean, 8, 17 + lean, 24), "#159996")
    rect(d, (24 + lean, 8, 26 + lean, 24), "#0d797f")
    # Grounded legs preserve the common foot pivot at base (20,36).
    if pose == "walk_a":
        poly(d, [(16, 25), (19, 25), (17, 34), (14, 36), (12, 35)], "#1d2938", INK)
        poly(d, [(22, 25), (25, 25), (27, 35), (25, 36), (23, 35)], "#233446", INK)
        rect(d, (11, 35, 16, 36), "#0a101e")
        rect(d, (23, 35, 28, 36), "#0a101e")
    elif pose == "walk_b":
        poly(d, [(16, 25), (19, 25), (14, 35), (12, 36), (11, 35)], "#1d2938", INK)
        poly(d, [(22, 25), (25, 25), (23, 34), (27, 36), (29, 35)], "#233446", INK)
        rect(d, (10, 35, 15, 36), "#0a101e")
        rect(d, (26, 35, 30, 36), "#0a101e")
    else:
        poly(d, [(16 + lean, 25), (19 + lean, 25), (19, 34), (17, 36), (14, 35)], "#1d2938", INK)
        poly(d, [(22 + lean, 25), (25 + lean, 25), (26, 35), (24, 36), (21, 35)], "#233446", INK)
        rect(d, (14, 35, 19, 36), "#0a101e")
        rect(d, (22, 35, 27, 36), "#0a101e")
    poly(d, [(15 + lean, 16), (19 + lean, 14), (24 + lean, 15), (27 + lean, 18), (26 + lean, 27), (16 + lean, 27), (14 + lean, 21)], "#31182d", INK)
    rect(d, (17 + lean, 18, 24 + lean, 25), "#78304a")
    rect(d, (19 + lean, 19, 21 + lean, 24), "#1d2737")
    rect(d, (17 + lean, 26, 25 + lean, 27), "#0c1728")
    rect(d, (20 + lean, 25, 21 + lean, 26), AMBER)
    poly(d, [(17 + lean, 7), (19 + lean, 5), (24 + lean, 6), (25 + lean, 12), (23 + lean, 17), (18 + lean, 16), (16 + lean, 13)], "#e0a58b", INK)
    rect(d, (18 + lean, 11, 19 + lean, 11), "#101c2b")
    rect(d, (23 + lean, 11, 24 + lean, 11), "#101c2b")
    poly(d, [(16 + lean, 7), (18 + lean, 3), (23 + lean, 3), (26 + lean, 7), (24 + lean, 10), (21 + lean, 9), (19 + lean, 12), (16 + lean, 12)], "#0a6973", INK)
    line(d, [(17 + lean, 7), (21 + lean, 4), (24 + lean, 6)], "#35d6c7", 1)
    rect(d, (15 + lean, 12, 16 + lean, 21), "#1bafa5")

    # Arms and the physical baton are separated from energy VFX.
    if pose == "attack_windup":
        line(d, [(16, 19), (13, 17), (10, 15)], "#152539", 4)
        rect(d, (9, 14, 11, 16), "#e2a78e")
        line(d, [(26, 19), (29, 14), (26, 11)], "#1c2a39", 4)
        rect(d, (25, 10, 27, 12), "#dfaa92")
        line(d, [(26, 11), (19, 4)], "#0b1524", 3)
        line(d, [(20, 5), (24, 9)], "#73d5d6", 1)
    elif pose == "attack_hit":
        line(d, [(16, 20), (13, 23), (10, 24)], "#152539", 4)
        rect(d, (9, 23, 11, 25), "#e2a78e")
        line(d, [(26, 19), (31, 18), (35, 18)], "#1c2a39", 4)
        rect(d, (34, 17, 36, 19), "#dfaa92")
        line(d, [(35, 18), (37, 13)], "#0a1322", 3)
        line(d, [(36, 16), (37, 13)], "#83e3dc", 1)
    elif pose == "attack_recover":
        line(d, [(16, 19), (14, 25)], "#152539", 4)
        rect(d, (13, 24, 15, 26), "#e2a78e")
        line(d, [(26, 19), (30, 23), (31, 25)], "#1c2a39", 4)
        rect(d, (30, 24, 32, 26), "#dfaa92")
        line(d, [(31, 25), (31, 34)], "#0a1322", 3)
        rect(d, (30, 32, 32, 34), CYAN)
    elif pose == "hurt":
        line(d, [(14, 19), (10, 19), (8, 21)], "#152539", 4)
        line(d, [(23, 20), (29, 17)], "#1c2a39", 4)
        rect(d, (7, 20, 9, 22), "#dfaa92")
        rect(d, (28, 16, 30, 18), "#dfaa92")
        line(d, [(29, 17), (33, 9)], "#0a1322", 3)
        rect(d, (32, 8, 34, 10), CYAN)
    else:
        line(d, [(15, 19), (13, 24)], "#152539", 4)
        rect(d, (12, 23, 14, 26), "#dca58c")
        line(d, [(27, 19), (30, 24)], "#1c2a39", 4)
        rect(d, (29, 23, 31, 26), "#dfaa92")
        line(d, [(30, 24), (33, 14)], "#0a1322", 3)
        line(d, [(32, 20), (33, 14)], "#71d8d6", 1)
        rect(d, (32, 12, 34, 15), CYAN)
    return upscale_sprite(im)


def guard_sprite(pose: str) -> Image.Image:
    im, d = sprite_canvas()
    dx = -2 if pose == "hurt" else 0
    draw_grounded_legs(d, pose, dx, "#1d2d3c", "#263949")
    poly(d, [(12 + dx, 15), (18 + dx, 13), (24 + dx, 13), (29 + dx, 18), (28 + dx, 28), (12 + dx, 28)], "#314655", INK)
    rect(d, (16 + dx, 18, 25 + dx, 25), "#1d303f")
    rect(d, (19 + dx, 19, 22 + dx, 22), "#cb5e72")
    rect(d, (17 + dx, 25, 26 + dx, 27), "#0e1a2a")
    poly(d, [(15 + dx, 6), (19 + dx, 3), (24 + dx, 4), (28 + dx, 8), (27 + dx, 15), (17 + dx, 16), (14 + dx, 12)], "#364e59", INK)
    rect(d, (17 + dx, 9, 26 + dx, 11), "#0b1725")
    rect(d, (18 + dx, 9, 25 + dx, 10), "#e77a80")
    rect(d, (18 + dx, 13, 25 + dx, 14), "#1d303e")
    if pose == "attack_windup":
        line(d, [(13, 18), (9, 14), (10, 9)], "#304b59", 4)
        line(d, [(28, 19), (31, 20)], "#304b59", 4)
        line(d, [(10, 10), (6, 3)], "#121a29", 3)
        rect(d, (5, 2, 7, 4), CYAN)
    elif pose == "attack_hit":
        line(d, [(13, 18), (8, 19), (4, 18)], "#304b59", 4)
        line(d, [(28, 19), (31, 22)], "#304b59", 4)
        line(d, [(6, 18), (3, 14)], "#121a29", 3)
        rect(d, (2, 12, 4, 15), CYAN)
    elif pose == "hurt":
        line(d, [(11, 18), (7, 22)], "#304b59", 4)
        line(d, [(25, 18), (31, 16)], "#304b59", 4)
        line(d, [(31, 16), (36, 10)], "#121a29", 3)
        rect(d, (35, 9, 37, 11), CYAN)
    elif pose == "walk_a":
        line(d, [(13, 18), (8, 22)], "#304b59", 4)
        line(d, [(28, 18), (32, 26)], "#304b59", 4)
        line(d, [(32, 25), (34, 15)], "#121a29", 3)
        rect(d, (33, 14, 35, 16), CYAN)
    elif pose == "walk_b":
        line(d, [(13, 18), (10, 27)], "#304b59", 4)
        line(d, [(28, 18), (31, 22)], "#304b59", 4)
        line(d, [(31, 22), (33, 12)], "#121a29", 3)
        rect(d, (32, 11, 34, 13), CYAN)
    else:
        line(d, [(13, 18), (10, 26)], "#304b59", 4)
        line(d, [(28, 18), (31, 25)], "#304b59", 4)
        line(d, [(30, 24), (32, 13)], "#121a29", 3)
        rect(d, (31, 12, 33, 14), CYAN)
    rect(d, (10, 24, 12, 27), "#637989")
    return upscale_sprite(im)


def captain_sprite(pose: str, weapon: str = "gun") -> Image.Image:
    im, d = sprite_canvas()
    dx = -2 if pose == "hurt" else 0
    draw_grounded_legs(d, pose, dx, "#293a4b", "#34485b")
    poly(d, [(12 + dx, 15), (17 + dx, 12), (25 + dx, 12), (30 + dx, 17), (29 + dx, 28), (12 + dx, 28)], "#38495a", INK)
    poly(d, [(16 + dx, 16), (25 + dx, 16), (27 + dx, 24), (20 + dx, 27), (15 + dx, 24)], "#5b6876")
    rect(d, (17 + dx, 16, 25 + dx, 17), AMBER)
    rect(d, (18 + dx, 21, 23 + dx, 23), "#1a293a")
    rect(d, (13 + dx, 15, 17 + dx, 17), "#e4b86a")
    rect(d, (25 + dx, 15, 29 + dx, 17), "#e4b86a")
    poly(d, [(15 + dx, 7), (18 + dx, 4), (25 + dx, 4), (28 + dx, 8), (27 + dx, 14), (17 + dx, 15)], "#687786", INK)
    rect(d, (17 + dx, 9, 26 + dx, 10), "#ee836c")
    rect(d, (16 + dx, 5, 27 + dx, 7), "#314358")
    rect(d, (19 + dx, 5, 23 + dx, 5), AMBER)
    if weapon == "baton":
        # Same officer before possession: his compact sidearm stays holstered
        # on the left hip while the right hand uses a short stun baton.
        rect(d, (11 + dx, 25, 16 + dx, 29), "#0b1322")
        rect(d, (12 + dx, 25, 16 + dx, 26), "#8498a3")
        rect(d, (12 + dx, 27, 13 + dx, 29), "#415569")
        if pose == "attack_windup":
            line(d, [(13, 18), (10, 25)], "#31485a", 4)
            line(d, [(29, 19), (32, 14), (30, 12)], "#324758", 4)
            line(d, [(30, 12), (23, 5)], "#0c1724", 3)
            rect(d, (22, 4, 24, 6), CYAN)
        elif pose == "attack_hit":
            line(d, [(13, 18), (10, 24)], "#31485a", 4)
            line(d, [(29, 19), (33, 18), (35, 18)], "#324758", 4)
            line(d, [(35, 18), (37, 12)], "#0c1724", 3)
            rect(d, (36, 11, 38, 13), CYAN)
        elif pose == "hurt":
            line(d, [(11, 18), (7, 21)], "#31485a", 4)
            line(d, [(27, 19), (31, 16)], "#324758", 4)
            line(d, [(31, 16), (34, 8)], "#0c1724", 3)
            rect(d, (33, 7, 35, 9), CYAN)
        elif pose == "walk_a":
            line(d, [(13, 18), (9, 22)], "#31485a", 4)
            line(d, [(29, 18), (33, 26)], "#324758", 4)
            line(d, [(33, 25), (35, 15)], "#0c1724", 3)
            rect(d, (34, 14, 36, 16), CYAN)
        elif pose == "walk_b":
            line(d, [(13, 18), (11, 27)], "#31485a", 4)
            line(d, [(29, 18), (31, 22)], "#324758", 4)
            line(d, [(31, 22), (33, 12)], "#0c1724", 3)
            rect(d, (32, 11, 34, 13), CYAN)
        else:
            line(d, [(13, 18), (10, 26)], "#31485a", 4)
            line(d, [(29, 18), (32, 24)], "#324758", 4)
            line(d, [(32, 24), (34, 14)], "#0c1724", 3)
            rect(d, (33, 13, 35, 15), CYAN)
        return upscale_sprite(im)
    if pose == "attack_windup":
        line(d, [(29, 19), (32, 15), (34, 14)], "#324758", 4)
        rect(d, (32, 11, 38, 16), "#0b111d")
        rect(d, (34, 12, 38, 13), "#8fa8ac")
        line(d, [(13, 18), (9, 25)], "#31485a", 4)
    elif pose == "attack_hit":
        line(d, [(29, 19), (34, 18), (36, 18)], "#324758", 4)
        rect(d, (33, 16, 38, 20), "#0b111d")
        rect(d, (35, 17, 38, 18), "#c0d9d2")
        line(d, [(13, 18), (9, 24)], "#31485a", 4)
    elif pose == "hurt":
        line(d, [(10, 18), (7, 20)], "#31485a", 4)
        line(d, [(27, 18), (33, 16)], "#31485a", 4)
        rect(d, (32, 13, 38, 18), "#0b111d")
        rect(d, (36, 14, 38, 15), "#c0d9d2")
    elif pose == "walk_a":
        line(d, [(13, 18), (8, 22)], "#31485a", 4)
        line(d, [(29, 18), (33, 27)], "#324758", 4)
        rect(d, (30, 25, 37, 28), "#0b111d")
        rect(d, (33, 26, 37, 27), "#8fa8ac")
    elif pose == "walk_b":
        line(d, [(13, 18), (11, 27)], "#31485a", 4)
        line(d, [(29, 18), (31, 22)], "#324758", 4)
        rect(d, (29, 20, 36, 24), "#0b111d")
        rect(d, (33, 21, 37, 22), "#8fa8ac")
    else:
        line(d, [(13, 18), (10, 26)], "#31485a", 4)
        line(d, [(29, 18), (32, 25)], "#324758", 4)
        rect(d, (29, 23, 36, 27), "#0b111d")
        rect(d, (33, 24, 37, 25), "#8fa8ac")
    return upscale_sprite(im)


def medic_sprite(pose: str) -> Image.Image:
    im, d = sprite_canvas()
    dx = -2 if pose == "hurt" else 0
    draw_grounded_legs(d, pose, dx, "#234050", "#2e5260")
    poly(d, [(13 + dx, 15), (18 + dx, 12), (24 + dx, 13), (29 + dx, 18), (28 + dx, 29), (12 + dx, 29)], "#d6ebe4", INK)
    poly(d, [(16 + dx, 16), (21 + dx, 20), (25 + dx, 16), (26 + dx, 28), (14 + dx, 28)], "#8bc8c3")
    rect(d, (19 + dx, 20, 23 + dx, 28), "#184453")
    rect(d, (25 + dx, 21, 27 + dx, 24), "#2b9aa2")
    rect(d, (25 + dx, 22, 27 + dx, 22), "#c8fff0")
    poly(d, [(15 + dx, 7), (19 + dx, 4), (24 + dx, 4), (27 + dx, 8), (26 + dx, 14), (17 + dx, 15)], "#e9beaa", INK)
    poly(d, [(14 + dx, 7), (19 + dx, 2), (25 + dx, 3), (28 + dx, 8), (24 + dx, 8), (18 + dx, 10), (15 + dx, 11)], "#97dfd2", INK)
    rect(d, (17 + dx, 11, 26 + dx, 13), "#e9f5ed")
    rect(d, (19 + dx, 11, 24 + dx, 12), "#76b8b9")
    if pose == "attack_windup":
        line(d, [(13, 19), (9, 14), (11, 12)], "#d0e8e0", 4)
        line(d, [(28, 19), (31, 14)], "#d0e8e0", 4)
        rect(d, (29, 9, 35, 14), "#1c6170")
        rect(d, (31, 8, 33, 10), CYAN)
    elif pose == "attack_hit":
        line(d, [(13, 19), (10, 24)], "#d0e8e0", 4)
        line(d, [(28, 18), (34, 17), (37, 18)], "#d0e8e0", 4)
        rect(d, (34, 15, 38, 20), "#1b6b77")
        rect(d, (36, 16, 38, 18), PALE)
    elif pose == "hurt":
        line(d, [(10, 19), (6, 19)], "#d0e8e0", 4)
        line(d, [(25, 19), (30, 23)], "#d0e8e0", 4)
        rect(d, (29, 21, 34, 25), "#2f8087")
    elif pose == "walk_a":
        line(d, [(13, 19), (8, 23)], "#d0e8e0", 4)
        line(d, [(28, 19), (32, 26)], "#d0e8e0", 4)
        rect(d, (30, 24, 35, 28), "#2f8087")
        rect(d, (32, 23, 34, 24), "#bdfff1")
    elif pose == "walk_b":
        line(d, [(13, 19), (10, 27)], "#d0e8e0", 4)
        line(d, [(28, 19), (31, 22)], "#d0e8e0", 4)
        rect(d, (29, 20, 34, 24), "#2f8087")
        rect(d, (31, 19, 33, 20), "#bdfff1")
    else:
        line(d, [(13, 19), (10, 25)], "#d0e8e0", 4)
        line(d, [(28, 19), (31, 25)], "#d0e8e0", 4)
        rect(d, (29, 23, 34, 27), "#2f8087")
        rect(d, (31, 22, 33, 23), "#bdfff1")
    return upscale_sprite(im)


def corrector_sprite(pose: str) -> Image.Image:
    im, d = sprite_canvas()
    dx = -2 if pose == "hurt" else 0
    # Large silhouette with floating magenta crown and grounded armored feet.
    line(d, [(9 + dx, 9), (15 + dx, 3), (24 + dx, 3), (31 + dx, 9)], "#6f357d", 2)
    rect(d, (12 + dx, 5, 14 + dx, 7), MAGENTA)
    rect(d, (27 + dx, 5, 29 + dx, 7), MAGENTA)
    for x in (13, 23):
        poly(d, [(x + dx, 24), (x + 5 + dx, 24), (x + 5, 35), (x + 2, 36), (x - 1, 35)], "#201a36", INK)
        rect(d, (x - 1, 35, x + 6, 36), "#0a0d1b")
    poly(d, [(8 + dx, 14), (14 + dx, 10), (27 + dx, 10), (34 + dx, 15), (36 + dx, 27), (27 + dx, 31), (12 + dx, 31), (5 + dx, 26)], "#291d45", INK)
    poly(d, [(12 + dx, 15), (19 + dx, 12), (27 + dx, 15), (30 + dx, 25), (21 + dx, 29), (11 + dx, 25)], "#40305e")
    poly(d, [(15 + dx, 16), (21 + dx, 14), (26 + dx, 17), (24 + dx, 23), (20 + dx, 25), (16 + dx, 22)], "#c954aa")
    rect(d, (19 + dx, 18, 22 + dx, 21), "#f2b4de")
    poly(d, [(15 + dx, 5), (19 + dx, 2), (24 + dx, 3), (27 + dx, 7), (25 + dx, 13), (17 + dx, 13)], "#64647b", INK)
    rect(d, (17 + dx, 8, 25 + dx, 9), "#1a142b")
    rect(d, (18 + dx, 8, 24 + dx, 8), "#f083c9")
    poly(d, [(9 + dx, 14), (14 + dx, 12), (12 + dx, 26), (6 + dx, 24)], "#4c315f", INK)
    poly(d, [(29 + dx, 12), (34 + dx, 15), (37 + dx, 25), (31 + dx, 27)], "#4c315f", INK)
    if pose == "attack_windup":
        line(d, [(10, 18), (7, 11), (9, 7)], "#704482", 5)
        line(d, [(33, 18), (35, 10), (33, 7)], "#704482", 5)
        rect(d, (6, 5, 10, 8), "#a851ab")
        rect(d, (32, 5, 36, 8), "#a851ab")
    elif pose == "attack_hit":
        line(d, [(10, 19), (6, 19), (4, 16)], "#704482", 4)
        line(d, [(33, 19), (36, 18), (37, 15)], "#704482", 4)
        rect(d, (2, 14, 5, 17), "#b257b4")
        rect(d, (35, 13, 38, 17), "#b257b4")
    elif pose == "hurt":
        line(d, [(8, 20), (3, 24)], "#704482", 5)
        line(d, [(31, 20), (36, 16)], "#704482", 5)
    else:
        line(d, [(8, 18), (5, 27)], "#704482", 5)
        line(d, [(33, 18), (35, 27)], "#704482", 4)
        rect(d, (3, 26, 7, 28), "#9a4d9f")
        rect(d, (35, 26, 38, 28), "#9a4d9f")
    return upscale_sprite(im)


MAPS = {
    "security_checkpoint": draw_security_map,
    "medical_room": draw_medical_map,
    "root_lab": draw_root_map,
}

PORTRAITS = {
    "heroine": draw_heroine_portrait,
    "guard": draw_guard_portrait,
    "captain_melee": lambda: draw_captain_portrait(weapon="baton"),
    "captain": draw_captain_portrait,
    "medic": draw_medic_portrait,
    "corrector": draw_corrector_portrait,
}

SPRITES = {
    "heroine": {
        "idle": heroine_sprite,
        "walk_a": heroine_sprite,
        "walk_b": heroine_sprite,
        "attack_windup": heroine_sprite,
        "attack_hit": heroine_sprite,
        "attack_recover": heroine_sprite,
        "hurt": heroine_sprite,
    },
    "guard": {name: guard_sprite for name in ("idle", "walk_a", "walk_b", "attack_windup", "attack_hit", "hurt")},
    "captain_melee": {
        name: (lambda pose: captain_sprite(pose, weapon="baton"))
        for name in ("idle", "walk_a", "walk_b", "attack_windup", "attack_hit", "hurt")
    },
    "captain": {name: captain_sprite for name in ("idle", "walk_a", "walk_b", "attack_windup", "attack_hit", "hurt")},
    "medic": {name: medic_sprite for name in ("idle", "walk_a", "walk_b", "attack_windup", "attack_hit", "hurt")},
    "corrector": {name: corrector_sprite for name in ("idle", "attack_windup", "attack_hit", "hurt")},
}


def write_art(path: Path, image: Image.Image, *, kind: str, identity: str, pose: str | None = None) -> dict:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)
    alpha_extrema = image.getchannel("A").getextrema() if "A" in image.getbands() else None
    return {
        "file": path.relative_to(ROOT).as_posix(),
        "kind": kind,
        "identity": identity,
        "pose": pose,
        "size": list(image.size),
        "mode": image.mode,
        "alpha_extrema": list(alpha_extrema) if alpha_extrema else None,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }


def write_review_previews() -> list[str]:
    review = ROOT / "review"
    review.mkdir(parents=True, exist_ok=True)
    map_sheet = Image.new("RGB", (1920, 390), "#0a0d19")
    map_draw = ImageDraw.Draw(map_sheet)
    for index, name in enumerate(MAPS):
        map_draw.text((index * 640 + 11, 8), name, fill="#bcf8eb")
        source = Image.open(ROOT / "maps" / f"{name}.png")
        map_sheet.paste(source.resize((640, 360), SCALE), (index * 640, 28))
    map_sheet.save(review / "maps-contact.png", optimize=True)

    portraits = Image.new("RGB", (len(PORTRAITS) * 176, 242), "#0a0d19")
    portrait_draw = ImageDraw.Draw(portraits)
    for index, name in enumerate(PORTRAITS):
        x = index * 176
        rect(portrait_draw, (x + 3, 28, x + 172, 238), "#151e30")
        rect(portrait_draw, (x + 8, 34, x + 167, 232), "#203348")
        for line_y in range(43, 230, 16):
            line(portrait_draw, [(x + 9, line_y), (x + 166, line_y)], "#294056")
        portrait_draw.text((x + 10, 8), name, fill="#e5fff2")
        source = Image.open(ROOT / "portraits" / f"{name}.png").convert("RGBA")
        scaled = source.resize((144, 176), SCALE)
        portraits.paste(scaled, (x + 16, 49), scaled)
    portraits.save(review / "portraits-contact.png", optimize=True)

    poses = ["idle", "walk_a", "walk_b", "attack_windup", "attack_hit", "attack_recover", "hurt"]
    contact = Image.new("RGB", (7 * 112, len(SPRITES) * 122), "#0b1020")
    contact_draw = ImageDraw.Draw(contact)
    for row, role in enumerate(SPRITES):
        available = SPRITES[role]
        for col, pose in enumerate(poses):
            if pose not in available:
                continue
            x, y = col * 112, row * 122
            rect(contact_draw, (x + 2, y + 19, x + 109, y + 119), "#19243a")
            for gx in range(x + 10, x + 104, 16):
                line(contact_draw, [(gx, y + 25), (gx, y + 115)], "#20344b")
            contact_draw.text((x + 4, y + 4), role + " " + pose.replace("attack_", ""), fill="#bfe9e4")
            source = Image.open(ROOT / "sprites" / role / f"{pose}.png").convert("RGBA")
            contact.paste(source, (x + 16, y + 28), source)
    contact.save(review / "sprites-contact.png", optimize=True)
    return [
        "review/maps-contact.png",
        "review/portraits-contact.png",
        "review/sprites-contact.png",
    ]


def main() -> None:
    records: list[dict] = []
    for name, create in MAPS.items():
        records.append(write_art(ROOT / "maps" / f"{name}.png", create(), kind="map", identity=name))
    for name, create in PORTRAITS.items():
        records.append(write_art(ROOT / "portraits" / f"{name}.png", create(), kind="portrait", identity=name))
    for role, poses in SPRITES.items():
        for pose, create in poses.items():
            records.append(
                write_art(
                    ROOT / "sprites" / role / f"{pose}.png",
                    create(pose),
                    kind="sprite",
                    identity=role,
                    pose=pose,
                )
            )
    previews = write_review_previews()
    manifest = {
        "version": 1,
        "source": "Original deterministic Pillow pixel drawing; no remote model or copied reference pixels.",
        "style": "hard-edge cyan/magenta cyberpunk pixel art",
        "map_size": list(MAP_SIZE),
        "portrait_size": list(PORTRAIT_SIZE),
        "sprite_size": list(SPRITE_SIZE),
        "sprite_foot_pivot": list(SPRITE_PIVOT),
        "review_previews": previews,
        "files": records,
    }
    (ROOT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"COMBAT_ART_PASS files={len(records)} maps={len(MAPS)} portraits={len(PORTRAITS)} sprites={sum(map(len, SPRITES.values()))}")


if __name__ == "__main__":
    main()
