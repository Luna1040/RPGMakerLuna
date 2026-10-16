extends RefCounted

static var sheets: Dictionary = {}

static func sheet(name: String) -> ImageTexture:
	if sheets.has(name): return sheets[name]
	var path := "res://assets/portraits/%s.png" % name
	if not FileAccess.file_exists(path): return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))!=OK: return null
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	sheets[name]=texture
	return texture

static func profession(name: String) -> AtlasTexture:
	var texture := sheet("classes")
	if texture==null: return null
	var index := ["刀客","剑客","枪客"].find(name)
	if index<0: index=0
	var atlas := AtlasTexture.new()
	atlas.atlas=texture
	var width := texture.get_width()/4.0
	atlas.region=Rect2(index*width,0,width,texture.get_height())
	var selection = JSON.parse_string(FileAccess.get_file_as_string("res://assets/portraits/selection.json"))
	if selection is Dictionary and selection.has("classes"):
		var r: Array=selection.classes[index]
		atlas.region=Rect2(r[0],r[1],r[2],r[3])
	return atlas

static func npc(name: String) -> AtlasTexture:
	var texture := sheet("npcs")
	if texture==null: return null
	var index := ["泫渤派门主","金香玉","韦大宝","平十指","刀剑笑","银娇龙"].find(name)
	if index<0: return null
	var atlas := AtlasTexture.new()
	atlas.atlas=texture
	var size := Vector2(texture.get_width()/3.0,texture.get_height()/2.0)
	atlas.region=Rect2(Vector2(index%3,index/3)*size,size)
	return atlas
