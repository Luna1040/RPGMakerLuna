from pathlib import Path
import sys,time,json
ROOT=Path(__file__).resolve().parent/'h3-runtime'
sys.path.insert(0,str(ROOT.parent))
sys.path.insert(0,str(ROOT/'matte-deps'))
import torch,onnxruntime as ort
import numpy as np
from PIL import Image,ImageDraw
from improve_h3_matte import matte
def session(use_gpu=True):
 if hasattr(ort,'preload_dlls'):ort.preload_dlls()
 opts=ort.SessionOptions();opts.intra_op_num_threads=8
 providers=[('CUDAExecutionProvider',{'device_id':0,'gpu_mem_limit':6*1024**3}), 'CPUExecutionProvider'] if use_gpu else ['CPUExecutionProvider']
 s=ort.InferenceSession(str(ROOT/'matte-v2/birefnet-lite.onnx'),sess_options=opts,providers=providers)
 print('PROVIDERS',s.get_providers(),'INPUT',s.get_inputs()[0].shape,flush=True)
 return s
def extract(s,im,return_mask=False):
 rgb=np.asarray(im.convert('RGB')).astype(np.float32)
 # Crop for segmentation only, then restore the original canvas and origin.
 yy,xx=np.where(rgb.max(axis=2)>20)
 box=(max(0,int(xx.min())-24),max(0,int(yy.min())-24),min(im.width,int(xx.max())+25),min(im.height,int(yy.max())+25))
 small=im.crop(box).convert('RGB').resize((1024,1024),Image.Resampling.BILINEAR)
 x=np.asarray(small).astype(np.float32)/255
 x=(x-np.array([.485,.456,.406],np.float32))/np.array([.229,.224,.225],np.float32)
 y=s.run(None,{s.get_inputs()[0].name:x.transpose(2,0,1)[None]})[-1].squeeze()
 if y.min()<0 or y.max()>1:y=1/(1+np.exp(-np.clip(y,-30,30)))
 alpha=np.zeros(rgb.shape[:2],np.float32)
 a=np.asarray(Image.fromarray(y.astype('float32'),'F').resize((box[2]-box[0],box[3]-box[1]),Image.Resampling.BILINEAR))
 alpha[box[1]:box[3],box[0]:box[2]]=a
 # Use the precise black key for the outside edge; AI removes internal holes.
 base=np.asarray(matte(im,True)).astype(np.float32)
 final=np.minimum(base[:,:,3]/255,np.clip((alpha-.03)/.94,0,1))
 # The model can classify detached blue sword trails as background.
 blue=(rgb[:,:,2]>40)&(rgb[:,:,2]-rgb[:,:,0]>18)&(rgb[:,:,2]-rgb[:,:,1]>7)
 final[blue]=base[:,:,3][blue]/255
 # Blue glow rejected by the body model is light composited over black, not
 # opaque dark-blue paint. Recover its coverage and unpremultiply its color.
 glow=blue&(alpha<.8)
 coverage=np.clip(rgb.max(axis=2)/255,0,1)
 final[glow]=(base[:,:,3][glow]/255)*coverage[glow]
 base[:,:,:3][glow]=np.clip(rgb[glow]/np.maximum(coverage[glow,None],.05),0,255)
 result=Image.fromarray(np.dstack([base[:,:,:3],final*255]).clip(0,255).astype('uint8'),'RGBA')
 return (result,alpha) if return_mask else result
if __name__=='__main__':
 s=session();out=ROOT/'matte-v2';sheet=Image.new('RGB',(1440,740),'#dbe2eb');d=ImageDraw.Draw(sheet)
 for row,(action,idx,box) in enumerate([('walk-hq',40,(230,140,440,290)),('attack-hq',60,(145,180,450,340))]):
  im=Image.open(ROOT/'output/frames'/f'{action}_{idx+1:05d}_.png').convert('RGB');t=time.time();cut=extract(s,im);cut.save(out/(action+'-biref.png'));print(action,'seconds',time.time()-t,flush=True)
  for col,(pic,title) in enumerate([(Image.open(ROOT/'review'/action/f'{idx:04d}.png'),'OLD'),(matte(im,True),'V2 KEY'),(cut,'AI + V2 KEY')]):
   bg=Image.new('RGBA',pic.size,'#c7d5e7');bg.alpha_composite(pic);crop=bg.crop(box).resize((470,320),Image.Resampling.NEAREST);sheet.paste(crop,(col*480,row*370+40));d.text((col*480+8,row*370+10),action+' / '+title,fill='#132338')
 sheet.save(out/'biref-comparison.png')
