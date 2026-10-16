extends RefCounted

const MAX_SLOTS := 6
const PROFESSIONS := ["刀客", "剑客", "枪客"]
const LEGACY_PROFESSIONS := ["医生", "医师", "弓手"]
var directory := "user://game-1791962707510/saves"
var error := ""

static func utc_minus_8(unix_seconds: int) -> String:
	return Time.get_datetime_string_from_unix_time(unix_seconds - 8 * 3600) + "-08:00"

static func utc_plus_8(unix_seconds: int) -> String:
	return Time.get_datetime_string_from_unix_time(unix_seconds + 8 * 3600) + "+08:00"

static func normalize_times(data: Dictionary) -> Dictionary:
	for key in ["created_at","saved_at","last_offline_at"]:
		var value: String=str(data.get(key,""))
		if value.ends_with("-08:00"):
			var epoch := Time.get_unix_time_from_datetime_string(value.left(19))+8*3600
			data[key]=utc_plus_8(epoch)
	data["timezone"]="UTC+08:00"
	return data

static func valid_stamp(value: Variant, allow_empty: bool=false) -> bool:
	return value is String and ((allow_empty and value.is_empty()) or (value.length()==25 and (value.ends_with("-08:00") or value.ends_with("+08:00"))))

func path_for(slot: int) -> String:
	return directory.path_join("slot_%d.json" % slot)

func read_slot(slot: int) -> Dictionary:
	error = ""
	if slot < 1 or slot > MAX_SLOTS: return {}
	var path := path_for(slot)
	if not FileAccess.file_exists(path):
		if FileAccess.file_exists(path+".bak"):
			var backup_only = parse_file(path+".bak")
			if valid(backup_only,slot):
				error = "存档替换中断，已读取备份。"
				return normalize_profession(backup_only)
			error = "存档备份损坏，保留文件。"
		return {}
	var data = parse_file(path)
	if not valid(data, slot):
		var backup = parse_file(path + ".bak") if FileAccess.file_exists(path + ".bak") else null
		if valid(backup, slot):
			error = "主存档损坏，已读取备份。"
			return normalize_profession(backup)
		error = "存档损坏，保留原文件；不会覆盖。"
		return {}
	return normalize_profession(data)

func normalize_profession(data: Dictionary) -> Dictionary:
	if data.profession in LEGACY_PROFESSIONS:
		data["original_profession"]=data.get("original_profession",data.profession)
		data.profession="刀客"
	return normalize_times(data)

func parse_file(path: String) -> Variant:
	var parser := JSON.new()
	return parser.data if parser.parse(FileAccess.get_file_as_string(path)) == OK else null

func valid(data: Variant, slot: int) -> bool:
	if not data is Dictionary: return false
	return data.get("version") == 1 and data.get("slot") == slot and data.get("name") is String and (data.get("profession") in PROFESSIONS or data.get("profession") in LEGACY_PROFESSIONS) and number(data.get("level")) and data.level >= 1 and data.level <= 99 and valid_stamp(data.get("created_at")) and valid_stamp(data.get("last_offline_at"),true) and valid_progress(data.get("progress"))

static func display_profession(profession: String) -> String:
	return "刀客" if profession in LEGACY_PROFESSIONS else profession

func deletion_signature(slot: int) -> String:
	var text := ""
	for suffix in ["",".bak",".tmp"]:
		var path: String = path_for(slot)+suffix
		text += suffix+":"+(FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "<absent>")
	return text.sha256_text()

func delete_slot(slot: int) -> bool:
	error = ""
	if slot<1 or slot>MAX_SLOTS:
		error = "无效槽位。"
		return false
	var files: Array[String] = []
	for suffix in ["",".bak",".tmp"]:
		var path: String = path_for(slot)+suffix
		if FileAccess.file_exists(path): files.append(path)
	if files.is_empty():
		error = "该槽位已经为空。"
		return false
	# Quarantine only the three named slot files; no recursive deletion or unrelated paths.
	var destination := directory.path_join(".deleted/slot_%d_%d_%d" % [slot,int(Time.get_unix_time_from_system()),Time.get_ticks_usec()])
	if DirAccess.make_dir_recursive_absolute(destination)!=OK:
		error = "无法完成删档，请检查存档目录写入权限。"
		return false
	var moved: Array[String] = []
	for path in files:
		if DirAccess.rename_absolute(path,destination.path_join(path.get_file()))!=OK:
			for previous in moved: DirAccess.rename_absolute(destination.path_join(previous.get_file()),previous)
			error = "删档失败，已恢复原槽位。"
			return false
		moved.append(path)
	return true

func number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and number(value[0]) and number(value[1])

func valid_progress(data: Variant) -> bool:
	if not data is Dictionary: return false
	if data.has("town_services"):
		var service: Variant=data.town_services
		if not service is Dictionary or service.get("version")!=1:return false
		var items=preload("res://town_items.gd")
		if not items.valid_slots(service.get("bag"),40) or not items.valid_slots(service.get("personal"),200) or not service.get("equipped") is Dictionary:return false
		for kind in service.equipped:
			var id: String=str(service.equipped[kind])
			if not items.DATA.has(id) or items.DATA[id].get("equip")!=kind:return false
	if data.has("advancement"):
		var advancement: Variant=data.advancement
		if not advancement is Dictionary:return false
		for field in ["stage","boar","bones"]:
			if not number(advancement.get(field)) or advancement[field]!=int(advancement[field]):return false
		if advancement.stage<0 or advancement.stage>14 or advancement.boar<0 or advancement.boar>1 or advancement.bones<0 or advancement.bones>3:return false
	if data.has("kungfu"):
		var skill_data: Variant=data.kungfu
		if not skill_data is Dictionary or not skill_data.get("learned") is Array or not skill_data.get("slots") is Array: return false
		if skill_data.slots.size()!=9 or not number(skill_data.get("remaining")) or skill_data.remaining<0 or skill_data.remaining>60: return false
		if not skill_data.get("active") in ["lightness","cloud_step"]: return false
		for id in skill_data.learned:
			if not id in ["attack","lightness","cloud_step","potion","blade_10","sword_10","spear_10","mp_small","hp_medium","mp_medium","return_scroll"]: return false
		for id in skill_data.slots:
			if not id in ["","attack","lightness","cloud_step","potion","blade_10","sword_10","spear_10","mp_small","hp_medium","mp_medium","return_scroll"]: return false
	if data.has("world3d") and not valid_3d(data.world3d): return false
	if data.has("wilderness") and not valid_wilderness(data.wilderness): return false
	if not pair(data.get("player")) or not pair(data.get("facing")): return false
	for key in ["hp","qi","level","exp","coins","potions","stage","kills","elapsed"]:
		if not number(data.get(key)) or data[key] < 0: return false
	if data.stage > 3 or not data.get("state") in ["play","win","lose"]: return false
	if not data.get("quest") is bool or not data.get("message") is String: return false
	if not data.get("enemies") is Array or not data.get("drops") is Array: return false
	if data.enemies.size() > 12 or data.drops.size() > 12: return false
	for enemy in data.enemies:
		if not enemy is Dictionary or not pair(enemy.get("pos")) or not pair(enemy.get("target")) or not enemy.get("boss") is bool: return false
		for key in ["hp","max","cool","wind","flash"]:
			if not number(enemy.get(key)): return false
		if enemy.max <= 0 or enemy.hp <= 0: return false
	for drop in data.drops:
		if not drop is Dictionary or not pair(drop.get("pos")) or not number(drop.get("value")): return false
	for key in ["attack_cd","skill_cd","dash_cd","invincible"]:
		if data.has(key) and not number(data[key]): return false
	return true

func valid_wilderness(data: Variant) -> bool:
	if not data is Dictionary or (data.get("version")!=1 and data.get("version")!=2) or not data.get("lightness") is bool: return false
	if not number(data.get("kills")) or data.kills<0: return false
	if not data.get("monsters") is Array: return false
	if data.monsters.size()!=(6 if data.version==1 else 60): return false
	for record in data.monsters:
		if not record is Dictionary or not record.get("dead") is bool: return false
		if not number(record.get("hp")) or record.hp<0 or record.hp>200: return false
		if not number(record.get("respawn")) or record.respawn<0 or record.respawn>12: return false
	return true

func valid_3d(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != 1: return false
	var at = data.get("position")
	if not at is Array or at.size()!=3: return false
	for coordinate in at:
		if not number(coordinate): return false
	for key in ["yaw","pitch","zoom","enemy_hp","training","hits"]:
		if not number(data.get(key)): return false
	return data.get("rewarded") is bool and data.enemy_hp>=0 and data.enemy_hp<=100 and data.training>=0 and data.training<=3 and data.hits>=0

func write_slot(slot: int, data: Dictionary) -> bool:
	error = ""
	if slot < 1 or slot > MAX_SLOTS or not valid(data,slot):
		error = "无效角色资料或槽位。"
		return false
	normalize_times(data)
	var result := DirAccess.make_dir_recursive_absolute(directory)
	if result != OK:
		error = "无法创建存档目录：%s" % error_string(result)
		return false
	var path := path_for(slot)
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null:
		error = "无法写入存档：%s" % error_string(FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(data,"\t",true,false))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		error = "存档写入失败。"
		return false
	if FileAccess.file_exists(path):
		if valid(parse_file(path),slot):
			if FileAccess.file_exists(path+".bak"): DirAccess.remove_absolute(path+".bak")
			result = DirAccess.rename_absolute(path,path+".bak")
		else:
			# Keep the last intact backup when replacing a corrupt primary.
			result = DirAccess.remove_absolute(path)
		if result != OK:
			error = "无法备份旧档。"
			return false
	result = DirAccess.rename_absolute(path+".tmp",path)
	if result != OK:
		if FileAccess.file_exists(path+".bak"): DirAccess.rename_absolute(path+".bak",path)
		error = "无法完成存档替换。"
		return false
	return true

func create(slot: int, character_name: String, profession: String, progress: Dictionary) -> Dictionary:
	error = ""
	var clean := character_name.strip_edges()
	if slot < 1 or slot > MAX_SLOTS or FileAccess.file_exists(path_for(slot)) or FileAccess.file_exists(path_for(slot)+".bak"):
		error = "该槽位不可创建角色；已有存档不会覆盖。"
		return {}
	if clean.length() < 1 or clean.length() > 12 or not profession in PROFESSIONS:
		error = "角色名须为 1—12 字，职业须从列表选择。"
		return {}
	for i in range(clean.length()):
		if clean.unicode_at(i) < 32:
			error = "角色名不能包含控制字符。"
			return {}
	var stamp := utc_plus_8(int(Time.get_unix_time_from_system()))
	var data := {"version":1,"slot":slot,"name":clean,"profession":profession,"level":1,"created_at":stamp,"last_offline_at":"","saved_at":stamp,"timezone":"UTC+08:00","progress":progress}
	return data if write_slot(slot,data) else {}
