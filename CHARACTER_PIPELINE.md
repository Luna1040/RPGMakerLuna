# 首个角色：制作流程与对接约定

更新：2026-10-11。此文件是后续对话的角色工作交接入口。前半部分保留 10 月 9 日首个角色的历史参数与验收结论；当前五角色扩展、队友机制及发布门槛见文末。

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

## 2026-10-11 五角色扩展与独立队友

当前正式接入目标是 `godot-belt-map`。本轮沿用姬骑士的精细手绘轮廓、上色与侧视比例，新增四类敌人和一位战牧同伴，不把颜色变化当作新角色。**机制与加载接口已接通，美术仍在生成和逐动作审查阶段；本节记录制作约定，不代表全部素材已经验收。**

| ID | 身份与识别点 | 要求动作 |
| --- | --- | --- |
| `scout` | 灰誓斥候；成年男性，皮甲、暗红围巾、单手剑 | `stand`, `walk`, `attack`, `hurt` |
| `caster` | 灰誓咒术师；成年女性，紫色法袍、银饰、法杖 | 同上；attack 为施法攻击 |
| `elite` | 灰誓重卫；成年男性，铁灰重甲、暗红披风、巨斧 | 同上 |
| `boss` | 陨星执政官；成年男性，黑金甲、酒红披风、巨剑 | 同上 |
| `serin` | 瑟琳 · 战牧；成年银发女性，象牙白与青绿袍装、短杖 | 同上，另加支援 `cast` |

共五张独立立绘、21 个必需动作片段。没有要求新生成死亡片：敌人暂用受击末帧淡出，瑟琳用灰暗受击末帧及倒下状态等待复苏。不能在交付文案里将这一回退处理称为独立死亡动画。

### 生产目录与断点恢复

本轮驱动脚本为 `character-generation-research/npc_roster_v1.py`；仅操作 `h3-runtime/npc-roster-v1/` 和带 `npc-roster-v1-` 前缀的 Comfy 输入/输出，不覆盖旧姬骑士资源。角色配置在 `roster.json`，取帧及人工复核结果在 `export-specs.json`。基础参数仍为 H3 20 steps / 768×768 / 124 source frames / 24 fps，无 turbo LoRA。

1. 使用已有姬骑士参考生成同画风、完整武器和足够画幅余量的透明角色母图，存放原始文件；检查发丝、衣袖、武器的边缘与内部空隙。
2. 运行 `npc_roster_v1.py reference --ids serin --source <原始PNG>` 生成 alpha 候选和深浅底对照，先审查 `review/serin-reference-alpha.jpg`。通过后才加 `--publish`，将干净参考以原子写入方式发布到 `references/` 和对应 portrait 路径。其余角色同理。
3. `npc_roster_v1.py run --watch-references` 会等待参考并串行向 9316 提交 GPU 工作，同时串行进行 CPU alpha 导出；已有完整成功 history 与 124 源帧的任务复用。不要并行启动第二个同名生成器，不要关闭用户的 9315 ComfyUI。
4. 每个 job 保留 `workflow.json`、`job.json`、`history.json`、`export-selection.json`。种子由角色基础 seed 加动作序号形成。`status` 只报告生成/导出进度，不能用队列提交数代替完成数。
5. 参考被放入 768×768 黑底，宽高约束为 540×520、初始地面线 y=648。提示词要求整个人物连头、胸、髋共同参与动作，武器全程存在且尺寸不变，镜头固定、不位移、不加模糊。此处主动使用黑底与语义抠图，不声称生成器能原生输出 alpha。
6. CPU 抠图输出整张 RGBA 画布，缓存按角色/动作/源帧隔离。检查 `review/<id>-<action>-alpha.jpg`、动作 WebP 和原片接触表。默认自动取帧、循环评分和 event 时刻只是候选，需人工修正后再导出。
7. 将通过检查的动作在 `export-specs.json` 内标为 `review_status:"visually_reviewed"`，按需要填写 `indices`、`durations`、`pivot`、`scale`、`event_ms`；运行 `export --ids <id> --actions <action> --force` 重新产出。不要直接改导出的 manifest 而丢失可重现源配置。

以下命令在工作区根目录运行（`python` 换成本机配置好的 Python）：

```sh
python character-generation-research/npc_roster_v1.py status
python character-generation-research/npc_roster_v1.py review --ids serin --actions stand walk attack hurt cast
python character-generation-research/npc_roster_v1.py export --ids serin --force
python character-generation-research/npc_roster_v1.py validate
```

生成脚本的 `validate` 会将尚未人工复核记录为 warning，所以它不是最终发布门槛。停止生成使用该脚本约定的 `STOP_AFTER_CURRENT` 标记，避免杀掉正在写源帧的进程。

### 游戏素材合同

生产输出在 `h3-runtime/npc-roster-v1/export/<id>/`；游戏加载路径为 `godot-belt-map/assets/roster/<id>/`。最终复制必须是已经审核的完整角色目录，不能只复制 portrait 然后宣布动作齐全。

`animation.json` 顶层字段：`version:1`、`id`、`name`、`canvas:[768,768]`、`portrait:"portrait.png"`、`actions`。每个动作记录：

- `frames:[{file,source_frame,duration_ms}]`：文件为角色目录内的安全相对路径，source_frame 指向原来的 0–123 源帧。
- `duration_ms`：等于全部帧时长之和；源视频长度不等于游戏动作长度。
- `pivot:[x,y]`、`scale`：该动作全帧固定的脚底原点与缩放。禁止逐帧 bbox 拉伸、中心对齐、逐帧原点或缩放。跨动作站姿对齐仍需实看。
- `source`、`source_count:124`、`review_status`：来源与复核记录。
- `event_ms`：攻击/施法出手时刻，必须位于动作内部。运行时将敌人前摇结束或队友施法释放时刻映射到这个视觉事件；伤害始终由战斗系统结算。
- `emitter:[x,y]`（可选）：实测的杖头/手掌发弹点，仍使用原 768×768 坐标。瑟琳及咒术师的 attack 可记录此字段，让投射物从画面中的施法位置出现；近战角色不必填写。要求两数有限且不超出画布。

运行时可另加动作级 `storage_crop:[x,y,w,h]`：由该动作所有帧的 alpha>0 联合包围盒加四周 4 px 透明留白派生，每帧使用完全相同的区域。原稿 export 不修改，顶层 canvas、pivot、scale、帧时序与 source_frame 均保持原值。播放器以 AtlasTexture margin 还原 768×768 虚拟画布，再照原坐标绘制；这是减少纹理空白的存储优化，不是图片变形，也不是逐帧居中或缩放。原图主体距画布边不足 4 px 时拒绝派生，不得悄悄夹断边缘。没有 storage_crop 的 PNG 仍严格保持 768×768。

最终检查裁切版时用 `--source-root` 指向原 export，逐像素比对重建画布的 alpha 与可见 RGB；完全透明处 RGB 可以不同。验证器同时检查四个整数、768 范围、文件尺寸与统一crop相符、四边4px完全透明；透明占比在还原后的画布上计算，避免把紧凑存图误判为没有抠背景。帧级 crop/storage_crop、pivot 或 scale 始终不允许。原稿比对可以抓出“边缘全透明但整块武器被遗漏”的错误，不能只凭裁后 PNG 的透明边就宣布无损。

原稿对照还核验可选 emitter 的存在性与数值保持一致；存储裁切不能平移、删除或新增发弹坐标。先在原稿的动作取帧配置中确定实测 emitter，再派生运行时资源。

对有 storage_crop 的动作，验证器会移除该字段后与原稿完整动作对象对比。运行时派生只能添加 storage_crop，不能改变 pivot/scale、event_ms、emitter、任何帧路径/源索引/时长或复核字段；即使 PNG 完全一致、总时长依然合法，元数据变化也不能通过。

`roster_animation.gd` 只采样整帧 PNG；`enemy_art.gd` 和 `roster_actor_view.gd` 负责显示，不执行技能扣蓝、伤害或奖励。走路左右腿、重心、躯干、头部应来自真实连续帧，不能用只有缩放和旋转的静态图冒充新动作。特效、投射物、护盾与预警继续使用独立游戏层。

### 瑟琳机制和存档接口

瑟琳拥有 140 HP / 80 MP。圣光弹 18 伤害、1.6 秒冷却、无蓝耗；愈合术消耗 18 MP、8 秒冷却，为 4.8 m 内可见且血量低于 55% 的队员恢复 40 HP；圣域盾在自身低于 72% HP 时消耗 24 MP、12 秒冷却，提供 38 点护盾、持续 6 秒。治疗优先于护盾和攻击。战斗回蓝 1.4/s，非战斗 4/s，没有被动回血。

三种命令为跟随作战、原地守卫、停战跟随；停战也禁止自动治疗/护盾，且不会免疫伤害。受击可打断未完成施法，蓝与冷却已经支付则不回退。倒下不再移动、回蓝、施法；旅店花 10 铜币恢复全队并复苏，同一笔休整不按队员人数重复收费。全队血蓝全满不扣钱。

战斗服务提供 `companion_status`、`companion_snapshot`、`validate_companion`、`restore_companion`、`rest_companion`，根 runtime 保存至 `companion.state`。状态恢复原子校验、禁止资源越界和真假字符串，读取同一存档不会复活或补满。没有 state 的旧档迁移为初始资源；新档存在空 state 则拒绝。切换模式或重新启用不恢复生命。队友专属装备、升级和其他职业尚未实现。

### 本轮发布门槛与证据

```sh
python godot-belt-map/tests/validate_roster_assets.py --source-root character-generation-research/h3-runtime/npc-roster-v1/export --output godot-belt-map/test-results/roster-assets.json
python -m unittest discover -s godot-belt-map/tests -p test_validate_roster_assets.py -v
python godot-belt-map/tests/run_tests.py --godot /path/to/godot --suite all
godot --path godot-belt-map --script res://tests/roster_capture.gd -- --foundations --page=serin
```

独立发布门槛必须返回 `ok:true` 且 `release_ready:true`：五立绘、21 动作齐全，RGBA 画布有效，边缘无不透明截断，主体非空，背景确有透明，帧时长/事件/源帧有效，固定原点，至少两张不同图，全部动作经过视觉复核。`--allow-pending-review` 只允许生产诊断，始终不会把待审核动作判为可发布。自动 alpha 检查不能发现所有白孔、错误遮挡和造型漂移，完整深浅底动图与游戏实测仍是必要证据。

带 storage_crop 的运行时版本还必须确认 `lossless_storage_verified:true`；Python 调用接口为 `validate(root, require_review=True, source_root=<原export目录>)`。原稿缺失、可见像素或 alpha 不一致都会使检查失败。未提供 source_root 时只检查结构并提示尚未证明无损，`release_ready` 保持 false，不作为最终运行时裁切验收。

本轮角色图鉴/队友集成已有 64 项检查通过（包含已导入的瑟琳待机预览），另有存档、剧情、暂停输入、战斗专项回归；最终数量以最终测试报告为准。图鉴可切换已就绪动作及深浅背景，预览采用固定画布，非循环动作在末帧停 650 ms 后重播，关闭图鉴即停止；未就绪动作禁用。2026-10-11 最终已完成五角色 21 动作、351 帧；25 项机制回归、351 帧原稿无损比对、全部动作原生截图及 4 个发弹截图通过。完整交接见 NPC_ROSTER_INTEGRATION.md。


### 中断恢复与重生成缓存（2026-10-11）

- 正式选帧、每帧时长、固定锚点、事件时刻、局部 alpha 规则均保存在 `npc-roster-v1/export-specs.json`。不要重跑历史 `configure_roster_resume.py`；它含被拒绝的候选方案，现已阻止执行。
- 成功 history 优先。只有在后台异常退出但所有 124 帧已完整写入时，才用 `recover_roster_frames.py` 校验连续编号、尺寸、解码及嵌入工作流，并保存每帧 SHA-256 的 `recovered-frames.json`；这不是伪造成功 history。
- 重生成可能沿用动作/序号，但原始图已经变了。抠图缓存必须同时匹配 `.source.sha256`；没有摘要或摘要不一致时重新抠图，禁止复用旧动作的 alpha/RGB。
- `approve_roster_review.py` 仅记录已实际完成的目视复核，不能代替查看整段、每帧深浅底和实机截图。它再调用无损运行时打包，边缘留白不合格会拒绝发布。
- 首领带大范围背景光的初版已放入 `archive/boss-attack-background-light-v1/`；游戏使用纯物理动作描述重生成的 v2。避免用大块硬遮罩掩盖污染，必要时重生成。
- 工作流的语义应描述具体身体动作。把“法术释放”拆成肩/髋转动、手掌伸展等物理动作，再由游戏独立生成弹体；仍需逐帧检查模型是否擅自加光。
