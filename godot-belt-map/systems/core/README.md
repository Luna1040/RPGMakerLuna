# 通用游戏核心

这些模块是 `RefCounted`，不创建节点、不依赖场景、没有隐式全局单例。通过 `preload(...).new()` 构造，场景只负责把实际游戏状态传入。全部时间推进来自调用方；暂停游戏时停止 `step(delta)` 即可。

## 存档 `save_store.gd`

```gdscript
const SaveStore = preload("res://systems/core/save_store.gd")
var saves = SaveStore.new() # 可传入自定义目录，默认 user://rpg_saves
var ok = saves.save_slot(1, {"progression": progression.snapshot()})
var result = saves.load_slot(1)
if result.ok:
	progression.restore(result.data.progression)
else:
	print(result.error) # 不要在这里把默认角色保存回失败的槽位
```

- 槽位为 **1、2、3**。`list_slots()` 始终返回三个概要，包含 `slot / exists / ok / recovered / error / metadata`。
- `load_slot()` 返回 `ok / data / error / recovered / metadata`。加载只读；错误时不修改磁盘，也不会返回部分角色数据。
- 元数据包含 `slot / version / created_at / updated_at`，时间为 Unix 秒。
- 同目录 `.tmp` 写入、flush、重新校验后提交；之前有效主档通过 `.bak.tmp` 原子替换为 `.bak`。不先删除旧主档。主档损坏或缺失时读取备份，`recovered=true`；恢复后再次保存也保留有效备份。
- 新版本主档不会静默降级到旧备份。未来版本和没有有效备份的坏档不能被默认数据覆盖。失败的非空槽加载还会加上本次运行的自动保存保护，成功修复加载后自动解除；`acknowledge_failed_load(slot)` 只解除会话锁，并不会绕过坏档/未来版本保护。
- 检查根结构、版本、槽号、时间、SHA-256 内容校验、最大 8 MiB、递归深度和 JSON 类型。只支持字符串字典键；拒绝对象、Vector、NaN/Infinity、循环引用。
- Godot JSON 的数字读取为浮点数。载入各子系统时明确转回需要的整数；超过精确 JSON 范围的整数拒绝保存。**RNG 的 64 位 `seed/state` 用 `str(value)` 保存、`int(value)` 恢复**。
- 业务状态恢复应由上层先验证所有子系统，再提交到当前角色；存档容器不猜测角色/任务的数据格式。

## 成长 `progression.gd`

- `level / xp / skill_points` 从 `1 / 0 / 0` 开始。`xp` 是当前等级内经验。
- `add_xp(amount)` 可连续升级，返回 `levels_gained / level / xp / skill_points / accepted_xp`；负经验忽略，最多 50 级，每升一级获得一点技能点。
- `xp_to_next()` 是当前等级的升级门槛，满级为 0。`threshold_for(level)` 提供指定等级门槛。
- `bonuses()` 返回与装备相同的加法属性键：`health / mana / attack / magic / defense`。每升一级分别增加 `8 / 3 / 2 / 2 / 1`。上层叠加到基础属性与装备后统一刷新。
- `spend_skill_points(amount=1)` 只接受余额内正数。`changed` 和 `level_up(new_level)` 可驱动界面。
- `snapshot()` 返回带版本的 JSON 字典；`restore(data)` 全部验证后提交，类型或版本错误不改变当前角色；越界等级、经验和技能点会裁到合法范围。

## 状态 `status_effects.gd`

`apply(id, duration, potency=1, source="") -> bool`；同种状态刷新剩余时间、保留较强数值，DOT 按上限叠层，**不重置跳伤计时**。`source` 为最后施加者 ID。

| ID | potency 的含义 | 上限 / 跳伤间隔 |
|---|---|---|
| slow | 减速比例，0～0.9 | 1 层 |
| stun | 数值不参与眩晕计算 | 1 层 |
| shock | 每层每跳伤害 | 3 层 / 1 秒 |
| burn | 每层每跳伤害 | 5 层 / 0.5 秒 |
| bleed | 每层每跳伤害 | 5 层 / 1 秒 |
| shield | 护盾吸收量 | 1 层，刷新保留较多剩余量 |

- `step(delta)` 返回事件数组。伤害事件为 `{type:"damage", effect, amount, ticks, stacks, source}`；过期事件为 `{type:"expired", effect, source}`。**调用方实际扣血**，不要又乘一次 `ticks` 或 `stacks`，`amount` 已是合计值。
- 长帧按有效持续时间补全跳伤，合并成每种状态一个伤害事件；状态寿命之后不再补伤。伤害先于过期事件。
- `movement_multiplier()` 含眩晕为 0，否则减速后的倍率；`is_stunned()` 可用于攻击和施法输入门禁；`has(id)` 查询。
- `absorb_damage(amount)` 消耗护盾，返回还应扣除的生命伤害。建议先计算抗性/护甲，再调用这个函数。
- `cleanse(id="")` 移除指定状态或所有状态，返回移除数量。
- `snapshot()` / `restore()` 保留剩余时间、DOT 相位、叠层和剩余护盾；错误恢复不改变现有状态。存档里的状态时间在离线期间不会自行流逝。

## 掉落 `loot_table.gd`

```gdscript
var tables = preload("res://systems/core/loot_table.gd").new()
var rng = RandomNumberGenerator.new()
rng.seed = 42042
var drops = tables.roll("elite", rng)
# [{"kind":"currency","id":"旧铜币","amount":25}, ...]
```

- 默认 `crate / enemy / elite / chest` 四张表，物品 ID 与已有装备目录/材料背包一致。不调用全局随机数；相同 RNG 状态与同样调用顺序得到相同结果。
- 每张表由 `guaranteed`、`rolls`、`chance`、`pool` 组成。`chance` 是每次额外抽取的概率，pool 使用非负权重。
- 条目包含 `kind / id / min / max`，pool 额外需要 `weight`；`kind` 是 `currency / material / equipment / none`。装备数量每次为 1；`none` 不产出物品。
- `register_table(id, definition)` 验证数据并复制，不与调用者共享可变配置。`weighted_pick(entries, rng)` 可以单独使用。
- 相同 kind/id 合并数量，因此重复装备也可能 `amount > 1`；上层逐件发放或按已有逻辑换成重复装备补偿。
- 错误返回空数组并设置 `last_error`；错误表不消耗 RNG。实际物品实例、拾取动画、所有权判断和任务事件由上层实现。

## 验证

```text
godot --headless --path godot-belt-map --script res://tests/core_foundations_test.gd
```

回归测试使用独立的临时 `user://core_test_*` 目录并清理，覆盖坏档恢复、备份保留、未来版本保护、校验和、成长上限、状态时间步一致性、护盾和确定性掉落。不会读取或修改正式角色存档。
