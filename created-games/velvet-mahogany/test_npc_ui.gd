extends SceneTree
var count:=0
var failed:=false
func check(ok: bool, what: String) -> void:
	count+=1
	if not ok: failed=true; push_error("FAIL: "+what)
func _initialize() -> void:
	root.size=Vector2i(1280,720)
	seed(731432)
	call_deferred("run")
func click(point: Vector2) -> void:
	var move:=InputEventMouseMotion.new()
	move.position=point; move.global_position=point
	root.push_input(move,true)
	await process_frame
	var e:=InputEventMouseButton.new()
	e.position=point; e.global_position=point; e.button_index=MOUSE_BUTTON_LEFT; e.pressed=true
	root.push_input(e,true)
	await process_frame
	e=InputEventMouseButton.new()
	e.position=point; e.global_position=point; e.button_index=MOUSE_BUTTON_LEFT; e.pressed=false
	root.push_input(e,true)
	await process_frame
func wait_game(g: Node) -> void:
	var deadline:=Time.get_ticks_msec()+30000
	while g.busy and Time.get_ticks_msec()<deadline: await create_timer(0.02).timeout
	check(not g.busy,"NPC returns control")
	await process_frame
func shot(name: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/npc-"+name+".png")
func run() -> void:
	var g=load("res://multiplayer.tscn").instantiate()
	root.add_child(g); current_scene=g
	g.npc_delay=0.02
	await process_frame
	check(g.poker.stacks.size()==6,"six seated players")
	await shot("lobby")
	await click(Vector2(410,664))
	await wait_game(g)
	check(g.poker.active and g.poker.actor==0,"holdem dealt to human turn")
	check(g.poker.holes[1].size()==2 and not g.poker.show_cards,"NPC hole cards hidden")
	await shot("holdem")
	var guard:=0
	while g.poker.active and guard<30:
		guard+=1
		await click(Vector2(500,665))
		await wait_game(g)
		if g.poker.board.size()==3: await shot("flop")
	check(not g.poker.active,"holdem mouse call through settlement")
	check(g.poker.stacks.reduce(func(a,b):return a+b,0)==6000,"holdem UI preserves chips")
	await shot("holdem-result")
	await click(Vector2(140,254))
	check(g.mode=="doudizhu","switch to doudizhu")
	await click(Vector2(410,664))
	await wait_game(g)
	check(g.ddz.phase=="bid" and g.ddz.hands[0].size()==17,"17 cards before landlord")
	await shot("bid")
	await click(Vector2(715,666))
	await wait_game(g)
	check(g.ddz.landlord==0 and g.ddz.hands[0].size()==20,"landlord gets bottom cards")
	await click(Vector2(348,578))
	check(g.selected.size()==1,"click selects a hand card")
	await click(Vector2(792,665))
	check(g.selected.is_empty(),"clear selected hand")
	await shot("doudizhu")
	guard=0
	while g.ddz.phase=="play" and guard<150:
		guard+=1
		await click(Vector2(648,665))
		if g.selected.is_empty(): await click(Vector2(520,665))
		else: await click(Vector2(389,665))
		await wait_game(g)
	check(g.ddz.phase=="done","DDZ mouse game reaches winner")
	check(g.ddz.scores.reduce(func(a,b):return a+b,0)==0,"DDZ scores conserved")
	await shot("doudizhu-result")
	print("PASS: " if not failed else "FAIL: ",count," NPC UI checks")
	quit(1 if failed else 0)
