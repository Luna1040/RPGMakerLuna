extends SceneTree
var failures: Array[String]=[]
var checks:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)
func key(g, code: int) -> void:
	var event:=InputEventKey.new(); event.pressed=true; event.keycode=code
	g._unhandled_key_input(event)
func run() -> void:
	var g=load("res://main.tscn").instantiate()
	g.save_enabled=false; g.save_path="user://shooter-test-unused.json"
	root.add_child(g); g.set_process(false)
	key(g,KEY_E)
	var c=g.combat
	c.muted=true
	check(c.textures.size()==4,"Four generated enemy assets load")
	check(g.animation_art.has("boss") and g.animation_art.boss.frames==36,"H3 boss loop loads with fixed canvas")
	var vfx=g.get_node("CombatVFX/Effects")
	check(vfx.clip.get("frames",0)==40 and vfx.material.blend_mode==CanvasItemMaterial.BLEND_MODE_ADD,"H3 explosion uses its own additive layer")
	g.hazards.clear(); g.stars.clear(); g.player=Vector2(180,420)
	for i in 110: c.step(.01)
	check(c.enemies.size()==6 and c.shots.size()>0,"Formation and automatic fire begin")
	c.reset(); var e=c.spawn(0,Vector2(500,420)); e.fire=99; e.age=-.05; e.origin=420-sin(float(e.id))*42
	c.shot(Vector2(100,420),Vector2(10000,0),1); c.fire_cd=99
	c.step(.05)
	check(c.kills==1 and c.enemies.is_empty(),"Swept shots hit fast traversals and enemy death awards once")
	check(g.stars.size()==1,"Enemy drops collectable loot")
	c.reset(); g.hit_cd=0; g.hull=3; g.dash_left=0
	c.add_bullet(g.player-Vector2(40,0),Vector2(800,0),0); c.step(.1)
	check(g.hull==2,"Swept hostile bullet hits center")
	c.add_bullet(g.player,Vector2.ZERO,0); c.step(.01)
	check(g.hull==2,"Damage invulnerability blocks repeated hits")
	g.hit_cd=0; g.dash_left=.2
	c.add_bullet(g.player,Vector2.ZERO,0); c.step(.01)
	check(g.hull==2,"Dash bypasses bullets")
	g.dash_left=0; c.add_bullet(g.player+Vector2(0,16),Vector2.ZERO,0); c.step(.01)
	check(g.hull==2,"Ship wings are outside small hurtbox")
	c.reset(); c.add_bullet(Vector2(400,400),Vector2.ZERO,0)
	key(g,KEY_Q)
	check(c.bullets.is_empty() and c.pulses==2,"Actual Q clears bullets and spends one pulse")
	key(g,KEY_Q); check(c.pulses==2,"Pulse cannot double-trigger")
	c.reset(); c.elapsed=30; c.step(.01)
	check(c.choice,"Timed supply pauses combat")
	var t: float=c.elapsed; var pos: Vector2=g.player
	g.step_flight(.5,Vector2.RIGHT)
	check(c.elapsed==t and g.player==pos,"Choice freezes game movement and combat clocks")
	key(g,KEY_2); check(not c.choice and c.weapon==1 and c.rank==2,"Keyboard selects piercing upgrade")
	c.choice=true; var initial_rank: int=c.rank
	var mouse:=InputEventMouseButton.new(); mouse.pressed=true; mouse.button_index=MOUSE_BUTTON_LEFT
	# Native input routing is shared with the dock buttons; positioning is checked in visual review.
	c.choose(2); check(c.weapon==2 and c.rank==initial_rank+1,"Switching weapon keeps shared rank")
	c.choice=false
	var old_weapon: int=c.weapon; c.choose(0)
	check(c.weapon==old_weapon,"Cannot purchase a weapon outside the supply screen")
	for kind in 3:
		c.shots.clear(); c.weapon=kind; c.fire()
		check(c.shots.size()>0 and c.shots[0].kind==(1 if kind==1 else 0),"Weapon branch fires: %d" % kind)
	c.reset(); c.elapsed=150; c.step(.01)
	check(c.boss_spawned and c.enemies.size()==1 and c.enemies[0].kind==3,"Boss replaces formations")
	c.choice=false; e=c.enemies[0]; c.bullets.clear(); c.enemy_fire(e)
	var count: int=c.bullets.size(); e.hp=e.max*.4; c.enemy_fire(e)
	check(c.bullets.size()-count>count,"Boss phase two adds aimed fan")
	e.hp=0; var before: int=g.bank; g.cargo=10; c.step(.01)
	check(c.won and c.enemies.is_empty() and c.bullets.is_empty() and g.cargo>=50,"Boss death clears battle and recovers rewards")
	c.step(4.9); check(g.mode=="flight","Victory waits before returning")
	c.step(.2); check(g.mode=="dock" and g.bank>before,"Victory auto returns and banks")
	before=g.bank; c.step(10); check(g.bank==before,"Victory settlement is idempotent")
	# All three builds must be able to complete a full encounter. Invulnerability isolates flow from aiming skill.
	var durations: Array=[]
	var peak:=0
	for branch in 3:
		g.launch(); g.player=Vector2(300,440); g.hazards.clear(); g.stars.clear()
		for i in 24000:
			if c.choice: key(g,KEY_1+branch)
			g.hit_cd=10; g.energy=100
			g.step_flight(.02,Vector2.ZERO)
			peak=maxi(peak,c.bullets.size())
			if g.mode=="dock": break
		check(g.mode=="dock" and c.won,"Full encounter reaches victory: branch %d" % branch)
		check(c.choices_taken==3 and peak<=240,"Three upgrades and bounded projectiles: branch %d" % branch)
		durations.append(snappedf(c.elapsed,.01))
	print("SHOOTER TEST ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," durations=",durations," peak_bullets=",peak)
	g.free(); quit(0 if failures.is_empty() else 1)
