extends SceneTree
## Real-stage visual QA. No foundation runtime, saved game, or simulated projectile.
## Godot --path . --script tests/roster_spell_capture.gd -- --character=all
## Waits for real reviewed, runtime-packed attack assets with authored emitters.
const Stage = preload("res://stage.gd")
const Encounters = preload("res://systems/encounters/encounters.gd")
const Clips = preload("res://systems/encounters/roster_animation.gd")
const FONT = preload("res://assets/fonts/NotoSansSC-subset.ttf")
var output_directory := "res://captures/roster-spells"
var reports: Array = []
var failures: Array[String] = []
var captured := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var requested := "all"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--character="): requested = argument.trim_prefix("--character=")
		if argument.begins_with("--out="): output_directory = argument.trim_prefix("--out=")
	if requested not in ["serin","caster","all"] or not output_directory.begins_with("res://captures/") or ".." in output_directory:
		push_error("Use --character=serin|caster|all and --out=res://captures/<directory>")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output_directory)
	ThemeDB.fallback_font = FONT
	root.size = Vector2i(1280,800)
	root.content_scale_size = Vector2i(1280,800)
	var ids: Array = ["serin","caster"] if requested == "all" else [requested]
	for id in ids:
		var clips := Clips.new()
		clips.configure(id)
		var reason := readiness(clips)
		if not reason.is_empty():
			print("ROSTER_SPELL_SKIP ",id," · ",reason)
			reports.append({"id":id,"status":"skipped_assets_not_ready","reason":reason})
			continue
		if DisplayServer.get_name() == "headless":
			print("ROSTER_SPELL_SKIP ",id," · native renderer required for screenshots")
			reports.append({"id":id,"status":"skipped_headless"})
			continue
		for facing in [1,-1]:
			await capture_spell(id,facing,clips)
	var report := FileAccess.open(output_directory+"/report.json",FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify({"captures":captured,"reports":reports,"failures":failures},"\t"))
	for failure in failures:
		push_error(failure)
	var status := "FAIL" if not failures.is_empty() else ("PASS" if captured > 0 else "SKIP")
	print("ROSTER_SPELL_CAPTURE ",status," · ",captured," real-stage captures · ",output_directory)
	quit(0 if failures.is_empty() else 1)

func readiness(clips) -> String:
	var clip: Dictionary = clips.clip("attack")
	if not clips.has_action("attack"): return "no published attack animation"
	if clip.get("review_status","") != "visually_reviewed": return "attack is not visually reviewed"
	if clip.get("storage_crop",[]).size() != 4: return "attack is not runtime-packed"
	if clip.get("emitter",[]).size() != 2: return "no authored attack emitter"
	if clip.get("pivot",[]).size() != 2 or float(clip.get("scale",0)) <= 0: return "invalid attack transform"
	if not clip.has("event_ms"): return "no authored release time"
	if clips.character_id == "caster" and clips.has_action("cast"):
		return "caster renderer selects cast, but combat socket reads attack; resolve manifest/render mismatch first"
	var selected: Dictionary = clips.sample("attack",float(clip.event_ms))
	if selected.is_empty() or bool(selected.get("portrait",true)): return "release frame texture missing"
	if not selected.texture is AtlasTexture: return "release frame did not load as packed AtlasTexture"
	return ""

func add_label(parent: Node, value: String, at: Vector2, size: int = 17) -> void:
	var label := Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_override("font",FONT)
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",Color("e1e9ee"))
	parent.add_child(label)

func clear_row(service) -> float:
	for depth in [8.4,7.6,6.8,6.0,5.2,4.4,3.6]:
		var left := Vector2(19.3,depth)
		var right := Vector2(23.3,depth)
		if service._walkable(left) and service._walkable(right) and service._line_clear(left,right,0.8):
			return depth
	return -1.0

func capture_spell(id: String, facing: int, clips) -> void:
	var stage = Stage.new()
	stage.foundations_enabled = false
	root.add_child(stage)
	stage.set_physics_process(false)
	for child in stage.sorting.get_children():
		if child != stage.foot_node and child is CanvasItem: child.hide()
	for child in stage.get_children():
		if child is CanvasLayer: child.hide()
	var service = Encounters.new()
	stage.add_child(service)
	service.setup(stage)
	var depth := clear_row(service)
	if depth < 0:
		failures.append(id+": real stage has no unobstructed four-metre capture row")
		stage.queue_free()
		await process_frame
		return
	var origin := Vector2(19.3 if facing > 0 else 23.3,depth)
	var target := Vector2(23.3 if facing > 0 else 19.3,depth)
	stage.camera.position = Vector2(21.3*stage.ppm,stage.project(origin).y-245.0)
	stage.camera.reset_smoothing()
	stage.foot = target
	stage.foot_node.position = stage.project(target)
	stage.knight.state = "stand"
	stage.knight.elapsed = 0.0
	stage.knight.facing = -facing
	stage.knight.show_frame()
	var shot: Dictionary = {}
	var selected: Dictionary = {}
	var elapsed := 0.24
	if id == "serin":
		stage.foot_node.hide()
		var enemy: Dictionary = service._spawn("melee",target,"spell-qa-target")
		enemy.facing = -facing
		enemy.art.queue_redraw()
		service.set_companion_enabled(true)
		service.companion_foot = origin
		service.companion_facing = facing
		service.companion_action = "attack1"
		service.companion_elapsed = elapsed
		service.companion_cast = "bolt"
		service.companion_target_id = enemy.id
		service._resolve_companion_cast()
		service._update_companion_view()
		selected = service.companion_view.selected
		if service.companion_projectiles.size() == 1: shot = service.companion_projectiles[0]
	else:
		var enemy: Dictionary = service._spawn("ranged",origin,"spell-qa-caster")
		elapsed = float(enemy.attack_windup)
		enemy.state = "attack"
		enemy.attack_active = true
		enemy.attack_elapsed = elapsed
		enemy.attack_variant = "ranged"
		enemy.attack_origin = origin
		enemy.attack_facing = facing
		enemy.facing = facing
		enemy.aim = target
		service._resolve_attack(enemy)
		enemy.art.queue_redraw()
		selected = enemy.art.visual_sample()
		if service.hostile_projectiles.size() == 1: shot = service.hostile_projectiles[0]
	service.queue_redraw()
	# Nothing steps after resolution. These are the service's unchanged birth coordinates.
	if shot.is_empty():
		failures.append(id+": real service did not create exactly one projectile")
		stage.queue_free()
		await process_frame
		return
	var clip: Dictionary = clips.clip("attack")
	var offset := (Vector2(clip.emitter[0],clip.emitter[1])-Vector2(clip.pivot[0],clip.pivot[1]))*float(clip.scale)
	var expected: Vector2 = stage.project(origin)+Vector2(offset.x*facing,offset.y)
	var actual: Vector2 = stage.project(shot.foot,shot.z)
	var error := expected.distance_to(actual)
	var release_index := Clips.frame_at(clip,float(clip.event_ms))
	if error > 0.01: failures.append(id+": projectile/emitter mismatch = "+str(error)+" px")
	if selected.get("action","") != "attack" or int(selected.get("frame",-1)) != release_index:
		failures.append(id+": renderer did not select authored release frame")
	if not shot.has("launch_from") or shot.launch_from != origin:
		failures.append(id+": original launch sweep anchor was not preserved")
	var layer := CanvasLayer.new()
	stage.add_child(layer)
	var panel := ColorRect.new()
	panel.position = Vector2(18,18)
	panel.size = Vector2(1244,112)
	panel.color = Color(0.03,0.06,0.1,0.94)
	layer.add_child(panel)
	var direction := "right" if facing > 0 else "left"
	add_label(layer,id+" · 真实施法出生帧 · "+("朝右" if facing > 0 else "朝左"),Vector2(34,27),24)
	add_label(layer,"elapsed %.2f s / event %.0f ms / frame %d / source %d / emitter delta %.4f px" % [elapsed,float(clip.event_ms),release_index,int(selected.get("source_frame",-1)),error],Vector2(34,65))
	add_label(layer,"真实 stage + 战斗服务 + 原渲染器；出弹后冻结，无模拟光弹、无额外角色缩放。",Vector2(34,96),15)
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := output_directory+"/"+id+"-birth-"+direction+".png"
	var result := image.save_png(path)
	if result != OK:
		failures.append("Could not write "+path)
	else:
		captured += 1
		print("ROSTER_SPELL_IMAGE ",path)
	var transform: Transform2D = stage.get_global_transform_with_canvas()
	var expected_screen := transform*expected
	var actual_screen := transform*actual
	reports.append({"id":id,"facing":facing,"status":"captured" if result == OK else "failed_save","path":path,
		"elapsed_seconds":elapsed,"event_ms":clip.event_ms,"frame":release_index,"source_frame":selected.get("source_frame",-1),
		"emitter":clip.emitter,"pivot":clip.pivot,"scale":clip.scale,"storage_crop":clip.storage_crop,
		"source_origin":[origin.x,origin.y],"target":[target.x,target.y],"launch_from":[shot.launch_from.x,shot.launch_from.y],
		"projectile_foot":[shot.foot.x,shot.foot.y],"projectile_z":shot.z,"projectile_life":shot.life,
		"expected_screen":[expected_screen.x,expected_screen.y],"projectile_screen":[actual_screen.x,actual_screen.y],"screen_error_px":error})
	stage.queue_free()
	await process_frame
