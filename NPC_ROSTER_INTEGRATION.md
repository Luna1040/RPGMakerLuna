# 五角色素材与队友系统交接

更新：2026-10-11。目标工程为 `godot-belt-map`，入口 `stage.tscn`。本文随角色与队友试玩版一同归档。

## 当前状态与发布条件

五名原创角色的立绘与 21 个整帧动作已完成，共 351 张透明 PNG：斥候 64、咒术师 72、重卫 71、首领 67、瑟琳 77。每名角色具备站立、步行、攻击和受击，瑟琳另有支援施法。原稿逐帧深浅背景复核后已接入真实战斗。

最终验收：`test-results/20261011T101927Z-39320/report.json` 的 25 项检查全部通过；`test-results/roster-assets-final.json` 输出 `release_ready:true`、`lossless_storage_verified:true`，351 帧均与原稿一致。`captures/roster-motion/` 保存全部 21 动作和原姬骑士同屏比例；`captures/roster-spells/` 保存瑟琳/咒术师双朝向共 4 个真实关卡发弹检查。测试报告以运行时重新生成结果为准。

首领攻击初版背景光污染已归档并拒绝，游戏使用重生成的 v2。首领待机采用可逆重心段往返播放闭合首尾；不同原始构图通过每动作固定 pivot/scale 校准，禁止逐帧追踪居中。

资源发布门槛必须输出 `release_ready:true`：

```sh
python godot-belt-map/tests/validate_roster_assets.py --source-root character-generation-research/h3-runtime/npc-roster-v1/export --output godot-belt-map/test-results/roster-assets.json
python godot-belt-map/tests/run_tests.py --godot /path/to/godot --suite all
```

第一条需要 Pillow。运行时素材使用下面的统一存储裁切时，最终验收必须带 `--source-root`，同时确认 `lossless_storage_verified:true`。`--allow-pending-review` 仅为生成中的诊断模式，允许结构正确但仍未人工复核的素材继续检查，永远不把待复核集判为可发布。脚本不会改变 PNG、manifest 或复核标记。

## 角色和文件

| 游戏行为 | 美术 ID | 中文身份 | 片段 |
| --- | --- | --- | --- |
| 近战兵 `melee` | `scout` | 灰誓斥候 | 站立、步行、攻击、受击 |
| 远程兵 `ranged` | `caster` | 灰誓咒术师 | 站立、步行、施法攻击、受击 |
| 重装兵 `elite` | `elite` | 灰誓重卫 | 站立、步行、攻击、受击 |
| 首领 `boss` | `boss` | 陨星执政官 | 站立、步行、攻击、受击 |
| 同行战牧 | `serin` | 瑟琳 · 战牧 | 站立、步行、攻击、受击、支援施法 |

每个目录 `godot-belt-map/assets/roster/<id>/` 应包含 `portrait.png`、`animation.json` 与动作子目录。必须使用与姬骑士一致的精细全身绘制、统一侧视方向和清晰轮廓；换色、借主角帧、静态图旋转或拼接肢体不能替代这 21 个动作。

源记录、生成和抠图过程位于 `character-generation-research/h3-runtime/npc-roster-v1/`。完整流程见 [CHARACTER_PIPELINE.md](CHARACTER_PIPELINE.md) 文末。画幅固定 768×768，PNG 为 RGBA，保留全部头发、服装、手、脚和武器；立绘可以使用独立大画幅。

## Manifest 与显示接口

顶层包含 `version:1`、`id`、`name`、`canvas:[768,768]`、`portrait`、`actions`。动作名为 `stand`、`walk`、`attack`、`hurt`，瑟琳另有 `cast`。每个动作：

| 字段 | 约定 |
| --- | --- |
| `frames` | 有序 `{file, source_frame, duration_ms}` 数组；file 为角色目录内的相对 PNG 路径 |
| `duration_ms` | 所有帧时长总和，不能拿 124/24 秒作为游戏出手时长 |
| `pivot` / `scale` | 同一动作所有帧共用的脚底原点和缩放；禁止逐帧裁切居中与缩放 |
| `event_ms` | `attack` / `cast` 的真实出手画面时刻；必须位于动作内 |
| `emitter`（可选） | `[x,y]` 发弹原点，使用原始 768×768 坐标；用于让瑟琳/咒术师的弹体从杖头或手掌释放，近战无需此字段 |
| `source` / `source_count` | 原始 job 标识及 124 张源帧的来源计数 |
| `review_status` | 人工观看整段动画、深浅底边缘和实机动作后才设 `visually_reviewed` |
| `storage_crop`（可选） | 运行时统一存储区域 `[x,y,width,height]`，同一动作所有 PNG 完全相同；不是新的角色坐标系 |

`roster_animation.gd` 负责按独立帧时长取图、循环与事件对齐；前摇与恢复分别映射，实际伤害/发弹仍由 `encounters.gd` 结算。`enemy_art.gd` 读敌人状态，`roster_actor_view.gd` 读瑟琳状态。动作视图不改血蓝、不触发奖励。按朝向围绕固定脚底原点镜像，不能把独立图片中心当脚底。

### 透明空白的运行时存储优化

原稿 `export/<id>/` 中的 PNG 始终保留完整 768×768，不覆盖、不缩放。运行时派生版可以按**同一动作全部帧的 alpha>0 联合包围盒，加四周 4 像素透明边距**存图，并在该动作声明 `storage_crop`。四个值必须是整数，区域必须完全在 768×768 内；如果原稿靠边而无法保留完整 4 像素，必须拒绝这一派生结果。

这仅减少 GPU 纹理中没有内容的空白。顶层 `canvas`、动作 `pivot/scale`、帧时长、原始 source_frame 均保持原值。播放器使用 AtlasTexture margin 恢复 768×768 虚拟画布，再按原脚底坐标绘制；不逐帧改变原点、尺寸或透视。没有 `storage_crop` 的原稿仍必须是 768×768。

发弹用的可选 `emitter` 同样保留原 768×768 坐标，不能减去 storage_crop 的左上角。验收要求它是两个有限且在画布范围内的数；提供原稿时同时核对这个字段的存在性与数值，丢失或擅自改成裁后坐标都会失败。没有发弹动作的近战角色不强制提供 emitter。

带 storage_crop 的动作在去掉这一新增字段后，必须与原稿动作记录完整相等：pivot、scale、事件、emitter、全部帧文件/源帧号/每帧时长及复核记录均不得变化。相同 PNG 但原点错移，或总时长合法却重分配了帧时间，也会被原稿对照拦截。

验收器检查裁切矩形、PNG 实际尺寸、四边完整透明留白，在恢复虚拟画布后计算 alpha、透明占比和主体边界。`--source-root` 进一步逐帧核对原稿的 alpha 与所有 alpha>0 像素的 RGB，能识别被整块漏掉的武器、飘带、错误偏移和颜色变化；alpha=0 的 RGB 不参与比较，因为没有显示贡献。只检查四边透明不能证明没有漏掉远离躯干的独立部件，因此不带原稿的检查会给出未证明无损的警告且 `release_ready:false`，最终发布必须补这项原稿比对。帧级 `crop/storage_crop/pivot/scale/offset` 仍被禁止。

没有新生成的死亡片。敌人使用受击末帧短暂淡出；瑟琳倒下时使用灰暗受击末帧、倾斜与文字标记，等待复苏。这是明确的临时死亡表现，不是完整倒地动画。护盾、光弹、预警与光效在独立层绘制。

## 同行角色的完整机制

瑟琳有独立 140 HP / 80 MP，敌人会在她和主角之间选择目标，近战范围可以同时伤及两人，敌方投射物由路径上的第一个队员身体截住。她遵守场景障碍与地面脚底排序，但不是新增阻挡地图行走的实体墙。

- 圣光弹：18 伤害，1.6 秒冷却，0 MP，前摇后发射独立光弹；墙体和第一个敌人消费弹体。
- 愈合术：18 MP，8 秒冷却；治疗 4.8 m 内可见、生命低于 55% 的队员，按更低生命比例优先，恢复 40 HP，不能复活。
- 圣域盾：24 MP，12 秒冷却；战斗中自身生命低于 72% 时施放，吸收 38 伤害，持续 6 秒。

受伤会打断未完成施法；施法已付出的法力、冷却不会退款。治疗优先于护盾和攻击；战斗内每秒回 1.4 MP，非战斗每秒回 4 MP，不被动回血。跟随作战会接敌，守卫留在锚点附近，停战跟随关闭主动攻击及支援施法；三种模式都可受伤。

倒下后停止移动、回蓝和技能，返回城镇、切换模式、重新招募或读同一存档都不会复活。旅店的 10 铜币休整恢复全队血蓝并复苏，满状态时不扣费。主角药水当前只作用于主角，不是给队友下达喝药命令。

招募沿用任务网：完成艾琳与雷恩的信任条件，经艾琳的「可以托付后背的人」约定邀请瑟琳。小队 HUD 显示血蓝/冷却/倒下，点击可打开图鉴；手册「冒险」页选择队友命令。

图鉴默认显示大立绘，可切换待机、移动、攻击、受击，瑟琳另有施法预览。尚未完整导入的动作显示「制作中」并禁用；缺文件不会用立绘冒充动画。待机/步行循环，攻击/受击/施法结束停留 650 ms 后重播。预览在世界暂停时独立播放，关闭图鉴立即停止；深浅底切换保持当前画面和时间，便于检查透明边缘。预览按完整固定画布及动作原点缩放，不逐帧裁切放大。

## 存档与测试

`game_runtime.snapshot()` 保存 `companion:{recruited,mode,state}`；state 由战斗服务生成，包含资源、护盾、冷却和动作进度。`validate_snapshot()` 在修改主角之前验证全部队友数据，拒绝越界、非有限数、真假字符串及招募/命令矛盾。旧存档完全没有 state 时迁移初始血蓝；新档含空 state 会被拒绝。重复读取不产生资源回复。

本轮已完成的 UI/runtime 专项结果：角色集成 64 项（包含已导入的瑟琳待机预览），原 runtime 61 项，基础存档验证 22 项，以及剧情集成和 Esc/L 菜单输入通过。独立资源门槛另有结构、坏数据及无损存储裁切的自身测试；这只证明验收脚本能拒绝坏数据，**不能代替实际素材复核；本次实际素材的最终通过证据见本文开头**。

```sh
python -m unittest discover -s godot-belt-map/tests -p test_validate_roster_assets.py -v
godot --headless --path godot-belt-map --script res://tests/roster_integration_test.gd -- --foundations
godot --headless --path godot-belt-map --script res://tests/menu_input_test.gd -- --foundations
godot --path godot-belt-map --script res://tests/roster_capture.gd -- --foundations --page=serin
godot --path godot-belt-map --script res://tests/roster_capture.gd -- --foundations --page=serin --action=stand --light
```

截图参数可使用任意角色 ID，或 `party` 查看有损血蓝及技能冷却 HUD，输出为 `captures/roster-<page>.png`。动画截图使用 `--action=stand|walk|attack|hurt|cast`，可加 `--light`，输出 `roster-<角色>-<动作>-dark|light.png`；请求尚未就绪动作会失败。没有美术时的图鉴占位提示和 fallback 截图不能作为最终角色证据。逐帧自动检查只覆盖画布边缘等结构问题；手臂与身体间白块、发丝污边、身份漂移、突然消失的武器、滑步或躯干僵硬仍必须看全动作。

## 本轮范围以外

当前为单机；无多人权威服务、账号或云存档。瑟琳的职业固定，尚无个人装备栏、独立升级或其他可招募职业。角色武器和衣装仍画在动作帧里，更换装备不能改变整套外观；随机装备实例/词缀及多套换装动画另行扩展。敌人死亡和瑟琳倒下没有单独生成的片段。古塔仍复用庭院背景，Windows/Web 检查不能代替 macOS 实机验收。
