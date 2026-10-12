# 成员 B｜Godot 与游戏系统执行方案

## 1. 先确认你的岗位

你是团队里的 **Godot 与游戏系统负责人**。你的核心交付不是平台首页、AI Prompt 或剧情文案，而是：

> 把现有 2.5D RPG 试玩做成稳定、数据驱动、可保存、可加载、可回滚、可被创作工作台安全修改的 Godot 游戏模板。

Leader 分工中，B 的明确范围是：

- 角色移动、2.5D `x/depth/z` 空间、碰撞与遮挡。
- 战斗、技能、状态效果、敌人 AI、Boss 运行框架。
- 任务、对话、背包、装备和奖励结算。
- 存档、版本迁移、场景状态与唯一物品一致性。
- 关卡/房间加载、重试和局部重置。
- Godot 游戏与创作工作台之间的交互接口。
- 为 C 提供机器可读的内容 Schema，为 D 提供能在 Godot 中配置的模板，为 A 提供稳定的表现层事件。

你不负责：

- C 的账号、作品广场、AI/Codex 调用、后端队列和发布网站。
- D 的最终剧情、主支线文案、关卡内容和数值验收。
- A 的角色原画、Sprite、UI 视觉、动画和特效资产。

但你必须定义三者如何接入 Godot。B 是整个团队的“可执行合同负责人”。

## 1.1 已对照仓库确认的现状

本节基于私有仓库 `main` 分支当前快照（页面显示最新提交 `50139d5`）的只读检查。

- 当前主工程确实是 `godot-belt-map/`，目标 Godot 版本为 4.7.2。
- 工程约有 30 个 GDScript、约 3,673 行脚本；已经有战斗、碰撞、地图、NPC、掉落、装备 UI、开发检查台和多项回归测试。
- `stage.tscn` 目前只有一个挂载 `stage.gd` 的根 Node；`knight.tscn` 也主要依赖脚本在运行时创建内容。
- `project.godot` 非常精简，没有 Autoload，也没有正式 InputMap；大量输入直接判断 `KEY_*`。
- `stage.gd` 约 662 行，同时管理输入、2.5D 物理、角色、投射物、战斗分发、NPC、掉落、UI、镜头、截图和测试入口，已经形成 God Object。
- `knight.gd` 约 485 行，承担动画、连招、技能、资源、装备属性和动作事件；`SKILLS` 仍是脚本常量。
- `equipment.gd` 的物品目录是硬编码 `CATALOG`。它已有“临时文件写入后重命名”的安全保存意识，但 `stage.gd` 明确设置 `persistence_enabled=false`，庭院正式流程仍不保存装备进度。
- `world_loot.gd` 用内存 Dictionary 管理木箱、宝箱、掉落和材料，关闭游戏后重置。
- `town_npcs.gd` 直接写死艾琳和雷恩的位置、资源、头像与三页台词，还没有 NPC 定义、对话图、任务或日程接口。
- `map-contract.json` 是很好的内容合同起点：已有稳定物件 ID、`x/depth/z` 语义、体积、阻挡、站立和投影参数，应继续演进，不要推倒。
- `combat_query.gd`、`belt_physics.gd` 与现有测试已把命中、碰撞和场景表现做了初步分离，这是 B 应保留的边界。
- 已有 `combat_actor_test.gd`、`combat_stage_test.gd`、`world_loot_test.gd`、`atlas_test.gd` 等无界面测试。B 的重构必须让这些继续通过，再补新测试。
- `godot-ai-workbench/bridge/lab.mjs` 目前只是独立 Codex 实验：用硬编码 Prompt 生成 24×16 ASCII 海边村庄并检查 NPC 可达性；它还没有与 Godot 运行时连接，且包含特定 Windows Codex 路径回退。
- `godot-ai-workbench/bridge/schema/` 主要是 Codex App Server 自身协议 Schema，不是 RPG 内容 Schema。B 需要另外建立游戏内容与 Runtime Patch Schema。

因此你不应重写现有手感。正确路线是：

> 先用现有测试锁住试玩表现，再从 `stage.gd` 周边渐进抽出权威状态、内容注册表、任务/对话运行时、保存服务和工作台桥接。

## 2. 你的第一个真实目标

先不要同时做完整平台、大世界和肉鸽。第一个可交付纵向切片应当是：

1. 玩家在苍石庭院与 NPC 对话并接受任务。
2. 通过出口进入一个战斗房/旧水道。
3. 击败普通敌人和一个 Boss。
4. 奖励进入背包，可以装备并影响战斗。
5. 返回庭院后任务正确完成。
6. 关闭并重新打开游戏，任务、奖励、宝箱、Boss 和装备状态仍一致。
7. 工作台发送“把雷光改成最多弹射 3 个目标”的结构化 Patch。
8. Godot 校验 Patch，在安全点应用并重试当前房间。
9. 修改可以撤销，且不会重复发奖或破坏存档。

这条链路完成，才证明你们拥有“可许愿修改的 RPG 模板”，而不是两个互不相干的系统。

## 3. 先做架构，不先堆功能

### 3.0 针对当前仓库的拆分顺序

不要一次把 `stage.gd` 拆空。按以下顺序渐进迁移，每一步都保持现有试玩能运行：

| 当前文件 | 现状 | B 的第一步 |
|---|---|---|
| `stage.gd` | 662 行，承担几乎全部场景编排 | 先保留为 Composition Root；抽出 `GameState`、`SceneState`、`ProjectileRuntime` 和 `InteractionRuntime`，不先改物理手感 |
| `knight.gd` | 动作状态机可用，但技能字典写死 | 保留动作执行；把 `SKILLS` 转为 `SkillDefinition`，由 `ContentRegistry` 注入 |
| `equipment.gd` | 目录硬编码，只能保存装备小片段 | 把目录移到 `ItemDefinition`；Inventory/Equipment 状态进入统一 SaveService |
| `world_loot.gd` | 宝箱、木箱、掉落为 Session 状态 | 为每个物件保留现有 ID，增加 `SceneObjectState`，从 GameState 恢复 |
| `town_npcs.gd` | NPC、台词、位置硬编码 | 转为 `NpcDefinition + DialogueGraph + NpcSpawn`，先保持原台词和画面不变 |
| `map-contract.json` | 已具备稳定空间合同 | 升级 Schema，增加 `scene_id/spawn_points/portals/interactables/save_scope` |
| `map_interface.gd` | 背包、地图、对话共用一个 CanvasLayer | 保持展示；先改为订阅状态/事件，不允许 UI 直接结算奖励 |
| `godot-ai-workbench/bridge/lab.mjs` | 生成实验，无 Godot 连接 | C 继续维护生成端；B 只交付 `WorkbenchBridge.gd` 和游戏协议 |

建议先建立四个小型 Autoload：

```text
ContentRegistry
GameState
SaveService
WorkbenchBridge
```

`SceneRouter` 在出现第二个可玩场景时再设为 Autoload；领域事件优先使用具体 Runtime 的 signal，跨场景事件再引入 `DomainEventBus`，避免过早形成另一个全局 God Object。

### 3.1 目标 Autoload

最终可演进为：

```text
EventBus            全局领域事件，不承载具体业务状态
GameState           当前战役权威状态与 state_version
ContentRegistry     根据稳定 ID 查找技能、物品、任务、对话和场景定义
SaveService         原子保存、加载、备份、迁移
SceneRouter         场景/房间切换、异步加载、安全重试点
WorkbenchBridge     与网页工作台交换能力、选择对象、快照、Patch 和执行结果
```

不要把所有逻辑都塞进一个 `GameManager.gd`。具体战斗、任务和背包逻辑使用普通 Node/Resource/服务类，通过明确事件交互。

### 3.2 推荐目录

仓库实际结构可不同，但职责要保持：

```text
res://
  core/
    events/
    state/
    content/
    save/
    bridge/
    validation/
  gameplay/
    actors/
    combat/
    abilities/
    status_effects/
    ai/
    inventory/
    equipment/
    quests/
    dialogue/
    interaction/
  world/
    scenes/
    rooms/
    portals/
    maps/
  ui/
  content/
    base/
    official_demo/
    schemas/
  tests/
    unit/
    integration/
    fixtures/
```

### 3.3 官方内容和生成内容分开

- 官方内置内容：优先使用有类型的 Godot `Resource`（`.tres`）和 `PackedScene`，便于编辑器检查与资源引用。
- AI/平台生成内容：通过 JSON DTO 进入，先做 Schema、ID、范围和能力校验，再转换为运行时对象。
- 不允许 AI 直接生成并运行 `.gd`、`.tscn` 字符串、Shader、表达式或任意资源路径。
- 首版 UGC 只允许使用白名单组件组合：技能参数、任务图、对话图、敌人配置、房间模板、掉落表和已登记资产。
- 新机制和新代码必须走独立分支、构建和测试，不能在玩家战斗中热执行。

## 4. 必须先定下来的数据合同

B 先写 Schema，C 才能让 AI 输出正确数据，D 才能用同一种格式做官方内容。

### 4.1 内容包

```json
{
  "schema_version": "rpg-content/1",
  "project_id": "project-demo",
  "content_version": 7,
  "bundle_id": "zone-courtyard-v7",
  "bundle_type": "zone",
  "entry_scene_id": "scene.courtyard",
  "dependencies": [],
  "payload": {
    "scenes": [],
    "actors": [],
    "skills": [],
    "items": [],
    "quests": [],
    "dialogues": [],
    "encounters": []
  },
  "asset_ids": [],
  "content_hash": "sha256:..."
}
```

硬规则：

- 所有持久对象有稳定 ID，显示名称不能作为引用键。
- 引用必须能在当前包、依赖包或基础注册表中解析。
- 所有修改带 Schema 版本和内容版本。
- 旧 ID 不能随意删除；使用迁移表或 Tombstone。

### 4.2 技能定义

```json
{
  "skill_id": "skill.knight.lightning",
  "display_name": "雷光",
  "action_profile_id": "action.knight.cast",
  "resource_cost": {"type": "mp", "amount": 25},
  "cooldown_ms": 4500,
  "damage_profile_id": "damage.lightning.basic",
  "targeting_profile_id": "target.forward_nearest",
  "effect_profile_ids": ["effect.shocked"],
  "chain_count": 1,
  "chain_radius_m": 0.0,
  "vfx_id": "vfx.lightning.basic",
  "sfx_id": "sfx.lightning.basic"
}
```

AI 只能修改白名单字段，例如 `chain_count`、`cooldown_ms`、`damage_profile_id`，不能直接改动画脚本或调用任意函数。

### 4.3 任务定义

```json
{
  "quest_id": "quest.courtyard.sewer_guard",
  "initial_state": "available",
  "states": ["hidden", "available", "active", "completed", "failed"],
  "objectives": [
    {"objective_id": "enter_sewer", "type": "enter_scene", "target_id": "scene.sewer"},
    {"objective_id": "defeat_guard", "type": "defeat_actor", "target_id": "enemy.sewer_guard"}
  ],
  "transitions": [],
  "rewards": [
    {"type": "grant_item", "item_id": "item.guard_blade", "count": 1}
  ]
}
```

任务 Runtime 只消费领域事件：`dialogue_choice`、`scene_entered`、`actor_defeated`、`item_obtained`、`interaction_completed`。不要让任务脚本直接查找场景里某个名字固定的 Node。

### 4.4 场景/房间定义

```json
{
  "scene_id": "scene.sewer.room_01",
  "packed_scene_id": "scene_template.side_belt_room",
  "projection": "side_facing_belt",
  "bounds": {"x": 0, "depth": 0, "width": 24, "depth_size": 8},
  "spawn_points": [],
  "portals": [],
  "interactables": [],
  "encounter_ids": [],
  "save_scope": "scene_persistent"
}
```

保留试玩版的空间合同：`x` 为横向位置，`depth` 为地面纵深，`z` 为跳跃高度；碰撞使用脚底/实体基座，而不是 Sprite 完整透明矩形。

## 5. Godot 运行系统怎么拆

### 5.1 战斗

你负责确定性执行：

- 输入缓冲、动作状态机、三段连击。
- 奔跑攻击、空中攻击、闪避或防御。
- Hitbox/Hurtbox、受击、击退、纵深击退、浮空和硬直。
- MP、冷却、状态效果和战斗 RNG。
- 敌人状态机：待机、巡逻、警戒、追击、攻击、受击、回撤、死亡。
- Boss 阶段切换和可读前摇。

表现层只监听事件：

```text
action_started
hit_confirmed
damage_applied
status_applied
actor_launched
actor_defeated
skill_cooldown_changed
```

A 可以根据事件播放动画、VFX、SFX、镜头和 UI；表现失败不能改变战斗结算。

### 5.2 背包与装备

- 物品用 `item_id + instance_id` 区分定义和实例。
- 拾取、穿戴、卸下、购买、制作和奖励必须是原子事务。
- 唯一物品只能有一个合法归属。
- 装备属性由统一 Stat Modifier 管线计算，UI 不自己算属性。
- 装备变化发出 `equipment_changed`，让 A 的外观层同步武器/服装。

### 5.3 任务与对话

- 任务是有限状态机，不是散落的布尔变量。
- 对话是有稳定节点 ID 的图，条件只使用白名单 Predicate。
- 对话选择先产生事件，任务系统结算后再进入下一节点。
- 奖励只由 RewardService/WorldReducer 发放，对话文本无权直接塞物品。
- 重进对话、重复网络响应和读档都不能重复奖励。

### 5.4 存档

保存内容至少包含：

- 玩家属性、技能、背包、装备和货币。
- 当前场景、重生点和安全重试点。
- 任务状态、目标进度和已领过的奖励。
- NPC 持久状态、关系引用和关键记忆 ID。
- 已开宝箱、已破坏物、Boss 死亡、门和机关。
- 商店库存与补货时间。
- `schema_version`、`content_version`、`state_version` 和随机流状态。

写入流程：

```text
生成快照
→ 写入临时文件
→ 重新读取并校验
→ 替换正式存档
→ 保留上一个有效备份
```

导出项目中持久数据写 `user://`，不要写 `res://`。Web 端还要真实测试刷新、关闭页面、清理站点数据和升级内容版本后的行为。

### 5.5 场景加载与房间重试

- `SceneRouter` 管理 Portal、入口点、加载画面和状态恢复。
- 使用异步/线程加载接口，避免大场景卡住战斗主线程。
- 每个房间定义进入快照与安全重试点。
- “重试当前房间”恢复进入房间时的战斗状态，但不回滚已经确认的战役级事务。
- Boss 调试支持从门口重试，不要求每次重新跑完整章节。

## 6. 你和 C 之间的工作台接口

C 负责许愿服务和平台；B 只负责 Godot 端协议与执行。不要让 Godot 直接把自然语言交给某段游戏脚本执行。

### 6.1 Godot 向工作台报告

```text
runtime_ready
  runtime_api_version
  schema_versions
  build_id
  supported_patch_ops
  supported_content_types

selection_changed
  project_id
  scene_id
  entity_type
  entity_id

context_snapshot
  state_version
  current_scene
  selected_entity
  relevant_definitions
  recent_domain_events

patch_result
  transaction_id
  status
  new_state_version
  errors
  warnings
```

### 6.2 工作台可以向 Godot 发送

```text
request_context
validate_bundle
validate_patch
apply_patch
reload_scope
restart_current_room
create_checkpoint
rollback_to_checkpoint
```

### 6.3 Patch 示例

```json
{
  "schema_version": "rpg-patch/1",
  "transaction_id": "txn-1042",
  "idempotency_key": "wish-551-apply-1",
  "base_state_version": 87,
  "safe_apply_point": "room_restart",
  "operations": [
    {
      "op": "set",
      "entity_type": "skill",
      "entity_id": "skill.knight.lightning",
      "path": "chain_count",
      "from": 1,
      "value": 3
    },
    {
      "op": "set",
      "entity_type": "skill",
      "entity_id": "skill.knight.lightning",
      "path": "chain_radius_m",
      "from": 0.0,
      "value": 4.0
    }
  ],
  "reload_scope": "current_room"
}
```

Godot 端执行顺序：

```text
校验 Schema
→ 校验 base_state_version
→ 校验目标 ID 与字段白名单
→ 校验数值范围和依赖能力
→ 生成预览差异
→ 到达 safe_apply_point
→ 创建回滚点
→ 原子应用
→ 重载指定范围
→ 运行冒烟测试
→ 返回 COMMITTED 或整体回滚
```

Web 工作台嵌入 Godot Web 时，可以使用固定 JavaScript 接口或 `postMessage` 桥接；Godot 侧用 `JavaScriptBridge` 包装已定义函数和回调。禁止使用 `JavaScriptBridge.eval()` 执行 AI 返回内容。原生构建可复用相同消息对象，通过 HTTP/WebSocket/本地 IPC 传输。

## 7. 内容加载的安全边界

首版建议两级内容：

1. **普通生成内容**：JSON + 已登记资产 ID，只能组合现成组件，直接进入预览。
2. **受信构建内容**：经过 CI 构建、测试和签名的 PCK/ZIP，用于官方更新或审核后的扩展。

不要让公共作品直接上传一个带脚本的 PCK 后在客户端运行。Godot 官方文档明确提醒资源包可能携带恶意代码、覆盖同路径资源；加载顺序和 `replace_files` 也会造成覆盖风险。公共 UGC 应隔离命名空间、校验哈希/签名，并默认禁止脚本。

推荐路径：

```text
user://projects/<project_id>/
  manifest.json
  versions/<content_version>/
  saves/<campaign_id>/
  checkpoints/
  cache/
```

发布作品和官方主线必须使用不同的 `project_id/campaign_id`。创作世界中生成的神装不能直接进入官方战役；跨作品奖励只接受平台批准的外观、称号或收藏数据。

## 8. 四周执行顺序

### 第 1 周：盘点与合同

- 使用仓库中的 `godot-belt-map/` 源项目，不以 Web 导出 PCK 作为开发源。
- 固定当前 Godot 版本，不在同一迭代顺便升级引擎。
- 以当前已确认的 30 个 GDScript、`stage.tscn`、`knight.tscn`、`map-contract.json` 和导出预设为基线。
- 给试玩现有功能做回归表：移动、奔跑、跳跃、三连、冲刺斩、空中斩、技能、木桩、木箱、宝箱、背包、地图、NPC。
- 建立稳定 ID、EventBus、ContentRegistry 和 Schema 草案。
- 与 C 确认消息协议；与 D 确认任务/对话/关卡编辑格式；与 A 确认动画和 VFX 事件。

交付：架构图、Schema 样例、试玩回归清单和能跑的稳定基线分支。

### 第 2 周：数据驱动和存档底座

- 把至少一个技能、一件装备、一个敌人和一个宝箱改为由定义数据驱动。
- 实现 GameState、SaveService、备份和版本字段。
- 保存并恢复装备、任务测试状态、宝箱和场景对象。
- 实现 Patch Validator 和一次原子参数修改。

交付：修改 JSON 后可改变“雷光”参数；刷新游戏后状态正确；非法字段被拒绝。

### 第 3 周：任务、对话与战斗房

- 实现任务 FSM、Predicate、Reward 和领域事件。
- 实现最小对话图与任务接受。
- 实现庭院到战斗房的 SceneRouter。
- 实现一个普通敌人和一个 Boss 基础状态机。

交付：20–30 分钟纵向切片的系统闭环，不要求最终美术和完整文案。

### 第 4 周：工作台闭环

- 实现选中对象、上下文快照、Patch 预检、应用、房间重试和回滚。
- 接 C 的最小工作台 Stub；没有后端时先用本地 JSON 模拟。
- 实现“雷光 → 连锁雷光”的完整修改演示。
- 增加冒烟测试、日志和错误码。

交付：游玩中选择技能 → 工作台修改 → 安全应用 → 重试房间 → 撤销。

## 9. 今天就能开始的任务

按这个顺序做，不要先写 Boss：

1. 安装 Git LFS，正常克隆而不是使用网页 ZIP；运行 `git lfs pull` 后确认 PNG/WebP 不是约 130 字节的 LFS 指针。
2. 用 Godot 4.7.2 打开 `godot-belt-map/project.godot`，先运行现有全部 smoke/test，再导出一次 Web。
3. 建立自己的功能分支，例如 `feature/b-runtime-foundation`。
4. 不改动作数值，先给 `stage.gd`、`knight.gd`、`equipment.gd`、`world_loot.gd` 和 `town_npcs.gd` 补一张依赖图。
5. 将直接使用的 `KEY_*` 映射为 InputMap Action，同时保留旧键位作为默认绑定。
6. 新建 `ContentRegistry`，只把“雷光”一项从 `knight.gd` 的 `SKILLS` 常量迁成外部定义；其余技能暂时不动。
7. 新建 `GameState` 和 `SaveService`，先接管 `equipment.gd` 已有保存能力，再扩展到宝箱与木箱。
8. 给 `map-contract.json` 写版本化校验器；非法坐标、重复 ID、缺失资源和不可达交互物必须拒绝。
9. 新建最小 `PatchValidator`，只允许修改雷光的 `chain_count/chain_radius_m` 等白名单字段。
10. 用本地 JSON 模拟 C 的平台消息，不等 C 后端完成，并录制“旧雷光 → 应用 Patch → 连锁雷光 → 撤销”。

### 9.1 建议的前四个 PR

#### PR B-01：`runtime-contract-foundation`

新增建议：

```text
godot-belt-map/core/content/content_registry.gd
godot-belt-map/core/state/game_state.gd
godot-belt-map/core/save/save_service.gd
godot-belt-map/core/validation/content_validator.gd
godot-belt-map/content/schemas/content-bundle.schema.json
godot-belt-map/content/schemas/runtime-patch.schema.json
godot-belt-map/content/base/skills.json
godot-belt-map/tests/content_registry_test.gd
```

只迁移雷光定义。验收：旧试玩表现和数值完全一致；无效 JSON、重复 ID、未知资源被拒绝；原测试全部通过。

#### PR B-02：`campaign-save-and-scene-state`

将 `equipment.gd`、`world_loot.gd` 的权威状态移入统一快照；宝箱、木箱、材料、Owned/Equipped 均可保存。验收：打开宝箱、拿装备、打碎木箱后重启，状态不重复、不丢失。

#### PR B-03：`npc-dialogue-quest-runtime`

把 `town_npcs.gd` 的两名 NPC 与台词迁入定义；加入最小对话图、任务 FSM、领域事件和一次性奖励。验收：艾琳发布任务，完成目标后只发一次奖励，存档恢复可继续。

#### PR B-04：`workbench-runtime-bridge`

新增 Godot 端 `WorkbenchBridge.gd`、Capability、ContextSnapshot、RuntimePatch 和 PatchResult；先接本地 Stub，再接 C。验收：选择雷光、获取上下文、预检、应用、重试房间、撤销完整可用。

## 10. 验收标准

### 系统验收

- 相同输入与随机种子产生一致战斗结果。
- 任务奖励、购买和拾取在重试/断线后不会重复。
- 过期 `base_state_version` 的 Patch 被拒绝。
- Patch 中未知 ID、未知字段、越界值和任意路径被拒绝。
- 应用失败时不留下半个修改。
- 重新加载后任务、装备、宝箱、Boss 和场景对象一致。
- 旧存档有迁移方案；迁移失败保留原文件。
- 工作台断开时，现有游戏仍可移动、战斗、保存和加载。

### 试玩回归

- WASD/方向键、双击奔跑、空格、J、1–3/K、E、Q、I、M、R 语义不退化。
- 三段攻击、冲刺攻击和空中攻击不互相覆盖。
- 技能 MP 和冷却只结算一次。
- 木桩击飞、浮空、感电和追击正确。
- `x/depth/z` 分离；树冠、武器透明区不产生虚假碰撞。
- 地图标记指向真实对象；宝箱开关状态与存档一致。

### 工作台验收

- 选中对象能返回稳定 `entity_id` 和最小相关上下文。
- 自然语言只在 C 的服务层处理；Godot 只接收结构化、可校验 Patch。
- 修改只能在声明的安全时机应用。
- 每次修改有事务 ID、幂等键、版本和错误信息。
- 可以应用、重试、撤销，并恢复到上一个有效状态。

## 11. 与其他成员的接口

### A（美术与表现）需要你提供

- 动画状态名、事件时间点、Pivot、碰撞足迹和资源命名规范。
- `action_started/hit_confirmed/status_applied` 等稳定信号。
- 角色装备外观层和 VFX/SFX Slot。
- 美术资源缺失时的 Placeholder 和回退行为。

### C（平台与 AI）需要你提供

- `CLIENT_CAPABILITIES`。
- 内容与 Patch JSON Schema。
- 上下文快照字段和最大大小。
- Patch 校验错误码、安全应用点和回滚命令。
- Godot Web 的固定 JS 接口；不要让 C 猜 NodePath 或直接写场景树。

### D（策划与关卡）需要你提供

- 可在 Inspector/Resource 中配置的技能、敌人、任务、对话、掉落和房间模板。
- 一套官方示例与字段说明。
- 验证工具：缺失引用、不可达出口、重复奖励和非法条件检查。
- Boss 调试入口、房间重试、事件日志和数值调试面板。

## 12. 当前验证限制

已经通过登录后的私有 GitHub 页面取得仓库快照并完成源代码盘点，但网页 ZIP 中的大型 PNG/WebP 是 Git LFS 指针；当前机器也没有可调用的 Godot 4.7.2 与 Git LFS。因此本轮能够确认代码结构和数据流，不能声称已在这个仓库快照上运行 Godot 测试。B 开始开发时必须使用正常 Git LFS 克隆并先跑现有测试。

## 13. 参考资料

- [Godot：运行时文件加载与保存](https://docs.godotengine.org/en/stable/tutorials/io/runtime_file_loading_and_saving.html)
- [Godot：保存游戏](https://docs.godotengine.org/en/stable/tutorials/io/saving_games.html)
- [Godot：ResourceLoader 与后台加载](https://docs.godotengine.org/en/stable/classes/class_resourceloader.html)
- [Godot：导出和加载 PCK/ZIP，以及安全注意事项](https://docs.godotengine.org/en/stable/tutorials/export/exporting_pcks.html)
- [Godot：HTTPRequest](https://docs.godotengine.org/en/stable/classes/class_httprequest.html)
- [Godot Web：JavaScriptBridge](https://docs.godotengine.org/en/stable/tutorials/platform/web/javascript_bridge.html)
