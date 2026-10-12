# B-01 实施与 Godot 验证说明

## 已完成

本次实现基于仓库 `main` 的下载快照，工作副本位于：

`/Users/ciguguanyin/Documents/Codex/2026-10-09/wo/work/RPGMakerLuna-b01`

本地分支：`b/runtime-contract-foundation`

本地提交：`ccceaf7 Add validated RPG runtime contract foundation`

Godot 项目：`godot-belt-map/project.godot`

### 运行时基础

- 新增 `ContentRegistry` Autoload：读取、校验并按稳定 ID 注册内容定义。
- 新增 `GameState` Autoload：保存玩家、任务、NPC、世界和标记等可序列化状态，并维护 `state_version`。
- 新增 `SaveService` Autoload：临时写入、回读验证、旧档备份、原子替换和恢复。
- 新增 `ContentValidator`：限制内容类型、ID、数值范围和运行时补丁白名单。

### 雷光数据驱动样板

`skill.knight.lightning` 已迁移到 `content/base/skills.json`：

- 消耗：25 MP
- 冷却：2.4 秒
- 基础伤害：42
- 深度半径：0.65
- 动作、VFX 和 SFX 使用注册 ID，不允许任意资源路径

角色逻辑、技能栏和 HUD 现在从注册表读取雷光名称与数值；当前战斗手感和数值保持不变。投射事件同时携带 `skill_id`、`depth_radius`、`vfx_id` 和 `sfx_id`，为后续工作台桥接预留稳定接口。

### AI 安全边界

当前运行时补丁只允许修改：

- `/resource_cost/amount`
- `/cooldown_seconds`
- `/combat/base_damage`
- `/combat/depth_radius`

脚本、场景、资源路径、着色器和任意对象均不能由生成内容注入。

## Godot 验证结果

验证环境：Godot `4.7.2.stable.official`。

- `CONTENT_FOUNDATION_TEST PASS`
- 8 个相关 GDScript 文件逐一通过 `--check-only` 解析。
- 3 个 JSON 文件通过 `jq` 语法校验。
- `git diff --check` 通过。
- 修改后的工程已在 Godot 编辑器中打开，可看到新增的 `content`、`core` 和 `docs` 目录。

基础测试不加载美术资源，覆盖：内容注册、雷光数值兼容、危险补丁拒绝、状态版本、重复覆盖存档和存档恢复。

## 当前环境阻塞

GitHub 网页处于登录状态，但终端没有 GitHub SSH/HTTPS 凭据，无法把本地分支直接推送到私有仓库。

下载的 GitHub ZIP 中图片和字体是 Git LFS 指针，不是实际二进制资源。因此 Godot 可以解析脚本并运行基础测试，但庭院主场景会因缺少字体、背景、角色帧和 NPC 帧而报资源加载错误，无法完成视觉与全部战斗回归。

下一步需要在本机完成一次带 Git LFS 的私有仓库克隆。推荐使用 GitHub Desktop 登录并克隆 `Luna1040/RPGMakerLuna`，或在终端配置 GitHub 凭据并安装 Git LFS。获得完整检出后，可把本提交迁移到真实分支并运行现有全部测试。

## 交付文件

- `B-01-runtime-contract-foundation.patch`：可用 `git am` 应用的提交补丁。
- `B-01-runtime-contract-foundation-files.zip`：只包含本次新增与修改文件。
- 本说明文件。
