# B-14｜Web 发行与端到端总验收实施说明

## 完成结果

B-14 已完成。本阶段不是再增加一组孤立功能，而是对 B-01 至 B-13 的实际 Godot 工程、生成战役闭环和 Web 发行物做最终总验收，并把过程固化为可重复运行的门禁。

## 全量 Godot 回归

使用 Godot `4.7.2.stable.official` 完成资源导入预检和全部 core/gameplay 测试：

- 37/37 通过，0 失败；
- 报告：`godot-belt-map/test-results/20261012T113913Z-9525/report.json`；
- 覆盖内容注册、草稿、导入、会话隔离、战役管理、Main/子 Agent 编排、HTTP Transport、断点恢复、供应商评测、世界蓝图、完整生成战役、NPC 资产、剧情、遭遇、存档、角色与旧试玩冒烟。

## Web 导出与真实浏览器启动

已使用与编辑器完全匹配的官方 Godot 4.7.2 无线程 Web 模板重新导出：

- `game.html`：5,486 bytes；
- `game.js`：279,815 bytes；
- `game.pck`：101,098,284 bytes；
- `game.wasm`：39,514,754 bytes。

本地 HTTP 加载后，浏览器中的 1280×720 游戏 Canvas 已完成渲染；城镇、玩家、NPC、HUD、小地图和技能栏均可见。修复后重新加载的浏览器控制台没有新增 error/warn。

浏览器首次验收发现了一个编辑器测试无法暴露的问题：导出 PCK 会把 PNG 重映射为 `.ctex`，原来的 `FileAccess.file_exists()` 因此把 7 个合法 NPC profile 全部误判为缺失。现已把图片及动作帧存在性检查改为 `ResourceLoader.exists(path, "Texture2D")`，同时保持 JSON 使用 `FileAccess`；桌面工程与导出 PCK 均能正确校验。

## 新增发行门禁

新增 `tests/release_acceptance.py`，使用 Python 标准库检查：

- Web 导出排除规则和固定 no-threads 模板；
- HTML/JS/PCK/WASM 的存在性、大小、二进制签名及 SHA-256；
- 发布目录和 PCK 中的测试、截图、报告、日志与环境文件泄漏；
- 疑似供应商密钥，以及当前会话 `RPG_AGENT_API_KEY` 的逐字泄漏；报告永不记录密钥值；
- HTML/PCK/WASM 的 HTTP 可访问性与 Content-Length；
- 导出 PCK 在 Godot 中无脚本/引擎错误启动。

实际门禁结果为 15/15 通过；门禁自身的三项单元测试 3/3 通过。机器可读报告：

`/Users/ciguguanyin/Documents/Codex/2026-10-09/wo/outputs/B-14-release-acceptance.json`

核心制品 SHA-256：

- `game.html`：`d53872b245f403f86cfe2a0bd7abdee34719a52ea2d05768ee44f0c72ace6569`
- `game.js`：`33c94cb3175f3333b82e2a3be5e8e86f77986f0aa2042b1631f6367a4e5bb6ba`
- `game.pck`：`966276bb3e67711bce035242392bedbbd470244d410eeff233029bffd623a475`
- `game.wasm`：`fc74679e3b97f76878947fcd4fbe1268cbfa6188182a2e33bbc3f5dc9bfa57d0`

仓库内新增 `RELEASE_CHECKLIST.md`，记录从全量测试、Web 导出、静态服务、自动门禁到浏览器首启的完整复现方式。

## 安全与范围结论

- API Key 仍只存在于当前进程内存或环境变量，未进入 Git、配置、报告或 Web 制品。
- Agent 仍不能提交 GDScript、场景源码、Shader 或任意文件路径；世界与 NPC 只组合经过注册和审查的合同/资产。
- `.tools/` 中的 Godot 模板和 Git LFS 工具不提交；发行二进制按仓库 `.gitattributes` 使用 Git LFS。
- B-14 没有伪造真实付费供应商验收：当前仍需团队提供实际供应商账号并明确发起可能计费的调用。
- 本轮实测环境是本机 macOS Godot 与 Web 浏览器；Windows、移动端和线上 CDN 仍应在相应发布阶段单独验收。
