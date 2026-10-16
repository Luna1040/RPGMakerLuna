extends SceneTree
var checks := 0
var events: Array = []
func check(ok: bool, title: String) -> void:
	checks+=1
	if not ok:
		push_error("FAIL: "+title)
		quit(1)
func _initialize() -> void:
	call_deferred("run")
func snapshot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/motion-"+name+".png")
func run() -> void:
	var game=load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await process_frame
	check(game.motion.clips.size()==3,"three H3 clips installed")
	check(game.motion.player.is_playing(),"idle playback")
	game.motion.release_event.connect(func(a): events.append(a))
	await create_timer(1).timeout
	await snapshot("idle")
	game.reset_bank()
	game.start_round()
	await create_timer(1).timeout
	check(game.busy and game.player.is_empty(),"cards wait for release")
	var balance: int = game.bankroll
	game.start_round()
	check(game.bankroll==balance,"double click cannot double charge")
	await snapshot("deal-early")
	await create_timer(1.5).timeout
	check(events.count("deal")==1,"one deal release")
	check(game.player.size()>0,"cards after release")
	await snapshot("deal-release")
	while game.busy: await create_timer(0.1).timeout
	if game.active:
		game.stand()
		while game.busy: await create_timer(0.1).timeout
	check(not game.active,"round settles")
	# Force a separate deterministic winning settlement to verify payout timing.
	game.stake=50
	game.active=true
	var before: int = game.bankroll
	var before_rounds: int = game.rounds
	var before_events: int = events.count("payout")
	game.finish(100,"动作测试返还")
	await create_timer(1).timeout
	check(game.bankroll==before and game.busy,"payout delayed until push")
	game.reset_bank()
	check(game.bankroll==before,"reset locked during payout")
	await snapshot("payout-early")
	await create_timer(2.1).timeout
	check(game.bankroll==before+100,"payout credited once at release")
	await snapshot("payout-release")
	while game.busy: await create_timer(0.1).timeout
	check(events.count("payout")==before_events+1,"one payout release")
	check(game.rounds==before_rounds+1,"one settlement")
	check(game.motion.action=="idle","return to idle")
	check(not game.active,"unlocked after payout")
	print("PASS: ",checks," video-event integration checks")
	quit()
