extends Node
## Transitional scene: the previous gameplay scene is already gone before the
## campaign registry is changed. No gameplay nodes are created here.

func _ready() -> void:
	var service = get_node_or_null("/root/CampaignSessionService")
	if service == null:
		push_error("CampaignSessionService is unavailable.")
		get_tree().call_deferred("change_scene_to_file", "res://stage.tscn")
		return
	var result: Dictionary = service.commit_pending_launch()
	if not result.ok:
		push_warning("Campaign launch failed; official content was restored: " + "; ".join(result.errors))
	get_tree().call_deferred("change_scene_to_file", "res://stage.tscn")
