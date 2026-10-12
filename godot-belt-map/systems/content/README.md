# 数据内容与运行时 Patch 合同

这一层是 Godot 游戏与网页创作工作台、Main Agent 及子 Agent 之间的安全边界。外部系统只提交 JSON 数据；运行时不会执行生成的 GDScript、场景文本、Shader、表达式或任意资源路径。

## 当前接入

- `ContentRegistry` 启动时验证 `content/base/skills.json`，按稳定 ID 返回只读副本。
- `WorkbenchBridge` 报告能力、校验 Patch，并且只在非战斗、角色站稳、无飞行投射物的安全点应用。
- 雷光 `skill.knight.lightning` 的 MP、冷却、伤害、纵深命中宽度、弹射目标数和弹射半径由注册表驱动。
- Patch 是原子事务：任一操作非法时全部拒绝；`patch_id` 重复提交不会重复修改。
- 覆盖状态随现有 `GameRuntime` 存档和跨场景快照保存，不另建第二套游戏状态或存档系统。
- 会话内最近一次 Patch 可以撤销；从存档恢复后历史栈清空，但当前覆盖值仍然保留。

当前白名单：

```text
/resource_cost/amount
/cooldown_seconds
/combat/base_damage
/combat/depth_radius
/combat/chain_count
/combat/chain_radius_m
```

例如把雷光改为最多弹射三个目标：

```json
{
  "schema_version": "runtime-patch/1",
  "patch_id": "author.lightning.chain-three",
  "base_content_revision": 0,
  "operations": [
    {
      "op": "replace",
      "target_type": "skill",
      "target_id": "skill.knight.lightning",
      "path": "/combat/chain_count",
      "value": 3
    }
  ]
}
```

调用方应先读取 `WorkbenchBridge.capabilities()` 中的当前 `content_revision`，再用 `inspect_target("skill", id)` 取得目标定义，并把该 revision 填入 `base_content_revision`。版本不匹配的并发修改会被拒绝，调用方重新读取能力和目标定义后再生成 Patch。

## Agent 分工接口

- Main Agent：组合请求、读取能力、汇总子 Agent 结果，并提交最终 Patch。
- Narrative Agent：以后只产出任务图、对话图和关系变化 DTO，不直接发奖励。
- World Agent：以后只产出已登记房间模板、稳定物件 ID 和地图合同。
- NPC Agent：以后只产出 NPC 定义、日程、对话引用和外观资产 ID。
- Systems Agent：只能修改注册表公开的数值/规则字段。
- Validator Agent：在提交前检查 Schema、引用、范围、预算和可达性；Godot 仍会独立再校验一次。

网络、鉴权、队列和 Agent 调度属于平台端。`WorkbenchBridge` 目前是纯 Godot 进程内合同，后续传输层只能调用它的公开方法，不能绕过注册表直接改场景节点。
