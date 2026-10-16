extends Button
var receiver: Callable
var allowed: Callable
func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("seed_id") and allowed.call()
func _drop_data(_at: Vector2, data: Variant) -> void:
	receiver.call(str(data.seed_id))
