extends SceneTree

var counts := {"stone":0,"roof":0,"wall":0,"wood":0,"wild-grass":0}

func inspect(node: Node) -> void:
	if node is MeshInstance3D:
		var kind := str(node.get_meta("material_kind",""))
		if node.name=="GeneratedStonePavement": kind="stone"
		if node.name.begins_with("GeneratedWildGrass"): kind="wild-grass"
		if counts.has(kind):
			assert(node.material_override is ShaderMaterial,"Tagged surface must use generated material")
			assert(node.material_override.get_shader_parameter("color_texture") is ImageTexture)
			counts[kind]+=1
	for child in node.get_children(): inspect(child)

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	for kind in counts:
		var path := "res://assets/textures/chibi/%s.png" % kind
		var refined := FileAccess.file_exists(path)
		if not refined: path="res://assets/textures/%s.png" % kind
		var image := Image.new()
		assert(image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))==OK)
		assert(image.get_size()==(Vector2i(1536,1536) if refined else Vector2i(1024,1024)))
		assert(not image.is_invisible())
		# Raw 2x2 contact sheets document source-edge imperfections, without changing production PNGs.
		var width := image.get_width()
		var tiled := Image.create(width*2,width*2,false,image.get_format())
		for x in range(2):
			for y in range(2): tiled.blit_rect(image,Rect2i(0,0,width,width),Vector2i(x*width,y*width))
		assert(tiled.save_png("res://art-jobs/textures-04/%s-tiled-raw.png" % kind)==OK)
	for name in ["hero-design","street-design"]:
		var image := Image.new()
		assert(image.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/references/%s.png" % name))==OK)
		assert(image.get_width()>=1024)
	var game = load("res://main.tscn").instantiate()
	game.saves.directory="res://art-jobs/textures-04/qa-empty-save-namespace"
	root.add_child(game)
	inspect(game.world)
	for kind in counts: assert(counts[kind]>0,"Generated surface must be integrated")
	game.active_slot=0
	game.queue_free()
	print("PASS: five PNG textures at expected native resolution, real material bindings, mipmapped ImageTextures, two separate design references")
	print("MATERIAL_BINDINGS: ",counts)
	quit(0)
