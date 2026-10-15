extends RefCounted
signal changed
const ACTION_CODES := {"left":KEY_A,"right":KEY_D,"up":KEY_W,"down":KEY_S,"jump":KEY_SPACE,"attack":KEY_J,"spell":KEY_K,"interact":KEY_E,"inventory":KEY_I,"map":KEY_M,"equip":KEY_Q,"skill1":KEY_1,"skill2":KEY_2,"skill3":KEY_3,"potion":KEY_4,"ether":KEY_5,"journal":KEY_L}
const DEFAULTS := {"left":KEY_LEFT,"right":KEY_RIGHT,"up":KEY_UP,"down":KEY_DOWN,"jump":KEY_C,"attack":KEY_X,"spell":KEY_R,"interact":KEY_E,"inventory":KEY_I,"map":KEY_M,"equip":KEY_F,"skill1":KEY_Q,"skill2":KEY_W,"skill3":KEY_A,"potion":KEY_4,"ether":KEY_5,"journal":KEY_L}
const TITLES := {"left":"向左","right":"向右","up":"向上","down":"向下","jump":"跳跃","attack":"攻击","spell":"施法","interact":"交互","inventory":"背包","map":"地图","equip":"拾取装备","skill1":"技能一","skill2":"技能二","skill3":"技能三","potion":"生命药水","ether":"法力药水","journal":"冒险手册"}
const PATH := "user://rpg_settings.cfg"
var keys: Dictionary = DEFAULTS.duplicate()
var master_volume := 0.55
var screen_shake := true
var fullscreen := false
var error := ""

func load_settings(path: String = PATH) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	master_volume = clampf(float(cfg.get_value("display", "volume", .55)),0,1)
	screen_shake = bool(cfg.get_value("display", "shake", true))
	fullscreen = bool(cfg.get_value("display", "fullscreen", false))
	var candidate: Dictionary = {}
	var used: Array = []
	for action in DEFAULTS:
		var code = cfg.get_value("input", action, DEFAULTS[action])
		if not code is int or not allowed_key(code) or code in used:
			candidate.clear()
			break
		candidate[action] = code
		used.append(code)
	keys = DEFAULTS.duplicate() if candidate.size() != DEFAULTS.size() or candidate == ACTION_CODES else candidate
	# Migrate only the old default pair; keep deliberate custom bindings.
	if keys.skill2 == KEY_Z and keys.skill3 == KEY_W and KEY_A not in keys.values():
		keys.skill2 = KEY_W
		keys.skill3 = KEY_A
	apply()

func save_settings(path: String = PATH) -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("display","volume",master_volume)
	cfg.set_value("display","shake",screen_shake)
	cfg.set_value("display","fullscreen",fullscreen)
	for action in keys:
		cfg.set_value("input",action,keys[action])
	var ok := cfg.save(path) == OK
	error = "" if ok else "设置写入失败"
	return ok

func apply() -> void:
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(master_volume,.0001)))
	AudioServer.set_bus_mute(0,master_volume <= 0)
	if not OS.has_feature("web") and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	changed.emit()

func allowed_key(code: int) -> bool:
	return code in [KEY_SPACE,KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN] or (code >= KEY_A and code <= KEY_Z) or (code >= KEY_0 and code <= KEY_9)

func rebind(action: String, code: int) -> bool:
	if not DEFAULTS.has(action) or not allowed_key(code):
		error = "请选择方向键、字母、数字或空格；功能键保留"
		return false
	for other in keys:
		if other != action and keys[other] == code:
			error = "该按键已用于：" + str(TITLES[other])
			return false
	keys[action] = code
	error = ""
	changed.emit()
	return true

func canonical(event: InputEventKey) -> int:
	var code := int(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
	for action in keys:
		if code == int(keys[action]):
			return int(ACTION_CODES[action])
	# Unassigned original keys must not retain their old action after remapping.
	if code in DEFAULTS.values() or code in ACTION_CODES.values():
		return 0
	return code

func movement() -> Vector2:
	return Vector2(float(Input.is_physical_key_pressed(keys.right))-float(Input.is_physical_key_pressed(keys.left)),float(Input.is_physical_key_pressed(keys.down))-float(Input.is_physical_key_pressed(keys.up))).limit_length(1)

func key_name(action: String) -> String:
	return OS.get_keycode_string(keys.get(action,0))
