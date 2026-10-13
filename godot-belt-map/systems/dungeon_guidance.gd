extends CanvasLayer
var runtime
var label := Label.new()
var shortcuts:=Label.new()
var room_grid: Control
var party_buttons:=HBoxContainer.new()
var summon_button:=Button.new()

func setup(service) -> void:
	runtime=service
	layer=9
	label.position=Vector2(375,95)
	label.size=Vector2(530,105)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size",20)
	label.add_theme_color_override("font_color",Color("fff0bf"))
	label.add_theme_color_override("font_outline_color",Color("091522"))
	label.add_theme_constant_override("outline_size",7)
	add_child(label)
	shortcuts.position=Vector2(28,662)
	shortcuts.add_theme_font_size_override("font_size",14)
	shortcuts.add_theme_color_override("font_outline_color",Color.BLACK)
	shortcuts.add_theme_constant_override("outline_size",5)
	shortcuts.text="队友  6 加入/离队 · 7 召唤/切换指令 · 8 复苏"
	shortcuts.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(shortcuts)
	party_buttons.position=Vector2(28,620)
	add_child(party_buttons)
	summon_button.text="召唤队友 [6]"
	summon_button.focus_mode=Control.FOCUS_NONE
	summon_button.pressed.connect(func(): runtime.demo_companion(0))
	party_buttons.add_child(summon_button)
	for item in [["召唤/指令 [7]",1],["复苏 [8]",2]]:
		var button:=Button.new()
		button.text=item[0]
		button.focus_mode=Control.FOCUS_NONE
		button.pressed.connect(runtime.demo_companion.bind(item[1]))
		party_buttons.add_child(button)
	room_grid=preload("room_grid.gd").new()
	room_grid.runtime=runtime
	add_child(room_grid)

func message() -> String:
	var run: Dictionary=runtime.run_state
	if run.get("rooms",false) and run.phase in ["ready","boon"] and int(run.wave)>0:
		return "房间已清理！拾取战利品\n前往发光的门，按 %s 进入下一间" % runtime.controls.key_name("interact")
	match str(run.phase):
		"combat":
			var remaining:=0
			for enemy in runtime.encounters.enemies:
				if enemy.state!="dead": remaining+=1
			return "%s · 第 %d / %d 间\n消灭敌人：剩余 %d · 清场开门" % [str(runtime.stage.contract.name),run.wave,runtime.Registry.waves(runtime.zone),remaining]
		"boon", "ready":
			if int(run.wave)>0:
				var reward: String = ""
				if run.phase=="boon" and not run.offers.is_empty(): reward=" · 获得"+str(runtime.BOONS[run.offers[0]].name)
				return "本轮清场！拾取战利品%s\n%d 秒后自动开始第 %d 轮" % [reward,ceili(maxf(0,runtime.wave_countdown)),int(run.wave)+1]
		"victory":
			return "副本通关！拾取战利品\n前往传送门「返回城镇」，按 %s 离开并交付任务" % runtime.controls.key_name("interact")
	return ""

func _process(_delta: float) -> void:
	if runtime==null: return
	label.visible=runtime.Registry.is_dungeon(runtime.zone) and not runtime.stage.interface.is_modal()
	label.text=message() if label.visible else ""
	shortcuts.visible=not runtime.stage.interface.is_modal()
	party_buttons.visible=shortcuts.visible
	summon_button.text="队友离队 [6]" if runtime.companion_recruited else "召唤队友 [6]"
