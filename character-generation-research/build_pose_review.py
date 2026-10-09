from pose_ab_test import OUT
import base64,json
def data(name):
 p=OUT/name
 return 'data:image/png;base64,'+base64.b64encode(p.read_bytes()).decode() if p.exists() else None
images={route:[data(f'gpt-{p}.png' if route=='gpt' else f'local-refined-{p}-rgba.png' if route=='refined' else f'controlnet-{p}-rgba.png') for p in ['A','M','B']] for route in ['gpt','controlnet','refined']}
images['guide']=[data(f'guide-{p}.png') for p in ['A','M','B']]
images['green']=[data(f'controlnet-{p}-green.png') for p in ['A','M','B']]
images['overlay']={route:[data(f'{route}-{p}-overlay.png') for p in ['A','M','B']] for route in ['gpt','controlnet','refined']}
html='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>角色动作：两条路线实测</title>
<style>body{margin:0;background:#111722;color:#e8edf4;font:16px system-ui,"Microsoft Yahei"}main{max-width:1440px;margin:auto;padding:30px}h1{font-size:28px}p{color:#b4c2d4;line-height:1.7}button,select,input{font:inherit}button,select{padding:9px 15px;background:#29364a;color:white;border:1px solid #536077;border-radius:7px;margin:4px}section{display:grid;grid-template-columns:1fr 1fr;gap:20px}article{background:#1a2433;border-radius:12px;padding:16px}canvas{width:100%;background:#202735}aside{display:flex;gap:12px;align-items:center;flex-wrap:wrap;margin:16px 0}small{color:#aab7c9}a{color:#9bc8ff}.warn{color:#ffd38c}#guide{width:240px}label{margin:6px}</style>
<main><h1>同一套参数骨架，两条生成路线</h1>
<p>三关键姿势实验，尚未完成连续动画。A 蓄力 → M 途中 → B 收势；循环回到 A 是重置，不是恢复动作。原始画布统一缩放显示，未逐帧居中、拉伸肢体或补造过渡帧。</p>
<aside><button id="play">播放三帧</button><input id="phase" type="range" min="0" max="2" step="1" value="0"><b id="name">A · 蓄力</b><select id="back"><option value="checker">棋盘背景</option><option value="light">浅色背景</option><option value="dark">深色背景</option></select><label><input id="bones" type="checkbox">查看骨架叠加检查图</label><label><input id="green" type="checkbox">本地组显示原始绿幕</label></aside>
<section><article><h2>GPT 图像生成 · 透明参考图编辑</h2><canvas id="gpt" width="768" height="768"></canvas><p>输入角色母版和姿势图。姿势图是视觉参考，不是真正的 ControlNet。检查手腕、剑长、脚的位置及服饰细节漂移。</p></article>
<article><h2>本地 SDXL ＋ OpenPose ControlNet</h2><canvas id="controlnet" width="768" height="768"></canvas><p>Animagine XL 3.1 ＋ Xinsir OpenPose，固定随机种子，绿幕后抠图。本轮基础组仅用文字描述外观，没有 IP-Adapter 身份约束；不能用它评判角色参考图复现能力。</p></article></section>
<aside><img id="guide"><div><h3>参数骨架</h3><p>固定肢体长度，双脚位置不变；骨盆、躯干角度、握剑点及剑方向随相位变化。金线是预期剑轴，仅供 GPT 参考；OpenPose ControlNet 本身不控制武器。</p><small>完整坐标保存在 poses.json；模型提示词和工作流保存在同目录。</small></div></aside>
<p class="warn">验收目标：透明边缘完整、关节跟随、人物设计一致、剑长稳定。单张漂亮不代表动画通过。</p></main>
<script>const assets=ASSETS;const cache={};let tick=null;let frame=0;const labels=['A · 蓄力','M · 途中','B · 收势'];
function img(src){if(!src)return null;if(!cache[src]){let i=new Image;i.onload=render;i.src=src;cache[src]=i}return cache[src]}
function render(){frame=+document.querySelector('#phase').value;document.querySelector('#name').textContent=labels[frame];document.querySelector('#guide').src=assets.guide[frame];for(const route of ['gpt','controlnet']){let c=document.getElementById(route),x=c.getContext('2d');let bg=document.querySelector('#back').value;x.fillStyle=bg==='light'?'#eee':'#202735';x.fillRect(0,0,768,768);if(bg==='checker'){x.fillStyle='#2e3848';for(let y=0;y<768;y+=24)for(let a=0;a<768;a+=24)if((a/24+y/24)%2)x.fillRect(a,y,24,24)}let src=assets[route][frame];if(route==='controlnet'&&document.querySelector('#green').checked)src=assets.green[frame];if(document.querySelector('#bones').checked)src=assets.overlay[route][frame];let im=img(src);if(im&&im.complete)x.drawImage(im,0,0,768,768);else if(!src){x.fillStyle='white';x.font='22px system-ui';x.fillText('本地结果尚未生成',220,380)}}}
document.querySelectorAll('input,select').forEach(e=>e.oninput=render);document.querySelector('#play').onclick=()=>{if(tick){clearInterval(tick);tick=null;document.querySelector('#play').textContent='播放三帧'}else{tick=setInterval(()=>{document.querySelector('#phase').value=(frame+1)%3;render()},550);document.querySelector('#play').textContent='暂停'}};render();</script></html>'''
html=html.replace('grid-template-columns:1fr 1fr','grid-template-columns:1fr 1fr 1fr')
html=html.replace('</article></section>','</article><article><h2>本地追加：Flux 按母版重绘</h2><canvas id="refined" width="768" height="768"></canvas><p>ControlNet 底稿再按角色母版重绘。外观接近母版，但 B 帧躯干退回直立姿势，未通过动作验收。</p></article></section>')
html=html.replace("for(const route of ['gpt','controlnet'])","for(const route of ['gpt','controlnet','refined'])")
(OUT/'review.html').write_text(html.replace('ASSETS',json.dumps(images)),encoding='utf-8')
print(OUT/'review.html')
