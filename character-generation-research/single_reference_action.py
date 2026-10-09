from comfy_trials import *

q=get('/queue')
if q['queue_running'] or q['queue_pending']:
    raise RuntimeError('ComfyUI is busy; leave existing jobs alone')
ref=upload(OUT/'v3b-attack-A.png')
run('v3d-downswing', '重新绘制这位女骑士挥剑结束的下一帧。她已经把头顶的剑劈到右下方。两条胳膊都从头顶放下来，伸向右下方，双手在右膝前方握住剑柄，剑尖指向画面右下角。头顶现在没有剑也没有手臂。背部继续前倾，低头看向剑尖，前膝弯曲，后腿蹬直，重心前移。头发和披风扬起。保持人物服装和画风。单人全身完整构图，灰色背景。',ref,size=(1024,1024))
run('v3d-mid-swing', '重画为挥剑动作的中间帧：图中女骑士把双臂和剑从头顶放下来，双臂向正前方伸直，两只手共同握住一把剑在胸口前方，剑竖直向上。她的肩膀向前转动，胸腔向右前方扭转，头向前探出，弓步向右。头顶原来的双臂和横向剑全部消失。银金铠甲、蓝裙蓝披风、金发马尾保持一致。灰色背景，单人全身，整把剑完整入画。',ref,size=(1024,1024))
