extends Node2D
## Whole-body authored sprite frames. This view never applies damage or rewards.
const ClipPlayer = preload("roster_animation.gd")
const FONT = preload("res://assets/fonts/NotoSansSC-subset.ttf")
const CHARACTER_IDS := {"melee":"scout","ranged":"caster","elite":"elite","boss":"boss"}
var data: Dictionary = {}
var animation := ClipPlayer.new()
var selected: Dictionary = {}

func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func visual_sample() -> Dictionary:
	if data.is_empty():
		return {}
	animation.configure(CHARACTER_IDS.get(str(data.get("kind","melee")),"scout"))
	var state := str(data.get("state","idle"))
	var action := "stand"
	var time := float(data.get("clock",0.0))*1000.0
	var loop := true
	var airborne: bool = data.has("reaction") and (data.reaction.airborne() or data.reaction.stun_left > 0.0)
	if state == "dead":
		action = "hurt"
		time = ClipPlayer.duration_ms(animation.clip(action))
		loop = false
	elif float(data.get("hurt_left",0.0)) > 0.0 or airborne:
		action = "hurt"
		time = ClipPlayer.duration_ms(animation.clip(action))*clampf(float(data.get("hurt_elapsed",0.0))/0.4,0.0,1.0)
		loop = false
	elif bool(data.get("attack_active",false)) and state in ["telegraph","attack","recover"]:
		action = "cast" if data.kind == "ranged" and animation.has_action("cast") else "attack"
		time = ClipPlayer.attack_time(animation.clip(action),float(data.get("attack_elapsed",0)),float(data.get("attack_windup",0.6)),float(data.get("attack_recovery",0.54)))
		loop = false
	elif state in ["chase","return"]:
		action = "walk"
	return animation.sample(action,time,loop)

func _draw() -> void:
	if data.is_empty():
		return
	selected = visual_sample()
	var dead: bool = data.get("state","") == "dead"
	var death_alpha := clampf(1.0-float(data.get("death_elapsed",1.0))/0.7,0.0,1.0) if dead else 1.0
	if death_alpha <= 0.0:
		return
	var lift: float = data.reaction.height if data.has("reaction") else 0.0
	draw_set_transform(Vector2.ZERO,0.0,Vector2(1,0.25))
	draw_circle(Vector2.ZERO,35 if data.kind == "boss" else 26,Color(0.02,0.04,0.06,0.35*death_alpha))
	draw_set_transform(Vector2.ZERO)
	if not selected.is_empty():
		var scale_factor := float(selected.scale)
		var tint := Color(1.0,0.95,0.93,death_alpha) if float(data.get("flash",0.0)) > 0.07 else Color(1,1,1,death_alpha)
		draw_set_transform(Vector2(0,-lift),0.0,Vector2(float(data.get("facing",1.0))*scale_factor,scale_factor))
		draw_texture(selected.texture,-selected.pivot,tint)
		draw_set_transform(Vector2.ZERO)
	if dead:
		return
	var bar_y := animation.standing_top()-12.0-lift
	draw_rect(Rect2(-39,bar_y,78,7),Color("192735"))
	draw_rect(Rect2(-38,bar_y+1,76*clampf(float(data.hp)/float(data.max_hp),0,1),5),Color("e8907d"))
	var label := str(animation.manifest.get("name",data.get("label","敌人")))
	var width := FONT.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x
	draw_string(FONT,Vector2(-width*0.5,bar_y-8),label,HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("fff0c8"))
	if selected.is_empty():
		draw_string(FONT,Vector2(-35,-100),"素材加载中",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("c6babc"))
	if data.has("reaction") and data.reaction.shock_left > 0.0:
		draw_polyline(PackedVector2Array([Vector2(-32,-lift-130),Vector2(-40,-lift-103),Vector2(-25,-lift-106),Vector2(-36,-lift-79)]),Color("9de8ff"),2)

