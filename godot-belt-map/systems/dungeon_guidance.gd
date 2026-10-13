extends CanvasLayer
var runtime
var label := Label.new()

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

func message() -> String:
	var run: Dictionary=runtime.run_state
	match str(run.phase):
		"combat":
			var remaining:=0
			for enemy in runtime.encounters.enemies:
				if enemy.state!="dead": remaining+=1
			return "%s · 第 %d / %d 轮\n消灭敌人：剩余 %d" % [runtime.Registry.title(runtime.zone),run.wave,runtime.Registry.waves(runtime.zone),remaining]
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
