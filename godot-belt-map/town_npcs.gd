extends RefCounted
## Original town residents. The map owns input and dialogue presentation.
const Validator = preload("res://systems/content/content_validator.gd")
const RosterAnimation = preload("res://systems/encounters/roster_animation.gd")
const CATALOG_PATH := "res://content/base/town_npcs.json"
const INTERACTION_RADIUS := 1.4
var residents: Array[Dictionary] = []
var elapsed := 0.0
var stage: Node2D

func setup(map_stage: Node2D) -> void:
	stage = map_stage
	var definitions := _definitions()
	var ids: Array = definitions.keys()
	ids.sort()
	var zone_id := str(stage.contract.get("zone_id", "town"))
	var city_ids := ["mira", "oren"]
	for id in ids:
		if zone_id == "city" and id not in city_ids: continue
		if zone_id == "town" and id in city_ids: continue
		_add_resident(definitions[id])

func _definitions() -> Dictionary:
	var registry = stage.get_node_or_null("/root/ContentRegistry")
	if registry != null and registry.loaded:
		return registry.definitions("npc")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	var errors := Validator.validate_content_bundle(parsed)
	if not errors.is_empty():
		push_error("Town NPC catalog: " + "; ".join(errors))
		return {}
	var result := {}
	for entry: Dictionary in parsed.entries:
		result[str(entry.id)] = entry.duplicate(true)
	return result

func _add_resident(definition: Dictionary) -> void:
	var id := str(definition.id)
	var display_name := str(definition.display_name)
	var world_position := Vector2(float(definition.position_m[0]), float(definition.position_m[1]))
	var visual_definition: Dictionary = definition.visual
	var asset_registry = stage.get_node_or_null("/root/NpcAssetRegistry")
	var asset_profile: Dictionary = asset_registry.resolve_visual(visual_definition) if asset_registry != null else {}
	var base_path := str(asset_profile.get("base_path", ""))
	var idle_path := str(asset_profile.get("manifest_path", ""))
	if asset_profile.is_empty() or base_path.is_empty() or idle_path.is_empty():
		push_error("Town NPC uses an unregistered asset id: " + id)
		return
	var pivot := Vector2(float(visual_definition.pivot_px[0]), float(visual_definition.pivot_px[1]))
	var drawn_height := float(visual_definition.drawn_height_px)
	var region: Array = visual_definition.portrait_region_px
	var portrait_region := Rect2(float(region[0]), float(region[1]), float(region[2]), float(region[3]))
	var lines: Array = definition.ambient_lines.duplicate()
	var texture: Texture2D = load(base_path)
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
	var roster_animation = null
	var blend := Sprite2D.new()
	visual.add_child(blend)
	if asset_profile.renderer == "roster_actions":
		roster_animation = RosterAnimation.new()
		roster_animation.configure(str(asset_profile.roster_id))
		var sampled: Dictionary = roster_animation.sample(str(asset_profile.ambient_action), 0.0, true)
		if sampled.is_empty():
			push_error("Town NPC asset profile has no playable ambient action: " + id)
			root.queue_free()
			return
		sprite.texture = sampled.texture
		sprite.scale = Vector2.ONE * float(sampled.scale)
		sprite.position = -Vector2(sampled.pivot) * float(sampled.scale)
	elif FileAccess.file_exists(idle_path):
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
	var portrait: Texture2D
	if asset_profile.renderer == "roster_actions":
		portrait = texture
	else:
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = portrait_region
		portrait = atlas
	residents.append({"id": id, "name": display_name, "position": world_position, "portrait": portrait, "lines": lines, "root": root, "visual": visual, "label": label, "sprite":sprite, "blend":blend, "idle_frames":idle_frames, "idle_data":idle_data,
		"renderer":str(asset_profile.renderer), "animation":roster_animation, "ambient_action":str(asset_profile.ambient_action), "asset_profile_id":str(asset_profile.profile_id)})

func step(delta: float, player_foot: Vector2, player_height: float) -> void:
	elapsed += delta
	var candidate := nearest(player_foot, player_height)
	for i in range(residents.size()):
		var resident: Dictionary = residents[i]
		if resident.animation != null:
			var sampled: Dictionary = resident.animation.sample(str(resident.ambient_action), elapsed * 1000.0 + i * 310.0, true)
			if not sampled.is_empty():
				resident.sprite.texture = sampled.texture
				resident.sprite.scale = Vector2.ONE * float(sampled.scale)
				resident.sprite.position = -Vector2(sampled.pivot) * float(sampled.scale)
		elif not resident.idle_frames.is_empty():
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
