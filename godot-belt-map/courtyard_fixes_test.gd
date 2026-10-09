extends SceneTree
const Physics=preload("belt_physics.gd")
var failures: Array[String]=[]
func check(ok: bool, text: String) -> void:
	if not ok: failures.append(text)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var stage=load("res://stage.gd").new()
	root.add_child(stage)
	stage.set_physics_process(false)
	stage.testing_motion=true
	for npc: Dictionary in stage.townsfolk.residents:
		var p: Vector2=npc.position
		check(Physics.blocked(stage.volumes,p,0),"NPC has no ground collision")
		check(Physics.blocked(stage.volumes,p,Physics.JUMP_RISE),"Normal jump passes through NPC torso")
		var stopped:=Physics.step_position(stage.volumes,stage.bounds,p-Vector2(1.2,0),Vector2(2.4,0),0,true)
		check(stopped.x<p.x-.45,"Swept movement crosses NPC")
		check(not stage.townsfolk.nearest(p-Vector2(.7,0),0).is_empty(),"NPC collision prevents dialogue approach")
	stage.foot=Vector2(4.0,4.1)
	stage.knight.request_dash_attack()
	for i in 70: stage._physics_process(1.0/120)
	check(stage.foot.x<4.71,"Real dash crosses innkeeper")
	stage.knight.reset_character()
	stage.height_z=0
	stage.grounded=true
	var q:=InputEventKey.new()
	q.keycode=KEY_Q
	q.pressed=true
	stage.loot.interact(Vector2(11.8,6.8),0)
	stage.loot._process(.3)
	stage.foot=Vector2(11.58,7.25)
	stage._unhandled_key_input(q)
	check(stage.knight.equipment.equipped.weapon=="courtyard_blade","Real Q did not equip ground weapon")
	check(stage.knight.get_attack_damage("attack1")==34,"Q weapon bonus did not reach character")
	stage.foot=Vector2(12.02,7.25)
	stage._unhandled_key_input(q)
	check(stage.knight.equipment.equipped.armor=="courtyard_mail","Second Q did not equip ground armor")
	stage.loot.interact(Vector2(22.2,4.8),0)
	stage.loot._process(.3)
	stage.foot=Vector2(21.98,5.25)
	stage._unhandled_key_input(q)
	check(stage.knight.equipment.equipped.charm=="courtyard_charm","Q did not equip ground necklace")
	check(Physics.blocked(stage.volumes,Vector2(16.15,5.0),1.3),"Fountain column has no airborne collision")
	check(not Physics.support(stage.volumes,Vector2(16.15,4.8)).valid,"Fountain basin incorrectly supports standing")
	var backdrop: Node=stage.get_node("CourtyardBackdrop")
	check(backdrop.get_child_count()>=4,"Background lacks repeated panels")
	for tile: Sprite2D in backdrop.get_children():
		check(is_equal_approx(tile.scale.x,tile.scale.y),"Background panel has unequal x/y scale")
	for error in failures: push_error(error)
	print("COURTYARD_FIXES_TEST ","PASS" if failures.is_empty() else "FAIL"," · NPC solid/swept dash, ground Q weapon/armor/necklace, stats, fountain, uniform backdrop tiles")
	quit(0 if failures.is_empty() else 1)
