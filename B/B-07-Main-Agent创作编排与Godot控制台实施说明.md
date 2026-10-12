# B-07 Main Agent 创作编排与 Godot 控制台实施说明

日期：2026-10-12  
仓库：`Luna1040/RPGMakerLuna`  
分支：`b/content-patch-foundation`

## 本阶段结果

本阶段把前面已经建立的 Agent JSON 合同、内容草稿、独立战役导入和新会话启动能力，收束为 Godot 内可操作的可信创作流程。

Godot 的 Esc 菜单新增“创作”页，标题使用“通用动态 RPG 世界引擎 Prompt”。玩家可以选择题材、基调、规模、内容策略，以及世界、地图、初始城镇、NPC、主线、支线、好感度、道具、装备和商店等模块，再由 Main Agent 创建一个有状态的创作 Run。

当前实现的 Agent 拓扑：

```text
Main Agent
├── World Agent
├── Narrative Agent
├── NPC Agent
├── Systems Agent
└── Validator Agent（等待全部业务子 Agent）
```

这不是 UI 中写死的一段流程说明，而是 `AuthoringOrchestrator` 执行的状态机。业务子 Agent 可以同时派发；Validator 带有显式依赖，只有全部业务结果完成并通过 Workbench 审查后才能领取。Validator 通过后，Main Agent 才能合并 Narrative/NPC 草稿并进入预览。

## 新增合同与接口

- `authoring-run-request/1`：严格声明项目、题材、主题、基调、规模、内容策略、请求系统和附加限制。
- `authoring-run/1`：保存内容基线、任务、依赖、结果、审查、草稿、补丁候选、预览和发布状态。
- Workbench 新增创建、查询、派发、回填、预览、发布和取消 Run 的公开接口。
- 外部 Agent 传输只接受 `agent-task/1` 和 `agent-result/1`；控制台复制 `authoring-dispatch/1` 信封，其中含原始任务、角色 Prompt 和 Validator 所需上游结果。
- 每个 Run 绑定 `catalog_hash`、`content_revision` 和 `content_context`。内容上下文发生变化后，未完成 Run 自动失效。
- 最多保留 16 个 Run；容量满时只能移除最旧的终态 Run，不会丢弃仍在等待 Agent 的任务。

## 安全与内容边界

- 外部模型不能直接修改 Godot 节点、场景、代码、资源路径、存档或当前战役。
- World Agent 当前只生成世界、区域、地图与城镇分析，不伪装成已经生成可执行地图。
- Narrative/NPC 只能提交授权目标内的 `content-draft/1`。
- Systems 只能提出白名单 Runtime Patch 候选；编排器不会自动应用。
- Validator 只能复核，不能生成可执行草稿或补丁。
- Main Agent 会检测多个子 Agent 对同一目标的冲突，并对合并后的完整候选目录再次做任务图、对话、NPC、资产与交叉引用检查。
- 发布必须先预览，并使用与草稿绑定的正确令牌；控制台另有一次人工二次确认。
- 发布只生成不可变 JSON 产物，不会热切换当前战役。之后仍须经过 B-04 导入为独立战役，再由 B-05/B-06 启动新会话。

成熟内容策略只允许明确成年的自愿角色。选择该策略时，请求必须同时包含：所有相关角色必须为成年人、亲密内容必须明确自愿、禁止性暴力与胁迫。缺任一条时，Run 在创建阶段即被拒绝；该策略不会放宽 Schema、授权目标或代码禁令。

## Godot 操作方式

1. 启动项目，按 Esc 打开手册，进入“创作”。
2. 填写主题，选择题材、基调、规模、内容策略和所需模块。
3. 点击“生成 Main Agent 计划”。
4. 点击“派发就绪任务并复制 JSON”，把任务信封交给外部 Agent 传输层。
5. 将单个子 Agent 返回的纯 `agent-result/1` JSON 粘贴到输入框并提交。
6. 全部业务结果通过后，再次派发 Validator。
7. Validator 通过后生成合并预览；确认差异后，二次点击发布。
8. 在后续导入流程中把发布产物安装成独立战役，再从“战役”页启动。

如果只选择世界、地图或系统分析，没有请求剧情/NPC 草稿，Validator 通过后 Run 会以“分析已完成”结束并保留审查报告，不会错误要求发布空内容包。

## 自动化验证

全量结果：31/31 通过，包括资源导入预检。

报告：

`godot-belt-map/test-results/20261012T100313Z-7427/report.json`

新增 `authoring_orchestrator` 覆盖：

- 成熟内容缺失三条边界时拒绝创建；
- 分析型 Run 无内容草稿时可以正常完成；
- Main Agent 正确拆分 World/Narrative/NPC/Systems/Validator；
- Validator 不会提前派发；
- 伪造 Agent 角色进入修订状态，修正后可以继续；
- Narrative/NPC 草稿各自通过授权范围和完整候选目录校验；
- Validator 收到四份已审查上游结果；
- Main Agent 合并四个授权操作；
- 预览和发布均不修改当前注册表；
- 错误令牌不能发布，正确令牌生成落盘产物；
- Godot 创作页标题、拓扑、表单操作和已发布状态真实渲染。

人工视觉截图：`outputs/B-07-AI创作控制台.png`。

## 仍未实现

本阶段没有假装完成外部模型连接。当前控制台使用剪贴板传输严格 JSON；尚未接入任何模型供应商、API Key、鉴权、网络重试、超时、长期任务队列或自动素材生成。地图结果仍是规划分析，不是自动生成的 Godot TileMap/场景。下一阶段应在保持相同合同的前提下接入可替换的 Agent Transport，并补充超时、取消、重试、速率限制和敏感凭据隔离。
