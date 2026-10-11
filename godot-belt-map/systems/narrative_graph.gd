extends Control
signal node_selected(data: Dictionary)
## Read-only narrative graph. State comes from the same service as dialogue choices.
var graph: Dictionary = {}
var node_boxes: Array[Dictionary] = []

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		for box in node_boxes:
			if box.rect.has_point(event.position):
				node_selected.emit(box.data)
				accept_event()
				return

func _get_tooltip(at_position: Vector2) -> String:
	for box in node_boxes:
		if box.rect.has_point(at_position): return str(box.data.get("description",""))
	return ""

func _draw() -> void:
	node_boxes.clear()
	var nodes:Array=graph.get("nodes",[])
	var edges:Array=graph.get("edges",[])
	var coordinates:Dictionary={}
	var node_width:=226.0
	custom_minimum_size.y=450
	for i in nodes.size():
		var item:Dictionary=nodes[i]
		var grid:Array=item.get("position",[i%4,int(i/4)])
		coordinates[str(item.get("id",i))]=Vector2(10+float(grid[0])*245,20+float(grid[1])*108)
	for edge in edges:
		var source:String=""
		var target:String=""
		if edge is Dictionary:
			source=str(edge.get("from",edge.get("source","")))
			target=str(edge.get("to",edge.get("target","")))
		elif edge is Array and edge.size()>=2:
			source=str(edge[0]); target=str(edge[1])
		if coordinates.has(source) and coordinates.has(target):
			var a:Vector2=coordinates[source]+Vector2(node_width/2,35)
			var b:Vector2=coordinates[target]+Vector2(node_width/2,35)
			draw_line(a,b,Color(.52,.68,.72,.45),2)
	for i in nodes.size():
		var item:Dictionary=nodes[i]
		var p:Vector2=coordinates[str(item.get("id",i))]
		var status:String=str(item.get("status",item.get("state","locked")))
		var color:=Color("6e8292")
		if status in ["completed","claimed","done","resolved","chosen","selected"]: color=Color("dfbd73")
		elif status in ["active","available","ready","accepted"]: color=Color("68cecb")
		elif status in ["excluded","blocked","rejected","locked_out"]: color=Color("b47383")
		var box:=Rect2(p,Vector2(node_width,70))
		node_boxes.append({"rect":box,"data":item})
		draw_rect(box,Color("142635"))
		draw_rect(box,color,false,2)
		var font:=ThemeDB.fallback_font
		draw_string(font,p+Vector2(12,27),str(item.get("title",item.get("label",item.get("id","")))),HORIZONTAL_ALIGNMENT_LEFT,node_width-24,18,color)
		var caption:String={"locked":"条件未满足","available":"可接取 / 可选择","active":"进行中","ready":"目标达成 · 可交付","claimed":"已经完成","selected":"已选择此路线","excluded":"另一条路线已选定"}.get(status,status)
		draw_string(font,p+Vector2(12,53),caption,HORIZONTAL_ALIGNMENT_LEFT,node_width-24,14,Color("afc4cf"))
