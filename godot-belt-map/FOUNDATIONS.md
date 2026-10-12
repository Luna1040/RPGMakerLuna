# 庭院 RPG 底层与接入约定

2026-10-11。当前入口仍是 `project.godot` → `stage.tscn`。新增框架已经接到实际游戏；历史 `godot-*` 演示没有迁移。本轮另已接入独立队友资源与角色图鉴；五角色立绘与 21 个整帧动作已完成逐动作验收并接入，合计 351 张透明动作帧。

## 可玩的流程

1. 靠近艾琳或雷恩按 E，接受独立的补给、调查、清敌与波次任务。
2. 打碎木箱收集材料，或者选择支付铜币采购；分别向两位 NPC 询问线索。
3. 在修复结界、资助商队改道、公开调查结果之间作出承诺。三种方案互斥，结果保存在人物关系与世界标记里。完成补给与清敌两条支线也可以开启最终委托。路线确定后，先找雷恩接受「庭院守夜人」，再挑战首领；任务不追溯接取前的击杀。
4. L / Esc 打开冒险手册，进入古塔试炼场。在手册里开始本轮，攻击预警出现后走位或跳跃。
5. 三轮战斗有近战、远程、精英和首领；轮间三选一祝福。击败敌人后经验立即结算，实物战利品需要拾取。
6. 升级获得技能点，手册内分配三分支六项天赋。建立双方信任后，通过艾琳的同行约定邀请战牧瑟琳。她有独立血量、法力、圣光弹、治疗与护盾，敌人也会攻击她。
7. 清场后保存检查点，或者回城交付任务、采购药剂和锻造。死亡后可撤退保留已拾取战利品，或读取检查点。

默认增加 L 手册、Esc 暂停菜单、4 生命药水、5 法力药水。移动、跳跃、技能、交互等可在设置中重绑；方向键始终可移动。R 仅在城镇复位位置，不再免费恢复资源。技能点洗点暂时免费，只在城镇提供。

手册新增「角色图鉴」，浏览五位角色的立绘、职业和招式。招募后左上角的小队面板显示瑟琳的生命、法力、技能冷却与倒下状态，点击可打开她的图鉴。旅店休整恢复全队并复苏倒下的瑟琳，统一收取 10 铜币；全队生命、法力都满时不收费。返回城镇、切换命令或重复招募不会免费复活队友。

## 模块边界

| 模块 | 责任 | 主要接口 |
| --- | --- | --- |
| `stage.gd` | 现有地面坐标、碰撞、输入分发、渲染与明确的模拟步进 | `project`, `_physics_process`, `on_attack`, `on_spell` |
| `systems/game_runtime.gd` | 组合系统、角色快照、旅行、检查点、三轮试炼、祝福、任务事件 | `setup`, `snapshot`, `validate_snapshot`, `restore`, `travel`, `save_game`, `load_game` |
| `systems/session_bridge.gd` | 两个场景实例之间传递纯数据；不充当永久存档 | `pending`, `target_zone`, `take` |
| `systems/content/` | 技能/装备/NPC/任务/对话稳定 ID、Schema 校验、原子 Patch、覆盖状态与撤销 | `get_definition`, `registered_ids`, `apply_runtime_patch`, `export_runtime_state` |
| `systems/content/content_draft_service.gd` | Agent 任务/NPC/对话草稿的全目录校验、差异预览与不可变原子发布；不热激活当前战役 | `validate_draft`, `preview_draft`, `publish_draft` |
| `systems/content/campaign_import_service.gd` | 已发布制品的重新物化、独立战役预览、双文件原子安装与篡改复检；不激活当前会话 | `preview_import`, `install_campaign`, `inspect_campaign` |
| `systems/content/campaign_session_service.gd` | 安全列出已安装战役/槽位摘要；结束旧场景后在 bootstrap 中激活战役、失败回滚并切换独立存档目录 | `list_campaigns`, `preview_campaign_launch`, `start_campaign_session`, `start_official_session` |
| `systems/agent/authoring_orchestrator.gd` | 可信 Main Agent 状态机：拆分 World/Narrative/NPC/Systems，等待 Validator，合并已审查草稿并控制预览/发布 | `create_run`, `dispatch_ready_tasks`, `submit_agent_result`, `preview_run`, `publish_run` |
| `systems/agent/agent_transport_service.gd` | 可替换的 OpenAI-compatible HTTP 传输；会话/环境密钥、并发、超时、有界重试、取消和严格 JSON 回收 | `configure`, `run_ready_stage`, `list_jobs`, `cancel_job`, `capabilities` |
| `systems/workbench_bridge.gd` | 创作工作台能力查询、Main→子 Agent 合同审查、安全点排队与 Patch 结果 | `capabilities`, `inspect_target`, `validate_agent_task`, `review_agent_result`, `submit_patch` |
| `systems/world_registry.gd` | 地点 ID 到地图合同的映射 | `ZONES`, `load_zone` |
| `systems/core/save_store.gd` | 三槽、版本、校验和、临时文件、备份与坏档保护 | `save_slot`, `load_slot`, `list_slots`, `protect_slot` |
| `systems/core/progression.gd` | 经验曲线、50 级上限、每级技能点和固有属性成长 | `add_xp`, `bonuses`, `snapshot`, `restore` |
| `systems/core/talent_tree.gd` | 六天赋、三分支、前置与点数消费 | `can_spend`, `spend`, `refund`, `bonuses` |
| `systems/adventure/` | 数据驱动的任务网络、条件对话、声望、交易、制作、药剂 | `choose`, `record_event`, `claim_quest`, `buy`, `craft`, `narrative_graph` |
| `systems/encounters/` | 四种敌人行为、预警、伤害、硬直/感电/浮空、寻路与队友 | `begin_wave`, `step`, `hit`, `hit_projectile`, `set_companion_enabled` |
| `systems/event_bus.gd` | 统一事件名与最近 120 条事件追踪 | `publish`, `event_emitted` |
| `systems/game_settings.gd` | 按键去冲突、音量、全屏、镜头震动与本地配置 | `rebind`, `canonical`, `movement`, `save_settings` |
| `systems/game_audio.gd` | 六种原创合成提示音与八声部上限 | `play` |
| `systems/session_panel.gd` | 统一模态菜单和交互 | `open`, `close`, `is_open` |
| `systems/roster_catalog.gd` / `roster_panel.gd` | 五角色身份、立绘与职业招式图鉴 | `entry`, `portrait`, `from_kind`, `setup` |
| `systems/party_hud.gd` | 独立队友血蓝、倒下与技能冷却展示 | `setup`, `update_status` |
| `systems/encounters/roster_animation.gd` | 整帧 PNG 选帧、固定脚底原点、出手事件时间重映射 | `configure`, `sample`, `attack_time` |
| `systems/encounters/roster_actor_view.gd` | 瑟琳自己的整帧动画视图 | `set_combat_view` |

另有可独立复用、已测试的 `core/status_effects.gd`（减速、眩晕、感电、燃烧、流血、护盾）和 `core/loot_table.gd`（权重/概率/保底、注入 RNG）。当前敌人的感电和浮空仍通过已有 `dummy_reactions.gd` 路径推进，敌人掉落使用遭遇服务的种子；不要对同一对象同时推进两个状态时钟，也不要在接入通用掉落表后再发一次旧奖励。

## 模拟顺序与暂停

`stage` 是模拟时钟所有者：处理待结算死亡 → 检查模态暂停 → 玩家位移/高度 → 动作帧/命中事件 → 投射物 → NPC/木桩 → `runtime.step` → 敌人与队友。菜单期间双方动作、伤害、冷却和回蓝冻结。战斗服务没有隐式 `_process` 攻击计时器。装饰性喷泉、UI 与音频不属于战斗计时。

攻击查询使用米制 `(x, depth, z)`，不使用屏幕距离。玩家近战接 `encounters.hit`，法术接 `hit_projectile`。后者返回 true 意味着弹体已经被敌人或实体墙消耗，应立即销毁。敌人脚底参与 Y 排序，浮空高度独立于地面深度。

F2 保留实体碰撞显示，F4 增加敌人受击体；开发截图报告包含会话快照、遭遇快照和事件追踪。F3/F6/F7/F8 继续可用。网页发行版隐藏开发检查台。

## 存档约定

桌面三槽位于 Godot `user://rpg_saves/slot_1.json` 等；设置位于 `user://rpg_settings.cfg`。网页使用同一格式，存储于该站点的浏览器数据。清理站点数据、隐私模式或浏览器存储限制可能影响保留，不能当云存档。

保存角色生命/法力/朝向、装备拥有及槽位、材料、经验、天赋、任务事件去重记录、声望/路线/标记、药剂、队友模式与独立状态、试炼种子/波次/祝福，以及每个地点独立的已破坏木箱、已开宝箱和未拾取掉落。Node、Texture、Callable 不进入存档。新快照还保存不可伪造为当前目录的 `content_context`；项目、战役、内容哈希或 manifest 哈希任一不匹配都拒绝读取。没有该字段的旧档只在官方内容下兼容。

导入战役的槽位不使用 `user://rpg_saves`，而位于 `user://projects/<project_id>/campaigns/<campaign_id>/saves`。切换战役只创建新会话，不自动读取槽位，也不会把官方存档复制到自定义战役。

`companion.state` 保存瑟琳的 HP/MP、倒下、护盾、技能冷却和动作状态。资源不得越界，布尔字段不能用字符串替代，内外两层的招募开关与命令必须一致。加载先完成校验再修改任何角色；重复读取不会回血、回蓝或复活。上一版没有 `state` 字段的旧档按满状态迁移，仍保留原来的招募与命令；新档显式写入空 `state:{}` 会被拒绝。该字段由 `companion_snapshot()` 生成，不要由 UI 拼装。

只能在未战斗、站稳、动作结束且无玩家飞行投射物时保存。轮间检查点恢复不会重新发放已完成波次的奖励。完整敌人快照能力已留在遭遇服务中，但正式存档不保存半次攻击，降低时序恢复风险。

新启动不会自动覆盖已有角色的槽：优先选择空槽，全部已占用时需先读档或确认保存。自动保存每 45 秒尝试，失败后停用当前会话自动保存。手动覆盖已有槽需要二次点击。加载先验证所有子系统，再修改场景；坏档会锁定该槽，未来版本不会被静默降级覆盖。没有天赋字段的旧会话按空树迁移；必须满足已花点数 + 剩余点数 = 等级 − 1。

RNG 的 64 位 `state` 若需要持久化，转成字符串再写 JSON；Godot JSON 数字无法精确表示所有 64 位整数。

## 扩写内容

- **任务 / 剧情**：编辑 `systems/adventure/adventure_data.json`，使用稳定 ID，`all`/`any`/`excludes` 条件和 `graph_edges`。该文件由 `ContentRegistry` 与冒险服务双重校验；已经发布的任务 ID 不要改名。新增分支后运行引用/循环检查和三路线测试。所有效果通过服务方法结算，UI 不直接加声望或发奖励。
- **新地点**：在 `world_registry.gd` 注册 ID 与合同 JSON。合同沿用 `map-contract.json`；`town_npcs:false` 可关闭城镇 NPC/木桩，`chests` 提供每个地点自己的宝箱。位置、碰撞、掉落保存使用地点 ID 隔离。当前背景与镜头仍按 3072 像素宽的庭院规格，新尺寸需要同时更新镜头及背景逻辑。
- **新敌人**：扩展 `encounters.gd` 的 DEFINITIONS/roster，并提供 `assets/roster/<id>/portrait.png` 与 `animation.json`。当前 `melee → scout`、`ranged → caster`，另有 `elite`、`boss` 和队友 `serin`。保留脚底坐标、明确出手时刻、唯一死亡事件和伤害查询。不要在动画/UI 内直接奖励。素材工作流与 manifest 约定见仓库根目录 `CHARACTER_PIPELINE.md`、`NPC_ROSTER_INTEGRATION.md`。
- **新装备**：扩展 `content/base/equipment.json`，不要改动已经进入存档的装备 ID。当前库存是一种装备 ID 一份，不支持同名随机词缀实例；要引入随机词缀，先升级存档模型为实例 ID，再接装备 UI。
- **新成长**：天赋属性统一叠加到真实伤害与容量；刷新从装备、等级、天赋、本轮祝福重新求和，禁止对现有数值反复累加。
- **新输入**：在 `game_settings.gd` 注册动作并由 stage 分发。UI、技能栏读取当前键位，禁止修改一个键后保留旧键的隐藏攻击行为。
- **NPC 定义**：城镇站位、名称、环境对话与登记资产 ID 位于 `content/base/town_npcs.json`。JSON 不得出现 `res://` 路径；新资产必须先进入 `town_npcs.gd` 的 allowlist，再引用 `asset.*` ID。
- **Agent / 工作台修改**：Main Agent 先读取 `WorkbenchBridge.capabilities()` 和目标定义，使用 `agent-task/1` 派发子任务，再用 `review_agent_result` 审查 `agent-result/1`。审查不会自动执行；只有 Main Agent 选中的 `runtime-patch/1` 才能进入 `submit_patch`。当前雷光支持安全修改消耗、冷却、伤害、纵深宽度、弹射数和弹射半径；不接受生成脚本或资源路径。具体合同见 `systems/content/README.md`。
- **Agent 生成任务/NPC/对话**：结构变更使用 `content-draft/1`；Main Agent 先审查，再调用 `preview_content_draft` 检查完整候选目录和差异，最后用完全相同的草稿与令牌调用 `publish_content_draft`。发布只生成带校验和的不可变 JSON 制品，不会热激活当前战役或改写现有存档；新战役导入器必须再次校验。
- **导入生成战役**：使用 `campaign-import-request/1` 选择 `new_campaign` 或 `explicit_project_copy`，先预览、再安装。安装结果固定在 `user://projects/<project_id>/campaigns/<campaign_id>`，使用独立 `saves` 子目录，并声明 `new_session_only`；保留战役 ID、既有不同内容和损坏目录都不会被覆盖。
- **启动生成战役**：先调用 `preview_campaign_launch` 取得绑定包哈希的令牌并向玩家确认结束当前会话，再调用 `start_campaign_session`。服务先让旧 gameplay scene 退出，随后只在 `campaign_bootstrap.tscn` 中复检并提交内容切换，最后创建使用独立 SaveStore 的新 `stage.tscn`。不要直接调用注册表加载函数，也不要在当前场景加入“热刷新剧情”入口。
- **战役管理界面**：Esc 菜单的“战役”页只调用 `WorkbenchBridge.list_campaigns`。页面显示官方/自定义战役、来源草稿、三槽摘要和损坏包错误；选择后先预览，再要求二次确认结束当前会话。网页端应复用相同接口与确认语义，不能自行拼接 `user://` 路径。
- **AI 创作控制台**：Esc 菜单的“创作”页以 `authoring-run-request/1` 创建 Run。Main Agent 根据所选世界、地图、城镇、NPC、任务、好感、道具、装备与商店模块拆出子任务；外部模型只领取严格 `agent-task/1` JSON 并回填单个 `agent-result/1`。所有业务结果完成后才会开放 Validator；Validator 通过后才合并草稿。用户仍需明确点击预览并二次确认发布。当前控制台用剪贴板衔接外部 Agent，尚未绑定模型供应商或账号。
- **Agent Transport**：在“创作”页配置 OpenAI-compatible chat-completions endpoint 与模型。远程端点必须为 HTTPS；仅 localhost 可使用 HTTP；URL 不接受查询参数或凭据。API Key 使用 `RPG_AGENT_API_KEY` 环境变量或当前 Godot 进程内存，不进入 `agent_transport.cfg`、任务元数据或日志。点击“运行当前就绪 Agent 阶段”只运行当前依赖已满足的阶段；业务子 Agent 完成后仍需玩家再次明确启动 Validator。失败按配置执行最多三次指数退避重试，任务可以取消，迟到结果不能复活已取消 Run。

## 验证

2026-10-11 底层框架发行版曾完成 21 项检查（20 组测试与 1 项资源导入预检）；网页版验证过存档写入、整页刷新后读档、城镇与试炼切换、敌人生成、战斗暂停及撤退回城。本轮新增图鉴/队友集成测试 64 项通过，包含独立资源往返、倒下保存、坏数据原子拒绝、休整扣费、旧档迁移、UI 暂停及已导入的待机预览时钟/末帧停顿/缺帧保护；同时复验 runtime、剧情集成、存档验证及 Esc/L 输入。2026-10-12 Agent Transport 版共 32 项 Godot 回归（含资源导入预检）；测试覆盖 Main Agent 拆分、伪造角色拒绝、Validator 依赖闸门、四操作合并、预览/发布隔离，以及传输配置约束、密钥不落盘、异步分阶段派发、HTTP 429 有界重试、Markdown 围栏拒绝、取消与迟到结果隔离。角色资产继续通过 351 帧无损原稿比对、21 动作原生渲染与 4 个双朝向发弹检查；新会话与战役管理测试覆盖包篡改回滚、官方/自定义内容切换、真实 stage 消费、独立 SaveStore、跨上下文坏档拒绝、损坏包禁用、槽位摘要、二次确认及 UI 发起的 bootstrap 启动。详见根目录 NPC_ROSTER_INTEGRATION.md。

安装 Python 3 后可运行跨平台测试工具（Godot 路径换成自己的）：

```sh
python tests/run_tests.py --godot /path/to/godot --suite all
```

macOS 默认应用路径可用 `/Applications/Godot.app/Contents/MacOS/Godot`，Windows 用 Godot console exe。测试脚本也支持 `GODOT_BIN` 环境变量，日志在 `test-results/`，不会进入网页包。核心、内容草稿发布、独立战役导入、新会话战役启动、战役管理 UI、Agent 创作编排、Agent Transport、任务、遭遇、存档事务与真实场景的集成测试分开运行，旧庭院回归使用隔离模式避免读取玩家进度。仅测试脚本需要 `-- --foundations` 强制开启新框架；正常 F5 自动开启。

新增素材发布门槛（需要 Pillow）：

```sh
python tests/validate_roster_assets.py --source-root ../character-generation-research/h3-runtime/npc-roster-v1/export --output test-results/roster-assets.json
godot --path . --script res://tests/roster_capture.gd -- --foundations --page=serin
```

第一条必须返回成功且 `release_ready:true`，其中每个动作都要先经过深浅底透明度与整段动画的人工检查，并标注 `review_status:"visually_reviewed"`。`--allow-pending-review` 只能帮助生产中的结构检查，不能授权发布。截图可改 `--page=scout|caster|elite|boss|party`；快照输出到 `captures/roster-*.png`。静态截图不能代替检查步态、全身参与、循环接缝与真实出手时刻。

运行时可用动作统一的 `storage_crop` 去掉透明空白，但原稿保留 768×768，pivot/scale 不变，AtlasTexture 恢复原虚拟画布；不是逐帧缩放或裁切定位。验收要求四周 4px 完全透明，并通过 `--source-root` 逐像素验证 alpha 与可见 RGB。未和原稿比对的裁切集不会被判为可发布。

图鉴默认立绘，已导入动作可在页面内直接预览。加 `--action=stand --light` 可捕获浅底动作预览，输出例如 `roster-serin-stand-light.png`；缺动作会失败。深浅底切换不重置播放位置；待机/移动循环，其他动作末帧停 650 ms 后重播。图鉴关闭后预览时钟停止，世界战斗时钟在图鉴打开时保持暂停。

## 当前边界

这是一套单机可演示框架。瑟琳已具备独立生命、法力、职业技能、受击、倒下、寻路及保存；她的装备和升级仍未独立实现。四类敌人及瑟琳的五套独立美术已经有加载和整帧动画接口，但本轮生成结果必须通过完整验收后才算素材交付。没有新生成的死亡动作：敌人暂使用受击末帧淡出，瑟琳保留灰暗倒下标记等待复苏。

古塔场景复用庭院背景，不代表新地图美术完成。武器外观仍烘焙在角色帧里，换装只改变属性。创作控制台已经实现可信任务状态机、人工 JSON 通道和 OpenAI-compatible HTTP 适配器，但仓库没有预置供应商、模型或密钥，也尚未完成任何真实付费供应商的账号验收。传输任务与 Run 当前只存在于本次 Godot 进程，重启后不会恢复；World Agent 的地图输出仍是分析，不能生成可执行 Godot 场景，自动素材生成也未接入。联机权威服务器、账号与云同步、完整随机词缀、多人组队、正式剧情演出和移动触控尚未实现。现有通用服务为后续增加这些系统保留接入点。Windows / Web 本机验证不等于 macOS 实机验收。
