extends Node2D
## Repeats source artwork at uniform scale rather than stretching the world.
## Mirrored neighbours share the exact same edge pixels, including their shadows.

const WORLD_WIDTH := 3072.0
const FLOOR_TOP := 365.0
const FLOOR_HEIGHT := 620.0
const BACKDROP_SCALE := 0.72

func setup(stage: Node2D) -> void:
	name = "CourtyardBackdrop"
	stage.add_child(self)
	var distant: Texture2D = load("res://assets/backdrop.png")
	# The final 100 source pixels depict a vertical retaining wall, not ground.
	var wall := AtlasTexture.new()
	wall.atlas = distant
	wall.region = Rect2(0, 0, distant.get_width(), 668)
	_add_mirrored_strip(wall, BACKDROP_SCALE, FLOOR_TOP - 668.0 * BACKDROP_SCALE, -10, "Arcade")
	# This source already joins several paving panels. Keeping its native aspect
	# avoids introducing a reflected perspective vanishing point every 827 px.
	var ground: Texture2D = load("res://assets/floor.png")
	_add_mirrored_strip(ground, FLOOR_HEIGHT / ground.get_height(), FLOOR_TOP, -9, "Paving")

func _add_mirrored_strip(texture: Texture2D, uniform_scale: float, top: float, layer: int, prefix: String) -> void:
	var tile_width := texture.get_width() * uniform_scale
	var count := ceili(WORLD_WIDTH / tile_width)
	for index in count:
		var tile := Sprite2D.new()
		tile.name = prefix + str(index)
		tile.texture = texture
		tile.centered = false
		tile.position = Vector2(index * tile_width, top)
		tile.scale = Vector2.ONE * uniform_scale
		tile.flip_h = index % 2 == 1
		tile.z_index = layer
		tile.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(tile)
