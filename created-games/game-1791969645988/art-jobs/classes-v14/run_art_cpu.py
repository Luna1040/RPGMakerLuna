"""Run the unchanged artCli with bounded ONNX CPU threads for this workspace."""
import sys, runpy
import onnxruntime as ort
original=ort.InferenceSession
def bounded(*args, **kwargs):
    options=ort.SessionOptions()
    options.intra_op_num_threads=2
    options.inter_op_num_threads=1
    kwargs['sess_options']=options
    return original(*args, **kwargs)
ort.InferenceSession=bounded
sys.argv[0]=r'Z:\RPGMakerLuna\godot-ai-workbench\art_cli.py'
runpy.run_path(sys.argv[0],run_name='__main__')
