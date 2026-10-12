# B｜Godot 与游戏系统成果归档

本目录集中归档成员 B 的方案、Prompt、B-01 至 B-14 阶段说明、补丁、早期基础包、Godot 界面截图和最终机器验收报告。实际可运行源码仍以仓库中的 `godot-belt-map/` 为准，Web 发行物位于 `releases/knight-web/`；这里不重复复制 100 MB 以上的运行制品。

## 总览

- 执行方案：`成员 B｜Godot 与游戏系统执行方案.md`
- 主 Prompt：`通用动态 RPG 世界引擎 Prompt.md`
- 早期 Prompt：`通用动态RPG生成器Prompt.md`
- 阶段交付：`B-01-*` 至 `B-14-*`
- 最终机器报告：`B-14-release-acceptance.json`
- 发行复现清单：`../godot-belt-map/RELEASE_CHECKLIST.md`

## 阶段索引

| 阶段 | 核心成果 |
| --- | --- |
| B-01 | Godot 内容 Patch 与运行时合同基础，含 patch 和源码压缩包 |
| B-02 | 统一内容注册表与 Agent 合同 |
| B-03 | Agent 内容草稿校验、预览和原子发布 |
| B-04 | 独立战役导入、复检和隔离安装 |
| B-05 | 新会话战役启动、内容切换和存档隔离 |
| B-06 | Godot 战役管理界面与二次确认启动 |
| B-07 | Main Agent 拆分 World/Narrative/NPC/Systems 子 Agent |
| B-08 | OpenAI-compatible Agent Transport 与自动分阶段执行 |
| B-09 | 创作 Run 断点续作、安全持久化和恢复重审 |
| B-10 | 供应商 Profile、预检、离线合同评测和可观测性 |
| B-11 | 世界蓝图、可达性校验和 Godot 预置地图编译 |
| B-12 | 从 Agent 创作到真实 Godot stage 的完整生成战役闭环 |
| B-13 | 多角色、多动作 NPC 资产注册表和质量门禁 |
| B-14 | 37 项全量回归、Web 导出、浏览器启动和发行安全门禁 |

## 最终验收结论

- Godot 全量回归：37/37 通过。
- Web 发行门禁：15/15 通过。
- 门禁单元测试：3/3 通过。
- Web 浏览器首屏正常渲染，修复后无新增 error/warn。
- API Key 不进入仓库、配置、校验点、日志、报告或 Web 制品。

详细限制和未覆盖平台见 `B-14-Web发行与端到端总验收实施说明.md`。
