extends Node2D

const CELL := 256.0/3.0
const ANCHOR := Vector2(128.0/3.0,238.0/3.0)
var textures := {}
var pixels := {}
var measurements := {}
var data: Dictionary
var action := "walk"
var frame := 0
var dressed := true
var hair := true
var weapon := true
var effects := true
var align_feet := true
var ghost := false
var skin_only := false
var facing := 1

func configure(manifest: Dictionary) -> void:
	data = manifest
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for name_ in ["skin","armor","hair","reference"]:
		var path := "res://assets/pose-reference.png" if name_ == "reference" else "res://assets/ai-%s-v1.png" % name_
		if name_ == "hair":
			path = "res://assets/ai-hair-v2.png"
		if name_ == "skin":
			path = "res://assets/ai-skin-v2.png"
		if FileAccess.file_exists(path):
			pixels[name_] = Image.load_from_file(path)
			textures[name_] = ImageTexture.create_from_image(pixels[name_])
			measurements[name_] = []
			for index in range(9):
				var region := source_rect(pixels[name_].get_size(),index)
				var bounds: Rect2i = solid_bounds(pixels[name_],region)
				# Position correction only. Never scale individual poses to fit.
				var foot_error: float = bounds.end.y * CELL/region.size.y - ANCHOR.y
				measurements[name_].append({"bounds":bounds,"foot_error":foot_error})
	var item: Dictionary = data.weapons.steel
	textures.sword = ImageTexture.create_from_image(Image.load_from_file(item.path))
	for action_data in data.animations.values():
		for record in action_data.frames:
			if record.layers.has("effect"):
				var effect: Dictionary = record.layers.effect
				textures[effect.path] = ImageTexture.create_from_image(Image.load_from_file(effect.path))
	queue_redraw()

func solid_bounds(image: Image, region: Rect2i) -> Rect2i:
	# Ignore almost-transparent generation fringes when measuring anchors.
	var first := region.size
	var last := Vector2i(-1,-1)
	for y in range(region.size.y):
		for x in range(region.size.x):
			if image.get_pixel(region.position.x+x,region.position.y+y).a > .7:
				first = first.min(Vector2i(x,y))
				last = last.max(Vector2i(x,y))
	return Rect2i(first,last-first+Vector2i.ONE)

func source_rect(size_: Vector2i, index: int) -> Rect2i:
	var col := index%3
	var row := index/3
	var start := Vector2i(floori(col*size_.x/3.0),floori(row*size_.y/3.0))
	var end := Vector2i(floori((col+1)*size_.x/3.0),floori((row+1)*size_.y/3.0))
	return Rect2i(start,end-start)

func pose_index() -> int:
	if action == "idle":
		return 0
	if action == "walk":
		return frame+1
	return [5,6,7,7,8,8][frame]

func set_pose(action_: String, frame_: int) -> void:
	action = action_
	frame = frame_
	queue_redraw()

func draw_sheet(layer: String, index: int, color := Color.WHITE) -> void:
	if not textures.has(layer):
		return
	var shift := 0.0
	if align_feet:
		if layer in ["skin","armor"]:
			shift = -float(measurements[layer][index].foot_error)
		elif layer == "hair":
			# Use a head-top reference, since a hair-only layer has no feet.
			var skin_rect := source_rect(pixels.skin.get_size(),index)
			var hair_rect := source_rect(pixels.hair.get_size(),index)
			var skin_top: float = measurements.skin[index].bounds.position.y*CELL/skin_rect.size.y
			var hair_top: float = measurements.hair[index].bounds.position.y*CELL/hair_rect.size.y
			shift = skin_top-hair_top-float(measurements.skin[index].foot_error)-2.0
	var rect := Rect2(-ANCHOR+Vector2(0,shift),Vector2(CELL,CELL))
	draw_texture_rect_region(textures[layer],rect,source_rect(pixels[layer].get_size(),index),color)

func _draw() -> void:
	if textures.is_empty():
		return
	var index := pose_index()
	draw_set_transform(Vector2.ZERO,0,Vector2(facing,1))
	draw_sheet("skin",index)
	if dressed and not skin_only:
		draw_sheet("armor",index)
	if hair and not skin_only:
		draw_sheet("hair",index)
	if ghost:
		draw_sheet("reference",index,Color(0.3,0.9,1,0.35))
	var record: Dictionary = data.animations[action].frames[frame]
	if weapon and not skin_only:
		var h := Vector2(record.attachments.hand[0],record.attachments.hand[1])
		var item: Dictionary = data.weapons.steel
		draw_set_transform(h*Vector2(facing,1),float(record.weapon_angle)*facing,Vector2(facing,1))
		draw_texture(textures.sword,-Vector2(item.grip[0],item.grip[1]))
		draw_set_transform(Vector2.ZERO,0,Vector2(facing,1))
	if effects and weapon and not skin_only and record.layers.has("effect"):
		var effect: Dictionary = record.layers.effect
		draw_texture(textures[effect.path],Vector2(effect.offset[0],effect.offset[1]))
	if ghost:
		draw_line(Vector2(-5,0),Vector2(5,0),Color("edc16c"),.5)
		draw_circle(Vector2(record.attachments.hand[0],record.attachments.hand[1]),1,Color("f38676"))
	draw_set_transform(Vector2.ZERO)
