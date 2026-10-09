# 首个角色：制作流程与对接约定

更新：2026-10-09。此文件是后续对话的角色工作交接入口。

## 已认可的方向

原创成年金发姬骑士，蓝披风、银金铠甲、长剑。用户已认可 H3 生成的协调全身动画，以及 combat-v1 的 0.64 秒快速攻击。不要回退到僵硬的分件木偶、粗糙 3D 或重新设计人物。地图由另一个对话处理，角色工作仅修改角色目录；不自动修改地图项目。

## 本地工具与路径

- 工作区：`C:/Users/11043/Desktop/先锋技术调研`
- 角色研究目录：`character-generation-research`
- 最初精美参考：`comfy-results/v2-master.png`
- 补足画幅参考：`h3-runtime/padded-green-reference.png`；H3 输入名 `knight-green-reference.png`
- 独立 H3 ComfyUI：`http://127.0.0.1:9316`，启动脚本 `start_h3.py`。原用户 ComfyUI 在 9315，不要关闭或修改。
- Python：`C:/Users/11043/Downloads/Flux2_klein_v1.0_普通版/Flux2_klein/python_embeded/python.exe`。
- Godot：`.tools/godot/Godot_v4.7.2-stable_win64.exe`。
- 旧对照项目：`h3-runtime/godot-preview`；入口 `play-h3-test.cmd`，保留作回归参考。

## 成功的生成参数

使用原参考图作 Reference-to-Video，固定机位，整个人物连头发、披风、剑均留在画幅内；人物约占画面高度 60%。强调髋部、躯干、头部共同参与动作，头发与披风延迟跟随。不要锁死躯干和头部，也不要以增加帧数掩盖动作问题。

- diffusion：`minimax_h3_ref2va_pruned_fp8_scaled.safetensors`
- text encoder：`qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors`
- video VAE：`minimax_h3_video_vae_fp16.safetensors`
- 768×768，124 帧，24 fps，20 steps，normal scheduler，res_multistep，denoise 1。
- 不加载 turbo LoRA。4 step 初稿质量较差；已认可版本为 20 step。
- 首轮 seed 731420；每个新动作记录自己的 seed 与完整 API workflow。
- 参考为绿幕，但已认可 H3 输出实际上是黑底；不要声称提示词能保证绿幕或原生透明。
- 单段 5.17 秒只是生成素材长度，不是游戏技能时长。

## 后处理和节奏

1. 保存原始视频、全部源帧、workflow、prompt id、history；不覆盖已认可原素材。
2. `biref_h3_matte.py`：本地 BiRefNet-lite + 黑底边缘清理；保留 768×768 统一画布与角色原点，输出 RGBA。AI 分割会误删蓝披风，必须检查深浅背景。
3. 不为每帧按 alpha bbox 独立缩放，否则武器长度和身体尺寸会跳变。若裁切，必须保存 crop offset / pivot。
4. 从源动作中选择有效帧，再设每帧独立时长；动作表必须记录 source_frame 与 duration_ms。
5. 已认可攻击 `build_combat.py` → `h3-runtime/combat-v1`：源帧 8,14,20,25,28,30,33,36,39,42,45,48,52,57,63,70,78,90；时长 35,35,40,45,50,20,20,20,20,55,25,30,35,40,40,45,45,40 ms，总计 640 ms。展示循环额外停 650 ms，不计入技能时长。
6. 黑底发光特效用独立加法层 `CanvasItemMaterial.BLEND_MODE_ADD`，人物正常 alpha。正片叠底不能消除黑底。当前分离依赖神经 mask + 本动作专用披风保护区域，不能直接推广为万能算法；角色与特效已经烘焙重叠，仍有边缘残留。
7. 不把人物整张图设为加法，否则盔甲和深色衣服会变透明/过亮。未来优先独立产出特效。

## 当前扩展任务

为首个角色建立可玩机制：站立呼吸、闲置小动作、移动、三段普通攻击、施法，以及受击反馈。复用已认可移动和第一段攻击，新增动作走同一 H3 流程。角色应支持转向、攻击缓冲与连击、施法资源/冷却、实际命中窗口、受击中断与恢复。训练目标用于验证机制，不替地图对话制作正式地图。

## 地图对话对接

角色包位于 `godot-first-knight`，独立角色场景 `knight.tscn`、脚本 `knight.gd`、资源 `assets/`。具体接口见 `godot-first-knight/INTEGRATION.md`。训练场入口 `play-first-knight.cmd`。地图通过角色节点位置、输入开关、伤害方法和技能信号对接；不得通过播放视频模拟角色逻辑。

## 重跑与增量更新

在工作区打开 PowerShell，使用上述嵌入式 Python：

1. 9316 未运行时：`python character-generation-research/start_h3.py`。不要重复启动同一端口。
2. `python character-generation-research/generate_character_set.py` 生成六个新增动作；已有成功 history 与 124 张源帧的动作跳过。每个动作的工作流、种子与 history 保存在 `h3-runtime/character-set/`。若设计新版本，使用新前缀保存，避免覆盖已认可素材。
3. `python character-generation-research/inspect_character_set.py` 输出原片接触表，先检查造型和动作阶段。该脚本需等待每段 124 帧完整写出。
4. 修改 `h3-runtime/character-set/export-specs.json` 决定取帧、帧时长与命中事件。站立与走路通过首尾图像及局部运动差选循环；这只是候选选择，仍需肉眼检查。
5. `python character-generation-research/build_character_set.py stand walk attack1 idle attack2 attack3 cast hurt` 导出素材。默认 CPU 抠图，避免与 H3 抢显存；缓存位于 `h3-runtime/character-set/mattes`。修改抠图算法后要使用新的缓存目录或明确更新对应缓存，否则会沿用旧结果。
6. `python character-generation-research/validate_character_assets.py` 检查画幅、alpha、边缘截断、时序与事件范围。
7. Godot 先 `--headless --editor --path godot-first-knight --quit` 导入，再运行机制测试 `--headless --path godot-first-knight -- --smoke-test`。最后打开可视窗口验收。

生成期间保留机器可读的工作流与 history；导出期间保留 source_frame。不要把临时 PNG 编号当成原始生成帧号，也不要用所有素材总帧数当作游戏播放时长。

## 验收

原参考一致性、全身协调、剑不变短/截断、循环接缝、深浅背景 alpha、实际游戏时长、动作中不能滑步、连击只在合法窗口触发、一次攻击不重复打同一目标、冷却/资源不足不施法。生成失败或身份漂移要明确标注，不能把作业排队当成完成。

## 2026-10-09 本轮交付结果

八种动作已接入训练场，共 163 张 RGBA 角色帧，另有第一段攻击加法层和独立能量弹。所有源视频、744 张本轮新源帧与工作流保留。

| 动作 | 帧数 | 游戏时长 | 机制 |
|---|---:|---:|---|
| 站立呼吸 | 39 | 3.276 秒循环 | 无输入待机 |
| 闲置整理头发 | 25 | 2.125 秒 | 停留 4 秒触发 |
| 步行 | 15 | 1.05 秒循环 | 横向移动和镜像转向 |
| 下劈 | 18 | 0.640 秒 | 22 伤害，305 ms 命中 |
| 突刺 | 17 | 0.525 秒 | 27 伤害，200 ms 命中 |
| 上挑 | 18 | 0.665 秒 | 35 伤害，250 ms 命中 |
| 施法 | 18 | 0.730 秒 | 25 MP，360 ms 释放，2.4 秒冷却 |
| 受击架剑反应 | 13 | 0.460 秒 | 中断动作、扣血、恢复 |

三个攻击总长 1.83 秒（连续输入时）。施法源片仍自带特效：后处理保留掌心光，削去飞出部分，并从原片提取 `magic_bolt.png` 用作独立加法投射物。人物与光照原本烘焙在一起，因此强光区域仍可能有少量分割残留，不应宣称达到逐帧人工精修水平。

验证文件：`godot-first-knight/asset-verification.json`（所有角色帧 768×768 RGBA、无不透明画布边缘、时序有效），`mechanics-check.log`（连击各一次命中、法术命中、冷却、伤害、恢复、归零、重置通过），`captures/`（八种动作实际 Godot 渲染截图）。

展示：`character-generation-research/h3-runtime/character-set/index.html` 和 `complete-character.webp`。可玩的入口：`play-first-knight.cmd`。地图可用角色包：`first-knight-character.zip`，接口说明位于包内 `INTEGRATION.md`。

已知范围：固定侧视，左向镜像；受击片偏架剑抵挡反应；没有独立死亡、跳跃或八方向素材。这是第一套基础战斗角色原型，后续可在既有动作表和信号接口上扩展。

### 近战判定修正

木桩现支持感电、击飞和浮空追击。状态逻辑在 `godot-first-knight/dummy_reactions.gd`，参数和地图接入方式见 `INTEGRATION.md`。第三段后可缓存回到第一段连续追击。木桩改为 1000 HP，受击框跟随高度；感电持续伤害不计连击。机制测试已包含感电时长/伤害、实际连击时间线的空中命中、空连上限、落地和过高目标落空。

原范围 185/205/180 像素未覆盖下劈/突刺的视觉剑锋，并错误地仅比较目标中心。现动作表记录视觉基础范围 220/235/180，运行时统一加 `melee_reach_margin=24`，得到 244/259/204 像素，再与目标受击体相交。范围随人物缩放变化。双向临界距离命中/落空和背向目标测试已加入机制测试。不要在后续导出时退回旧范围。

### 母图污染与真正绿幕测试

用户指出的发丝/颈部白块已追溯至原始参考图的四个封闭背景孔洞。旧 `prepare_h3_green.py` 只清外围相连背景，留下这些灰白岛；不能把它当作合格绿幕母图。`test_clean_chroma.py` 对单张母图记录四处背景区域，清掉孔洞后重新生成参考。结果和源图 SHA 位于 `h3-runtime/chroma-test/master-mask.json`，前后对比 `reference-comparison.png`。

清理后的母图配合明确绿色背景提示，已跑完 124 帧测试（workflow/history 同目录）。实际检查第 40 帧仍是黑底，说明本地 H3 这次没有遵守绿幕要求；该帧的原有白色孔洞已消失。不要宣称已经实现可靠绿幕动画，也不要因此修改全部量产素材。下一步应以干净母图验证跨动作稳定性，并把背景颜色合规检查作为导入前的硬性门槛。已交付八动作仍使用旧源片，不能说它们的白块已全部修好。
