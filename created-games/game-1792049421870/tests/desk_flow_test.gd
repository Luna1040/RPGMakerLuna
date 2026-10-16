extends "res://tests/desk_test_driver.gd"
func _initialize() -> void:call_deferred("run")
func run() -> void:
	await spawn_game(91)
	await click("tools");game.action_button.pressed.emit();advance(.35)
	await click("board")
	for i in range(12):key(KEY_SPACE);advance(.30)
	check(game.beads_placed==12,"12 bead input releases")
	key(KEY_Q);advance(.5);key(KEY_Q);advance(.5)
	await click("handheld")
	var center:Vector2=game.camera.unproject_position(game.props.handheld.to_global(Vector3(0,.0245,0)));button(MOUSE_BUTTON_LEFT,true,center)
	# Real danger and retry share exactly the same desktop/level delta.
	key(KEY_D)
	for i in range(300):advance(1.0/60)
	check(game.pocket.dead,"real input hazard");key(KEY_R)
	check(not game.pocket.dead and game.pocket.deaths==1,"checkpoint retry");key(KEY_D)
	var pauses:Array[float]=[];var budget:=0
	while game.phase not in ["won","lost"] and budget<16000:
		budget+=1
		if game.phase=="warning":
			var first_incomplete:bool=not game.pocket.won
			var saved:Vector2=game.pocket.player
			var saved_checkpoint:Vector2=game.pocket.checkpoint
			if game.patrol.visit==1:check(saved.x>1000,"first saved position truly progressed")
			await hide_evidence()
			check(game.phase=="warning","warning gives time to collect real props")
			advance(maxf(0,12-game.phase_clock)+.02)
			check(game.phase=="checking","safe arrival check")
			if game.patrol.visit==1:check(first_incomplete,"first visit task unfinished passes")
			advance(4.1)
			if game.visits_passed==3:
				advance(game.patrol.RETURN+.1);break
			check(game.phase=="returning","returning locks interactions")
			key(KEY_Q);check(game.inspecting.is_empty(),"no taking in returning")
			advance(game.patrol.RETURN+.1);check(game.phase=="free","return to free after seat")
			check(game.pocket.player==saved and game.pocket.checkpoint==saved_checkpoint,"level position and checkpoint preserved while hidden")
			await resume_play();key(KEY_D);pauses.append(game.elapsed)
		elif game.phase=="free":
			var p=game.pocket
			if p.grounded and not p.won:
				var floor_found:=false;var ahead:float=p.player.x+38
				for platform in p.platforms:
					if platform.position.y==310 and ahead>=platform.position.x and ahead<=platform.end.x:floor_found=true
				var danger:=not floor_found
				for h in p.hazards:
					if h.position.x>p.player.x and h.position.x-p.player.x<52:danger=true
				if danger:key(KEY_SPACE)
			advance(1.0/60)
		else:advance(1.0/60)
	check(game.phase=="won" and game.visits_passed==3,"three true visits win")
	check(game.pocket.won and game.pocket.checkpoints_passed==2,"real movement jump reaches two checkpoints and finish")
	check(game.pocket.time_played>30 and game.pocket.time_played<50,"level effective playtime "+str(game.pocket.time_played))
	check(game.patrol.intervals.size()==3 and pauses.size()==2,"three intervals no fourth")
	advance(100);check(game.patrol.visit==3,"no fourth after win")
	await clean()
	if failures.is_empty():print("DESK_FLOW_PASS unified_desktop_platform_delta midcourse_hide_resume real_ray_beads_jump_hazard_retry three_checks_win");quit(0)
	else:print("DESK_FLOW_FAILED ",failures);quit(1)
