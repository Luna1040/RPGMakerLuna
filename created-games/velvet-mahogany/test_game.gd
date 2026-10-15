extends SceneTree
const R = preload("res://rules.gd")
var checks := 0
func check(value: bool, what: String) -> void:
	checks+=1
	if not value:
		push_error("FAIL: "+what)
		quit(1)
func _initialize() -> void:
	root.size=Vector2i(1280,720)
	call_deferred("run")
func click_at(point: Vector2) -> void:
	var e:=InputEventMouseButton.new()
	e.position=point
	e.global_position=point
	e.button_index=MOUSE_BUTTON_LEFT
	e.pressed=true
	root.push_input(e, true)
	await process_frame
	e=InputEventMouseButton.new()
	e.position=point
	e.global_position=point
	e.button_index=MOUSE_BUTTON_LEFT
	e.pressed=false
	root.push_input(e, true)
	await process_frame
func wait_idle(game: Node) -> void:
	while game.busy: await create_timer(0.1).timeout
	await process_frame
func shot(file: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/"+file+".png")
func run() -> void:
	check(R.blackjack([0,13,9])==12,"multiple aces")
	check(R.blackjack([0,12])==21,"natural blackjack")
	check(R.baccarat([8,7,12])==7,"baccarat modulo")
	check(not R.banker_draw(3,8),"banker 3 vs 8 stands")
	check(R.banker_draw(6,7),"banker 6 vs 7 draws")
	check(not R.banker_draw(6,5),"banker 6 vs 5 stands")
	check(R.banker_draw(5,-1),"banker 5 without third draws")
	check(R.poker([0,9,10,11,12]).pay==250,"royal flush")
	check(R.poker([0,1,2,3,4]).pay==50,"wheel flush")
	check(R.poker([0,14,28,42,4]).pay==4,"wheel straight")
	check(R.poker([10,23,36,49,0]).pay==25,"four of a kind")
	check(R.poker([0,13,26,1,14]).pay==9,"full house")
	check(R.poker([10,23,2,17,33]).pay==1,"jacks pair")
	check(R.poker([8,21,2,17,33]).pay==0,"low pair loses")
	check(R.deck().size()==52,"single deck")
	check(R.deck(8).size()==416,"eight decks")
	var game=load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await process_frame
	game.reset_bank()
	await process_frame
	await shot("01-table")
	await click_at(Vector2(410,668))
	await wait_idle(game)
	check(game.player.size()>=2,"mouse deal blackjack")
	if game.active:
		await click_at(Vector2(514,668))
		await wait_idle(game)
	check(not game.active and game.rounds==1,"blackjack settlement")
	await shot("02-blackjack")
	await click_at(Vector2(135,256))
	check(game.mode==1,"mouse baccarat tab")
	await click_at(Vector2(410,668))
	await wait_idle(game)
	check(not game.active and game.rounds==2,"baccarat settlement")
	check(game.player.size() in [2,3] and game.dealer.size() in [2,3],"baccarat cards")
	await shot("03-baccarat")
	await click_at(Vector2(135,313))
	check(game.mode==2,"mouse poker tab")
	await click_at(Vector2(410,668))
	await wait_idle(game)
	check(game.active and game.player.size()==5,"poker dealt")
	var first=game.player[0]
	await click_at(Vector2(573,495))
	check(game.held.has(0),"mouse hold card")
	await shot("04-hold")
	await click_at(Vector2(410,668))
	await wait_idle(game)
	check(not game.active and game.player[0]==first,"held card preserved")
	check(game.rounds==3,"poker settlement")
	var unique={}
	for c in game.player: unique[c]=true
	check(unique.size()==5,"no duplicate poker cards")
	game.load_progress()
	check(game.rounds==3,"save round trip")
	await shot("05-result")
	print("PASS: ",checks," rule and mouse interaction checks")
	quit()
