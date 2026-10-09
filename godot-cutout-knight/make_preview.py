"""Arrange already-rendered Godot frames into a review GIF and contact sheet."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
PREVIEW = ROOT / "preview"
FONT = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 20)
SMALL = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 15)
BG = (10, 18, 29, 255)
poses = {}
for action, count in [("idle", 1), ("walk", 4), ("slash", 6)]:
    for frame in range(count):
        poses[action, frame] = Image.open(PREVIEW / f"{action}_{frame:02d}.png").convert("RGBA")

def attack_key(t):
    for i, duration in enumerate([.19, .19, .12, .12, .19, .28]):
        if t < duration:
            return ("slash", i)
        t -= duration
    return ("idle", 0)

frames = []
durations = []
clock = 0.0
for i in range(32):
    canvas = Image.new("RGBA", (900, 525), BG)
    draw = ImageDraw.Draw(canvas)
    draw.text((22, 10), "四帧走路 · 左右腿交替", font=FONT, fill=(214,230,246))
    draw.text((472, 10), "六姿势挥剑 · 独立武器", font=FONT, fill=(214,230,246))
    for x, key in [(20, ("walk", int(clock/.22) % 4)), (470, attack_key(clock))]:
        picture = poses[key].crop((70,10,390,355)).resize((416,448), Image.Resampling.NEAREST)
        canvas.alpha_composite(picture, (x,43))
        draw.line((x,488,x+416,488), fill=(93,118,146), width=1)
    draw.text((22,501), "2.5D 独立部件骨架原型；关节接缝仍需修整。", font=SMALL, fill=(173,197,218))
    frames.append(canvas.convert("RGB"))
    duration = 50 if i % 2 == 0 else 60
    durations.append(duration)
    clock += duration/1000
frames[0].save(PREVIEW / "walk-and-slash.gif", save_all=True, append_images=frames[1:], duration=durations, loop=0, disposal=2)

sheet = Image.new("RGBA", (1200, 740), BG)
draw = ImageDraw.Draw(sheet)
for index, key in enumerate([("walk",i) for i in range(4)] + [("slash",i) for i in range(6)]):
    row = 0 if index < 4 else 1
    col = index if index < 4 else index-4
    width = 300 if row == 0 else 200
    tile = poses[key].crop((70,10,390,355))
    target = (int(width*.90), int(width*.90*345/320))
    tile = tile.resize(target, Image.Resampling.NEAREST)
    x = col*width+(width-target[0])//2
    y = 46 if row == 0 else 410
    sheet.alpha_composite(tile,(x,y))
    draw.text((col*width+12,y-30), f"{key[0]} {key[1]+1}",font=SMALL,fill=(201,223,242))
sheet.convert("RGB").save(PREVIEW / "all-keyposes.png")
print("PREVIEWS_READY: walk-and-slash.gif, all-keyposes.png")
