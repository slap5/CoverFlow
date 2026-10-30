extends RefCounted

static func plan(record: Dictionary) -> Dictionary:
	var override: String = str(record.get("launch_override", ""))
	if not override.is_empty():
		return file_plan(override)
	var identity: String = str(record.get("id", ""))
	var stored: String = str(record.get("launch_target", ""))
	if identity.begins_with("steam:"):
		var app_id: String = identity.trim_prefix("steam:")
		if app_id.is_valid_int() and int(app_id) > 0:
			return {"kind": "uri", "target": "steam://rungameid/" + app_id}
	if identity.begins_with("epic:"):
		if stored.begins_with("com.epicgames.launcher://apps/"):
			return {"kind": "uri", "target": stored}
		var app_id: String = identity.trim_prefix("epic:")
		if not app_id.is_empty():
			# Upgrade old imports by resolving the full Epic identity from its manifest.
			var folder: String = OS.get_environment("ProgramData").path_join("Epic/EpicGamesLauncher/Data/Manifests")
			var directory: DirAccess = DirAccess.open(folder)
			if directory != null:
				for filename in directory.get_files():
					if filename.get_extension() != "item":
						continue
					var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(filename)))
					if data is Dictionary and str(data.get("AppName", "")) == app_id:
						var parts: String = str(data.get("CatalogNamespace", "")) + ":" + str(data.get("CatalogItemId", "")) + ":" + app_id
						if not str(data.get("CatalogNamespace", "")).is_empty() and not str(data.get("CatalogItemId", "")).is_empty():
							return {"kind": "uri", "target": "com.epicgames.launcher://apps/" + parts.uri_encode() + "?action=launch&silent=true"}
			return {"kind": "uri", "target": "com.epicgames.launcher://apps/" + app_id.uri_encode() + "?action=launch&silent=true"}
	if identity.begins_with("xbox:"):
		var aumid: String = identity.trim_prefix("xbox:")
		var expression: RegEx = RegEx.new()
		expression.compile("^[A-Za-z0-9._-]+![A-Za-z0-9._-]+$")
		if expression.search(aumid) != null:
			return {"kind": "xbox", "target": "shell:AppsFolder\\" + aumid}
	if not stored.is_empty() and not stored.contains("://"):
		return file_plan(stored)
	if identity.begins_with("rockstar:"):
		var folder: String = str(record.get("install_path", ""))
		for name in ["PlayGTAV.exe", "PlayRDR2.exe", "LaunchGTAIV.exe"]:
			if FileAccess.file_exists(folder.path_join(name)):
				return file_plan(folder.path_join(name))
	return {"error": "Choose this game's desktop shortcut or launcher executable once using Set launch file."}

static func file_plan(path: String) -> Dictionary:
	if path.get_extension().to_lower() not in ["exe", "lnk", "url"] or not path.is_absolute_path():
		return {"error": "Choose an absolute path to a game .exe, .lnk or .url file."}
	if not FileAccess.file_exists(path):
		return {"error": "Launch file is missing. Use Set launch file to update it."}
	return {"kind": "file", "target": path}
