extends RefCounted
const DATA := {
 "attack":{"name":"普通攻击","level":1,"icon":"skill_12.png"},
 "lightness":{"name":"轻功提纵术","level":5,"icon":"mugong_601101.png","cost":10},
 "potion":{"name":"小金创药","level":1,"icon":"potion.png"},
 "cloud_step":{"name":"梯云纵","level":10,"icon":"mugong_601102.png","cost":15},
 "mp_small":{"name":"小人参","level":1,"icon":"../client-services/mp_small.png"},
 "hp_medium":{"name":"中金创药","level":1,"icon":"../client-services/hp_medium.png"},
 "mp_medium":{"name":"中人参","level":1,"icon":"../client-services/mp_medium.png"},
 "return_scroll":{"name":"泫渤派回城符","level":1,"icon":"../client-services/return_scroll.png"},
 "blade_10":{"name":"疾风烈火","level":10,"icon":"../client-progress/mugong_100101.png","role":"blade","cost":5,"power":30},
 "sword_10":{"name":"碧波潮生","level":10,"icon":"../client-progress/mugong_200101.png","role":"sword","cost":7,"power":35},
 "spear_10":{"name":"震云贯日","level":10,"icon":"../client-progress/mugong_300101.png","role":"spear","cost":9,"power":40}
}
static func icon(id: String) -> Texture2D:
 if not DATA.has(id):return null
 return load("res://assets/client-skills/"+DATA[id].icon) as Texture2D
