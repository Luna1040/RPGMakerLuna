extends SceneTree
## Visual QA only; never starts a foundation runtime or writes gameplay saves.
## Godot --path . --script tests/roster_motion_capture.gd -- --character=serin --action=stand
## --character=all --action=all captures every currently available authored clip.
## Outputs contact sheets, actual-game-scale lineup and alpha-bound metrics.
const Clips = preload("res://systems/encounters/roster_animation.gd")
const EnemyView = preload("res://systems/encounters/enemy_art.gd")
const AllyView = preload("res://systems/encounters/roster_actor_view.gd")
const Reaction = preload("res://dummy_reactions.gd")
const StageScript = preload("res://stage.gd")
const FONT = preload("res://assets/fonts/NotoSansSC-subset.ttf")
const IDS := ["scout","caster","elite","boss","serin"]
const ACTIONS := ["stand","walk","attack","hurt","cast"]
const KINDS := {"scout":"melee","caster":"ranged","elite":"elite","boss":"boss"}
var output_directory := "res://captures/roster-motion"
var reports: Array = []
var failures: Array[String] = []
var containers: Array[Node] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var requested_id := "serin"
	var requested_action := "stand"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--character="): requested_id = argument.trim_prefix("--character=")
		if argument.begins_with("--action="): requested_action = argument.trim_prefix("--action=")
		if argument.begins_with("--out="): output_directory = argument.trim_prefix("--out=")
	if requested_id not in IDS+["all"] or requested_action not in ACTIONS+["all"]:
		push_error("Use --character=scout|caster|elite|boss|serin|all and --action=stand|walk|attack|hurt|cast|all")
		quit(1)
		return
	if not output_directory.begins_with("res://captures/") or ".." in output_directory:
		push_error("Capture output must stay within res://captures/.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output_directory)
	ThemeDB.fallback_font = FONT
	var ids: Array = IDS if requested_id == "all" else [requested_id]
	var actions: Array = ACTIONS if requested_action == "all" else [requested_action]
	for id in ids:
		var player := Clips.new()
		player.configure(id)
		for action in actions:
			if not player.has_action(action):
				print("ROSTER_MOTION_SKIP ",id,"/",action," · no authored clip published")
				reports.append({"id":id,"action":action,"status":"skipped_missing_action"})
				continue
			await capture_sheet(id,action,player)
			await clear_containers()
	await capture_lineup()
	await clear_containers()
	resource_budget()
	var file := FileAccess.open(output_directory+"/report.json",FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"reports":reports,"failures":failures},"\t"))
	for failure in failures:
		push_error(failure)
	print("ROSTER_MOTION_CAPTURE ","PASS" if failures.is_empty() else "FAIL"," · ",output_directory)
	quit(0 if failures.is_empty() else 1)

func canvas(size: Vector2i) -> Node2D:
	root.size = size
	root.content_scale_size = size
	var node := Node2D.new()
	root.add_child(node)
	containers.append(node)
	return node

func rectangle(parent: Node, rect: Rect2, color: Color) -> void:
	var box := ColorRect.new()
	box.position = rect.position
	box.size = rect.size
	box.color = color
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)

func label(parent: Node, text: String, at: Vector2, size: int = 16, color: Color = Color("d9e3eb")) -> void:
	var item := Label.new()
	item.text = text
	item.position = at
	item.add_theme_font_override("font",FONT)
	item.add_theme_font_size_override("font_size",size)
	item.add_theme_color_override("font_color",color)
	parent.add_child(item)

func inverse_attack_time(clip: Dictionary, desired_ms: float, windup: float, recovery: float) -> float:
	var duration := Clips.duration_ms(clip)
	var event := clampf(float(clip.get("event_ms",duration*0.42)),0.0,duration-0.00001)
	if desired_ms <= event:
		return desired_ms/maxf(event,0.001)*windup
	return windup+(desired_ms-event)/maxf(duration-event,0.001)*recovery

func authored_actor(id: String, action: String, desired_ms: float) -> Node2D:
	if id == "serin":
		var view := AllyView.new()
		var mapped: String = {"attack":"attack1","hurt":"hit","cast":"magic"}.get(action,action)
		var elapsed := desired_ms/1000.0
		if action in ["attack","cast"]:
			elapsed = inverse_attack_time(view.animation.clip(action),desired_ms,0.24,0.36)
		elif action == "hurt":
			elapsed = desired_ms/Clips.duration_ms(view.animation.clip(action))*0.32
		view.set_combat_view({"action":mapped,"elapsed":elapsed,"facing":1,"hp":140.0,"mp":80.0,"dead":false,"hurt_left":0.0})
		return view
	var view := EnemyView.new()
	view.animation.configure(id)
	var windup: float = {"scout":0.6,"caster":0.9,"elite":0.8,"boss":1.1}[id]
	var recovery := 0.86 if id == "boss" else 0.54
	var attack := action in ["attack","cast"]
	view.data = {"kind":KINDS[id],"state":"telegraph" if attack else ("chase" if action == "walk" else "idle"),
		"clock":desired_ms/1000.0,"facing":1,"hp":100.0,"max_hp":100.0,"label":id,"reaction":Reaction.new(),"flash":0.0,
		"hurt_left":0.4 if action == "hurt" else 0.0,"hurt_elapsed":desired_ms/Clips.duration_ms(view.animation.clip(action))*0.4,
		"attack_active":attack,"attack_elapsed":inverse_attack_time(view.animation.clip(action),desired_ms,windup,recovery),"attack_windup":windup,"attack_recovery":recovery}
	# Enemy cast is selected by the production renderer for caster only.
	return view

func metrics(selected: Dictionary) -> Dictionary:
	if selected.is_empty():
		return {"missing":true}
	var texture: Texture2D = selected.texture
	var bitmap := Clips.virtual_image(texture)
	var used := bitmap.get_used_rect()
	var pivot: Vector2 = selected.pivot
	var scale_factor := float(selected.scale)
	var edge_touch := used.position.x <= 1 or used.position.y <= 1 or used.end.x >= bitmap.get_width()-1 or used.end.y >= bitmap.get_height()-1
	return {"frame":selected.frame,"source_frame":selected.source_frame,"source_used_rect":[used.position.x,used.position.y,used.size.x,used.size.y],
		"pivot":[pivot.x,pivot.y],"scale":scale_factor,"screen_body_height":used.size.y*scale_factor,
		"screen_foot_offset":(used.end.y-pivot.y)*scale_factor,"touches_canvas_edge":edge_touch,"portrait_fallback":selected.portrait}

func capture_sheet(id: String, action: String, player) -> void:
	var clip: Dictionary = player.clip(action)
	var pivot: Array = clip.get("pivot",[384,700])
	var crop: Array = clip.get("storage_crop",[0,0,768,768])
	# Keep actual gameplay scale, but widen cells for extended weapons. A fixed
	# 320-pixel cell would let the scout's 198-pixel sword reach cross its edge.
	var left_extent := absf((float(crop[0])-float(pivot[0]))*float(clip.get("scale",0.32)))
	var right_extent := absf((float(crop[0])+float(crop[2])-float(pivot[0]))*float(clip.get("scale",0.32)))
	var cell_width := maxi(320,ceili(maxf(left_extent,right_extent)*2.0)+32)
	var page_width := cell_width*4
	var foot_y := maxi(338,ceili(float(pivot[1])*float(clip.get("scale",0.32)))+65)
	var cell_height := foot_y+59
	var page := canvas(Vector2i(page_width,83+cell_height*2))
	rectangle(page,Rect2(0,0,page_width,83+cell_height*2),Color("0b1520"))
	var duration := Clips.duration_ms(clip)
	label(page,str(player.manifest.get("name",id))+" · "+action+" · 原始比例动作检查",Vector2(22,15),23)
	label(page,"整帧 PNG / 固定脚底十字 / 绿色基准线 / 8 个时间采样；未缩放角色以适配格子",Vector2(22,50),16,Color("a7c3ce"))
	var sampled: Array = []
	for index in 8:
		var column := index%4
		var row := index/4
		var origin := Vector2(column*cell_width,row*cell_height+83)
		rectangle(page,Rect2(origin+Vector2(6,3),Vector2(cell_width-12,cell_height-12)),Color("172534") if index%2 == 0 else Color("1b2b3a"))
		var sample_ms := float(index)/7.0*maxf(0.0,duration-0.001)
		var actor := authored_actor(id,action,sample_ms)
		actor.position = origin+Vector2(cell_width*0.5,foot_y)
		page.add_child(actor)
		var selected: Dictionary = actor.selected if id == "serin" else actor.visual_sample()
		var info := metrics(selected)
		info["sample_ms"] = sample_ms
		sampled.append(info)
		rectangle(page,Rect2(origin+Vector2(14,foot_y),Vector2(cell_width-28,1)),Color(0.4,0.86,0.65,0.65))
		rectangle(page,Rect2(actor.position-Vector2(1,6),Vector2(2,12)),Color("80ffb0"))
		label(page,"%d ms · 帧 %d / 源 %d" % [roundi(sample_ms),info.get("frame",-1),info.get("source_frame",-1)],origin+Vector2(14,9),15)
		label(page,"底差 %.1f px · 身高 %.1f px" % [float(info.get("screen_foot_offset",0)),float(info.get("screen_body_height",0))],origin+Vector2(14,foot_y+23),14)
		if bool(info.get("touches_canvas_edge",false)):
			label(page,"检查：源图接触边界",origin+Vector2(14,foot_y+40),13,Color("ffc18e"))
	var path := output_directory+"/"+id+"-"+action+"-contact.png"
	await save_view(path)
	reports.append({"id":id,"action":action,"status":"captured","path":path,"samples":sampled,"render_texture_bytes_while_captured":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)})

func capture_lineup() -> void:
	root.size = Vector2i(1280,800)
	root.content_scale_size = Vector2i(1280,800)
	var stage = StageScript.new()
	stage.foundations_enabled = false
	root.add_child(stage)
	containers.append(stage)
	stage.set_physics_process(false)
	for child in stage.sorting.get_children():
		if child != stage.foot_node and child is CanvasItem:
			child.hide()
	for child in stage.get_children():
		if child is CanvasLayer:
			child.hide()
	stage.camera.position = Vector2(2400,540)
	stage.camera.reset_smoothing()
	stage.foot = Vector2(16,8.4)
	stage.foot_node.position = stage.project(stage.foot)
	stage.knight.state = "stand"
	stage.knight.elapsed = 0.0
	stage.knight.show_frame()
	var layer := CanvasLayer.new()
	stage.add_child(layer)
	rectangle(layer,Rect2(18,18,1244,104),Color(0.035,0.065,0.10,0.94))
	label(layer,"同场景 · 实际游戏比例比较",Vector2(35,28),25)
	label(layer,"左侧为原姬骑士；其余使用各自 manifest 的固定 pivot / scale。全员同一地面深度，未做额外缩放。",Vector2(35,68),17)
	label(layer,"缺动作仅展示立绘并明确标注；此截图不会生成或修改任何角色素材。",Vector2(35,94),14,Color("a7c3ce"))
	var lineup: Array = []
	var hero_texture: Texture2D = stage.knight.body.texture
	var hero_used: Rect2i = hero_texture.get_image().get_used_rect()
	label(layer,"姬骑士 · 原角色",Vector2(94,678),16)
	lineup.append({"id":"knight","screen_body_height":hero_used.size.y*absf(stage.knight.visual.scale.y)})
	for index in IDS.size():
		var id: String = IDS[index]
		var reader := Clips.new()
		reader.configure(id)
		var actor := authored_actor(id,"stand",0)
		actor.position = stage.project(Vector2(17.6+index*1.6,8.4))
		stage.sorting.add_child(actor)
		var selected: Dictionary = actor.selected if id == "serin" else actor.visual_sample()
		var info := metrics(selected)
		info["id"] = id
		lineup.append(info)
		var screen_x := 352+index*192
		label(layer,id+(" · 立绘" if not reader.has_action("stand") else " · 待机"),Vector2(screen_x-68,678),16)
		if not info.get("missing",false):
			label(layer,"高 %.1f / 底差 %.1f" % [float(info.screen_body_height),float(info.screen_foot_offset)],Vector2(screen_x-68,705),13)
		rectangle(layer,Rect2(screen_x-72,648,144,1),Color(0.4,0.86,0.65,0.7))
	await save_view(output_directory+"/lineup-actual-scale.png")
	reports.append({"status":"captured","type":"lineup_actual_scale","characters":lineup,"render_texture_bytes_while_captured":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)})

func resource_budget() -> void:
	var characters: Array = []
	var total_frames := 0
	var total_rgba := 0
	for id in IDS:
		var reader := Clips.new()
		var second := Clips.new()
		reader.configure(id)
		second.configure(id)
		var canvas_size: Array = reader.manifest.get("canvas",[768,768])
		var unique := {}
		for clip in reader.manifest.get("actions",{}).values():
			var crop: Array = clip.get("storage_crop",[0,0,canvas_size[0],canvas_size[1]])
			for frame in clip.get("frames",[]):
				unique[str(frame.file)] = int(crop[2])*int(crop[3])*4
		var bytes := 0
		for stored_bytes in unique.values():
			bytes += int(stored_bytes)
		total_frames += unique.size()
		total_rgba += bytes
		var same_resource: Variant = null
		var checked_path := ""
		var imported := false
		if not unique.is_empty():
			checked_path = str(unique.keys()[0])
			var a: Texture2D = reader.texture_for(checked_path)
			var b: Texture2D = second.texture_for(checked_path)
			if a is AtlasTexture: a = a.atlas
			if b is AtlasTexture: b = b.atlas
			same_resource = a == b and a != null
			imported = FileAccess.file_exists(reader.directory+checked_path+".import")
		characters.append({"id":id,"clips":reader.manifest.get("actions",{}).size(),"unique_frames":unique.size(),
			"rgba_bytes_no_mips":bytes,"same_texture_across_two_players":same_resource,"checked_frame":checked_path,"import_metadata_exists":imported})
	reports.append({"type":"texture_budget","characters":characters,"unique_frames":total_frames,"rgba_bytes_no_mips":total_rgba,
		"estimate_350_frames_768":350*768*768*4,"estimate_400_frames_768":400*768*768*4,"estimate_400_frames_384":400*384*384*4})

func save_view(path: String) -> void:
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(path)
	if result != OK:
		failures.append("Could not save "+path+" error="+str(result))
	else:
		print("ROSTER_MOTION_IMAGE ",path)

func clear_containers() -> void:
	for node in containers:
		if is_instance_valid(node): node.queue_free()
	containers.clear()
	await process_frame
	await create_timer(0.15).timeout
