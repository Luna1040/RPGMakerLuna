extends SceneTree
var failures: Array[String]=[]
var checks:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message); push_error(message)
func key(game, code: int) -> void:
	var event:=InputEventKey.new()
	event.pressed=true; event.keycode=code
	game._unhandled_key_input(event)
func run() -> void:
	var game=load("res://main.tscn").instantiate()
	game.save_enabled=false
	game.save_path="user://starlight-test-only.json"
	DirAccess.remove_absolute(game.save_path)
	root.add_child(game)
	game.set_process(false)
	check(game.mode=="dock" and game.gates==0,"Fresh profile starts docked")
	key(game,KEY_TAB)
	check(game.selected_sector==0,"Locked sectors cannot be selected")
	key(game,KEY_E)
	check(game.mode=="flight" and game.stars.size()==37,"Launch input populates sector")
	var start: Vector2=game.player
	Input.action_press("ui_right"); game._process(.05); Input.action_release("ui_right")
	check(game.player.x>start.x,"Actual movement input works")
	game.hazards.clear()
	game.stars.clear(); game.stars.append_array([{"p":game.player,"core":false,"value":1,"phase":0.0}])
	game.step_flight(.01,Vector2.ZERO)
	check(game.cargo==1 and game.stars.is_empty(),"Pickups add cargo")
	game.cargo=game.capacity()
	game.stars.clear(); game.stars.append_array([{"p":game.player,"core":false,"value":1,"phase":0.0},{"p":game.player,"core":true,"value":0,"phase":0.0}])
	game.step_flight(.01,Vector2.ZERO)
	check(game.cargo==game.capacity() and game.cargo_cores==1 and game.stars.size()==1,"Full hold still collects cores without overflow")
	game.player=Vector2(500,400); key(game,KEY_E)
	check(game.mode=="flight" and game.bank==0,"Cannot remotely bank cargo")
	game.player=game.HOME; key(game,KEY_E)
	check(game.mode=="dock" and game.bank==18 and game.cores==1,"Dock interaction banks both resources")
	game.bank_cargo()
	check(game.bank==18,"Settlement cannot be repeated")
	check(not game.buy(0) and game.bank==18,"Insufficient funds cannot upgrade")
	game.bank=100
	key(game,KEY_1)
	check(game.capacity()==26 and game.bank==78,"Upgrade changes actual capacity and deducts cost")
	check(game.repair_gate() and game.gates==1 and game.unlocked()==1 and game.cores==0,"Gate unlock spends both resources")
	game.selected_sector=1; key(game,KEY_E)
	check(game.sector==1 and game.hazards.size()==7,"New sector has greater danger")
	var before: float=game.energy
	key(game,KEY_SPACE)
	check(game.dash_left>0 and game.energy==before-8,"Dash input spends energy")
	before=game.energy; key(game,KEY_SPACE)
	check(game.energy==before,"Dash cooldown blocks repeated casts")
	key(game,KEY_Q); check(game.scan_left>0 and game.scan_cd>0,"Scan reveals core routes")
	game.cargo=13; game.cargo_cores=2; game.energy=.001
	var bank_before: int=game.bank
	game.step_flight(.05,Vector2.ZERO)
	check(game.mode=="dock" and game.bank==bank_before+6 and game.cores==0,"Failure retains half cargo and loses only carried cores")
	game.bank=1000; game.cores=20
	check(game.repair_gate() and game.repair_gate() and game.gates==3,"Full campaign progression reaches final gate")
	bank_before=game.bank
	check(not game.repair_gate() and game.bank==bank_before,"Final gate reward is not repeatable")
	game.selected_sector=1; game.launch(); game.hazards.clear(); game.stars.clear()
	game.player=Vector2(650,440)
	before=game.energy; game.step_flight(1.0,Vector2.ZERO)
	check(is_equal_approx(before-game.energy,3.22),"Ion cloud has extra energy drain")
	game.bank_cargo(); game.selected_sector=2; game.launch(); game.hazards.clear(); game.stars.clear()
	game.player=Vector2(600,440); game.flight_time=5
	game.step_flight(.01,Vector2.ZERO)
	check(game.hull==3,"Solar warning does not damage early")
	game.flight_time=7; game.step_flight(.01,Vector2.ZERO)
	check(game.hull==2,"Solar eruption damages inside danger lane")
	game.hit_cd=0; game.trigger_dash(); game.step_flight(.01,Vector2.ZERO)
	check(game.hull==2,"Dash avoids solar damage")
	game.bank_cargo()
	bank_before=game.bank
	game.save_enabled=true
	check(game.save_progress(),"Save writes atomically")
	game.bank=0
	check(game.load_progress() and game.bank==bank_before and game.levels[0]==1 and game.gates==3,"Progress survives save/load")
	check(game.save_progress(),"Existing save can be replaced")
	var file:=FileAccess.open(game.save_path,FileAccess.WRITE); file.store_string("{bad"); file.close()
	check(not game.load_progress() and game.bank==bank_before,"Corrupt save does not mutate progress")
	DirAccess.remove_absolute(game.save_path)
	var source:=FileAccess.get_file_as_string("res://main.gd")
	var missing:=0
	for character in source:
		var code:=character.unicode_at(0)
		if code>=0x4e00 and code<=0x9fff and not game.ui_font.has_char(code): missing+=1
	check(missing==0,"Font covers all Chinese UI text")
	check(root.get_node("GameAssistant").home_button!=null,"Lobby navigation retained")
	game.queue_free()
	await process_frame
	print("STARLIGHT TEST ","PASS" if failures.is_empty() else "FAIL"," checks=",checks)
	quit(0 if failures.is_empty() else 1)
