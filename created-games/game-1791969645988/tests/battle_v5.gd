extends SceneTree
var failures:=0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures+=1
		push_error(label)
func fixture(game) -> void:
	game.character={"name":"战斗测试","profession":"剑仙","level":7,"xp":0,"hp":170,"stones":10,"victories":0,"created_at":game.store.timestamp(),"logged_out_at":"","quest":5,"field_quest":2,"cleared":[],"zone":"field","position":[400,500],"progression_version":2}
	game.slot=0
	game.player_pos=Vector2(400,500)
	game.show_world()
func finish_normal(game) -> void:
	for i in range(1000):
		if game.mode!="battle": break
		game.advance_battle(0.1)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game=load("res://main.tscn").instantiate()
	game.store.directory="res://tests/battle-v5-saves"
	root.add_child(game)
	await process_frame
	fixture(game)
	var low=game.encounter_rewards(5,1)
	var high=game.encounter_rewards(9,1)
	var dungeon=game.encounter_rewards(5,1,"dungeon")
	check(low.xp==20 and low.stones==10,"small per-wild-monster reward")
	check(high.xp>low.xp and high.stones>low.stones,"rewards scale with level")
	check(dungeon.xp==low.xp*5 and dungeon.stones==low.stones*5,"future dungeon reward policy")
	check(game.encounter_rewards(5,0).xp==0,"no kills no reward")
	game.start_battle(1)
	check(game.screen.get_node("QuickBattle").text=="快速战斗","top right quick combat")
	check(not game.actions.sword.is_empty() and not game.actions.bite.is_empty(),"generated attacks loaded")
	var base_texture=game.battle_player.get_node("Portrait").texture
	game.advance_battle(0.22)
	check(game.battle_player.position.x>600,"player dashes across arena")
	game.advance_battle(0.2)
	check(game.battle_player.get_node("Portrait").texture!=base_texture,"generated sword pose replaces idle")
	check(game.enemy_hp==game.max_enemy_hp,"no damage before hit event")
	game.advance_battle(0.2)
	check(game.enemy_hp<game.max_enemy_hp,"one impact applies damage")
	var after_player_hit=game.enemy_hp
	check(game.player_hit_done,"impact tracked once")
	game.resolve_player_hit(true)
	check(game.enemy_hp==after_player_hit,"no double hit")
	var number=null
	for child in game.battle_effects.get_children():
		if child is Label: number=child
	check(number!=null,"damage text spawned")
	if number!=null:
		number.set_process(false)
		number._process(1.0)
		check(is_equal_approx(number.modulate.a,1.0),"damage text holds one second")
		number._process(0.175)
		check(number.modulate.a>0 and number.modulate.a<1,"damage text fades after hold")
		number._process(0.175)
		check(number.is_queued_for_deletion(),"damage text removed after fade")
	finish_normal(game)
	check(game.mode=="result" and game.enemy_hp==0,"normal animated battle settles")
	var expected={"stones":game.character.stones,"xp":game.character.xp,"level":game.character.level,"hp":game.character.hp,"combat_hp":game.combat_hp,"rounds":game.round_number}
	game.return_from_battle()
	check(game.player_pos==Vector2(400,500),"battle returns to original map position")
	fixture(game)
	game.start_battle(1)
	game.quick_button.pressed.emit()
	check(game.mode=="result","quick button settles immediately")
	check(game.character.stones==expected.stones and game.character.xp==expected.xp and game.character.hp==expected.hp and game.round_number==expected.rounds,"normal and quick outcomes identical")
	var reward_stones=int(game.character.stones)
	game.quick_battle()
	game.settle_battle()
	check(game.character.stones==reward_stones,"quick click and repeated settlement cannot duplicate rewards")
	check(game.battle_log.text.begins_with("快速战斗结束"),"quick mode shows summary only")
	fixture(game)
	game.start_battle(1)
	game.advance_battle(0.65)
	check(game.player_hit_done and not game.enemy_hit_done,"partially animated round")
	game.quick_battle()
	check(game.character.stones==expected.stones and game.combat_hp==expected.combat_hp and game.round_number==expected.rounds,"skip mid round never repeats applied hit")
	fixture(game)
	game.character.hp=1
	game.start_battle(2)
	game.quick_battle()
	check(game.mode=="result" and game.enemy_hp>0,"quick defeat also resolves")
	check(game.character.stones==10 and game.character.cleared.is_empty(),"defeat grants no rewards")
	fixture(game)
	game.character.hp=1
	game.start_battle(2)
	game.advance_battle(2.3)
	check(game.phase==6 and game.combat_hp==0,"defeat awaits final damage fade")
	var final_enemy_hp=game.enemy_hp
	var final_round=game.round_number
	game.quick_battle()
	check(game.enemy_hp==final_enemy_hp and game.round_number==final_round,"skip after defeat cannot grant dead player another attack")
	game.store.delete_slot(0)
	game.character={}
	print("BATTLE TEST: ","PASS" if failures==0 else "FAIL"," (",failures," failures)")
	quit(0 if failures==0 else 1)
