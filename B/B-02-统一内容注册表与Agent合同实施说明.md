# B-02｜统一内容注册表与 Agent 合同实施说明

## 结果

已在真实 Godot 工程中完成第二阶段：装备、城镇 NPC、任务与对话进入同一个稳定 ID 内容注册表；Main Agent → 子 Agent 的任务与结果合同已经具备 Godot 侧严格校验，并保持原有玩法、装备存档 ID、任务结算和 B-01 Runtime Patch 存档兼容。

工作分支：`b/content-patch-foundation`

提交：`3a009f1 Add unified RPG catalogs and agent contracts`

Draft PR：<https://github.com/Luna1040/RPGMakerLuna/pull/1>

## 内容体系

- 技能：`skill.knight.lightning`，权威文件为 `content/base/skills.json`。
- 装备：沿用 `knight_sword`、`courtyard_blade` 等已发布 ID，权威文件迁移到 `content/base/equipment.json`。
- NPC：沿用 `innkeeper`、`smith`，站位、显示名、环境对白及资产引用迁移到 `content/base/town_npcs.json`。
- 任务：沿用 `courtyard_provisions` 等 ID，由现有 `adventure_data.json` 注册并建立索引。
- 对话：以 NPC ID 作为稳定目标 ID，由现有条件对话目录注册。

`ContentRegistry` 会同时校验三个内容 Bundle 与冒险目录的交叉引用，全部通过后才原子替换运行时目录。所有读取接口返回深拷贝。

装备模型保留原来的 `CATALOG` 实例属性，避免修改现有 UI、战利品、交易和存档调用；该属性现在来自注册表，不再有第二份硬编码定义。已有存档中的装备 ID 无需迁移。

NPC 内容不允许写入 `res://` 路径。JSON 只能引用 `asset.*` ID，`town_npcs.gd` 内的 allowlist 是唯一资源路径解析边界。

## Main Agent 与子 Agent

新增：

- `content/schemas/agent-task.schema.json`
- `content/schemas/agent-result.schema.json`
- `ContentValidator.validate_agent_task`
- `ContentValidator.validate_agent_result`
- `WorkbenchBridge.validate_agent_task`
- `WorkbenchBridge.review_agent_result`

角色包括 Narrative、World、NPC、Systems、Validator。任务必须固定：

- `request_id`
- `project_id`
- 当前 `content_revision`
- 子 Agent 角色
- `allowed_targets`
- 只读 `context_refs`
- 最大建议数
- 是否允许新 ID
- 禁止生成代码

结果必须与任务的 request、角色、revision、目标范围和数量预算匹配。当前只有 Systems Agent 可以给出候选 Runtime Patch；Validator Agent 可读取所有目标但不能自行生成可执行 Patch。

`review_agent_result` 只返回校验后的候选 Patch，不会修改游戏。Main Agent 必须再次明确调用 `submit_patch`，随后仍经过 B-01 的 revision、幂等、白名单、原子事务和安全点检查。

## 兼容与安全

- `base_hash` 继续只覆盖可 Patch 技能包，B-01 运行时覆盖存档格式不变。
- 新增 `catalog_hash` 覆盖技能、装备、NPC、任务与对话，供 Main Agent 缓存失效使用。
- 装备旧 ID、槽位、拥有列表与穿戴状态不变。
- 任务、对话、奖励仍由现有 Adventure 服务执行，Agent 不能直接发放奖励。
- 当前装备/NPC/任务/对话为只读 Agent 目标；尚未开放运行时结构 Patch。
- 不执行 Agent 生成的脚本、资源路径、场景、Shader 或表达式。

## 验证

Godot 4.7.2 完整回归：25/25 通过。

报告：`godot-belt-map/test-results/20261012T082729Z-4676/report.json`

覆盖包括：

- 统一目录的稳定 ID、深拷贝与交叉引用。
- 装备目录实际进入角色、背包、战利品、商店与存档验证。
- NPC 数据实际进入城镇生成、动画、碰撞和交互。
- 任务/对话继续通过三路线与真实场景集成测试。
- Main Agent task、子 Agent result、越权角色、伪造 request 和审查不自动执行。
- Runtime Patch 原子性、revision、幂等、撤销、存档往返与安全队列。

Python 测试运行器自身测试：11/11 通过。

## 下一阶段建议

B-03 可在这一边界上增加“离线草稿 → Validator → 用户预览 → 正式发布”的内容导入流程，优先支持新增任务/对话与 NPC 定义；在结构 Patch 正式开放前，不应允许 Agent 直接改写正在运行的任务图或资产路径。
