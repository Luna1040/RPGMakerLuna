extends SceneTree
var failures:Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,msg:String) -> void:
	if not ok:failures.append(msg);push_error("DESK_PLATFORM_TIMING_FAIL "+msg)
func key(p:Node2D,code:int) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.pressed=true;p.key_input(event)
func run() -> void:
	var results:Array[Vector2]=[]
	for variant in range(3):
		var p:Node2D=load("res://pocket_game.gd").new();root.add_child(p);p.set_physics_process(false);p.set_active(true);key(p,KEY_D)
		var t:=0.0
		while t<5 and not p.dead:
			var dt:float=1.0/60 if variant==0 else (1.0/30 if variant==1 else (.12 if int(t*60)%53==0 else 1.0/60))
			p.advance(dt);t+=dt
		check(p.dead,"danger catches at varying render delta");key(p,KEY_R);key(p,KEY_D)
		var frame:=0
		while not p.won and not p.dead and frame<8000:
			frame+=1
			if p.grounded:
				var ahead:float=p.player.x+38;var found:=false
				for platform in p.platforms:
					if platform.position.y==310 and ahead>=platform.position.x and ahead<=platform.end.x:found=true
				var danger:=not found
				for h in p.hazards:
					if h.position.x>p.player.x and h.position.x-p.player.x<52:danger=true
				if danger:key(p,KEY_SPACE)
			var dt:float=1.0/60 if variant==0 else (1.0/30 if variant==1 else (.10 if frame%79==0 else 1.0/60))
			p.advance(dt)
		check(p.won and p.checkpoints_passed==2,"jump course fixed substeps "+str(variant))
		check(p.redraw_revision>20,"advance redraw revision")
		var pos:Vector2=p.player;p.set_active(false);p.advance(1);check(p.player==pos,"inactive does not advance")
		results.append(pos);p.queue_free();await process_frame
	if failures.is_empty():print("DESK_PLATFORM_TIMING_PASS real_input_hazard_retry_jump_goal 60Hz_30Hz_stalls fixed_120Hz redraw_pause");quit(0)
	else:print(failures);quit(1)
