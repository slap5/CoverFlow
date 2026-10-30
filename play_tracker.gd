extends Node
signal changed
const StatsStore = preload("res://stats_store.gd")
var store = StatsStore.new()
var game_id: String = ""
var game_title: String = ""
var state: String = "idle"
var message: String = "Play a game to start tracking."
var pid: int = -1
var result_path: String = ""
var request_path: String = ""
var last_payload: String = ""
var poll_time: float = 0
var since_update: float = 0

func _ready() -> void:
 store.load_data()
 if store.blocked: message = store.error

func is_busy() -> bool:
 return pid != -1

func begin(record: Dictionary, plan: Dictionary) -> void:
 if is_busy() or store.blocked: return
 if OS.get_name() != "Windows": return
 game_id = str(record["id"])
 game_title = str(record.get("name", "Game"))
 var executable: String = str(record.get("tracking_exe", ""))
 var folder: String = str(record.get("install_path", ""))
 # A chosen tracking executable is strongest. Otherwise prefer the game's install folder,
 # since a launcher EXE may hand off to a different game binary in a subdirectory.
 if executable.is_empty() and folder.is_empty() and plan.get("kind", "") == "file" and str(plan.get("target", "")).get_extension().to_lower() == "exe":
  executable = str(plan["target"])
 if executable.is_empty() and folder.is_empty():
  message = "Set Track EXE once to enable playtime for this game."
  state = "unconfigured"
  changed.emit()
  return
 var token: String = "%d_%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
 request_path = "user://tracking_" + token + ".json"
 result_path = "user://tracking_" + token + "_result.json"
 var request: Dictionary = {"session":token,"parent_pid":OS.get_process_id(),"executable":executable,"install_path":folder}
 var script_file := FileAccess.open("user://track_game.ps1", FileAccess.WRITE)
 var request_file := FileAccess.open(request_path, FileAccess.WRITE)
 if script_file == null or request_file == null:
  message = "Could not prepare playtime tracking."
  state = "error"
  changed.emit()
  return
 script_file.store_string(FileAccess.get_file_as_string("res://track_game.ps1"))
 script_file.close()
 request_file.store_string(JSON.stringify(request))
 request_file.close()
 var powershell: String = OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
 pid = OS.create_process(powershell, PackedStringArray(["-NoLogo","-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",ProjectSettings.globalize_path("user://track_game.ps1"),"-RequestPath",ProjectSettings.globalize_path(request_path),"-ResultPath",ProjectSettings.globalize_path(result_path)]), false)
 state = "waiting" if pid >= 0 else "error"
 message = "Waiting for " + game_title + "…" if pid >= 0 else "Could not start playtime tracking."
 last_payload = ""
 since_update = 0
 changed.emit()

func _process(delta: float) -> void:
 if pid == -1: return
 poll_time += delta
 since_update += delta
 if poll_time < 0.5: return
 poll_time = 0
 read_snapshot()
 if not OS.is_process_running(pid):
  read_snapshot()
  if state in ["waiting", "running", "checking"]:
   state = "error"
   message = "Tracker stopped unexpectedly. Last saved playtime was kept."
  pid = -1
  cleanup()
  changed.emit()
 elif since_update > 25:
  message = "Tracking is not responding. Last saved time was kept."
  state = "error"
  stop()

func read_snapshot() -> void:
 if result_path.is_empty() or not FileAccess.file_exists(result_path): return
 var payload := FileAccess.get_file_as_string(result_path)
 if payload == last_payload: return
 var snapshot: Variant = JSON.parse_string(payload)
 if not snapshot is Dictionary: return
 last_payload = payload
 since_update = 0
 state = str(snapshot.get("state", "waiting"))
 message = str(snapshot.get("message", ""))
 store.apply_snapshot(game_id, snapshot)
 if not store.error.is_empty(): message = store.error
 changed.emit()

func stop() -> void:
 if pid == -1: return
 read_snapshot()
 var f := FileAccess.open(request_path + ".stop", FileAccess.WRITE)
 if f != null: f.store_string("stop"); f.close()
 # This PID belongs only to our read-only monitor, never the game or launcher.
 if OS.is_process_running(pid): OS.kill(pid)
 pid = -1
 state = "ended"
 message = "Tracking stopped; saved time kept. The game is still running."
 cleanup()
 changed.emit()

func cleanup() -> void:
 for path in [request_path,result_path,request_path+".stop",result_path+".tmp"]:
  if not path.is_empty() and FileAccess.file_exists(path): DirAccess.remove_absolute(path)

func _exit_tree() -> void:
 stop()
