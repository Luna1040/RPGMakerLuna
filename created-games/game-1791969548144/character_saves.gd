extends RefCounted

var path := "user://canosa_characters_v1.json"
var slots: Array = [null,null,null,null,null,null]
var error := ""

static func utc_plus_8(unix: int) -> String:
 return Time.get_datetime_string_from_unix_time(unix+28800)+"+08:00"

static func migrate_time(value: String) -> String:
 if value.ends_with("-08:00"):
  return utc_plus_8(Time.get_unix_time_from_datetime_string(value.left(19))+28800)
 return value

func read_slots() -> bool:
 error=""
 if not FileAccess.file_exists(path): return true
 var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
 if not parsed is Dictionary or parsed.get("version")!=1 or not parsed.get("slots") is Array or parsed.slots.size()!=6:
  error="存档格式无效，已保留原文件，禁止覆盖"
  return false
 for record in parsed.slots:
  if record!=null and (not record is Dictionary or not record.get("class") in ["战士","法师"] or not record.get("name") is String or not record.get("created_at") is String):
   error="角色资料无效，已保留原文件"
   return false
 slots=parsed.slots
 for record in slots:
  if record!=null:
   for field in ["created_at","offline_at","last_seen_at"]:
    if record.has(field): record[field]=migrate_time(str(record[field]))
 # If a previous process was interrupted, use its last saved heartbeat as an
 # explicitly estimated offline time instead of leaving a permanently online slot.
 for record in slots:
  if record!=null and record.get("online",false):
   record.offline_at=record.get("last_seen_at",record.offline_at)
   record["offline_estimated"]=true
   record["online"]=false
 return true

func write_slots() -> bool:
 if not error.is_empty(): return false
 var temp=path+".tmp"
 var file=FileAccess.open(temp,FileAccess.WRITE)
 if file==null:
  error="存档写入失败："+str(FileAccess.get_open_error())
  return false
 file.store_string(JSON.stringify({"version":1,"timezone":"UTC+08:00","slots":slots},"\t",false))
 file.flush()
 var status=file.get_error()
 file.close()
 if status!=OK:
  error="存档写入未完成"
  return false
 var absolute=ProjectSettings.globalize_path(path)
 if FileAccess.file_exists(path):
  var backup=absolute+".bak"
  if FileAccess.file_exists(backup): DirAccess.remove_absolute(backup)
  if DirAccess.rename_absolute(absolute,backup)!=OK:
   error="无法备份原存档"
   return false
 if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),absolute)!=OK:
  if FileAccess.file_exists(absolute+".bak"): DirAccess.rename_absolute(absolute+".bak",absolute)
  error="无法保存存档，原文件已保留"
  return false
 return true

func create(slot: int, name: String, profession: String, now: int) -> bool:
 name=name.strip_edges()
 if slot<0 or slot>=6 or slots[slot]!=null or not profession in ["战士","法师"] or name.is_empty() or name.length()>12:
  return false
 for c in name:
  if c.unicode_at(0)<32: return false
 slots[slot]={"name":name,"class":profession,"created_at":utc_plus_8(now),"offline_at":"","level":1,"snapshot":{}}
 if not write_slots():
  slots[slot]=null
  return false
 return true

func save_character(slot: int, snapshot: Dictionary, offline: bool, now: int) -> bool:
 if slot<0 or slot>=6 or slots[slot]==null: return false
 var before: Dictionary=slots[slot].duplicate(true)
 slots[slot].snapshot=snapshot.duplicate(true)
 slots[slot].level=snapshot.get("level",1)
 slots[slot]["last_seen_at"]=utc_plus_8(now)
 slots[slot]["online"]=not offline
 if offline:
  slots[slot].offline_at=utc_plus_8(now)
  slots[slot]["offline_estimated"]=false
 if write_slots(): return true
 slots[slot]=before
 return false

func delete_character(slot: int, confirmed: bool) -> bool:
 if not confirmed or slot<0 or slot>=6 or slots[slot]==null: return false
 var old=slots[slot]
 slots[slot]=null
 if write_slots(): return true
 slots[slot]=old
 return false
