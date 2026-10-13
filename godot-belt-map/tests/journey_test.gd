extends SceneTree
var failures:Array[String]=[]
var stage
var runtime

func _initialize() -> void:
	call_deferred("run")

func check(value:bool, message:String) -> void:
	if not value:
		failures.append(message)
		print("CHECK_FAIL ",message)

func adopt() -> void:
	stage=current_scene
	runtime=stage.runtime
	runtime.persistence_enabled=false
	stage.set_physics_process(false)

func settle() -> void:
	for i in 6: await process_frame
	adopt()

func key(code:int, echo:bool=false) -> void:
	var event:=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=true
	event.echo=echo
	Input.parse_input_event(event)
	await process_frame
	event=event.duplicate()
	event.pressed=false
	event.echo=false
	Input.parse_input_event(event)
	await process_frame

func capture(name:String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures/journey")
	root.get_texture().get_image().save_png("res://captures/journey/"+name+".png")

func run() -> void:
	stage=load("res://stage.tscn").instantiate()
	root.add_child(stage)
	current_scene=stage
	adopt()
	check(runtime.portals.links.size()==3,"Town must expose west dungeon, east dungeon and next-city gate")
	var gate:Dictionary=runtime.portals.links[2]
	check(runtime.portals.locked(gate),"New character cannot skip the city quest gate")
	check(not runtime.use_portal(gate),"Gate must be checked by runtime, not only label")
	for resident in stage.townsfolk.residents:
		if resident.id=="smith": runtime.open_npc(resident)
	var view=runtime.panel.dialogue_view
	check(view.visible and not runtime.panel.menu_root.visible,"Conversation must replace the old menu")
	check(view.right.modulate.r>view.left.modulate.r,"NPC starts highlighted")
	await key(KEY_SPACE)
	check(view.index==0,"First space reveals text without skipping the line")
	await key(KEY_SPACE,true)
	check(view.index==0,"Held space cannot skip dialogue")
	await key(KEY_SPACE)
	check(view.index==1 and view.left.modulate.r>view.right.modulate.r,"Next line highlights the hero")
	check(stage.height_z==0 and stage.knight.state!="jump","Dialogue space cannot jump")
	view.advance()
	await capture("dialogue-hero")
	while not view.at_choices: view.advance()
	view.select_topic("menace_order")
	check(runtime.adventure._status("courtyard_menace")=="available","Reading a topic does not accept a quest")
	await key(KEY_ESCAPE)
	check(not runtime.panel.is_open() and runtime.adventure._status("courtyard_menace")=="available","Cancel leaves quests unchanged")
	for resident in stage.townsfolk.residents:
		if resident.id=="smith": runtime.open_npc(resident)
	view.select_topic("menace_order")
	while not view.at_choices: view.advance()
	view.choices.get_child(0).pressed.emit()
	check(runtime.adventure._status("courtyard_menace")=="active","Confirm button must accept through adventure service")
	runtime.panel.close()
	stage.foot=Vector2(2.4,7.4)
	stage.foot_node.position=stage.project(stage.foot)
	stage.camera.position.x=640
	await capture("west-portal")
	check(runtime.portals.nearby().get("id")=="town_west","West exit must be reachable")
	check(runtime.use_portal(runtime.portals.links[0]),"West portal must start forest route")
	await settle()
	check(runtime.zone=="forest" and runtime.encounters.active,"Portal dungeon starts wave automatically")
	check(not runtime.panel.is_open(),"Portal arrival must not ask players to find another menu")
	check(not runtime.use_portal(runtime.portals.links[0]),"Active battle seals exit")
	var enemies:Array=runtime.encounters.enemies.duplicate()
	for enemy in enemies:
		runtime.encounters.hit(enemy.foot,0,{"damage":9999,"range":500,"shape":"radial","depth_radius":10.0})
	runtime.encounters.step(.01)
	check(runtime.run_state.phase=="victory","Forest ends after its single beginner wave")
	check(runtime.adventure._status("courtyard_menace")=="ready","Real forest kills complete the accepted quest")
	check(runtime.use_portal(runtime.portals.links[0]),"Cleared forest permits return")
	await settle()
	check(runtime.zone=="town","Forest exit returns to courtyard")
	check(runtime.adventure.claim_quest("courtyard_menace").ok,"Return trip preserves quest completion and rewards")
	check(not runtime.portals.locked(runtime.portals.links[2]),"Hand-in unlocks next town")
	check(runtime.use_portal(runtime.portals.links[2]),"Unlocked gate travels to city")
	await settle()
	check(runtime.zone=="city" and runtime.validate_snapshot(runtime.snapshot()),"New city must be a valid persistent zone")
	await capture("next-city")
	check(runtime.use_portal(runtime.portals.links[1]),"City east gate enters ancient tower")
	await settle()
	check(runtime.zone=="ruins" and runtime.encounters.active,"Tower entry from city starts combat")
	check(runtime.run_state.get("return_zone","")=="city","Dungeon remembers originating city")
	check(runtime.return_town(),"Retreat route is available")
	await settle()
	check(runtime.zone=="city","Retreat must return to the originating city")
	check(runtime.use_portal(runtime.portals.links[0]),"City west road returns to courtyard")
	await settle()
	check(runtime.zone=="town" and runtime.adventure._status("courtyard_menace")=="claimed","Round trip preserves quest receipt")
	for failure in failures: push_error(failure)
	print("JOURNEY_TEST ","PASS" if failures.is_empty() else "FAIL")
	stage.queue_free()
	await process_frame
	await create_timer(.15).timeout
	quit(0 if failures.is_empty() else 1)
