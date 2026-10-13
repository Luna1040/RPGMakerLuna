extends Node2D
## Visible map exits. Interaction is explicit, so arrivals never bounce back.
var runtime
var links: Array = []
var labels: Array[Label] = []
var elapsed := 0.0

func setup(service) -> void:
	runtime=service
	links=runtime.stage.contract.get("portals",[])
	for link in links:
		var label:=Label.new()
		label.position=runtime.stage.project(Vector2(link.x,link.depth))+Vector2(-155,-235)
		label.size=Vector2(310,80)
		label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size",18)
		label.add_theme_color_override("font_shadow_color",Color.BLACK)
		label.add_theme_constant_override("shadow_outline_size",5)
		add_child(label)
		labels.append(label)

func locked(link: Dictionary) -> bool:
	return link.has("quest") and runtime.adventure._status(str(link.quest))!="claimed"

func nearby() -> Dictionary:
	if runtime.stage.height_z>.3: return {}
	for link in links:
		var delta:Vector2=runtime.stage.foot-Vector2(link.x,link.depth)
		if absf(delta.x)<1.25 and absf(delta.y)<1.15: return link
	return {}

func prompt() -> String:
	var link:=nearby()
	if link.is_empty(): return ""
	if runtime.encounters.active: return "战斗中传送门封锁 · 清敌后离开，或 Esc 撤退"
	return "E 查看关口条件 · "+str(link.label) if locked(link) else "E 进入 · "+str(link.label)

func interact() -> bool:
	var link:=nearby()
	if link.is_empty(): return false
	if runtime.encounters.active:
		runtime.say("先清理当前敌人，或从 Esc 冒险菜单撤退。")
	elif locked(link):
		runtime.say("关口尚未开放：找雷恩接取「雷恩的试炼」，从西门进入旧林道，清敌后回去交付。")
	else: runtime.use_portal(link)
	return true

func _process(delta: float) -> void:
	if runtime==null: return
	elapsed+=delta
	for i in links.size():
		var link:Dictionary=links[i]
		labels[i].text=str(link.label)+("\n交付雷恩的试炼后开放" if locked(link) else "\n["+runtime.controls.key_name("interact")+"] 传送")
		labels[i].modulate=Color("d1b08c") if locked(link) else Color("b6f0fa")
	queue_redraw()

func _draw() -> void:
	if runtime==null: return
	for link in links:
		var foot:Vector2=runtime.stage.project(Vector2(link.x,link.depth))
		var color:=Color("ac8660") if locked(link) else Color("60daed")
		var outline:=PackedVector2Array()
		var fill:=PackedVector2Array()
		for j in 65:
			var angle:=TAU*j/64.0
			var point:=foot+Vector2(cos(angle)*47,sin(angle)*91-96)
			outline.append(point)
			fill.append(point)
		draw_colored_polygon(fill,Color(color,.12))
		draw_polyline(outline,Color(color,.25),12,true)
		draw_polyline(outline,color,3,true)
		draw_line(foot+Vector2(-59,0),foot+Vector2(59,0),color,4,true)
		for j in 8:
			var phase:=fposmod(elapsed*.3+j*.125,1.0)
			draw_circle(foot+Vector2(sin(j*2.1+elapsed)*30,-20-phase*145),2,Color(color,1-phase))
