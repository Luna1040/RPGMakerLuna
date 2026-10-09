extends Node2D
var knight: CharacterBody2D
var font := SystemFont.new()
var target := Vector2(920,620)
const TARGET_MAX_HP := 1000.0
var target_hp := TARGET_MAX_HP
var target_flash := 0.0
var target_respawn := 0.0
var target_counter := 0.0
var reactions = preload("res://dummy_reactions.gd").new()
var effect_clock := 0.0
var retaliation := false
var projectiles: Array = []
var numbers: Array = []
var impacts: Array = []
var last_event := "Approach the target. J: sword combo, K: magic."
var hit_count := 0
var bolt_texture: Texture2D
var light := false
var show_hitboxes := false
const TARGET_HALF_WIDTH := 25.0
var gallery_demo := false
var demo_clock := 0.0
var demo_index := -1
var demo_actions := ["stand", "idle", "walk", "attack1", "attack2", "attack3", "cast", "hurt"]
var action_titles := {"stand":"站立呼吸", "idle":"闲置整理头发", "walk":"移动", "attack1":"一段：下劈", "attack2":"二段：突刺", "attack3":"三段：上挑", "cast":"施法", "hurt":"受击"}
var equipment_ui: CanvasLayer

func _ready() -> void:
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	if ResourceLoader.exists("res://assets/magic_bolt.png"):
		bolt_texture = load("res://assets/magic_bolt.png")
	knight = load("res://knight.tscn").instantiate()
	knight.position = Vector2(460,620)
	add_child(knight)
	knight.attack_hitbox.connect(on_attack)
	knight.spell_requested.connect(on_spell)
	knight.died.connect(func(): last_event = "Defeated - press R to reset")
	equipment_ui = preload("res://equipment_ui.gd").new()
	equipment_ui.knight = knight
	equipment_ui.arena = self
	add_child(equipment_ui)
	if "--smoke-test" in OS.get_cmdline_user_args():
		call_deferred("smoke_test")
	elif "--equipment-test" in OS.get_cmdline_user_args():
		call_deferred("equipment_test")
	elif "--capture-equipment" in OS.get_cmdline_user_args():
		call_deferred("capture_equipment")
	elif "--capture" in OS.get_cmdline_user_args():
		call_deferred("capture_gallery")

func on_attack(event: Dictionary) -> void:
	var forward_distance := (target.x - float(event["origin"].x)) * int(event["facing"])
	var base: Vector2 = target - Vector2(0,reactions.height)
	var vertical_overlap := base.y >= float(event["origin"].y)-230 and base.y-205 <= float(event["origin"].y)
	if target_hp > 0 and vertical_overlap and forward_distance + TARGET_HALF_WIDTH >= -20 and forward_distance - TARGET_HALF_WIDTH <= float(event["range"]):
		damage_target(float(event["damage"]), str(event["action"]))
	else:
		last_event = str(event["action"]) + " missed (move closer / face target)"

func on_spell(event: Dictionary) -> void:
	var bolt := Sprite2D.new()
	bolt.texture = bolt_texture
	bolt.position = event["origin"]
	bolt.scale = Vector2(0.62*int(event["facing"]),0.62)
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	bolt.material = material
	add_child(bolt)
	projectiles.append({"position":event["origin"],"velocity":Vector2(650 * int(event["facing"]),0),"damage":event["damage"],"life":1.8,"sprite":bolt})
	last_event = "Spell released - 25 mana, 2.4s cooldown"

func damage_target(amount: float, source: String, direct := true) -> void:
	if target_hp <= 0:
		return
	var result := {"bonus":0.0,"air_hit":false,"launched":false}
	if direct:
		result = reactions.hit(source)
		amount += float(result["bonus"])
	target_hp = maxf(0.0, target_hp - amount)
	target_flash = 0.14
	if direct:
		hit_count += 1
	var base: Vector2 = target - Vector2(0,reactions.height)
	var suffix := " 感电" if not direct else (" 电击!" if result["bonus"]>0 else "")
	numbers.append({"position":base + Vector2(-15,-200),"text":str(int(amount))+suffix,"life":0.75})
	impacts.append({"position":base + Vector2(0,-115),"life":0.22})
	last_event = source + " hit: " + str(int(amount))
	if result["launched"]:
		last_event = "击飞！继续按 J 可以浮空追击"
	elif result["air_hit"]:
		last_event = "浮空追击 %d 次" % reactions.air_hits
	if target_hp <= 0:
		target_respawn = 1.5
		reactions.reset()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.keycode == KEY_R:
		knight.reset_character()
		target_hp = TARGET_MAX_HP
		reactions.reset()
		target_respawn = 0
		hit_count = 0
		for p in projectiles:
			p["sprite"].queue_free()
		projectiles.clear()
	elif event.keycode == KEY_H:
		knight.apply_damage(15,target)
	elif event.keycode == KEY_T:
		retaliation = not retaliation
	elif event.keycode == KEY_B:
		light = not light
	elif event.keycode == KEY_F2:
		show_hitboxes = not show_hitboxes
	elif event.keycode == KEY_TAB:
		gallery_demo = not gallery_demo
		knight.input_enabled = not gallery_demo
		knight.set_physics_process(not gallery_demo)
		knight.position = Vector2(460,620)
		demo_clock = 0
		demo_index = -1
		if not gallery_demo:
			knight.reset_character()

func _process(delta: float) -> void:
	effect_clock += delta
	if target_hp > 0 and not gallery_demo:
		var dot: float = reactions.step(delta)
		if dot > 0:
			damage_target(dot,"shock",false)
	if gallery_demo:
		demo_clock += delta
		var index := int(demo_clock / 3.0) % demo_actions.size()
		if index != demo_index:
			demo_index = index
			knight.mana = 100
			knight.change_action(demo_actions[index])
			last_event = "Animation gallery: " + demo_actions[index]
		knight.elapsed = fmod(knight.elapsed + delta,float(knight.clips[knight.state]["duration_ms"])/1000.0)
		knight.fired = knight.elapsed * 1000.0 >= float(knight.clips[knight.state].get("event_ms",0))
		knight.show_frame()
		knight.queue_redraw()
	knight.position.x = clampf(knight.position.x,100,1180)
	target_flash = maxf(0.0,target_flash-delta)
	if target_respawn > 0:
		target_respawn -= delta
		if target_respawn <= 0:
			target_hp = TARGET_MAX_HP
			reactions.reset()
	target_counter += delta
	if retaliation and target_counter > 2.0 and target_hp > 0 and not reactions.airborne() and reactions.stun_left <= 0:
		target_counter = 0
		if absf(knight.position.x-target.x)<180:
			knight.apply_damage(12,target)
	for i in range(projectiles.size()-1,-1,-1):
		var p: Dictionary = projectiles[i]
		var old_x: float = p["position"].x
		p["position"] += p["velocity"] * delta
		p["sprite"].position = p["position"]
		p["life"] -= delta
		# Swept interval avoids tunnelling at lower frame rates.
		if target_hp > 0 and absf(p["position"].y-(target.y-reactions.height-140))<90 and minf(old_x,p["position"].x) <= target.x+25 and maxf(old_x,p["position"].x) >= target.x-25:
			damage_target(p["damage"],"magic")
			p["sprite"].queue_free()
			projectiles.remove_at(i)
		elif p["life"] <= 0:
			p["sprite"].queue_free()
			projectiles.remove_at(i)
	for list in [numbers,impacts]:
		for i in range(list.size()-1,-1,-1):
			list[i]["life"] -= delta
			if list[i]["life"] <= 0:
				list.remove_at(i)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0,0,1280,800),Color("d5e0e9") if light else Color("111a28"))
	for x in range(0,1280,40):
		draw_line(Vector2(x,220),Vector2(x,660),Color(0.4,0.55,0.7,0.08))
	draw_line(Vector2(40,623),Vector2(1240,623),Color("60788e"),2)
	var ink := Color("203548") if light else Color("e1e9f3")
	draw_string(font,Vector2(474,48),"姬骑士 · 战斗训练场",HORIZONTAL_ALIGNMENT_LEFT,-1,26,ink)
	draw_string(font,Vector2(474,84),"A/D 移动   J 三段连击   K 施法   E 装备",HORIZONTAL_ALIGNMENT_LEFT,-1,18,ink)
	draw_string(font,Vector2(474,113),"H 受击   R 重置   T 反击   B 背景   Tab 动作   F2 判定",HORIZONTAL_ALIGNMENT_LEFT,-1,17,ink)
	if not is_instance_valid(knight):
		return
	if show_hitboxes:
		var attack: String = knight.state if knight.state.begins_with("attack") else "attack1"
		var reach: float = knight.get_attack_reach(attack)
		var left: float = knight.position.x - 20 if knight.facing > 0 else knight.position.x - reach
		draw_rect(Rect2(left,knight.position.y-230,reach+20,230),Color(0.3,1,0.6,0.12))
		draw_rect(Rect2(left,knight.position.y-230,reach+20,230),Color(0.3,1,0.6,0.8),false,2)
		draw_rect(Rect2(target.x-TARGET_HALF_WIDTH,target.y-reactions.height-205,TARGET_HALF_WIDTH*2,205),Color(1,0.6,0.2,0.8),false,2)
	draw_string(font,Vector2(474,156),"K 感电 → J 上挑击飞 → 继续 J 浮空追击",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("83d9fa"))
	draw_string(font,Vector2(35,713),"动作：%s / 帧 %d   |   命中 %d 次   |   木桩反击：%s" % [action_titles.get(knight.state,knight.state),knight.action_frame,hit_count,"开" if retaliation else "关"],HORIZONTAL_ALIGNMENT_LEFT,-1,19,ink)
	draw_string(font,Vector2(35,752),last_event,HORIZONTAL_ALIGNMENT_LEFT,-1,19,ink)
	if target_hp > 0:
		var base: Vector2 = target - Vector2(0,reactions.height)
		var wood := Color("ffd799") if target_flash > 0 else Color("a98460")
		draw_line(target+Vector2(-28,0),target+Vector2(28,0),Color(0.3,0.4,0.5,0.6),5)
		draw_line(base, base+Vector2(0,-155),wood,12)
		draw_line(base+Vector2(-48,-122),base+Vector2(48,-122),wood,10)
		draw_circle(base+Vector2(0,-180),24,wood)
		draw_circle(base+Vector2(0,-120),25,Color("e7bca0"),false,3)
		draw_rect(Rect2(base.x-50,base.y-225,100*target_hp/TARGET_MAX_HP,6),Color("eb996a"))
		var status := "%d 连击" % reactions.combo if reactions.combo>0 else "训练木桩"
		if reactions.airborne():
			status += " · 浮空 %d" % reactions.air_hits
		if reactions.shock_left > 0:
			status += " · 感电 %.1fs" % reactions.shock_left
			var points := PackedVector2Array()
			for i in range(12):
				points.append(base+Vector2(sin(effect_clock*24+i*4.3)*32,-18-i*17))
			draw_polyline(points,Color("89e5ff"),2.0,true)
		draw_string(font,base+Vector2(-90,-245),status,HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("83d9fa"))
	for p in projectiles:
		if bolt_texture == null:
			draw_circle(p["position"],10,Color("77d8ff"))
	for n in numbers:
		draw_string(font,n["position"]+Vector2(0,-(0.75-n["life"])*65),n["text"],HORIZONTAL_ALIGNMENT_LEFT,-1,28,Color("ffc97c"))
	for hit in impacts:
		draw_arc(hit["position"],12+(0.22-hit["life"])*170,0,TAU,24,Color(1,0.85,0.5,hit["life"]/0.22),3)

func equipment_test() -> void:
	await preload("res://equipment_tests.gd").new().run(self)

func capture_equipment() -> void:
	knight.input_enabled = false
	knight.set_physics_process(false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://captures/equipment-hud.png")
	equipment_ui.toggle()
	equipment_ui.select_item("guardian_armor")
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://captures/equipment-panel.png")
	equipment_ui.equip_selected()
	equipment_ui.select_item("arcane_sword")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://captures/equipment-equipped.png")
	equipment_ui.toggle()
	print("EQUIPMENT UI CAPTURE PASS")
	get_tree().quit()

func smoke_test() -> void:
	knight.input_enabled = false
	var state = preload("res://dummy_reactions.gd").new()
	state.hit("magic")
	assert(state.hit("attack1")["bonus"] == 6,"Shocked melee must trigger bonus damage")
	assert(is_equal_approx(state.step(4.1),32.0),"Shock must tick eight times without recursion")
	assert(state.shock_left == 0 and state.hit("attack1")["bonus"] == 0,"Shock must expire")
	state.reset()
	state.hit("attack3")
	state.step(0.72)
	assert(state.height>50,"Launch must stay airborne long enough to chain next attack")
	assert(state.hit("attack1")["air_hit"],"Follow-up must count as air combo")
	assert(state.rise_speed>=210 and state.air_hold>0,"Air hit must suspend and relaunch")
	for i in range(6):
		state.hit("attack2")
	state.rise_speed = -50
	state.air_hold = 0
	state.hit("attack3")
	assert(state.rise_speed == -50,"Juggle limit must prevent indefinite relaunch")
	state.step(3)
	assert(not state.airborne() and state.air_hits==0,"Target must land and clear air count")
	state.hit("magic")
	state.hit("attack3")
	state.reset()
	assert(state.shock_left==0 and not state.airborne() and state.combo==0,"Reset must clear target states")
	for action in ["attack1","attack2","attack3"]:
		for direction in [-1,1]:
			var reach: float = knight.get_attack_reach(action)
			for distance in [reach+TARGET_HALF_WIDTH-1,reach+TARGET_HALF_WIDTH+1]:
				target_hp = 250
				reactions.reset()
				var previous_hits := hit_count
				on_attack({"origin":Vector2(target.x-distance*direction,target.y),"facing":direction,"range":reach,"damage":1,"action":action})
				assert(hit_count-previous_hits == (1 if distance<reach+TARGET_HALF_WIDTH else 0),"Melee edge overlap boundary failed")
			var previous_hits := hit_count
			on_attack({"origin":Vector2(target.x+200*direction,target.y),"facing":direction,"range":reach,"damage":1,"action":action})
			assert(hit_count==previous_hits,"A target behind the character must not be hit")
	hit_count = 0
	target_hp = 250
	reactions.reset()
	knight.position.x = target.x-120
	knight.request_attack()
	await get_tree().create_timer(0.22).timeout
	knight.request_attack()
	await get_tree().create_timer(0.6).timeout
	knight.request_attack()
	await get_tree().create_timer(1.8).timeout
	assert(hit_count == 3, "Combo must hit exactly once per strike")
	knight.request_cast()
	var mana_after_cast: float = knight.mana
	knight.request_cast()
	assert(knight.mana == mana_after_cast,"Cooldown must prevent duplicate spend")
	await get_tree().create_timer(1.8).timeout
	assert(hit_count == 4,"Spell must hit once")
	knight.apply_damage(15,target)
	assert(knight.health == 85 and knight.state == "hurt","Damage must enter hurt")
	await get_tree().create_timer(1.0).timeout
	assert(knight.state == "stand","Hurt must recover")
	knight.apply_damage(200,target)
	assert(knight.defeated,"Lethal damage must disable combat")
	knight.reset_character()
	assert(knight.health == 100 and not knight.defeated,"Reset must restore health")
	# Actual timeline: buffer a fourth attack during the uppercut recovery.
	reactions.reset()
	target_hp = TARGET_MAX_HP
	hit_count = 0
	knight.change_action("attack3")
	await get_tree().create_timer(0.3).timeout
	knight.request_attack()
	await get_tree().create_timer(0.72).timeout
	assert(hit_count==2 and reactions.air_hits==1,"Uppercut must chain into a real airborne hit")
	assert(reactions.height>0,"Target must still be visibly airborne after follow-up")
	reactions.height = 300
	reactions.rise_speed = 0
	var hits_before := hit_count
	on_attack({"origin":knight.global_position,"facing":1,"range":500,"damage":1,"action":"attack1"})
	assert(hit_count==hits_before,"Melee must miss targets above its vertical reach")
	print("CHARACTER MECHANICS PASS: shock ticks/bonus/expiry, launch, air combo, juggle limit, landing, vertical hitbox, melee boundaries, combo, spell, cooldown, damage, reset")
	get_tree().quit()

func capture_gallery() -> void:
	knight.input_enabled = false
	knight.set_physics_process(false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	for action in demo_actions:
		knight.change_action(action)
		knight.elapsed = float(knight.clips[action].get("event_ms",float(knight.clips[action]["duration_ms"])*0.5))/1000.0
		knight.show_frame()
		last_event = "Character animation: " + action
		queue_redraw()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://captures/"+action+".png")
	reactions.reset()
	reactions.hit("magic")
	reactions.hit("attack3")
	reactions.step(0.45)
	reactions.hit("attack1")
	knight.change_action("attack3")
	knight.elapsed = 0.27
	knight.show_frame()
	last_event = "感电 + 击飞 + 浮空追击"
	queue_redraw()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://captures/reactions.png")
	print("CAPTURED ALL EIGHT ACTIONS")
	get_tree().quit()
