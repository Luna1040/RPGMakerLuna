# B-06 战役管理器与 Godot 启动界面实施说明

## 交付结论

B-06 已接入 Godot 正式工程，并推送到现有草稿 PR：

- 分支：`b/content-patch-foundation`
- 提交：`6665fdc Add validated campaign manager UI`
- PR：<https://github.com/Luna1040/RPGMakerLuna/pull/1>
- Godot 完整回归：30/30 通过
- 测试运行器单元测试：11/11 通过

玩家现在可以在真实游戏中按 Esc，进入新增的“战役”页，查看官方战役、所有已安装生成战役及各自的三槽存档摘要。选择战役后必须先预览，再进行“结束当前会话”二次确认，最后才进入 B-05 的 bootstrap 新会话链路。

## 实际界面

界面截图：`/Users/ciguguanyin/Documents/Codex/2026-10-09/wo/outputs/B-06-战役管理界面.png`

![战役管理界面](./B-06-战役管理界面.png)

1280×800 实际渲染已检查：八个页签、当前战役、项目/战役 ID、三槽摘要和启动按钮均完整显示。

## 玩家操作

```text
游戏中按 Esc
→ 点击“战役”
→ 查看官方战役、生成战役、独立存档槽和包状态
→ 点击“预览并开始”
→ Godot 再次校验战役包并生成 launch_token
→ 页面显示目标战役、目标存档目录和结束当前会话警告
→ 点击“确认结束当前会话并启动”
→ 旧 stage 退出
→ campaign_bootstrap.tscn 提交内容切换
→ 新 stage 使用目标战役内容和独立 SaveStore
```

当前战役也可以选择“重新开始此战役”，但仍然必须经过预览、二次确认和 bootstrap，不存在热刷新入口。

## 战役库接口

新增工作台公开接口：

```gdscript
WorkbenchBridge.list_campaigns()
WorkbenchBridge.list_campaigns(project_id)
WorkbenchBridge.preview_official_launch()
```

原有接口继续使用：

```gdscript
WorkbenchBridge.preview_campaign_launch(project_id, campaign_id)
WorkbenchBridge.start_campaign_session(project_id, campaign_id, launch_token)
WorkbenchBridge.start_official_session()
```

`WorkbenchBridge.capabilities()` 新增：

```json
{
  "campaign_library": "validated_read_only_with_save_slot_summaries"
}
```

网页端后续可以复用完全相同的数据与确认语义，不需要也不允许自行拼接 `user://` 路径。

## 战役列表内容

每条可用战役返回：

- `kind`：official 或 campaign；
- `project_id`、`campaign_id`；
- `display_name`；
- `activation_policy`；
- `source_draft_id`；
- `content_hash`、`manifest_hash`；
- `save_directory`；
- `active`、`available`；
- 三个只读槽位摘要。

槽位摘要只读取 SaveStore 信封元数据，不恢复游戏状态，包含：

- 槽位是否存在；
- 是否可通过格式与校验和检查；
- 更新时间；
- 是否从备份恢复；
- 异常信息。

## 安全边界

- 项目 ID 与战役 ID 必须分别符合 `project.*`、`campaign.*` 规范，路径形式输入直接拒绝。
- Godot UI 不直接访问文件系统，只调用 `WorkbenchBridge.list_campaigns()`。
- 每个发现的战役都重新经过 `CampaignImportService.inspect_campaign()` 完整校验。
- manifest/content 缺失、篡改或交叉引用错误的战役仍会显示，但 `available:false` 且按钮禁用。
- 列表最多扫描展示 64 个项目、256 个战役，异常目录不会无限扩大菜单。
- 预览不会改变当前 ContentRegistry、场景或存档目录。
- 最终确认仍必须携带与项目、战役、manifest hash、content hash 绑定的 `launch_token`。
- 确认后不会自动加载、复制或覆盖目标战役的任何槽位。
- 网页与 Godot 不能绕过 WorkbenchBridge 直接调用 ContentRegistry。

## 测试覆盖

新增 `campaign_manager_ui_test.gd`，实际验证：

- 官方战役正确显示并标记为当前战役；
- 已安装自定义战役显示名称、来源草稿与独立槽位；
- 路径式 project ID 被拒绝；
- 损坏的规范战役目录会显示但不可启动；
- 自定义战役槽 2 的摘要从该战役 SaveStore 读取；
- Godot “战役”页真实创建；
- 点击预览不会热切换官方 ContentRegistry；
- 页面出现明确的结束会话确认按钮；
- 点击确认后真实执行 `stage → bootstrap → stage`；
- 新 stage 使用自定义内容和自定义 SaveStore；
- 测试结束时再次通过 bootstrap 恢复官方 stage。

完整测试报告：

```text
/Users/ciguguanyin/Documents/Codex/2026-10-09/wo/work/RPGMakerLuna-real/godot-belt-map/test-results/20261012T094757Z-7006/report.json
```

## 改动位置

- `systems/content/campaign_session_service.gd`：安全战役库、官方预览、槽位摘要与扫描上限。
- `systems/workbench_bridge.gd`：对 Godot/网页暴露战役库和官方启动预览。
- `systems/session_panel.gd`：Esc 菜单“战役”页、卡片、状态、二次确认和启动动作。
- `tests/campaign_manager_ui_test.gd`：真实 UI 与 bootstrap 集成回归。
- `tests/campaign_manager_capture.gd`：1280×800 手工视觉验收截图。

## 下一阶段建议

B-07 可以继续制作“游戏内 Agent 创作控制台”：玩家选择世界类型、主题、规模与限制后，Main Agent 拆分 Narrative / World / NPC / Systems / Validator 子任务；界面实时展示生成进度、冲突和 Validator 结果，最终把通过审查的内容送入现有草稿发布、战役导入和战役管理器链路。这样就能把 B-01 至 B-06 的底层能力连成玩家可操作的完整 AI 创作闭环。
