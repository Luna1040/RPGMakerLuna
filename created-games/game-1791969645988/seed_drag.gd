extends Button
var seed_id: String
func _get_drag_data(_at: Vector2) -> Variant:
	var preview:=Label.new()
	preview.text=text
	set_drag_preview(preview)
	return {"seed_id":seed_id}
