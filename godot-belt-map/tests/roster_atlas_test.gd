extends SceneTree
## Confirms AtlasTexture padding reconstructs the virtual source pixel space.
const Clips = preload("res://systems/encounters/roster_animation.gd")
var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var original := Image.create(12,10,false,Image.FORMAT_RGBA8)
	original.fill(Color.TRANSPARENT)
	for y in range(2,7):
		for x in range(3,8):
			original.set_pixel(x,y,Color(float(x)/12.0,float(y)/10.0,0.75,0.25 if x == 3 else 1.0))
	var crop := Rect2i(2,1,7,7)
	var source := original.get_region(crop)
	var texture := ImageTexture.create_from_image(source)
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(Vector2.ZERO,Vector2(crop.size))
	atlas.margin = Rect2(Vector2(crop.position),Vector2(original.get_size()-crop.size))
	check(atlas.get_size() == Vector2(original.get_size()),"AtlasTexture logical size must include the full virtual canvas")
	var reconstructed := atlas.get_image()
	check(reconstructed.get_size() == crop.size,"Godot AtlasTexture.get_image returns the stored region, not transparent margin")
	check(reconstructed.get_format() == original.get_format(),"virtual image must retain RGBA8")
	var expanded := Clips.virtual_image(atlas)
	check(Clips.virtual_alpha_bounds(atlas) == original.get_used_rect(),"CPU alpha bounds helper must restore margin offsets")
	reconstructed = expanded
	if reconstructed.get_size() == original.get_size():
		for y in original.get_height():
			for x in original.get_width():
				check(reconstructed.get_pixel(x,y).is_equal_approx(original.get_pixel(x,y)),"virtual pixel mismatch at %d,%d" % [x,y])
	var pivot := Vector2(6,8)
	for facing in [-1.0,1.0]:
		var scaling := Vector2(facing*0.486,0.486)
		for source_pixel in [Vector2(3,2),Vector2(7,6)]:
			var full_position: Vector2 = (source_pixel-pivot)*scaling
			var stored_position: Vector2 = (source_pixel-Vector2(crop.position)+atlas.margin.position-pivot)*scaling
			check(full_position.is_equal_approx(stored_position),"crop plus AtlasTexture margin must preserve every visible pixel's world position")
	var probe := cache_probe()
	if probe != null:
		check(probe.get_ref() == null,"shared raw PNG cache must not permanently retain unused GPU textures")
	if DisplayServer.get_name() != "headless":
		var full_texture := ImageTexture.create_from_image(original)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(64,32)
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var drawing := Node2D.new()
		drawing.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		viewport.add_child(drawing)
		drawing.draw.connect(_draw_comparison.bind(drawing,full_texture,atlas))
		drawing.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var screen := viewport.get_texture().get_image()
		for y in 26:
			for x in 12:
				check(screen.get_pixel(x,y).is_equal_approx(screen.get_pixel(x+20,y)),"GPU draw_texture placement mismatch %d,%d" % [x,y])
		print("ROSTER_ATLAS_GPU_PIXELS ","PASS" if failures.is_empty() else "FAIL"," · draw_texture at normal and mirrored scale")
		viewport.queue_free()
		await process_frame
	else:
		print("ROSTER_ATLAS_GPU_PIXELS SKIP · headless renderer; run without --headless to verify actual GPU output")
	print("ROSTER_ATLAS_TEST ","PASS" if failures.is_empty() else "FAIL"," · ",checks," margin, virtual image and mirrored pixel-placement checks")
	for message in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)

func _draw_comparison(canvas: Node2D, full: Texture2D, packed: Texture2D) -> void:
	canvas.draw_texture(full,Vector2.ZERO)
	canvas.draw_texture(packed,Vector2(20,0))
	canvas.draw_set_transform(Vector2(12,16),0.0,Vector2(-0.486,0.486))
	canvas.draw_texture(full,Vector2.ZERO)
	canvas.draw_set_transform(Vector2(32,16),0.0,Vector2(-0.486,0.486))
	canvas.draw_texture(packed,Vector2.ZERO)

func cache_probe() -> WeakRef:
	var first := Clips.new()
	var second := Clips.new()
	first.configure("serin")
	second.configure("serin")
	if not first.has_action("stand"):
		print("ROSTER_TEXTURE_SHARING SKIP · Serin stand not yet published")
		return null
	var relative := str(first.clip("stand").frames[0].file)
	var a: Texture2D = first.texture_for(relative)
	var b: Texture2D = second.texture_for(relative)
	check(a != null and b != null,"published first frame must load")
	if a == null or b == null: return null
	if a is AtlasTexture: a = a.atlas
	if b is AtlasTexture: b = b.atlas
	check(a == b,"two actor players must share one underlying imported or raw GPU texture")
	return weakref(a)
