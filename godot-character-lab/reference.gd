extends SceneTree

func _initialize() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/character.json"))
	var sheet := Image.create(768,768,false,Image.FORMAT_RGBA8)
	var map := [["idle",0],["walk",0],["walk",1],["walk",2],["walk",3],["slash",0],["slash",1],["slash",2],["slash",5]]
	for index in range(9):
		var record: Dictionary = data.animations[map[index][0]].frames[map[index][1]]
		var layer: Dictionary = record.layers.body
		var pose := Image.load_from_file(layer.path)
		pose.resize(pose.get_width()*3,pose.get_height()*3,Image.INTERPOLATE_NEAREST)
		var cell := Vector2i((index%3)*256,(index/3)*256)
		var offset := Vector2i(layer.offset[0]*3,layer.offset[1]*3)
		sheet.blit_rect(pose,Rect2i(Vector2i.ZERO,pose.get_size()),cell+Vector2i(128,238)+offset)
	assert(sheet.save_png("res://assets/pose-reference.png") == OK)
	print("REFERENCE_READY: 9 original poses, fixed floor and hand coordinates")
	quit()
