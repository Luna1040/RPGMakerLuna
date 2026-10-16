extends RefCounted

const SLOT_COUNT := 6
var directory := "user://characters"
var last_error := ""

func timestamp(unix_time: int = -1) -> String:
	if unix_time < 0:
		unix_time = int(Time.get_unix_time_from_system())
	return Time.get_datetime_string_from_unix_time(unix_time + 8 * 3600) + "+08:00"

func slot_path(slot: int) -> String:
	return directory.path_join("slot_%d.json" % slot)

func load_slot(slot: int) -> Dictionary:
	if slot < 0 or slot >= SLOT_COUNT or not FileAccess.file_exists(slot_path(slot)):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(slot_path(slot)))
	if not data is Dictionary or not data.has_all(["name", "profession", "level", "created_at", "logged_out_at"]):
		return {"corrupt": true}
	normalize_dates(data)
	return data

func save_slot(slot: int, character: Dictionary) -> bool:
	normalize_dates(character)
	last_error = ""
	if slot < 0 or slot >= SLOT_COUNT:
		last_error = "存档位置无效"
		return false
	var target := ProjectSettings.globalize_path(directory)
	if DirAccess.make_dir_recursive_absolute(target) != OK:
		last_error = "无法创建存档目录"
		return false
	var destination := ProjectSettings.globalize_path(slot_path(slot))
	var temporary := destination + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "无法写入存档"
		return false
	character.saved_at=timestamp()
	character.save_timezone="UTC+8"
	file.store_string(JSON.stringify(character, "\t", false))
	file.flush()
	var result := file.get_error()
	file.close()
	if result != OK:
		last_error = "存档写入失败"
		return false
	if DirAccess.rename_absolute(temporary, destination) != OK:
		last_error = "无法替换存档文件"
		return false
	return true

func delete_slot(slot: int) -> bool:
	if slot < 0 or slot >= SLOT_COUNT:
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(slot))) == OK

func normalize_dates(data: Dictionary) -> void:
	for key in ["created_at","logged_out_at","saved_at"]:
		var value:=str(data.get(key,""))
		if value.ends_with("-08:00") and value.length()>=25:
			data[key]=timestamp(Time.get_unix_time_from_datetime_string(value.left(19))+8*3600)
