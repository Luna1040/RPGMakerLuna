extends SceneTree
func _initialize() -> void:
	call_deferred("run_test")
func run_test() -> void:
	var draft_path:="user://creator-drafts.json"
	var backup:=""
	var existed:=FileAccess.file_exists(draft_path)
	if existed: backup=FileAccess.get_file_as_string(draft_path)
	var home=load("res://home.tscn").instantiate()
	root.add_child(home)
	var pending={"id":"resume-test","directory":"unused","title":"未完成的世界","description":"测试","status":"paused","last_prompt":"原来的完整需求","last_reply":"已完成移动"}
	home.select_game(pending)
	assert(home.prompt.text=="原来的完整需求")
	home.prompt.text="尚未发送的补充要求"
	home.save_drafts()
	home.free()
	var restored=load("res://home.tscn").instantiate()
	root.add_child(restored)
	assert(restored.selected_id=="resume-test")
	assert(restored.prompt.text=="尚未发送的补充要求")
	restored.add_card(pending)
	var card=restored.cards.get_child(restored.cards.get_child_count()-1)
	var row=card.get_child(0).get_child(card.get_child(0).get_child_count()-1)
	assert(row.get_child(0).disabled,"Unfinished game must not be playable")
	assert(not row.get_child(1).disabled,"Resume must remain available")
	restored.free()
	if existed:
		var file:=FileAccess.open(draft_path,FileAccess.WRITE)
		file.store_string(backup)
		file.close()
	else: DirAccess.remove_absolute(draft_path)
	print("CREATOR_RESUME PASS")
	quit()
