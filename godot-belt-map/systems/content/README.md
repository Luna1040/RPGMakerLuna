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

## 可信创作 Run

`AuthoringOrchestrator` 把上述合同变成 Godot 内真正的状态机。入口请求使用 `content/schemas/authoring-run-request.schema.json`，支持西幻、修仙、武林和混合题材，并声明主题、基调、规模、内容策略、所需系统和附加限制。

```text
create_authoring_run
→ Main Agent 按需求拆出 World / Narrative / NPC / Systems
→ dispatch_authoring_tasks 返回可派发任务和角色专属 Prompt
→ submit_authoring_result 逐项配对并调用 review_agent_result
→ 所有业务子 Agent 完成后，Validator 才能派发
→ Validator 通过后，Main Agent 合并已审查 content_draft
→ preview_authoring_run
→ 玩家二次确认
→ publish_authoring_run
```

每个 Run 绑定创建时的 `catalog_hash`、`content_revision` 和 `content_context`。任意一项变化，未结束 Run 都会进入 `stale`，不能把旧建议写入新战役。最多保留 16 个 Run；容量满时只清理最旧的终态 Run，不丢弃仍在等待结果的任务。

状态和权限约束：

- World 只产出世界、区域、地图和城镇分析；当前不能生成场景、脚本或资源路径。
- Narrative 和 NPC 必须把结构修改包装为 `content_draft/1`，并且只能写任务里列出的目标。
- Systems 只能提交白名单 Runtime Patch 候选；编排器仅保存候选，不会自动调用 `submit_patch()`。
- Validator 依赖所有业务任务，只审查上游结果，`deliverables` 必须为空；它不能生成补丁或草稿。
- Main Agent 只合并 Workbench 已经审查通过的草稿；两个子 Agent 对同一目标给出不同操作时，Run 进入修订状态。
- `preview_token` 同时绑定草稿和候选内容。错误、过期或不匹配令牌不能发布。

内容策略 `mature_consensual` 只代表“成年人之间明确自愿的成熟内容”，请求必须显式带上三条硬边界：`所有相关角色必须为成年人`、`亲密内容必须明确自愿`、`禁止性暴力与胁迫`。缺任一条时，Run 创建即失败。该策略不放宽目标权限、Schema、代码禁令或发布确认。

Godot Esc 菜单的“创作”页提供请求表单、任务状态、派发/复制 JSON、回填结果、Validator 闸门、合并预览与二次发布确认。剪贴板信封是 `authoring-dispatch/1`，其中每项包含原始 `agent-task/1`、面向该角色的 Prompt，以及 Validator 所需的已审查上游结果。当前没有内置模型供应商：外部传输层必须消费这些 JSON，再把单个严格 `agent-result/1` 回填；不能通过 UI 文字伪装成已完成的模型调用。

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

## 独立战役导入

`CampaignImportService` 把已经发布的制品转换为独立、不可变的战役包。调用方先提交 `campaign-import-request/1`，再执行：

```text
preview_campaign_import
→ 重新读取并校验 published-content/1
→ 重新物化完整技能/装备/NPC/剧情目录
→ 校验候选哈希、任务图、NPC 资产与全部交叉引用
→ 返回 campaign preview_token 和独立存档命名空间
→ install_campaign 原子安装 manifest.json + content.json
```

导入请求只能选择：

- `new_campaign`：明确作为新战役启动。
- `explicit_project_copy`：明确复制为另一个项目/战役实例后启动。

`campaign.official.*`、`campaign.base.*`、`campaign.system.*` 为保留 ID，不能成为导入目标。所有项目、草稿和战役 ID 都先通过规范化检查，再用于拼接固定目录；调用方不能提供任意文件路径。

安装目录：

```text
user://projects/<project_id>/campaigns/<campaign_id>/
├── manifest.json
└── content.json
```

`manifest.json` 使用 `campaign-manifest/1`，记录来源制品、完整内容哈希、激活策略、`runtime_activation:"new_session_only"` 和相对存档目录 `saves`。`content.json` 使用 `campaign-content/1`，冻结完整技能、装备、NPC 与冒险目录。两个文件都带规范化 JSON 校验和。

安装先在同级临时目录写入两个文件，执行落盘回读、Schema、校验和、严格字段、任务图、NPC 资产登记与交叉引用检查，全部通过后才整体原子重命名。现有相同战役包返回幂等成功；现有不同或损坏目录不会被覆盖。

导入和安装均返回 `activates_runtime:false` 与 `requires_new_session:true`。它们不会调用 `ContentRegistry` 的加载/修改接口，也不会访问 `user://rpg_saves`。新会话启动器只会读取已安装战役包，并把存档定向到：

```text
user://projects/<project_id>/campaigns/<campaign_id>/saves
```

## 新会话战役启动

工作台不能把生成内容热切换进当前游戏场景。标准入口是：

```text
WorkbenchBridge.preview_campaign_launch(project_id, campaign_id)
→ 展示战役名称、内容哈希、独立存档目录和“将结束当前会话”提示
→ 用户确认
→ WorkbenchBridge.start_campaign_session(project_id, campaign_id, launch_token)
→ 清除场景间临时数据、待应用 Runtime Patch 与旧 GameRuntime 引用
→ campaign_bootstrap.tscn 先替换旧 gameplay scene
→ 再次校验 manifest.json、content.json、身份和两个校验和
→ ContentRegistry 原子切换完整内容目录
→ stage.tscn 创建新的 GameRuntime，并绑定战役专属 SaveStore
```

`preview_campaign_launch()` 不修改注册表或存档路径。`launch_token` 同时绑定项目、战役、manifest hash 与 content hash；预览后包内容变化时，排队或提交都会失败。正式内容切换只允许在 `campaign_bootstrap.tscn` 中提交，因此旧场景节点不会观察到一半官方、一半自定义的目录。启动失败会恢复官方内容与 `user://rpg_saves`，不会自动加载或覆盖任何槽位。

每份新快照都写入 `content_context`，其中包含 official/campaign 类型、项目 ID、战役 ID、内容哈希与 manifest 哈希。读取时必须与当前 `ContentRegistry` 完全一致；旧版没有该字段的存档只允许在官方内容上下文迁移，不能进入自定义战役。返回官方战役使用 `WorkbenchBridge.start_official_session()`，同样经过 bootstrap 新会话边界。

工作台 UI 只应使用 `preview_campaign_launch()` 与 `start_campaign_session()`。`queue_campaign_launch()` / `commit_pending_launch()` 是启动服务和 bootstrap 之间的内部事务接口，不能作为当前场景的“刷新内容”按钮。

## 战役管理器

Godot 的 Esc 菜单现已提供“战役”页。页面通过 `WorkbenchBridge.list_campaigns()` 读取战役库，不直接遍历文件系统或解析 manifest。返回结果包含：

- 官方战役与所有规范项目目录中的已安装战役；
- 当前激活的项目/战役上下文；
- 显示名、激活策略、来源草稿、内容与 manifest 哈希；
- 每个战役独立三槽的存在、可读性、更新时间和备份恢复状态；
- 损坏或不完整战役包的只读错误信息。

损坏包会显示但启动按钮禁用。项目 ID 不能是路径；目录扫描只接受规范 `project.*` / `campaign.*` ID，并限制为最多 64 个项目、256 个战役，避免异常目录拖垮菜单。槽位摘要只读取 `SaveStore` 信封元数据，不恢复游戏状态。

Godot 与网页工作台应使用同一交互：

```text
list_campaigns
→ 选择战役
→ preview_campaign_launch / preview_official_launch
→ 显示“结束当前会话”二次确认和目标存档目录
→ start_campaign_session / start_official_session
```

预览后仍不会激活内容；只有玩家点击最终确认才会进入 B-05 的 bootstrap 链路。管理器不会自动读取目标槽位，进入新会话后由玩家在对应战役的“存档”页明确选择。

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
