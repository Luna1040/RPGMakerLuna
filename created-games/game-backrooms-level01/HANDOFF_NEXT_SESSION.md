# 下一轮交接：回声层 Level 0

## 项目位置

- Godot 项目：`/Users/chenyijin/RPGMakerLuna/created-games/game-backrooms-level01`
- 主场景：`main.tscn`
- 主逻辑：`main.gd`
- 设计说明：`LEVEL_DESIGN.md`
- Godot 可执行文件：`/opt/homebrew/bin/godot`（4.7.2）
- 运行命令：`godot --path /Users/chenyijin/RPGMakerLuna/created-games/game-backrooms-level01`

## 当前进度

这是一个第一人称 Backrooms Level 0 原型，包含固定 31×31 办公区地图、移动/跳跃/冲刺、背包、杏仁水、胶卷、纸条、三处相机异常、闪光驱退和追踪怪物、暂停/开始界面。

最近完成的改动在 `main.gd`：

- 怪物在开场走廊远处短暂现身；拍摄异常后进入追逐逻辑。
- 杏仁水、胶卷和纸条的模型细节已增加。
- 程序纹理提高到 512×512，随机调整墙面色调；地图加宽了几处空间，并加入通风口和地面杂物。
- Godot headless 可启动；没有脚本报错。退出时仍有一条 ObjectDB 清理警告。
- HUD 增加阶段式逃生提示；Manila 档案/纸条会逐步透露 419 密码与阀门顺序。
- 加入脚步、相机快门、拾取、纸张、阀门、错误操作、水门和心跳音效，资源位于 `audio/sfx_*.wav`。
- 怪物行为：初次拍照后苏醒；无遮挡地注视时完全停下，移开视线后沿路追踪；拍中怪物会随机传送到一处可达走廊并短暂隐身。
- 杏仁水靠近即自动拾取，也可以瞄准按 E；左侧任务栏开局就显示下一只水阀或水门的相对方向和距离。
- 首次拍照后，追踪者会被导演到玩家附近的可达通道；黑暗区约停留 1 秒后，吉祥物跳吓以 55% 概率抽取并短间隔重试，每局最多一次，只提高恐惧、不造成伤害。麻薯脸由 Godot 3D 几何按用户提供图片搭建。
- 追踪者正式首次现身时弹应对提示，并给 4.5 秒追击/恐惧缓冲；开场也会提前说明第一次拍照会唤醒它。

怪物资源在 `assets/creatures/the_stalker/`，由 `STALKER_SCENE` 在 `main.gd` 预载。展示用单独场景是 `stalker_preview.tscn`，截图在 `previews/`。

## 目前游戏通关逻辑与待办

现有唯一离开方法是拍摄三处异常，然后到地图出口按 E：

- 异常位置/名字/照片编号：`main.gd` 顶部的 `ANOMALY_CELLS`、`ANOMALY_NAMES`、`ANOMALY_CODES`。
- 地图/房间生成：`_prepare_map()`、`_build_level()`。
- 相机记录异常：`_take_photo()`。
- 出口检查/打开/结局：`_try_exit()`、`_open_exit()`、`_finish()`。
- 通用 E 键交互：`_input()`、`_interact()`。
- 可交互物品识别：对象通过 `interact_kind` metadata 标记；`_interact()` 按类型分发。
- HUD：`_update_hud()`；背包显示在 `_input()`/背包相关逻辑附近。

已接入 Level 0 的三条逃生路线（实现位于 `main.gd`，设计记录在 `LEVEL_DESIGN.md`）：

- 拍摄三处异常后穿过出口墙缝，目的地 Level 1。
- 查阅 Manila Room 档案，按异常顺序输入 419 到旧电梯密码盘，目的地 Level 2。
- 按阀门刻痕从少到多操作三只阀门，接通水流后从湿脚印边的水门离开，目的地 Level 37 Poolrooms。

Level 37 无尽泳池已接入独立场景 `poolrooms.tscn` / `poolrooms.gd`。从 Level 0 操作三只水阀并通过水门后进入该层；顺序开启 01、02、03 回水阀即可打开泵房出口。Level 1/2 仍是结算卡，地图待制作。

## 继续前注意

- 以当前用户最新指令为准；暂停状态不代表取消未完成的逃生机制需求。
- 不要把任何 API key、隧道 token 或凭据写进项目/交接文件。
- 工作区文件目前有未提交/未跟踪内容；改文件前用 `git status` 确认，不要清理或覆盖其他已有内容。
