extends SceneTree
const TestStage = preload("res://tests/encounters_test.gd").TestStage
const Encounters = preload("res://systems/encounters/encounters.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280,800)
	var stage = TestStage.new()
	root.add_child(stage)
	stage.add_child(stage.sorting)
	stage.sorting.y_sort_enabled = true
	var background := Polygon2D.new()
	background.polygon = PackedVector2Array([Vector2(0,0),Vector2(4000,0),Vector2(4000,1200),Vector2(0,1200)])
	background.color = Color("172731")
	background.z_index = -5
	stage.add_child(background)
	stage.knight = preload("res://characters/first_knight/knight.tscn").instantiate()
	stage.knight.use_local_input = false
	stage.knight.equipment.persistence_enabled = false
	stage.sorting.add_child(stage.knight)
	stage.knight.set_physics_process(false)
	stage.foot = Vector2(18.5,4.5)
	stage.knight.position = stage.project(stage.foot)
	var service = Encounters.new()
	stage.add_child(service)
	service.setup(stage)
	service.set_companion_enabled(true)
	service.companion_foot = Vector2(20.2,5.2)
	service.begin_wave(3,1101)
	var boss: Dictionary = service.enemies[0]
	boss.state = "telegraph"
	boss.attack_variant = "slam"
	boss.aim = Vector2(22,5.3)
	boss.attack_origin = boss.foot
	var melee: Dictionary = service.enemies[2]
	melee.foot = Vector2(23.4,7.6)
	melee.state = "telegraph"
	melee.attack_variant = "melee"
	melee.attack_origin = melee.foot
	melee.attack_facing = -1
	var caster: Dictionary = service.enemies[1]
	caster.foot = Vector2(23.5,3)
	caster.state = "telegraph"
	caster.attack_variant = "ranged"
	caster.attack_origin = caster.foot
	caster.aim = Vector2(21.5,3.3)
	for enemy: Dictionary in service.enemies:
		enemy.art.position = stage.project(enemy.foot)
		enemy.art.queue_redraw()
	service._update_companion_view()
	service.queue_redraw()
	var camera := Camera2D.new()
	camera.position = Vector2(21*120,610)
	stage.add_child(camera)
	var layer := CanvasLayer.new()
	stage.add_child(layer)
	var label := Label.new()
	label.position = Vector2(30,25)
	label.text = "ENCOUNTER FOUNDATION / Code-drawn prototype actors\nShared animated ally / telegraphs / melee, caster, boss / no additional art downloads"
	label.add_theme_font_size_override("font_size",20)
	layer.add_child(label)
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://systems/encounters/review.png")
	print("ENCOUNTERS_VISUAL_CAPTURE systems/encounters/review.png")
	quit()
