"""Repair card faces in the already-approved H3 video; never transform scene pixels."""
from pathlib import Path
import sys,json
ROOT=Path(__file__).resolve().parents[4]
sys.path[:0]=[str(ROOT/'character-generation-research/h3-runtime/deps'),str(ROOT/'character-generation-research/h3-plugin-deps')]
import cv2
import numpy as np
base=Path(__file__).resolve().parent
source=base.parent/'dealer-motion-v1/deal/outputs'
out=base/'fixed-wide-frames'; out.mkdir(exist_ok=True)
maskdir=base/'repair-masks';maskdir.mkdir(exist_ok=True)
records=[]
for i in range(124):
    im=cv2.imdecode(np.frombuffer((source/f'{i:05d}.png').read_bytes(),np.uint8),cv2.IMREAD_COLOR)
    b,g,r=cv2.split(im.astype(np.int16))
    white=((b>110)&(g>130)&(r>130)&(np.abs(r-g)<23)&(np.abs(g-b)<23)).astype(np.uint8)*255
    roi=np.zeros_like(white);roi[270:530,410:640]=white[270:530,410:640]
    contours,_=cv2.findContours(roi,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
    mask=np.zeros_like(white)
    clusters=[c for c in contours if cv2.contourArea(c)>5]
    changed=True
    while changed:
        changed=False
        for a in range(len(clusters)):
            ax,ay,aw,ah=cv2.boundingRect(clusters[a])
            for z in range(a+1,len(clusters)):
                bx,by,bw,bh=cv2.boundingRect(clusters[z])
                gapx=max(0,ax-(bx+bw),bx-(ax+aw))
                gapy=max(0,ay-(by+bh),by-(ay+ah))
                if gapx<=10 and gapy<=10 and max(ay+ah,by+bh)<350:
                    clusters[a]=np.concatenate([clusters[a],clusters[z]])
                    clusters.pop(z);changed=True;break
            if changed:break
    for c in clusters:
        c=cv2.convexHull(c)
        x,y,w,h=cv2.boundingRect(c)
        if cv2.contourArea(c)>65 and w>=14 and h>=4:
            cv2.drawContours(mask,[c],-1,255,cv2.FILLED)
    # Preserve the original card silhouette, hand occlusion and narrow white border.
    inner=cv2.erode(mask,np.ones((3,3),np.uint8),iterations=1)
    skin=(r-g>10)&(g-b>9)&(r>120)&(b>70)
    skin_labels, skin_map, skin_stats, _=cv2.connectedComponentsWithStats(skin.astype(np.uint8))
    for component in range(1,skin_labels):
        if skin_stats[component,cv2.CC_STAT_AREA]>150: inner[skin_map==component]=0
    y,x=np.indices(mask.shape)
    pattern=((x+y)%10<=1)|((x-y)%10<=1)
    texture=np.zeros_like(im);texture[:]=[48,28,128]
    texture[pattern]=[85,105,177]
    result=im.copy();result[inner>0]=texture[inner>0]
    assert np.array_equal(result[mask==0],im[mask==0])
    (out/f'{i:05d}.png').write_bytes(cv2.imencode('.png',result)[1].tobytes())
    (maskdir/f'{i:05d}.png').write_bytes(cv2.imencode('.png',mask)[1].tobytes())
    records.append({'source_frame':i,'mask_pixels':int((mask>0).sum()),'pixels_changed_outside_mask':0})
(base/'repair-audit.json').write_text(json.dumps({'source':'../dealer-motion-v1/deal/outputs','canvas':[1024,576],'frames':records,'camera_transform':'none','outside_mask_difference':0},indent=2),encoding='utf-8')
print('PASS: 124 frames; all pixels outside card masks identical to original wide video')
