# B-08 Agent Transport 与自动分阶段执行实施说明

日期：2026-10-12  
仓库：`Luna1040/RPGMakerLuna`  
分支：`b/content-patch-foundation`

## 阶段结果

B-08 已把 B-07 的纯人工剪贴板链路扩展为 Godot 原生、可替换的 OpenAI-compatible Agent Transport。人工 JSON 通道仍然保留；未配置网络时，创作流程不会受影响。

`AgentTransportService` 只负责传输，不获得新的内容权限：

```text
AuthoringOrchestrator 生成 agent-task/1 与角色 Prompt
→ AgentTransportService 发送 OpenAI-compatible 请求
→ 严格提取 choices[0].message.content
→ 只接受无 Markdown 围栏的 JSON 对象
→ AuthoringOrchestrator 配对 Run / request / role
→ WorkbenchBridge 执行 Schema、目标授权与完整候选目录审查
```

Provider 返回内容不能直接修改场景、代码、资源路径、存档、Runtime Patch 或当前战役。

## Godot 控制台

“通用动态 RPG 世界引擎 Prompt”页面新增 Agent Transport 区域：

- OpenAI-compatible endpoint；
- 模型 ID；
- 会话 API Key；
- 15–90 秒常用超时选项；
- 0–3 次有界重试；
- 1–4 个并发任务；
- 就绪状态、密钥来源与活跃任务数；
- 保存配置和清除会话密钥；
- “运行当前就绪 Agent 阶段”；
- 每项任务的角色、状态、尝试次数、错误与取消按钮。

自动执行按阶段停顿。World/Narrative/NPC/Systems 完成后，Run 只进入 `validator_ready`；不会自动运行 Validator。玩家再次点击运行，才会启动 Validator。Validator 通过后也不会自动预览或发布。

## 凭据与网络安全

- 非敏感配置写入 `user://agent_transport.cfg`。
- API Key 只从 `RPG_AGENT_API_KEY` 环境变量或本次进程内存读取。
- API Key 不进入配置文件、公开 job 信息、Prompt、错误消息或日志。
- 远程 endpoint 必须使用 HTTPS。
- 明文 HTTP 仅允许 `localhost` 和 `127.0.0.1`。
- endpoint 禁止 query、fragment、userinfo，避免把密钥藏进 URL。
- Provider 响应限制为 1 MiB。
- 请求禁止工具调用、生成代码和资源路径。

HTTP 408、425、429、5xx 或底层网络中断可以执行指数退避重试；最大重试次数为 3。认证失败、非法 JSON、Markdown 代码围栏、缺失 message content、Schema/权限拒绝不会无限重试。

## 生命周期与取消

传输任务状态：

```text
queued → running → completed
                 ↘ retry_wait → running
                 ↘ rejected / failed / cancelled
```

失败、格式拒绝和取消都不会把 Agent 任务标为完成。玩家可以在同一个 Run 重新执行，修订 Prompt 会带上可信边界给出的拒绝原因。

通过 Workbench 取消 Run 时会先取消关联 HTTPRequest。`AuthoringOrchestrator` 同时拒绝终态 Run 的 active-task 查询和迟到 Agent 结果，因此网络回调不能把已取消 Run 重新变成进行中。

## 验证结果

全量 Godot 回归：32/32 通过，包括资源导入预检。

报告：

`godot-belt-map/test-results/20261012T103703Z-7857/report.json`

新增 `agent_transport_service` 测试覆盖：

- 拒绝远程明文 HTTP；
- 拒绝带查询参数的 endpoint；
- 安全配置可以落盘；
- 会话 API Key 不出现在配置文件；
- Primary Agent 自动异步执行；
- Validator 不会自动越过依赖闸门；
- 玩家明确启动 Validator 后分析型 Run 正常完成；
- HTTP 429 第一次失败、第二次成功，尝试次数受控；
- Markdown 围栏 JSON 被拒绝，修正后可以重试；
- 公开 job 不包含 bundle、Prompt 或 API Key；
- 活跃任务期间拒绝重配；
- 任务取消后不会误标完成；
- 迟到结果不能复活已取消 Run；
- Godot 页面不回显会话密钥，并显示密钥来源和自动运行按钮。

视觉截图：`outputs/B-08-Agent-Transport控制台.png`。

## 当前边界

仓库没有内置供应商地址、模型或密钥，本阶段也没有使用用户付费账号进行真实 Provider 请求。当前验证通过可控的 OpenAI-compatible 响应适配器完成，覆盖与真实 HTTP 相同的响应解析、重试和可信审查路径。

Run 与传输队列当前只存在于 Godot 进程内，重启后不会恢复。下一阶段应实现带校验和的 durable authoring store，保存非敏感任务状态、恢复 queued/retry_wait 作业，并确保任何凭据仍不进入持久化数据。

本阶段参考 `build-agents` 技能的可审查行为、耐久任务与凭据隔离原则；由于仓库已经是 Godot 成熟架构，没有另建 Eve/Vercel 项目或引入第二套运行时。
