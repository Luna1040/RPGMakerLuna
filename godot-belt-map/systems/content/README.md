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

## 生成内容草稿与发布

任务、对话和 NPC 结构不使用热 Patch，而是进入两阶段创作流水线：

```text
子 Agent content_draft
→ Main Agent 汇总
→ ContentDraftService 完整候选目录校验
→ preview_content_draft 生成差异和 preview_token
→ 人或 Main Agent 选择
→ publish_content_draft 原子发布不可变 JSON 制品
```

草稿使用 `content/schemas/content-draft.schema.json`。支持 `quest`、`dialogue`、`npc` 的 `upsert`；同一草稿不能重复写同一目标。Narrative Agent 只能生成任务/对话，NPC Agent 只能生成 NPC/对话，Main Agent 可以把已经审查的片段合并成 `author_role: "main"` 的草稿。

Godot 会在完整候选目录上重新检查：

- 任务 ID、目标、条件、奖励、前置依赖和循环。
- 对话动作、条件、任务引用、费用与效果。
- NPC 定义与对话一一对应。
- 新 NPC 只能复用正式目录已经登记的 `asset.*`，不能声明路径或凭空增加资产。
- `base_catalog_hash` 与 `base_content_revision` 必须仍等于当前内容上下文。
- 草稿字段使用严格 allowlist，未知字段不会被静默带入发布制品。

`preview_content_draft()` 返回每个目标是新增还是替换、变动路径、候选内容哈希和与草稿内容绑定的预览令牌，但不会改变 `ContentRegistry`。`publish_content_draft()` 必须携带完全相同的草稿与令牌；预览后有任何改动或基础目录发生变化都会失败。服务只保留最近 32 个预览；同一制品的重复发布则按幂等请求处理。

发布制品使用 `content/schemas/published-content.schema.json`，默认写入：

```text
user://projects/<project_id>/published/<draft_id>.json
```

写入采用临时文件验证后原子重命名，同一 `draft_id` 同内容重复发布为幂等成功，不同内容冲突会被拒绝。制品包含源目录哈希、候选内容哈希和自身校验和。

重要边界：发布不等于激活。B-03 不会把生成的任务图热替换进当前战役，也不会修改当前存档；返回值明确给出 `activates_runtime:false` 与 `reload_required:"new_campaign_import"`。后续导入器必须在独立项目/战役命名空间中加载制品并重新校验，不能覆盖正在进行的官方战役。

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
