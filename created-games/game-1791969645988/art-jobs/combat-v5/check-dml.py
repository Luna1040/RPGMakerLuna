import sys,time
sys.path.insert(0,r'Z:\RPGMakerLuna\created-games\game-1791969645988\art-jobs\combat-v5\dml-deps')
import onnxruntime as ort,numpy as np
print('PROVIDERS',ort.get_available_providers(),flush=True)
s=ort.SessionOptions();s.enable_mem_pattern=False;s.execution_mode=ort.ExecutionMode.ORT_SEQUENTIAL
start=time.time()
model=ort.InferenceSession(r'Z:\RPGMakerLuna\created-games\game-1791969645988\art-jobs\combat-v5\birefnet-lite.onnx',sess_options=s,providers=['DmlExecutionProvider'])
print('ACTIVE',model.get_providers(),'INPUT',model.get_inputs()[0].shape,'LOAD',time.time()-start,flush=True)
if model.get_providers()[0]!='DmlExecutionProvider': raise RuntimeError('DirectML unavailable; refusing silent CPU fallback')
start=time.time();y=model.run(None,{model.get_inputs()[0].name:np.zeros((1,3,1024,1024),np.float32)})
print('INFERENCE_SECONDS',time.time()-start,flush=True)
