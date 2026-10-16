extends RefCounted

# Ignore source texture dimensions before assigning it, then apply the slot rectangle.
static func add_to(parent: Control, texture: Texture2D, bounds: Rect2) -> TextureRect:
	var picture:=TextureRect.new()
	picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size=Vector2.ZERO
	picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
	picture.clip_contents=true
	picture.texture=texture
	parent.add_child(picture)
	picture.position=bounds.position
	picture.size=bounds.size
	return picture
