"""Six complete importable canvases, with shared loaders and per-shot outputs."""
from pathlib import Path
import sys,json
sys.path.insert(0,str(Path(__file__).resolve().parent))
from build_h3_comparison import DEST,SCHEMA,base,mbedit,add
from adapt_community_workflows import postprocess,keyframes,chain
from export_h3_comparison_ui import canvas

SCHEMA['H3ComparisonConcatFiles']={'input':{'required':{
    'clip1':['VHS_FILENAMES'],'clip2':['VHS_FILENAMES'],'clip3':['VHS_FILENAMES'],
    'filename_prefix':['STRING',{'default':'h3-comparison/full_30s'}],
    'update_benchmark_inputs':['BOOLEAN',{'default':False}]}},'output':['STRING'],'output_name':['video_path']}

NAMES={1:'01_MBEDIT_双阶段_三镜头30秒',2:'02_MBEDIT_分窗重绘_三镜头30秒',3:'03_MBEDIT_整段重绘_三镜头30秒',4:'04_H3原生关键帧_三镜头30秒',5:'05_Seamless_CORE_三镜头30秒',6:'06_Seamless_ContextPin_三镜头30秒'}

def complete(index):
    if index in (5,6):return chain(index)
    shared=({1,2,3,4,5,6,7,12,13,19} if index==1 else
            {2,3,4,9,10,16} if index==4 else
            {593,595,599,600,612,631,632,608,622,597,703,598,667})
    merged={};outputs=[]
    for shot in range(3):
        if index==1:g=mbedit(shot,f'benchmark_01_last{shot}.png' if shot else None);output=24
        elif index==4:g=keyframes(shot,f'benchmark_04_last{shot}.png' if shot else None);output=15
        else:g=postprocess(index,shot,f'benchmark_baseline_shot{shot+1}.mp4');output=908
        offset=shot*1000
        for key,item in g.items():
            ident=int(key)
            if shot and ident in shared:continue
            values={}
            for name,value in item['inputs'].items():
                if isinstance(value,list):
                    source=int(value[0]);value=[str(source if source in shared else source+offset),value[1]]
                values[name]=value
            merged[str(ident+offset)]={'class_type':item['class_type'],'inputs':values}
        if shot and index in (1,4):
            ident=offset+(30 if index==1 else 1)
            previous=(shot-1)*1000+(22 if index==1 else 13)
            merged[str(ident)]={'class_type':'ImageFromBatch','inputs':{'image':[str(previous),0],'batch_index':-1,'length':1}}
        outputs.append([str(offset+output),0])
    add(merged,9010,'H3ComparisonConcatFiles',clip1=outputs[0],clip2=outputs[1],clip3=outputs[2],filename_prefix=f'h3-comparison/{index:02d}_Complete/full_30s',update_benchmark_inputs=index==1)
    return merged

if __name__=='__main__':
    dest=DEST/'complete-workflows';dest.mkdir(exist_ok=True)
    saved=base.CORE/'user/default/workflows/古风开场_六套完整工作流';saved.mkdir(parents=True,exist_ok=True)
    for index,name in NAMES.items():
        graph=complete(index)
        (dest/(name+'.api.json')).write_text(json.dumps(graph,ensure_ascii=False,indent=2),encoding='utf-8')
        workflow=canvas(graph)
        for n in workflow['nodes']:
            if n['id']==9010:n['title']='拼成完整约30秒视频；01会更新后续重绘输入'
            elif n['type'] in ('MiniMaxH3ReferenceToVideo','H3Keyframes','MMH3ReferenceMultiPrompt'):
                n['title']=f'镜头{n["id"]//1000+1}：'+['出场','会面拔剑','交手'][n['id']//1000]
        if index <= 4:
            groups=[]
            for shot,label in enumerate(('01 出场与跟拍','02 会面与拔剑','03 交手与收势')):
                members=[n for n in workflow['nodes'] if n['id'] != 9010 and n['id']//1000 == shot]
                x=shot*2250
                for j,n in enumerate(members):
                    n['pos']=[x+(j%5)*430,100+(j//5)*550]
                height=((len(members)+4)//5)*550+100
                groups.append({'title':label,'bounding':[x-30,30,2170,height],
                               'color':['#365340','#374a61','#624b36'][shot],'font_size':28,'flags':{}})
            end=next(n for n in workflow['nodes'] if n['id']==9010)
            end['pos']=[6820,150]
            end['size']=[500,330]
            workflow['groups']=groups
            workflow['extra']['ds']={'scale':0.18,'offset':[120,120]}
        else:
            for n in workflow['nodes']:
                if n['type'] in ('H3MultishotSampler','H3MultishotMemorySampler'):
                    n['size']=[620,1000]
        payload=json.dumps(workflow,ensure_ascii=False,indent=2)
        (dest/(name+'.json')).write_text(payload,encoding='utf-8');(saved/(name+'.json')).write_text(payload,encoding='utf-8')
    print(saved)
