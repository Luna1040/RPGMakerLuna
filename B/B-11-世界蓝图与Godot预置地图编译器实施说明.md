# B-11 世界蓝图与 Godot 预置地图编译器实施说明

## 结论

World Agent 已不再局限于自然语言地图分析。它可以返回严格 `world_blueprint` deliverable，Godot 在可信边界内校验 `world-blueprint/1`，再由预置编译器生成 `world-bundle/1` 与现有 `side-facing-belt` 地图合同。模型仍不能生成或执行 GDScript，也不能提交 `res://` 或任意资源路径。

## 蓝图覆盖

- 世界题材与 lore summary；
- 1–8 个区域和 1–8 张地图；
- 明确初始地图/初始城镇；
- 每张地图的 biome、边界、出生点、NPC 开关；
- 建筑、树、箱子、水体、墙与喷泉地标；
- 有向出口图，所有地图必须从初始地图可达。

## 预置资产与运行时合同

Agent 只能引用 `asset.world.inn/tree/crate/fountain`。编译器负责把稳定 ID 映射为现有 `inn/tree/crate/fountain` 组件，并生成物理 volume、projection parameters、spawn、bounds、exits 和校验和。未知资产、脚本字符串、资源路径、越界 volume、被阻挡出生点、拓扑不可达图，以及没有实际可行走 spawn→exit 路径的地图会在编译前拒绝。物理路径检查使用与角色碰撞半径一致的安全余量和网格搜索。

输出仍使用仓库现有 `stage.gd`、`belt_physics.gd`、`CourtyardBackdrop` 与 prop renderer；没有动态加载生成代码。

## Main Agent 集成

- Agent result Schema 新增 `world_blueprint` kind。
- 只有 World Agent 能提交；project_id 必须与 task 相同。
- Workbench 在 result review 内同步编译，review 只保留验证后的 world bundle。
- Validator 通过后，Main Agent 把唯一 world bundle 放入 Run；多个世界蓝图视为冲突。
- 创作控制台显示编译地图数、初始地图和 world hash。

## 自动化验收

`world_blueprint_compiler_test.gd` 覆盖有效双地图编译、资产 ID 映射、无路径/脚本、篡改哈希拒绝、未知资产拒绝、出生点碰撞拒绝、不可达地图拒绝，以及 World → Validator → Main Agent 的完整合同闭环。

B-11 核心回归：16 passed，0 failed。报告：`godot-belt-map/test-results/20261012T110818Z-8574/report.json`。

B-11 仍只把蓝图编译进 Run；B-12 将把 world bundle 与剧情、NPC、任务、装备和商店一起装入可启动的独立战役。
