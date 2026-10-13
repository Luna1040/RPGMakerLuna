extends Node
## Persistent overlay survives scene disposal, so loading happens under black.
var pending: Dictionary = {}
var target_zone := "town"
var portal_entry := false
var busy := false
var veil := ColorRect.new()
var heading := Label.new()
var subtitle := Label.new()
var title_tween: Tween

func _ready() -> void:
	var layer:=CanvasLayer.new()
	layer.layer=100
	add_child(layer)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color=Color(0,0,0,0)
	veil.mouse_filter=Control.MOUSE_FILTER_IGNORE
	layer.add_child(veil)
	heading.position=Vector2(240,325)
	heading.size=Vector2(800,80)
	heading.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size",42)
	heading.add_theme_color_override("font_color",Color("f6dfab"))
	heading.add_theme_color_override("font_outline_color",Color("101827"))
	heading.add_theme_constant_override("outline_size",8)
	heading.mouse_filter=Control.MOUSE_FILTER_IGNORE
	layer.add_child(heading)
	heading.modulate.a=0
	subtitle.position=Vector2(240,403)
	subtitle.size=Vector2(800,40)
	subtitle.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	subtitle.text="正在进入区域…"
	subtitle.mouse_filter=Control.MOUSE_FILTER_IGNORE
	layer.add_child(subtitle)
	subtitle.hide()

func take() -> Dictionary:
	var result:=pending
	pending={}
	return result

func announce(title: String) -> void:
	if title_tween: title_tween.kill()
	heading.text=title
	heading.modulate.a=1
	title_tween=create_tween()
	title_tween.tween_interval(1.6)
	title_tween.tween_property(heading,"modulate:a",0.0,.65)

func change_map() -> void:
	if busy: return
	if DisplayServer.get_name()=="headless":
		get_tree().call_deferred("change_scene_to_file","res://stage.tscn")
		return
	busy=true
	veil.mouse_filter=Control.MOUSE_FILTER_STOP
	if title_tween: title_tween.kill()
	heading.modulate.a=0
	var fade:=create_tween()
	fade.tween_property(veil,"color:a",1.0,.23)
	await fade.finished
	subtitle.show()
	await RenderingServer.frame_post_draw
	var error:=get_tree().change_scene_to_file("res://stage.tscn")
	if error!=OK:
		busy=false
		if get_tree().current_scene!=null: get_tree().current_scene.runtime.transitioning=false
		pending.clear()
		veil.color.a=0
		veil.mouse_filter=Control.MOUSE_FILTER_IGNORE
		subtitle.hide()
		announce("区域加载失败，请重试")
		return
	await get_tree().process_frame
	await get_tree().process_frame
	subtitle.hide()
	fade=create_tween()
	fade.tween_property(veil,"color:a",0.0,.3)
	await fade.finished
	busy=false
	veil.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var scene=get_tree().current_scene
	if scene!=null: announce(str(scene.contract.name))
