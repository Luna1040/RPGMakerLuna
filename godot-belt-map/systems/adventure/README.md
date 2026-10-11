# 庭院叙事、任务与经济

`adventure_state.gd` 是独立 `RefCounted` 服务，`adventure_data.json` 是内容目录，`adventure_catalog.gd` 在加载时校验内容与引用。服务不操作场景、输入、试炼生成器或存档文件；地图运行时负责这些连接。

## 初始化与事件

```gdscript
var adventure = preload("res://systems/adventure/adventure_state.gd").new()
adventure.set_up(knight.equipment, loot, progression)
adventure.notice.connect(show_notice)
adventure.changed.connect(refresh_journal)

# ID 必须在一次遭遇中唯一。下一次重开试炼使用新的遭遇前缀。
adventure.record_event("crate_destroyed", {"id": crate_id})
adventure.record_event("enemy_killed", {"id": encounter_id + ":" + enemy_id})
adventure.record_event("boss_killed", {"id": encounter_id + ":" + boss_id})
adventure.record_event("wave_cleared", {"id": encounter_id + ":wave:" + str(wave)})
```

只有已接受、未领取的任务推进事件目标。同一目标保存收到过的事件 ID，重载后也不会重复计数；木桩事件标记 `training: true` 或 `is_dummy: true`，不算敌人。不要给怪物死亡事件传多个数量；一次事件只计数一次。没有 ID 的事件无法去重。

物资目标读取 `loot.materials`，因此 `material_collected` 不需要额外累计。背包变化后刷新 UI 即可。补给委托领取时真正扣除木料与碎布；如果提前打光了箱子，可在艾琳对话中花 10 铜币采购替代物资。

## 可玩叙事网

- `courtyard_provisions`：艾琳的补给，独立委托。
- `courtyard_menace`：雷恩的试炼，独立清敌委托。
- `missing_supplies`：与两位 NPC 分别交谈收集线索。
- `clearance_waves`：独立三波委托，可跨遭遇累计。
- `supply_resolution`：一次性选择 `repair` / `bargain` / `investigate`。修复消耗木料与秘银，协商消耗铜币，追查需要两条线索。选择持久化后排除另外两条路线。
- `courtyard_finale`：上述任一分支开放首领委托；也可独立完成补给和清敌后直接开放，不强制选路线。各路线改变 NPC 台词与首领奖励。
- `companion_oath`：两位 NPC 信任均达到 2 后开放的可选同行约定，不阻塞主线。

战斗试炼入口始终存在，剧情条件只控制委托和报酬。要使首领击杀计入委托，先接受 `courtyard_finale` 再进入试炼。条件 DSL 支持 `all` / `any` / `excludes`、任务状态、世界旗标、分支选择、声望阈值与物资要求。目录校验拒绝任务前置循环、未知条件、无效引用与负数成本。

## UI 接口

所有变更操作返回 `{ok: bool, message: String, action: String}`（`accept_quest` 仅返回 `bool`），并发出 `notice`。不要因 UI 按钮显示可用就跳过调用结果检查：方法会重新检查状态和费用。

- `quest_rows()`：`id/title/description/npc_id/status/can_accept/can_claim/objectives/rewards/requires`。`status` 为 `locked/available/active/ready/claimed`；目标包含 `id/label/current/target/complete`。
- `accept_quest(id)` / `claim_quest(id)`：接取和领取。领取前验证物资、奖励空间；成功才扣费、记录已领取、授予 XP。重复调用不会重复奖励。
- `dialogue_for(npc_id)`：`npc_id/name/text/reputation/choices`。选项包含 `id/label/action/enabled/reason`。条件不满足的选项不列出，物资不足或交付未完成的选项保留并提供不可用原因。
- `choose(npc_id, choice_id)`：调用时重新核对选项条件。`action` 为 `shop/craft/journal/request_trial/recruit_companion` 时，由地图打开面板、开始试炼或呼叫同伴；其它效果已在服务内提交。
- `shop_rows()`：`id/name/description/kind/cost/owned/can_buy/reason`。`cost` 为物资到数量的字典；`owned` 对装备为布尔值，对药剂为数量。
- `recipe_rows()`：`id/name/cost/output/can_craft/reason`，`output` 为 `{kind,id,amount}`。
- `buy(item_id, quantity = 1)` / `craft(recipe_id)`：验证全部成本和空间后提交；独一装备已拥有则不扣费。药剂堆叠上限 99，钱包上限 999999。
- `use_consumable("healing_potion", actor)` / `use_consumable("mana_potion", actor)`：治疗 55 / 回蓝 45，满状态、倒地或空栈不消耗。建议映射按键 4 / 5。新游戏初始 2 瓶治疗、1 瓶法力药剂。
- `wallet()`：返回物资钱包快照。
- `graph_nodes()`：`id/kind/title/description/status/position`，`position` 为 `[列,行]`。选择节点另有 `npc_id/choice_id`。`selected/excluded` 可用金色/灰色显示分支结果。
- `narrative_graph()`：`title/nodes/edges/routes/flags/reputation`。边包含 `from/to/label/kind`，可分辨可选联系、汇流和共同前置。

## 持久化边界

`snapshot()` 返回版本 1 的 `quests/flags/reputation/routes/consumables`，包含已接受、已领取和事件凭据。钱包与装备由整局存档保存，避免多处复制。`restore(data)` 只变更服务自己的状态，不扣费、不发奖、不操作装备、钱包或 XP，适合先用候选实例验证再应用存档。它过滤未知 ID、限制计数与物品上限、修正矛盾路线旗标；错误顶层结构或版本返回 `false`，保留原状态。

可信本地存档可以恢复已领取状态；这不是联网防作弊系统。扩展目录时保留已有 ID，避免破坏旧存档。剧情菜单里不存在的一次性选项不可通过直接调用重新支付或换路线。

## 验证

```text
Godot --headless --path godot-belt-map --script res://tests/adventure_state_test.gd
Godot --headless --path godot-belt-map --script res://tests/adventure_integration_test.gd -- --foundations
```

覆盖交易失败不扣费、装备唯一性、堆叠上限、制作、接取前事件无效、重复事件与重复领取、跨局恢复、全部叙事分支、替代补给解法、同伴关系、药剂满状态/倒地限制，以及目录循环/引用错误。

集成测试实例化真实场景并点击 NPC 对话按钮，打碎真实木箱并拾取物资，驱动真实敌人死亡与三波事件，验证经验成长、结局、同伴、各菜单模态门禁，并通过临时目录中的真实存档文件往返恢复整个运行时。临时测试槽不会接触玩家存档，测试结束会清理。
