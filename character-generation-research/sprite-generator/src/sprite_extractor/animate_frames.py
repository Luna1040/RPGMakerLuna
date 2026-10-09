"""Encode extracted frame cycles as exact-duration animated WebP files."""
from __future__ import annotations
import argparse,json
from pathlib import Path
from .io_utils import atomic_write_json

def _exports(path:Path):
    if (path/"summary.json").is_file(): return [path]
    batch=path/"batch-summary.json"
    if not batch.is_file(): raise ValueError("input must be an extraction directory or batch root")
    raw=json.loads(batch.read_text()); exports=[]
    for record in raw.get("results",[]):
        if record.get("status")!="exported": continue
        target=Path(record["output"]); target=target if target.is_absolute() else path/target
        exports.append(target.resolve())
    if not exports: raise ValueError("batch contains no exported sequences")
    return exports

def encode(root:Path,height:int)->dict:
    from PIL import Image
    summary=json.loads((root/"summary.json").read_text()); records=summary["six_frame_cycle"]["frames"]
    frame_count=len(records)
    if frame_count<2: raise ValueError(f"{root} contains fewer than two selected frames")
    period=float(summary["period"]["seconds"]); total_ms=round(period*1000)
    if total_ms<frame_count: raise ValueError("estimated cycle is too short for positive millisecond holds")
    bounds=[round(i*total_ms/frame_count) for i in range(frame_count+1)]; durations=[b-a for a,b in zip(bounds,bounds[1:])]
    if any(value<=0 for value in durations) or sum(durations)!=total_ms: raise ValueError("could not represent cycle duration exactly")
    output=root/f"cycle-{height}h.webp"; metadata=root/f"cycle-{height}h.json"
    if output.exists() or metadata.exists(): raise FileExistsError(f"animation output already exists in {root}")
    images=[]; source_paths=[]; size=None
    for record in records:
        source=(root/record["path"]).resolve()
        if root.resolve() not in source.parents: raise ValueError("selected frame path escapes extraction directory")
        with Image.open(source) as image:
            width=max(1,round(image.width*height/image.height)); resized=image.convert("RGBA").resize((width,height),Image.Resampling.LANCZOS)
        if size is None: size=resized.size
        elif resized.size!=size: raise ValueError("selected source frames do not share one aspect ratio")
        images.append(resized); source_paths.append(str(source.relative_to(root.resolve())))
    temporary=output.with_name(output.name+".working")
    images[0].save(temporary,format="WEBP",save_all=True,append_images=images[1:],duration=durations,loop=0,lossless=True,method=6,exact=True)
    temporary.replace(output)
    result={"version":"1.0","animation":output.name,"height":height,"width":size[0],"frame_count":frame_count,"loop":"forever","estimated_cycle_seconds":period,"encoded_cycle_ms":total_ms,"frame_durations_ms":durations,"source_frames":source_paths,"encoding":{"format":"WebP","lossless":True,"method":6,"exact_transparent_rgb":True}}
    atomic_write_json(metadata,result); return {"directory":str(root),**result}

def main(argv=None):
    parser=argparse.ArgumentParser(); parser.add_argument("input"); parser.add_argument("--height",type=int,default=128); args=parser.parse_args(argv)
    if args.height<=0: parser.error("--height must be positive")
    roots=_exports(Path(args.input).resolve()); results=[]; failed=[]
    for root in roots:
        try:
            result=encode(root,args.height); results.append(result); print(f"encoded {root/result['animation']}",flush=True)
        except Exception as error: failed.append({"directory":str(root),"error":f"{type(error).__name__}: {error}"}); print(f"failed {root}: {error}",flush=True)
    print(json.dumps({"encoded":len(results),"failed":len(failed),"results":results,"failures":failed},indent=2))
    return 1 if failed else 0

if __name__=="__main__": raise SystemExit(main())
