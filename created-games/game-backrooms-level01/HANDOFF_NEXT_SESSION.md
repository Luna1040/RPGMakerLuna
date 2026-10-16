# 下一轮交接：回声层 Level 0

## 项目位置

- Godot 项目：`/Users/chenyijin/RPGMakerLuna/created-games/game-backrooms-level01`
- 主场景：`main.tscn`
- 主逻辑：`main.gd`
- 设计说明：`LEVEL_DESIGN.md`
- Godot 可执行文件：`/opt/homebrew/bin/godot`（4.7.2）
- 运行命令：`godot --path /Users/chenyijin/RPGMakerLuna/created-games/game-backrooms-level01`

## 当前进度

这是一个第一人称 Backrooms Level 0 原型，包含固定 21×21 展示版办公区地图、移动/跳跃/冲刺、背包、杏仁水、胶卷、纸条、三处相机异常、闪光驱退和追踪怪物、暂停/开始界面，并接入独立 Level 37 泳池层。

最近完成的改动在 `main.gd`：

- 追踪者开场保持沉寂；首次使用相机后才会苏醒并靠近玩家。
- 杏仁水、胶卷和纸条的模型细节已增加。
- 程序纹理提高到 512×512，随机调整墙面色调；地图加宽了几处空间，并加入通风口和地面杂物。
- Godot headless 可启动；没有脚本报错。退出时仍有一条 ObjectDB 清理警告。
- Manila 档案/纸条会透露 419 密码与阀门顺序；HUD 目前只保留状态数值，不常驻显示路线任务。
- 加入脚步、相机快门、拾取、纸张、阀门、错误操作、水门和心跳音效，资源位于 `audio/sfx_*.wav`。
- 怪物行为：首次使用相机后沿路追踪；无遮挡地看着时明显减速，移开视线后恢复速度；拍中怪物会随机传送到一处可达走廊并短暂隐身。
- 杏仁水可靠近拾取，也可以瞄准按 E；场景目前保留一个杏仁水拾取点。
- 追踪者开场保持沉寂，首次使用相机时才被惊动，并被导演到玩家附近的可达通道。麻薯脸由 Godot 3D 几何按用户提供图片搭建；每局随机选择一处无灯走廊作为必定触发点，只提高恐惧、不造成伤害。
- Level 0 迷宫从 31×31 缩到 21×21，仍保留三处异常、支路和出口。最新调整移除了出生点的额外杏仁水和相纸、出口告示牌、地面路线箭头、常驻目标方向 HUD 与定时引导提示；降低了零散杂物、通风口、荧光灯和阀门灯光的密度/亮度，水声改为较弱的环境线索。
- 湿脚印压到地毯表面；Level 37 门框移到脚印走廊北端，竖直门面与门框对齐，避免偏在走廊边缘或像地面贴片一样躺平。加入 `audio/sfx_pipe_flow.wav`。Level 37 入口 UI 已锚定在屏幕底部，避免 800×450 展示窗口里提示跑出画面。
- Level 0 天花荧光灯替换为新生成的顶视灯具贴图并增加发光表现，资源在 `assets/textures/ceiling_fluorescent_troffer.png`。

怪物资源在 `assets/creatures/the_stalker/`，由 `STALKER_SCENE` 在 `main.gd` 预载。展示用单独场景是 `stalker_preview.tscn`，截图在 `previews/`。

## 目前游戏通关逻辑与待办

主线离开方法是拍摄三处异常，然后到地图出口按 E：

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

- 2026-10-16 已按最近一轮对话处理湿脚印/Level 37 门错位、随机无灯走廊必刷麻薯、减少显眼引导和环境/拾取物密度。开场不预放拾取物，追踪者在首次使用相机前保持沉寂。
- 根据用户提供的运行画面，修正标题菜单时 HUD/拾取提示提前显示的问题：开始探索前隐藏状态 HUD 与交互提示；杏仁水自动拾取范围仅在开始探索后启用，开场不再弹出提示或自动获得物品。
- Level 1 和 Level 2 目前仍是路线结算卡；如果后续继续扩展，先按用户最新明确的美术与引导偏好处理 Level 0，再决定是否制作新层地图。

- 以当前用户最新指令为准；暂停状态不代表取消未完成的逃生机制需求。
- 不要把任何 API key、隧道 token 或凭据写进项目/交接文件。
- 工作区文件目前有未提交/未跟踪内容；改文件前用 `git status` 确认，不要清理或覆盖其他已有内容。
