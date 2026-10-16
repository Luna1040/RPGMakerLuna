# 《昨夜不存在》战斗 Demo 像素素材

这是一套可复现的原创程序绘制候选素材。运行 `python3 assets/combat/generate_combat_assets.py` 需要 Pillow；脚本只写本目录。没有调用远程生图服务，也没有把用户参考图、旧的非像素竞技场或其他游戏角色像素复制进来。女主沿用本项目已有的蓝绿色长发、酒红马甲、黑色衬衣身份设计，并在战斗版增加电棍。

## 接入合同

| 资源 | 路径 | 规格与用途 |
|---|---|---|
| 安保检查区 | `maps/security_checkpoint.png` | 320×180 RGB。左右两侧可辨的门：左侧 x≈0–29、y≈69–129 为食堂封门图形；右侧 x≈290–319、y≈69–129 为通往医疗室的门。 |
| 医疗室 | `maps/medical_room.png` | 320×180 RGB。两张治疗床、扫描台、仪器轨道、监护屏、药柜和管线。 |
| 根层神经实验室 | `maps/root_lab.png` | 320×180 RGB。厚边环形核心、外围控制台和细神经电路。洋红电弧仅是环境装饰，动态 Boss 预警由游戏单独绘制。 |
| 立绘 | `portraits/{heroine,guard,captain_melee,captain,medic,corrector}.png` | 共六张 72×88 RGBA，透明背景，表现五种身份与队长借身前/后的持械差分；底边为半身立绘的有意裁切。 |
| 女主战斗帧 | `sprites/heroine/{idle,walk_a,walk_b,attack_windup,attack_hit,attack_recover,hurt}.png` | 每帧 80×80 RGBA。 |
| 普通安保 / 医疗员 | `sprites/{guard,medic}/{idle,walk_a,walk_b,attack_windup,attack_hit,hurt}.png` | 每帧 80×80 RGBA；guard 近战，medic 使用医疗针，均有两相步行。 |
| 队长借身前 | `sprites/captain_melee/{idle,walk_a,walk_b,attack_windup,attack_hit,hurt}.png` | 每帧 80×80 RGBA。同一队长制服，枪收在腰侧，手持电棍近身攻击。 |
| 队长借身后 | `sprites/captain/{idle,walk_a,walk_b,attack_windup,attack_hit,hurt}.png` | 每帧 80×80 RGBA。同一队长造型，玩家取得枪械后的举枪与射击姿势。 |
| 校正者 | `sprites/corrector/{idle,attack_windup,attack_hit,hurt}.png` | 每帧 80×80 RGBA，悬浮待机；Boss 动态攻击特效由 Godot 绘制。 |

共 35 张战斗帧，全部使用相同的脚底锚点 **(40,72)**，普通 alpha 合成；脚下阴影由 Godot 绘制。武器出手姿势已区分前摇、命中与受击，但伤害和时序必须由游戏状态机结算，一次攻击只在命中事件结算一次。电光、枪口闪光、弹道、治疗效果和 Boss 攻击预警不要从人物贴图推导，应在独立视觉层绘制，防止辉光吞没人物轮廓或预警。

## 生成与复核

`manifest.json` 记录每一张正式 PNG 的路径、尺寸、色彩模式、alpha 范围与 SHA-256。复核对照图位于 `review/maps-contact.png`、`review/portraits-contact.png`、`review/sprites-contact.png`；这些是查看用合成图，不要作为游戏运行贴图。地图中只绘制静态底层；门状态、角色、前景遮挡、碰撞和交互热点仍需由 Godot 与数据层保持一致。

这套素材采用硬边像素和青紫/冷青绿/洋红三种场景色系。它是可玩的 Demo 原创候选，不是 H3 动画，也未经过用户在真实游戏窗口中的最终美术验收。人物目前只有正面朝向，女主、普通安保、队长和医疗员各有两相步行；正式多方向移动、更多受击与死亡帧、环境可遮挡前景层，以及 Boss 动态特效仍需下一轮美术制作。对照图和 PNG 逐张查看后，还应在 Godot 中实测角色比例、门的可达性、Y-sort、攻击预警的对比度与人物透明边缘。
