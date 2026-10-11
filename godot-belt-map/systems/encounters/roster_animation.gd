extends RefCounted
## Whole-frame PNG playback. Timing math is pure and never advances gameplay.
const ROOT := "res://assets/roster/"
const IDS := ["scout","caster","elite","boss","serin"]
## Weak references share development PNGs without retaining every roster frame.
static var _raw_cache: Dictionary = {}
var character_id := ""
var directory := ""
var manifest: Dictionary = {}
var _textures: Dictionary = {}
var _standing_top := INF

func configure(id: String) -> void:
	if id == character_id:
		return
	character_id = id if id in IDS else "scout"
	directory = ROOT+character_id+"/"
	manifest.clear()
	_textures.clear()
	_standing_top = INF
	var path := directory+"animation.json"
	if FileAccess.file_exists(path):
		var decoded = JSON.parse_string(FileAccess.get_file_as_string(path))
		if decoded is Dictionary and decoded.get("actions",{}) is Dictionary:
			manifest = decoded

func clip(action: String) -> Dictionary:
	var actions: Dictionary = manifest.get("actions",{})
	return actions.get(action,{})

func has_action(action: String) -> bool:
	return not clip(action).get("frames",[]).is_empty()

static func duration_ms(action: Dictionary) -> float:
	var sum := 0.0
	for frame in action.get("frames",[]):
		sum += maxf(1.0,float(frame.get("duration_ms",100.0)))
	return sum if sum > 0.0 else maxf(1.0,float(action.get("duration_ms",1000.0)))

static func frame_at(action: Dictionary, milliseconds: float, loop: bool = false) -> int:
	var frames: Array = action.get("frames",[])
	if frames.is_empty():
		return -1
	var duration := duration_ms(action)
	var time := fposmod(milliseconds,duration) if loop else clampf(milliseconds,0.0,duration-0.00001)
	for index in frames.size():
		time -= maxf(1.0,float(frames[index].get("duration_ms",100.0)))
		if time < 0.0:
			return index
	return frames.size()-1

static func attack_time(action: Dictionary, elapsed: float, windup: float, recovery: float) -> float:
	# Retiming on either side maps the exact gameplay strike to event_ms.
	var duration := duration_ms(action)
	var impact := clampf(float(action.get("event_ms",duration*0.42)),0.0,duration-0.00001)
	if elapsed <= windup:
		return impact*clampf(elapsed/maxf(0.001,windup),0.0,1.0)
	return minf(duration-0.00001,impact+(duration-impact)*clampf((elapsed-windup)/maxf(0.001,recovery),0.0,1.0))

func sample(action: String, milliseconds: float, loop: bool = false) -> Dictionary:
	var authored := clip(action)
	var index := frame_at(authored,milliseconds,loop)
	if index < 0:
		return portrait_sample()
	var entry: Dictionary = authored.frames[index]
	var texture := texture_for(str(entry.get("file","")))
	if texture == null:
		return portrait_sample()
	var canvas: Array = manifest.get("canvas",[768,768])
	var pivot: Array = authored.get("pivot",[float(canvas[0])*0.5,float(canvas[1])*0.9])
	return {"texture":texture,"frame":index,"source_frame":entry.get("source_frame",index),"action":action,
		"pivot":Vector2(float(pivot[0]),float(pivot[1])),"scale":float(authored.get("scale",0.32)),"portrait":false}

func portrait_sample() -> Dictionary:
	var texture := texture_for(str(manifest.get("portrait","portrait.png")))
	if texture == null:
		return {}
	var size := texture.get_size()
	var pivot: Array = manifest.get("portrait_pivot",[size.x*0.5,size.y*0.96])
	return {"texture":texture,"frame":-1,"source_frame":-1,"action":"portrait",
		"pivot":Vector2(float(pivot[0]),float(pivot[1])),"scale":float(manifest.get("portrait_scale",210.0/maxf(1.0,size.y))),"portrait":true}

func texture_for(relative: String) -> Texture2D:
	if relative.is_empty() or relative.is_absolute_path() or ".." in relative:
		return null
	if _textures.has(relative):
		return _textures[relative]
	var path := directory+relative
	var storage := _storage_crop(relative)
	var stored_size := Vector2i(int(storage[2]),int(storage[3])) if storage.size() == 4 else Vector2i.ZERO
	var result: Texture2D
	if ResourceLoader.exists(path):
		result = load(path) as Texture2D
	# Immediately after publication the editor may not yet have rebuilt an
	# old full-canvas import. Never apply a crop margin to that stale texture.
	if result != null and stored_size != Vector2i.ZERO and Vector2i(result.get_size()) != stored_size:
		result = null
	if result == null and FileAccess.file_exists(path):
		var cache_key := path+":"+str(FileAccess.get_modified_time(path))+":"+str(stored_size)
		if _raw_cache.has(cache_key):
			result = _raw_cache[cache_key].get_ref() as Texture2D
		if result == null:
			var source := Image.load_from_file(path)
			if source != null and not source.is_empty():
				result = ImageTexture.create_from_image(source)
				_raw_cache[cache_key] = weakref(result)
	if result != null and not storage.is_empty():
		if Vector2i(result.get_size()) != stored_size:
			return null
		var canvas: Array = manifest.get("canvas",[768,768])
		var wrapped := AtlasTexture.new()
		wrapped.atlas = result
		wrapped.region = Rect2(Vector2.ZERO,Vector2(stored_size))
		wrapped.margin = Rect2(float(storage[0]),float(storage[1]),float(canvas[0])-stored_size.x,float(canvas[1])-stored_size.y)
		result = wrapped
	if result != null:
		_textures[relative] = result
	return result

func _storage_crop(relative: String) -> Array:
	for action in manifest.get("actions",{}).values():
		var crop = action.get("storage_crop",[])
		if not crop is Array or crop.size() != 4:
			continue
		for frame in action.get("frames",[]):
			if str(frame.get("file","")) == relative:
				return crop
	return []

static func virtual_image(texture: Texture2D) -> Image:
	# AtlasTexture.get_image() omits margin even though get_size/drawing include
	# it. Expand only for CPU QA; the GPU keeps the compact underlying texture.
	var pixels := texture.get_image()
	if not texture is AtlasTexture:
		return pixels
	var canvas := Vector2i(texture.get_size())
	var expanded := Image.create(canvas.x,canvas.y,false,Image.FORMAT_RGBA8)
	expanded.fill(Color.TRANSPARENT)
	if pixels.get_format() != Image.FORMAT_RGBA8:
		pixels.convert(Image.FORMAT_RGBA8)
	expanded.blit_rect(pixels,Rect2i(Vector2i.ZERO,pixels.get_size()),Vector2i(texture.margin.position))
	return expanded

static func virtual_alpha_bounds(texture: Texture2D) -> Rect2i:
	var used := texture.get_image().get_used_rect()
	if texture is AtlasTexture:
		used.position += Vector2i(texture.margin.position)
	return used

func standing_top() -> float:
	# One fixed standing-alpha anchor keeps labels near the head without
	# bobbing as an attack, staff, cape or hit pose changes frame bounds.
	if is_finite(_standing_top):
		return _standing_top
	var sampled := sample("stand",0.0) if has_action("stand") else portrait_sample()
	if sampled.is_empty():
		return -220.0
	var used := virtual_alpha_bounds(sampled.texture)
	_standing_top = (float(used.position.y)-float(sampled.pivot.y))*float(sampled.scale)
	return _standing_top

static func anchored_position(pivot: Vector2, scale_factor: float, facing: float) -> Vector2:
	return Vector2(-pivot.x*scale_factor*facing,-pivot.y*scale_factor)
