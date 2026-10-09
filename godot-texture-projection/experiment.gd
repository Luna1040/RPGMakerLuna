extends Node2D

const OldModel = preload("res://model.gd")
var source: Image
var art: ImageTexture
var old: Node2D
var old_materials := {}
var fitted_view: SubViewport
var fitted_root: Node3D
var fitted_material: ShaderMaterial
var fitted_camera: Camera3D
var time := 0.0
var angle := 0.0
var animate := false
var pose_name := "idle"
var cut_background := true
var status: Label
var angle_slider: HSlider

func _ready() -> void:
	var atlas := (load("res://assets/original-atlas.png") as Texture2D).get_image()
	var cell := atlas.get_region(Rect2i(0,0,atlas.get_width()/4,atlas.get_height()/4))
	# The generated atlas is not a multiple of the requested 320px cell size.
	# Pad the extracted frame without resampling any original pixels.
	source = Image.create(320,320,false,Image.FORMAT_RGBA8)
	source.fill(Color.TRANSPARENT)
	source.blit_rect(cell,Rect2i(Vector2i.ZERO,cell.get_size()),Vector2i.ZERO)
	art = ImageTexture.create_from_image(source)
	source.save_png("res://assets/original-idle.png")
	var original := Sprite2D.new()
	original.texture = art
	original.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	original.position = Vector2(215,390)
	original.scale = Vector2(1.1,1.1)
	add_child(original)
	make_old()
	make_fitted()
	build_ui()
	queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://preview/comparison.png")
	fitted_view.get_texture().get_image().save_png("res://preview/fitted-front.png")
	old.viewport.get_texture().get_image().save_png("res://preview/old-projected.png")
	print("TEXTURE_TEST_READY: original art -> projected 3D and silhouette extrusion; lighting disabled")
	if "--verify" in OS.get_cmdline_user_args():
		await verify_render()

func make_old() -> void:
	old = OldModel.new()
	old.effects = false
	old.camera_angle = 18.0
	add_child(old)
	old.viewport.size = Vector2i(320,320)
	old.pixel_viewport.size = Vector2i(320,320)
	old.display.visible = false
	old.camera.size = 2.3
	old.camera.position = Vector3(.3,1.15,0)+Vector3(sin(deg_to_rad(18.0))*7,0,cos(deg_to_rad(18.0))*7)
	old.camera.look_at(Vector3(.3,1.15,0))
	var right: Vector3 = old.camera.global_basis.x
	for key in old.meshes:
		var node: MeshInstance3D = old.meshes[key]
		var mat := ShaderMaterial.new()
		mat.shader = load("res://projected.gdshader")
		mat.set_shader_parameter("original",art)
		mat.set_shader_parameter("rest_transform",node.global_transform)
		mat.set_shader_parameter("projection_right",right)
		node.material_override = mat
		old_materials[key] = mat
	var sprite := Sprite2D.new()
	sprite.texture = old.viewport.get_texture()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = Vector2(640,390)
	sprite.scale = Vector2(1.1,1.1)
	add_child(sprite)

func make_fitted() -> void:
	fitted_view = SubViewport.new()
	fitted_view.size = Vector2i(320,320)
	fitted_view.transparent_bg = true
	fitted_view.own_world_3d = true
	fitted_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(fitted_view)
	fitted_root = Node3D.new()
	fitted_view.add_child(fitted_root)
	fitted_camera = Camera3D.new()
	fitted_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	fitted_camera.size = 2.3
	fitted_camera.position = Vector3(0,0,5)
	fitted_view.add_child(fitted_camera)
	fitted_camera.look_at(Vector3.ZERO)
	fitted_material = ShaderMaterial.new()
	fitted_material.shader = load("res://art-surface.gdshader")
	fitted_material.set_shader_parameter("original",art)
	var front := SurfaceTool.new()
	front.begin(Mesh.PRIMITIVE_TRIANGLES)
	# A subdivided real 3D surface, with UVs locked to the original image.
	for y in range(0,320,4):
		for x in range(0,320,4):
			add_quad(front, [Vector2(x,y),Vector2(x+4,y),Vector2(x,y+4),Vector2(x+4,y+4)],.04)
	var face := MeshInstance3D.new()
	face.mesh = front.commit()
	face.material_override = fitted_material
	fitted_root.add_child(face)
	var sides := SurfaceTool.new()
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in range(320):
		for x in range(320):
			if not solid(x,y):
				continue
			for edge in [[Vector2i(-1,0),Vector2(x,y),Vector2(x,y+1)], [Vector2i(1,0),Vector2(x+1,y+1),Vector2(x+1,y)], [Vector2i(0,-1),Vector2(x+1,y),Vector2(x,y)], [Vector2i(0,1),Vector2(x,y+1),Vector2(x+1,y+1)]]:
				if not solid(x+edge[0].x,y+edge[0].y):
					var a: Vector2 = edge[1]
					var b: Vector2 = edge[2]
					var v := [world(a,.039),world(b,.039),world(a,-.04),world(b,-.04)]
					for index in [0,1,2,1,3,2]:
						sides.add_vertex(v[index])
	sides.generate_normals()
	var rim := MeshInstance3D.new()
	rim.mesh = sides.commit()
	var edge_mat := StandardMaterial3D.new()
	edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	edge_mat.albedo_color = Color("17243e")
	rim.material_override = edge_mat
	fitted_root.add_child(rim)
	# The source has no rear view. Do not fabricate a convincing reverse texture.
	var back_mat := ShaderMaterial.new()
	back_mat.shader = load("res://back.gdshader")
	back_mat.set_shader_parameter("original",art)
	var back := MeshInstance3D.new()
	back.mesh = face.mesh
	back.position.z = -.08
	back.material_override = back_mat
	fitted_root.add_child(back)
	var sprite := Sprite2D.new()
	sprite.texture = fitted_view.get_texture()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = Vector2(1065,390)
	sprite.scale = Vector2(1.1,1.1)
	add_child(sprite)

func world(p: Vector2,z: float) -> Vector3:
	return Vector3((p.x/320.0-.5)*2.3,(.5-p.y/320.0)*2.3,z)

func solid(x: int,y: int) -> bool:
	return x >= 0 and x < 320 and y >= 0 and y < 320 and source.get_pixel(x,y).a >= .5

func add_quad(tool: SurfaceTool, points: Array,z: float) -> void:
	for index in [0,2,1,1,2,3]:
		var p: Vector2 = points[index]
		tool.set_uv(p/320.0)
		tool.set_normal(Vector3(0,0,1))
		tool.add_vertex(world(p,z))

func label(at: Vector2,text_: String,size := 18,color := Color("c5d5eb")) -> Label:
	var node := Label.new()
	node.position = at
	node.text = text_
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",color)
	add_child(node)
	return node

func button(at: Vector2,text_: String,callback: Callable) -> void:
	var node := Button.new()
	node.position = at
	node.text = text_
	node.pressed.connect(callback)
	add_child(node)

func build_ui() -> void:
	label(Vector2(30,20),"Original knight artwork as a 3D texture",28)
	label(Vector2(30,61),"No new lighting, reflections, ambient occlusion or shadow blur. Original painted shading stays in the texture.",17)
	label(Vector2(75,147),"1  Original 2D frame",22)
	label(Vector2(490,147),"2  Project onto old 3D mesh",22)
	label(Vector2(905,147),"3  Fit mesh to art (2.5D)",22)
	label(Vector2(55,593),"Reference: unchanged first generated frame",16)
	label(Vector2(456,593),"Geometry clips details and misplaces features",16,Color("f0ae85"))
	label(Vector2(874,593),"Front artwork preserved; thin volume only",16)
	button(Vector2(30,102),"Static / reset",func(): animate = false; angle_slider.value = 0; pose_name = "idle")
	button(Vector2(163,102),"Motion stress test",func(): animate = not animate; pose_name = "walk")
	button(Vector2(325,102),"Turn to rear",func(): angle_slider.value = 160)
	button(Vector2(444,102),"Projection alpha on/off",func(): cut_background = not cut_background; for mat in old_materials.values(): mat.set_shader_parameter("cut_background",cut_background))
	label(Vector2(675,105),"Turn",16)
	angle_slider = HSlider.new()
	angle_slider.position = Vector2(724,108)
	angle_slider.size = Vector2(260,20)
	angle_slider.min_value = -80
	angle_slider.max_value = 180
	angle_slider.value_changed.connect(func(value: float): angle = value)
	add_child(angle_slider)
	status = label(Vector2(1010,105),"0 degrees",16)
	label(Vector2(30,663),"The fitted mesh is NOT a reconstructed human body. Back, hidden limbs and separate equipment are missing.",18,Color("f0be83"))
	label(Vector2(30,699),"Motion test: old mesh moves its joints; fitted surface only deforms the one image. It is not a completed walk animation.",17)
	label(Vector2(30,735),"Goal: test whether original painted detail survives texturing before spending time on reconstruction and rigging.",17)

func _process(delta: float) -> void:
	time += delta
	if old == null or fitted_root == null:
		return
	old.set_pose(pose_name,int(time*3)%4 if pose_name == "walk" else 0)
	for key in old_materials:
		old.meshes[key].material_override = old_materials[key]
	old.camera.size = 2.3
	old.camera.position = Vector3(.3,1.15,0)+Vector3(sin(deg_to_rad(18.0+angle))*7,0,cos(deg_to_rad(18.0+angle))*7)
	old.camera.look_at(Vector3(.3,1.15,0))
	fitted_root.rotation.y = deg_to_rad(angle)
	fitted_material.set_shader_parameter("clock",time)
	fitted_material.set_shader_parameter("deformation",1.0 if animate else 0.0)
	status.text = "%d degrees" % int(angle)

func _draw() -> void:
	for x in [425,850]:
		draw_line(Vector2(x,145),Vector2(x,625),Color("29364a"),1)
	for col in range(3):
		draw_line(Vector2(col*425+35,566),Vector2(col*425+390,566),Color("647993"),1)

func verify_render() -> void:
	var front := fitted_view.get_texture().get_image()
	var errors := 0
	var samples := 0
	var mismatch_examples := []
	var missing := 0
	var max_color_error := 0.0
	# Sample opaque interior texels, away from alpha boundaries. This checks
	# geometric UV alignment, not the entire screen or transparent edge pixels.
	for y in range(1,319):
		for x in range(1,319):
			var c := source.get_pixel(x,y)
			if c.a > .99 and solid(x-1,y) and solid(x+1,y) and solid(x,y-1) and solid(x,y+1):
				samples += 1
				var result := front.get_pixel(x,y)
				if result.a < .9:
					missing += 1
				max_color_error = maxf(max_color_error,maxf(absf(result.r-c.r),maxf(absf(result.g-c.g),absf(result.b-c.b))))
				if result.a < .9 or maxf(absf(result.r-c.r),maxf(absf(result.g-c.g),absf(result.b-c.b))) > .025:
					errors += 1
					if mismatch_examples.size() < 8:
						mismatch_examples.append({"xy":[x,y],"source":c.to_html(),"render":result.to_html()})
	angle = 45
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	fitted_view.get_texture().get_image().save_png("res://preview/fitted-45.png")
	angle = 160
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	fitted_view.get_texture().get_image().save_png("res://preview/fitted-rear.png")
	var report := {"opaque_interior_samples":samples,"errors_at_strict_color_tolerance":errors,"missing_interior_texels":missing,"maximum_rgb_error":max_color_error,"mismatch_examples":mismatch_examples,"strict_tolerance":.025,"acceptance_rgb_tolerance":.04,"color_note":"GL compatibility color conversion loses several dark RGB levels; not byte-identical to the original PNG","original_frame":"original-atlas cell 0","unlit":true,"fitted_model":"subdivided textured front, extruded silhouette sides, plain rear; no skeleton"}
	var f := FileAccess.open("res://preview/verification.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"\t"))
	print("TEXTURE_VERIFY ",JSON.stringify(report))
	get_tree().quit(0 if missing == 0 and max_color_error <= .04 else 1)
