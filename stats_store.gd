extends RefCounted
# Separate from the library so changing artwork cannot overwrite tracked time.
var path: String = "user://coverflow_stats.json"
var data: Dictionary = {}
var blocked: bool = false
var error: String = ""

func load_data() -> void:
 if not FileAccess.file_exists(path): return
 var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
 if not parsed is Dictionary or parsed.get("version", 0) != 1 or not parsed.get("games") is Dictionary:
  blocked = true
  error = "Stats file could not be read. It has been left untouched."
  return
 data = parsed["games"]

func get_stats(id: String) -> Dictionary:
 var value: Variant = data.get(id, {})
 return value if value is Dictionary else {}

func apply_snapshot(game_id: String, snapshot: Dictionary) -> bool:
 if blocked or not snapshot.get("started", false): return false
 var token: String = str(snapshot.get("session", ""))
 if token.is_empty(): return false
 var record: Dictionary = get_stats(game_id).duplicate(true)
 var total: float = maxf(0.0, float(snapshot.get("seconds", 0.0)))
 if not is_finite(total): return false
 # One session ID per launch; repeated polling and final messages are idempotent.
 if str(record.get("session_id", "")) != token:
  record["sessions"] = int(record.get("sessions", 0)) + 1
  record["session_id"] = token
  record["session_seconds"] = 0.0
 var previous: float = float(record.get("session_seconds", 0.0))
 record["seconds"] = maxf(0.0, float(record.get("seconds", 0.0))) + maxf(0.0, total - previous)
 record["session_seconds"] = maxf(previous, total)
 record["last_session"] = record["session_seconds"]
 record["last_played"] = str(snapshot.get("last_played", record.get("last_played", "")))
 var updated: Dictionary = data.duplicate(true)
 updated[game_id] = record
 if save_data(updated):
  data = updated
  return true
 return false

func save_data(updated: Dictionary) -> bool:
 var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
 if f == null:
  error = "Could not save playtime. Check free space and folder permissions."
  return false
 f.store_string(JSON.stringify({"version":1,"games":updated}, "\t"))
 f.flush()
 var result := f.get_error()
 f.close()
 if result != OK:
  error = "Could not write playtime."
  return false
 if FileAccess.file_exists(path) and DirAccess.copy_absolute(path, path + ".bak") != OK:
  error = "Could not back up playtime; previous stats were kept."
  return false
 if DirAccess.rename_absolute(path + ".tmp", path) != OK:
  error = "Could not save playtime; previous stats were kept."
  return false
 error = ""
 return true

static func duration(seconds: float) -> String:
 var minutes: int = int(maxf(0.0, seconds) / 60.0)
 if minutes < 1: return "< 1m" if seconds > 0 else "0m"
 return "%dh %02dm" % [minutes / 60, minutes % 60] if minutes >= 60 else "%dm" % minutes
