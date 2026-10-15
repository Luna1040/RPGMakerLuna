extends CanvasLayer
## Lobby navigation stays visible; AI tools require the launcher (--ai-dev).
var panel: PanelContainer
var prompt: TextEdit
var output: TextEdit
var status: Label
var poll: HTTPRequest
var action: HTTPRequest
var endpoint := ""
var headers := PackedStringArray()
var was_paused := false
var screenshot := ""
var home_request: HTTPRequest
var home_button: Button
var home_feedback: Label
var menu_home_feedback: Label

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	layer=120
	add_home_navigation()
	if not "--ai-dev" in OS.get_cmdline_user_args():
		add_offline_menu()
		return
	var connection_path:=OS.get_environment("GAME_ASSISTANT_CONNECTION")
	if connection_path.is_empty(): connection_path=default_connection_path()
	var connection: Variant = null
	if FileAccess.file_exists(connection_path):
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(connection_path)) == OK:
			connection = parser.data
	if not valid_connection(connection):
		add_offline_menu()
		home_failed("大厅连接不可用，请从大厅入口重新进入。")
		return
	endpoint=connection.url
	headers=PackedStringArray(["Content-Type: application/json","Authorization: Bearer "+connection.token])
	var launcher:=Button.new()
	launcher.text="F1 · AI 开发助手"
	launcher.position=Vector2(1095,205)
	launcher.size=Vector2(170,36)
	launcher.pressed.connect(toggle)
	add_child(launcher)
	panel=PanelContainer.new()
	panel.position=Vector2(210,90)
	panel.size=Vector2(860,620)
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("111b2b")
	style.border_color=Color("80bfcf")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left=18
	style.content_margin_right=18
	style.content_margin_top=16
	style.content_margin_bottom=16
	panel.add_theme_stylebox_override("panel",style)
	add_child(panel)
	var box:=VBoxContainer.new()
	panel.add_child(box)
	status=Label.new()
	status.text="AI 开发助手 · 修改完成自动重启 · F1 收起"
	box.add_child(status)
	add_menu_feedback(box)
	prompt=TextEdit.new()
	prompt.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	prompt.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	prompt.placeholder_text="边玩边提需求：修复问题、调整手感、添加新内容…（Ctrl+Enter 发送）"
	prompt.custom_minimum_size=Vector2(820,140)
	box.add_child(prompt)
	var buttons:=HBoxContainer.new()
	box.add_child(buttons)
	for item in [["发送现场与需求",submit],["停止任务",interrupt],["立即重启游戏",restart],["返回游戏大厅",go_home],["返回游戏",toggle]]:
		var button:=Button.new()
		button.text=item[0]
		button.pressed.connect(item[1])
		buttons.add_child(button)
	output=TextEdit.new()
	output.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	output.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	output.editable=false
	output.custom_minimum_size=Vector2(820,400)
	output.size_flags_vertical=Control.SIZE_EXPAND_FILL
	box.add_child(output)
	panel.hide()
	poll=HTTPRequest.new()
	add_child(poll)
	poll.timeout=5
	poll.request_completed.connect(receive_state)
	action=HTTPRequest.new()
	action.timeout=75
	add_child(action)
	action.request_completed.connect(func(_result,code,_headers,body):
		if code>=400 or code==0: status.text="请求失败："+body.get_string_from_utf8()
	)
	var timer:=Timer.new()
	timer.wait_time=1
	timer.autostart=true
	timer.timeout.connect(func():
		if poll.get_http_client_status()==HTTPClient.STATUS_DISCONNECTED: poll.request(endpoint+"/state",headers)
	)
	add_child(timer)

func _input(event: InputEvent) -> void:
	if panel==null: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_F1:
			toggle()
			get_viewport().set_input_as_handled()
		elif event.keycode==KEY_ESCAPE:
			toggle()
			get_viewport().set_input_as_handled()
		elif panel.visible and prompt != null and event.keycode==KEY_ENTER and event.ctrl_pressed:
			submit()
			get_viewport().set_input_as_handled()

func toggle() -> void:
	if panel.visible:
		panel.hide()
		get_tree().paused=was_paused
	else:
		was_paused=get_tree().paused
		get_tree().paused=true
		if DisplayServer.get_name()!="headless":
			screenshot=Marshalls.raw_to_base64(get_viewport().get_texture().get_image().save_png_to_buffer())
		panel.show()
		if prompt != null:
			prompt.grab_focus()

func default_connection_path() -> String:
	return ProjectSettings.globalize_path("res://../../.game-assistant/connection.json").simplify_path()

func valid_connection(connection: Variant) -> bool:
	if not connection is Dictionary:
		return false
	return connection.get("url") is String and connection.get("token") is String and not str(connection.get("url", "")).is_empty() and not str(connection.get("token", "")).is_empty()

func add_menu_feedback(box: VBoxContainer) -> void:
	menu_home_feedback = Label.new()
	menu_home_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_home_feedback.add_theme_color_override("font_color", Color("ffd56a"))
	box.add_child(menu_home_feedback)

func add_offline_menu() -> void:
	panel = PanelContainer.new()
	panel.position = Vector2(350, 275)
	panel.size = Vector2(580, 250)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	var heading := Label.new()
	heading.text = "游戏已暂停 · Esc 返回游戏"
	heading.add_theme_font_size_override("font_size", 26)
	box.add_child(heading)
	var explanation := Label.new()
	explanation.text = "当前未连接游戏大厅。请从大厅入口进入游戏以使用返回功能。"
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(explanation)
	add_menu_feedback(box)
	for item in [["返回游戏", toggle], ["返回游戏大厅", go_home]]:
		var button := Button.new()
		button.text = item[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(item[1])
		box.add_child(button)
	panel.hide()

func submit() -> void:
	if prompt.text.strip_edges().is_empty(): return
	var context:={"scene":get_tree().current_scene.scene_file_path,"engine":Engine.get_version_info().string}
	var stage=get_tree().current_scene
	if stage.get("runtime")!=null: context["zone"]=stage.runtime.zone
	if stage.get("knight")!=null: context["player_position"]=[stage.knight.position.x,stage.knight.position.y]
	var err:=action.request(endpoint+"/task",headers,HTTPClient.METHOD_POST,JSON.stringify({"prompt":prompt.text,"context":context,"screenshot":screenshot}))
	status.text="已提交，等待 Codex…" if err==OK else "请求忙，请稍后再试"

func interrupt() -> void:
	action.request(endpoint+"/interrupt",headers,HTTPClient.METHOD_POST,"{}")

func restart() -> void:
	action.request(endpoint+"/restart",headers,HTTPClient.METHOD_POST,"{}")

func go_home() -> void:
	if home_request == null or home_button.disabled:
		return
	if endpoint.is_empty():
		home_failed("未连接大厅，请从大厅入口重新进入游戏。")
		return
	home_button.disabled = true
	home_button.text = "正在返回大厅…"
	home_feedback.text = ""
	if menu_home_feedback != null:
		menu_home_feedback.text = "正在返回大厅…"
	var error := home_request.request(endpoint+"/home",headers,HTTPClient.METHOD_POST,"{}")
	if error != OK:
		home_failed("返回请求未发出，请重试。")

func add_home_navigation() -> void:
	home_button = Button.new()
	home_button.name = "ReturnToLobby"
	home_button.text = "返回游戏大厅"
	home_button.focus_mode = Control.FOCUS_NONE
	home_button.position = Vector2(800, 38)
	home_button.size = Vector2(190, 42)
	home_button.pressed.connect(go_home)
	add_child(home_button)
	home_feedback = Label.new()
	home_feedback.position = Vector2(650, 84)
	home_feedback.size = Vector2(350, 46)
	home_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	home_feedback.add_theme_font_size_override("font_size", 15)
	home_feedback.add_theme_color_override("font_color", Color("ffd56a"))
	add_child(home_feedback)
	home_request = HTTPRequest.new()
	home_request.timeout = 8
	home_request.request_completed.connect(func(result, code, _response_headers, body):
		if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
			var message := "无法连接大厅，请重试。"
			var parser := JSON.new()
			if parser.parse(body.get_string_from_utf8()) == OK and parser.data is Dictionary:
				message = str(parser.data.get("error", message))
			home_failed(message)
		else:
			home_button.disabled = false
			home_button.text = "返回游戏大厅"
			home_feedback.text = ""
			if menu_home_feedback != null:
				menu_home_feedback.text = ""
	)
	add_child(home_request)

func home_failed(message: String) -> void:
	home_button.disabled = false
	home_button.text = "返回游戏大厅"
	home_feedback.text = message
	if menu_home_feedback != null:
		menu_home_feedback.text = message

func receive_state(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code!=200:
		status.text="桥接服务未连接，请用 AI 开发版入口启动"
		return
	var data=JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary: return
	status.text="AI 开发助手 · "+str(data.get("status",""))+" · F1 返回游戏"
	output.text=str(data.get("text",""))+"\n\n"+"\n".join(data.get("events",[]))
