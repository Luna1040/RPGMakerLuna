extends VBoxContainer
## Portraits and tactics remain readable inside the existing modal scroll area.
const Catalog = preload("roster_catalog.gd")
const ClipPlayer = preload("encounters/roster_animation.gd")
const ACTION_LABELS := {"portrait":"立绘","stand":"待机","walk":"移动","attack":"攻击","hurt":"受击","cast":"施法"}
var runtime
var selected_id := "scout"
var preview_mode := "portrait"
var light_background := false
var animation
var preview
var action_buttons: Dictionary = {}
var portrait_style: StyleBoxFlat
var background_button: Button

func setup(service, id: String = "scout") -> void:
	runtime=service
	selected_id=id if Catalog.ENTRIES.has(id) else "scout"
	add_theme_constant_override("separation",12)
	refresh()

func label(parent: Node, value: String, size: int = 18, color: Color = Color("d5dfec")) -> Label:
	var node:=Label.new()
	node.text=value
	node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",color)
	parent.add_child(node)
	return node

func refresh() -> void:
	preview=null
	action_buttons.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var selector:=HFlowContainer.new()
	selector.add_theme_constant_override("h_separation",8)
	add_child(selector)
	for id in Catalog.ORDER:
		var character_id:String=id
		var choice:=Button.new()
		choice.text=("● " if id==selected_id else "")+str(Catalog.ENTRIES[id].name)
		choice.custom_minimum_size.y=38
		choice.add_theme_font_size_override("font_size",18)
		choice.pressed.connect(func(): selected_id=character_id; preview_mode="portrait"; refresh())
		selector.add_child(choice)
	animation=ClipPlayer.new()
	animation.configure(selected_id)
	if preview_mode!="portrait" and not action_ready(preview_mode): preview_mode="portrait"
	var modes:=HFlowContainer.new()
	modes.add_theme_constant_override("h_separation",6)
	add_child(modes)
	for action in ACTION_LABELS:
		if action=="cast" and selected_id!="serin": continue
		var mode:String=action
		var ready:bool=action=="portrait" or action_ready(action)
		var choose:=Button.new()
		choose.text=("● " if action==preview_mode else "")+ACTION_LABELS[action]+(" · 制作中" if not ready else "")
		choose.disabled=not ready
		choose.custom_minimum_size.y=34
		choose.add_theme_font_size_override("font_size",16)
		choose.tooltip_text="此动作尚未完整导入，立绘不会替代动作。" if not ready else "显示完整角色立绘" if action=="portrait" else "播放整帧动作，切换深浅背景检查透明边缘。"
		choose.pressed.connect(func(): select_action(mode))
		modes.add_child(choose)
		action_buttons[action]=choose
	background_button=Button.new()
	background_button.custom_minimum_size.y=34
	background_button.add_theme_font_size_override("font_size",16)
	background_button.pressed.connect(func(): light_background=not light_background; update_background())
	modes.add_child(background_button)
	var info:Dictionary=Catalog.entry(selected_id)
	var columns:=HBoxContainer.new()
	columns.add_theme_constant_override("separation",24)
	add_child(columns)
	var portrait_box:=PanelContainer.new()
	portrait_box.custom_minimum_size=Vector2(300,350) if preview_mode=="portrait" else Vector2(390,350)
	portrait_box.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("0b1522")
	style.border_color=Color(info.color).darkened(.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	portrait_style=style
	portrait_box.add_theme_stylebox_override("panel",style)
	columns.add_child(portrait_box)
	var texture:=Catalog.portrait(selected_id)
	if preview_mode!="portrait":
		preview=MotionPreview.new()
		preview.host=self
		preview.animation=animation
		preview.action=preview_mode
		portrait_box.add_child(preview)
		preview.sample_frame()
	elif texture!=null:
		var picture:=TextureRect.new()
		picture.texture=texture
		picture.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
		picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
		portrait_box.add_child(picture)
	else:
		var missing:=Label.new()
		missing.text="立绘资源等待导入"
		missing.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		portrait_box.add_child(missing)
	update_background()
	var details:=VBoxContainer.new()
	details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation",10)
	columns.add_child(details)
	label(details,info.name,27,Color(info.color))
	label(details,info.faction+"  /  "+info.role,17,Color("a4bacd"))
	label(details,info.description)
	details.add_child(HSeparator.new())
	if selected_id=="serin":
		var ally:Dictionary=runtime.encounters.companion_status()
		label(details,"生命 %d / %d  ·  法力 %d / %d" % [ally.hp,ally.max_hp,ally.mp,ally.max_mp],19,Color("f1d593"))
		label(details,"已加入小队" if runtime.companion_recruited else "与镇民建立信任，在对话中邀请她加入。",17)
		for skill in ally.get("skills",[]):
			label(details,"%s · 消耗 %d MP / 冷却 %.1f 秒" % [skill.name,skill.cost,skill.cooldown],18,Color("c5e6e3"))
			label(details,str(skill.get("description","")),16,Color("a4bacd"))
	else:
		var enemy:Dictionary=runtime.encounters.DEFINITIONS[info.kind]
		label(details,"生命 %d  ·  基础伤害 %d  ·  攻击蓄势 %.1f 秒" % [enemy.hp,enemy.damage,enemy.windup],18,Color("f1d593"))
		for move in info.moves: label(details,move,18,Color("c5dbe9"))
	details.add_child(HSeparator.new())
	label(details,"交战手记",19,Color("f1d593"))
	label(details,info.tactics,17,Color("b8c9d7"))

func action_ready(action: String) -> bool:
	if animation==null or not animation.has_action(action): return false
	var clip:Dictionary=animation.clip(action)
	if not clip.get("frames") is Array or clip.frames.size()<2: return false
	for entry in clip.frames:
		if not entry is Dictionary: return false
		var file:String=str(entry.get("file",""))
		if file.is_empty() or file.is_absolute_path() or ".." in file: return false
		var path:String=animation.directory+file
		if not ResourceLoader.exists(path) and not FileAccess.file_exists(path): return false
	return true

func select_action(action: String) -> bool:
	if not ACTION_LABELS.has(action) or (action!="portrait" and not action_ready(action)): return false
	preview_mode=action
	refresh()
	return true

func update_background() -> void:
	if portrait_style!=null: portrait_style.bg_color=Color("e3e8e8") if light_background else Color("0b1522")
	if is_instance_valid(background_button): background_button.text="切换深底" if light_background else "切换浅底"
	if is_instance_valid(preview): preview.queue_redraw()

class MotionPreview extends Control:
	var host
	var animation
	var action:="stand"
	var clock_ms:=0.0
	var selected:Dictionary={}
	var error_text:=""
	const REPLAY_PAUSE_MS:=650.0

	func _ready() -> void:
		mouse_filter=Control.MOUSE_FILTER_IGNORE
		texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST

	func _process(delta: float) -> void:
		# Combat stays paused by the parent modal; only this presentation clock runs.
		if not is_visible_in_tree() or host==null or not host.runtime.panel.is_open(): return
		var duration:=ClipPlayer.duration_ms(animation.clip(action))
		var cycle:=duration+(0.0 if action in ["stand","walk"] else REPLAY_PAUSE_MS)
		clock_ms=fposmod(clock_ms+maxf(delta,0.0)*1000.0,cycle)
		sample_frame()

	func sample_frame() -> void:
		selected=animation.sample(action,clock_ms,action in ["stand","walk"])
		# Missing resources must not silently substitute the portrait for animation.
		if selected.is_empty() or bool(selected.get("portrait",true)):
			selected={}
			error_text="动作资源未就绪"
		else: error_text=""
		queue_redraw()

	func _draw() -> void:
		var color:=Color("203845") if host.light_background else Color("b7cbd4")
		var font:Font=get_theme_default_font()
		if not error_text.is_empty():
			draw_string(font,Vector2(20,50),error_text,HORIZONTAL_ALIGNMENT_LEFT,-1,18,color)
			return
		if selected.is_empty(): return
		var canvas:Array=animation.manifest.get("canvas",[768,768])
		var authored_scale:float=float(selected.scale)
		var canvas_size:=Vector2(float(canvas[0]),float(canvas[1]))*authored_scale
		# Fit the entire fixed canvas, never a changing alpha bounding box.
		var zoom:=minf(1.0,minf((size.x-16)/maxf(1,canvas_size.x),(size.y-46)/maxf(1,canvas_size.y)))
		var scale_factor:=authored_scale*maxf(.01,zoom)
		var offset:=(size-Vector2(float(canvas[0]),float(canvas[1]))*scale_factor)/2.0-Vector2(0,10)
		var origin:Vector2=offset+selected.pivot*scale_factor
		draw_line(Vector2(12,origin.y),Vector2(size.x-12,origin.y),Color(color,.22),1)
		draw_set_transform(origin,0,Vector2.ONE*scale_factor)
		draw_texture(selected.texture,-selected.pivot)
		draw_set_transform(Vector2.ZERO)
		var clip:Dictionary=animation.clip(action)
		var info:="%s · %d / %d 帧" % [ACTION_LABELS[action],int(selected.frame)+1,clip.frames.size()]
		if action not in ["stand","walk"] and clock_ms>=ClipPlayer.duration_ms(clip): info+=" · 重播前停顿"
		draw_string(font,Vector2(14,size.y-15),info,HORIZONTAL_ALIGNMENT_LEFT,size.x-28,14,color)
