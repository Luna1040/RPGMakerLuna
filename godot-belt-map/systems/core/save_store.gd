extends RefCounted
## Three versioned JSON slots. Loads never modify files or the caller's live state.
## A failed load locks that slot against autosaving until explicitly acknowledged.
const FORMAT := "rpgmakerluna-save"
const VERSION := 1
const SLOT_COUNT := 3
const MAX_BYTES := 8 * 1024 * 1024
const MAX_DEPTH := 48
const MAX_JSON_INTEGER := 9007199254740991
var directory: String
var last_error := ""
var _blocked_slots: Dictionary = {}

func _init(save_directory: String = "user://rpg_saves") -> void:
	directory = save_directory.trim_suffix("/")

func slot_path(slot: int) -> String:
	return directory.path_join("slot_%d.json" % slot)

func save_slot(slot: int, payload: Dictionary) -> bool:
	last_error = ""
	if not _valid_slot(slot):
		return _fail("Invalid save slot; expected 1..3.")
	if _blocked_slots.has(slot):
		return _fail("Slot is protected after a failed load: " + str(_blocked_slots[slot]))
	if directory.is_empty() or not _json_safe(payload):
		return _fail("Save payload needs finite JSON values, string keys, and integers within the exact JSON range; store 64-bit RNG state as text.")
	var primary := _read(slot_path(slot), slot)
	var backup := _read(slot_path(slot) + ".bak", slot)
	if primary.get("future", false) or backup.get("future", false):
		return _fail("A newer save version must not be overwritten.")
	if not primary.ok and not primary.get("missing", false) and not backup.ok:
		return _fail("Existing save is damaged; refusing to replace it with default data.")
	# Normalize JSON number types before hashing; parsing JSON turns integers into floats.
	var normalized: Dictionary = JSON.parse_string(JSON.stringify(payload, "", true, true))
	var now := int(Time.get_unix_time_from_system())
	var previous: Dictionary = primary.metadata if primary.ok else (backup.metadata if backup.ok else {})
	var envelope := {
		"format": FORMAT, "version": VERSION, "slot": slot,
		"created_at": int(previous.get("created_at", now)), "updated_at": now,
		"data": normalized, "checksum": _digest(normalized)
	}
	var text := JSON.stringify(envelope, "\t", true, true)
	if text.to_utf8_buffer().size() > MAX_BYTES:
		return _fail("Save is larger than the 8 MiB limit.")
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return _fail("Could not create the save directory.")
	var path := slot_path(slot)
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _fail("Could not open the temporary save: " + error_string(FileAccess.get_open_error()))
	file.store_string(text)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or not _read(temporary, slot).ok:
		return _fail("Temporary save failed validation; existing save is unchanged.")
	# Preserve the last valid primary, never the corrupt file recovered from a backup.
	if primary.ok:
		var backup_temporary := path + ".bak.tmp"
		if DirAccess.copy_absolute(path, backup_temporary) != OK:
			return _fail("Could not prepare the save backup.")
		if DirAccess.rename_absolute(backup_temporary, path + ".bak") != OK:
			return _fail("Could not atomically replace the save backup.")
	# Rename in the same directory is the commit point. Never delete the old primary first.
	if DirAccess.rename_absolute(temporary, path) != OK:
		return _fail("Could not atomically replace the save; previous files are retained.")
	return true

func load_slot(slot: int) -> Dictionary:
	last_error = ""
	if not _valid_slot(slot):
		last_error = "Invalid save slot; expected 1..3."
		return _failure(last_error)
	var result := _resolve(slot)
	if result.ok:
		_blocked_slots.erase(slot)
	else:
		last_error = result.error
		if not result.get("missing", false):
			_blocked_slots[slot] = last_error
	return result

func list_slots() -> Array:
	var result: Array = []
	for slot in range(1, SLOT_COUNT + 1):
		var loaded := _resolve(slot)
		result.append({
			"slot": slot, "exists": not loaded.get("missing", false),
			"ok": loaded.ok, "recovered": loaded.recovered,
			"error": loaded.error, "metadata": loaded.metadata.duplicate(true)
		})
	return result

func protect_slot(slot: int, reason: String = "Save contents failed game-state validation.") -> bool:
	## Higher-level schema validation can reject an otherwise valid JSON envelope.
	## Protect it from later autosaves instead of replacing it with default state.
	if not _valid_slot(slot):
		return _fail("Invalid save slot; expected 1..3.")
	_blocked_slots[slot] = reason if not reason.is_empty() else "Save contents failed game-state validation."
	last_error = _blocked_slots[slot]
	return true

func acknowledge_failed_load(slot: int) -> bool:
	## This only removes the session autosave lock; damaged/newer files remain protected.
	## A successful subsequent load also unlocks the slot automatically.
	if not _valid_slot(slot):
		return false
	_blocked_slots.erase(slot)
	return true

func _resolve(slot: int) -> Dictionary:
	var primary := _read(slot_path(slot), slot)
	if primary.ok or primary.get("future", false):
		return primary
	var backup := _read(slot_path(slot) + ".bak", slot)
	if backup.ok:
		backup.recovered = true
		backup.metadata["recovery_reason"] = primary.error
		return backup
	var failed := _failure("Primary: %s Backup: %s" % [primary.error, backup.error])
	failed["missing"] = primary.get("missing", false) and backup.get("missing", false)
	failed["future"] = backup.get("future", false)
	return failed

func _read(path: String, expected_slot: int) -> Dictionary:
	if not FileAccess.file_exists(path):
		var missing := _failure("No save file.")
		missing["missing"] = true
		return missing
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Save file is not readable.")
	if file.get_length() > MAX_BYTES:
		file.close()
		return _failure("Save file exceeds the size limit.")
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return _failure("Save root is not a valid JSON object.")
	var document: Dictionary = parser.data
	if not _whole_number(document.get("version")):
		return _failure("Save version is invalid.")
	if float(document.version) > VERSION:
		var future := _failure("Save was created by a newer game version.")
		future["future"] = true
		return future
	if int(document.version) != VERSION or document.get("format") != FORMAT:
		return _failure("Unsupported save format.")
	if not _whole_number(document.get("slot")) or int(document.slot) != expected_slot:
		return _failure("Save belongs to a different slot.")
	if not _whole_number(document.get("created_at")) or not _whole_number(document.get("updated_at")):
		return _failure("Save timestamps are invalid.")
	if float(document.created_at) < 0 or float(document.updated_at) < 0 or float(document.created_at) > MAX_JSON_INTEGER or float(document.updated_at) > MAX_JSON_INTEGER:
		return _failure("Save timestamps are invalid.")
	if not document.get("data") is Dictionary or not _json_safe(document.data):
		return _failure("Save payload is not a valid JSON object.")
	if not document.get("checksum") is String or document.checksum != _digest(document.data):
		return _failure("Save checksum does not match its payload.")
	return {
		"ok": true, "data": document.data.duplicate(true), "error": "", "recovered": false,
		"metadata": {"slot": expected_slot, "version": VERSION,
			"created_at": int(document.created_at), "updated_at": int(document.updated_at)}
	}

func _valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= SLOT_COUNT

func _fail(message: String) -> bool:
	last_error = message
	return false

func _failure(message: String) -> Dictionary:
	return {"ok": false, "data": {}, "error": message, "recovered": false, "metadata": {}}

func _digest(payload: Dictionary) -> String:
	return JSON.stringify(payload, "", true, true).sha256_text()

func _whole_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))

func _json_safe(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_DEPTH:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_INT:
			return value >= -MAX_JSON_INTEGER and value <= MAX_JSON_INTEGER
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for child in value:
				if not _json_safe(child, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if not key is String or not _json_safe(value[key], depth + 1):
					return false
			return true
	return false
