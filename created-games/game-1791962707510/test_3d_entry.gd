extends SceneTree

func _initialize() -> void:
	call_deferred("check_entry")

func check_entry() -> void:
	assert(ProjectSettings.get_setting("application/run/main_scene")=="res://main.tscn")
	var game = load("res://main.tscn").instantiate()
	game.saves.directory="res://art-jobs/entry-test-%d" % Time.get_ticks_usec()
	root.add_child(game)
	await physics_frame
	assert(game.world is Node3D and game.hero is CharacterBody3D and game.camera.current)
	assert(game.get_script().resource_path=="res://city_3d.gd","Official entry must load the expanded city")
	assert(game.monsters.size()==60,"Official entry contains sixty wilderness creatures")
	assert(game.menu.visible and game.slot_buttons.size()==6)
	game.active_slot=0
	game.queue_free()
	print("PASS: official main.tscn loads 3D street, volume models, camera and six-slot menu; no gameplay window launched")
	quit(0)
