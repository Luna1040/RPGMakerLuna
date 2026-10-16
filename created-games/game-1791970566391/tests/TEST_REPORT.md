# 《昨夜不存在》自动验证记录

验证日期：2026-10-16。引擎：Godot 4.7.2 stable，macOS。验证对象为本源码副本；五项机制测试在无窗口模式运行，另用真实 OpenGL Compatibility 渲染器短暂开窗拍摄静帧，没有操作桌面制作工具中的游戏窗口。

## 本轮结果

| 检查 | 结果 | 覆盖范围 |
|---|---|---|
| 编辑器资源导入与脚本解析 | 通过 | 三张战斗地图、六张角色立绘、35 张战斗动作帧及原有酒吧素材导入；复查无 `SCRIPT ERROR` 或 `Parse Error`。 |
| `BAR_WORLD_PASS` | 通过 | 酒吧全景、周骁入场、可行走路线、调酒热点和交互动作。 |
| `MIXER_PASS` | 通过 | 酒瓶查看、双击倒酒、三种上限、酒库解锁与配方效果；新首层需击败安保队长并借身后，才检验共情线索和稳定酒的悖论变化。 |
| `CELLAR_SAVE_PASS` | 通过 | 信用点与酒库解锁记录的保存、重载。测试使用临时配置文件，完成后删除。 |
| `COMBAT_STAGE_PASS` | 通过 | 三张不同地图与战斗素材加载；女主电棍输入→前摇→近距离命中、远距离未命中且不发弹；普通安保及安保队长近战前摇；队长倒地后按 E 借身，枪械在动作事件后发弹并实际命中；食堂出口保持未开放，医疗室可通行；医疗员给予一次强化刷新；Boss 三种招式先预警并触发对应的脉冲弹、冲刺和裂隙特效，单次伤害不超过 5，击败后锚点可交互。 |
| `P0_FLOW_PASS` | 通过 | 标题→酒吧→对话→调酒→女主电棍→安保队长借身→双出口→医疗员刷新→Boss→因果结局→结算与升级的主线。 |
| `COMBAT_PREVIEW_PASS` | 通过静帧复核 | 真实渲染器输出八张安保区、女主电棍命中、借身后持枪、医疗室，以及 Boss 预警、脉冲、冲锋、裂隙的 1280×720 整数放大截图；已核对角色缩为 `0.5` 倍后的构图、门牌不会遮挡队长、三层色调与攻击提示位置。 |

测试入口（把 `PROJECT` 换成此目录）：

```sh
Godot --headless --editor --path PROJECT --quit
Godot --headless --path PROJECT --script res://tests/bar_world_test.gd
Godot --headless --path PROJECT --script res://tests/mixer_test.gd
Godot --headless --path PROJECT --script res://tests/cellar_save_test.gd
Godot --headless --path PROJECT --script res://tests/combat_stage_test.gd
Godot --headless --path PROJECT --script res://tests/p0_flow_test.gd
```

判定同时查看退出码、上述明确的 `*_PASS` 标记以及 `SCRIPT ERROR`、`Parse Error`、`*_FAIL`；Godot 的编辑器导入即使有脚本错误也可能返回退出码 0。首次新目录导入时，字体曾短暂提示缺少 `.godot/imported` 缓存，导入后复查已消失。当前沙箱仍提示无法写 `user://logs`、用户编辑器设置目录，以及 macOS 系统证书查询错误；这些环境提示未伴随脚本或测试失败。

## 画面复核与待完成的试玩

本轮已查看真实 Godot 渲染器的八张静帧，发现初版人物过大后把所有战斗小图统一缩为原来一半，并把被队长遮住的医疗室出口牌移到空白区域。静帧能确认这几处视觉修改及 Boss 特效出现，仍不能证明连续走路、攻击/受击衔接、动态 Y-sort/遮挡、医疗刷新界面的操作手感，或 Boss 三招实际躲避体验。下一轮应在正式游戏窗口连续试玩三层并逐项确认。

本轮战斗动作帧为原创程序像素候选，尚非 H3 动画；现有酒吧 H3 动作不代表战斗动作已由 H3 生成。

`combat_preview_capture.gd` 在真实渲染器下把八张 QA 截图保存到环境变量 `COMBAT_PREVIEW_OUTPUT_DIR` 指定的绝对路径，不写游戏存档或发布素材。本轮得到 `COMBAT_PREVIEW_PASS`；headless 下则按预期输出 `COMBAT_PREVIEW_SKIP`。
