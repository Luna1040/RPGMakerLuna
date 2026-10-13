extends RefCounted
## Original town residents. The map owns input and dialogue presentation.
const INTERACTION_RADIUS := 1.4
var residents: Array[Dictionary] = []
var elapsed := 0.0
var stage: Node2D

func setup(map_stage: Node2D) -> void:
	stage = map_stage
	if stage.contract.get("zone_id", "town")=="city":
		_add_resident("mira","米拉 · 药剂师",Vector2(6,5.1),"res://assets/npcs/mira.png",Vector2(510,1520),1500,Rect2(240,20,560,650),["欢迎来到晨钟城，出发前来补充药剂吧。"])
		_add_resident("oren","奥伦 · 卫队长",Vector2(18.5,5.5),"res://assets/npcs/oren.png",Vector2(510,1520),1500,Rect2(240,10,560,650),["古塔的钟声已经失控，我们需要你的援手。"])
		return
	_add_resident("innkeeper", "艾琳 · 旅店主人", Vector2(5.2, 4.1), "res://assets/npcs/innkeeper.png", Vector2(520, 1500), 1458.0, Rect2(300, 40, 410, 455), [
		"欢迎来到苍石庭院。我是艾琳，旅店就在身后。先在这里熟悉一下身手吧。",
		"旧木箱已经没人用了，打碎后留下的杂物可以收进背包。别对着镇民挥剑就好。",
		"庭院东边住着铁匠雷恩。如果找到了新装备，可以去和他聊聊。"
	])
	_add_resident("smith", "雷恩 · 铁匠", Vector2(18.5, 6.4), "res://assets/npcs/smith.png", Vector2(520, 1510), 1500.0, Rect2(300, 5, 410, 450), [
		"我是雷恩。剑刃要锋利，握剑的手也要稳。欢迎来我的小作坊。",
		"庭院的宝箱里留了些武器与装备，靠近后交互就能打开。拿到手，记得检查背包。",
		"木箱能踩，也能打碎。喷泉池沿和中间的石柱都是实体，池水里不能落脚。"
	])

func _add_resident(id: String, display_name: String, world_position: Vector2, path: String, pivot: Vector2, drawn_height: float, portrait_region: Rect2, lines: Array) -> void:
	var texture: Texture2D = load(path)
	var root := Node2D.new()
	root.name = "TownNPC_" + id
	root.position = stage.project(world_position)
	stage.sorting.add_child(root)
	# Physical footprint is centered at the feet, not the whole illustrated silhouette.
	stage.volumes.append({"id":"npc-"+id,"kind":"npc","x":world_position.x-0.28,"depth":world_position.y-0.23,"width":0.56,"depth_size":0.46,"base_z":0.0,"height":2.2,"solid":true,"standable":false})
	var shadow := Polygon2D.new()
	var points := PackedVector2Array()
	for i in range(32):
		var angle := TAU * i / 32.0
		points.append(Vector2(cos(angle) * 25, sin(angle) * 7))
	shadow.polygon = points
	shadow.color = Color(0.025, 0.03, 0.035, 0.3)
	root.add_child(shadow)
	var visual := Node2D.new()
	root.add_child(visual)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	var ratio := 264.0 / drawn_height
	sprite.scale = Vector2.ONE * ratio
	sprite.position = -pivot * ratio
	visual.add_child(sprite)
	var idle_frames: Array[Texture2D] = []
	var idle_data: Dictionary = {}
	var idle_path := "res://assets/npcs/" + id + "-idle.json"
	var blend := Sprite2D.new()
	if FileAccess.file_exists(idle_path):
		idle_data = JSON.parse_string(FileAccess.get_file_as_string(idle_path))
		for frame: Dictionary in idle_data.frames:
			idle_frames.append(load("res://assets/npcs/" + str(frame.file)))
		sprite.texture = idle_frames[0]
		sprite.scale = Vector2.ONE * float(idle_data.scale)
		sprite.position = -Vector2(idle_data.pivot[0], idle_data.pivot[1]) * float(idle_data.scale)
		blend.texture = idle_frames[0]
		blend.centered = false
		blend.scale = sprite.scale
		blend.position = sprite.position
		blend.modulate.a = 0.0
		visual.add_child(blend)
	var label := Label.new()
	label.position = Vector2(-120, -292)
	label.size = Vector2(240, 27)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.65))
	label.add_theme_color_override("font_shadow_color", Color(0.02, 0.03, 0.04, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.text = display_name
	root.add_child(label)
	var portrait := AtlasTexture.new()
	portrait.atlas = texture
	portrait.region = portrait_region
	residents.append({"id": id, "name": display_name, "position": world_position, "portrait": portrait, "lines": lines, "root": root, "visual": visual, "label": label, "sprite":sprite, "blend":blend, "idle_frames":idle_frames, "idle_data":idle_data})

func step(delta: float, player_foot: Vector2, player_height: float) -> void:
	elapsed += delta
	var candidate := nearest(player_foot, player_height)
	for i in range(residents.size()):
		var resident: Dictionary = residents[i]
		if not resident.idle_frames.is_empty():
			var duration: float = resident.idle_frames.size() * float(resident.idle_data.frame_ms) / 1000.0
			# Play the actual occupational gesture, pause, then dissolve back to its start.
			# Each NPC starts at a different phase; collision and foot root never move.
			var phase := fposmod(elapsed + i*2.6, duration+1.2)
			var index := mini(int(phase*1000.0/float(resident.idle_data.frame_ms)),resident.idle_frames.size()-1)
			resident.sprite.texture = resident.idle_frames[index]
			var blend_alpha := clampf((phase-duration-.7)/.5,0,1)
			resident.blend.modulate.a = blend_alpha
			resident.sprite.modulate.a = 1.0
		else:
			resident.visual.scale.y = 1.0 + sin(elapsed * 1.7 + i * 1.9) * 0.0025
		resident.label.modulate = Color.WHITE if candidate.get("id", "") == resident.id else Color(0.85, 0.85, 0.85, 0.85)

func nearest(player_foot: Vector2, player_height: float = 0.0) -> Dictionary:
	if player_height > 0.3:
		return {}
	var result: Dictionary = {}
	var best_distance := INTERACTION_RADIUS
	for resident: Dictionary in residents:
		var distance := player_foot.distance_to(resident.position)
		if distance <= best_distance:
			best_distance = distance
			result = resident
	return result
