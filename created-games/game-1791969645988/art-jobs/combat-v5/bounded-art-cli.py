import sys,runpy,onnxruntime as ort
from pathlib import Path
actual=ort.InferenceSession
def bounded(*args,**kwargs):
 options=ort.SessionOptions();options.intra_op_num_threads=4;options.inter_op_num_threads=1
 kwargs['sess_options']=options
 return actual(*args,**kwargs)
ort.InferenceSession=bounded
sys.argv=[r'Z:\RPGMakerLuna\godot-ai-workbench\art_cli.py',*sys.argv[1:]]
runpy.run_path(sys.argv[0],run_name='__main__')
