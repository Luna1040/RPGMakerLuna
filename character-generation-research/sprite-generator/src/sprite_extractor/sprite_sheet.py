"""Remove backgrounds and pack selected four-view frames into a sprite sheet."""
from __future__ import annotations
import argparse,json,math,tempfile
from pathlib import Path
import numpy as np
from .comfy_postprocess import remove_background_masks
from .comfy_workflow import ComfyClient,configured_comfyui_url,configured_sprite_box_height
from .diagnose_cycle import _series,_identity_evidence,_robust_fit,_design
from .io_utils import atomic_write_json
from .sprite_split import ALPHA_NOISE_THRESHOLD,SPLIT_ALGORITHMS,scale_edges,shared_split_edges

class Remover:
    def __init__(self,server=None,config=None,timeout=7200.0,poll_interval=2.0):
        self.client=ComfyClient(server or configured_comfyui_url(config)); self.config=config; self.timeout=timeout; self.poll_interval=poll_interval; self.provenance={}
    def masks(self,arrays):
        from PIL import Image
        try:
            with tempfile.TemporaryDirectory(prefix="sprite-extractor-rembg-") as temporary:
                root=Path(temporary); sources=[]
                for index,array in enumerate(arrays):
                    path=root/f"input-{index:04d}.png"; Image.fromarray(np.clip(np.rint(array*255),0,255).astype(np.uint8),"RGB").save(path); sources.append(path)
                masks,self.provenance=remove_background_masks(self.client,sources,root/"masks",config_path=self.config,timeout=self.timeout,poll_interval=self.poll_interval)
                result=[]
                for path in masks:
                    with Image.open(path) as image: result.append(np.asarray(image.convert("L"),np.float32)/255.0)
        finally:
            self.client.free_if_idle()
        return np.stack(result)

def _premultiplied_resize(rgb,alpha,size):
    from PIL import Image
    a=alpha.astype(np.float32); prem=rgb.astype(np.float32)*255.0*a[...,None]
    channels=[np.asarray(Image.fromarray(channel,"F").resize(size,Image.Resampling.LANCZOS)) for channel in (*np.moveaxis(prem,2,0),a)]
    out_a=np.clip(channels[3],0,1); out=np.zeros((*out_a.shape,4),np.uint8); out[...,3]=np.rint(out_a*255).astype(np.uint8)
    valid=out_a>1e-6
    for i in range(3): out[...,i][valid]=np.clip(np.rint(channels[i][valid]/out_a[valid]),0,255).astype(np.uint8)
    return Image.fromarray(out,"RGBA")

def _ground(summary,raw):
    period=float(summary["period"]["seconds"]); phase=float(summary["right_ground_phase"]["phase"]); right=_series(raw,"right_ankle"); left=_series(raw,"left_ankle")
    right,_,_,_,issues,rejected=_identity_evidence(right,left,.35,.12,int(raw["crop"]["x1"])-int(raw["crop"]["x0"])); _,beta=_robust_fit(right,period)
    y=float((_design(np.array([phase*period]),period)@beta)[0]); return y,{"method":"saved-period-phase robust named-right-ankle waveform","excluded_identity_frames":len(rejected),"identity_issue_count":len(issues)}

def build(root:Path,height:int,directions,list_remover:Remover,split_algorithm:str="blobs"):
    from PIL import Image
    out=root/f"sprite-sheet-{height}h.png"; meta=root/f"sprite-sheet-{height}h.json"
    if out.exists() or meta.exists(): raise FileExistsError(f"sprite-sheet output exists in {root}")
    summary=json.loads((root/"summary.json").read_text()); raw=json.loads((root/"raw_pose.json").read_text()); records=summary["six_frame_cycle"]["frames"]
    frame_count=len(records)
    if frame_count<2: raise ValueError("sprite sheet requires at least two selected frames")
    sources=[]; arrays=[]
    for record in records:
        path=(root/record["path"]).resolve(); sources.append(path)
        if root.resolve() not in path.parents: raise ValueError("selected frame path escapes extraction directory")
        with Image.open(path) as image: arrays.append(np.asarray(image.convert("RGB"),np.float32)/255)
    if any(array.shape!=arrays[0].shape for array in arrays): raise ValueError("selected source frames do not share one size")
    masks=list_remover.masks(arrays); source_h,source_w=arrays[0].shape[:2]
    if masks.shape!=(frame_count,source_h,source_w): raise ValueError(f"background model returned mask shape {masks.shape}, expected {(frame_count,source_h,source_w)}")
    if split_algorithm not in SPLIT_ALGORITHMS: raise ValueError(f"split algorithm must be one of {', '.join(SPLIT_ALGORITHMS)}")
    scaled_w=round(source_w*height/source_h)
    if scaled_w<4: raise ValueError("scaled image is too narrow for four nonempty views")
    prepared_masks,combined_mask,source_edges,blobs=shared_split_edges(masks,split_algorithm); edges=scale_edges(source_edges,source_w,scaled_w)
    panels=[[None]*frame_count for _ in range(4)]; unions=[]; split_records=[]
    for col,(rgb,prepared) in enumerate(zip(arrays,prepared_masks)):
        whole=_premultiplied_resize(rgb,prepared,(scaled_w,height))
        for row in range(4): panels[row][col]=whole.crop((edges[row],0,edges[row+1],height))
        split_records.append({"source_edges":source_edges,"scaled_edges":edges,"blobs":[{"area":blob.area,"x0":blob.x0,"y0":blob.y0,"x1":blob.x1,"y1":blob.y1} for blob in blobs]})
    for row in range(4):
        boxes=[p.getchannel("A").getbbox() for p in panels[row]]; valid=[b for b in boxes if b]; unions.append((min(b[0] for b in valid),max(b[2] for b in valid)) if valid else (0,edges[row+1]-edges[row]))
    cell=max(height,max(hi-lo for lo,hi in unions)) if split_algorithm=="blobs" else max(height,max(panel.width for row in panels for panel in row)); top=(cell-height)//2
    total_ms=round(float(summary["period"]["seconds"])*1000); timing=[round((i+1)*total_ms/frame_count)-round(i*total_ms/frame_count) for i in range(frame_count)]
    if total_ms<frame_count or any(value<=0 for value in timing): raise ValueError("estimated cycle is too short for positive millisecond holds")
    sheet=Image.new("RGBA",(cell*frame_count,cell*4),(0,0,0,0)); offsets=[]; cells=[]
    for row in range(4):
        lo,hi=unions[row]; offset=round((cell-(hi-lo))/2-lo); offsets.append(offset)
        for col,panel in enumerate(panels[row]): sheet.alpha_composite(panel,(col*cell+offset,row*cell+top)); cells.append({"row":row,"column":col,"direction":directions[row],"rect":{"x":col*cell,"y":row*cell,"width":cell,"height":cell},"source_frame_id":records[col]["frame_id"],"source_pts":records[col]["pts"],"duration_ms":timing[col]})
    ground,evidence=_ground(summary,raw); scale=height/source_h; origin={"x":cell/2,"y":ground*scale+top,"normalized":{"x":.5,"y":(ground*scale+top)/cell}}
    tmp=out.with_name(out.name+".working"); sheet.save(tmp,format="PNG"); tmp.replace(out)
    data={"version":"1.0","sheet":out.name,"layout":{"rows":4,"columns":frame_count,"cell_size":cell,"direction_order":directions},"origin":{**origin,"coordinate_basis":"cell_top_left_pixels"},"source_ground_y":ground,"origin_evidence":evidence,"source_size":{"width":source_w,"height":source_h},"scaled_full_size":{"width":scaled_w,"height":height},"scale":scale,"vertical_padding":{"top":top,"bottom":cell-height-top},"row_horizontal_offsets":offsets,"splitting":{"algorithm":split_algorithm,"basis":"combined-selected-frame-alpha" if split_algorithm=="blobs" else "fixed-quarters","alpha_noise_threshold":ALPHA_NOISE_THRESHOLD if split_algorithm=="blobs" else None,"source_edges":source_edges,"scaled_edges":edges,"combined_foreground_pixels":int(np.count_nonzero(combined_mask)),"blobs":[{"area":blob.area,"x0":blob.x0,"y0":blob.y0,"x1":blob.x1,"y1":blob.y1} for blob in blobs],"frames":split_records},"cycle":{"seconds":summary["period"]["seconds"],"milliseconds":round(float(summary["period"]["seconds"])*1000)},"cells":cells,"source_paths":[str(p.relative_to(root.resolve())) for p in sources],"background_removal":{"backend":"ComfyUI API workflow",**getattr(list_remover,"provenance",{})},"resize":"premultiplied-alpha Lanczos; stored as straight RGBA"}; atomic_write_json(meta,data); return data

def main(argv=None):
    p=argparse.ArgumentParser(); p.add_argument("input"); p.add_argument("--sprite-box-height","--height",dest="height",type=int); p.add_argument("--directions",default="right,left,back,front"); p.add_argument("--split-algorithm",choices=SPLIT_ALGORITHMS,default="blobs"); p.add_argument("--server"); p.add_argument("--config",action="append",metavar="PATH"); args=p.parse_args(argv)
    config=[Path(path).resolve() for path in args.config] if args.config else None
    if args.height is None: args.height=configured_sprite_box_height(config)
    directions=[x.strip() for x in args.directions.split(",")]; root=Path(args.input).resolve(); batch=root/"batch-summary.json"
    roots=[root] if (root/"summary.json").is_file() else [Path(r["output"]).resolve() for r in json.loads(batch.read_text())["results"] if r["status"]=="exported"]
    if args.height<=0 or len(directions)!=4 or any(not x for x in directions): p.error("positive --height and exactly four nonempty comma-separated directions required")
    remover=Remover(args.server,config); failed=[]
    for item in roots:
        try: build(item,args.height,directions,remover,args.split_algorithm); print(f"packed {item}",flush=True)
        except Exception as error: failed.append({"directory":str(item),"error":f"{type(error).__name__}: {error}"}); print(f"failed {item}: {error}",flush=True)
    return 1 if failed else 0
if __name__=="__main__": raise SystemExit(main())
