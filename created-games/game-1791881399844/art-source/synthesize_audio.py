from pathlib import Path
import math,random,wave,struct
root=Path('created-games/game-1791881399844/assets/shooter-v1/audio'); root.mkdir(exist_ok=True)
rng=random.Random(17)
for name,duration,base in [('shot',.08,950),('hit',.16,160),('explode',.55,85),('pulse',.6,440),('upgrade',.5,660),('victory',1.2,523)]:
 rate=22050; data=[]
 for n in range(int(rate*duration)):
  t=n/rate; x=t/duration; env=(1-x)**2*min(1,t/.006)
  freq=base*(1-.6*x) if name not in ['upgrade','victory'] else base*([1,1.25,1.5,2][min(3,int(x*4))])
  signal=math.sin(math.tau*freq*t)
  if name in ['hit','explode']: signal=signal*.25+rng.uniform(-1,1)*.75
  data.append(struct.pack('<h',int(signal*env*6500)))
 with wave.open(str(root/(name+'.wav')),'wb') as f: f.setparams((1,2,rate,0,'NONE','not compressed'));f.writeframes(b''.join(data))
