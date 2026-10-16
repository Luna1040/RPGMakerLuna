from pathlib import Path
from PIL import Image,ImageDraw
import shutil
root=Path('created-games/game-1791881399844'); dest=root/'assets/shooter-v1';dest.mkdir(exist_ok=True)
src=Path('C:/Users/11043/.codex/generated_images/01a11a72-2a35-7b01-9d6c-2bbb93234718')
names={'scout':'4572f190-2a04-4e85-aaae-1b433d5f558c','gunship':'37688137-b726-4854-bee8-13fa1060d18e','spinner':'e4627bee-2ebc-4d51-bb5d-332b5163f919','boss':'6c9e4c73-e6be-417c-9a49-694af30fc98b'}
contact=Image.new('RGB',(1200,640),(12,23,38))
for n,(name,uid) in enumerate(names.items()):
 im=Image.open(root/'art-source'/f'{name}-original.png').convert('RGBA')
 box=im.getchannel('A').getbbox();print(name,im.size,im.getchannel('A').getextrema(),box)
 im=im.crop(box);im.thumbnail((460,460),Image.Resampling.LANCZOS);out=Image.new('RGBA',(512,512));out.alpha_composite(im,((512-im.width)//2,(512-im.height)//2));out.save(dest/f'{name}.png')
 out.thumbnail((280,280));contact.paste(out,(n*300,140),out);ImageDraw.Draw(contact).text((n*300+20,100),name,fill='white')
contact.save(root/'art-source/shooter-contact.jpg')
