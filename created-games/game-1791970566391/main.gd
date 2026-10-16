extends Node2D

const Data = preload("res://game_data.gd")
const State = preload("res://run_state.gd")
const SCREEN := Vector2(320, 180)
const BAR_VIEW_SIZE := Vector2(768, 432)
const BAR_VIEW_SCALE := 5.0 / 12.0
const BAR_INTERACT_DURATION := 0.8
const MIX_POUR_DURATION := 0.72
const CELLAR_SAVE_PATH := "user://last_night_cellar.cfg"
const CYAN := Color("4cc9d8")
const AMBER := Color("e7b95a")
const MAGENTA := Color("d957a8")
const RED := Color("f04b55")
const INK := Color("090d18")

enum Phase { TITLE, BAR, DIALOGUE, MIX, TRANSITION, ROOM, UPGRADE, CAUSAL, RETURN_BAR, SETTLEMENT, FACILITY, CREDITS, DEAD }

const BAR_WORLD_SIZE := Vector2(768, 432)
const BAR_SPAWN := Vector2(384, 405)
const BAR_RETURN_SPAWN := Vector2(384, 350)
const BAR_MIX_HOTSPOT := Rect2(296, 126, 36, 34)
const BAR_MIX_POS := Vector2(325, 185)
const BAR_COMMS_POS := Vector2(290, 350)
const BAR_COMMS_ART_POS := Vector2(258, 350)
const BAR_ZHOU_POS := Vector2(230, 230)
const BAR_ZHOU_ENTRY_START := Vector2(345, 505)
const BAR_ZHOU_ENTRY_ROUTE := [Vector2(345, 405), Vector2(250, 405), Vector2(250, 230), BAR_ZHOU_POS]
const BAR_ZHOU_WALK_SPEED := 120.0
const BAR_WINDOW_POS := Vector2(240, 70)
const BAR_COASTER_POS := Vector2(220, 130)
const BAR_ARCHIVE_POS := Vector2(490, 95)
const BAR_DANCE_POS := Vector2(620, 145)
const BAR_DANCE_NPC_ANCHORS := [Vector2(590,235), Vector2(680,300)]
const BAR_COUNTER_SORT_Y := 309.0
const BAR_SPRITE_PIVOT := Vector2(40, 72)
const BAR_COLLIDERS := [
	Rect2(20,95,185,85), Rect2(20,195,185,75), Rect2(20,295,205,75),
	Rect2(270,120,40,190), Rect2(450,120,40,190), Rect2(310,120,140,44),
	Rect2(270,242,102,68), Rect2(404,242,86,68),
	Rect2(280,30,195,65), Rect2(540,65,195,67),
]

var phase := Phase.TITLE
var state: RunState = State.new()
var ui_font: Font
var title_texture: Texture2D
var bar_texture: Texture2D
var bar_foreground_texture: Texture2D
var bartender_texture: Texture2D
var zhou_texture: Texture2D
var mixer_shaker_texture: Texture2D
var mixer_glass_texture: Texture2D
var mixer_bottle_textures := {}
var mixer_drinks: Array[Dictionary] = []
var bartender_walk_frames: Array[Texture2D] = []
var bartender_interact_frames: Array[Texture2D] = []
var zhou_walk_frames: Array[Texture2D] = []
var zhou_interact_frames: Array[Texture2D] = []
var bar_walk_time := 0.0
var bar_is_walking := false
var bar_action_time := 0.0
var bar_action_active := false
var bar_pending_action := ""
var zhou_action_time := 0.0
var zhou_action_active := false
var zhou_walk_time := 0.0
var zhou_route_index := 0
var zhou_arrived := false
var zhou_is_walking := false
var zhou_pos := BAR_ZHOU_ENTRY_START
var title_menu_index := 0
var title_notice := ""
var title_notice_time := 0.0
var elapsed := 0.0
var rng := RandomNumberGenerator.new()
var paused := false
var bar_stage := "intro"
var bar_player := BAR_SPAWN
var interaction_hint := ""
var dialogue_id := "arrival"
var dialogue_selected := 0
var dialogue_flags := {}
var toast_text := ""
var toast_time := 0.0
var mix_selected_id := "still_sea"
var mix_added_ids: Array[String] = []
var mix_cellar_open := false
var mix_pour_id := ""
var mix_pour_time := 0.0
var mix_message := "单击查看属性，双击酒瓶倒入杯中。"
var cocktail_ids: Array[String] = []
var persistence_enabled := true
var room_index := 0
var room_clear := false
var door_visible := false
var anchor_ready := false
var player := {}
var enemies: Array = []
var projectiles: Array = []
var hazards: Array = []
var particles: Array = []
var upgrades: Array[String] = []
var upgrade_options: Array = []
var witness_downed := false
var witness_pos := Vector2.ZERO
var borrowed := false
var aim_point := Vector2(260, 90)
var last_move := Vector2.RIGHT
var attack_cd := 0.0
var q_cd := 0.0
var dash_time := 0.0
var dash_dir := Vector2.RIGHT
var dash_charges := 1
var dash_max := 1
var dash_recover := 0.0
var shield := 0
var hit_count := 0
var attack_count := 0
var paradox_factor := 1.0
var anger_reward := false
var flash := 0.0
var shake := 0.0
var settlement_lines: Array[String] = []
var mix_hotspot_hovered := false
var bar_mouse_active := false
var transition_time := 0.0

func _ready() -> void:
	rng.seed = 1791970566391
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ui_font = load("res://font.ttf")
	title_texture = load("res://assets/title-cover-remote-pixel.png")
	bar_texture = load("res://assets/bar-lounge-dancefloor-gap-pixel.png")
	bar_foreground_texture = load("res://assets/bar-lounge-dancefloor-gap-foreground.png")
	bartender_texture = load("res://assets/bartender-idle-static-large-80.png")
	zhou_texture = load("res://assets/zhou-idle-static-large-80.png")
	bartender_walk_frames = load_bar_frames("bartender", "walk")
	bartender_interact_frames = load_bar_frames("bartender", "interact")
	zhou_walk_frames = load_bar_frames("zhou", "walk")
	zhou_interact_frames = load_bar_frames("zhou", "interact")
	mixer_drinks = Data.all_drinks()
	for drink in mixer_drinks:
		mixer_bottle_textures[drink.id] = load("res://assets/mixer/%s.png" % drink.id) as Texture2D
	mixer_shaker_texture = load("res://assets/mixer/shaker.png")
	mixer_glass_texture = load("res://assets/mixer/mixing_glass.png")
	load_cellar()
	reset_player_stats()
	queue_redraw()

func load_bar_frames(role: String, action: String) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	for i in range(8):
		var path := "res://assets/bar-motion/%s/%s/%02d.png" % [role, action, i]
		if ResourceLoader.exists(path): frames.append(load(path) as Texture2D)
	return frames

func load_cellar(path: String = CELLAR_SAVE_PATH) -> void:
	if not persistence_enabled or (DisplayServer.get_name() == "headless" and path == CELLAR_SAVE_PATH): return
	var config := ConfigFile.new()
	if config.load(path) != OK: return
	state.credits = maxi(0, int(config.get_value("cellar", "credits", 0)))
	var saved = config.get_value("cellar", "unlocked", [])
	if saved is Array:
		for value in saved:
			var id := str(value)
			if not Data.drink_by_id(id).is_empty() and not state.is_drink_unlocked(id):
				state.unlocked_drinks.append(id)

func save_cellar(path: String = CELLAR_SAVE_PATH) -> void:
	if not persistence_enabled or (DisplayServer.get_name() == "headless" and path == CELLAR_SAVE_PATH): return
	var config := ConfigFile.new()
	config.set_value("cellar", "credits", state.credits)
	config.set_value("cellar", "unlocked", state.unlocked_drinks)
	var result := config.save(path)
	if result != OK: push_warning("酒库进度暂未写入本机：%s" % error_string(result))

func phase_name() -> String:
	return Phase.keys()[phase]

func _process(delta: float) -> void:
	elapsed += delta
	toast_time = maxf(0.0, toast_time - delta)
	title_notice_time = maxf(0.0, title_notice_time - delta)
	flash = maxf(0.0, flash - delta * 4.0)
	shake = maxf(0.0, shake - delta * 18.0)
	for p in particles:
		p.pos += p.vel * delta
		p.life -= delta
	particles = particles.filter(func(p): return p.life > 0.0)
	if not paused:
		if phase in [Phase.BAR, Phase.RETURN_BAR]: update_bar(delta)
		elif phase == Phase.MIX: update_mixer(delta)
		elif phase == Phase.TRANSITION: update_transition(delta)
		elif phase == Phase.ROOM: update_room(delta)
		if zhou_action_active:
			zhou_action_time += delta
			if zhou_action_time >= BAR_INTERACT_DURATION: zhou_action_active = false
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		aim_point = event.position
		if phase == Phase.TITLE:
			for i in range(4):
				if title_button_rect(i).has_point(event.position): title_menu_index = i
		elif phase == Phase.BAR:
			bar_mouse_active = true
			mix_hotspot_hovered = BAR_MIX_HOTSPOT.has_point(bar_screen_to_world(event.position))
			if mix_hotspot_hovered: interaction_hint = "开始调制"
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if paused: return
		if phase == Phase.TITLE:
			for i in range(4):
				if title_button_rect(i).has_point(event.position): title_menu_index = i; activate_title_menu()
		elif phase == Phase.BAR and BAR_MIX_HOTSPOT.has_point(bar_screen_to_world(event.position)):
			begin_bar_action("mix")
		elif phase == Phase.MIX:
			handle_mix_click(event.position, event.double_click)
		elif phase == Phase.ROOM and not paused: normal_attack((aim_point - player.pos).normalized())
		return
	if not (event is InputEventKey and event.pressed and not event.echo): return
	var key: Key = event.keycode
	if key == KEY_ESCAPE and phase == Phase.MIX:
		if mix_cellar_open: mix_cellar_open = false
		elif mix_pour_id.is_empty(): phase = Phase.BAR
		return
	if key == KEY_ESCAPE and phase not in [Phase.TITLE, Phase.CREDITS]:
		paused = not paused
		return
	if paused: return
	match phase:
		Phase.TITLE:
			if key in [KEY_UP, KEY_W]: title_menu_index = wrapi(title_menu_index - 1, 0, 4)
			elif key in [KEY_DOWN, KEY_S]: title_menu_index = wrapi(title_menu_index + 1, 0, 4)
			elif key in [KEY_1, KEY_2, KEY_3, KEY_4]: title_menu_index = key - KEY_1; activate_title_menu()
			elif key in [KEY_ENTER, KEY_SPACE]: activate_title_menu()
		Phase.BAR, Phase.RETURN_BAR:
			if key == KEY_E: begin_bar_action("interact")
		Phase.DIALOGUE:
			handle_dialogue_input(key)
		Phase.MIX:
			handle_mix_input(key)
		Phase.ROOM:
			if key in [KEY_J, KEY_F]: normal_attack(keyboard_aim())
			elif key == KEY_SPACE: dash()
			elif key == KEY_Q: use_skill()
			elif key == KEY_E: interact_room()
		Phase.UPGRADE:
			if key in [KEY_1, KEY_2, KEY_3]: choose_upgrade(key - KEY_1)
		Phase.CAUSAL:
			if key in [KEY_1, KEY_2, KEY_3]: choose_causal(key - KEY_1)
		Phase.SETTLEMENT:
			if key in [KEY_ENTER, KEY_SPACE]: phase = Phase.FACILITY
		Phase.FACILITY:
			if key in [KEY_1, KEY_2]: choose_facility(key - KEY_1)
		Phase.CREDITS:
			if key == KEY_R: restart_demo()
		Phase.DEAD:
			if key == KEY_R: enter_room(room_index)

func movement_input() -> Vector2:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): move.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): move.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): move.y += 1.0
	if move.length_squared() > 0.0:
		move = move.normalized()
		last_move = move
	return move

func title_button_rect(index: int) -> Rect2:
	return Rect2(232, 104 + index * 15, 78, 13)

func activate_title_menu() -> void:
	if title_menu_index == 0:
		bar_player = BAR_SPAWN; bar_mouse_active = false; bar_action_active = false
		start_zhou_entrance(); phase = Phase.BAR
	else:
		title_notice = ["", "继续委托将在存档系统完成后开放", "载入昨日将在存档系统完成后开放", "游戏设置尚未开放"][title_menu_index]
		title_notice_time = 2.4

func start_zhou_entrance() -> void:
	zhou_pos = BAR_ZHOU_ENTRY_START
	zhou_route_index = 0
	zhou_arrived = false
	zhou_is_walking = false
	zhou_walk_time = 0.0
	zhou_action_active = false
	zhou_action_time = 0.0

func advance_zhou_entrance(delta: float) -> void:
	var travel := maxf(0.0, delta) * BAR_ZHOU_WALK_SPEED
	var previous := zhou_pos
	while travel > 0.0 and zhou_route_index < BAR_ZHOU_ENTRY_ROUTE.size():
		var target: Vector2 = BAR_ZHOU_ENTRY_ROUTE[zhou_route_index]
		var distance := zhou_pos.distance_to(target)
		if distance <= travel:
			zhou_pos = target
			zhou_route_index += 1
			travel -= distance
		else:
			zhou_pos = zhou_pos.move_toward(target, travel)
			travel = 0.0
	zhou_arrived = zhou_route_index >= BAR_ZHOU_ENTRY_ROUTE.size()
	zhou_is_walking = not zhou_arrived and zhou_pos != previous
	if zhou_is_walking: zhou_walk_time += delta

func update_bar(delta: float) -> void:
	if bar_action_active:
		bar_is_walking = false
		bar_action_time += delta
		if bar_action_time >= BAR_INTERACT_DURATION:
			bar_action_active = false
			if bar_pending_action == "mix": open_mixer()
			else: interact_bar()
			bar_pending_action = ""
			if phase not in [Phase.BAR, Phase.RETURN_BAR]: return
	else:
		var previous := bar_player
		move_bar_player(movement_input() * 64.0 * delta)
		bar_is_walking = bar_player != previous
		if bar_is_walking: bar_walk_time += delta
	if phase == Phase.BAR and bar_stage == "intro" and not zhou_arrived:
		advance_zhou_entrance(delta)
	else:
		zhou_is_walking = false
	if bar_mouse_active:
		mix_hotspot_hovered = phase == Phase.BAR and BAR_MIX_HOTSPOT.has_point(bar_screen_to_world(aim_point))
	else:
		mix_hotspot_hovered = false
	interaction_hint = ""
	if phase == Phase.RETURN_BAR and bar_player.distance_to(BAR_COMMS_POS) < 30.0:
		interaction_hint = "E  接听结尾来电" if bar_stage == "ending_ready" else "E  查看委托结算"
	elif phase == Phase.BAR and bar_player.distance_to(BAR_MIX_POS) < 28.0:
		interaction_hint = "开始调制"
	elif phase == Phase.BAR and bar_stage == "intro" and zhou_arrived and bar_player.distance_to(zhou_pos) < 28.0:
		interaction_hint = "E  与周骁交谈"
	elif bar_player.distance_to(BAR_WINDOW_POS) < 28.0:
		interaction_hint = "E  查看雨窗"
	elif bar_player.distance_to(BAR_COASTER_POS) < 26.0:
		interaction_hint = "E  查看遗留杯垫"
	elif bar_player.distance_to(BAR_ARCHIVE_POS) < 30.0:
		interaction_hint = "E  查看档案墙"
	elif bar_player.distance_to(BAR_DANCE_POS) < 32.0:
		interaction_hint = "E  聆听舞池节拍"
	if mix_hotspot_hovered: interaction_hint = "开始调制"

func begin_bar_action(action: String) -> void:
	if bar_action_active or phase not in [Phase.BAR, Phase.RETURN_BAR]: return
	if action == "interact" and not bar_interaction_in_reach(): return
	bar_action_active = true
	bar_action_time = 0.0
	bar_pending_action = action
	bar_is_walking = false

func bar_interaction_in_reach() -> bool:
	if phase == Phase.RETURN_BAR and bar_player.distance_to(BAR_COMMS_POS) < 32.0: return true
	if phase == Phase.BAR and bar_player.distance_to(BAR_MIX_POS) < 30.0: return true
	if phase == Phase.BAR and bar_stage == "intro" and zhou_arrived and bar_player.distance_to(zhou_pos) < 30.0: return true
	return bar_player.distance_to(BAR_WINDOW_POS) < 30.0 or bar_player.distance_to(BAR_COASTER_POS) < 28.0 or bar_player.distance_to(BAR_ARCHIVE_POS) < 32.0 or bar_player.distance_to(BAR_DANCE_POS) < 34.0

func bar_camera_origin() -> Vector2:
	# Keep all three bar districts visible while the player moves between them.
	return Vector2.ZERO

func bar_world_to_screen(world_position: Vector2) -> Vector2:
	return pixel((world_position-bar_camera_origin())*BAR_VIEW_SCALE)

func bar_screen_to_world(screen_position: Vector2) -> Vector2:
	return pixel(screen_position/BAR_VIEW_SCALE+bar_camera_origin())

func bar_world_to_view(world_position: Vector2) -> Vector2:
	return pixel(world_position-bar_camera_origin())

func bar_hotspot_screen_rect() -> Rect2:
	return Rect2(bar_world_to_screen(BAR_MIX_HOTSPOT.position),pixel(BAR_MIX_HOTSPOT.size*BAR_VIEW_SCALE))

func bar_position_walkable(position: Vector2) -> bool:
	if position.x < 12.0 or position.x > BAR_WORLD_SIZE.x - 12.0 or position.y < 28.0 or position.y > BAR_WORLD_SIZE.y - 12.0:
		return false
	var feet := Rect2(position - Vector2(6, 5), Vector2(12, 7))
	for collider in BAR_COLLIDERS:
		if feet.intersects(collider): return false
	return true

func move_bar_player(displacement: Vector2) -> void:
	var next_x := bar_player + Vector2(displacement.x, 0)
	if bar_position_walkable(next_x): bar_player = next_x
	var next_y := bar_player + Vector2(0, displacement.y)
	if bar_position_walkable(next_y): bar_player = next_y
	bar_player = pixel(bar_player)

func interact_bar() -> void:
	if phase == Phase.RETURN_BAR and bar_player.distance_to(BAR_COMMS_POS) < 32.0:
		if bar_stage == "ending_ready": phase = Phase.CREDITS
		else: prepare_settlement()
		return
	if phase == Phase.BAR and bar_player.distance_to(BAR_MIX_POS) < 30.0:
		open_mixer()
	elif phase == Phase.BAR and bar_stage == "intro" and zhou_arrived and bar_player.distance_to(zhou_pos) < 30.0:
		dialogue_id = "arrival"; dialogue_selected = 0; phase = Phase.DIALOGUE
		zhou_action_time = 0.0; zhou_action_active = true
	elif bar_player.distance_to(BAR_WINDOW_POS) < 30.0:
		inspect_bar_object("rain_window")
	elif bar_player.distance_to(BAR_COASTER_POS) < 28.0:
		inspect_bar_object("coaster")
	elif bar_player.distance_to(BAR_ARCHIVE_POS) < 32.0:
		inspect_bar_object("archive")
	elif bar_player.distance_to(BAR_DANCE_POS) < 34.0:
		inspect_bar_object("dancefloor")

func inspect_bar_object(id: String) -> void:
	match id:
		"rain_window":
			if not dialogue_flags.get("rain_window_seen", false):
				dialogue_flags["rain_window_seen"] = true
				state.add_clue("rain_window_trace")
				show_toast("雨痕逆着重力爬升。你记下了旧时间线的坐标。")
			elif phase == Phase.RETURN_BAR:
				show_toast("改写后，只有那道逆流雨痕仍停在原来的位置。")
			else: show_toast("玻璃上映出一座不存在于城市档案里的高塔。")
		"coaster":
			dialogue_flags["coaster_seen"] = true
			show_toast("杯垫背面刻着：十二年前，黎雾点过一杯静海。")
		"archive":
			dialogue_flags["archive_seen"] = true
			show_toast("档案墙：周骁 / 七号街枪击案 / 已固定线索 "+str(state.clues.size()))
		"dancefloor":
			if not dialogue_flags.get("dancefloor_seen", false):
				dialogue_flags["dancefloor_seen"] = true
				show_toast("低频穿过灯砖，舞池留下两处适合低声交谈的静区。")
			else:
				show_toast("节拍在镜面与金属之间折返，恰好掩住桌边的谈话声。")

func open_mixer() -> void:
	mix_hotspot_hovered = false
	mix_selected_id = "still_sea"
	mix_added_ids.clear()
	mix_cellar_open = false
	mix_pour_id = ""
	mix_pour_time = 0.0
	mix_message = "单击查看属性，双击酒瓶倒入杯中。"
	phase = Phase.MIX

func mix_bottle_rect(index: int) -> Rect2:
	return Rect2(12 + index * 33, 42, 30, 69)

func mix_cellar_card_rect(index: int) -> Rect2:
	return Rect2(8 + (index % 2) * 154, 32 + floori(float(index) / 2.0) * 43, 146, 40)

func mix_back_rect() -> Rect2:
	return Rect2(6, 5, 24, 18)

func mix_cellar_button_rect() -> Rect2:
	return Rect2(256, 5, 56, 19)

func mix_undo_button_rect() -> Rect2:
	return Rect2(269, 116, 41, 15)

func mix_finish_button_rect() -> Rect2:
	return Rect2(220, 141, 90, 23)

func mix_cellar_buy_button_rect() -> Rect2:
	return Rect2(224, 163, 88, 15)

func update_mixer(delta: float) -> void:
	if mix_pour_id.is_empty(): return
	mix_pour_time += delta
	if mix_pour_time >= MIX_POUR_DURATION:
		var poured := mix_pour_id
		mix_pour_id = ""
		mix_pour_time = 0.0
		mix_added_ids.append(poured)
		mix_message = "%s 已倒入调酒杯（%d / 3）。" % [Data.drink_by_id(poured).name, mix_added_ids.size()]

func start_mix_pour(id: String) -> void:
	if not mix_pour_id.is_empty():
		mix_message = "先等这一瓶倒完。"
		return
	if not state.is_drink_unlocked(id):
		mix_message = "这瓶尚未解锁，请到酒库查看。"
		return
	if id in mix_added_ids:
		mix_message = "同一种酒已加入，换一瓶试试。"
		return
	if mix_added_ids.size() >= 3:
		mix_message = "一杯最多加入三种酒。"
		return
	mix_pour_id = id
	mix_pour_time = 0.0
	mix_message = "正在倒入 %s…" % Data.drink_by_id(id).name

func undo_mix_pour() -> void:
	if not mix_pour_id.is_empty():
		mix_message = "请等倒酒动画结束。"
	elif mix_added_ids.is_empty():
		mix_message = "杯中还没有酒。"
	else:
		var removed: String = mix_added_ids.pop_back()
		mix_message = "已撤回 %s。" % Data.drink_by_id(removed).name

func buy_selected_drink() -> void:
	var drink: Dictionary = Data.drink_by_id(mix_selected_id)
	if drink.is_empty(): return
	if state.is_drink_unlocked(mix_selected_id):
		mix_message = "%s 已在酒库中。" % drink.name
	elif state.buy_drink(mix_selected_id):
		save_cellar()
		mix_message = "已解锁 %s · %s，剩余 %d 信用点。" % [drink.name, drink.quality, state.credits]
	else:
		mix_message = "解锁 %s 还需 %d 信用点。" % [drink.name, maxi(0, int(drink.cost) - state.credits)]

func handle_mix_click(position: Vector2, double_click: bool) -> void:
	if mix_cellar_open:
		if mix_back_rect().has_point(position) or mix_cellar_button_rect().has_point(position):
			mix_cellar_open = false
			return
		if mix_cellar_buy_button_rect().has_point(position):
			buy_selected_drink()
			return
		for i in range(mixer_drinks.size()):
			if mix_cellar_card_rect(i).has_point(position):
				mix_selected_id = mixer_drinks[i].id
				mix_message = "%s · %s：%s" % [mixer_drinks[i].name, mixer_drinks[i].quality, mixer_drinks[i].desc]
				return
		return
	if mix_back_rect().has_point(position):
		if mix_pour_id.is_empty(): phase = Phase.BAR
		return
	if mix_cellar_button_rect().has_point(position):
		if not mix_pour_id.is_empty():
			mix_message = "请等倒酒动画结束。"
			return
		mix_cellar_open = true
		mix_message = "选择酒种，再用信用点解锁。"
		return
	if mix_undo_button_rect().has_point(position):
		undo_mix_pour()
		return
	if mix_finish_button_rect().has_point(position):
		finish_mix()
		return
	for i in range(mixer_drinks.size()):
		if mix_bottle_rect(i).has_point(position):
			var id: String = mixer_drinks[i].id
			var was_selected := mix_selected_id == id
			mix_selected_id = id
			mix_message = "%s · %s：%s" % [mixer_drinks[i].name, mixer_drinks[i].quality, mixer_drinks[i].desc]
			if double_click and was_selected: start_mix_pour(id)
			return

func handle_dialogue_input(key: Key) -> void:
	var node: Dictionary = Data.DIALOGUE[dialogue_id]
	var options: Array = node.options
	if key in [KEY_UP, KEY_W]: dialogue_selected = wrapi(dialogue_selected - 1, 0, options.size())
	elif key in [KEY_DOWN, KEY_S]: dialogue_selected = wrapi(dialogue_selected + 1, 0, options.size())
	elif key in [KEY_1, KEY_2, KEY_3] and key - KEY_1 < options.size():
		dialogue_selected = key - KEY_1; advance_dialogue()
	elif key in [KEY_ENTER, KEY_SPACE]: advance_dialogue()

func advance_dialogue() -> void:
	var option: Dictionary = Data.DIALOGUE[dialogue_id].options[dialogue_selected]
	if option.has("flag"): dialogue_flags[option.flag] = true
	if option.next == "END":
		bar_stage = "mix_ready"; phase = Phase.BAR; show_toast("委托已接取：吧台现在可以调酒")
	else:
		dialogue_id = option.next; dialogue_selected = 0

func handle_mix_input(key: Key) -> void:
	if key == KEY_B:
		if not mix_pour_id.is_empty():
			mix_message = "请等倒酒动画结束。"
			return
		mix_cellar_open = not mix_cellar_open
		return
	if key in [KEY_LEFT, KEY_A, KEY_RIGHT, KEY_D]:
		var selected_index := 0
		for i in range(mixer_drinks.size()):
			if mixer_drinks[i].id == mix_selected_id: selected_index = i
		selected_index = wrapi(selected_index + (-1 if key in [KEY_LEFT, KEY_A] else 1), 0, mixer_drinks.size())
		mix_selected_id = mixer_drinks[selected_index].id
		return
	if key >= KEY_1 and key <= KEY_6:
		mix_selected_id = mixer_drinks[key - KEY_1].id
		return
	if mix_cellar_open:
		if key in [KEY_ENTER, KEY_SPACE]: buy_selected_drink()
		return
	if key == KEY_BACKSPACE: undo_mix_pour()
	elif key == KEY_F: finish_mix()
	elif key in [KEY_ENTER, KEY_SPACE]: start_mix_pour(mix_selected_id)

func finish_mix() -> void:
	if not mix_pour_id.is_empty():
		mix_message = "请等倒酒动画结束。"
		return
	if mix_added_ids.is_empty():
		mix_message = "至少倒入一种酒才能开始潜航。"
		return
	cocktail_ids = mix_added_ids.duplicate()
	reset_player_stats()
	if "still_sea" in cocktail_ids: player.max_hp *= 1.2; player.hp = player.max_hp
	if "reverse_fire" in cocktail_ids: player.damage *= 1.15
	anger_reward = "anger" in cocktail_ids
	paradox_factor = 0.7 if "stable" in cocktail_ids else 1.0
	if "overload" in cocktail_ids: state.paradox += 20.0; state.add_clue("overload_echo")
	bar_stage = "diving"; transition_time = 0.0; phase = Phase.TRANSITION
	show_toast("配方锁定：" + cocktail_summary() + "。杯中记忆正在展开。")

func update_transition(delta: float) -> void:
	transition_time += delta
	if transition_time >= 1.8:
		start_dive()

func cocktail_summary() -> String:
	var names: Array[String] = []
	for id in cocktail_ids:
		var drink: Dictionary = Data.drink_by_id(id)
		if not drink.is_empty(): names.append(drink.name)
	return " / ".join(names)

func reset_player_stats() -> void:
	player = {"pos":Vector2(38,112), "hp":100.0, "max_hp":100.0, "damage":18.0, "speed":70.0, "invuln":0.0, "role":"代理人"}

func start_dive() -> void:
	room_index = 0; borrowed = false; upgrades.clear(); state.reached_room = 1; enter_room(0)

func enter_room(index: int) -> void:
	room_index = index; phase = Phase.ROOM
	room_clear = false; door_visible = false; anchor_ready = false
	witness_downed = false; witness_pos = Vector2.ZERO
	projectiles.clear(); hazards.clear(); particles.clear(); enemies.clear()
	player.pos = Vector2(38,112); player.hp = player.max_hp; player.invuln = 0.8
	attack_cd = 0.0; q_cd = 0.0; dash_time = 0.0
	dash_max = 2 if "second_dash" in upgrades else 1
	dash_charges = dash_max; dash_recover = 0.0; shield = 0
	for spec in Data.ROOMS[index].enemies: enemies.append(make_enemy(spec))
	if anger_reward and index < 2: enemies.append(make_enemy({"type":"melee", "pos":Vector2(280,145)}))
	state.reached_room = maxi(state.reached_room, index + 1)
	show_toast(Data.ROOMS[index].objective)

func make_enemy(spec: Dictionary) -> Dictionary:
	var cfg: Dictionary = Data.CHARACTERS[spec.type]
	return {"type":spec.type, "pos":spec.pos, "hp":cfg.hp, "max_hp":cfg.hp, "speed":cfg.speed, "damage":cfg.damage, "cool":rng.randf_range(0.2,0.8), "windup":0.0, "armed":false, "hurt":0.0, "pattern":0, "charge":0.0, "charge_dir":Vector2.ZERO}

func update_room(delta: float) -> void:
	attack_cd = maxf(0.0, attack_cd - delta); q_cd = maxf(0.0, q_cd - delta); player.invuln = maxf(0.0, player.invuln - delta)
	if dash_charges < dash_max:
		dash_recover += delta
		if dash_recover >= 1.25: dash_charges += 1; dash_recover = 0.0
	var move := movement_input()
	if dash_time > 0.0: dash_time -= delta; player.pos += dash_dir * 180.0 * delta
	else: player.pos += move * player.speed * delta
	player.pos.x = round(clampf(player.pos.x, 12.0, 307.0)); player.pos.y = round(clampf(player.pos.y, 38.0, 164.0))
	update_enemies(delta); update_projectiles(delta); update_hazards(delta); check_room_clear()
	if player.hp <= 0.0: phase = Phase.DEAD

func update_enemies(delta: float) -> void:
	for e in enemies:
		e.cool -= delta; e.hurt = maxf(0.0, e.hurt - delta)
		var to_player: Vector2 = player.pos - e.pos; var distance := to_player.length()
		if e.charge > 0.0:
			e.charge -= delta; e.pos += e.charge_dir * 135.0 * delta
			if distance < 12.0: hurt_player(e.damage, e.pos)
			continue
		if e.armed:
			e.windup -= delta
			if e.windup <= 0.0: e.armed = false; resolve_enemy_attack(e)
			continue
		match e.type:
			"melee", "noise":
				if distance > 14.0: e.pos += to_player.normalized() * e.speed * delta
				elif e.cool <= 0.0: e.armed = true; e.windup = 0.32; e.cool = 1.0
			"shooter", "witness":
				if distance < 55.0: e.pos -= to_player.normalized() * e.speed * delta
				elif distance > 110.0: e.pos += to_player.normalized() * e.speed * 0.5 * delta
				if e.cool <= 0.0: e.armed = true; e.windup = 0.5; e.cool = 1.6
			"boss": update_boss(e, delta, to_player, distance)
		e.pos.x = clampf(e.pos.x,14.0,306.0); e.pos.y = clampf(e.pos.y,40.0,163.0)

func resolve_enemy_attack(e: Dictionary) -> void:
	var direction: Vector2 = (player.pos - e.pos).normalized()
	if e.type in ["melee", "noise"]:
		if player.pos.distance_to(e.pos) < 20.0: hurt_player(e.damage, e.pos)
	else: spawn_projectile(e.pos,direction*76.0,e.damage,true,Color(Data.CHARACTERS[e.type].color))

func update_boss(e: Dictionary, delta: float, to_player: Vector2, distance: float) -> void:
	if distance > 62.0: e.pos += to_player.normalized() * e.speed * 0.35 * delta
	if e.cool > 0.0: return
	e.pattern = (e.pattern + 1) % 3
	if e.pattern == 0:
		for i in range(10): spawn_projectile(e.pos,Vector2.from_angle(TAU*i/10.0)*58.0,e.damage,true,RED)
		e.cool = 1.9
	elif e.pattern == 1:
		e.charge_dir = to_player.normalized(); e.charge = 0.55; e.cool = 1.7
	else:
		if enemies.filter(func(x): return x.type=="noise").size()<2: enemies.append(make_enemy({"type":"noise","pos":e.pos+Vector2(-24,18)}))
		e.cool=2.1

func update_projectiles(delta: float) -> void:
	for shot in projectiles.duplicate():
		shot.delay -= delta
		if shot.delay > 0.0: continue
		shot.pos += shot.vel*delta; shot.life -= delta
		if shot.enemy:
			if shot.pos.distance_to(player.pos)<7.0: hurt_player(shot.damage,shot.pos); projectiles.erase(shot); continue
		else:
			for e in enemies.duplicate():
				if shot.pos.distance_to(e.pos)<(11.0 if e.type=="boss" else 7.0): damage_enemy(e,shot.damage,shot.vel.normalized()); projectiles.erase(shot); break
		if shot in projectiles and (shot.life<=0.0 or not Rect2(0,28,320,152).has_point(shot.pos)): projectiles.erase(shot)

func update_hazards(delta: float) -> void:
	for h in hazards.duplicate():
		h.life -= delta
		if h.kind=="heal" and player.pos.distance_to(h.pos)<h.radius: player.hp=minf(player.max_hp,player.hp+11.0*delta)
		elif h.kind=="noise" and player.pos.distance_to(h.pos)<h.radius and h.tick<=0.0: hurt_player(5.0,h.pos); h.tick=0.7
		h.tick-=delta
		if h.life<=0.0: hazards.erase(h)

func normal_attack(direction: Vector2) -> void:
	if attack_cd>0.0 or direction==Vector2.ZERO: return
	direction=direction.normalized(); attack_count+=1
	if borrowed:
		for spread in [-0.12,0.0,0.12]: spawn_projectile(player.pos,direction.rotated(spread)*145.0,player.damage*0.72,false,CYAN)
		attack_cd=0.38
	else: spawn_projectile(player.pos,direction*132.0,player.damage,false,AMBER); attack_cd=0.3
	if "copy" in upgrades and attack_count%4==0: projectiles.append({"pos":player.pos,"vel":direction*132.0,"damage":player.damage*0.7,"enemy":false,"life":1.5,"delay":0.18,"color":MAGENTA})
	burst(player.pos+direction*8.0,CYAN if borrowed else AMBER,5)

func spawn_projectile(pos: Vector2, velocity: Vector2, damage: float, enemy: bool, color: Color) -> void:
	projectiles.append({"pos":pos,"vel":velocity,"damage":damage,"enemy":enemy,"life":2.6,"delay":0.0,"color":color})

func keyboard_aim() -> Vector2:
	var target=nearest_enemy()
	return last_move if target==null else (target.pos-player.pos).normalized()

func nearest_enemy():
	var result=null; var best:=INF
	for e in enemies:
		var distance: float=player.pos.distance_squared_to(e.pos)
		if distance<best: best=distance; result=e
	return result

func dash() -> void:
	if dash_charges<=0 or dash_time>0.0:return
	var move:=movement_input()
	if move==Vector2.ZERO:move=last_move
	dash_dir=move.normalized();dash_time=0.16;dash_charges-=1;player.invuln=0.28
	if "shield" in upgrades:shield=1
	burst(player.pos,CYAN,9)

func use_skill() -> void:
	if q_cd>0.0:return
	var factor:=0.75 if "overclock" in upgrades else 1.0
	if borrowed:
		hazards.append({"kind":"heal","pos":player.pos,"radius":30.0,"life":5.0,"tick":0.0});q_cd=7.0*factor;show_toast("医疗员 Q：恢复区部署")
	else:
		for e in enemies.duplicate():
			if e.pos.distance_to(player.pos)<52.0:damage_enemy(e,player.damage*1.55,(e.pos-player.pos).normalized())
		q_cd=5.0*factor;state.paradox+=2.0*paradox_factor;burst(player.pos,MAGENTA,18)

func damage_enemy(e: Dictionary, amount: float, direction: Vector2, allow_chain:=true) -> void:
	if not e in enemies:return
	e.hp-=amount;e.hurt=0.12;e.pos+=direction*2.0;hit_count+=1;shake=2.0;burst(e.pos,Color(Data.CHARACTERS[e.type].color),4)
	if allow_chain and "pulse" in upgrades and hit_count%3==0:
		var other=nearest_other_enemy(e)
		if other!=null:damage_enemy(other,10.0,Vector2.ZERO,false)
	if e.hp>0.0:return
	var death_pos:Vector2=e.pos;var type:String=e.type;enemies.erase(e)
	if type=="witness":witness_downed=true;witness_pos=death_pos;show_toast("见证者数据崩解：靠近医疗员按 E 借身")
	elif type=="boss":anchor_ready=true;state.add_clue("liwu_message");show_toast("黎雾：‘如果你看到这里，说明他们终于把你造出来了。’")
	else:
		if type=="noise":hazards.append({"kind":"noise","pos":death_pos,"radius":18.0,"life":2.4,"tick":0.0})
		if "drain" in upgrades:player.hp=minf(player.max_hp,player.hp+8.0)

func nearest_other_enemy(excluded:Dictionary):
	var best=null;var distance:=INF
	for e in enemies:
		if e==excluded:continue
		var d:float=e.pos.distance_squared_to(excluded.pos)
		if d<distance:distance=d;best=e
	return best

func hurt_player(amount:float,source:Vector2)->void:
	if player.invuln>0.0:return
	if shield>0:shield=0;player.invuln=0.35;show_toast("反馈屏障吸收伤害");return
	player.hp-=amount;player.invuln=0.55;flash=0.55;shake=5.0
	var away:Vector2=(player.pos-source).normalized()
	if away==Vector2.ZERO:away=Vector2.LEFT
	player.pos+=away*5.0

func check_room_clear()->void:
	if room_clear:return
	if room_index==1:
		if enemies.is_empty() and witness_downed and borrowed:complete_room()
	elif room_index==2:
		if enemies.is_empty() and anchor_ready:complete_room()
	elif enemies.is_empty():complete_room()

func complete_room()->void:
	room_clear=true;state.add_clue(Data.ROOMS[room_index].id)
	if room_index==0 and "empathy" in cocktail_ids:state.add_clue("zhou_fear")
	state.paradox+=[4.0,7.0,10.0][room_index]*paradox_factor
	if room_index<2:door_visible=true;show_toast("房间已固定：右侧记忆门开启")

func interact_room()->void:
	if witness_downed and not borrowed and player.pos.distance_to(witness_pos)<20.0:borrow_witness();return
	if room_index==2 and anchor_ready and player.pos.distance_to(Vector2(284,88))<24.0:phase=Phase.CAUSAL;return
	if door_visible and player.pos.distance_to(Vector2(302,96))<25.0:open_upgrade()

func borrow_witness()->void:
	borrowed=true;player.role="企业医疗员";player.damage+=3.0;player.hp=minf(player.max_hp,player.hp+35.0)
	state.add_clue("medical_alive");state.paradox+=5.0*paradox_factor;burst(witness_pos,CYAN,24)
	show_toast("借身完成：三连发 / Q 恢复区 / 隐藏门与医疗记录可见");check_room_clear()

func open_upgrade()->void:
	upgrade_options=Data.UPGRADES.slice(0,3) if room_index==0 else Data.UPGRADES.slice(3,6);phase=Phase.UPGRADE

func choose_upgrade(index:int)->void:
	if index<0 or index>=upgrade_options.size():return
	var id:String=upgrade_options[index].id
	if not id in upgrades:upgrades.append(id)
	if id=="second_dash":dash_max=2
	if id=="overclock":state.paradox+=10.0
	enter_room(room_index+1)

func choose_causal(index:int)->void:
	var ids:=["shot_prevented","shot_preserved","death_faked"];var id:String=ids[index]
	state.choose_ending(id);state.paradox+=float(Data.ENDINGS[id].paradox);phase=Phase.RETURN_BAR;bar_player=BAR_RETURN_SPAWN;bar_stage="returned";bar_mouse_active=false
	zhou_pos = BAR_ZHOU_POS; zhou_route_index = BAR_ZHOU_ENTRY_ROUTE.size(); zhou_arrived = true; zhou_is_walking = false; zhou_action_active = false
	show_toast("现实已重写："+Data.ENDINGS[id].bar)

func prepare_settlement()->void:
	var ending:Dictionary=Data.ENDINGS[state.ending_id()];var score:=state.calculate_score(ending.alignment);var multiplier:=1.15 if anger_reward else 1.0;var paid:=state.claim_reward(score,multiplier)
	if paid > 0: save_cellar()
	settlement_lines=["潜航深度  25 / 25","证据完整  "+str(mini(25,state.clues.size()*7))+" / 25","委托吻合  "+str(ending.alignment)+" / 25","因果稳定  "+str(clampi(25-int(state.paradox*0.25),0,25))+" / 25","总评分  "+str(score)+" / 100",("一次性报酬  +"+str(paid)+" 信用点") if paid>0 else "报酬已领取（不会重复发放）"]
	phase=Phase.SETTLEMENT

func choose_facility(index:int)->void:
	var id:="bar_counter" if index==0 else "stabilizer"
	if state.buy_facility(id):
		save_cellar()
		phase=Phase.RETURN_BAR;bar_stage="ending_ready";bar_player=BAR_RETURN_SPAWN;bar_mouse_active=false
		show_toast("设施升级完成：场景灯效已更新。前往吧台通讯器接听来电。")
	else:show_toast("信用点不足或设施已升级")

func restart_demo()->void:
	var former_state := state
	state = State.new()
	state.credits = former_state.credits
	for id in former_state.unlocked_drinks:
		if not state.is_drink_unlocked(id): state.unlocked_drinks.append(id)
	phase=Phase.TITLE;title_menu_index=0;title_notice_time=0.0;bar_stage="intro";bar_player=BAR_SPAWN;bar_mouse_active=false;dialogue_flags.clear();cocktail_ids.clear();upgrades.clear();borrowed=false;reset_player_stats()
	mix_added_ids.clear();mix_pour_id="";mix_pour_time=0.0;mix_cellar_open=false;mix_selected_id="still_sea"
	bar_action_active = false; bar_pending_action = ""; bar_is_walking = false; bar_walk_time = 0.0
	start_zhou_entrance()

func show_toast(value:String)->void:toast_text=value;toast_time=3.2

func burst(pos:Vector2,color:Color,count:int)->void:
	for i in range(count):particles.append({"pos":pos,"vel":Vector2.from_angle(rng.randf_range(0,TAU))*rng.randf_range(10,42),"life":rng.randf_range(0.2,0.55),"color":color})

func _draw()->void:
	draw_rect(Rect2(Vector2.ZERO,SCREEN),INK)
	match phase:
		Phase.TITLE:draw_title()
		Phase.BAR,Phase.DIALOGUE,Phase.RETURN_BAR:draw_bar()
		Phase.MIX:draw_mix()
		Phase.TRANSITION:draw_memory_transition()
		Phase.ROOM:draw_room()
		Phase.UPGRADE:draw_upgrade()
		Phase.CAUSAL:draw_causal()
		Phase.SETTLEMENT:draw_settlement()
		Phase.FACILITY:draw_facility()
		Phase.CREDITS:draw_credits()
		Phase.DEAD:draw_dead()
	if toast_time>0.0 and phase not in [Phase.DIALOGUE,Phase.TITLE]:draw_toast()
	if paused:draw_pause()
	if flash>0.0:draw_rect(Rect2(0,0,320,180),Color(1,0.1,0.12,flash*0.22))

func draw_title()->void:
	draw_texture_rect(title_texture,Rect2(0,0,320,180),false)
	draw_title_parallax()
	# Exact lettering is rendered on the remote-generated blank sign at native pixel size.
	txt("昨夜不存在",Vector2(108,87),20,Color("7b175b"))
	txt("昨夜不存在",Vector2(107,86),20,Color("ee5fc4"))
	txt("昨夜不存在",Vector2(106,85),20,Color("fff0fa"))
	txt("Last night never existed",Vector2(108,96),8,Color("67e7f1"))
	var labels := ["开始委托", "继续委托", "载入昨日", "游戏设置"]
	for i in range(4):
		var rect := title_button_rect(i)
		var selected := i == title_menu_index
		var enabled := i == 0
		var border := CYAN if enabled else Color("4c5365")
		if selected: border = AMBER if enabled else MAGENTA.darkened(0.25)
		draw_rect(rect,Color(0.025,0.04,0.08,0.94))
		draw_rect(rect,border,false,1)
		if selected: draw_rect(Rect2(rect.position+Vector2(2,2),rect.size-Vector2(4,4)),border*Color(1,1,1,0.13))
		txt((">" if selected else " ")+labels[i],rect.position+Vector2(5,10),8,Color.WHITE if enabled else Color("929eb3"))
		if not enabled: txt("未开放",rect.position+Vector2(55,9),5,Color("687388"))
	if title_notice_time > 0.0:
		draw_rect(Rect2(63,164,194,11),Color("090c16"));txt(fit_text(title_notice,30),Vector2(70,172),5,MAGENTA)
	else: txt("↑↓ / 鼠标选择    Enter / 点击确认",Vector2(104,174),5,Color("758297"))

func draw_title_parallax()->void:
	# Two opposing, integer-stepped building lanes preserve pixel sharpness while the skyline moves.
	var left_shift := int(floor(elapsed*2.0))%96
	var right_shift := int(floor(elapsed*1.0))%112
	for i in range(5):
		var x := -54+i*48+left_shift
		if x<70 or x>250:
			draw_rect(Rect2(x,8+(i%2)*7,30,39),Color(0.035,0.065,0.13,0.58))
			draw_rect(Rect2(x+5,15+(i%2)*7,2,2),Color(0.22,0.38,0.5,0.55))
	for i in range(5):
		var x := 334-i*56-right_shift
		if x<65 or x>255:
			draw_rect(Rect2(x,17+(i%3)*5,38,46),Color(0.07,0.045,0.12,0.48))
			draw_rect(Rect2(x+27,25+(i%3)*5,2,6),Color(0.55,0.12,0.42,0.38))

func draw_city_layers()->void:
	var drift:=int(floor(elapsed*2.0))
	for i in range(11):
		var x:float=(i*34-drift/3)%360-20;var h:float=28+(i*13)%35;draw_rect(Rect2(x,45-h,26,h),Color("111a31"))
		for wy in range(8,int(h)-4,7):draw_rect(Rect2(x+5,45-h+wy,2,1),Color("38506c"))
	for i in range(9):
		var x:float=(i*43-drift)%390-25;draw_rect(Rect2(x,30+(i%3)*8,34,48),Color("151326"));draw_rect(Rect2(x+3,35+(i%3)*8,2,18),MAGENTA.darkened(0.35))
	for y in range(0,180,13):draw_line(Vector2((y*7+drift)%320,y),Vector2((y*7+drift)%320+2,y+5),Color(0.35,0.6,0.75,0.3),1)

func draw_bar()->void:
	draw_set_transform(Vector2.ZERO,0.0,Vector2(BAR_VIEW_SCALE,BAR_VIEW_SCALE))
	draw_bar_background();var actors:Array=[{"type":"player","pos":bar_player},{"type":"zhou","pos":zhou_pos},{"type":"counter_front","pos":Vector2(0,BAR_COUNTER_SORT_Y)}]
	if phase==Phase.RETURN_BAR and state.ending_id()=="shot_prevented":actors.append({"type":"corp","pos":Vector2(190,188)})
	actors.sort_custom(func(a,b):return a.pos.y<b.pos.y)
	for actor in actors:
		if actor.type=="player":draw_bar_sprite(bartender_display_texture(),actor.pos)
		elif actor.type=="corp":draw_pixel_person(bar_world_to_view(actor.pos),RED,"corp")
		elif actor.type=="counter_front":draw_bar_foreground()
		else:draw_bar_sprite(zhou_display_texture(),actor.pos)
	if phase==Phase.RETURN_BAR:draw_return_difference()
	if phase==Phase.BAR and mix_hotspot_hovered:
		var hotspot:=Rect2(bar_world_to_view(BAR_MIX_HOTSPOT.position),BAR_MIX_HOTSPOT.size);draw_rect(hotspot,Color(0.15,0.9,0.95,0.10));draw_rect(hotspot,CYAN,false,1)
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
	if not interaction_hint.is_empty():draw_rect(Rect2(103,154,114,15),Color("0d1724"));draw_rect(Rect2(103,154,114,15),CYAN,false,1);txt(interaction_hint,Vector2(112,164),6,Color.WHITE)
	else:txt("WASD/方向键 移动   E 交互",Vector2(109,173),6,Color("8492aa"))
	if phase==Phase.DIALOGUE:draw_dialogue()

func draw_bar_background()->void:
	var camera:=bar_camera_origin()
	draw_texture_rect_region(bar_texture,Rect2(Vector2.ZERO,BAR_VIEW_SIZE),Rect2(camera,BAR_VIEW_SIZE))
	# Separate integer-pixel rain drift uses a slightly slower camera factor for real parallax.
	var rain_shift:=int(floor(elapsed*2.0))%9
	var parallax_camera:=Vector2(round(camera.x*0.92),round(camera.y*0.92))
	for i in range(18):
		var start:=Vector2(8+i*13+rain_shift,18+(i%4)*11)-parallax_camera
		draw_line(start,start+Vector2(-3,18),Color(0.35,0.85,1.0,0.22),1)
	var light_shift:=int(floor(elapsed))%5
	var light_pos:=bar_world_to_view(Vector2(38+light_shift,171))
	draw_rect(Rect2(light_pos,Vector2(92,2)),Color(0.15,0.8,0.92,0.08))
	draw_dancefloor_lights()
	# Ordinary bar communicator replaces the removed dive terminal.
	var comm:=bar_world_to_view(BAR_COMMS_ART_POS)
	draw_rect(Rect2(comm-Vector2(9,7),Vector2(18,10)),Color("101827"));draw_rect(Rect2(comm-Vector2(6,5),Vector2(12,5)),CYAN.darkened(0.55));draw_rect(Rect2(comm-Vector2(4,3),Vector2(6,1)),CYAN)

func draw_dancefloor_lights()->void:
	# Slow integer-stepped accents keep the generated floor readable and leave its walk area unobstructed.
	var phase_step:=int(floor(elapsed*1.25))%4
	var colors:=[CYAN,MAGENTA,AMBER,Color("f5ddec")]
	for row in range(4):
		for column in range(4):
			if (row+column+phase_step)%4!=0:continue
			var world_pos:=Vector2(548+column*45,166+row*45)
			var screen_pos:=bar_world_to_view(world_pos)
			draw_rect(Rect2(screen_pos,Vector2(18,2)),colors[(row+column)%colors.size()]*Color(1,1,1,0.12))

func draw_bar_foreground()->void:
	# Reuse actual selected-image pixels as the camera-aware sortable occluder.
	var camera:=bar_camera_origin()
	draw_texture_rect_region(bar_foreground_texture,Rect2(Vector2.ZERO,BAR_VIEW_SIZE),Rect2(camera,BAR_VIEW_SIZE))

func draw_bar_sprite(texture:Texture2D,world_position:Vector2)->void:
	var screen_position:=bar_world_to_view(world_position)
	draw_rect(Rect2(screen_position-Vector2(12,4),Vector2(24,7)),Color(0,0,0,0.52))
	draw_texture(texture,pixel(screen_position-BAR_SPRITE_PIVOT))

func bartender_display_texture() -> Texture2D:
	if bar_action_active and not bartender_interact_frames.is_empty():
		var index := mini(int(bar_action_time / BAR_INTERACT_DURATION * bartender_interact_frames.size()), bartender_interact_frames.size() - 1)
		return bartender_interact_frames[index]
	if bar_is_walking and not bartender_walk_frames.is_empty():
		return bartender_walk_frames[int(bar_walk_time / 0.125) % bartender_walk_frames.size()]
	return bartender_texture

func zhou_display_texture() -> Texture2D:
	if zhou_action_active and not zhou_interact_frames.is_empty():
		var index := mini(int(zhou_action_time / BAR_INTERACT_DURATION * zhou_interact_frames.size()), zhou_interact_frames.size() - 1)
		return zhou_interact_frames[index]
	if zhou_is_walking and not zhou_walk_frames.is_empty():
		return zhou_walk_frames[int(zhou_walk_time / 0.125) % zhou_walk_frames.size()]
	return zhou_texture

func draw_return_difference()->void:
	var ending:=state.ending_id()
	var comm:=bar_world_to_view(BAR_COMMS_ART_POS)
	var seat:=bar_world_to_view(Vector2(145,240))
	if ending=="shot_prevented":draw_rect(Rect2(comm-Vector2(8,13),Vector2(17,4)),AMBER);txt("企业回函",comm+Vector2(-15,-17),6,AMBER)
	elif ending=="shot_preserved":draw_rect(Rect2(seat-Vector2(18,9),Vector2(36,4)),AMBER.darkened(0.35));txt("空座仍温热",seat+Vector2(-20,2),6,AMBER)
	else:draw_rect(Rect2(seat-Vector2(14,22),Vector2(27,22)),Color("dad2bd"));draw_rect(Rect2(seat-Vector2(11,19),Vector2(9,13)),CYAN);draw_rect(Rect2(seat+Vector2(1,-19),Vector2(9,13)),MAGENTA);txt("你 + 黎雾",seat+Vector2(-16,7),6,AMBER);txt("来电…",comm+Vector2(-10,-14),6,MAGENTA)
	if state.clues.has("rain_window_trace"):
		var trace:=bar_world_to_view(Vector2(240,58));draw_line(trace-Vector2(4,18),trace+Vector2(5,13),CYAN,2);draw_rect(Rect2(trace+Vector2(7,-4),Vector2(3,3)),MAGENTA)
	if not state.facility.is_empty():
		if state.facility=="bar_counter":draw_line(bar_world_to_view(Vector2(276,245)),bar_world_to_view(Vector2(480,245)),AMBER,2)
		else:
			# Stabilizer feedback is a bar light ring, never a terminal/machine.
			draw_arc(comm,9,0,TAU,16,CYAN,1);draw_arc(comm,6,0,TAU,16,MAGENTA,1)

func draw_dialogue()->void:
	var node:Dictionary=Data.DIALOGUE[dialogue_id];draw_rect(Rect2(7,108,306,65),Color("090d18"));draw_rect(Rect2(7,108,306,65),CYAN,false,1);txt(node.speaker,Vector2(15,121),8,AMBER);draw_wrapped(node.text,Vector2(15,133),48,6,Color("d6d9df"))
	var options:Array=node.options
	for i in range(options.size()):
		var y:=155+i*9;txt(("> " if i==dialogue_selected else "  ")+str(i+1)+" "+options[i].text,Vector2(15,y),6,CYAN if i==dialogue_selected else Color("9ba5b7"))

func draw_mix()->void:
	draw_rect(Rect2(0,0,320,180),Color("0b101b"))
	for x in range(0,320,16):
		draw_line(Vector2(x,28),Vector2(x,180),Color("172238"),1)
	for y in range(34,180,16):
		draw_line(Vector2(0,y),Vector2(320,y),Color("111d30"),1)
	if mix_cellar_open:
		draw_cellar()
		return
	draw_rect(Rect2(0,0,320,28),Color("151d30"))
	draw_rect(Rect2(0,27,320,1),CYAN.darkened(0.35))
	draw_rect(mix_back_rect(),Color("24364a"))
	txt("←",Vector2(12,18),10,CYAN)
	txt("神经鸡尾酒",Vector2(36,19),10,AMBER)
	txt("信用点 %d" % state.credits,Vector2(182,18),6,Color("bed4e4"))
	draw_rect(mix_cellar_button_rect(),Color("193b4b"))
	draw_rect(mix_cellar_button_rect(),CYAN,false,1)
	txt("酒库",Vector2(270,18),8,Color.WHITE)

	# Shelf and counter use rigid pixel edges to match the game's nearest-filtered art.
	draw_rect(Rect2(6,32,204,82),Color("18172b"))
	draw_rect(Rect2(6,32,204,82),Color("51627b"),false,1)
	draw_rect(Rect2(10,36,196,3),Color("283451"))
	draw_rect(Rect2(9,94,198,4),Color("62405a"))
	draw_rect(Rect2(9,98,198,2),MAGENTA.darkened(0.42))
	for i in range(mixer_drinks.size()):
		var drink: Dictionary = mixer_drinks[i]
		var rect := mix_bottle_rect(i)
		var selected: bool = mix_selected_id == drink.id
		var bottle_color := Color(drink.color)
		if selected:
			draw_rect(Rect2(rect.position+Vector2(0,1),Vector2(30,70)),bottle_color.darkened(0.83))
			draw_rect(Rect2(rect.position+Vector2(0,1),Vector2(30,70)),bottle_color,false,1)
		var bottle := mixer_bottle_textures.get(drink.id) as Texture2D
		if bottle != null: draw_texture(bottle,rect.position+Vector2(2,5))
		if not state.is_drink_unlocked(drink.id):
			draw_rect(Rect2(rect.position+Vector2(2,5),Vector2(26,48)),Color(0.01,0.02,0.05,0.43))
			draw_rect(Rect2(rect.position+Vector2(18,8),Vector2(9,9)),Color("25253d"))
			txt("锁",rect.position+Vector2(19,15),5,AMBER)
		if drink.id in mix_added_ids:
			draw_rect(Rect2(rect.position+Vector2(2,2),Vector2(7,7)),Color("1b584e"))
			txt("✓",rect.position+Vector2(2,8),6,Color("a5ffe3"))
		txt(drink.name,rect.position+Vector2(7,66),7,Color.WHITE if state.is_drink_unlocked(drink.id) else Color("9a92a7"))

	draw_rect(Rect2(216,32,97,82),Color("151b2b"))
	draw_rect(Rect2(216,32,97,82),Color("51627b"),false,1)
	txt("调 和 台",Vector2(236,43),7,CYAN)
	draw_rect(Rect2(219,105,91,4),Color("6c4865"))
	draw_rect(Rect2(219,109,91,2),MAGENTA.darkened(0.35))
	if mixer_shaker_texture != null: draw_texture(mixer_shaker_texture,Vector2(219,60))
	if not mix_added_ids.is_empty():
		var top_drink: Dictionary = Data.drink_by_id(mix_added_ids.back())
		var fill_height := 7 * mix_added_ids.size()
		draw_rect(Rect2(280,105-fill_height,16,fill_height),Color(top_drink.color)*Color(1,1,1,0.84))
		for j in range(mix_added_ids.size()):
			draw_rect(Rect2(282+j*4,102-j*6,2,2),Color("e9ffff"))
	if mixer_glass_texture != null: draw_texture(mixer_glass_texture,Vector2(270,69))
	if not mix_pour_id.is_empty(): draw_mix_pour_animation()

	draw_rect(Rect2(6,117,204,48),Color("182236"))
	draw_rect(Rect2(6,117,204,48),Color("405a73"),false,1)
	var selected_drink: Dictionary = Data.drink_by_id(mix_selected_id)
	if not selected_drink.is_empty():
		txt("%s  %s · %s" % [selected_drink.name,selected_drink.category,selected_drink.quality],Vector2(13,131),8,Color(selected_drink.color))
		txt("属性  %s" % selected_drink.desc,Vector2(13,146),7,Color("edf3f7"))
		var selection_status := "已解锁 · 双击倒入" if state.is_drink_unlocked(mix_selected_id) else "未解锁 · 酒库中需 %d 信用点" % int(selected_drink.cost)
		txt(selection_status,Vector2(13,158),6,Color("afc7d4") if state.is_drink_unlocked(mix_selected_id) else AMBER)

	draw_rect(Rect2(216,117,97,48),Color("182236"))
	draw_rect(Rect2(216,117,97,48),Color("405a73"),false,1)
	txt("杯中 %d / 3" % mix_added_ids.size(),Vector2(221,128),7,Color.WHITE)
	draw_rect(mix_undo_button_rect(),Color("2b3246"))
	draw_rect(mix_undo_button_rect(),Color("70889a"),false,1)
	txt("撤回",Vector2(278,126),6,Color("c9d7e0"))
	var names: Array[String] = []
	for id in mix_added_ids: names.append(Data.drink_by_id(id).name)
	txt(fit_text(" / ".join(names) if not names.is_empty() else "尚未倒入",17),Vector2(221,138),5,Color("a8c2d2"))
	var can_finish := not mix_added_ids.is_empty() and mix_pour_id.is_empty()
	draw_rect(mix_finish_button_rect(),Color("1a6870") if can_finish else Color("283442"))
	draw_rect(mix_finish_button_rect(),CYAN if can_finish else Color("536271"),false,1)
	txt("完成调制",Vector2(239,157),9,Color.WHITE if can_finish else Color("8798a5"))
	draw_rect(Rect2(0,168,320,12),Color("121c2d"))
	txt(fit_text(mix_message,49),Vector2(9,177),6,Color("b6d9e3"))

func draw_mix_pour_animation() -> void:
	var drink: Dictionary = Data.drink_by_id(mix_pour_id)
	if drink.is_empty(): return
	var source_index := 0
	for i in range(mixer_drinks.size()):
		if mixer_drinks[i].id == mix_pour_id: source_index = i
	var amount := clampf(mix_pour_time / MIX_POUR_DURATION,0.0,1.0)
	var lift := clampf(amount * 2.4,0.0,1.0)
	var source := mix_bottle_rect(source_index).position + Vector2(2,5)
	var position := source.lerp(Vector2(247,47),lift)
	var angle := 0.62 * clampf((amount-0.17)*3.0,0.0,1.0)
	var bottle := mixer_bottle_textures.get(mix_pour_id) as Texture2D
	if bottle != null:
		draw_set_transform(position+Vector2(13,24),angle,Vector2.ONE)
		draw_texture(bottle,Vector2(-13,-24))
		draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
	if amount > 0.42 and amount < 0.87:
		var pour_color := Color(drink.color)
		var start := Vector2(273,55)
		var end := Vector2(287,83)
		draw_line(start,end,pour_color,2)
		for j in range(3):
			draw_rect(Rect2(275+j*4,59+j*7,2,3),pour_color.lightened(0.28))

func draw_cellar() -> void:
	draw_rect(Rect2(0,0,320,27),Color("151d30"))
	draw_rect(Rect2(0,26,320,1),AMBER.darkened(0.23))
	draw_rect(mix_back_rect(),Color("3a3448"))
	txt("←",Vector2(12,18),10,AMBER)
	txt("神经酒库",Vector2(37,19),10,AMBER)
	txt("信用点 %d" % state.credits,Vector2(184,18),7,Color.WHITE)
	draw_rect(mix_cellar_button_rect(),Color("254554"))
	draw_rect(mix_cellar_button_rect(),CYAN,false,1)
	txt("返回",Vector2(269,18),7,Color.WHITE)
	for i in range(mixer_drinks.size()):
		var drink: Dictionary = mixer_drinks[i]
		var card := mix_cellar_card_rect(i)
		var unlocked := state.is_drink_unlocked(drink.id)
		var selected: bool = mix_selected_id == drink.id
		var accent := Color(drink.color)
		draw_rect(card,Color("192338") if unlocked else Color("241d30"))
		draw_rect(card,accent if selected else Color("45536b"),false,1)
		var bottle := mixer_bottle_textures.get(drink.id) as Texture2D
		if bottle != null: draw_texture_rect(bottle,Rect2(card.position+Vector2(3,2),Vector2(21,36)),false)
		txt("%s · %s" % [drink.name,drink.quality],card.position+Vector2(28,13),8,accent)
		txt("%s | %s" % [drink.category,drink.desc],card.position+Vector2(28,25),6,Color("c8d7e2"))
		txt("已解锁" if unlocked else "%d 信用点解锁" % int(drink.cost),card.position+Vector2(28,35),6,Color("9de4d3") if unlocked else AMBER)
	var selected_drink: Dictionary = Data.drink_by_id(mix_selected_id)
	var can_buy := not selected_drink.is_empty() and not state.is_drink_unlocked(mix_selected_id) and state.credits >= int(selected_drink.cost)
	draw_rect(mix_cellar_buy_button_rect(),Color("6c4b27") if can_buy else Color("2a3344"))
	draw_rect(mix_cellar_buy_button_rect(),AMBER if can_buy else Color("637182"),false,1)
	txt("解锁所选" if can_buy else "选择待解锁酒",Vector2(235,174),6,Color.WHITE if can_buy else Color("a1acbd"))
	txt(fit_text(mix_message,34),Vector2(9,174),6,Color("bdd8e0"))

func draw_memory_transition()->void:
	draw_set_transform(Vector2.ZERO,0.0,Vector2(BAR_VIEW_SCALE,BAR_VIEW_SCALE))
	draw_bar_background()
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
	var t:=clampf(transition_time/1.8,0.0,1.0)
	draw_rect(Rect2(0,0,320,180),Color(0.02,0.02,0.08,t*0.76))
	var center:=Vector2(160,92)
	for i in range(7):
		var radius:=12.0+i*12.0+t*18.0
		var color:Color=[CYAN,MAGENTA,AMBER][i%3]*Color(1,1,1,0.62-t*0.34)
		draw_arc(center,radius,0,TAU,32,color,1)
	var cup_y:=118-int(t*12.0)
	draw_rect(Rect2(146,cup_y,28,3),AMBER)
	draw_colored_polygon(PackedVector2Array([Vector2(149,cup_y+3),Vector2(171,cup_y+3),Vector2(167,cup_y+18),Vector2(153,cup_y+18)]),Color("311b45"))
	draw_rect(Rect2(153,cup_y+6,14,7),Color(0.25,0.9,0.95,0.72))
	txt("杯中记忆正在展开",Vector2(119,31),9,Color.WHITE)
	txt("潜入第一记忆层…",Vector2(130,44),6,CYAN)

func draw_room()->void:
	draw_room_background()
	for h in hazards:draw_hazard(h)
	if witness_downed and not borrowed:draw_shadow(witness_pos);draw_rect(Rect2(witness_pos-Vector2(8,3),Vector2(16,5)),Color("3f9d8d"));txt("E 借身",witness_pos+Vector2(-11,-9),5,CYAN)
	if door_visible:draw_door(Vector2(304,94))
	if room_index==2 and anchor_ready:draw_anchor(Vector2(284,88))
	var actors:Array=[{"kind":"player","pos":player.pos}]
	for e in enemies:actors.append({"kind":"enemy","pos":e.pos,"ref":e})
	actors.sort_custom(func(a,b):return a.pos.y<b.pos.y)
	for actor in actors:
		if actor.kind=="player":draw_combat_player(actor.pos)
		else:draw_enemy(actor.ref)
	for shot in projectiles:
		if shot.delay>0.0:continue
		var p:Vector2=pixel(shot.pos);draw_line(p,p-shot.vel.normalized()*5.0,shot.color,2)
	for p in particles:draw_rect(Rect2(pixel(p.pos),Vector2(2,2)),p.color*Color(1,1,1,clampf(p.life*3,0,1)))
	draw_rect(Rect2(0,154,320,9),Color("101626"));draw_rect(Rect2(0,154,320,2),Color("35405a"))
	for x in range(12,320,47):draw_rect(Rect2(x,150,4,17),Color("171c2c"))
	draw_combat_hud()

func draw_room_background()->void:
	var theme:String=Data.ROOMS[room_index].theme;var floor_color:Color={"street":Color("111b29"),"station":Color("10222a"),"root":Color("171326")}[theme];draw_rect(Rect2(0,27,320,153),floor_color)
	for i in range(12):
		var x:=i*29-int(elapsed*0.4)%29;draw_rect(Rect2(x,28-(i%3)*4,21,24+(i%3)*4),Color("11192d"));draw_rect(Rect2(x+4,32-(i%3)*4,1,8),Color("3b506b"))
	for x in range(0,321,16):draw_line(Vector2(x,43),Vector2(x-25,180),floor_color.lightened(0.055),1)
	for y in range(43,181,16):draw_line(Vector2(0,y),Vector2(320,y),floor_color.lightened(0.05),1)
	if theme=="street":
		for x in [46,112,228]:draw_rect(Rect2(x,52,38,7),Color("242739"))
		for i in range(7):draw_rect(Rect2(25+i*44,128+(i%2)*8,27,2),Color(0.15,0.55,0.62,0.25))
		draw_rect(Rect2(135,45,48,16),Color("25182a"));txt("07",Vector2(153,56),8,MAGENTA)
	elif theme=="station":
		for x in [40,92,240]:draw_rect(Rect2(x,55,33,18),Color("19313a"))
		for x in [46,98,246]:draw_rect(Rect2(x+4,59,25,3),CYAN.darkened(0.35))
		if borrowed:draw_line(Vector2(274,44),Vector2(274,151),CYAN,1);txt("隐藏医疗门",Vector2(248,48),5,CYAN)
	else:
		for i in range(9):var x:=30+i*34;draw_line(Vector2(x,45),Vector2(160,95),Color(0.45,0.18,0.55,0.3),1)
		draw_rect(Rect2(141,49,38,11),Color("311b40"));txt("ROOT",Vector2(149,57),6,MAGENTA)
	for p in [Vector2(32,76),Vector2(112,125),Vector2(272,62)]:draw_shadow(p);draw_rect(Rect2(p-Vector2(8,15),Vector2(16,15)),Color("1d2938"));draw_rect(Rect2(p-Vector2(6,13),Vector2(12,3)),CYAN.darkened(0.5))

func draw_combat_hud()->void:
	draw_rect(Rect2(0,0,320,28),Color("080c16"));txt("L"+str(room_index+1)+" "+Data.ROOMS[room_index].name,Vector2(7,9),6,CYAN);draw_rect(Rect2(7,14,74,6),Color("321522"));draw_rect(Rect2(7,14,74*maxf(0,player.hp/player.max_hp),6),RED);txt(str(int(maxf(0,player.hp)))+"/"+str(int(player.max_hp)),Vector2(35,20),5,Color.WHITE);txt("冲 "+str(dash_charges)+"  Q "+("READY" if q_cd<=0 else str(snapped(q_cd,0.1))),Vector2(91,19),6,AMBER);txt("悖论 "+str(int(state.paradox)),Vector2(168,19),6,MAGENTA);txt("线索 "+str(state.clues.size()),Vector2(241,19),6,CYAN);txt("LMB/J攻击  SPACE冲刺  Q技能  E交互",Vector2(89,176),5,Color("8894a8"));var cross:=pixel(aim_point);draw_line(cross-Vector2(3,0),cross+Vector2(3,0),CYAN,1);draw_line(cross-Vector2(0,3),cross+Vector2(0,3),CYAN,1)

func draw_combat_player(pos:Vector2)->void:
	draw_shadow(pos);var col:=CYAN if borrowed else AMBER
	if player.invuln>0.0 and int(elapsed*18)%2==0:col=Color.WHITE
	var p:=pixel(pos)
	if borrowed:draw_rect(Rect2(p-Vector2(5,13),Vector2(10,12)),Color("235d62"));draw_rect(Rect2(p-Vector2(3,17),Vector2(6,5)),Color("a9d8ca"));draw_rect(Rect2(p+Vector2(4,-10),Vector2(7,3)),CYAN)
	else:draw_rect(Rect2(p-Vector2(5,12),Vector2(10,11)),Color("3b293a"));draw_rect(Rect2(p-Vector2(3,16),Vector2(6,5)),Color("d2b69a"));draw_rect(Rect2(p+Vector2(4,-9),Vector2(6,2)),col)
	draw_rect(Rect2(p-Vector2(6,2),Vector2(12,2)),col)
	if shield>0:draw_rect(Rect2(p-Vector2(8,19),Vector2(16,20)),CYAN,false,1)

func draw_enemy(e:Dictionary)->void:
	draw_shadow(e.pos);var p:=pixel(e.pos);var col:=Color(Data.CHARACTERS[e.type].color)
	if e.hurt>0:col=Color.WHITE
	if e.type=="boss":draw_rect(Rect2(p-Vector2(11,25),Vector2(22,24)),Color("491c2c"));draw_rect(Rect2(p-Vector2(8,29),Vector2(16,7)),col);draw_rect(Rect2(p-Vector2(14,18),Vector2(28,4)),col.darkened(0.2))
	elif e.type=="noise":draw_rect(Rect2(p-Vector2(6,11),Vector2(12,10)),Color("332656"));draw_rect(Rect2(p-Vector2(8,8),Vector2(16,2)),col)
	else:draw_rect(Rect2(p-Vector2(5,13),Vector2(10,12)),col.darkened(0.55));draw_rect(Rect2(p-Vector2(3,17),Vector2(6,5)),col);draw_rect(Rect2(p+Vector2(4,-10),Vector2(8,2)),col) if e.type in ["shooter","witness"] else null
	if e.armed:draw_line(p,player.pos,Color(1,0.18,0.2,0.75),1);txt("!",p-Vector2(2,21),7,RED)
	draw_rect(Rect2(p.x-9,p.y-(32 if e.type=="boss" else 22),18,2),Color("31121c"));draw_rect(Rect2(p.x-9,p.y-(32 if e.type=="boss" else 22),18*maxf(0,e.hp/e.max_hp),2),col)

func draw_shadow(pos:Vector2)->void:var p:=pixel(pos);draw_rect(Rect2(p-Vector2(7,2),Vector2(14,4)),Color(0,0,0,0.5));draw_rect(Rect2(p-Vector2(5,3),Vector2(10,1)),Color(0,0,0,0.4))
func draw_hazard(h:Dictionary)->void:var col:=CYAN if h.kind=="heal" else MAGENTA;draw_circle(pixel(h.pos),h.radius,col*Color(1,1,1,0.09));draw_arc(pixel(h.pos),h.radius,0,TAU,24,col,1)
func draw_door(pos:Vector2)->void:draw_rect(Rect2(pos-Vector2(9,18),Vector2(16,36)),Color("102631"));draw_rect(Rect2(pos-Vector2(9,18),Vector2(16,36)),CYAN,false,2);txt("E",pos+Vector2(-2,3),7,Color.WHITE)
func draw_anchor(pos:Vector2)->void:draw_circle(pos,14+sin(elapsed*4)*2,AMBER*Color(1,1,1,0.12));draw_rect(Rect2(pos-Vector2(4,12),Vector2(8,24)),AMBER,false,2);txt("E 锚点",pos+Vector2(-12,-18),6,AMBER)

func draw_upgrade()->void:
	draw_rect(Rect2(0,0,320,180),Color("0c101d"));txt("固定完成 // 选择一项记忆强化",Vector2(73,27),10,CYAN)
	for i in range(3):
		var u:Dictionary=upgrade_options[i];var r:=Rect2(12+i*103,48,91,89);draw_rect(r,Color("171727"));draw_rect(r,[CYAN,AMBER,MAGENTA][i],false,1);draw_rect(Rect2(r.position+Vector2(34,12),Vector2(24,24)),Color("25253b"));txt(str(i+1),r.position+Vector2(42,30),10,[CYAN,AMBER,MAGENTA][i]);txt(u.name,r.position+Vector2(19,55),8,Color.WHITE);draw_wrapped(u.desc,r.position+Vector2(9,69),15,6,Color("9fa8bb"))
	txt("按 1 / 2 / 3 确认；强化保留到本次潜航结束",Vector2(76,158),6,Color("8996aa"))

func draw_causal()->void:
	draw_rect(Rect2(0,0,320,180),Color("100d1b"));draw_anchor(Vector2(160,39));txt("因果锚点 // 只能有一个过去被写入",Vector2(76,67),9,AMBER);var ids:=["shot_prevented","shot_preserved","death_faked"]
	for i in range(3):var e:Dictionary=Data.ENDINGS[ids[i]];var r:=Rect2(10+i*103,82,94,66);draw_rect(r,Color("191629"));draw_rect(r,[RED,CYAN,MAGENTA][i],false,1);txt(str(i+1)+" "+e.name,r.position+Vector2(8,17),8,Color.WHITE);draw_wrapped(e.choice,r.position+Vector2(8,31),14,6,Color("aab0c2"))
	txt("选择互斥；写入后无法在本次委托中撤销",Vector2(92,166),6,Color("7e899e"))

func draw_settlement()->void:
	draw_rect(Rect2(28,18,264,146),Color("101525"));draw_rect(Rect2(28,18,264,146),AMBER,false,1);txt("委托 #071 结算",Vector2(108,36),11,AMBER)
	for i in range(settlement_lines.size()):txt(settlement_lines[i],Vector2(73,57+i*14),7,Color.WHITE if i<4 else CYAN)
	txt("Enter  进入设施升级",Vector2(111,151),6,Color("929db1"))

func draw_facility()->void:
	draw_rect(Rect2(0,0,320,180),Color("0d111d"));txt("只够完成一次设施升级",Vector2(96,29),10,AMBER);txt("当前信用点 "+str(state.credits),Vector2(124,44),7,CYAN);var opts:=[{"name":"吧台 Mk.I","desc":"下一单解锁额外基酒；吧台灯带变为琥珀色"},{"name":"稳定器 Mk.I","desc":"下一单初始悖论降低；吧台通讯灯出现稳定光环"}]
	for i in range(2):var r:=Rect2(29+i*139,59,123,78);draw_rect(r,Color("171727"));draw_rect(r,CYAN if i==1 else AMBER,false,1);txt(str(i+1)+"  "+opts[i].name,r.position+Vector2(12,22),9,Color.WHITE);draw_wrapped(opts[i].desc,r.position+Vector2(12,39),19,6,Color("a3adbe"));txt("150 信用点",r.position+Vector2(35,69),6,CYAN)

func draw_credits()->void:
	draw_city_layers();draw_rect(Rect2(34,27,252,126),Color(0.04,0.05,0.1,0.93));draw_rect(Rect2(34,27,252,126),CYAN,false,1);txt("一 单 委 托 完 成",Vector2(90,49),13,AMBER);txt("结局："+Data.ENDINGS[state.ending_id()].name,Vector2(106,68),8,Color.WHITE);txt("升级："+("吧台 Mk.I" if state.facility=="bar_counter" else "稳定器 Mk.I"),Vector2(106,82),7,CYAN)
	var call:="企业内部通讯：周主管请求预约。" if state.ending_id()=="shot_prevented" else ("周骁：至少这一次，我记得真相。" if state.ending_id()=="shot_preserved" else "未知来电 / 黎雾：‘下一杯，留给我。’")
	draw_wrapped(call,Vector2(70,104),34,7,MAGENTA);txt("R  从标题重新开始",Vector2(117,141),6,Color("8d98aa"))

func draw_dead()->void:draw_room_background();draw_rect(Rect2(56,51,208,79),Color(0.05,0.04,0.09,0.94));draw_rect(Rect2(56,51,208,79),RED,false,1);txt("记忆排异 / 潜航中断",Vector2(95,77),11,RED);txt("已固定线索仍在；可重试当前记忆层。",Vector2(82,98),7,Color.WHITE);txt("R  重试第 "+str(room_index+1)+" 层",Vector2(119,116),7,CYAN)
func draw_toast()->void:draw_rect(Rect2(38,31,244,16),Color(0.03,0.06,0.1,0.94));draw_rect(Rect2(38,31,244,16),CYAN,false,1);txt(fit_text(toast_text,40),Vector2(45,42),6,Color.WHITE)
func draw_pause()->void:draw_rect(Rect2(0,0,320,180),Color(0,0,0,0.67));draw_rect(Rect2(92,58,136,58),Color("111827"));draw_rect(Rect2(92,58,136,58),CYAN,false,1);txt("潜航暂停",Vector2(130,78),10,CYAN);txt("ESC 继续",Vector2(139,99),7,Color.WHITE)

func draw_pixel_person(pos:Vector2,color:Color,role:String)->void:
	var p:=pixel(pos)
	draw_rect(Rect2(p-Vector2(9,3),Vector2(18,5)),Color(0,0,0,0.52));draw_rect(Rect2(p-Vector2(6,4),Vector2(12,1)),Color(0,0,0,0.4))
	# Enlarged 28 px gameplay placeholder with one fixed foot pivot; still not formal character art.
	draw_rect(Rect2(p-Vector2(7,20),Vector2(14,16)),color.darkened(0.55))
	draw_rect(Rect2(p-Vector2(4,28),Vector2(8,8)),Color("bd987f"))
	draw_rect(Rect2(p-Vector2(9,17),Vector2(3,11)),color.darkened(0.25));draw_rect(Rect2(p+Vector2(6,-17),Vector2(3,11)),color.darkened(0.25))
	draw_rect(Rect2(p-Vector2(7,5),Vector2(5,5)),color);draw_rect(Rect2(p+Vector2(2,-5),Vector2(5,5)),color)
	if role=="corp":draw_rect(Rect2(p-Vector2(7,20),Vector2(14,3)),RED)

func pixel(value:Vector2)->Vector2:return Vector2(round(value.x),round(value.y))
func fit_text(value:String,chars:int)->String:return value if value.length()<=chars else value.substr(0,chars-1)+"…"
func txt(value:String,pos:Vector2,size:int,color:Color)->void:draw_string(ui_font,pixel(pos),value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)
func draw_wrapped(value:String,pos:Vector2,chars:int,size:int,color:Color)->void:
	var line:="";var y:=0
	for ch in value:
		line+=ch
		if line.length()>=chars:txt(line,pos+Vector2(0,y),size,color);line="";y+=size+3
	if not line.is_empty():txt(line,pos+Vector2(0,y),size,color)
