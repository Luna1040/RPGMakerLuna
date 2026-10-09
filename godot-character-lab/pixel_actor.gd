extends Node2D

signal action_event(event_name: String)
var data: Dictionary
var textures: Dictionary = {}
var animation := "idle"
var frame := 0
var elapsed := 0.0
var outfit := "knight"
var boots := "knight"
var hair := "gold"
var cape := true
var weapon := "steel"
var effects := true
var mannequin := false
var debug_bounds := false
var facing := 1
var repeat_attack := false
var attack_wait := 0.0
var paused := false

func configure(manifest: Dictionary) -> void:
	data = manifest
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for action in data.animations.values():
		for record in action.frames:
			for layer in record.layers.values():
				if not textures.has(layer.path):
					textures[layer.path] = ImageTexture.create_from_image(Image.load_from_file(layer.path))
	for item in data.weapons.values():
		textures[item.path] = ImageTexture.create_from_image(Image.load_from_file(item.path))

func play(action: String, restart := false) -> void:
	if action == animation and not restart:
		return
	animation = action
	frame = 0
	elapsed = 0.0
	emit_frame_events()
	queue_redraw()

func current_record() -> Dictionary:
	return data.animations[animation].frames[frame]

func emit_frame_events() -> void:
	for event in current_record().events:
		action_event.emit(event)

func tick(delta: float) -> void:
	if paused:
		return
	if attack_wait > 0:
		attack_wait -= delta
		if attack_wait <= 0:
			play("slash", true)
		return
	elapsed += delta
	while elapsed >= float(current_record().duration):
		elapsed -= float(current_record().duration)
		frame += 1
		if frame >= data.animations[animation].frames.size():
			if data.animations[animation].loop:
				frame = 0
			else:
				play("idle", true)
				if repeat_attack:
					attack_wait = 0.5
				break
		emit_frame_events()
	queue_redraw()

func active_layers() -> Array:
	var result := []
	if not mannequin:
		if cape:
			result.append("cape")
		if hair != "none":
			result.append("hair_back_"+hair)
	result.append("body")
	if not mannequin:
		if boots != "none":
			result.append("boots_"+boots)
		if outfit != "none":
			result.append("torso_"+outfit)
		if hair != "none":
			result.append("hair_front_"+hair)
	return result

func draw_layer(layer_name: String, record: Dictionary) -> void:
	if not record.layers.has(layer_name):
		return
	var item: Dictionary = record.layers[layer_name]
	var offset := Vector2(item.offset[0],item.offset[1])
	draw_texture(textures[item.path],offset)
	if debug_bounds:
		draw_rect(Rect2(offset,Vector2(item.size[0],item.size[1])),Color(0.3,0.8,0.8,0.45),false,0.35)

func _draw() -> void:
	if data.is_empty():
		return
	var record := current_record()
	draw_set_transform(Vector2.ZERO,0,Vector2(facing,1))
	for layer in active_layers():
		draw_layer(layer,record)
	if weapon != "none" and not mannequin:
		var item: Dictionary = data.weapons[weapon]
		var h := Vector2(record.attachments.hand[0],record.attachments.hand[1])
		# Weapon scale never depends on body bounds or current image width.
		draw_set_transform(h * Vector2(facing,1),float(record.weapon_angle)*facing,Vector2(facing,1))
		draw_texture(textures[item.path],-Vector2(item.grip[0],item.grip[1]))
		draw_set_transform(Vector2.ZERO,0,Vector2(facing,1))
		draw_layer("grip",record)
	if effects and not mannequin and weapon != "none":
		draw_layer("effect",record)
	if debug_bounds:
		draw_line(Vector2(-4,0),Vector2(4,0),Color("ffba65"),0.5)
		draw_line(Vector2(0,-4),Vector2(0,4),Color("ffba65"),0.5)
		var h := Vector2(record.attachments.hand[0],record.attachments.hand[1])
		draw_circle(h,1,Color("fa8f6c"))
	draw_set_transform(Vector2.ZERO)
