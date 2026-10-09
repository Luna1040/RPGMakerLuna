extends Node2D

# PNG playback only: this node never creates a camera, mesh or SubViewport.
var bundle: Dictionary = {}
var textures := {}
var animation := "idle"
var frame := 0
var facing := 1

func load_bundle(path: String) -> void:
	bundle = JSON.parse_string(FileAccess.get_file_as_string(path))
	textures.clear()
	for records in bundle.animations.values():
		for record in records:
			textures[record.path] = ImageTexture.create_from_image(Image.load_from_file(record.path))
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()

func set_pose(action: String, index: int) -> void:
	animation = action
	frame = index
	queue_redraw()

func _draw() -> void:
	if bundle.is_empty():
		return
	var record: Dictionary = bundle.animations[animation][frame]
	draw_set_transform(Vector2.ZERO,0,Vector2(facing,1))
	draw_texture(textures[record.path],Vector2(record.offset[0],record.offset[1]))
	draw_set_transform(Vector2.ZERO)
