extends SceneTree
const Clips = preload("res://systems/encounters/roster_animation.gd")
const EnemyView = preload("res://systems/encounters/enemy_art.gd")
const AllyView = preload("res://systems/encounters/roster_actor_view.gd")
const Reactions = preload("res://dummy_reactions.gd")
var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func fixture() -> Dictionary:
	return {"duration_ms":300,"event_ms":150,"pivot":[384,700],"scale":0.35,"frames":[
		{"file":"fixture-a.png","duration_ms":100,"source_frame":3,"pivot":[1,1]},
		{"file":"fixture-b.png","duration_ms":50,"source_frame":7,"pivot":[700,700]},
		{"file":"fixture-c.png","duration_ms":150,"source_frame":9}]}

func seed_art(player) -> void:
	var art := fixture()
	player.manifest = {"canvas":[768,768],"actions":{"stand":art,"walk":art,"attack":art,"cast":art,"hurt":art}}
	var source := Image.create(8,8,false,Image.FORMAT_RGBA8)
	source.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(source)
	for file in ["fixture-a.png","fixture-b.png","fixture-c.png"]:
		player._textures[file] = texture

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var clip := fixture()
	check(Clips.duration_ms(clip) == 300,"duration must be the sum of per-frame timing")
	check(Clips.frame_at(clip,0) == 0,"first frame")
	check(Clips.frame_at(clip,99.99) == 0,"hold frame for authored duration")
	check(Clips.frame_at(clip,100) == 1,"first exact boundary advances")
	check(Clips.frame_at(clip,150) == 2,"second exact boundary advances")
	check(Clips.frame_at(clip,300) == 2,"one-shot clamps to its final frame")
	check(Clips.frame_at(clip,300,true) == 0,"loop wraps without duplicating endpoint")
	check(Clips.frame_at({},0) == -1,"missing clip cannot masquerade as animation")
	for windup in [0.24,0.6,0.9,1.1]:
		var impact := Clips.attack_time(clip,windup,windup,0.54)
		check(is_equal_approx(impact,150),"authored impact must align to actual release: "+str(windup))
		check(Clips.frame_at(clip,Clips.attack_time(clip,windup-0.0001,windup,0.54)) == 1,"impact frame must never appear before release")
		check(Clips.frame_at(clip,impact) == 2,"impact frame must appear at release")
		check(Clips.attack_time(clip,windup+0.54,windup,0.54) >= 299.99,"recovery must reach complete authored endpoint")
	var player := Clips.new()
	player.configure("serin")
	seed_art(player)
	for elapsed in [0.0,100.0,150.0,500.0]:
		var sampled := player.sample("attack",elapsed)
		check(sampled.pivot == Vector2(384,700) and sampled.scale == 0.35,"per-action fixed anchors must ignore per-frame crop pivots")
	check(player.sample("attack",150).source_frame == 9,"sample must retain authored source-frame identity")
	check(player.texture_for("../first_knight/stand.png") == null,"renderer must not escape its character art directory")
	var right := Clips.anchored_position(Vector2(384,700),0.35,1)
	var left := Clips.anchored_position(Vector2(384,700),0.35,-1)
	check(is_equal_approx(right.x,-left.x) and right.y == left.y,"facing must mirror around fixed foot pivot without vertical drift")
	check((right+Vector2(384,700)*0.35).length() < 0.001,"right-facing anchor remains at logical foot origin")
	check((left+Vector2(-384,700)*0.35).length() < 0.001,"left-facing anchor remains at logical foot origin")
	var enemy := EnemyView.new()
	root.add_child(enemy)
	enemy.animation.configure("scout")
	seed_art(enemy.animation)
	enemy.data = {"kind":"melee","state":"idle","clock":0.1,"facing":1,"reaction":Reactions.new(),"hp":10,"max_hp":10,"label":"测试","flash":0.0,"hurt_left":0.0,"hurt_elapsed":0.0,"attack_active":false}
	check(enemy.visual_sample().action == "stand","idle must select full standing frames")
	enemy.data.state = "chase"
	check(enemy.visual_sample().action == "walk","chase must select full walking frames")
	enemy.data.merge({"state":"telegraph","attack_active":true,"attack_elapsed":0.6,"attack_windup":0.6,"attack_recovery":0.54},true)
	check(enemy.visual_sample().action == "attack" and enemy.visual_sample().frame == 2,"enemy telegraph/release must sample attack at authored impact")
	enemy.data.hurt_left = 0.2
	enemy.data.hurt_elapsed = 0.2
	check(enemy.visual_sample().action == "hurt","whole-body hurt frames must override attack visuals")
	enemy.data.state = "dead"
	check(enemy.visual_sample().action == "hurt" and enemy.visual_sample().frame == 2,"death fallback must use hurt endpoint, not advertise an invented death clip")
	var ally := AllyView.new()
	root.add_child(ally)
	seed_art(ally.animation)
	ally.set_combat_view({"action":"attack1","elapsed":0.24,"facing":1,"hp":100,"mp":50})
	check(ally.selected.action == "attack" and ally.selected.frame == 2,"Serin attack impact must align with 0.24-second projectile release")
	ally.set_combat_view({"action":"magic","elapsed":0.24,"facing":-1,"hp":100,"mp":50})
	check(ally.selected.action == "cast" and ally.selected.frame == 2,"Serin class spells must use her own cast clip")
	ally.set_combat_view({"action":"dead","dead":true,"elapsed":0.0,"facing":1,"hp":0,"mp":50})
	check(ally.selected.action == "hurt" and ally.selected.frame == 2,"fallen Serin must hold own hurt endpoint")
	await process_frame
	enemy.queue_free()
	ally.queue_free()
	await process_frame
	for message in failures:
		push_error(message)
	print("ROSTER_ANIMATION_TEST ","PASS" if failures.is_empty() else "FAIL"," · ",checks," timing, impact, fixed pivot, facing, action and fallback checks")
	quit(0 if failures.is_empty() else 1)
