from comfy_trials import *
q=get('/queue')
if q['queue_running'] or q['queue_pending']: raise RuntimeError('ComfyUI busy')
ref=upload(OUT/'v3d-downswing.png')
run('v3e-followthrough', '将这个角色改成深度弯腰的劈剑收势。整个上半身向右俯身，背部接近水平，头部大幅降低到现在胸口的高度，脸朝右下方看地面，臀部抬高向左后方，前腿膝盖深弯，后腿伸直。双手放低到右小腿前方，共同握住一把指向右下的长剑。马尾从低下的头部向左上方甩起，披风向左上方掀起。重新画完整人物，保持服装设计和画风，灰色背景，头脚剑全部入画。',ref,size=(1024,1024))
ref=upload(OUT/'v3b-attack-A.png')
run('v3e-windup', '将这个角色改成站高的举剑蓄力姿势。膝盖伸展，骨盆抬高，胸口挺起，背部向左后方倾斜，头部随胸口抬高并向左后方移动，目光仍然看向右侧敌人。双手共同握住头顶的剑柄，把剑举到身后，剑尖朝向左上方。马尾和披风向下自然垂落。重新画完整人物，保持服装设计和画风，灰色背景，头脚剑全部入画。',ref,size=(1024,1024))
