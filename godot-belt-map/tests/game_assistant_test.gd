extends SceneTree

func _initialize() -> void:
	call_deferred("run_test")

func run_test() -> void:
	var assistant=root.get_node_or_null("GameAssistant")
	assert(assistant!=null)
	await process_frame
	assert(is_instance_valid(assistant) and assistant.panel!=null)
	assert(not paused)
	assistant.toggle()
	assert(paused and assistant.panel.visible)
	assistant.prompt.text="测试文字输入不会触发移动或攻击"
	assistant.toggle()
	assert(not paused and not assistant.panel.visible)
	paused=true
	assistant.toggle()
	assistant.toggle()
	assert(paused,"Closing panel must preserve pre-existing pause")
	paused=false
	assistant.receive_state(0,200,PackedStringArray(),JSON.stringify({"status":"completed","text":"连接正常","events":["文件修改完成"]}).to_utf8_buffer())
	assert("连接正常" in assistant.output.text)
	# Long commands without whitespace must wrap, not create a horizontal scrollbar.
	for child in assistant.get_children():
		if child is Timer: child.stop()
	assistant.poll.cancel_request()
	assistant.toggle()
	var long_line="C:/Users/developer/"+"long_directory_name/".repeat(30)+"command.exe"
	assistant.prompt.text=long_line
	assistant.output.text=long_line+"\n"+"长回复应该完整换行显示，不需要横向拖动。".repeat(30)
	for frame in range(3): await process_frame
	for editor in [assistant.prompt,assistant.output]:
		assert(editor.get_line_wrap_count(0)>0,"Long paths must wrap")
		assert(not editor.get_h_scroll_bar().visible,"Horizontal scrolling must not be needed")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../.game-assistant/panel-review.png"))
	print("GAME_ASSISTANT_TEST PASS")
	quit()
