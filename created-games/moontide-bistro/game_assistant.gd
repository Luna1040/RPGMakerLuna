extends CanvasLayer
## Enabled only by the hackathon launcher (--ai-dev).
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

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	layer=120
	if not "--ai-dev" in OS.get_cmdline_user_args():
		queue_free()
		return
	var connection_path:=OS.get_environment("GAME_ASSISTANT_CONNECTION")
	if connection_path.is_empty(): connection_path=ProjectSettings.globalize_path("res://../.game-assistant/connection.json")
	var connection=JSON.parse_string(FileAccess.get_file_as_string(connection_path))
	if not connection is Dictionary:
		queue_free()
		return
	endpoint=connection.url
	headers=PackedStringArray(["Content-Type: application/json","Authorization: Bearer "+connection.token])
	var launcher:=Button.new()
	launcher.text="F1 · AI 开发助手"
	launcher.position=Vector2(968,775)
	launcher.size=Vector2(145,28)
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
	prompt=TextEdit.new()
	prompt.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	prompt.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	prompt.placeholder_text="边玩边提需求：修复问题、调整手感、添加新内容…（Ctrl+Enter 发送）"
	prompt.custom_minimum_size=Vector2(820,140)
	box.add_child(prompt)
	var buttons:=HBoxContainer.new()
	box.add_child(buttons)
	for item in [["发送现场与需求",submit],["停止任务",interrupt],["立即重启游戏",restart],["创作首页",go_home],["返回游戏",toggle]]:
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
		elif panel.visible and event.keycode==KEY_ESCAPE:
			toggle()
			get_viewport().set_input_as_handled()
		elif panel.visible and event.keycode==KEY_ENTER and event.ctrl_pressed:
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
		prompt.grab_focus()

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
	action.request(endpoint+"/home",headers,HTTPClient.METHOD_POST,"{}")

func receive_state(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code!=200:
		status.text="桥接服务未连接，请用 AI 开发版入口启动"
		return
	var data=JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary: return
	status.text="AI 开发助手 · "+str(data.get("status",""))+" · F1 返回游戏"
	output.text=str(data.get("text",""))+"\n\n"+"\n".join(data.get("events",[]))
