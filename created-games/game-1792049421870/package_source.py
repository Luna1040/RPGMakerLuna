"""Build a complete portable source ZIP after validation, without private data/caches."""
from pathlib import Path
import argparse,hashlib,zipfile
p=argparse.ArgumentParser();p.add_argument("--output",type=Path);args=p.parse_args()
root=Path(__file__).resolve().parent;out=(args.output or root.parent/(root.name+"-source.zip")).resolve()
if root == out or root in out.parents:raise SystemExit("Output ZIP must be outside the project directory")
skip={".godot",".git","art-jobs","__pycache__",".game-assistant",".team-comfy-private"}
with zipfile.ZipFile(out,"w",zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for f in sorted(root.rglob("*")):
  rel=f.relative_to(root)
  if not f.is_file() or f.is_symlink() or skip.intersection(rel.parts) or f.suffix in {".log",".pyc"} or f.name==".DS_Store":continue
  data=f.read_bytes()
  if data.startswith(b"version https://git-lfs.github.com/spec/v1"):raise RuntimeError("LFS pointer: "+str(rel))
  info=zipfile.ZipInfo(root.name+"/"+rel.as_posix(),date_time=(2026,10,16,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o100644<<16
  z.writestr(info,data,compress_type=zipfile.ZIP_DEFLATED,compresslevel=9)
print(out);print(hashlib.sha256(out.read_bytes()).hexdigest())
