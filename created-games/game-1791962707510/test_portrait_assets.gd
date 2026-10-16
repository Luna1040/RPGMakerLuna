extends SceneTree

func _initialize() -> void:
	var art = load("res://portrait_art.gd")
	assert(art.sheet("classes").get_size()==Vector2(1536,768))
	assert(art.sheet("npcs").get_size()==Vector2(1536,1024))
	for name in ["刀客","剑客","枪客","医生"]:
		var texture: AtlasTexture=art.profession(name)
		assert(texture!=null and Rect2(Vector2.ZERO,texture.atlas.get_size()).encloses(texture.region))
	assert(art.profession("医生").region==art.profession("医师").region)
	var rectangles: Array[Rect2] = []
	for name in ["泫渤派门主","金香玉","韦大宝","平十指","刀剑笑","银娇龙"]:
		var texture: AtlasTexture=art.npc(name)
		assert(texture!=null and Rect2(Vector2.ZERO,texture.atlas.get_size()).encloses(texture.region))
		assert(not texture.region in rectangles)
		rectangles.append(texture.region)
	print("PASS: four profession portraits, healer alias, six distinct NPC atlas regions, all rectangles inside actual generated images")
	quit(0)
