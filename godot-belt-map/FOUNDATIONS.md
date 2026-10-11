# 庭院 RPG 底层与接入约定

2026-10-11。当前入口仍是 `project.godot` → `stage.tscn`。新增框架已经接到实际游戏；历史 `godot-*` 演示没有迁移。

## 可玩的流程

1. 靠近艾琳或雷恩按 E，接受独立的补给、调查、清敌与波次任务。
2. 打碎木箱收集材料，或者选择支付铜币采购；分别向两位 NPC 询问线索。
3. 在修复结界、资助商队改道、公开调查结果之间作出承诺。三种方案互斥，结果保存在人物关系与世界标记里。完成补给与清敌两条支线也可以开启最终委托。路线确定后，先找雷恩接受「庭院守夜人」，再挑战首领；任务不追溯接取前的击杀。
4. L / Esc 打开冒险手册，进入古塔试炼场。在手册里开始本轮，攻击预警出现后走位或跳跃。
5. 三轮战斗有近战、远程、精英和首领；轮间三选一祝福。击败敌人后经验立即结算，实物战利品需要拾取。
6. 升级获得技能点，手册内分配三分支六项天赋。建立双方信任后，通过艾琳的同行约定招募支援幻影。
7. 清场后保存检查点，或者回城交付任务、采购药剂和锻造。死亡后可撤退保留已拾取战利品，或读取检查点。

默认增加 L 手册、Esc 暂停菜单、4 生命药水、5 法力药水。移动、跳跃、技能、交互等可在设置中重绑；方向键始终可移动。R 仅在城镇复位位置，不再免费恢复资源。技能点洗点暂时免费，只在城镇提供。

## 模块边界

| 模块 | 责任 | 主要接口 |
| --- | --- | --- |
| `stage.gd` | 现有地面坐标、碰撞、输入分发、渲染与明确的模拟步进 | `project`, `_physics_process`, `on_attack`, `on_spell` |
| `systems/game_runtime.gd` | 组合系统、角色快照、旅行、检查点、三轮试炼、祝福、任务事件 | `setup`, `snapshot`, `validate_snapshot`, `restore`, `travel`, `save_game`, `load_game` |
| `systems/session_bridge.gd` | 两个场景实例之间传递纯数据；不充当永久存档 | `pending`, `target_zone`, `take` |
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

另有可独立复用、已测试的 `core/status_effects.gd`（减速、眩晕、感电、燃烧、流血、护盾）和 `core/loot_table.gd`（权重/概率/保底、注入 RNG）。当前敌人的感电和浮空仍通过已有 `dummy_reactions.gd` 路径推进，敌人掉落使用遭遇服务的种子；不要对同一对象同时推进两个状态时钟，也不要在接入通用掉落表后再发一次旧奖励。

## 模拟顺序与暂停

`stage` 是模拟时钟所有者：处理待结算死亡 → 检查模态暂停 → 玩家位移/高度 → 动作帧/命中事件 → 投射物 → NPC/木桩 → `runtime.step` → 敌人与队友。菜单期间双方动作、伤害、冷却和回蓝冻结。战斗服务没有隐式 `_process` 攻击计时器。装饰性喷泉、UI 与音频不属于战斗计时。

攻击查询使用米制 `(x, depth, z)`，不使用屏幕距离。玩家近战接 `encounters.hit`，法术接 `hit_projectile`。后者返回 true 意味着弹体已经被敌人或实体墙消耗，应立即销毁。敌人脚底参与 Y 排序，浮空高度独立于地面深度。

F2 保留实体碰撞显示，F4 增加敌人受击体；开发截图报告包含会话快照、遭遇快照和事件追踪。F3/F6/F7/F8 继续可用。网页发行版隐藏开发检查台。

## 存档约定

桌面三槽位于 Godot `user://rpg_saves/slot_1.json` 等；设置位于 `user://rpg_settings.cfg`。网页使用同一格式，存储于该站点的浏览器数据。清理站点数据、隐私模式或浏览器存储限制可能影响保留，不能当云存档。

保存角色生命/法力/朝向、装备拥有及槽位、材料、经验、天赋、任务事件去重记录、声望/路线/标记、药剂、队友模式、试炼种子/波次/祝福，以及每个地点独立的已破坏木箱、已开宝箱和未拾取掉落。Node、Texture、Callable 不进入存档。

只能在未战斗、站稳、动作结束且无玩家飞行投射物时保存。轮间检查点恢复不会重新发放已完成波次的奖励。完整敌人快照能力已留在遭遇服务中，但正式存档不保存半次攻击，降低时序恢复风险。

新启动不会自动覆盖已有角色的槽：优先选择空槽，全部已占用时需先读档或确认保存。自动保存每 45 秒尝试，失败后停用当前会话自动保存。手动覆盖已有槽需要二次点击。加载先验证所有子系统，再修改场景；坏档会锁定该槽，未来版本不会被静默降级覆盖。没有天赋字段的旧会话按空树迁移；必须满足已花点数 + 剩余点数 = 等级 − 1。

RNG 的 64 位 `state` 若需要持久化，转成字符串再写 JSON；Godot JSON 数字无法精确表示所有 64 位整数。

## 扩写内容

- **任务 / 剧情**：编辑 `systems/adventure/adventure_data.json`，使用稳定 ID，`all`/`any`/`excludes` 条件和 `graph_edges`。已经发布的任务 ID 不要改名；新增分支后运行目录引用/循环检查和三路线测试。所有效果通过服务方法结算，UI 不直接加声望或发奖励。
- **新地点**：在 `world_registry.gd` 注册 ID 与合同 JSON。合同沿用 `map-contract.json`；`town_npcs:false` 可关闭城镇 NPC/木桩，`chests` 提供每个地点自己的宝箱。位置、碰撞、掉落保存使用地点 ID 隔离。当前背景与镜头仍按 3072 像素宽的庭院规格，新尺寸需要同时更新镜头及背景逻辑。
- **新敌人**：扩展 `encounters.gd` 的 DEFINITIONS/roster 或替换其绘制视图，保留脚底坐标、明确出手时刻、唯一死亡事件和伤害查询。不要在动画/UI 内直接奖励。
- **新装备**：扩展 `characters/first_knight/equipment.gd` 的 CATALOG。当前库存是一种装备 ID 一份，不支持同名随机词缀实例；要引入随机词缀，先升级存档模型为实例 ID，再接装备 UI。
- **新成长**：天赋属性统一叠加到真实伤害与容量；刷新从装备、等级、天赋、本轮祝福重新求和，禁止对现有数值反复累加。
- **新输入**：在 `game_settings.gd` 注册动作并由 stage 分发。UI、技能栏读取当前键位，禁止修改一个键后保留旧键的隐藏攻击行为。

## 验证

2026-10-11 完整回归为 21 项通过（20 组测试与 1 项资源导入预检）；随后三项集成复验全部通过。网页版另外人工验证了存档写入、整页刷新后读档、城镇与试炼切换、敌人生成、战斗暂停及撤退回城。验证基于 Windows / 本机浏览器，未代替 macOS 实机验收。

安装 Python 3 后可运行跨平台测试工具（Godot 路径换成自己的）：

```sh
python tests/run_tests.py --godot /path/to/godot --suite all
```

macOS 默认应用路径可用 `/Applications/Godot.app/Contents/MacOS/Godot`，Windows 用 Godot console exe。测试脚本也支持 `GODOT_BIN` 环境变量，日志在 `test-results/`，不会进入网页包。核心、任务、遭遇、存档事务与真实场景的集成测试分开运行，旧庭院回归使用隔离模式避免读取玩家进度。仅测试脚本需要 `-- --foundations` 强制开启新框架；正常 F5 自动开启。

## 当前边界

这是一套单机可演示框架。敌人使用代码绘制的占位外观；队友是复用主角动作的无敌支援幻影，尚非有独立生命/装备的完整角色。古塔场景复用庭院背景，不代表新地图美术完成。武器外观仍烘焙在角色帧里，换装只改变属性。

联机权威服务器、账号与云同步、完整随机词缀、多人组队、正式剧情演出、移动触控和新的角色美术没有伪装成已完成。现有通用服务为后续增加这些系统保留明确接入点。Windows / Web 本机验证，macOS 仍需实机验收。
