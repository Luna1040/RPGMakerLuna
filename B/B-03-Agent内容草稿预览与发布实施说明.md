# B-03｜Agent 内容草稿预览与发布实施说明

## 结果

已在真实 Godot 工程中完成第三阶段：Narrative Agent 与 NPC Agent 可以提交结构化任务、对话和 NPC 草稿；Main Agent 负责审查并显式触发预览与发布；Godot 在完整候选目录上重新校验引用、权限、资产、任务图和奖励，最终只生成不可变 JSON 制品，不会热替换当前战役或修改现有存档。

工作分支：`b/content-patch-foundation`

提交：`d2944dc Add validated Agent content draft publishing`

Draft PR：<https://github.com/Luna1040/RPGMakerLuna/pull/1>

## Main Agent 与子 Agent 流程

```text
Main Agent 派发 agent-task/1
→ Narrative / NPC Agent 返回 agent-result/1 + content_draft
→ WorkbenchBridge 校验任务身份、角色、项目与目标范围
→ ContentDraftService 在完整候选目录上校验
→ Main Agent 调用 preview_content_draft 查看增改项与字段差异
→ Main Agent 或用户选择是否发布
→ publish_content_draft 原子写入不可变 JSON 制品
```

职责边界：

- Narrative Agent：仅可生成任务与对话。
- NPC Agent：仅可生成 NPC 与对话。
- Main Agent：审查子 Agent 结果，也可把已审查片段合并为 `author_role: "main"` 的草稿。
- Systems Agent、World Agent、Validator Agent：没有创建任务/NPC/对话草稿的权限。
- 子 Agent 草稿必须与派发任务的 `request_id`、角色、`project_id`、revision 和 `allowed_targets` 一致。
- 审查、预览和发布是三个分离动作；任何一个动作都不会自动进入下一个阶段。

## 新增合同与接口

Schema：

- `content/schemas/content-draft.schema.json`
- `content/schemas/published-content.schema.json`
- `agent-result.schema.json` 新增 `content_draft` deliverable。

Godot 服务：

- `ContentDraftService.validate_draft`
- `ContentDraftService.preview_draft`
- `ContentDraftService.publish_draft`
- `WorkbenchBridge.preview_content_draft`
- `WorkbenchBridge.publish_content_draft`

`WorkbenchBridge.capabilities()` 现在会公开草稿/发布 Schema、支持的目标类型，以及 `published_content_activation: "new_campaign_import"`。

## 完整候选目录校验

草稿目前只允许 `quest`、`dialogue`、`npc` 的 `upsert`。每次预览或发布都会从当前 `ContentRegistry` 深拷贝候选目录，应用全部操作，再统一检查：

- 严格字段 allowlist，拒绝未知字段和隐式脚本载荷。
- 任务定义 ID 与目标 ID 一致。
- 任务目标、前置条件、奖励、路线奖励、依赖和循环合法。
- 对话条件、动作、任务引用、费用与效果合法。
- NPC 定义与对话一一对应，任务引用的 NPC 必须存在。
- 新 NPC 只能复用正式目录已登记的 `asset.*` ID，不能传入 `res://`、文件路径或新资产声明。
- `base_catalog_hash` 与 `base_content_revision` 必须匹配当前目录。
- 单个草稿不允许重复写入同一目标，目录规模受到上限约束。

## 预览与不可变发布

预览返回：

- 每个目标是 `add` 还是 `replace`。
- 发生变化的 JSON 字段路径。
- 完整候选内容哈希。
- 与草稿及基础目录绑定的预览令牌。
- `activates_runtime:false`。
- `reload_required:"new_campaign_import"`。

服务只缓存最近 32 个预览。发布时必须再次提供完全相同的草稿与令牌；草稿被修改、目录 revision/hash 变化、令牌未知或目标越权都会失败。

发布路径：

```text
user://projects/<project_id>/published/<draft_id>.json
```

发布先写临时文件，在临时文件上执行 JSON、Schema 和校验和验证，再原子重命名。制品包含源目录哈希、源 revision、候选内容哈希、完整草稿和制品校验和。同一 `draft_id`、同一内容重复发布为幂等成功；相同 ID 的不同内容会被拒绝。

## 安全边界

发布不等于激活。B-03 不会：

- 改写当前 `ContentRegistry`。
- 把生成任务图热替换进正在运行的战役。
- 修改当前存档、奖励、声望或 NPC 状态。
- 执行 Agent 生成的 GDScript、表达式、资源路径、场景或 Shader。
- 允许新 NPC 绕过资产登记表。

后续导入器必须把发布制品加载到独立项目/新战役命名空间，并重新验证制品校验和与所有交叉引用；不得覆盖正在进行的官方战役。

## 验证

Godot 全量回归（含资源导入预检）：27/27 通过。

报告：`godot-belt-map/test-results/20261012T085128Z-5180/report.json`

新增测试覆盖：

- 新任务与既有对话组合草稿通过完整目录校验。
- 预览输出新增/替换差异且不修改运行时注册表。
- 经审查草稿原子发布并通过落盘回读校验。
- 相同发布幂等，篡改草稿不能复用预览令牌。
- 过期目录哈希、悬空 NPC 引用和未登记 NPC 资产被拒绝。
- Narrative Agent 可以领取新任务 ID，但不能跨任务目标或跨项目写入。
- Systems Agent 不能获得叙事新 ID 权限。
- 发布制品的来源上下文必须与内嵌草稿一致。
- 原有 Runtime Patch、任务、遭遇、存档、角色图鉴、真实场景与资源导入回归全部继续通过。

Python 测试运行器自身测试：11/11 通过。

## 下一阶段建议

B-04 应实现“独立新战役导入器”：读取已发布制品，在单独命名空间重建候选目录，验证制品校验和、来源上下文与全部引用，生成新的 campaign manifest；只允许在新游戏或明确复制项目时激活，禁止覆盖当前官方战役和现有存档。
