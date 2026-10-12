# 数据内容、Main Agent 与运行时 Patch 合同

这一层是 Godot 游戏、网页创作工作台、Main Agent 与子 Agent 之间的安全边界。外部系统只交换 JSON；运行时不会执行生成的 GDScript、场景文本、Shader、表达式或任意资源路径。

## 统一内容注册表

`ContentRegistry` 启动时以原子方式读取并校验四类正式内容。任一文件或交叉引用无效时，整批内容都不会进入运行时。

| 目标类型 | 稳定 ID 示例 | 权威数据源 | 当前权限 |
| --- | --- | --- | --- |
| `skill` | `skill.knight.lightning` | `content/base/skills.json` | 可读取；白名单数值可 Patch |
| `equipment` | `courtyard_blade` | `content/base/equipment.json` | 可读取；保持旧存档 ID，不开放运行时 Patch |
| `npc` | `innkeeper` | `content/base/town_npcs.json` | 可读取；资源仅使用登记的 `asset.*` ID |
| `quest` | `courtyard_provisions` | `systems/adventure/adventure_data.json` | 可读取；由既有任务服务结算 |
| `dialogue` | `innkeeper` | `systems/adventure/adventure_data.json` 的 `npcs` | 可读取；由既有条件/效果服务执行 |

装备实例、城镇 NPC 和冒险状态都从该注册表取得深拷贝，不再各自维护第二份硬编码定义。装备保存仍沿用原来的 `knight_sword` 等 ID，因此旧存档不需要迁移。NPC 数据只保存已登记资产 ID，`town_npcs.gd` 的本地 allowlist 才能把它解析为 `res://` 路径；Agent 不能提交路径。

`base_hash` 只覆盖可 Patch 的技能包，以保持已有运行时覆盖存档兼容；`catalog_hash` 覆盖技能、装备、NPC、任务和对话，供 Main Agent 缓存与上下文失效判断。

读取接口：

```gdscript
ContentRegistry.get_definition("equipment", "courtyard_blade")
ContentRegistry.registered_ids("quest")
WorkbenchBridge.inspect_target("dialogue", "innkeeper")
WorkbenchBridge.capabilities().targets_by_type
```

以上接口都返回深拷贝，调用方无法借由修改返回值改变游戏状态。

## Main Agent → 子 Agent

Main Agent 是唯一编排者。它先读取 `WorkbenchBridge.capabilities()` 和所需目标，再按 `content/schemas/agent-task.schema.json` 派发任务。子 Agent 只返回 `content/schemas/agent-result.schema.json`；Main Agent 使用 `review_agent_result(task, result)` 做配对、权限、revision、目标范围和 Patch 校验。

推荐顺序：

1. Main Agent 读取 `content_revision`、`catalog_hash`、`targets_by_type` 和目标定义。
2. Main Agent 为每个子 Agent 生成独立 `request_id`，列出可修改的 `allowed_targets` 与只读 `context_refs`。
3. 子 Agent 返回分析或候选 Runtime Patch，不直接接触场景节点、存档或奖励结算。
4. Main Agent 汇总结果；`review_agent_result` 只审查，不会应用变更。
5. Main Agent 明确选择候选 Patch 后，再逐个调用 `submit_patch()`。Godot 会再次校验，并在安全点应用或排队。
6. Validator Agent 可以读取所有已登记目标并给出分析，但不能自行生成可执行 Patch；当前只有 Systems Agent 可提出 Runtime Patch。

角色边界：

- Narrative Agent：任务与对话目标的分析、分支一致性和可达性建议。
- World Agent：读取相关内容作为上下文并给出世界/地图规划；当前 Godot 尚未开放地图结构 Patch。
- NPC Agent：NPC 与对话的一致性、身份、关系和表现建议。
- Systems Agent：技能/装备系统分析；目前只有技能白名单字段能成为候选 Patch。
- Validator Agent：跨引用、Schema、范围、预算、权限与冲突复核，不直接修改内容。

任务示例：

```json
{
  "schema_version": "agent-task/1",
  "request_id": "request.balance.lightning-001",
  "project_id": "project.rpgmakerluna.courtyard",
  "content_revision": 0,
  "agent_role": "systems",
  "objective": "检查雷光的单体伤害并提出一个保守调整。",
  "allowed_targets": [{"target_type": "skill", "target_id": "skill.knight.lightning"}],
  "constraints": {"max_proposals": 2, "allow_new_ids": false, "allow_generated_code": false},
  "context_refs": [{"target_type": "quest", "target_id": "courtyard_provisions"}]
}
```

结果示例：

```json
{
  "schema_version": "agent-result/1",
  "request_id": "request.balance.lightning-001",
  "agent_role": "systems",
  "status": "completed",
  "summary": "提出一项保守的基础伤害调整。",
  "deliverables": [
    {
      "deliverable_id": "deliverable.balance.lightning-note",
      "kind": "analysis",
      "target_type": "skill",
      "target_id": "skill.knight.lightning",
      "content": "仅调整基础伤害，不改变消耗、冷却或弹射范围。"
    },
    {
      "deliverable_id": "deliverable.balance.lightning-patch",
      "kind": "runtime_patch",
      "payload": {
        "schema_version": "runtime-patch/1",
        "patch_id": "author.lightning.damage-001",
        "base_content_revision": 0,
        "operations": [{"op": "replace", "target_type": "skill", "target_id": "skill.knight.lightning", "path": "/combat/base_damage", "value": 45.0}]
      }
    }
  ],
  "evidence": ["候选值处于 Godot 白名单范围内。"],
  "warnings": []
}
```

若 `request_id`、角色、revision、目标授权或数量预算不匹配，整个结果被拒绝。`needs_revision` / `blocked` 结果不能携带可执行 Patch。

## 运行时 Patch

技能 Patch 是原子事务：任一操作非法时全部拒绝；重复 `patch_id` 不会重复修改。会话内最近一次 Patch 可撤销；覆盖状态进入现有 `GameRuntime` 快照和 `SaveStore`，不另建第二套状态或存档。

当前技能白名单：

```text
/resource_cost/amount
/cooldown_seconds
/combat/base_damage
/combat/depth_radius
/combat/chain_count
/combat/chain_radius_m
```

调用方应先读取当前 revision 并检查目标，然后提交符合 `content/schemas/runtime-patch.schema.json` 的 JSON。版本不匹配会被拒绝；调用方必须重新读取，不可盲目重放。`WorkbenchBridge` 只在非战斗、角色站稳、无飞行投射物的安全点应用，否则进入有界队列。

网络、鉴权、持久任务队列和真正的 Agent 进程调度属于平台端。本目录实现的是 Godot 内的可信执行边界：传输层只能调用公开方法，不能绕过注册表直接改场景、奖励或存档。
