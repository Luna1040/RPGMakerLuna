# RPGMakerLuna

原创像素/插画风 RPG 原型、角色制作实验及素材档案。2026-10-11 更新五名原创角色、整帧动作与独立队友战斗。

## 当前主工程

- `godot-belt-map/`：当前 Godot 4.7.2 主工程，包含庭院、古塔试炼、网状叙事、角色成长、存档与开发检查台。
- `releases/knight-web/`：网页试玩成品，入口 `index.html`；通过 HTTP/HTTPS 静态服务器运行。
- `releases/苍石庭院-角色与队友试玩-20261011.zip`：最新网页试玩包，可上传静态托管；底层框架版及 20261009 包保留为历史版。
- [`godot-belt-map/FOUNDATIONS.md`](godot-belt-map/FOUNDATIONS.md)：底层架构、接口、存档边界、剧情扩写和测试方法。
- [`godot-belt-map/README.md`](godot-belt-map/README.md)：团队克隆、Godot 导入、分支协作与完整验收说明。
- `CHARACTER_PIPELINE.md`：角色素材生产流程。
- [`NPC_ROSTER_INTEGRATION.md`](NPC_ROSTER_INTEGRATION.md)：五角色动作、队友机制、资源格式和验收方法。
- `godot-belt-map/使用与对接说明.txt`：最新操作、机制、测试与集成记录。

## Windows / macOS 正确开始

当前应打开 **`godot-belt-map/project.godot`**。仓库里其他 `godot-*` 文件夹是历史实验，不是本次庭院试玩入口。

运行现成游戏只需要 Godot 和仓库素材，**不需要安装 ComfyUI、AI 模型、Python、Node.js 或配置 API Key**。当前开发机使用 Godot **4.7.2 标准版**（GDScript，无需 .NET）；优先使用同版本。引擎不包含在仓库中，可从 [Godot 官方下载归档](https://godotengine.org/download/archive/) 获取对应系统版本。

### 第一步：下载完整仓库（两个系统都需要）

1. 安装 [Git](https://git-scm.com/downloads) 和 [Git LFS](https://git-lfs.com/)。安装完成后重新打开终端。macOS 已安装 Homebrew 的用户也可以运行 `brew install git git-lfs`。
2. 在 Windows PowerShell 或 macOS「终端」进入想存放项目的目录，执行：

```sh
git lfs install
git clone https://github.com/Luna1040/RPGMakerLuna.git
cd RPGMakerLuna
git switch b/content-patch-foundation
git lfs pull
git lfs fsck
```

`b/content-patch-foundation` 是当前成员 B 成果所在分支；合并后可使用默认分支。等待素材下载结束、`git lfs fsck` 校验通过，再启动工程。仓库包含大量历史图片和视频，首次下载可能较久。不要用 GitHub 的「Download ZIP」代替以上步骤，以免拿到 LFS 指针而缺少真实素材。

开发者还应运行 `python3 godot-belt-map/tools/verify_checkout.py`（Windows 可用 `py -3`），确认工程文件齐全且不存在未还原的 LFS 指针。

### Windows：启动游戏

1. 下载并解压 Windows 版 Godot，双击 Godot 编辑器 `.exe`。
2. 在项目管理器点击 **导入 / Import**，选择刚克隆的 `RPGMakerLuna/godot-belt-map/project.godot`，然后打开编辑器。
3. 首次打开等待素材导入完成，点击编辑器右上角 **运行项目 ▶**，或按 **F5**。会进入「苍石庭院」试玩。

推荐先使用上述编辑器方式，不需要配置环境变量。仓库根目录的 `play-knight-map.cmd` 沿用开发机目录约定：只有把对应引擎放到 `.tools/godot/Godot_v4.7.2-stable_win64.exe` 后才能直接双击；新克隆的仓库不包含这个文件。

### macOS：启动游戏

1. 下载适合自己 Mac 的 Godot 标准版，解压并把 `Godot.app` 放进「应用程序 / Applications」。
2. 打开 Godot，点击 **导入 / Import**，选择 `RPGMakerLuna/godot-belt-map/project.godot`，打开编辑器并等待素材导入。
3. 点击右上角 **运行项目 ▶**。也可以按 **F5**；如果键盘把 F5 用作系统功能，使用 **Fn + F5**。

macOS 使用同一份 GDScript 和素材，不使用 Windows 的 `.cmd` 启动器。需要命令行打开编辑器时，在仓库根目录运行（假设应用名为 `Godot.app`）：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --editor --path godot-belt-map
```

当前已在 Windows 验证，并在 macOS 15.7.4 Apple Silicon、Godot 4.7.2 上完成全新克隆、首次资源导入与自动化回归。本节针对现成游戏工程；仓库里的 AI 素材生产脚本包含 Windows 路径及 NVIDIA/CUDA 环境依赖，不能据此认为整套生图环境也能直接在 Mac 运行。

导入步骤也可参考 [Godot 官方项目管理器说明](https://docs.godotengine.org/en/stable/tutorials/editor/project_manager.html)。

### 只想试玩网页版

已导出的网页包不需要 Godot。先完成上面的 LFS 下载，然后使用 HTTP 静态服务器托管 `releases/knight-web/`，入口是 `index.html`。如果已安装 Python 3，可在仓库根目录执行：

Windows（PowerShell）：

```powershell
py -3 -m http.server 8793 --bind 127.0.0.1 --directory releases/knight-web
```

macOS（终端）：

```sh
python3 -m http.server 8793 --bind 127.0.0.1 --directory releases/knight-web
```

保持终端打开，在浏览器访问 [本机试玩](http://127.0.0.1:8793/)，点击开始后再操作。结束时在终端按 `Ctrl+C`。这两个命令只供本机访问；对外分发可将 `releases/苍石庭院-角色与队友试玩-20261011.zip` 解压上传静态托管服务。**不要直接双击 HTML，以 `file://` 打开不能正常加载游戏。**

### 基本操作

| 按键 | 功能 |
| --- | --- |
| WASD / 方向键 | 移动；同方向 0.5 秒内双击并保持按住可奔跑 |
| 空格 | 跳跃 |
| J | 普通连击；奔跑时冲刺攻击；空中下劈 |
| K / 1 / 2 / 3 | 施法 / 三个主动技能 |
| E | 交谈、开箱、拾取 |
| Q | 拾取并穿戴附近装备，或穿戴待装备物 |
| I / M | 背包和属性 / 大地图 |
| L / Esc | 冒险手册 / 暂停、存档、设置；再次按下关闭 |
| 4 / 5 | 生命药水 / 法力药水 |
| R | 城镇位置复位，生命与法力保持不变 |

开发检查台快捷键见下方「导出与开发」，仅桌面工程提供；Mac 的功能键必要时配合 Fn 使用。

### 启动问题排查

- **贴图丢失、字体报错、素材无法读取**：在仓库根目录重新运行 `git lfs pull` 和 `git lfs fsck`。如果 PNG 文件只有几行 `version https://git-lfs.github.com/spec/v1` 文本，就是指针文件，尚未下载真实素材。
- **提示没有 `git lfs` 命令**：安装 Git LFS、重开终端，再运行 `git lfs install` 和 `git lfs pull`。
- **双击 `.cmd` 提示找不到路径**：按上面的编辑器导入方式启动；Mac 不运行 `.cmd`。
- **首次打开很慢**：等待 Godot 完成首次素材导入；不要在导入过程中反复关闭编辑器。
- **运行了其他演示或空场景**：确认导入的是 `godot-belt-map/project.godot`，使用「运行项目」而非「运行当前场景」。
- **网页无法打开或按键无效**：确认静态服务器仍在运行、地址端口一致，并点击游戏区域使其获得键盘焦点。
- **更新项目**：没有本地改动时，在仓库根目录运行 `git pull`、`git lfs pull`，然后重新打开工程；有本地改动请先提交或备份。

## 素材与实验归档

- `character-generation-research/`：生成脚本、工作流、参考图、原始动作帧、抠图、视频及验收图；H3 模型和 ComfyUI 运行环境另行安装。
- `map-generation-research/`：地图工坊、世界/地点数据、生成试验及场景素材。
- `godot-first-knight/`：首个角色独立演示。
- 其他 `godot-*`、`discarded-wardrobe-neutral/` 和 `pixel-rpg-cli-test/`：早期分层、换装、3D 转 2D、像素及工具链实验。属于历史试验，不代表当前方案。
- `ASSET_MANIFEST.json`：复制时各源文件路径、字节数与 SHA-256，便于对照素材是否齐全。

## 导出与开发

`godot-belt-map/export_presets.cfg` 包含 Web Preview 预设。网页导出模板不随仓库分发，请安装同版本官方模板并更新自定义模板路径。
中文字体是 Noto Sans SC 字符子集，许可证随素材与网页包保存；添加新界面文字时需要重新生成子集或换用完整字体。
F3 打开开发检查台，F2 碰撞体，F4 命中范围，F6 暂停，F7 单步，F8 慢速。

## 本次未上传

模型权重、ComfyUI/引擎/CLI 下载包、Python/Node 依赖、缓存、临时下载分片、运行日志、认证与环境配置。
保留生成中间素材和验收截图。网页产物及角色压缩包也通过 LFS 保存。
第三方工具目录保留各自许可证，不对第三方内容重新授予许可证。

## 2026-10-11 角色与队友

按 **L / Esc → 角色图鉴** 查看五名角色的立绘和动作。待机、移动循环播放；攻击与受击播放后稍停再重播，瑟琳另有支援施法。深浅底切换可检查透明边缘。

| 角色 | 战斗身份 | 动作 |
| --- | --- | --- |
| 灰誓斥候 | 短剑近战兵 | 待机、移动、攻击、受击 |
| 灰誓咒术师 | 远程施法者 | 待机、移动、施法攻击、受击 |
| 灰誓重卫 | 巨斧重装兵 | 待机、移动、攻击、受击 |
| 陨星执政官 | 巨剑首领 | 待机、移动、攻击、受击 |
| 瑟琳 · 战牧 | 可招募队友 | 待机、移动、攻击、受击、支援施法 |

角色使用独立原创立绘和整帧 PNG 动画，源参考、H3 工作流、原始视频及帧、透明原稿与验收图均有归档。运行时只裁去每段动作共有的透明空白，保持原画布、脚底、缩放和帧时序；没有重新压缩画面尺寸。

瑟琳拥有 **140 HP / 80 MP**，会被敌人攻击、打断、击倒。圣光弹提供远程攻击，愈合术治疗低血量队员，圣域盾在战斗中保护自己；技能消耗法力并有独立冷却。小队面板可查看资源与状态，冒险手册可选择跟随作战、原地守卫或停战跟随。倒下后到城镇旅店花 10 铜币全队休整复苏；切换模式、回城或读档不会自动复活。

Esc 关闭菜单在按钮获得键盘焦点后仍有效；网页外层重新点击后也能把 Esc 传回游戏。

## 可玩的底层框架

先向艾琳和雷恩接取委托、询问失踪补给的线索。选定故事路线后，再找雷恩接受「庭院守夜人」，然后从 L / Esc 冒险手册进入古塔，点击开始本轮；任务不追溯接取前的击杀。完成三轮试炼、选择轮间祝福，回城领取任务报酬。升级后可分配天赋；建立艾琳与雷恩的信任后，经艾琳的「可以托付后背的人」对话招募瑟琳。

- **网状叙事**：六条交叉任务、修复 / 协商 / 调查三条互斥路线、共享结局、声望与条件对话。手册内可查看并点击叙事关系图。
- **战斗与试炼**：近战 / 远程 / 精英 / 首领、可闪避的预警、真实伤害、浮空 / 感电、三轮试炼、三选一祝福、失败与回城。
- **成长与经济**：等级经验、三分支六天赋、药剂、商店、制作、确定性掉落及奖励去重。
- **持久化**：三个存档槽，分别保存每个地点的箱子、宝箱、未拾取物，连同角色、任务分支、装备、材料、成长和队友状态。临时文件写入、备份恢复、校验和及坏档保护。
- **设置与开发**：重绑按键、音量、全屏、震动开关；碰撞及敌人受击体显示、事件追踪、跨平台自动化测试工具。

存档仅在城镇或清场后的安全检查点写入。新启动不会自动覆盖已有角色槽；继续游戏请在 Esc → 存档中读取。网页存档保留在当前浏览器的站点数据，不是云存档。

**当前边界**：敌人死亡使用受击末帧淡出，瑟琳倒下使用灰暗受击末帧，尚无单独死亡动画。瑟琳暂不提供个人装备栏或独立升级；古塔复用庭院美术。换装尚不改变角色外观；未实现联机、账号云同步或手机触控。Windows 已验证；macOS 已完成干净克隆、首次导入和自动化回归。

开发者在 `godot-belt-map` 目录运行：

```sh
python tests/run_tests.py --godot /absolute/path/to/godot --suite all
```

完整回归含 36 组自动化测试与 1 次资源导入检查；正常结果为 `PASS: 37 passed, 0 failed.`。工具会同时检查退出码、错误日志和 PASS 标记，避免把 Godot 退出码 0 误当作成功。角色素材还需通过原稿逐像素与动作记录一致性检查，详见 [角色交接](NPC_ROSTER_INTEGRATION.md) 和 [底层说明](godot-belt-map/FOUNDATIONS.md)。
