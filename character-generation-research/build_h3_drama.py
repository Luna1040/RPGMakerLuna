"""Three directed ten-second H3 shots, with frame continuity and final assembly."""
from pathlib import Path
import json
import uuid
import build_guofeng_workflows as base
import build_h3_opening as opening

DEST = base.ROOT / 'guofeng-drama'
SAVED = base.CORE / 'user/default/workflows/古风开场_三镜头30秒'
COMMON = '''Chinese wuxia film opening, adult characters, cinematic live action. <Picture 1> defines the heroine's face, hair, ivory and pale-blue hanfu and the ancient pavilion in a bamboo grove. Keep her identity and costume consistent. Animate full body actions with clear intent, weight, foot placement and readable gestures. Real spatial movement, not a still portrait with moving hair. One continuous shot with the camera movement specified below. No internal cuts, captions, logos, modern objects or extra limbs. Silent video.'''
PROMPTS = [
    COMMON + '''
SHOT 1 — ARRIVAL, about ten seconds. Begin exactly from the supplied first frame. In the first third the heroine turns her head sharply toward a sound outside the pavilion, turns her shoulders and steps forward. During the middle third she walks purposefully out of the pavilion and down the bamboo path, her sleeves trailing behind her steps. During the final third she slows and stops as she notices someone ahead, lifting her gaze with an alert expression. Camera: a smooth lateral tracking move follows her at medium-full-body distance, revealing the path ahead and settling into an over-the-shoulder composition. Keep the walking readable. End with room ahead of her for an approaching rival.''',
    COMMON + '''
SHOT 2 — ENCOUNTER. <Picture 2> is the previous shot's final frame; continue the location and the heroine's position from it. Over about ten seconds: an adult swordsman in dark charcoal hanfu enters the path ahead and stops three paces from the heroine, blocking her way. She takes a decisive step toward him and raises an open hand to challenge him; he reaches for his sword. She lowers her hand and draws a slender straight sword from her waist; he draws his sword in response. Finish with both opponents in clearly separated fighting stances, facing one another. Camera: a slow thirty-degree arc from behind the heroine to a side-on medium-wide two-shot, keeping both people's bodies and swords visible. Show their approach, confrontation and change into fighting stances, not just facial reactions. Exactly two people.''',
    COMMON + '''
SHOT 3 — FIRST CLASH. <Picture 2> is the previous shot's final frame. Continue the same heroine and dark-robed adult rival, their swords, positions and bamboo path. A readable short wuxia exchange over about ten seconds: first the rival steps forward and delivers one diagonal sword strike; the heroine steps sideways and raises her blade to parry, the blades visibly meeting once. Then she pivots on her planted foot and makes a single controlled horizontal counterstrike; he steps back and blocks it. Finally they disengage by one step and hold opposing guard stances, leaving a tense ending for a title added later. Camera: a controlled low lateral tracking move during the exchange, then gently pull back to a wider view at the end. Full bodies and blade paths remain visible. Grounded footwork, fast decisive actions separated by short readable pauses; no flying, no spinning camera, no gore. Exactly two people.'''
]

def graph(fast):
    merged = {}
    for shot, prompt in enumerate(PROMPTS):
        offset = shot * 100
        g = opening.make(fast)
        g['6']['inputs'].update(prompt=prompt, length=243)
        if not fast:
            # Keep the original image as the identity reference. The scaled image
            # is only the first-frame guide and canvas-size source.
            g['20']['inputs']['megapixels'] = 1.05
            g['6']['inputs']['ref_image_size'] = 'max'
            g['6']['inputs']['ref_images.ref_image_0'] = ['1', 0]
        g['8']['inputs']['noise_seed'] = 731429 + shot * 7919
        g['14']['inputs']['filename_prefix'] = f'guofeng-drama/{"preview" if fast else "quality"}/shot{shot+1}'
        if shot:
            base.node(g, 23, 'ImageFromBatch', image=['12', 0], batch_index=-1, length=1)
            g['22']['inputs']['image'] = ['23', 0]
            g['6']['inputs']['ref_images.ref_image_1'] = ['23', 0]
        for key, item in g.items():
            if shot and key in ('1', '2', '3', '4', '5', '20', '21'):
                continue
            values = {}
            for name, value in item['inputs'].items():
                if isinstance(value, list):
                    source = int(value[0])
                    shared = source in (1, 2, 3, 4, 5, 20, 21)
                    value = [str(source if shared else source + offset), value[1]]
                values[name] = value
            merged[str(int(key) + offset)] = {'class_type': item['class_type'], 'inputs': values}
        if shot:
            merged[str(offset + 23)]['inputs']['image'] = [str(offset - 100 + 12), 0]
    base.node(merged, 350, 'ConcatenateVideo', codec='h264', **{f'videos.video{i}':[str(i*100+13), 0] for i in range(3)})
    base.node(merged, 351, 'SaveVideo', video=['350', 0], filename_prefix=f'guofeng-drama/{"preview" if fast else "quality"}/full_30s', format='mp4', **{'format.codec':'h264'})
    return merged

def workflow(g):
    nodes, links = [], []
    for key, item in g.items():
        ident, kind, values = int(key), item['class_type'], item['inputs']
        schema = base.SCHEMA[kind]
        inputs, widgets, named = [], [], {}
        for name, spec in {**schema['input'].get('required', {}), **schema['input'].get('optional', {})}.items():
            typ = spec[0]
            if typ == 'COMFY_AUTOGROW_V3':
                template = spec[1]['template']['input']['required']
                subtype = next(iter(template.values()))[0]
                for field in values:
                    if field.startswith(name + '.'):
                        inputs.append({'name':field, 'type':subtype, 'link':None, 'shape':7})
                continue
            if name not in values:
                if typ not in ('INT','FLOAT','BOOLEAN','STRING','COMBO','COMFY_DYNAMICCOMBO_V3') and isinstance(typ,str):
                    inputs.append({'name':name,'type':typ,'link':None})
                continue
            value = values[name]
            if isinstance(value,list):
                inp = {'name':name,'type':typ,'link':None}
                if typ in ('INT','FLOAT','STRING','BOOLEAN'):
                    inp['widget'] = {'name':name}
                    widgets.append(spec[1].get('default', 0))
                inputs.append(inp)
            else:
                widgets.append(value)
                named[name] = value
                if len(spec)>1 and isinstance(spec[1],dict) and spec[1].get('control_after_generate'):
                    widgets.append('fixed')
        if kind == 'LoadImage':
            widgets.append('image')
        if kind == 'SaveVideo':
            widgets = [values['filename_prefix'],'mp4','h264']
        local, shot = ident % 100, ident // 100
        positions = {1:(0,0),2:(0,430),3:(0,700),4:(0,960),5:(400,700),20:(400,0),21:(400,340),
                     6:(900,0),22:(1450,0),7:(1850,0),8:(1850,280),9:(1850,540),10:(1850,790),
                     11:(2250,0),12:(2650,0),13:(3050,0),14:(3450,0),23:(900,730)}
        x,y = positions.get(local,(3900,0))
        pos = [x, y + shot*1250] if ident < 300 else [4000+(ident-350)*450,1100]
        title = kind
        if local == 6:
            title = f'镜头{shot+1}：' + ['出场／侧向跟拍','相遇对峙／弧形运镜','交手／低机位横移拉远'][shot] + '（243帧≈10秒）'
        elif ident == 1: title = '只替换这里：你的开场原图（当前为测试女侠）'
        elif ident == 20: title = '生成画幅：预览0.33MP／画质修正1.05MP'
        elif local == 23: title = '上一镜头末帧：自动传递场景和姿态'
        elif local == 22: title = '首帧衔接：上一镜头末帧／原图'
        elif ident == 350: title = '按顺序拼接三个镜头'
        elif ident == 351: title = '完整约30秒成片'
        elif local == 14: title = f'镜头{shot+1}单独输出（可逐段审片）'
        outputs = [{'name':n,'type':t,'links':[]} for n,t in zip(schema['output_name'],schema['output'])]
        nodes.append({'id':ident,'type':kind,'pos':pos,'size':[500 if local==6 else 350,650 if local in (6,14) else 260],
                      'flags':{},'order':len(nodes),'mode':0,'inputs':inputs,'outputs':outputs,'title':title,
                      'properties':{'cnr_id':'comfy-core','ver':'0.39.0','Node name for S&R':kind},'widgets_values':widgets,'widgets_values_named':named})
    by_id = {n['id']:n for n in nodes}
    for key,item in g.items():
        for name,value in item['inputs'].items():
            if not isinstance(value,list): continue
            src,slot = int(value[0]),value[1]
            target = by_id[int(key)]
            target_slot = next(i for i,v in enumerate(target['inputs']) if v['name']==name)
            lid = len(links)+1
            target['inputs'][target_slot]['link']=lid
            by_id[src]['outputs'][slot]['links'].append(lid)
            links.append([lid,src,slot,int(key),target_slot,by_id[src]['outputs'][slot]['type']])
    groups = [{'title':f'镜头{i+1} · {label} · 约10秒','bounding':[850,i*1250-70,3000,1200],'color':'#365d79','font_size':28,'flags':{}} for i,label in enumerate(['出场','相遇与拔剑','交手'])]
    return {'id':str(uuid.uuid4()),'revision':0,'last_node_id':max(by_id),'last_link_id':len(links),'nodes':nodes,'links':links,'groups':groups,'config':{},'extra':{'ds':{'scale':0.28,'offset':[120,120]}},'version':0.4}

if __name__ == '__main__':
    DEST.mkdir(exist_ok=True)
    SAVED.mkdir(parents=True,exist_ok=True)
    for fast,name in [(True,'01_三镜头30秒_演出预览'),(False,'02_三镜头30秒_精细生成')]:
        g=graph(fast)
        (DEST/(name+'.api.json')).write_text(json.dumps(g,ensure_ascii=False,indent=2),encoding='utf-8')
        payload=json.dumps(workflow(g),ensure_ascii=False,indent=2)
        (DEST/(name+'.json')).write_text(payload,encoding='utf-8')
        (SAVED/(name+'.json')).write_text(payload,encoding='utf-8')
    print(DEST)
