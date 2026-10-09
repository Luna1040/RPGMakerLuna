extends SceneTree

# Original deterministic pixel poses. Export cropped PNGs, never infer anchors
# from the opaque bounds: offsets always refer to the same floor origin.
const SIZE := Vector2i(192, 128)
const ORIGIN := Vector2i(80, 104)
const INK := Color("192536")
var img: Image
var manifest := {"version": 1, "pixel_scale": 1, "origin": [80, 104], "animations": {}, "layers": [], "weapons": {}}

func _initialize() -> void:
	var layer_names := ["cape", "hair_back_gold", "hair_back_copper", "body", "boots_knight", "boots_scout", "torso_knight", "torso_scout", "hair_front_gold", "hair_front_copper", "grip", "effect"]
	manifest.layers = layer_names
	for animation in ["idle", "walk", "slash"]:
		var count := 1 if animation == "idle" else (4 if animation == "walk" else 6)
		var records := []
		for frame in range(count):
			var pose := make_pose(animation, frame)
			var record := {"duration": 0.20 if animation == "walk" else (0.5 if animation == "idle" else [0.18, 0.14, 0.08, 0.10, 0.14, 0.20][frame]), "layers": {}, "attachments": {"hand": point_array(pose.hand), "head": point_array(pose.head)}, "weapon_angle": pose.sword_angle, "events": []}
			if animation == "slash" and frame == 2:
				record.events = ["swing", "hit_window"]
			for layer in layer_names:
				img = Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
				paint_layer(layer, pose, animation, frame)
				var rect := img.get_used_rect()
				if rect.size == Vector2i.ZERO:
					continue
				var folder := "res://assets/frames/%s/%s" % [layer, animation]
				DirAccess.make_dir_recursive_absolute(folder)
				var path := "%s/%02d.png" % [folder, frame]
				assert(img.get_region(rect).save_png(path) == OK)
				record.layers[layer] = {"path": path, "offset": point_array(rect.position - ORIGIN), "size": point_array(rect.size)}
			records.append(record)
		manifest.animations[animation] = {"loop": animation != "slash", "frames": records}
	# Each weapon is authored ONCE, independent of animation frame dimensions.
	for weapon in ["steel", "gold"]:
		img = Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
		paint_layer("sword", {"hand": Vector2.ZERO, "sword_angle": 0.0}, "idle", 0)
		if weapon == "gold":
			for y in range(SIZE.y):
				for x in range(SIZE.x):
					if img.get_pixel(x,y) == Color("9cbcd8"):
						img.set_pixel(x,y,Color("ddb45d"))
		var rect := img.get_used_rect()
		DirAccess.make_dir_recursive_absolute("res://assets/weapons")
		var path := "res://assets/weapons/%s.png" % weapon
		assert(img.get_region(rect).save_png(path) == OK)
		manifest.weapons[weapon] = {"path": path, "grip": point_array(ORIGIN-rect.position), "blade_length": 26, "scale": 1}
	var file := FileAccess.open("res://assets/character.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("ASSETS_READY: original poses, cropped PNG layers, explicit offsets and events")
	quit()

func point_array(p) -> Array:
	return [int(p.x), int(p.y)]

func make_pose(animation: String, frame: int) -> Dictionary:
	var pose := {"head": Vector2(1, -53), "shoulder": Vector2(2, -41), "hip": Vector2(0, -24), "near_knee": Vector2(4, -13), "near_ankle": Vector2(5, -3), "far_knee": Vector2(-4, -13), "far_ankle": Vector2(-5, -3), "elbow": Vector2(8, -32), "hand": Vector2(13, -26), "sword_angle": 0.62}
	if animation == "walk":
		# Near leg is always the light leg; far leg is always the dark leg.
		var nk := [Vector2(8,-13), Vector2(3,-13), Vector2(-8,-14), Vector2(-5,-17)]
		var na := [Vector2(14,-3), Vector2(0,-3), Vector2(-12,-3), Vector2(-6,-10)]
		var fk := [Vector2(-7,-14), Vector2(-5,-17), Vector2(7,-13), Vector2(3,-13)]
		var fa := [Vector2(-12,-3), Vector2(-6,-10), Vector2(14,-3), Vector2(0,-3)]
		pose.near_knee = nk[frame]
		pose.near_ankle = na[frame]
		pose.far_knee = fk[frame]
		pose.far_ankle = fa[frame]
	if animation == "slash":
		pose.near_knee = Vector2(9,-13)
		pose.near_ankle = Vector2(15,-3)
		pose.far_knee = Vector2(-7,-14)
		pose.far_ankle = Vector2(-11,-3)
		pose.elbow = [Vector2(-5,-40), Vector2(0,-48), Vector2(13,-41), Vector2(14,-30), Vector2(9,-31), Vector2(8,-32)][frame]
		pose.hand = [Vector2(-9,-46), Vector2(5,-53), Vector2(24,-42), Vector2(22,-24), Vector2(16,-24), Vector2(13,-26)][frame]
		pose.sword_angle = [-2.2, -1.2, 0.10, 0.78, 0.65, 0.62][frame]
	return pose

func pixel(x: int, y: int, color: Color) -> void:
	var at := Vector2i(x, y) + ORIGIN
	if at.x >= 0 and at.y >= 0 and at.x < SIZE.x and at.y < SIZE.y:
		img.set_pixelv(at, color)

func polygon(points: Array, color: Color) -> void:
	var packed := PackedVector2Array(points)
	var min_p := Vector2(999,999)
	var max_p := Vector2(-999,-999)
	for p in packed:
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	for y in range(floori(min_p.y), ceili(max_p.y) + 1):
		for x in range(floori(min_p.x), ceili(max_p.x) + 1):
			if Geometry2D.is_point_in_polygon(Vector2(x+0.5,y+0.5), packed):
				pixel(x,y,color)

func box(at: Vector2, size: Vector2, color: Color) -> void:
	for y in range(roundi(at.y), roundi(at.y + size.y)):
		for x in range(roundi(at.x), roundi(at.x + size.x)):
			pixel(x,y,color)

func oval(center: Vector2, radius: Vector2, color: Color) -> void:
	for y in range(floori(center.y-radius.y), ceili(center.y+radius.y)+1):
		for x in range(floori(center.x-radius.x), ceili(center.x+radius.x)+1):
			if Vector2((x-center.x)/radius.x, (y-center.y)/radius.y).length_squared() <= 1.0:
				pixel(x,y,color)

func limb(a: Vector2, b: Vector2, width: float, color: Color) -> void:
	var normal := (b-a).normalized().orthogonal() * width * 0.5
	polygon([a+normal,b+normal,b-normal,a-normal],color)
	oval(a,Vector2.ONE*width*0.5,color)
	oval(b,Vector2.ONE*width*0.5,color)

func outlined_limb(a: Vector2, b: Vector2, width: float, color: Color) -> void:
	limb(a,b,width+2,INK)
	limb(a,b,width,color)

func leg(hip: Vector2, knee: Vector2, ankle: Vector2, color: Color) -> void:
	outlined_limb(hip,knee,5,color)
	outlined_limb(knee,ankle,3,color)
	box(ankle+Vector2(-2,-1),Vector2(8,4),INK)
	box(ankle+Vector2(-1,0),Vector2(6,2),color)

func paint_layer(layer: String, p: Dictionary, animation: String, frame: int) -> void:
	var near_color := Color("acbeca")
	var far_color := Color("64798e")
	if layer == "grip":
		box(p.hand+Vector2(-1,-1),Vector2(3,3),Color("d1dae0"))
		return
	if layer == "body":
		leg(p.hip+Vector2(-2,0),p.far_knee,p.far_ankle,far_color)
		outlined_limb(Vector2(-3,-40),Vector2(-5,-30),3,far_color)
		leg(p.hip+Vector2(2,0),p.near_knee,p.near_ankle,near_color)
		polygon([Vector2(-5,-42),Vector2(5,-42),Vector2(6,-34),Vector2(3,-29),Vector2(5,-23),Vector2(-5,-23),Vector2(-3,-30),Vector2(-6,-36)],INK)
		polygon([Vector2(-4,-40),Vector2(4,-40),Vector2(4,-34),Vector2(2,-29),Vector2(3,-25),Vector2(-3,-25),Vector2(-2,-31),Vector2(-4,-35)],near_color)
		box(Vector2(-4,-28),Vector2(8,5),Color("40536c"))
		box(Vector2(-4,-39),Vector2(8,7),Color("40536c"))
		outlined_limb(p.shoulder,p.elbow,4,near_color)
		outlined_limb(p.elbow,p.hand,3,near_color)
		oval(p.hand,Vector2(2,2),Color("d1dae0"))
		box(Vector2(-1,-47),Vector2(4,6),near_color)
		oval(p.head,Vector2(6,8),INK)
		oval(p.head+Vector2(1,0),Vector2(5,7),near_color)
		box(p.head+Vector2(5,0),Vector2(2,3),near_color)
		pixel(int(p.head.x+4),int(p.head.y-1),INK)
		pixel(int(p.head.x+4),int(p.head.y+3),Color("63778b"))
		return
	if layer.begins_with("boots_"):
		var scout := layer.ends_with("scout")
		var light := Color("a97950") if scout else Color("c9d6e4")
		var dark := Color("684c39") if scout else Color("6b819b")
		for side in ["far","near"]:
			var knee: Vector2 = p[side+"_knee"]
			var ankle: Vector2 = p[side+"_ankle"]
			var c := dark if side == "far" else light
			outlined_limb(knee.lerp(ankle,0.35),ankle,4,c)
			box(ankle+Vector2(-3,-1),Vector2(10,4),INK)
			box(ankle+Vector2(-2,0),Vector2(8,2),c)
			if side == "near":
				limb(knee.lerp(ankle,0.40)+Vector2(-1,0),ankle+Vector2(-1,0),1,Color("e1bf69"))
		return
	if layer.begins_with("torso_"):
		var scout := layer.ends_with("scout")
		var c := Color("559686") if scout else Color("a9bdd5")
		var shade := Color("305c63") if scout else Color("566d91")
		polygon([Vector2(-5,-42),Vector2(5,-42),Vector2(6,-35),Vector2(3,-29),Vector2(7,-21),Vector2(-6,-21),Vector2(-3,-30),Vector2(-6,-36)],INK)
		polygon([Vector2(-4,-40),Vector2(4,-40),Vector2(4,-35),Vector2(1,-29),Vector2(5,-23),Vector2(-4,-23),Vector2(-2,-31),Vector2(-4,-35)],c)
		polygon([Vector2(-4,-40),Vector2(-1,-40),Vector2(-1,-30),Vector2(-3,-23),Vector2(-4,-23),Vector2(-2,-31)],shade)
		box(Vector2(-4,-29),Vector2(8,2),Color("d6b365"))
		pixel(1,-28,Color("f4dd99"))
		outlined_limb(p.shoulder,p.elbow,5,c)
		outlined_limb(p.elbow,p.hand,3,shade)
		oval(p.shoulder,Vector2(4,3),INK)
		oval(p.shoulder,Vector2(3,2),c)
		pixel(int(p.shoulder.x),int(p.shoulder.y-1),Color("eff1cf"))
		oval(p.hand,Vector2(2,2),Color("d1dae0"))
		return
	if layer == "cape":
		polygon([Vector2(-4,-42),Vector2(-9,-38),Vector2(-11,-27),Vector2(-15,-12),Vector2(-7,-15),Vector2(-3,-25)],INK)
		polygon([Vector2(-5,-40),Vector2(-8,-37),Vector2(-9,-27),Vector2(-13,-15),Vector2(-8,-17),Vector2(-5,-27)],Color("3759a2"))
		limb(Vector2(-9,-34),Vector2(-12,-17),1,Color("6c92d4"))
		return
	if layer.begins_with("hair_"):
		var copper := layer.ends_with("copper")
		var c := Color("d88650") if copper else Color("edc566")
		var shade := Color("995437") if copper else Color("a37737")
		if layer.begins_with("hair_back"):
			polygon([Vector2(-3,-59),Vector2(-8,-56),Vector2(-8,-48),Vector2(-12,-44),Vector2(-15,-32),Vector2(-9,-35),Vector2(-6,-45),Vector2(-2,-48)],INK)
			polygon([Vector2(-4,-57),Vector2(-6,-54),Vector2(-6,-48),Vector2(-10,-43),Vector2(-12,-35),Vector2(-9,-38),Vector2(-5,-47),Vector2(-3,-49)],shade)
			limb(Vector2(-7,-48),Vector2(-11,-38),2,c)
		else:
			polygon([Vector2(-5,-57),Vector2(-3,-62),Vector2(3,-62),Vector2(7,-57),Vector2(7,-53),Vector2(3,-55),Vector2(0,-54),Vector2(-3,-50),Vector2(-5,-52)],INK)
			polygon([Vector2(-4,-56),Vector2(-2,-60),Vector2(3,-60),Vector2(5,-57),Vector2(5,-55),Vector2(2,-57),Vector2(0,-56),Vector2(-3,-52)],c)
			limb(Vector2(-2,-58),Vector2(2,-59),1,Color("fff1af") if not copper else Color("f3c080"))
		return
	if layer == "sword":
		var direction := Vector2.from_angle(p.sword_angle)
		var normal := direction.orthogonal()
		var h: Vector2 = p.hand
		limb(h-direction*3,h+direction*3,3,INK)
		limb(h-direction*3,h+direction*2,1,Color("be8550"))
		limb(h+direction*4-normal*5,h+direction*4+normal*5,3,INK)
		limb(h+direction*4-normal*4,h+direction*4+normal*4,1,Color("f5ce70"))
		polygon([h+direction*5+normal*3,h+direction*27+normal*2,h+direction*32,h+direction*27-normal*2,h+direction*5-normal*3],INK)
		polygon([h+direction*6+normal*2,h+direction*26+normal,h+direction*30,h+direction*26-normal,h+direction*6-normal*2],Color("9cbcd8"))
		limb(h+direction*6,h+direction*28,1,Color("eef6ff"))
		return
	if layer == "effect" and animation == "slash" and frame in [2,3]:
		var outer := []
		var inner := []
		var center := Vector2(8,-37)
		var start := -1.25 if frame == 2 else -0.15
		for i in range(17):
			var angle := start + i / 16.0 * 1.6
			outer.append(center+Vector2.from_angle(angle)*43)
			inner.push_front(center+Vector2.from_angle(angle)*35)
		polygon(outer+inner,Color("58bed9",0.70))
		outer = []
		inner = []
		for i in range(17):
			var angle := start + i / 16.0 * 1.6
			outer.append(center+Vector2.from_angle(angle)*41)
			inner.push_front(center+Vector2.from_angle(angle)*39)
		polygon(outer+inner,Color("dbfbff",0.95))
