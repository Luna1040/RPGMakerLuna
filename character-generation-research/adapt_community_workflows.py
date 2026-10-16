"""Resolve author canvases into API graphs, retaining executed author nodes."""
import json
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from build_h3_comparison import ROOT,DEST,SCHEMA,REF,MODEL,LORA,PROMPTS,add,save,video_output

SOURCES=ROOT/'h3-community-workflows'
# Author source confirms these defaults; replace with live schema on restart.
SCHEMA.setdefault('RTXVideoSuperResolution',{'input':{'required':{
    'strength':['FLOAT',{'default':1.0}],
    'image_encoding':['STRING',{'default':'8-bit RGB'}]}}})

def widgets(n):
    if 'widgets_values_named' in n:return dict(n['widgets_values_named'])
    values=n.get('widgets_values',[])
    if isinstance(values,dict):return dict(values)
    out={};i=0
    schema=SCHEMA.get(n['type'],{}).get('input',{})
    for section in ('required','optional'):
        for name,spec in schema.get(section,{}).items():
            typ=spec[0]; opts=spec[1] if len(spec)>1 and isinstance(spec[1],dict) else {}
            if opts.get('forceInput'):continue
            if isinstance(typ,list) or typ in ('STRING','INT','FLOAT','BOOLEAN','COMBO','COMFY_DYNAMICCOMBO_V3'):
                if i>=len(values):continue
                out[name]=values[i];i+=1
                if opts.get('control_after_generate') and i<len(values) and values[i] in ('fixed','randomize','increment','decrement'):i+=1
    return out

class Adapter:
    def __init__(self,path,overrides=None):
        self.w=json.loads(path.read_text(encoding='utf-8'));self.ns={n['id']:n for n in self.w['nodes']}
        self.links={l[0]:l for l in self.w['links']};self.g={};self.overrides=overrides or {}
    def resolve(self,ident,slot=0):
        n=self.ns[ident];kind=n['type']
        if kind=='Reroute' or n.get('mode')==4:
            output=n.get('outputs',[{}])[slot].get('type')
            inp=next((v for v in n.get('inputs',[]) if v.get('link') and (kind=='Reroute' or v.get('type')==output)),None)
            if inp is None:raise ValueError(f'No bypass {ident}:{slot}')
            l=self.links[inp['link']];return self.resolve(l[1],l[2])
        if kind in ('PrimitiveFloat','PrimitiveInt','PrimitiveStringMultiline','PrimitiveBoolean','easy int'):
            return self.overrides.get(ident,{}).get('value',widgets(n).get('value',n['widgets_values'][0]))
        if str(ident) in self.g:return [str(ident),slot]
        if kind not in SCHEMA:raise ValueError(f'Missing node {kind} ({ident})')
        vals=widgets(n);override=self.overrides.get(ident,{})
        if kind=='LoadImage':vals={'image':REF}
        if kind=='UNETLoader':vals['unet_name']=MODEL
        if kind=='CLIPLoader':vals['clip_name']='qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors'
        if kind=='VAELoader':vals['vae_name']='minimax_h3_audio_vae_fp32.safetensors' if 'audio' in vals.get('vae_name','') else 'minimax_h3_video_vae_fp16.safetensors'
        if kind=='LoraLoaderModelOnly':vals['lora_name']=LORA
        for inp in n.get('inputs',[]):
            name=inp['name'];link=inp.get('link')
            if name in override:continue
            # All unrelated sample identities are replaced by one common still.
            if (name.startswith('ref_images.ref_image_') or name.startswith('images.image_')) and not name.endswith('_0'):continue
            if link:
                l=self.links[link];vals[name]=self.resolve(l[1],l[2])
        vals.update(override);vals={k:v for k,v in vals.items() if v is not None and k not in ('upload','videopreview','audiopreview','control_after_generate','choose video to upload','choose audio to upload')}
        add(self.g,ident,kind,**vals)
        return [str(ident),slot]

def postprocess(index,shot,video,attention='comfy kitchen attention'):
    context=index==2
    pattern='*Ctxt*json' if context else '*v18.json'
    path=next((SOURCES/'MBEDIT').glob(pattern))
    width,height=(1920,1088) if context else (1504,832)
    prompt=PROMPTS[shot].replace("<Picture 2> is the previous shot's final frame; continue the location and the heroine's position from it.","Preserve the location and the heroine's position from the input video.").replace("<Picture 2> is the previous shot's final frame.","Preserve the starting composition and motion from the input video.")
    overrides={631:{'attention':attention},630:{'noise_seed':731429+shot*7919},
               642:{'images':['900',0],'resize_type':'target dimensions','resize_type.scale':None,'resize_type.width':width,'resize_type.height':height},
               603:{'samples':None},
               678 if context else 609:{'width':width,'height':height,'length':243,'prompts' if context else 'prompt':prompt},
               641:{'value':prompt}}
    if not context:
        overrides[612]={'lora_name':'minimax_h3_ref2v_lightx2v_turbo_4step_v0.1_resized_avg_rank_20_bf16.safetensors'}
    # Use an exact target resize following NVIDIA's learned super-resolution.
    overrides[686 if context else 643]={'pixels':['903',0]}
    if context:
        overrides[687]={'audio_latent':None}
    else:
        overrides[645]={'audio_latent':['905',1]}
    adapter=Adapter(path,overrides)
    source=673 if context else 623
    adapter.resolve(source)
    g=adapter.g
    encode=g[str(686 if context else 643)]
    encode['class_type']='VAEEncodeTiled'
    encode['inputs'].update(tile_size=512,overlap=64,temporal_size=64,temporal_overlap=8)
    add(g,898,'LoadVideo',file=video)
    add(g,900,'GetVideoComponents',video=['898',0])
    add(g,903,'ImageScale',image=['642',0],upscale_method='lanczos',width=width,height=height,crop='disabled')
    if not context:add(g,905,'LTXVSeparateAVLatent',av_latent=['609',1])
    # RTX must be visited explicitly because the encode link is overridden.
    adapter.resolve(642)
    add(g,906,'VAEDecodeTiled',samples=[str(source),0],vae=['599',0],tile_size=512,overlap=64,temporal_size=32,temporal_overlap=8)
    video_output(g,908,['906',0],f'h3-comparison/{index:02d}_MBEDIT_{"Context" if context else "Pixel"}/shot{shot+1}')
    return g

def chain(index):
    full=index==6
    p=SOURCES/'Seamless-Chain/workflows'/('H3_Seamless_Chain_v2.json' if full else 'H3_Seamless_Chain_CORE.json')
    w=json.loads(p.read_text(encoding='utf-8'))
    kind='H3MultishotMemorySampler' if full else 'H3MultishotSampler'
    n=next(n for n in w['nodes'] if n['type']==kind)
    values=widgets(n)
    g={}
    add(g,1,'LoadImage',image=REF)
    add(g,2,'H3ModelLoaderAny',model_name=MODEL,activation_reserve_gb=3.)
    add(g,3,'H3ClipLoaderAny',clip_name='qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors',type='minimax')
    add(g,4,'VAELoader',vae_name='minimax_h3_video_vae_fp16.safetensors')
    add(g,5,'VAELoader',vae_name='minimax_h3_audio_vae_fp32.safetensors')
    add(g,9,'ModelAttentionBackend',model=['2',0],attention='comfy kitchen attention')
    values.update(model=['2',0],clip=['3',0],video_vae=['4',0],audio_vae=['5',0],script='\n---\n'.join(PROMPTS),shot_count=3,width=1344,height=768,frames_per_shot=243,seed=731429,steps=20 if full else 14,seed_per_shot=True,start_image=['1',0],reference_images=['1',0],preview_first_shot=False,self_anchor_voice=False,save_every_shot=True)
    if not full:values.pop('preview_first_shot',None)
    # context_pin removes 22 regenerated overlap frames at each join. A 260f
    # source window yields 736 output frames (~30.67s) across three shots.
    if full:values['frames_per_shot']=260
    if full:
        # Picture 2 is the fixed start-image identity anchor in this node,
        # while the preceding scene is carried as latent context, not Picture 2.
        values['script']=values['script'].replace("<Picture 2> is the previous shot's final frame; continue the location and the heroine's position from it.","Continue the location and the heroine's position from the context carried from the preceding shot.").replace("<Picture 2> is the previous shot's final frame.","Continue from the context carried from the preceding shot.")
    values['model']=['9',0]
    add(g,6,kind,**values)
    video_output(g,8,['6',0],f'h3-comparison/{index:02d}_Chain_{"Full" if full else "Core"}/full_30s')
    return g

def keyframes(shot=0,previous=None):
    g={}
    add(g,1,'LoadImage',image=previous or REF)
    add(g,2,'H3ModelLoaderAny',model_name='minimax_h3_fl2va_pruned_fp8_scaled.safetensors',activation_reserve_gb=3.)
    add(g,3,'H3ClipLoaderAny',clip_name='qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors',type='minimax')
    add(g,4,'VAELoader',vae_name='minimax_h3_video_vae_fp16.safetensors')
    add(g,5,'ImageScale',image=['1',0],upscale_method='lanczos',width=1344,height=768,crop='disabled')
    # Native FL conditioning takes the only available frame as its first anchor.
    prompt=PROMPTS[shot].replace('<Picture 1>','The first frame').replace('<Picture 2>','The first frame')
    add(g,6,'H3Keyframes',clip=['3',0],vae=['4',0],prompt=prompt,width=1344,height=768,length=243,positions='0%',image_1=['5',0])
    add(g,16,'ModelAttentionBackend',model=['2',0],attention='comfy kitchen attention')
    add(g,7,'BasicGuider',model=['16',0],conditioning=['6',0])
    add(g,8,'RandomNoise',noise_seed=731429+shot*7919)
    add(g,9,'KSamplerSelect',sampler_name='res_multistep')
    add(g,10,'BasicScheduler',model=['16',0],scheduler='simple',steps=20,denoise=1.)
    add(g,11,'SamplerCustomAdvanced',noise=['8',0],guider=['7',0],sampler=['9',0],sigmas=['10',0],latent_image=['6',1])
    add(g,12,'LTXVSeparateAVLatent',av_latent=['11',0])
    add(g,13,'VAEDecodeTiled',samples=['12',0],vae=['4',0],tile_size=512,overlap=64,temporal_size=32,temporal_overlap=8)
    video_output(g,15,['13',0],f'h3-comparison/04_Keyframes/shot{shot+1}')
    return g

if __name__=='__main__':
    for i in (5,6):save(f'{i:02d}_Chain',chain(i))
    save('04_Keyframes_shot1',keyframes())
    for i in (2,3):
        save(f'{i:02d}_Post_shot1',postprocess(i,0,'benchmark_baseline_shot1.mp4'))
    print('Community adaptations saved')
