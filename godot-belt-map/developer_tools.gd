extends CanvasLayer
var stage
var panel := PanelContainer.new()
var stats := Label.new()
var collision_toggle := CheckButton.new()
var hit_toggle := CheckButton.new()
var pause_toggle := CheckButton.new()
var overlay: Node2D
var hit_event: Dictionary = {}
var hit_foot := Vector2.ZERO
var hit_height := 0.0
var message := ""
var last_hit := "尚无攻击记录"
var speed := 1.0

func setup(map_stage) -> void:
	stage=map_stage
	layer=30
	process_mode=Node.PROCESS_MODE_ALWAYS
	var Overlay = preload("developer_overlay.gd")
	overlay=Overlay.new()
	overlay.tools=self
	overlay.z_index=100
	stage.add_child(overlay)
	var launcher := Button.new()
	launcher.text="F3 · 开发工具"
	launcher.position=Vector2(1110,165)
	launcher.size=Vector2(148,32)
	launcher.pressed.connect(func(): panel.visible=not panel.visible)
	add_child(launcher)
	panel.position=Vector2(18,118)
	panel.custom_minimum_size=Vector2(345,520)
	var style := StyleBoxFlat.new()
	style.bg_color=Color(.035,.055,.075,.96)
	style.border_color=Color("8cafbd")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left=14
	style.content_margin_right=14
	style.content_margin_top=12
	style.content_margin_bottom=12
	panel.add_theme_stylebox_override("panel",style)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",7)
	panel.add_child(column)
	var title := Label.new()
	title.text="开发检查台   ·   F3 收起"
	title.add_theme_font_size_override("font_size",21)
	column.add_child(title)
	collision_toggle.text="F2  碰撞体 / 高度 / 排序锚点"
	collision_toggle.toggled.connect(func(value): stage.debug_collision=value; overlay.queue_redraw())
	column.add_child(collision_toggle)
	hit_toggle.text="F4  最近一次攻击范围 / 木桩受击体"
	column.add_child(hit_toggle)
	pause_toggle.text="F6  暂停世界"
	pause_toggle.toggled.connect(func(value): get_tree().paused=value)
	column.add_child(pause_toggle)
	var step_button := Button.new()
	step_button.text="F7  单步推进 1/60 秒（先暂停）"
	step_button.pressed.connect(single_step)
	column.add_child(step_button)
	var speed_row := HBoxContainer.new()
	column.add_child(speed_row)
	for rate in [.25,.5,1.0]:
		var button := Button.new()
		button.text="%.2f×" % rate
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.pressed.connect(func(): set_speed(rate))
		speed_row.add_child(button)
	add_button(column,"F9 · 演示快速传送",func():
		if stage.runtime!=null:
			panel.hide()
			stage.runtime.panel.open("demo"))
	add_button(column,"恢复生命 / 法力 / 技能冷却",restore_resources)
	add_button(column,"复位木桩与浮空 / 感电状态",reset_targets)
	add_button(column,"保存截图与调试数据",save_report)
	stats.add_theme_font_size_override("font_size",15)
	stats.custom_minimum_size.x=315
	column.add_child(stats)
	panel.hide()
	if "--dev-tools" in OS.get_cmdline_user_args():
		panel.show()
		collision_toggle.button_pressed=true

func add_button(parent: Node, title: String, action: Callable) -> void:
	var button := Button.new()
	button.text=title
	button.pressed.connect(action)
	parent.add_child(button)

func set_speed(value: float) -> void:
	speed=value
	Engine.time_scale=value

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_F2: collision_toggle.button_pressed=not collision_toggle.button_pressed
		KEY_F3: panel.visible=not panel.visible
		KEY_F4: hit_toggle.button_pressed=not hit_toggle.button_pressed
		KEY_F6: pause_toggle.button_pressed=not pause_toggle.button_pressed
		KEY_F7: single_step()
		KEY_F8: set_speed(.25 if speed==1.0 else 1.0)
		_: return
	get_viewport().set_input_as_handled()

func single_step() -> void:
	if not get_tree().paused:
		message="先按 F6 暂停，再单步"
		return
	stage._physics_process(1.0/60.0)
	stage.loot._process(1.0/60.0)
	for prop in stage.sorting.get_children():
		for child in prop.get_children():
			if child.get_script()==preload("fountain_water.gd"): child._process(1.0/60.0)
	message="已推进一个物理帧"

func record_hit(event: Dictionary, count: int) -> void:
	hit_event=event.duplicate(true)
	hit_foot=stage.foot
	hit_height=stage.height_z
	last_hit="%s · 伤害 %.0f · 命中 %d" % [str(event.get("action","攻击")),float(event.get("damage",0)),count]

func reset_targets() -> void:
	for target in stage.practice.targets:
		target.hp=1000.0
		target.respawn=0.0
		target.reaction.reset()
		target.art.show()
	stage.practice.step(0)
	message="木桩已复位"

func restore_resources() -> void:
	stage.knight.health=stage.knight.max_health
	stage.knight.mana=stage.knight.max_mana
	stage.knight.cast_cooldown=0.0
	for id in stage.knight.skill_cooldowns: stage.knight.skill_cooldowns[id]=0.0
	stage.knight.stats_changed.emit(stage.knight.health,stage.knight.mana)
	message="已恢复资源与冷却，当前动作保留"

func _process(_delta: float) -> void:
	if stage==null: return
	overlay.queue_redraw()
	if not panel.visible: return
	var p: Vector2=stage.get_global_mouse_position()
	var ground := Vector2(p.x/stage.ppm,(p.y-stage.origin_y)/stage.depth_scale)
	var selected: Array[String]=[]
	for v in stage.volumes:
		if stage.Physics.overlaps(v,ground): selected.append(str(v.id))
	stats.text="%s  ·  %.2f×  ·  FPS %d\nx %.2f  depth %.2f  z %.2f\n垂直速度 %.2f   地面 %s\n动作 %s   第 %d 帧   %.3fs\n平台 %s\n鼠标地面 %.2f, %.2f\n鼠标附近 %s\n%s\n%s\n红：实体  蓝：水域  金：可站立\n青：玩家  紫：交互  十字：排序点" % ["暂停" if get_tree().paused else "运行",speed,Engine.get_frames_per_second(),stage.foot.x,stage.foot.y,stage.height_z,stage.vertical_speed,str(stage.grounded),stage.knight.state,stage.knight.action_frame,stage.knight.elapsed,stage.platform if stage.platform!="" else "地面",ground.x,ground.y,", ".join(selected) if not selected.is_empty() else "无",last_hit,message]

func save_report() -> void:
	var folder := "res://captures/debug"
	DirAccess.make_dir_recursive_absolute(folder)
	var stamp := Time.get_datetime_string_from_system().replace(":","-")+"-"+str(Time.get_ticks_msec())
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder+"/"+stamp+".png")
	var data := {"foot":{"x":stage.foot.x,"depth":stage.foot.y},"height":stage.height_z,"state":stage.knight.state,"frame":stage.knight.action_frame,"elapsed":stage.knight.elapsed,"grounded":stage.grounded,"platform":stage.platform,"speed":speed,"volumes":stage.volumes,"last_hit":hit_event,"equipment":stage.knight.equipment.equipped}
	if stage.runtime!=null:
		data["session"]=stage.runtime.snapshot()
		data["event_trace"]=stage.runtime.events.trace.duplicate(true)
		data["encounters"]=stage.runtime.encounters.snapshot()
	var file := FileAccess.open(folder+"/"+stamp+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(data,"  "))
	message="已保存至 captures/debug"

func _exit_tree() -> void:
	Engine.time_scale=1.0
