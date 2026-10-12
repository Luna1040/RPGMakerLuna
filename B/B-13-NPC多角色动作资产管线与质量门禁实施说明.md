# B-13｜NPC 多角色动作资产管线与质量门禁实施说明

## 完成结果

B-13 已把生成 NPC 从“只能复用旅店主人/铁匠两套固定素材”升级为 Godot 内受信的多角色、多动作资产管线。NPC Agent 仍不能提交文件路径或上传脚本，只能选择已经过发布审核的 `profile_id + asset ID` 组合。

当前登记 7 个可用 profile：

- 旅店主人、铁匠：保留现有高质量职业待机动画，兼容正式试玩。
- 瑟琳、斥候、咒术师、重卫、首领：接入既有 768×768 全身角色管线。
- 五套角色共登记 21 个动作、351 帧；瑟琳包含 `stand / walk / attack / hurt / cast`，其余包含 `stand / walk / attack / hurt`。

## 新的可信资产边界

新增 `NpcAssetRegistry` Autoload，启动时读取 `npc_asset_catalog.json` 并执行以下门禁：

- profile、基础图 asset ID、动作 manifest asset ID 必须成对登记，禁止跨 profile 拼接。
- 本地路径必须位于 `res://assets/npcs/` 或 `res://assets/roster/`，禁止绝对路径、父目录跳转、查询串和非 PNG/JSON 文件。
- 动作清单身份、768×768 虚拟画布、帧数、实际帧文件、`visually_reviewed` 状态必须有效。
- 角色打包报告必须为 `packed`，且不能存在跳过动作。
- 随项目保存的发布证明必须记录 `release_ready: true`、351 帧检查和至少 25 项回归检查。
- 面向 Agent/工作台的 capabilities 只暴露 profile/asset ID、动作名和审核状态，不暴露任何 `res://` 路径。

因此，即使 Agent 猜测本地路径、混用角色肖像与动作清单、选择未审核动作或伪造 profile，也会在草案预览前被拒绝。

## 运行时表现

`town_npcs.gd` 现在通过资产注册表解析视觉资源：

- 旧 NPC 继续使用原职业待机序列，不改变正式试玩表现。
- 多动作 profile 使用现有 `RosterAnimation` 固定脚点、固定 pivot、存储裁切还原和共享纹理缓存。
- 生成 NPC 在真实地图中按 manifest 的逐帧时长播放 `ambient_action`，不再用静态图缩放冒充动作。
- 肖像、场景全身图、动作清单来自同一 profile，避免换脸、换装和比例漂移。

B-12 的端到端生成战役验收已改用 `profile.npc.serin`，证明 Agent 生成 NPC 可以在实际 `stage.tscn` 中加载多动作角色，而不是只通过独立资源测试。

## 自动化验收

新增 `npc_asset_registry_test.gd`，覆盖：

- 7 个发布 profile 与动作列表可查询；
- Workbench capabilities 不泄漏路径；
- 已审核咒术师 profile 可进入 NPC 内容草案；
- 肖像/manifest 跨 profile 混用被拒绝；
- 虚构 profile、未登记动作、危险路径、待审核状态和缺失发布证明被拒绝；
- 完整生成战役在真实场景加载瑟琳多动作 NPC。

Godot 核心测试结果：18/18 通过，报告：

`godot-belt-map/test-results/20261012T112813Z-9165/report.json`

现有 Python 资产门禁的 18 项单元测试全部通过。当前运行时 351 帧结构检查为 `ok: true`，无待审核动作；由于本机未安装 Git LFS，仓库中的原始未裁切归档仍是 LFS 指针，本轮无法重新完成逐像素“裁切前后无损”比对。项目使用已有的正式发布证明（此前记录 351 帧、25 项回归、`release_ready: true`），没有把本轮无法读取原稿的结构检查冒充成重新发布验收。
