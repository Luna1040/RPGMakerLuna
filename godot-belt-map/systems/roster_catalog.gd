extends RefCounted
## Shared identity data for encounter portraits and the in-game character book.
## Portraits load lazily so content import order cannot break gameplay scripts.
const ORDER := ["scout","caster","elite","boss","serin"]
const ENTRIES := {
	"scout":{"name":"灰誓斥候","kind":"melee","faction":"灰誓军团","role":"近战突袭","color":"cbb4aa","description":"潜入古塔外围的游击兵。轻装利刃让他能快速贴近目标，出刀前仍会留下短暂破绽。","tactics":"留意近身攻击的红色预警。后退、跳跃或用上挑打断，可避免被连续围攻。","moves":["贴身追击 · 接近目标后进行短距离斩击。","蓄势斩击 · 预警结束后伤害结算，收招期间可以反击。"]},
	"caster":{"name":"灰誓咒术师","kind":"ranged","faction":"灰誓军团","role":"远程压制","color":"bdabeb","description":"以古塔残余魔力驱动咒术的远程兵。她会寻找施法位置，以光弹封锁前进路线。","tactics":"观察施法线，横向移动或跳跃避开弹道；地形能挡住光弹，贴身攻击可以打断蓄势。","moves":["魔能光弹 · 蓄势后发射沿直线飞行的投射物。","战术移位 · 搜索可见的目标并调整施法距离。"]},
	"elite":{"name":"灰誓重卫","kind":"elite","faction":"灰誓军团","role":"重装近战","color":"d4b47c","description":"守卫塔内通道的重甲军士。生命更高、近战攻击距离更长，挥击后的空隙也更加明显。","tactics":"不要在红色挥击区域内硬拼。引出攻击后绕开正面，再用连击压制。","moves":["重装推进 · 缓慢逼近目标，压缩躲避空间。","破阵挥击 · 更长距离的重击，拥有明确的蓄势与收招。"]},
	"boss":{"name":"陨星执政官","kind":"boss","faction":"古塔统领","role":"首领 / 区域打击","color":"e0998e","description":"占据古塔核心的灰誓统领。交替使用近身重击与锁定落点的震地攻击，逼迫挑战者持续走位。","tactics":"红色范围是即将命中的区域。震地预警出现后离开落点，趁收招打出完整连段。","moves":["统领重击 · 正面近战挥击，造成较高伤害。","陨星震地 · 锁定落点，蓄势后造成范围伤害。"]},
	"serin":{"name":"瑟琳 · 战牧","kind":"companion","faction":"苍石同行者","role":"远程支援 / 治疗 / 护盾","color":"94ded8","description":"随巡礼队驻留苍石庭院的战牧。她拥有独立生命与法力，会以圣光支援战斗，也需要你保护与照应。","tactics":"跟随作战会寻找目标；原地守卫会留在指定地点；停战跟随停止主动攻击和施法。倒下后停止作战，回城在旅店休整可复苏。","moves":["圣光弹 · 持续远程输出，不消耗法力。","治疗 · 自动照顾受伤的自己或主角，需要法力并有冷却。","圣域盾 · 危急时为自己附加护盾，吸收后续伤害。"]}
}

static func entry(id: String) -> Dictionary:
	return ENTRIES.get(id,{}).duplicate(true)

static func portrait(id: String) -> Texture2D:
	if not ENTRIES.has(id): return null
	var path:="res://assets/roster/%s/portrait.png" % id
	if not ResourceLoader.exists(path): return null
	return load(path) as Texture2D

static func from_kind(kind: String) -> String:
	return {"melee":"scout","ranged":"caster"}.get(kind,kind)
