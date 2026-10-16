"""Verify merged graph references and exercise the exact file-mux node."""
from pathlib import Path
import sys,json,importlib.util
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT))
from build_h3_complete_workflows import complete,SCHEMA
for index in range(1,7):
    graph=complete(index)
    for item in graph.values():
        assert item['class_type'] in SCHEMA,item['class_type']
        for value in item['inputs'].values():
            if isinstance(value,list):
                assert value[0] in graph,value
                source=graph[value[0]]['class_type']
                assert value[1]<len(SCHEMA[source]['output']),value
    print('COMPLETE_GRAPH_LINKS_OK',index,len(graph))
CORE=next((ROOT/'h3-runtime').glob('ComfyUI-*'));sys.path.insert(0,str(CORE))
import folder_paths
folder_paths.set_output_directory(str(ROOT/'h3-comparison/qa'))
source=ROOT/'h3-community-nodes/ComfyUI-H3-ComparisonIO/__init__.py'
spec=importlib.util.spec_from_file_location('h3_comparison_io_check',source)
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
clips=[]
for shot in range(1,4):
    done=json.loads((ROOT/f'h3-comparison/01_MBEDIT_Latent_shot{shot}.done.json').read_text(encoding='utf-8'))
    clips.append((True,[done['video']]))
result=module.H3ComparisonConcatFiles().join(*clips,'concat-check/master',False)
assert result['ui']['images'][0]['metadata']['frame_count']==729,result
print('EXTERNAL_MUX_VERIFIED',result['result'][0])
