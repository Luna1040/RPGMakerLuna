extends SceneTree

class TextureStage extends Node2D:
	var knight: Texture2D = GradientTexture2D.new()
	var hero := Vector2(320,640)
	var runtime = {"zone":"town"}

class NodeStage extends Node2D:
	var knight := Node2D.new()
	var runtime = null

func _initialize() -> void:
	var assistant = load("res://game_assistant.gd").new()
	var texture_stage := TextureStage.new()
	var context: Dictionary = assistant.build_context(texture_stage)
	assert(context["player_position"] == [320.0,640.0])
	assert(context["zone"] == "town")
	var node_stage := NodeStage.new()
	node_stage.knight.position = Vector2(12,34)
	context = assistant.build_context(node_stage)
	assert(context["player_position"] == [12.0,34.0])
	var empty_stage := Node2D.new()
	context = assistant.build_context(empty_stage)
	assert(not context.has("player_position"))
	context = assistant.build_context(null)
	assert(context.has("engine"))
	node_stage.knight.free()
	node_stage.free()
	empty_stage.free()
	texture_stage.free()
	assistant.free()
	print("PASS: texture, Node2D, empty and missing stage context")
	quit()
