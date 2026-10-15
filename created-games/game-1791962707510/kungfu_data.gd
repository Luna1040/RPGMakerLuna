extends RefCounted
const DATA := {
 "attack":{"name":"普通攻击","level":1,"icon":"skill_12.png"},
 "lightness":{"name":"轻功提纵术","level":5,"icon":"skill_20.png"},
 "potion":{"name":"小金创药","level":1,"icon":"potion.png"},
 "cloud_step":{"name":"梯云纵","level":10,"icon":"skill_26.png"}
}
static func icon(id: String) -> Texture2D:
 if not DATA.has(id):return null
 return load("res://assets/client-skills/"+DATA[id].icon) as Texture2D
