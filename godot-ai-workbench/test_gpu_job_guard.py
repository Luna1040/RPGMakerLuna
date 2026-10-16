import importlib.util, json, os, pathlib, subprocess, sys, tempfile, time, types
sys.path.insert(0,str(pathlib.Path(__file__).parent))
import gpu_job_guard as g
if len(sys.argv)>1:
    g.STATE=pathlib.Path(sys.argv[1]); name=sys.argv[2]
    class Executor:
        cache_type=0
        cache_args={}
        def execute(self):
            with (g.STATE/"trace").open("a") as f: f.write(name+" start\n")
            time.sleep(.15)
            with (g.STATE/"trace").open("a") as f: f.write(name+" end\n")
    def unload():
        with (g.STATE/"trace").open("a") as f: f.write(name+" unload\n")
    sys.modules['execution']=types.SimpleNamespace(CacheSet=lambda **kw: {})
    sys.modules['comfy']=types.ModuleType('comfy')
    sys.modules['comfy.model_management']=types.SimpleNamespace(unload_all_models=unload,soft_empty_cache=lambda:None)
    e=Executor()
    if name=='A':
        g.execute_guarded(e); g.execute_guarded(e)
        (g.STATE/'ready').touch()
        while not (g.STATE/'done').exists(): g.maintain(e); time.sleep(.02)
    else:
        g.execute_guarded(e)
        (g.STATE/'done').touch()
else:
    with tempfile.TemporaryDirectory() as folder:
        root=pathlib.Path(folder)
        a=subprocess.Popen([sys.executable,__file__,folder,'A'])
        try:
            deadline=time.monotonic()+10
            while not (root/'ready').exists():
                if time.monotonic()>deadline: raise RuntimeError('worker A timeout')
                time.sleep(.05)
            b=subprocess.Popen([sys.executable,__file__,folder,'B'])
            try:
                assert b.wait(timeout=15)==0
                assert a.wait(timeout=15)==0
            finally:
                if b.poll() is None: b.kill()
            trace=(root/'trace').read_text().splitlines()
            assert trace==['A start','A end','A start','A end','A unload','B start','B end'],trace
            print('PASS: same-service cache reused; switch unload acknowledged before next execution')
        finally:
            if a.poll() is None: a.kill()
