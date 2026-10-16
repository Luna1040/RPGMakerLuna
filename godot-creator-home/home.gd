extends Control
var endpoint: String
var headers: PackedStringArray
var prompt: TextEdit
var conversation: TextEdit
var status: Label
var mode_label: Label
var cards: HBoxContainer
var poll: HTTPRequest
var catalog: HTTPRequest
var action: HTTPRequest
var last_catalog := ""
var selected_id := ""
var root_path: String
var last_request := ""
var drafts: Dictionary = {}
var restoring := false
var restored_card := false

func save_drafts() -> void:
	if restoring or prompt==null: return
	drafts[selected_id]=prompt.text
	var file:=FileAccess.open("user://creator-drafts.tmp",FileAccess.WRITE)
	if file==null: return
	file.store_string(JSON.stringify({"selected_id":selected_id,"drafts":drafts}))
	file.close()
	DirAccess.rename_absolute("user://creator-drafts.tmp","user://creator-drafts.json")

func select_game(game: Dictionary) -> void:
	save_drafts()
	restoring=true
	selected_id=str(game.get("id",""))
	mode_label.text="新游戏" if selected_id.is_empty() else "继续创作："+str(game.title)
	prompt.text=str(drafts.get(selected_id,game.get("last_prompt",game.get("brief",""))))
	last_request=str(game.get("last_prompt",""))
	conversation.text=str(game.get("last_reply",game.get("progress","补充要求，或者直接发送原需求继续完成。")))
	restoring=false
	save_drafts()
	prompt.grab_focus()

func label_at(text: String, position_: Vector2, font_size: int, color: Color) -> Label:
	var label:=Label.new()
	label.text=text
	label.position=position_
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	add_child(label)
	return label

func _ready() -> void:
	var app_theme:=Theme.new()
	app_theme.default_font=load("res://font.ttf")
	app_theme.default_font_size=17
	var button_style:=StyleBoxFlat.new()
	button_style.bg_color=Color("263d50")
	button_style.set_corner_radius_all(6)
	button_style.content_margin_left=12
	button_style.content_margin_right=12
	button_style.content_margin_top=6
	button_style.content_margin_bottom=6
	app_theme.set_stylebox("normal","Button",button_style)
	app_theme.set_color("font_color","Button",Color("eef8ff"))
	theme=app_theme
	root_path=ProjectSettings.globalize_path("res://..").trim_suffix("/")
	var connection_path:=OS.get_environment("GAME_ASSISTANT_CONNECTION")
	if connection_path.is_empty(): connection_path=root_path+"/.game-assistant/connection.json"
	var connection=JSON.parse_string(FileAccess.get_file_as_string(connection_path))
	label_at("LUNA  /  CREATE & PLAY",Vector2(48,26),17,Color("84d9c0"))
	label_at("把一个想法，变成能玩的世界。",Vector2(48,61),34,Color("f1f5ff"))
	label_at("和 AI 一起创作 · 从这里开始，也从这里回到你的游戏",Vector2(49,114),16,Color("94a1b9"))
	mode_label=label_at("新游戏",Vector2(48,160),18,Color("84d9c0"))
	prompt=TextEdit.new()
	prompt.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	prompt.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	prompt.position=Vector2(48,195)
	prompt.size=Vector2(1184,115)
	prompt.placeholder_text="想做什么游戏？例如：做一个俯视角躲避弹幕游戏，收集星星升级，坚持 60 秒获胜。"
	add_child(prompt)
	if FileAccess.file_exists("user://creator-drafts.json"):
		var saved=JSON.parse_string(FileAccess.get_file_as_string("user://creator-drafts.json"))
		if saved is Dictionary:
			drafts=saved.get("drafts",{})
			selected_id=str(saved.get("selected_id",""))
			prompt.text=str(drafts.get(selected_id,""))
	prompt.text_changed.connect(save_drafts)
	var send:=Button.new()
	send.text="发送并开始创作  →"
	send.position=Vector2(1002,324)
	send.size=Vector2(230,42)
	send.pressed.connect(submit)
	add_child(send)
	var fresh:=Button.new()
	fresh.text="＋ 创建另一个游戏"
	fresh.position=Vector2(48,324)
	fresh.size=Vector2(210,42)
	fresh.pressed.connect(func(): select_game({}); restored_card=true)
	add_child(fresh)
	var stop:=Button.new()
	stop.text="停止生成"
	stop.position=Vector2(275,324)
	stop.size=Vector2(120,42)
	stop.pressed.connect(func(): post("/interrupt",{}))
	add_child(stop)
	status=label_at("正在连接创作助手…",Vector2(420,332),15,Color("a3afc5"))
	conversation=TextEdit.new()
	conversation.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	conversation.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	conversation.position=Vector2(48,382)
	conversation.size=Vector2(1184,117)
	conversation.editable=false
	conversation.add_theme_color_override("font_readonly_color",Color("cdd6e5"))
	conversation.text="描述玩法、画风和目标。创建完成后，下方会出现可进入的游戏。"
	add_child(conversation)
	label_at("我的游戏",Vector2(48,522),24,Color("f1f5ff"))
	label_at("每个世界独立保存 · 点击进入试玩",Vector2(205,531),15,Color("94a1b9"))
	var scroll:=ScrollContainer.new()
	scroll.position=Vector2(48,568)
	scroll.size=Vector2(1184,225)
	scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	cards=HBoxContainer.new()
	cards.add_theme_constant_override("separation",18)
	scroll.add_child(cards)
	if not connection is Dictionary:
		status.text="请通过运行游戏.bat 启动"
		return
	endpoint=connection.url
	headers=PackedStringArray(["Content-Type: application/json","Authorization: Bearer "+connection.token])
	poll=HTTPRequest.new()
	add_child(poll)
	poll.timeout=4
	poll.request_completed.connect(receive_state)
	catalog=HTTPRequest.new()
	add_child(catalog)
	catalog.timeout=4
	catalog.request_completed.connect(receive_games)
	action=HTTPRequest.new()
	add_child(action)
	action.timeout=75
	action.request_completed.connect(func(_result,code,_h,body):
		var result=JSON.parse_string(body.get_string_from_utf8())
		if code>=400 or code==0: conversation.text="请求未完成："+body.get_string_from_utf8()
		elif result is Dictionary and result.has("id"):
			selected_id=result.id
			save_drafts()
			mode_label.text="继续完善刚创建的游戏"
	)
	var timer:=Timer.new()
	timer.wait_time=1
	timer.autostart=true
	timer.timeout.connect(refresh)
	add_child(timer)
	refresh()

func refresh() -> void:
	if poll.get_http_client_status()==HTTPClient.STATUS_DISCONNECTED: poll.request(endpoint+"/state",headers)
	if catalog.get_http_client_status()==HTTPClient.STATUS_DISCONNECTED: catalog.request(endpoint+"/games",headers)

func post(route: String, data: Dictionary) -> void:
	if action==null: return
	var err:=action.request(endpoint+route,headers,HTTPClient.METHOD_POST,JSON.stringify(data))
	if err!=OK: status.text="上一条请求处理中…"

func submit() -> void:
	if prompt.text.strip_edges().is_empty(): return
	last_request=prompt.text
	conversation.text="你："+last_request+"\n\n正在发送…"
	post("/create" if selected_id.is_empty() else "/continue",{"prompt":prompt.text,"id":selected_id})

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.keycode==KEY_ENTER:
		submit()
		get_viewport().set_input_as_handled()

func receive_state(_result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if code!=200: status.text="连接中断，请重新打开启动入口"; return
	var data=JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary: return
	var names={"ready":"准备好了","running":"正在创作…","validating":"正在检查游戏…","failed":"需要调整后重试","interrupted":"已停止","completed":"已完成"}
	status.text=names.get(data.get("status",""),str(data.get("status","")))
	if str(data.get("gameId",""))==selected_id:
		if not str(data.get("text","")).is_empty(): conversation.text=("你："+last_request+"\n\n" if not last_request.is_empty() else "")+"Codex："+str(data.text)
		if data.get("error")!=null: conversation.text+="\n"+str(data.error)

func receive_games(_result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if code!=200: return
	var raw:=body.get_string_from_utf8()
	var data=JSON.parse_string(raw)
	if not data is Dictionary: return
	for game in data.games:
		var listing_path:=root_path.path_join(str(game.directory)).path_join("listing.json")
		if not FileAccess.file_exists(listing_path): continue
		var listing=JSON.parse_string(FileAccess.get_file_as_string(listing_path))
		if not listing is Dictionary: continue
		for key in ["description", "synopsis", "cover"]:
			if listing.get(key) is String: game[key]=listing[key]
	raw=JSON.stringify(data)
	if raw==last_catalog: return
	last_catalog=raw
	for child in cards.get_children(): cards.remove_child(child); child.queue_free()
	for game in data.games: add_card(game)
	if not restored_card:
		restored_card=true
		for game in data.games:
			if game.id==selected_id:
				select_game(game)
				break

func add_card(game: Dictionary) -> void:
	var card:=PanelContainer.new()
	card.custom_minimum_size=Vector2(350,225)
	card.tooltip_text=str(game.get("synopsis", ""))
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("152238")
	style.set_corner_radius_all(10)
	style.content_margin_left=14
	style.content_margin_right=14
	style.content_margin_top=12
	style.content_margin_bottom=12
	card.add_theme_stylebox_override("panel",style)
	cards.add_child(card)
	card.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and game.status=="ready": post("/play",{"id":game.id})
	)
	var column:=VBoxContainer.new()
	card.add_child(column)
	if game.status=="ready" and not str(game.get("cover","")).is_empty():
		var image:=Image.load_from_file(root_path+"/"+game.cover)
		if image!=null:
			var picture:=TextureRect.new()
			picture.texture=ImageTexture.create_from_image(image)
			picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
			picture.custom_minimum_size=Vector2(320,96)
			column.add_child(picture)
	else:
		var placeholder:=PanelContainer.new()
		placeholder.custom_minimum_size=Vector2(320,96)
		column.add_child(placeholder)
		var caption:=Label.new()
		var stage_text:="预览待生成" if game.status=="ready" else ("制作中" if game.status=="creating" else "待继续创作")
		caption.text="GODOT  ·  "+stage_text+"\n工程与需求已保留"
		caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_color_override("font_color",Color("84d9c0"))
		caption.add_theme_font_size_override("font_size",15)
		placeholder.add_child(caption)
	var title:=Label.new()
	title.text=game.title
	title.clip_text=true
	title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size",20)
	column.add_child(title)
	var description:=Label.new()
	description.text=str(game.description).left(27)
	description.add_theme_font_size_override("font_size",13)
	column.add_child(description)
	var row:=HBoxContainer.new()
	column.add_child(row)
	var play:=Button.new()
	play.text="进入游戏 →" if game.status=="ready" else ("正在创建…" if game.status=="creating" else "尚未完成")
	play.disabled=game.status!="ready"
	play.pressed.connect(func(): post("/play",{"id":game.id}))
	row.add_child(play)
	var edit:=Button.new()
	edit.text="继续创作"
	edit.pressed.connect(func(): select_game(game))
	row.add_child(edit)
