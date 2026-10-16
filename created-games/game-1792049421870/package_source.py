from pathlib import Path
import hashlib,zipfile
root=Path(__file__).resolve().parent
out=root.parent/(root.name+"-source.zip")
with zipfile.ZipFile(out,"w",zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for p in sorted(root.rglob("*")):
  rel=p.relative_to(root)
  if not p.is_file() or p.is_symlink() or any(x in {".godot",".git","art-jobs","__pycache__"} for x in rel.parts) or p.suffix in {".log",".pyc"} or p.name==".DS_Store":continue
  z.write(p,root.name+"/"+rel.as_posix())
print(out)
print(hashlib.sha256(out.read_bytes()).hexdigest())
