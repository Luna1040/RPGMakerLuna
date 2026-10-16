# 昨夜不存在 · Godot 源码快照

这是可运行的 P0 游戏原型源码，使用 Godot 4.7.2 stable。用 Godot 打开此目录中的 `project.godot`，等待首次导入完成后按 F5 试玩。普通试玩不需要团队生图连接包；只有从制作工具的 AI 开发入口启动时，F1 助手才需要本机桥接器。

标题界面按 Enter 或点击“开始委托”。酒吧中用 WASD／方向键移动，E 交互；调酒时单击酒瓶查看属性、再次双击倒入杯中，最多三种酒，酒库可用信用点解锁。记忆关卡中 J/F 攻击、空格闪避、Q 技能、E 交互。女主在第一层持电棍近战，击败安保队长后按 E 借身才解锁枪械；食堂出口仅作路线展示，医疗室可前进。第二层击败医疗员可得一次强化刷新，在强化界面按 R 使用。

本包包含游戏脚本、场景、运行素材、字体、设计说明和五项自动测试。运行素材已放在 `assets/`；不包含 `.godot` 缓存、团队连接配置、密钥、用户参考图、远程生图原片与工作流、个人存档和其他游戏。项目首页卡片使用 `assets/title-cover-creator-card-20261016-v1.png`；完整静态封面在 `assets/title-cover-preview-20261016-v1.png`。

在原 RPGMakerLuna Git 仓库中，PNG 和 TTF 由 Git LFS 管理；克隆仓库后请运行 `git lfs pull`，确认拿到真正的图片和字体。单独的 ZIP 已包含实际二进制文件，不需要 LFS。

此包是内部开发快照，不是公开发布版。现有字体的再分发许可及远程模型生成素材的正式发布许可尚待核查；游戏视觉手感、动作循环和音频也仍需后续完善。

自动检查（把 `PROJECT` 换成此目录）：

```sh
Godot --headless --editor --path PROJECT --quit
Godot --headless --path PROJECT --script res://tests/bar_world_test.gd
Godot --headless --path PROJECT --script res://tests/mixer_test.gd
Godot --headless --path PROJECT --script res://tests/cellar_save_test.gd
Godot --headless --path PROJECT --script res://tests/combat_stage_test.gd
Godot --headless --path PROJECT --script res://tests/p0_flow_test.gd
```

本轮逐项结果与仍需实际窗口试玩的内容见 `tests/TEST_REPORT.md`。
