"""Invoke the unchanged artCli/matte tool using a workspace-local DirectML provider."""
import sys,runpy,os
from pathlib import Path
root=Path(__file__).resolve().parent
sys.path.insert(0,str(root/'dml-runtime'))
os.add_dll_directory(str(root/'dml-runtime/onnxruntime/capi'))
import onnxruntime as ort
original=ort.InferenceSession
def accelerated(*args,**kwargs):
    options=ort.SessionOptions()
    options.enable_mem_pattern=False
    options.execution_mode=ort.ExecutionMode.ORT_SEQUENTIAL
    options.intra_op_num_threads=2
    options.inter_op_num_threads=1
    kwargs['sess_options']=options
    kwargs['providers']=['DmlExecutionProvider','CPUExecutionProvider']
    print('ONNX providers:',ort.get_available_providers(),flush=True)
    return original(*args,**kwargs)
ort.InferenceSession=accelerated
sys.argv[0]=r'Z:\RPGMakerLuna\godot-ai-workbench\art_cli.py'
runpy.run_path(sys.argv[0],run_name='__main__')
