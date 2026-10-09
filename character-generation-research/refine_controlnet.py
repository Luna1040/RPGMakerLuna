from comfy_trials import *
from pose_ab_test import OUT as POSES
q=get('/queue')
if q['queue_running'] or q['queue_pending']:raise RuntimeError('ComfyUI busy')
master=upload(OUT/'v2-master.png')
import sys
for phase in sys.argv[1:] or ['M']:
 pose=upload(POSES/f'controlnet-{phase}-green.png')
 sword={'A':'双手在头顶共同握住一把长剑，剑刃指向左上方','M':'两只手都握住同一把剑柄，剑向右上方倾斜','B':'双手在前腿大腿上方共同握住同一把长剑，剑刃指向右下方，已经向下劈完，不能指向上方'}[phase]
 text='以图1为动作底稿，保持图1的头、胸、臀、肩、肘、膝、脚的位置和弓步前倾姿势。把图1的人物外观重新画成图2的成年女骑士：图2的金发高马尾、蓝眼、金冠、银金铠甲、蓝色短裙、蓝色披风、铠甲靴，以及图2精美细致的二维画风。图2只提供角色设计，不要照搬图2站姿。修正图1双手，'+sword+'，完整剑身入画。重新画一位完整人物，只有两只手两条腿一把剑。背景是完全均匀的鲜绿色，绝对没有地面和投影，没有环境，没有文字。'
 run('controlnet-refined-'+phase,text,pose,master,size=(1024,1024))
 (POSES/f'local-refined-{phase}-green.png').write_bytes((OUT/f'controlnet-refined-{phase}.png').read_bytes())
 (POSES/f'local-refined-{phase}-api.json').write_bytes((OUT/f'controlnet-refined-{phase}-workflow.json').read_bytes())
