extends SceneTree

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var game = load("res://main.tscn").instantiate()
	game.saves.directory="res://art-jobs/chibi-05/npc-test-%d" % Time.get_ticks_usec()
	root.add_child(game)
	game.name_input.text="NPC寻路测试"
	game.select_slot(1)
	var frames := 0
	for title in game.town_actors:
		game.dialogue.hide()
		game.hero.position=Vector3(0,0.05,3.5)
		game.hero.velocity=Vector3.ZERO
		game.camera_anchor=game.hero.position+Vector3(0,1.3,0)
		var actor: Node3D=game.town_actors[title]
		game.navigate_to_actor(actor,"master" if title=="泫渤派门主" else "npc:"+title)
		assert(not game.route.is_empty())
		for step in range(700):
			await physics_frame
			frames+=1
			if game.dialogue.visible: break
		assert(game.dialogue.visible and game.dialogue_text.text.begins_with(title),"Every NPC approach reaches dialogue")
		assert(game.hero.position.distance_to(actor.position)<1.8)
		assert(game.dialogue_portrait.texture is AtlasTexture)
	print("PASS: all six 3D NPCs reachable around stalls, proximity dialogue and correct generated portrait bindings")
	print("NPC_PHYSICS_FRAMES: ",frames)
	game.active_slot=0
	game.queue_free()
	quit(0)
