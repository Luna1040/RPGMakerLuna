"""Export editable ComfyUI canvases beside executable API graphs."""
import json,uuid,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from build_h3_comparison import DEST,SCHEMA,base

def canvas(g):
    nodes=[];links=[];lookup={}
    for order,(key,item) in enumerate(g.items()):
        kind=item['class_type'];values=item['inputs'];schema=SCHEMA.get(kind,{'input':{'required':{}},'output':['IMAGE'],'output_name':['images']})
        specs={**schema['input'].get('required',{}),**schema['input'].get('optional',{})}
        inputs=[];widgets=[];named={}
        for name,spec in specs.items():
            typ=spec[0];opts=spec[1] if len(spec)>1 and isinstance(spec[1],dict) else {}
            if typ=='COMFY_DYNAMICCOMBO_V3':
                selection=values.get(name,opts.get('default'))
                if selection is None:continue
                widgets.append(selection);named[name]=selection
                variant=next((v for v in opts['options'] if v['key']==selection),{})
                for sub,ss in variant.get('inputs',{}).get('required',{}).items():
                    field=name+'.'+sub
                    if field in values:widgets.append(values[field]);named[field]=values[field]
                continue
            if typ=='COMFY_AUTOGROW_V3':
                sub=next(iter(opts['template']['input']['required'].values()))[0]
                for field,v in values.items():
                    if field.startswith(name+'.'):inputs.append({'name':field,'type':sub,'link':None,'shape':7})
                continue
            v=values.get(name,opts.get('default'))
            is_widget=isinstance(typ,list) or typ in ('COMBO','STRING','INT','FLOAT','BOOLEAN')
            if is_widget and not opts.get('forceInput'):
                if v is None:continue
                widgets.append(opts.get('default',0) if isinstance(v,list) else v)
                if opts.get('control_after_generate'):widgets.append('fixed')
                if not isinstance(v,list):named[name]=v
            if isinstance(v,list) or not is_widget or opts.get('forceInput'):
                if name in values:
                    inp={'name':name,'type':typ if isinstance(typ,str) else 'COMBO','link':None}
                    if is_widget and not opts.get('forceInput'):inp['widget']={'name':name}
                    inputs.append(inp)
        # Any expanded or newly introduced linked input is kept explicitly.
        for name,v in values.items():
            if isinstance(v,list) and not any(x['name']==name for x in inputs):
                source=g[v[0]]['class_type'];outputs=SCHEMA.get(source,{}).get('output',['IMAGE'])
                inputs.append({'name':name,'type':outputs[v[1]],'link':None})
        if kind=='LoadImage':widgets.append('image')
        if kind=='VHS_VideoCombine':
            # VHS serializes format-dependent widgets as a name/value object.
            widgets={k:v for k,v in values.items() if not isinstance(v,list)}
            named=dict(widgets)
        outputs=[{'name':n,'type':t,'links':[]} for n,t in zip(schema.get('output_name',schema['output']),schema['output'])]
        n={'id':int(key),'type':kind,'pos':[(order%5)*420,(order//5)*530],'size':[380,460 if kind in ('H3MultishotSampler','H3MultishotMemorySampler','MiniMaxH3ReferenceToVideo') else 330],
           'flags':{},'order':order,'mode':0,'inputs':inputs,'outputs':outputs,'properties':{'Node name for S&R':kind},'widgets_values':widgets,'widgets_values_named':named}
        nodes.append(n);lookup[key]=n
    for key,item in g.items():
        for name,v in item['inputs'].items():
            if not isinstance(v,list):continue
            src,slot=v;target=lookup[key];ts=next(i for i,x in enumerate(target['inputs']) if x['name']==name)
            lid=len(links)+1;target['inputs'][ts]['link']=lid
            lookup[src]['outputs'][slot]['links'].append(lid)
            links.append([lid,int(src),slot,int(key),ts,lookup[src]['outputs'][slot]['type']])
    return {'id':str(uuid.uuid4()),'revision':0,'last_node_id':max(int(x) for x in g),'last_link_id':len(links),'nodes':nodes,'links':links,'groups':[], 'config':{},'extra':{'ds':{'scale':0.45,'offset':[100,100]}},'version':0.4}

if __name__=='__main__':
    saved=base.CORE/'user/default/workflows/古风开场_六工作流对比';saved.mkdir(parents=True,exist_ok=True)
    for p in DEST.glob('*.api.json'):
        g=json.loads(p.read_text(encoding='utf-8'));payload=json.dumps(canvas(g),ensure_ascii=False,indent=2)
        name=p.name.replace('.api.json','.json');(DEST/name).write_text(payload,encoding='utf-8');(saved/name).write_text(payload,encoding='utf-8')
    print(saved)
