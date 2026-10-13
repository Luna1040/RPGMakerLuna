extends SceneTree
var failures:Array[String]=[]
var checks:=0
var stage
var runtime
var temp_path:=""

func check(ok: bool, why: String) -> void:
	checks+=1
	if not ok: failures.append(why); push_error(why)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	stage=load("res://stage.gd").new()
	root.add_child(stage)
	stage.set_physics_process(false)
	stage.testing_motion=true
	runtime=stage.runtime
	check(runtime!=null,"--foundations must enable complete runtime in test")
	if runtime==null: quit(1); return
	runtime.persistence_enabled=false
	temp_path="user://foundation_runtime_tests_"+str(Time.get_ticks_usec())
	runtime.saves=load("res://systems/core/save_store.gd").new(temp_path)
	runtime.autosave_armed=false
	check(not runtime.save_game(1,true),"Fresh character must not autosave into an unselected slot")
	var data:Dictionary=runtime.snapshot()
	check(runtime.validate_snapshot(data),"Fresh runtime snapshot invalid")
	for tab in ["adventure","journal","network","trade","saves","settings"]:
		runtime.panel.open(tab)
		check(stage.interface.is_modal(),"Panel must acquire world modal: "+tab)
		check(runtime.panel.body.get_child_count()>0,"Panel empty: "+tab)
	runtime.panel.close()
	stage.knight.health=41
	stage.knight.mana=32
	stage.knight.equipment.equip("arcane_sword")
	stage.loot.damage_crate("box-a",100)
	stage.loot._process(.4)
	stage.loot.interact(Vector2(8.4,6.1),0)
	stage.loot.interact(Vector2(11.8,6.8),0)
	data=runtime.snapshot()
	check(runtime.save_game(1),"Save runtime with gear, crates, materials and unpicked chest loot")
	var material_count:int=stage.loot.materials["木料"]
	var drop_count:int=stage.loot.drops.size()
	stage.loot.materials["木料"]=0
	stage.knight.health=99
	stage.knight.equipment.equip("knight_sword")
	check(runtime.load_game(1),"Load actual runtime save")
	check(stage.knight.equipment.equipped.weapon=="arcane_sword","Equipment restore")
	check(is_equal_approx(stage.knight.health,41),"Health restore")
	check(stage.loot.materials["木料"]==material_count,"Materials restore")
	check(not stage.loot.crates.has("box-a"),"Broken crate resurrected")
	check(stage.loot.drops.size()==drop_count,"Ground drops not restored")
	check(stage.loot.chests[0].opened,"Opened chest restore")
	check(runtime.load_game(1) and stage.loot.drops.size()==drop_count,"Loading twice duplicates loot")
	var malformed:Array[Dictionary]=[]
	var candidate:Dictionary=data.duplicate(true)
	candidate.equipment.equipped["bonus_slot"]="arcane_sword"; malformed.append(candidate)
	candidate=data.duplicate(true); candidate.equipment.equipped.erase("boots"); malformed.append(candidate)
	candidate=data.duplicate(true); candidate.equipment.owned.append(candidate.equipment.owned[0]); malformed.append(candidate)
	candidate=data.duplicate(true); candidate.player.foot=[INF,4]; malformed.append(candidate)
	candidate=data.duplicate(true); candidate.player.health="x"; malformed.append(candidate)
	candidate=data.duplicate(true); candidate.run.seed={}; malformed.append(candidate)
	candidate=data.duplicate(true); candidate.schema={}; malformed.append(candidate)
	candidate=data.duplicate(true); candidate.materials["木料"]=-1; malformed.append(candidate)
	candidate=data.duplicate(true); candidate.worlds.town.drops[0].amount=-5; malformed.append(candidate)
	var before:=JSON.stringify(runtime.snapshot())
	for bad in malformed:
		check(not runtime.restore(bad),"Malformed runtime payload accepted")
		check(JSON.stringify(runtime.snapshot())==before,"Rejected load mutated active game")
	check(runtime.saves.save_slot(2,malformed[0]),"Fixture valid envelope with invalid gameplay")
	check(not runtime.load_game(2),"Invalid semantic load accepted")
	check(not runtime.saves.save_slot(2,data),"Failed semantic load must protect source slot")
	runtime.progression.add_xp(200)
	runtime.refresh_bonuses()
	var base_damage:float=stage.knight.get_attack_damage("attack1")
	check(runtime.talents.spend("blade_training",runtime.progression),"Spend earned point")
	check(is_equal_approx(stage.knight.get_attack_damage("attack1"),base_damage+3),"Talent not applied to real hit damage")
	check(runtime.validate_snapshot(runtime.snapshot()),"Spent talent snapshot invalid")
	check(not runtime.talents.spend("execution",runtime.progression),"Prerequisite skipped")
	var health:float=stage.knight.health
	var mana:float=stage.knight.mana
	runtime.panel.open("adventure")
	stage.test_input=Vector2.RIGHT
	var foot:Vector2=stage.foot
	stage._physics_process(1.0)
	check(stage.foot==foot and stage.knight.health==health and stage.knight.mana==mana,"World moves or resources advance behind modal")
	runtime.panel.close()
	var original_key:int=runtime.controls.keys.attack
	check(runtime.controls.rebind("attack",KEY_V),"Valid key rebinding failed")
	check(not runtime.controls.rebind("spell",KEY_V),"Duplicate key accepted")
	var key:=InputEventKey.new(); key.keycode=KEY_V; key.pressed=true
	check(runtime.controls.canonical(key)==KEY_J,"Remap did not map new key")
	key.keycode=KEY_J
	check(runtime.controls.canonical(key)==0,"Original unassigned attack still active")
	runtime.controls.keys.attack=original_key
	check(not runtime.start_wave(),"Cannot start wave in town")
	runtime.zone="ruins"
	runtime.run_state={"phase":"boon","wave":1,"seed":123,"boons":[],"offers":["edge","ward","arcane"]}
	check(not runtime.choose_boon("fleet"),"Unlisted boon accepted")
	check(runtime.choose_boon("edge"),"Valid boon rejected")
	check(not runtime.choose_boon("edge") and runtime.run_state.boons.size()==1,"Boon can be claimed twice")
	check(stage.knight.run_bonuses.attack==8,"Boon does not affect real stats")
	var transfer:Dictionary=runtime.prepare_transfer("town")
	check(transfer.zone=="town" and transfer.worlds.has("ruins") and transfer.worlds.has("town"),"World state not kept separately on travel")
	check(runtime.validate_snapshot(transfer),"Scene handoff snapshot invalid")
	stage.queue_free()
	await process_frame
	await process_frame
	# Delete only files created in this unique test-owned directory.
	var directory:=DirAccess.open(temp_path)
	if directory!=null:
		for name in directory.get_files(): directory.remove(name)
		DirAccess.remove_absolute(temp_path)
	print("RUNTIME_FOUNDATIONS_TEST ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
