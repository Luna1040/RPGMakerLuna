extends SceneTree

const NAMES = ["head","torso_blue","hair","cape_blue","near_upper_arm","near_forearm","far_upper_arm","far_forearm","near_thigh","near_lower","far_thigh","far_lower","sword","torso_red","cape_red","joint"]

func _initialize() -> void:
	var atlas := Image.load_from_file("res://assets/knight-parts-v1.png")
	print("PART_ATLAS_SIZE ",atlas.get_size())
	var manifest := {"source":"knight-parts-v1.png","parts":{},"logical_character_height":220,"generator":"built-in imagegen; fixed 4x4 cutout atlas"}
	for i in range(16):
		var col := i%4
		var row := i/4
		var start := Vector2i(floori(col*atlas.get_width()/4.0),floori(row*atlas.get_height()/4.0))
		var end := Vector2i(floori((col+1)*atlas.get_width()/4.0),floori((row+1)*atlas.get_height()/4.0))
		# The generated sword spills into the empty left margin of the next tile.
		if i == 12:
			end.x = floori(atlas.get_width()*.292)
		var cell := atlas.get_region(Rect2i(start,end-start))
		var rect := alpha_bounds(cell)
		assert(rect.size.x > 5 and rect.size.y > 5,"Missing part: "+NAMES[i])
		var piece := cell.get_region(rect)
		var path := "res://assets/%s.png" % NAMES[i]
		assert(piece.save_png(path) == OK)
		manifest.parts[NAMES[i]] = {"path":path,"size":[piece.get_width(),piece.get_height()],"source_rect":[start.x+rect.position.x,start.y+rect.position.y,rect.size.x,rect.size.y]}
		if NAMES[i] in ["near_lower","far_lower"]:
			var prefix: String = NAMES[i].trim_suffix("_lower")
			var top := piece.get_region(Rect2i(0,0,piece.get_width(),floori(piece.get_height()*.80)))
			var boot_y := floori(piece.get_height()*.70)
			var boot := piece.get_region(Rect2i(0,boot_y,piece.get_width(),piece.get_height()-boot_y))
			top.save_png("res://assets/%s_shin.png" % prefix)
			boot.save_png("res://assets/%s_boot.png" % prefix)
			for suffix in ["shin","boot"]:
				manifest.parts[prefix+"_"+suffix] = {"path":"res://assets/%s_%s.png" % [prefix,suffix],"derived_from":NAMES[i]}
	var f := FileAccess.open("res://assets/parts.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest,"\t"))
	print("CUTOUT_ASSETS_READY ",manifest.parts.size()," original raster parts and derived shin/boot crops")
	quit()

func alpha_bounds(img: Image) -> Rect2i:
	# Find the dominant connected component so neighboring tile fragments do
	# not expand the crop. Pixels inside the chosen rectangle stay untouched.
	var width := img.get_width()
	var height := img.get_height()
	var visited := PackedByteArray()
	visited.resize(width*height)
	var best_count := 0
	var best := Rect2i()
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var start := y*width+x
			if visited[start] != 0 or img.get_pixel(x,y).a <= .55:
				continue
			var queue: Array[int] = [start]
			visited[start] = 1
			var low := Vector2i(x,y)
			var high := low
			var cursor := 0
			while cursor < queue.size():
				var index := queue[cursor]
				cursor += 1
				var p := Vector2i(index%width,index/width)
				low = low.min(p)
				high = high.max(p)
				for offset in [Vector2i(-1,0),Vector2i(1,0),Vector2i(0,-1),Vector2i(0,1),Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(1,1)]:
					var q: Vector2i = p+offset
					if q.x < 0 or q.x >= width or q.y < 0 or q.y >= height:
						continue
					var next := q.y*width+q.x
					if visited[next] == 0 and img.get_pixelv(q).a > .55:
						visited[next] = 1
						queue.append(next)
			if queue.size() > best_count:
				best_count = queue.size()
				best = Rect2i(low,high-low+Vector2i.ONE)
	return best
