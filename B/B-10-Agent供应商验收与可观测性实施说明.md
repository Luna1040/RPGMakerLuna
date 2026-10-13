# B-10 Agent 供应商验收与可观测性实施说明

## 结论

B-10 已完成供应商 Profile、显式真实 HTTP 预检、离线合同评测与无敏感信息指标。没有用户提供的付费供应商账号或密钥，因此没有把任何外部付费服务标为“已验收”；网络验收使用本机 TCP 服务，真实经过 Godot `HTTPRequest → HTTP 服务 → OpenAI-compatible envelope → 严格 JSON probe` 全链路。

## Profile

- 自定义 OpenAI-compatible：允许 HTTPS，或仅 localhost 的 HTTP。
- OpenAI：固定 `https://api.openai.com/v1/chat/completions`，避免 UI 把官方 Profile 指向第三方域名；模型 ID 仍由用户明确填写，不内置可能过期的默认模型。
- 本机兼容服务：只允许 `localhost` / `127.0.0.1`。
- 旧 `agent-transport-config/1` 没有 `profile_id` 时按 `custom` 迁移；配置文件依旧不包含密钥。

官方端点和 JSON mode 依据 OpenAI 官方 Chat Completions API 参考核对：`https://platform.openai.com/docs/api-reference/chat`。官方文档同时说明 `json_object` 是较旧 JSON mode，支持时应优先 Structured Outputs；本项目当前保留通用兼容模式，最终结果仍由本地严格 Schema 审查，不把供应商格式保证视为授权。

## 真实预检

预检必须由用户点击“真实 HTTP 预检（会调用模型）”发起，不会随启动自动扣费。探针验证：

1. endpoint 与 Profile 约束；
2. 会话或环境密钥可用；
3. 实际 HTTP POST 能完成；
4. 返回 2xx 和 `choices[0].message.content`；
5. content 是纯 JSON 对象且满足 `{ok:true}` 探针。

UI/指标只保存状态、HTTP 状态、延迟、无敏感信息描述和时间，不保存请求体、响应全文、Authorization 或 API Key。

## 离线评测与指标

- `evaluate_cases()` 对 1–32 个样本调用生产环境同一 `WorkbenchBridge.validate_agent_task/review_agent_result`。
- 验收集同时包含合法 World 结果与伪造 role 的越权结果，要求前者通过、后者拒绝。
- 指标统计 completed/rejected/failed/cancelled/retried、成功率、平均延迟和最多 128 个结束任务的 P95。
- 指标只聚合数字，不保留 Prompt、Agent 输出或凭据。

## 自动化验收

`agent_provider_acceptance_test.gd` 启动真实本机 TCP HTTP 服务，验证真实 Authorization 请求、JSON 探针、严格 envelope 解析、Profile 锁定、离线正反样本和完成任务指标。外部付费账号验收保持明确未完成状态，不以 mock 冒充。

B-10 核心回归：15 passed，0 failed。报告：`godot-belt-map/test-results/20261012T110043Z-8405/report.json`。

截图：`B-10-Agent供应商验收控制台.png`
