# 跳跃动画接口

地图负责独立的高度、重力、平台碰撞和空中移动。每次更新物理后调用：

```gdscript
knight.set_airborne(not grounded, vertical_speed)
knight._physics_process(delta)
```

`vertical_speed` 单位为米/秒，向上为正，与 `belt_physics.gd` 一致。
`set_airborne` 不修改地图坐标，也不触发第二次重力。

角色从独立 `assets/jump.json` 读取 H3 新生成的完整身体动作帧；按起跳、上升、顶点、下降、落地阶段选帧。
普通跳跃落地恢复持续 0.18 秒。该动画只覆盖站立/移动/闲置状态的外观，保留施法、受击动作及命中事件。
空中 J 使用 `request_air_attack()` 切入独立下劈；地图解析成功落地后调用 `notify_air_attack_landed(true)`，落水回岸时传 `false` 取消冲击。下劈素材在 `assets/combat-motion.json`，悬空保持 `hold_ms`，落地从 `landing_start_ms` 接续剩余素材并在 0.22 秒内恢复。空中 K 保留雷光施法。
源视频里的整个人物平移由导出时的原点数据抵消；游戏世界的腾空位移只由地图负责。

生成工作流及原始结果：`character-generation-research/h3-runtime/map-jump/`。
回归脚本：`jump_test.gd`，通过 Godot `--headless --path godot-belt-map --script res://characters/first_knight/jump_test.gd` 执行。
