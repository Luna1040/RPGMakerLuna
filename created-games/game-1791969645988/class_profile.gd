extends RefCounted
const ROLES={"剑仙":"sword","阴阳":"yinyang","魅影":"shadow","天师":"celestial"}
static func role(c: Dictionary) -> String: return str(ROLES.get(c.get("profession","剑仙"),"sword"))
static func apply(holder: Control, c: Dictionary, scale_value: float, loader: Callable) -> void:
	var key:=role(c)
	var path: String="res://assets/classes/"+key+".png"
	if not FileAccess.file_exists(path): return
	var profiles: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/classes/profiles.json")) if FileAccess.file_exists("res://assets/classes/profiles.json") else {}
	var profile: Dictionary=profiles.get(key,{"height":700,"pivot":[384,748]})
	var sprite: Sprite2D=holder.get_node("Portrait")
	sprite.texture=loader.call(path)
	sprite.centered=false
	var amount: float=72.0*scale_value/float(profile.height)
	sprite.scale=Vector2.ONE*amount
	sprite.position=-Vector2(profile.pivot[0],profile.pivot[1])*amount
