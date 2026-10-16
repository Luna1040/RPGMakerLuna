extends RefCounted
const DATA={
 "potion":{"name":"小金创药","price":15,"stack":9999999,"hp":60,"icon":"res://assets/client-skills/potion.png"},
 "hp_medium":{"name":"中金创药","price":40,"hp":180,"icon":"res://assets/client-services/hp_medium.png"},
 "mp_small":{"name":"小人参","price":20,"mp":30,"icon":"res://assets/client-services/mp_small.png"},
 "mp_medium":{"name":"中人参","price":50,"mp":80,"icon":"res://assets/client-services/mp_medium.png"},
 "return_scroll":{"name":"泫渤派回城符","price":50,"icon":"res://assets/client-services/return_scroll.png"},
 "blade_weapon":{"name":"精铁刀","price":150,"stack":1,"equip":"weapon","role":"blade","attack":5,"icon":"res://assets/client-services/blade_weapon.png"},
 "sword_weapon":{"name":"精铁剑","price":150,"stack":1,"equip":"weapon","role":"sword","attack":5,"icon":"res://assets/client-services/sword_weapon.png"},
 "spear_weapon":{"name":"精铁枪","price":150,"stack":1,"equip":"weapon","role":"spear","attack":5,"icon":"res://assets/client-services/spear_weapon.png"},
 "armor":{"name":"江湖布衣","price":120,"stack":1,"equip":"armor","defense":3,"icon":"res://assets/client-services/armor.png"}
}
static func valid_slots(value: Variant, count: int) -> bool:
 if not value is Array or value.size()!=count:return false
 for entry in value:
  if not entry is Dictionary:return false
  if entry.is_empty():continue
  if not DATA.has(entry.get("id")) or not (entry.get("count") is float or entry.get("count") is int):return false
  if not is_finite(float(entry.count)) or entry.count<1 or entry.count!=int(entry.count) or entry.count>DATA[entry.id].get("stack",999):return false
 return true
static func icon(id: String) -> Texture2D:
 return load(DATA[id].icon) if DATA.has(id) else null
