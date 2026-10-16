extends RefCounted
## Independent RNG and bounded transitions: a large delta cannot skip arrival checks.
var game:Node3D
var rng:=RandomNumberGenerator.new()
var enabled:=true
var free_remaining:=0.0
var intervals:Array[float]=[]
var visit:=0
const WARNING:=12.0
const CHECK:=4.0
const RETURN:=10.0
func _init(owner:Node3D) -> void:game=owner;reset()
func reset(seed_value:int=-1) -> void:
	if seed_value<0:rng.randomize()
	else:rng.seed=seed_value
	visit=0;intervals.clear();schedule()
func schedule() -> void:
	free_remaining=rng.randf_range(20,30);intervals.append(free_remaining)
func advance(delta:float) -> void:
	if not enabled:return
	# Do not carry unspent time across states. Arrival must remain observable once.
	match game.phase:
		"free":
			free_remaining=maxf(0,free_remaining-delta)
			if free_remaining<=0:
				visit+=1;game.begin_warning()
		"warning":
			game.phase_clock=minf(WARNING,game.phase_clock+delta)
			game.office.pose("warning",game.phase_clock/WARNING,delta)
			if game.phase_clock>=WARNING:game.begin_check()
		"checking":
			game.phase_clock=minf(CHECK,game.phase_clock+delta)
			if not game.is_safe():game.finish(false)
			elif game.phase_clock>=CHECK:
				game.visits_passed+=1
				game.phase="returning";game.phase_clock=0;game.toast("老板往回走了。等他坐下再继续。",4)
		"returning":
			game.phase_clock=minf(RETURN,game.phase_clock+delta)
			game.office.pose("returning",game.phase_clock/RETURN,delta)
			if game.phase_clock>=RETURN:
				game.office.pose("free",0)
				if game.visits_passed==3:game.finish(true);return
				game.phase="free";game.phase_clock=0;schedule()
				game.toast("老板坐下了。移开文件夹，打开抽屉取出物件继续。",5)
