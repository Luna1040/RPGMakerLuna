extends SceneTree
const S=preload("res://spell_system.gd")
const E=preload("res://estate_system.gd")
const G=preload("res://equipment_system.gd")
var failures:=0
func check(ok: bool, label: String) -> void:
	if not ok: failures+=1; push_error(label)
func fixture(profession: String) -> Dictionary:
	var c: Dictionary={"profession":profession,"realm":"练气期","level":10,"xp":0,"loot_seed":12345}
	G.normalize(c); E.normalize(c); S.normalize(c); return c
func _initialize() -> void: call_deferred("run")
func run() -> void:
	check(S.DATA.size()==16,"sixteen distinct spells")
	for profession in S.CLASSES:
		var c:=fixture(profession)
		var ids:=S.ids(c)
		check(ids.size()==4,"four spells for each profession")
		var qi:=0; var foundation:=0
		for id in ids:
			if int(S.DATA[id].realm)==0: qi+=1
			else: foundation+=1
		check(qi==2 and foundation==2,"two spells per realm")
		var id: String=ids[0]
		check(not S.learn(c,id),"manual required")
		E.put(c.inventory,S.manual(id,55))
		for rank in range(1,11):
			check(S.cost(c,id)==rank and S.learn(c,id) and c.spells[id]==rank,"increasing same-name manual costs")
		check(E.count(c.inventory,"spell_manual",id)==0 and not S.learn(c,id),"fifty five total manuals and max ten")
		E.put(c.inventory,S.manual(ids[2],1))
		check(not S.learn(c,ids[2]),"foundation realm required")
		c.realm="筑基期"; check(S.learn(c,ids[2]),"foundation unlocks own spells")
		var foreign: String=S.DATA.keys()[4] if profession=="剑仙" else "sword_q1"
		E.put(c.inventory,S.manual(foreign,1)); check(not S.learn(c,foreign),"cannot learn another profession")
	var mortal:=fixture(S.CLASSES[0]); mortal.realm="\u51e1\u4eba"
	check(not S.permitted(mortal,"sword_q1"),"qi spell requires qi realm")
	var sample:=fixture("剑仙"); var drops:=S.drop_wild(sample,10000)
	check(drops.size()>1300 and drops.size()<1700,"wild manual drop sampling near fifteen percent")
	for item in drops: check(S.DATA[item.id]["class"]=="剑仙" and int(S.DATA[item.id].realm)==0,"useful profession manuals at qi")
	var same:=fixture("剑仙"); var another:=same.duplicate(true)
	check(S.drop_wild(same,100)==S.drop_wild(another,100),"saved RNG deterministic")
	var game=load("res://main.tscn").instantiate(); game.store.directory="res://tests/spells-v14-saves"; root.add_child(game); await process_frame
	game.create_character(0); game.name_input.text="仙法测试"; game.finish_creation()
	game.character.level=20; game.character.realm="练气期"; game.character.quest=5; game.character.field_quest=2; game.character.sect_quest=2; game.character.zone="sect"; game.show_world()
	game.player_pos=game.SECT_POS[0]+game.NPC_APPROACH; game.talk(0)
	check(is_instance_valid(game.modal),"elder foundation guide opens")
	game.advance_foundation(1); game.advance_foundation(2)
	check(game.character.foundation_quest==2,"level twenty stage handed in")
	game.advance_foundation(3); check(game.character.foundation_quest==2,"pill preparation needed")
	E.put(game.character.inventory,E.stack("breakthrough_pill","foundation","筑基丹",1))
	game.advance_foundation(3); check(game.character.foundation_quest==3,"pill preparation stage")
	game.advance_foundation(4); check(game.character.foundation_quest==3,"foundation breakthrough required")
	game.character.realm="筑基期"; game.character.foundation_established=true
	game.advance_foundation(4); var stones:=int(game.character.stones)
	game.advance_foundation(4); check(game.character.foundation_quest==4 and game.character.stones==stones,"foundation hand-in reward once")
	check(game.get_task_groups()["已完成任务"].size()>=3,"foundation tasks in journal")
	E.put(game.character.inventory,S.manual("sword_q1",3))
	game.toggle_menu(5); game.spell_ui.learn("sword_q1")
	check(game.MENU_NAMES[5]=="仙法" and game.character.spells.sword_q1==1,"spell menu learns")
	game.spell_ui.learn("sword_q1"); check(game.character.spells.sword_q1==2,"spell menu upgrades with same manual")
	for frame in range(4): await process_frame
	check(game.menu_window.get_global_rect().end.y<=712,"spell menu fits viewport")
	for child in game.menu_window.get_node("Content").get_children():
		if child is Control: check(child.get_global_rect().end.y<=game.menu_window.get_global_rect().end.y+1,"spell controls fit")
	var store_directory: String=game.store.directory
	var before_failure: Dictionary=game.character.duplicate(true)
	E.put(game.character.inventory,S.manual("sword_q1",3))
	before_failure=game.character.duplicate(true)
	game.store.directory="res://main.gd/invalid-save"
	game.spell_ui.learn("sword_q1")
	check(game.character.spells==before_failure.spells and game.character.inventory==before_failure.inventory,"save failure rolls back manual consumption and level")
	game.store.directory=store_directory
	for profession in S.CLASSES:
		game.close_menu(); game.character.profession=profession; game.character.zone="field"; game.character.cleared=[]; game.character.monster_respawns={}; game.show_world()
		var portrait: Sprite2D=game.avatar.get_node("Portrait")
		check(not portrait.centered and portrait.texture.get_width()==768,"class map portrait and foot anchor")
		var texture=portrait.texture
		game.start_battle(2)
		check(hash(game.battle_player.get_node("Portrait").texture.get_image().get_data())==hash(texture.get_image().get_data()),"battle keeps selected class portrait")
		game.advance_battle(0.9)
		game.reset_battle_poses()
		check(not game.battle_player.get_node("Portrait").centered,"battle restoration keeps class foot anchor")
		if profession!=S.CLASSES[0]: check(game.actions.sword.is_empty(),"unapproved attack cannot replace profession identity")
		game.quick_battle(); game.return_from_battle(); game.character.cleared=[]; game.character.monster_respawns={}
	game.character.profession=S.CLASSES[0]
	game.close_menu(); game.character.zone="field"; game.character.cleared=[]; game.character.monster_respawns={}; game.character.hp=80; game.show_world()
	var saved: Dictionary=game.character.duplicate(true)
	game.start_battle(2); game.quick_battle(); var quick: Dictionary=game.character.duplicate(true)
	game.return_from_battle(); game.character=saved.duplicate(true); game.show_world(); game.start_battle(2)
	for tick in range(1600):
		if game.mode!="battle": break
		game.advance_battle(0.1)
	check(game.character.hp==quick.hp and game.character.spells==quick.spells and game.character.inventory==quick.inventory,"normal and quick same learned-spell results and drops")
	game.return_from_battle(); game.persist(); var spells=game.character.spells.duplicate(true); game.logout(); game.enter_character(0)
	check(game.character.spells==spells and game.character.foundation_quest==4,"spells and quest save roundtrip")
	game.store.delete_slot(0); game.character={}
	print("SPELL TEST: ","PASS" if failures==0 else "FAIL"," (",failures," failures)")
	quit(0 if failures==0 else 1)
