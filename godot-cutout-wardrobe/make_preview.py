"""Review collage/GIF assembled from the actual rendered outfit frames."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
P = ROOT / "preview"
FONT = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 20)
SMALL = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 15)
BG = (10,18,29,255)
STYLES = [("armor_blue","蓝甲"),("armor_red","红甲"),("casual","日常服"),("bikini","比基尼")]

def frame(style,action,key):
    return Image.open(P/f"{style}_{action}_{key:02d}.png").convert("RGBA")

def layout(action,key):
    canvas = Image.new("RGBA", (1280,390), BG)
    d = ImageDraw.Draw(canvas)
    for column,(style,label) in enumerate(STYLES):
        x=column*320
        d.text((x+18,13),label,font=FONT,fill=(213,230,244))
        tile=frame(style,action,key).crop((55,88,375,358))
        canvas.alpha_composite(tile,(x,61))
        d.line((x+8,324,x+306,324),fill=(91,115,144),width=1)
    d.text((18,349),"同一骨架 · 每个服装部件连同露出的皮肤一起画 · 躯干、手臂、腿脚、披风可分别切换",font=SMALL,fill=(163,192,216))
    return canvas.convert("RGB")

layout("idle",0).save(P/"outfit-gallery.png")
walk=[layout("walk",i) for i in range(4)]
walk[0].save(P/"outfit-walk.gif",save_all=True,append_images=walk[1:],duration=[220]*4,loop=0,disposal=2)
sheet=Image.new("RGBA",(1536,620),BG)
d=ImageDraw.Draw(sheet)
for row,style in enumerate(["casual","bikini"]):
    for key in range(6):
        x=key*256
        # Preserve the complete rendered frame, including the wind-up sword tip.
        tile=frame(style,"slash",key).resize((256,256),Image.Resampling.NEAREST)
        y=row*310+40
        sheet.alpha_composite(tile,(x,y))
        d.text((x+8,y-30),f"{style} {key+1}",font=SMALL,fill=(202,222,241))
sheet.convert("RGB").save(P/"outfit-slash-keyposes.png")
print("WARDROBE_PREVIEW_READY: outfit-gallery.png, outfit-walk.gif")
