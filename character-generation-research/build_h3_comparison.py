"""Local adaptations of preserved community recipes; original files remain intact."""
from pathlib import Path
import json
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
sys.stdout.reconfigure(encoding='utf-8',errors='replace')
sys.stderr.reconfigure(encoding='utf-8',errors='replace')
import build_guofeng_workflows as base
from build_h3_drama import PROMPTS

ROOT=Path(__file__).resolve().parent
DEST=ROOT/'h3-comparison'
SCHEMA=json.loads((DEST/'node-schema.json').read_text(encoding='utf-8'))
base.SCHEMA=SCHEMA
REF='wuxia-opening-reference-v1.png'
MODEL='minimax_h3_ref2va_pruned_fp8_scaled.safetensors'
LORA='minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors'

def add(g,i,kind,**values):
    # Populate only primitive required defaults; object sockets stay explicit.
    inputs={}
    for name,spec in SCHEMA[kind]['input'].get('required',{}).items():
        if len(spec)>1 and isinstance(spec[1],dict) and 'default' in spec[1]:
            inputs[name]=spec[1]['default']
    inputs.update(values)
    base.node(g,i,kind,**inputs)

def video_output(g,ident,images,prefix):
    add(g,ident,'VHS_VideoCombine',images=images,frame_rate=24.,loop_count=0,
        filename_prefix=prefix,format='video/h264-mp4',pix_fmt='yuv420p',crf=19,
        save_metadata=True,trim_to_audio=False,pingpong=False,save_output=True)

def mbedit(shot=0, previous=None, attention='pytorch attention'):
    g={}
    add(g,1,'LoadImage',image=REF)
    add(g,2,'CLIPLoader',clip_name='qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors',type='minimax',device='default')
    add(g,3,'UNETLoader',unet_name=MODEL,weight_dtype='default')
    add(g,4,'VAELoader',vae_name='minimax_h3_video_vae_fp16.safetensors')
    add(g,5,'LoraLoaderModelOnly',model=['3',0],lora_name=LORA,strength_model=0.8)
    add(g,6,'ModelAttentionBackend',model=['5',0],attention=attention)
    add(g,7,'MiniMaxH3SigmaShift',model=['6',0],shift_video=12.,shift_audio=3.)
    refs={'ref_images.ref_image_0':['1',0]}
    first=['1',0]
    if previous:
        add(g,30,'LoadImage',image=previous)
        first=['30',0]
        refs['ref_images.ref_image_1']=first
    add(g,8,'MiniMaxH3ReferenceToVideo',clip=['2',0],vae=['4',0],prompt=PROMPTS[shot],width=960,height=544,length=243,ref_image_size='match',**refs)
    add(g,9,'ImageScale',image=first,upscale_method='lanczos',width=960,height=544,crop='disabled')
    add(g,10,'MiniMaxH3AddGuide',positive=['8',0],latent=['8',1],vae=['4',0],image=['9',0],frame_idx=0)
    add(g,11,'RandomNoise',noise_seed=731429+shot*7919)
    add(g,12,'KSamplerSelect',sampler_name='euler')
    add(g,13,'BasicScheduler',model=['7',0],scheduler='simple',steps=8,denoise=1.)
    add(g,14,'BasicGuider',model=['7',0],conditioning=['10',0])
    add(g,15,'SamplerCustomAdvanced',noise=['11',0],guider=['14',0],sampler=['12',0],sigmas=['13',0],latent_image=['8',1])
    add(g,16,'LTXVSeparateAVLatent',av_latent=['15',0])
    add(g,17,'MinimaxH3LatentUpscaler3D',latent=['16',0],model_name='minimax_h3_latent_upscaler_3d_conv_v1_bf16.safetensors',mode='megapixels',**{'mode.megapixels':1.0},align=32,enable_temporal_chunking=True,force_unload=True,device='cuda',precision='fp16')
    add(g,18,'LTXVConcatAVLatent',video_latent=['17',0],audio_latent=['16',1])
    add(g,19,'ManualSigmas',sigmas='0.9035, 0.6316, 0.3158, 0.0000')
    # First-frame guide geometry must match each pass's own latent grid.
    add(g,31,'MiniMaxH3AddGuide',positive=['8',0],latent=['18',0],vae=['4',0],image=first,frame_idx=0)
    add(g,32,'BasicGuider',model=['7',0],conditioning=['31',0])
    add(g,20,'SamplerCustomAdvanced',noise=['11',0],guider=['32',0],sampler=['12',0],sigmas=['19',0],latent_image=['18',0])
    add(g,21,'LTXVSeparateAVLatent',av_latent=['20',0])
    add(g,22,'VAEDecodeTiled',samples=['21',0],vae=['4',0],tile_size=512,overlap=64,temporal_size=32,temporal_overlap=8)
    video_output(g,24,['22',0],f'h3-comparison/01_MBEDIT_Latent/shot{shot+1}')
    return g

def save(name,g):
    (DEST/(name+'.api.json')).write_text(json.dumps(g,ensure_ascii=False,indent=2),encoding='utf-8')

if __name__=='__main__':
    save('01_MBEDIT_Latent_shot1',mbedit())
    (DEST/'comparison-script.json').write_text(json.dumps(PROMPTS,ensure_ascii=False,indent=2),encoding='utf-8')
    (DEST/'adaptations.json').write_text(json.dumps({'01':{
        'source':'MBEDIT - MH3-r2v_2Pass-LatentUpscaler_v5.json',
        'preserved':'LoRA 0.8; shifts 12/3; 960x544; euler/simple 8 steps; learned latent upscale 1MP; second pass 0.9035,0.6316,0.3158,0',
        'changes':['local FP8 model replaces unavailable INT8 ConvRot','local FP16 video VAE replaces INT8 VAE','one shared image replaces five example references','first-frame guide added for requested image-to-video and shot continuity','243 frames per shot; shared three-shot script','tiled video decode and silent MP4 output','pytorch attention until isolated CUDA13 dependency completes']
    }},ensure_ascii=False,indent=2),encoding='utf-8')
    print(DEST)
