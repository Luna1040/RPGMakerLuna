"""Extract labelled frames for visual review; retain originals at native size."""
from pathlib import Path
import argparse,subprocess,json
from PIL import Image,ImageDraw

ROOT=Path(__file__).resolve().parent/'h3-comparison'
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('video');p.add_argument('--name',required=True);args=p.parse_args()
    video=Path(args.video);dest=ROOT/'qa'/args.name;dest.mkdir(parents=True,exist_ok=True)
    info=json.loads(subprocess.check_output([r'C:\ffmpeg\bin\ffprobe.exe','-v','error','-show_entries','format=duration','-of','json',str(video)]))
    duration=float(info['format']['duration']);times=[min(duration-.08,duration*i/11) for i in range(12)]
    sheet=Image.new('RGB',(4*640,3*390),(20,27,22));draw=ImageDraw.Draw(sheet)
    for i,t in enumerate(times):
        frame=dest/f'{i:02d}_{t:.2f}s.png'
        subprocess.run([r'C:\ffmpeg\bin\ffmpeg.exe','-y','-v','error','-ss',str(t),'-i',str(video),'-frames:v','1',str(frame)],check=True)
        im=Image.open(frame).convert('RGB');im.thumbnail((640,360))
        x,y=i%4*640,i//4*390;sheet.paste(im,(x,y+30));draw.text((x+10,y+7),f'{args.name} | {t:.2f}s',fill='white')
    sheet.save(dest/'contact-sheet.jpg',quality=94)
    print(dest/'contact-sheet.jpg')
