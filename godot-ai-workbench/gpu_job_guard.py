"""Cross-process GPU lease for the two managed ComfyUI workers."""
import contextlib
import gc
import logging
import os
from pathlib import Path
import time
import json
import uuid

@contextlib.contextmanager
def gpu_lease(path, waiting_callback=None):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+b") as handle:
        handle.seek(0, 2)
        if handle.tell() == 0:
            handle.write(b"0")
            handle.flush()
        waiting = False
        while True:
            try:
                handle.seek(0)
                if os.name == "nt":
                    import msvcrt
                    msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except (OSError, BlockingIOError):
                if not waiting:
                    logging.warning("[GPU] Waiting for other image/video task to release VRAM")
                    waiting = True
                if waiting_callback: waiting_callback()
                time.sleep(0.25)
        try:
            yield
        finally:
            handle.seek(0)
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl
                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)

STATE = Path(__file__).resolve().parents[1] / ".game-assistant/gpu-scheduler"
SESSION = str(os.getpid()) + "-" + uuid.uuid4().hex
last_used = time.monotonic()
has_models = False

def read_owner():
    try:
        return json.loads((STATE / "owner.json").read_text())
    except FileNotFoundError:
        return {}

def write_owner(value):
    STATE.mkdir(parents=True, exist_ok=True)
    temp = STATE / (SESSION + ".tmp")
    temp.write_text(json.dumps(value))
    os.replace(temp, STATE / "owner.json")

def alive(pid):
    if os.name == "nt":
        import ctypes
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.OpenProcess.restype = ctypes.c_void_p
        kernel.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        kernel.CloseHandle.argtypes = [ctypes.c_void_p]
        handle = kernel.OpenProcess(0x100000, False, pid)
        if not handle:
            if ctypes.get_last_error() == 87: return False
            raise RuntimeError("Cannot verify previous GPU owner process")
        try: return kernel.WaitForSingleObject(handle, 0) == 258
        finally: kernel.CloseHandle(handle)
    try: os.kill(pid, 0); return True
    except ProcessLookupError: return False

def maintain(executor):
    global has_models
    request = STATE / (SESSION + ".release")
    idle_seconds = float(os.environ.get("GAME_GPU_IDLE_SECONDS", "600"))
    requested = request.exists()
    if not requested and (not has_models or idle_seconds <= 0 or time.monotonic()-last_used < idle_seconds):
        return
    import execution
    import comfy.model_management as memory
    memory.unload_all_models()
    executor.caches = execution.CacheSet(cache_type=executor.cache_type, cache_args=executor.cache_args)
    gc.collect()
    memory.soft_empty_cache()
    has_models = False
    # This worker is between prompts. Waiting peers cannot execute until this acknowledgement.
    if read_owner().get("session") == SESSION: write_owner({})
    request.unlink(missing_ok=True)
    logging.info("[GPU] Released model/cache memory (%s)", "service switch" if requested else "idle timeout")

def execute_guarded(executor, *args):
    global has_models, last_used
    with gpu_lease(STATE / "execution.lock", lambda: maintain(executor)):
        owner = read_owner()
        if owner and owner.get("session") != SESSION:
            if alive(int(owner["pid"])):
                request = STATE / (owner["session"] + ".release")
                request.touch()
                logging.info("[GPU] Waiting for previous service to unload models")
                deadline = time.monotonic()+120
                while read_owner().get("session") == owner["session"]:
                    if not alive(int(owner["pid"])): break
                    if time.monotonic()>deadline:
                        raise RuntimeError("Previous service did not acknowledge GPU release; refusing concurrent model load")
                    time.sleep(.1)
            write_owner({})
        write_owner({"pid":os.getpid(), "session":SESSION})
        has_models = True
        logging.info("[GPU] Exclusive prompt execution; keeping models for same-service reuse")
        try:
            return executor.execute(*args)
        finally:
            last_used = time.monotonic()

def run_comfy(main):
    main = Path(main)
    source = main.read_text(encoding="utf-8")
    replacements = {
        "e.execute(item[2], prompt_id, extra_data, item[4])": "__import__('gpu_job_guard').execute_guarded(e, item[2], prompt_id, extra_data, item[4])",
        "queue_item = q.get(timeout=timeout)": "__import__('gpu_job_guard').maintain(e)\n            queue_item = q.get(timeout=min(timeout, 1.0))",
    }
    for needle, replacement in replacements.items():
        if source.count(needle) != 1:
            raise RuntimeError("Unsupported ComfyUI worker: GPU guard requires review")
        source = source.replace(needle, replacement)
    logging.warning("[GPU] Image/video serialization enabled; cache retained; idle unload %s seconds", os.environ.get("GAME_GPU_IDLE_SECONDS", "600"))
    exec(compile(source, str(main), "exec"), {"__name__":"__main__", "__file__":str(main), "__package__":None})
