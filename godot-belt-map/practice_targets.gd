extends RefCounted
const Reactions = preload("dummy_reactions.gd")
const HitQuery = preload("combat_query.gd")
var stage
var targets: Array[Dictionary] = []
var total_hits := 0
var total_damage := 0.0

class TargetArt extends Node2D:
	var health := 1000.0
	var height := 0.0
	var flash := 0.0
	var shock := false
	var combo := 0
	func _draw() -> void:
		draw_set_transform(Vector2.ZERO,0,Vector2(1,0.22))
		draw_circle(Vector2.ZERO,32,Color(0,0,0,.3))
		draw_set_transform(Vector2(0,-height))
		var wood := Color("d6ad79") if flash>0 else Color("8d623e")
		draw_line(Vector2(-32,-6),Vector2(33,-6),Color("33261e"),12)
		draw_line(Vector2(0,-8),Vector2(0,-105),Color("443225"),16)
		draw_line(Vector2(-45,-96),Vector2(45,-96),Color("3b2d23"),19)
		draw_line(Vector2(-43,-96),Vector2(43,-96),wood,13)
		draw_rect(Rect2(-23,-117,46,68),Color("30291f"))
		draw_rect(Rect2(-19,-114,38,61),wood)
		for y in [-105,-68]:
			draw_line(Vector2(-20,y),Vector2(21,y),Color("ceb682"),5)
		draw_circle(Vector2(0,-140),20,Color("342b21"))
		draw_circle(Vector2(0,-140),16,wood)
		draw_circle(Vector2(0,-83),11,Color("932f2c"))
		draw_circle(Vector2(0,-83),5,Color("eec28e"))
		if shock:
			draw_polyline(PackedVector2Array([Vector2(-29,-141),Vector2(-38,-112),Vector2(-22,-114),Vector2(-35,-76)]),Color("8edbff"),3)
		draw_rect(Rect2(-46,-185,92,7),Color("171e2a"))
		draw_rect(Rect2(-45,-184,90*health/1000.0,5),Color("e7bd6d"))
		var font := ThemeDB.fallback_font
		draw_string(font,Vector2(-46,-192),"练习木桩",HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("ffdf9d"))
		if combo>1:
			draw_string(font,Vector2(35,-128),str(combo)+" 连击",HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("91dbff"))

func setup(map_stage) -> void:
	stage=map_stage
	for foot: Vector2 in [Vector2(7.0,8.3),Vector2(13.0,7.8)]:
		var art := TargetArt.new()
		art.position=stage.project(foot)
		stage.sorting.add_child(art)
		targets.append({"foot":foot,"art":art,"reaction":Reactions.new(),"hp":1000.0,"respawn":0.0})

func step(delta: float) -> void:
	for t: Dictionary in targets:
		if t.hp<=0:
			t.respawn-=delta
			if t.respawn<=0:
				t.hp=1000.0
				t.reaction.reset()
				t.art.show()
			continue
		t.hp=maxf(1,t.hp-t.reaction.step(delta))
		t.art.height=t.reaction.height
		t.art.combo=t.reaction.combo
		t.art.shock=t.reaction.shock_left>0
		t.art.health=t.hp
		t.art.flash=maxf(0,t.art.flash-delta)
		t.art.queue_redraw()

func hit(foot: Vector2, z: float, event: Dictionary) -> int:
	var count := 0
	for t: Dictionary in targets:
		if t.hp<=0: continue
		var rect := Rect2(t.foot-Vector2(.23,.22),Vector2(.46,.44))
		if HitQuery.overlaps(foot,z,rect,t.reaction.height/120.0,1.35,event):
			apply_hit(t,event)
			count+=1
	return count

func projectile(from_x: float, to_x: float, depth: float, z: float, damage: float) -> bool:
	for t: Dictionary in targets:
		if t.hp<=0 or absf(depth-t.foot.y)>.65: continue
		if z<t.reaction.height/120.0-.3 or z>t.reaction.height/120.0+1.9: continue
		if maxf(from_x,to_x)<t.foot.x-.25 or minf(from_x,to_x)>t.foot.x+.25: continue
		apply_hit(t,{"action":"magic","damage":damage})
		return true
	return false

func apply_hit(t: Dictionary, event: Dictionary) -> void:
	var action: String=event.get("action", "attack1")
	var reaction: Dictionary=t.reaction.hit("attack3" if event.get("launch",false) else action)
	var damage := float(event.get("damage",0))+float(reaction.bonus)
	t.hp=maxf(0,t.hp-damage)
	t.art.flash=.15
	total_hits+=1
	total_damage+=damage
	var number := Label.new()
	number.text=str(int(damage)) + (" 浮空" if reaction.air_hit else "")
	number.position=stage.project(t.foot)-Vector2(20,150+t.reaction.height)
	number.z_index=30
	number.add_theme_font_size_override("font_size",23)
	number.add_theme_color_override("font_color",Color("fff0ae"))
	number.add_theme_color_override("font_shadow_color",Color.BLACK)
	number.add_theme_constant_override("shadow_offset_x",2)
	number.add_theme_constant_override("shadow_offset_y",2)
	stage.add_child(number)
	var tween: Tween=stage.create_tween().set_parallel(true)
	tween.tween_property(number,"position:y",number.position.y-45,.65)
	tween.tween_property(number,"modulate:a",0.0,.65)
	tween.chain().tween_callback(number.queue_free)
	if t.hp<=0:
		t.respawn=2.0
		t.art.hide()
