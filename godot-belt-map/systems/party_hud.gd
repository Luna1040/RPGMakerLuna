extends CanvasLayer
## Independent companion vitals, visible only while the world is interactive.
const Catalog = preload("roster_catalog.gd")
var runtime
var card:=PanelContainer.new()
var name_label:=Label.new()
var hp:=ProgressBar.new()
var mp:=ProgressBar.new()
var details:=Label.new()
var skills:=Label.new()
var clock:=0.0

func setup(service) -> void:
	runtime=service
	layer=9
	card.position=Vector2(28,151)
	card.size=Vector2(300,130)
	var style:=StyleBoxFlat.new()
	style.bg_color=Color(.035,.07,.11,.9)
	style.border_color=Color("698d8c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left=12
	style.content_margin_right=12
	style.content_margin_top=9
	style.content_margin_bottom=9
	card.add_theme_stylebox_override("panel",style)
	add_child(card)
	var rows:=VBoxContainer.new()
	rows.add_theme_constant_override("separation",3)
	card.add_child(rows)
	name_label.add_theme_font_size_override("font_size",18)
	name_label.add_theme_color_override("font_color",Color("d7eae4"))
	rows.add_child(name_label)
	for bar in [hp,mp]:
		bar.custom_minimum_size=Vector2(276,18)
		bar.show_percentage=false
		bar.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var background:=StyleBoxFlat.new()
		background.bg_color=Color("0a1420")
		background.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("background",background)
		var fill:=StyleBoxFlat.new()
		fill.bg_color=Color("64bcb2") if bar==hp else Color("6a94db")
		fill.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill",fill)
		rows.add_child(bar)
	details.add_theme_font_size_override("font_size",14)
	details.add_theme_color_override("font_color",Color("b4c9d1"))
	rows.add_child(details)
	skills.add_theme_font_size_override("font_size",14)
	skills.add_theme_color_override("font_color",Color("eadba9"))
	skills.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(skills)
	card.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
			runtime.panel.roster_id="serin"
			runtime.panel.open("roster")
			card.accept_event())
	# Labels should not swallow the click used to open the character record.
	for row in rows.get_children(): row.mouse_filter=Control.MOUSE_FILTER_IGNORE
	rows.mouse_filter=Control.MOUSE_FILTER_IGNORE
	update_status()

func _process(delta: float) -> void:
	if runtime==null or runtime.panel==null: return
	visible=runtime.companion_recruited and not runtime.stage.interface.is_modal()
	clock+=delta
	if clock>=.1:
		clock=0
		update_status()

func update_status() -> void:
	if runtime==null: return
	var ally:Dictionary=runtime.encounters.companion_status()
	visible=runtime.companion_recruited and not runtime.stage.interface.is_modal()
	name_label.text="瑟琳 · 战牧  /  "+("倒下" if ally.dead else {"follow":"跟随","guard":"守卫","passive":"停战"}.get(ally.mode,"跟随"))
	hp.max_value=ally.max_hp
	hp.value=ally.hp
	mp.max_value=ally.max_mp
	mp.value=ally.mp
	details.text="生命 %d/%d  ·  法力 %d/%d" % [ally.hp,ally.max_hp,ally.mp,ally.max_mp]
	var cooldowns:Array[String]=[]
	var tooltip:Array[String]=["点击查看瑟琳的职业与技能。"]
	for skill in ally.get("skills",[]):
		cooldowns.append("%s %s" % [str(skill.name),"%.0fs" % ceilf(float(skill.remaining)) if float(skill.remaining)>0 else "就绪"])
		tooltip.append("%s · %d MP · %s" % [skill.name,skill.cost,str(skill.get("description",""))])
	skills.text="回城旅店休整可复苏" if ally.dead else " / ".join(cooldowns)
	if not ally.dead and float(ally.get("shield",0))>0: details.text+="  盾 %d" % ally.shield
	card.tooltip_text="\n".join(tooltip)
