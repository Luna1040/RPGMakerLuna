# B-09 Agent 断点续作与安全持久化实施说明

## 结论

B-09 已在 Godot 主工程完成：创作 Run、子 Agent 任务状态与尚未完成的传输队列能够跨进程恢复。恢复不是把磁盘状态原样当成可信状态，而是由 Main Agent 重新生成任务合同，再让已保存的 `agent-result/1` 重新经过 Workbench 的 Schema、角色、授权目标与内容边界审查。

## 已实现能力

- 新增 `AuthoringPersistenceService` Autoload，正常游戏自动监听 Run、任务和传输 job 的状态变化。
- 使用 `user://authoring_state.json`、同目录临时文件与 `.bak` 完成原子校验点；主文件损坏时读取最后一个有效备份。
- 信封包含格式版本、创建/更新时间、规范化 JSON 与 SHA-256 校验和，单文件上限 4 MiB。
- AuthoringOrchestrator 只持久化原始创作请求、内容上下文、Agent 原始结果与必要状态；不信任或持久化派生 review、合并 draft、完整任务 bundle、Prompt 和预览令牌。
- AgentTransportService 只持久化活动 job 的 Run/Request/角色/尝试次数等最小元数据。恢复时从可信编排器重新物化 bundle；`running` 与 `retry_wait` 都安全降级为 `queued`。
- API Key 仍仅来自 `RPG_AGENT_API_KEY` 或本次 Godot 进程内存。恢复出的队列在没有密钥时保持暂停，玩家重新提供会话密钥后才继续。
- 已发布 Run 只有在不可变产物仍存在、Schema/校验和有效且 draft 完全一致时才恢复为 `published`；否则降级为重新审查。
- `previewed` 不恢复旧 preview token，恢复后必须重新预览才能发布。
- 内容目录哈希、revision 或 content context 变化时，旧 Run 标为 `stale`，不会向新战役上下文重放。
- 创作控制台显示“断点续作 / 原子校验点 / 备份恢复”状态，并明确说明哪些字段不会落盘。

## 安全边界

持久文件明确排除：

- 会话与环境 API Key；
- HTTP `Authorization` / Bearer 请求头；
- 发给供应商的完整 Prompt 与 task bundle；
- 一次性预览令牌；
- 被视为可信结论的 review 或未经复检的 draft。

恢复是“用持久证据重建并重新验证”，不是“信任磁盘快照”。因此本地文件即使被修改，也不能越过 Validator、内容草稿验证或发布闸门。

## 自动化验收

新增 `authoring_persistence_service_test.gd`，覆盖：

1. 连续原子写入并生成有效 `.bak`；
2. 持久文本不含 API Key、Authorization、Bearer、Prompt、preview token；
3. 故意破坏主文件后自动从有效备份恢复；
4. 中断的 running job 恢复为安全 queued；
5. 恢复 job 的公开元数据不暴露 bundle/Prompt；
6. 新会话重新提供密钥后继续执行；
7. 恢复结果再次通过可信审查，Run 只推进到显式 Validator 门禁。

B-09 核心回归结果：14 passed，0 failed。

报告：`godot-belt-map/test-results/20261012T104858Z-8183/report.json`

## 可视验收

截图：`B-09-Agent断点续作控制台.png`

页面标题继续使用“通用动态 RPG 世界引擎 Prompt”，未加入版本号。

## 尚未包含

- B-10 的供应商 profile、真实 HTTP 预检、延迟/错误指标与离线评测；
- B-11 的可执行世界蓝图编译；
- B-12 到 B-14 的完整生成战役、NPC 资产生产与发行验收。
