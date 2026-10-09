# 地图对话的角色接口

角色场景 `knight.tscn`，脚本 `knight.gd`、装备模块 `equipment.gd`，动作与素材 `assets/`。完整携带以上文件；角色不依赖训练场 `arena.gd` 或装备 UI。项目基于 Godot 4.7.2 / Compatibility renderer。

建议复制到地图项目 `characters/first_knight/`，保持 `knight.tscn`、`knight.gd`、`equipment.gd`、`assets/` 相邻。场景使用相对脚本路径，脚本相对于自身定位 assets，因此可整体移动文件夹，无需占用地图项目根目录的 assets。

这是固定侧视角色的第一版机制，移动基线是横向地面移动，没有上下/背面角色视图，也没有跳跃或导航寻路。地图若采用俯视移动，不要把横向角色动画误认为已完成八方向素材。

## 原点、输入与控制

- `global_position` 是角色脚下地面点。每个动作有固定 pivot 与统一缩放，逐帧不重新自动裁切。
- `facing` 为 1（右）或 -1（左）；左向暂用整套镜像，因此左右手持剑关系也会镜像。
- `input_enabled=false` 关闭玩家操作。设置 `use_local_input=false` 后，地图可用 `set_movement_axis(-1..1)` 输入横向移动。
- `request_attack()` 请求普攻，动作中后续按键缓存为下一段；第三段如果仍有缓存，则接回第一段以支持浮空追击，没有缓存则恢复待机。
- `request_cast()` 请求施法：25 MP，2.4 秒冷却。攻击期间可以缓存施法，已缓存连击优先。
- `apply_damage(amount, from_position)` 扣血、进入受击、清空连击/施法缓存。受击期间免重复伤害；生命归零禁用战斗，直到 `reset_character()`。
- `reset_character()` 恢复生命、蓝量、冷却和动作。
- 角色用 CharacterBody2D，地图负责地面、碰撞层与世界边界。本训练场锁定地面高度，不包含重力平台跳跃。

## 事件

- `attack_hitbox(event)`：每次攻击在动作表 `event_ms` 时仅发一次。字段 `origin`、`facing`、`range`、`damage`、`action`。地图消费事件，按方向与距离查询敌人并调用伤害接口。角色本身不会直接改地图敌人的血量。

  `range` 已包含角色导出的 `melee_reach_margin`（默认 24 像素），并随 `visual_scale` 缩放；地图不要重复加此余量。应检测攻击范围与敌人受击体的相交，不能只比较敌人中心距离。当前默认三段有效前伸为 244 / 259 / 204 像素；木桩半宽 25 像素也参与相交判定。`F2` 显示训练场判定范围（待机显示第一段攻击范围）。
- `spell_requested(event)`：施法释放时发一次，字段 `origin`、`facing`、`damage`。地图生成自己的投射物；训练场提供简单示例。
- `action_changed(action)`：当前动画变化。
- `stats_changed(health,mana)`：离散的扣血、消耗和重置事件。MP 持续恢复可逐帧读 `mana`；不要以为此信号每帧触发。
- `died`：生命耗尽通知。当前没有独立死亡素材，播放受击后停住并禁用战斗；正式死亡动画是后续扩展。

## 动作资源

`assets/animations.json` 记录每帧文件、原始 source_frame、duration_ms、动作总时长、pivot、scale 和命中事件。`attack1` 采用已认可的 640 ms 快速下劈。角色正常 alpha 渲染，单独 `fx` 帧使用 Godot 加法混合。

`assets/magic_bolt.png` 是从施法源片提取的黑底能量弹，边缘已衰减到黑色，使用加法混合。角色帧已削去飞出的弹体，但保留掌心蓄光。训练场按释放事件创建独立投射物并做沿轨迹的命中检测。源模型没有严格遵守“无特效”提示，因此这里采用后处理分离。

发布游戏时，请在导出设置中包含 `*.json`，确保动作表随包导出。`assets/` 内 PNG 采用 Godot 正常资源导入；首次从命令行启动前先让编辑器完成导入。

角色尺寸、速度、伤害等是可调的第一版游戏参数，不是模型输出决定的参数。不要改原始视频来调整技能速度，应改时序表并复查命中点。

## 验证入口

双击工作区 `play-first-knight.cmd`，训练木桩支持伤害数字、连击、法术投射物、生命/蓝量/冷却、受击和重置。`J` 连击、`K` 施法、`A/D` 移动、`H` 模拟受击、`R` 重置、`T` 开关木桩反击、`B` 深浅背景。

`Tab` 进入/退出八动作自动展示；展示模式暂停角色战斗逻辑，退出时重置角色。

## 木桩状态交互（2026-10-09）

训练木桩 1000 HP。法术命中施加 4 秒感电，每 0.5 秒造成 4 点伤害；感电期间每次近战直接命中额外造成 6 点电击伤害。持续伤害不增加连击次数，不递归触发感电。再次施法命中刷新时长。

第三段上挑施加向上初速度 360、重力 600。后续空中直接命中会停顿 55 ms，并补充至少 210 的向上速度；最多前六次空中追击提供补升力，最大高度 180，之后自然落地，防止无限悬空。落地清除空中追击计数。受击框和伤害数字跟随实际高度，法术也检测移动后的受击体。攻击仍需真实相交，过高的目标不会被地面刀气隔空击中。

`dummy_reactions.gd` 是可复用的 RefCounted 状态模块：`hit(action)` 返回本次附加伤害/是否空中命中/是否首次击飞；`step(delta)` 返回本步感电持续伤害；`height` 给出相对地面的高度。地图敌人可各自持有一份该状态，用自己的 HP 与受击框对接。`reset()` 清空感电、浮空和连击状态。角色包包含该模块，但角色本身不强制所有敌人都可击飞。

命令行加 `-- --smoke-test` 执行角色机制测试。源素材与研究过程不随地图一起复制，仅最终角色场景、脚本（包含 equipment.gd）、assets 需要随项目打包。

## 角色状态栏与装备（2026-10-09）

训练场按 `E` 或点击左上角「装备」打开整备面板，`E` / `Esc` / 返回按钮关闭。面板打开时暂停整个训练世界：角色动作、蓝量回复、法术弹体、木桩感电和反击均停住，UI 仍可操作。`Tab` 在面板中用于焦点导航，关闭后继续原有全动作展示快捷键。鼠标滚轮可浏览背包。

状态栏使用实际 `max_health` / `max_mana`，显示当前值和上限、护甲、近战/法术加成、移动速度；右下显示法术就绪、冷却或法力不足。`R` 恢复当前装备下的生命与法力上限，保留穿戴方案。

`equipment.gd` 是独立 RefCounted 属性模块，每个角色有自己的 `knight.equipment`。当前原型提供 10 件已拥有的训练装备，武器、铠甲、饰品、战靴各占一个槽位。同槽替换，卸下的物品仍留在背包。初始骑士长剑和银金骑士甲没有额外属性，默认战斗参数与旧版一致。未实现掉落、商店、强化或视觉换装；动画帧中的铠甲和剑保持原样。

| 装备属性 | 生效规则 |
|---|---|
| 生命 / 法力 | 加到基础 100 的上限；换装不回复资源，降低上限时钳制当前值，不复活 |
| 近战加成 | 加到三段动作表的原伤害 22 / 27 / 35，不修改时序、范围或击飞 |
| 法术加成 | 加到法术直接伤害 42；消耗 25、冷却 2.4 秒、感电参数保持原样 |
| 护甲 | 每次有效受伤减去固定值；至少受 1 点伤害，原输入不足 1 点时保留该小数伤害 |
| 移速 | 加到角色导出参数 `move_speed`，仅影响原有地面移动 |
| 法力回复 | 加到基础 7 MP / 秒，上限受当前装备影响 |

地图接口：

```gdscript
knight.equipment.equip("edge_sword") # 只允许已拥有的有效 ID
knight.equipment.unequip("weapon") # 卸下指定槽位
var stats = knight.get_effective_stats() # 上限、伤害加成、护甲、有效移速和回复
var next_bonuses = knight.equipment.preview("guardian_armor") # 不改变角色的预览
knight.equipment_changed.connect(update_equipment_ui)
```

`equip` / `unequip` 返回是否发生变更，并自动刷新角色属性、发出 `stats_changed` 与 `equipment_changed`。`get_attack_damage(action)` 返回含装备加成的该段伤害，事件的 `damage` 已包含加成，地图不要重复计算。

默认自动读取/写入 `user://first_knight_equipment.json`（版本 1），保存已拥有 ID 和穿戴槽位。写临时文件后替换存档；读取时过滤未知 ID、重复物品和槽位错配，损坏 JSON 保留默认装备。保存失败时装备仍生效，UI 提示没有保存。Windows 常规位置为 `%APPDATA%/Godot/app_userdata/First Knight - Character Mechanics/`。地图项目若自行管理存档，可在角色进入场景前设 `knight.equipment.persistence_enabled = false`；训练场测试与截图模式自动禁用玩家存档读写。

`equipment_ui.gd` 是训练场创建的 CanvasLayer，不是角色强制依赖；迁移 UI 时设置其 `knight` 为角色节点再添加到场景。它使用 Godot Control、系统中文字体和容器，随项目画布缩放。

验证入口：`--headless --path godot-first-knight -- --equipment-test`，覆盖装备槽位、实际近战/法术事件、减伤、容量钳制、回复、死亡/重置、存档恢复与非法数据、鼠标选择、穿戴/卸下、键盘导航、暂停恢复。`-- --capture-equipment` 在实际渲染窗口生成 `captures/equipment-hud.png`、`equipment-panel.png`、`equipment-equipped.png`。日志见 `equipment-check.log`、`equipment-combat-check.log`、`equipment-capture.log`。
