from pathlib import Path
p=Path(__file__).with_name('repair_video.py')
s=p.read_text(encoding='utf-8-sig')
old='''    for c in contours:
        x,y,w,h=cv2.boundingRect(c)
        if cv2.contourArea(c)>65 and w>=14 and h>=4:
            cv2.drawContours(mask,[cv2.convexHull(c)],-1,255,cv2.FILLED)'''
new='''    clusters=[c for c in contours if cv2.contourArea(c)>5]
    changed=True
    while changed:
        changed=False
        for a in range(len(clusters)):
            ax,ay,aw,ah=cv2.boundingRect(clusters[a])
            for z in range(a+1,len(clusters)):
                bx,by,bw,bh=cv2.boundingRect(clusters[z])
                gapx=max(0,ax-(bx+bw),bx-(ax+aw))
                gapy=max(0,ay-(by+bh),by-(ay+ah))
                if gapx<=10 and gapy<=10:
                    clusters[a]=np.concatenate([clusters[a],clusters[z]])
                    clusters.pop(z);changed=True;break
            if changed:break
    for c in clusters:
        c=cv2.convexHull(c)
        x,y,w,h=cv2.boundingRect(c)
        if cv2.contourArea(c)>65 and w>=14 and h>=4:
            cv2.drawContours(mask,[c],-1,255,cv2.FILLED)'''
assert old in s
p.write_text(s.replace(old,new),encoding='utf-8')
