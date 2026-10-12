extends Node
## Crash-safe authoring checkpoint. The payload contains no provider credentials,
## Authorization headers, prompts, preview tokens or trusted review decisions.

signal state_saved(path: String)
signal state_restored(restored_runs: int, restored_jobs: int, recovered: bool)
signal state_error(message: String)

const FORMAT := "rpgmakerluna-authoring-state"
const VERSION := 1
const DEFAULT_PATH := "user://authoring_state.json"
const MAX_BYTES := 4 * 1024 * 1024
const MAX_DEPTH := 48
const MAX_JSON_INTEGER := 9007199254740991

var state_path := DEFAULT_PATH
var persistence_enabled := true
var _restoring := false
var _flush_scheduled := false
var _last_status := {"loaded":false,"saved":false,"recovered":false,"error":"","updated_at":0}

func _ready() -> void:
	# Script-driven tests opt in with enable_for_test(), keeping suites isolated.
	persistence_enabled = "--script" not in OS.get_cmdline_args()
	var orchestrator = _orchestrator()
	var transport = _transport()
	if orchestrator != null:
		orchestrator.run_created.connect(_on_state_changed)
		orchestrator.run_updated.connect(_on_state_changed)
		orchestrator.task_updated.connect(_on_state_changed)
	if transport != null:
		transport.job_updated.connect(_on_state_changed)
	if persistence_enabled: call_deferred("restore_now")

func status() -> Dictionary:
	var result: Dictionary = _last_status.duplicate(true)
	result["enabled"] = persistence_enabled
	result["path"] = state_path
	return result

func enable_for_test(path: String) -> bool:
	if not OS.is_debug_build() or path.strip_edges().is_empty(): return false
	state_path = path
	persistence_enabled = true
	return true

func flush_now() -> Dictionary:
	_flush_scheduled = false
	if not persistence_enabled or _restoring:
		return {"ok":false,"errors":["Authoring persistence is disabled or restoring."]}
	var orchestrator = _orchestrator()
	var transport = _transport()
	if orchestrator == null or transport == null:
		return _fail("Authoring services are unavailable.")
	var data := {"content_context":_registry().content_context() if _registry()!=null else {},
		"orchestrator":orchestrator.export_state(), "transport":transport.export_state()}
	if not _json_safe(data): return _fail("Authoring checkpoint contains unsupported values.")
	var normalized = JSON.parse_string(JSON.stringify(data, "", true, true))
	var now := int(Time.get_unix_time_from_system())
	var previous := _read(state_path)
	var envelope := {"format":FORMAT,"version":VERSION,
		"created_at":int(previous.get("metadata",{}).get("created_at",now)) if previous.get("ok",false) else now,
		"updated_at":now,"data":normalized,"checksum":_digest(normalized)}
	var text := JSON.stringify(envelope, "\t", true, true)
	if text.to_utf8_buffer().size() > MAX_BYTES: return _fail("Authoring checkpoint exceeds the 4 MiB limit.")
	var absolute := ProjectSettings.globalize_path(state_path)
	var directory := absolute.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return _fail("Could not create the authoring checkpoint directory.")
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return _fail("Could not open the temporary authoring checkpoint.")
	file.store_string(text)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or not _read(temporary).get("ok",false):
		return _fail("Temporary authoring checkpoint failed validation.")
	if previous.get("ok",false):
		var backup_temporary := absolute + ".bak.tmp"
		if DirAccess.copy_absolute(absolute, backup_temporary) != OK or DirAccess.rename_absolute(backup_temporary, absolute + ".bak") != OK:
			return _fail("Could not atomically update the authoring checkpoint backup.")
	if DirAccess.rename_absolute(temporary, absolute) != OK:
		return _fail("Could not atomically replace the authoring checkpoint.")
	_last_status = {"loaded":_last_status.loaded,"saved":true,"recovered":false,"error":"","updated_at":now}
	state_saved.emit(state_path)
	return {"ok":true,"errors":[],"path":state_path,"updated_at":now}

func restore_now() -> Dictionary:
	if not persistence_enabled: return {"ok":true,"loaded":false,"errors":[],"restored_runs":0,"restored_jobs":0}
	var resolved := _resolve()
	if not resolved.get("ok",false):
		if resolved.get("missing",false): return {"ok":true,"loaded":false,"errors":[],"restored_runs":0,"restored_jobs":0}
		return _fail(str(resolved.get("error","Could not restore authoring checkpoint.")))
	var data: Dictionary = resolved.data
	if not data.get("content_context") is Dictionary or _registry()==null:
		return _fail("Authoring checkpoint content context is invalid.")
	var orchestrator = _orchestrator()
	var transport = _transport()
	if orchestrator == null or transport == null: return _fail("Authoring services are unavailable.")
	_restoring = true
	var run_result: Dictionary = orchestrator.import_state(data.get("orchestrator",{}))
	var job_result: Dictionary = transport.import_state(data.get("transport",{}))
	_restoring = false
	var errors: Array = run_result.get("errors",[]).duplicate()
	errors.append_array(job_result.get("errors",[]))
	if not errors.is_empty(): return _fail("Authoring checkpoint was only partially restorable: " + "; ".join(errors))
	_last_status = {"loaded":true,"saved":false,"recovered":bool(resolved.recovered),"error":"",
		"updated_at":int(resolved.metadata.updated_at)}
	state_restored.emit(int(run_result.get("restored",0)),int(job_result.get("restored",0)),bool(resolved.recovered))
	return {"ok":true,"loaded":true,"errors":[],"restored_runs":int(run_result.get("restored",0)),
		"restored_jobs":int(job_result.get("restored",0)),"recovered":bool(resolved.recovered)}

func clear_persisted_state() -> Dictionary:
	if not persistence_enabled: return {"ok":false,"errors":["Authoring persistence is disabled."]}
	var absolute := ProjectSettings.globalize_path(state_path)
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		var target: String = absolute + suffix
		if FileAccess.file_exists(target) and DirAccess.remove_absolute(target) != OK:
			return _fail("Could not remove authoring checkpoint file: " + suffix)
	_last_status = {"loaded":false,"saved":false,"recovered":false,"error":"","updated_at":0}
	return {"ok":true,"errors":[]}

func _on_state_changed(_first = null, _second = null, _third = null) -> void:
	if not persistence_enabled or _restoring or _flush_scheduled: return
	_flush_scheduled = true
	call_deferred("_flush_deferred")

func _flush_deferred() -> void:
	if _flush_scheduled: flush_now()

func _resolve() -> Dictionary:
	var primary := _read(state_path)
	if primary.get("ok",false) or primary.get("future",false): return primary
	var backup := _read(state_path + ".bak")
	if backup.get("ok",false):
		backup.recovered = true
		return backup
	return {"ok":false,"data":{},"error":"Primary: %s Backup: %s" % [primary.error,backup.error],
		"recovered":false,"metadata":{},"missing":primary.get("missing",false) and backup.get("missing",false)}

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok":false,"data":{},"error":"No checkpoint.","recovered":false,"metadata":{},"missing":true}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok":false,"data":{},"error":"Checkpoint is unreadable.","recovered":false,"metadata":{}}
	if file.get_length() > MAX_BYTES:
		file.close()
		return {"ok":false,"data":{},"error":"Checkpoint exceeds its size limit.","recovered":false,"metadata":{}}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK or not parser.data is Dictionary: return {"ok":false,"data":{},"error":"Checkpoint is not valid JSON.","recovered":false,"metadata":{}}
	var document: Dictionary = parser.data
	if _whole_number(document.get("version")) and int(document.version) > VERSION:
		return {"ok":false,"data":{},"error":"Checkpoint was created by a newer version.","future":true,"recovered":false,"metadata":{}}
	if document.get("format") != FORMAT or not _whole_number(document.get("version")) or int(document.version) != VERSION:
		return {"ok":false,"data":{},"error":"Unsupported checkpoint format.","recovered":false,"metadata":{}}
	if not _whole_number(document.get("created_at")) or not _whole_number(document.get("updated_at")):
		return {"ok":false,"data":{},"error":"Checkpoint timestamps are invalid.","recovered":false,"metadata":{}}
	if not document.get("data") is Dictionary or not _json_safe(document.data) or document.get("checksum") != _digest(document.data):
		return {"ok":false,"data":{},"error":"Checkpoint checksum or payload is invalid.","recovered":false,"metadata":{}}
	return {"ok":true,"data":document.data.duplicate(true),"error":"","recovered":false,
		"metadata":{"created_at":int(document.created_at),"updated_at":int(document.updated_at)}}

func _digest(payload: Dictionary) -> String:
	return JSON.stringify(payload, "", true, true).sha256_text()

func _whole_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floorf(float(value))

func _json_safe(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_DEPTH: return false
	match typeof(value):
		TYPE_NIL,TYPE_BOOL,TYPE_STRING: return true
		TYPE_INT: return value>=-MAX_JSON_INTEGER and value<=MAX_JSON_INTEGER
		TYPE_FLOAT: return is_finite(value)
		TYPE_ARRAY:
			for child in value:
				if not _json_safe(child,depth+1): return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if not key is String or not _json_safe(value[key],depth+1): return false
			return true
	return false

func _fail(message: String) -> Dictionary:
	_last_status.error = message
	state_error.emit(message)
	return {"ok":false,"errors":[message]}

func _registry(): return get_node_or_null("/root/ContentRegistry")
func _orchestrator(): return get_node_or_null("/root/AuthoringOrchestrator")
func _transport(): return get_node_or_null("/root/AgentTransportService")
