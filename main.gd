extends Node3D

const CoverEditor = preload("cover_editor.gd")
const AppTheme = preload("app_theme.gd")
const PlayTracker = preload("res://play_tracker.gd")
const StatsPanel = preload("res://stats_panel.gd")
const LaunchService = preload("launch_service.gd")

# Library records are data; the scene only displays them.
const CASE_SPACING: float = 1.9
const STRIP_HEIGHT: float = 100.0
const PIXELS_PER_CASE: float = 180.0
const SAVE_PATH: String = "user://coverflow_library.json"
const SCAN_RESULT: String = "user://coverflow_scan.json"
const SCAN_LIMIT_MS: int = 90000

var cover_paths: Array[String] = [
	"res://covers/game_1.jpg", "res://covers/game_2.jpg",
	"res://covers/game_3.jpg", "res://covers/game_4.jpg",
	"res://covers/game_5.png"
]
var games: Array[Dictionary] = []
var cases: Array[Node3D] = []
var candidates: Array[Dictionary] = []
var checkboxes: Array[CheckBox] = []
var scroll_position: float = 0.0
var selected_index: int = 0
var scrolling: bool = false
var demo_mode: bool = true
var save_blocked: bool = false
var title_label: Label
var status_label: Label
var scroll_strip: Panel
var importer: Window
var result_list: VBoxContainer
var scan_status: Label
var scan_notes: TextEdit
var scan_button: Button
var add_button: Button
var search_box: LineEdit
var source_filter: OptionButton
var cover_button: Button
var manual_dialog: FileDialog
var cover_dialog: FileDialog
var scan_pid: int = -1
var scan_started: int = 0
var scan_poll: float = 0.0
var scan_note_text: String = ""
var cover_game_id: String = ""
var cover_editor: Window
var ui_root: Control
var source_label: Label
var empty_hint: Label
var library_count: Label
var carousel_count: Label
var play_button: Button
var launch_file_button: Button
var launch_dialog: FileDialog
var migration_dialog: FileDialog
var remove_dialog: ConfirmationDialog
var about_dialog: AcceptDialog
var launch_game_id: String = ""
var remove_game_id: String = ""
var launch_pid: int = -1
var launch_started: int = 0
var launch_title: String = ""
var launch_debounce: int = 0
var tracker: Node
var game_menu: MenuButton
var display_dialog: Window
var case_size: float = 1.0
var stats_collapsed: bool = false
var width_slider: HSlider
var height_slider: HSlider
var size_slider: HSlider
var display_game_id: String = ""
var original_art: Dictionary = {}
var loading_art_controls: bool = false
var stats_panel: PanelContainer
var tracking_dialog: FileDialog
var tracking_game_id: String = ""
var pending_track_record: Dictionary = {}
var pending_track_plan: Dictionary = {}

@onready var original_case: Node3D = $GameCase


func _ready() -> void:
	original_case.hide()
	original_case.set_process_input(false)
	original_case.set_process_unhandled_input(false)
	# Preserve the authored CSG children when duplicating the case template.
	load_library()
	var preferences := ConfigFile.new()
	if preferences.load("user://display.cfg") == OK:
		case_size = 1.0
		stats_collapsed = bool(preferences.get_value("display", "stats_collapsed", false))
	tracker = PlayTracker.new()
	add_child(tracker)
	create_interface()
	tracker.changed.connect(refresh_stats)
	create_importer()
	cover_editor = CoverEditor.new()
	add_child(cover_editor)
	cover_editor.setup(self, ui_root.theme)
	create_display_dialog()
	rebuild_cases()
	stats_panel.set_collapsed(stats_collapsed)


func load_library() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		demo_mode = false
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not parsed is Dictionary or parsed.get("version", 0) != 1 or not parsed.get("games") is Array:
		save_blocked = true
		return
	var seen: Dictionary = {}
	for value in parsed["games"]:
		if not value is Dictionary or str(value.get("id", "")).is_empty() or str(value.get("name", "")).is_empty():
			save_blocked = true
			games.clear()
			return
		var identity: String = str(value["id"])
		if not seen.has(identity):
			games.append(value)
			seen[identity] = true
	demo_mode = false


func save_library(records: Array[Dictionary]) -> bool:
	if save_blocked:
		return false
	var temporary: String = SAVE_PATH + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": 1, "games": records}, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return false
	# Keep the last good save before replacing it.
	if FileAccess.file_exists(SAVE_PATH):
		if DirAccess.copy_absolute(SAVE_PATH, SAVE_PATH + ".bak") != OK:
			return false
	return DirAccess.rename_absolute(temporary, SAVE_PATH) == OK


func display_records() -> Array[Dictionary]:
	if not demo_mode:
		return games
	var demos: Array[Dictionary] = []
	for index in range(cover_paths.size()):
		demos.append({"id": "demo:%d" % index, "name": "Demo case %d" % (index + 1), "source": "Demo", "cover": cover_paths[index]})
	return demos


func rebuild_cases() -> void:
	for old_case in cases:
		remove_child(old_case)
		old_case.queue_free()
	cases.clear()
	var records: Array[Dictionary] = display_records()
	for index in range(records.size()):
		var game_case: Node3D = original_case.duplicate() as Node3D
		add_child(game_case)
		game_case.show()
		game_case.rotation = Vector3(0.0, -0.15, 0.0)
		game_case.position = Vector3(index * CASE_SPACING, 0, 0)
		game_case.set_process_unhandled_input(false)
		cases.append(game_case)
		var cover_path: String = str(records[index].get("cover", ""))
		if not cover_path.is_empty() and FileAccess.file_exists(cover_path):
			add_cover(game_case, cover_path, records[index])
		else:
			add_placeholder(game_case, str(records[index].get("name", "Game")))
		apply_art_dimensions(game_case, records[index])
	selected_index = clampi(selected_index, 0, maxi(cases.size() - 1, 0))
	scroll_position = float(selected_index)
	update_selection()
	if save_blocked:
		status_label.text = "Saved library could not be read. Import is disabled to protect it; see INSTALL.md."
	else:
		status_label.text = "Add your installed games. Choose the ones you want to keep." if demo_mode else "%d games saved" % games.size()


func add_placeholder(game_case: Node3D, game_name: String) -> void:
	var hue: float = float(absi(game_name.hash()) % 100) / 100.0
	var gradient: Gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color.from_hsv(hue, 0.55, 0.48), Color("101c2a")])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2.ONE
	var front: MeshInstance3D = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(1.36, 1.96)
	front.mesh = quad
	front.position.z = 0.078
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	front.material_override = material
	game_case.add_child(front)
	var label: Label3D = Label3D.new()
	label.text = game_name
	label.outline_size = 0
	label.font_size = 48
	label.pixel_size = 0.004
	label.width = 290.0
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.position = Vector3(0, 0.05, 0.083)
	game_case.add_child(label)
	var badge: Label3D = Label3D.new()
	badge.text = "C O V E R F L O W"
	badge.outline_size = 0
	badge.font_size = 24
	badge.pixel_size = 0.0025
	badge.modulate = Color("b8d9d5")
	badge.position = Vector3(0, 0.82, 0.083)
	game_case.add_child(badge)
	var foot: Label3D = Label3D.new()
	foot.text = "YOUR COLLECTION"
	foot.outline_size = 0
	foot.font_size = 22
	foot.pixel_size = 0.0025
	foot.position = Vector3(0, -0.82, 0.083)
	game_case.add_child(foot)


func make_button(parent: Node, caption: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func create_interface() -> void:
	var app_theme: Theme = AppTheme.create()
	get_window().theme = app_theme
	var interface: CanvasLayer = CanvasLayer.new()
	add_child(interface)
	ui_root = Control.new()
	ui_root.theme = app_theme
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interface.add_child(ui_root)
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var header: HBoxContainer = HBoxContainer.new()
	ui_root.add_child(header)
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 40
	header.offset_right = -40
	header.offset_top = 26
	header.offset_bottom = 82
	var logo: TextureRect = TextureRect.new()
	logo.texture = load("res://icon.svg")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(56, 56)
	header.add_child(logo)
	var brand: VBoxContainer = VBoxContainer.new()
	brand.add_theme_constant_override("separation", 0)
	header.add_child(brand)
	ui_label(brand, "COVERFLOW", 36, AppTheme.TEXT).add_theme_font_override("font", preload("res://assets/Anton-Regular.ttf"))
	ui_label(brand, "YOUR GAMES. ONE PLACE.", 10, AppTheme.MUTED)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	library_count = ui_label(header, "", 14, AppTheme.MUTED)
	var find: Button = make_button(header, "+  Find games", open_importer)
	find.theme_type_variation = "PrimaryButton"
	var fullscreen_button: Button = make_button(header, "Full screen", toggle_fullscreen)
	fullscreen_button.tooltip_text = "F11 to toggle full screen; Escape to leave it"
	var settings: MenuButton = MenuButton.new()
	settings.text = "Menu"
	header.add_child(settings)
	var menu: PopupMenu = settings.get_popup()
	menu.add_item("Open saved library folder", 0)
	menu.add_item("Import previous library…", 1)
	menu.add_separator()
	menu.add_item("About CoverFlow", 2)
	menu.add_item("Exit", 3)
	menu.id_pressed.connect(_on_menu)
	var divider: ColorRect = ColorRect.new()
	divider.color = Color("213140")
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(divider)
	divider.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	divider.offset_left = 40
	divider.offset_right = -40
	divider.offset_top = 104
	divider.offset_bottom = 105
	var collection: Label = ui_label(ui_root, "THE COLLECTION", 12, AppTheme.ACCENT)
	collection.position = Vector2(42, 115)
	var hint: Label = ui_label(ui_root, "Drag a cover to turn it around", 13, AppTheme.MUTED)
	hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	hint.offset_left = -300
	hint.offset_right = -40
	hint.offset_top = 100
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_label = ui_label(ui_root, "", 30, AppTheme.TEXT)
	title_label.add_theme_font_override("font", preload("res://assets/Anton-Regular.ttf"))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	title_label.offset_left = 60
	title_label.anchor_right = 0.59
	title_label.offset_right = -15
	title_label.offset_top = -260
	title_label.offset_bottom = -220
	source_label = ui_label(ui_root, "", 13, AppTheme.ACCENT)
	source_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	source_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	source_label.anchor_right = 0.59
	source_label.offset_top = -220
	source_label.offset_bottom = -199
	var controls: HBoxContainer = HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	ui_root.add_child(controls)
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	controls.anchor_right = 0.59
	controls.offset_left = 24
	controls.offset_right = -12
	controls.offset_top = -190
	controls.offset_bottom = -145
	play_button = make_button(controls, "PLAY GAME", launch_selected)
	play_button.theme_type_variation = "PrimaryButton"
	play_button.custom_minimum_size = Vector2(170, 46)
	game_menu = MenuButton.new()
	game_menu.text = "⚙"
	game_menu.tooltip_text = "Game settings"
	game_menu.custom_minimum_size = Vector2(46, 46)
	controls.add_child(game_menu)
	var actions := game_menu.get_popup()
	for caption in ["Edit artwork size", "Upload local cover", "Set launch file", "Tracking executable", "Stop tracking", "Remove from collection"]:
		actions.add_item(caption)
	actions.about_to_popup.connect(func() -> void:
		var unavailable: bool = demo_mode or games.is_empty() or save_blocked
		for index in range(0, 6): actions.set_item_disabled(index, unavailable)
		actions.set_item_disabled(3, unavailable or tracker.is_busy())
		actions.set_item_disabled(4, not tracker.is_busy())
	)
	actions.id_pressed.connect(func(id: int) -> void:
		match id:
			0: open_display_settings()
			1: choose_cover()
			2: choose_launch_file()
			3: choose_tracking_file()
			4: tracker.stop()
			5: ask_remove_game()
	)
	var secondary: HBoxContainer = HBoxContainer.new()
	secondary.alignment = BoxContainer.ALIGNMENT_CENTER
	ui_root.add_child(secondary)
	secondary.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	secondary.anchor_right = 0.59
	secondary.offset_left = 24
	secondary.offset_right = -12
	secondary.offset_top = -142
	secondary.offset_bottom = -106
	cover_button = make_button(secondary, "Local cover", choose_cover)
	launch_file_button = make_button(secondary, "Set launch file", choose_launch_file)
	var remove_button: Button = make_button(secondary, "Remove", ask_remove_game)
	secondary.hide()
	remove_button.tooltip_text = "Remove from CoverFlow only; does not uninstall the game"
	status_label = ui_label(ui_root, "", 12, AppTheme.MUTED)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	status_label.offset_left = 30
	status_label.offset_right = -30
	status_label.anchor_right = 0.59
	status_label.offset_top = -292
	status_label.offset_bottom = -264
	scroll_strip = Panel.new()
	scroll_strip.add_theme_stylebox_override("panel", AppTheme.box(Color("1c1e1c"), Color("625e4c"), 0))
	ui_root.add_child(scroll_strip)
	scroll_strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	scroll_strip.offset_top = -STRIP_HEIGHT
	scroll_strip.gui_input.connect(_on_strip_input)
	for right_side in [false, true]:
		var sticker_art := TextureRect.new()
		var atlas := AtlasTexture.new()
		atlas.atlas = preload("res://assets/stickers.png")
		atlas.region = Rect2(1366 if right_side else 0, 180 if right_side else 130, 682, 220)
		sticker_art.texture = atlas
		sticker_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sticker_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		sticker_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scroll_strip.add_child(sticker_art)
		sticker_art.anchor_left = 0.5 if right_side else 0.0
		sticker_art.anchor_right = 1.0 if right_side else 0.5
		sticker_art.anchor_bottom = 1.0
		sticker_art.offset_left = 225 if right_side else 0
		sticker_art.offset_right = 0 if right_side else -225
	var strip_center: HBoxContainer = HBoxContainer.new()
	strip_center.alignment = BoxContainer.ALIGNMENT_CENTER
	strip_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll_strip.add_child(strip_center)
	strip_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	make_button(strip_center, "‹", func() -> void: navigate(-1))
	var strip_text: VBoxContainer = VBoxContainer.new()
	strip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip_text.custom_minimum_size.x = 320
	strip_text.alignment = BoxContainer.ALIGNMENT_CENTER
	strip_center.add_child(strip_text)
	carousel_count = ui_label(strip_text, "", 14, AppTheme.TEXT)
	carousel_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var instructions: Label = ui_label(strip_text, "DRAG TO BROWSE  /  ARROW KEYS TO STEP", 10, AppTheme.MUTED)
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	make_button(strip_center, "›", func() -> void: navigate(1))
	cover_dialog = FileDialog.new()
	cover_dialog.theme = ui_root.theme
	cover_dialog.title = "Choose a full back / spine / front wrap"
	cover_dialog.access = FileDialog.ACCESS_FILESYSTEM
	cover_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	cover_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Cover images"])
	add_child(cover_dialog)
	cover_dialog.file_selected.connect(set_cover)
	cover_dialog.canceled.connect(update_selection)
	launch_dialog = FileDialog.new()
	launch_dialog.theme = ui_root.theme
	launch_dialog.title = "Choose the game's executable or desktop shortcut"
	launch_dialog.access = FileDialog.ACCESS_FILESYSTEM
	launch_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	launch_dialog.filters = PackedStringArray(["*.exe, *.lnk, *.url ; Games and shortcuts"])
	add_child(launch_dialog)
	launch_dialog.file_selected.connect(set_launch_file)
	launch_dialog.canceled.connect(update_selection)
	migration_dialog = FileDialog.new()
	migration_dialog.theme = ui_root.theme
	migration_dialog.title = "Import an existing coverflow_library.json"
	migration_dialog.access = FileDialog.ACCESS_FILESYSTEM
	migration_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	migration_dialog.filters = PackedStringArray(["*.json ; CoverFlow library"])
	add_child(migration_dialog)
	migration_dialog.file_selected.connect(migrate_library)
	migration_dialog.canceled.connect(update_selection)
	remove_dialog = ConfirmationDialog.new()
	remove_dialog.theme = ui_root.theme
	remove_dialog.title = "Remove from CoverFlow?"
	remove_dialog.dialog_text = "This removes the library entry and keeps the installed game untouched."
	add_child(remove_dialog)
	remove_dialog.confirmed.connect(remove_selected_game)
	remove_dialog.canceled.connect(update_selection)
	about_dialog = AcceptDialog.new()
	about_dialog.theme = ui_root.theme
	about_dialog.title = "CoverFlow 0.5"
	about_dialog.dialog_text = "Your games. One place.\nBuilt with Godot Engine.\nCover artwork: local images only.\nLauncher accounts and installed clients are still required.\n\nF11: full screen  •  Left / Right: browse  •  Enter: play\nSaved games and covers stay in your Windows user profile."
	add_child(about_dialog)
	about_dialog.confirmed.connect(update_selection)
	empty_hint = ui_label(ui_root, "Make room for your favorites.\nFind installed games to start your collection.", 23, AppTheme.MUTED)
	empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	empty_hint.offset_left = -380
	empty_hint.offset_right = -30
	empty_hint.anchor_left = 0.0
	empty_hint.anchor_right = 0.59
	empty_hint.offset_left = 30
	empty_hint.offset_top = -120
	empty_hint.offset_bottom = 20
	create_stage()
	create_animated_background()
	stats_panel = StatsPanel.new()
	ui_root.add_child(stats_panel)
	stats_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stats_panel.anchor_left = 0.61
	stats_panel.offset_left = 0
	stats_panel.offset_right = -28
	stats_panel.offset_top = 120
	stats_panel.offset_bottom = -125
	stats_panel.setup(self)
	tracking_dialog = FileDialog.new()
	tracking_dialog.title = "Select the actual game EXE to track (not its launcher)"
	tracking_dialog.access = FileDialog.ACCESS_FILESYSTEM
	tracking_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	tracking_dialog.filters = PackedStringArray(["*.exe ; Game executable"])
	tracking_dialog.theme = ui_root.theme
	add_child(tracking_dialog)
	tracking_dialog.file_selected.connect(set_tracking_file)
	tracking_dialog.canceled.connect(update_selection)


func ui_label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func create_stage() -> void:
	var stage: MeshInstance3D = MeshInstance3D.new()
	var shape: CylinderMesh = CylinderMesh.new()
	shape.top_radius = 1.15
	shape.bottom_radius = 1.22
	shape.height = 0.055
	shape.radial_segments = 96
	stage.mesh = shape
	stage.position = Vector3(-get_viewport().get_visible_rect().size.aspect() * 0.88, -1.08, 0)
	stage.name = "CaseStage"
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("181916")
	material.roughness = 1.0
	stage.material_override = material
	add_child(stage)
	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 1.16
	torus.outer_radius = 1.175
	ring.mesh = torus
	ring.scale.y = 0.3
	ring.position = Vector3(-get_viewport().get_visible_rect().size.aspect() * 0.88, -1.055, 0)
	ring.name = "CaseRing"
	var glow: StandardMaterial3D = StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color("948244")
	ring.material_override = glow
	add_child(ring)


func create_importer() -> void:
	importer = Window.new()
	importer.theme = ui_root.theme
	importer.title = "Find and select games"
	importer.size = Vector2i(900, 540)
	importer.min_size = Vector2i(600, 400)
	importer.exclusive = true
	importer.transient = true
	importer.visible = false
	add_child(importer)
	importer.close_requested.connect(close_importer)
	var margin: MarginContainer = MarginContainer.new()
	importer.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	var column: VBoxContainer = VBoxContainer.new()
	margin.add_child(column)
	var actions: HBoxContainer = HBoxContainer.new()
	column.add_child(actions)
	scan_button = make_button(actions, "Scan installed games", start_scan)
	make_button(actions, "Browse for a game", browse_manual)
	var filters: HBoxContainer = HBoxContainer.new()
	column.add_child(filters)
	search_box = LineEdit.new()
	search_box.placeholder_text = "Search found games…"
	search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(search_box)
	search_box.text_changed.connect(func(_text: String) -> void: apply_filters())
	source_filter = OptionButton.new()
	for source in ["All launchers", "Steam", "Epic Games", "Xbox / Microsoft Store", "Rockstar Games", "GOG Galaxy", "EA app", "Ubisoft Connect", "Manual"]:
		source_filter.add_item(source)
	filters.add_child(source_filter)
	source_filter.item_selected.connect(func(_index: int) -> void: apply_filters())
	scan_status = Label.new()
	scan_status.text = "Scan to find installed games. Nothing is selected automatically."
	column.add_child(scan_status)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	result_list = VBoxContainer.new()
	result_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(result_list)
	scan_notes = TextEdit.new()
	scan_notes.editable = false
	scan_notes.custom_minimum_size.y = 72
	scan_notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	column.add_child(scan_notes)
	var footer: HBoxContainer = HBoxContainer.new()
	column.add_child(footer)
	make_button(footer, "Select All Visible", func() -> void: select_visible(true))
	make_button(footer, "Deselect All", func() -> void: select_visible(false))
	add_button = make_button(footer, "Add Selected (0)", import_selected)
	make_button(footer, "Cancel", close_importer)
	add_button.disabled = true
	manual_dialog = FileDialog.new()
	manual_dialog.title = "Choose a game executable or shortcut"
	manual_dialog.access = FileDialog.ACCESS_FILESYSTEM
	manual_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	manual_dialog.filters = PackedStringArray(["*.exe, *.lnk, *.url ; Games and shortcuts"])
	importer.add_child(manual_dialog)
	manual_dialog.file_selected.connect(add_manual_candidate)


func open_importer() -> void:
	scrolling = false
	importer.popup_centered_clamped(Vector2i(900, 540), 0.92)
	update_selection()
	if candidates.is_empty() and scan_pid == -1:
		start_scan()


func close_importer() -> void:
	cancel_scan()
	# Cancel discards pending choices, never imports them.
	for checkbox in checkboxes:
		checkbox.button_pressed = false
	importer.hide()
	update_selection()


func browse_manual() -> void:
	manual_dialog.popup_centered_ratio(0.8)


func normalized_path(value: String) -> String:
	return value.replace("\\", "/").trim_suffix("/").to_lower()


func already_added(record: Dictionary) -> bool:
	for existing in games:
		if str(existing.get("id", "")) == str(record.get("id", "")):
			return true
		var path: String = str(record.get("install_path", ""))
		if not path.is_empty() and normalized_path(path) == normalized_path(str(existing.get("install_path", ""))):
			return true
	return false


func add_manual_candidate(path: String) -> void:
	var identity: String = "manual:" + normalized_path(path)
	for record in candidates:
		if record.get("id", "") == identity:
			return
	candidates.append({"id": identity, "name": path.get_file().get_basename(), "source": "Manual", "install_path": "", "launch_target": path, "cover": ""})
	render_candidates()


func start_scan() -> void:
	if scan_pid != -1:
		return
	if OS.get_name() != "Windows":
		scan_status.text = "Automatic scanning requires Windows. Browse still works."
		return
	var script_path: String = get_script().resource_path.get_base_dir().path_join("scan_games.ps1")
	if not FileAccess.file_exists(script_path):
		scan_status.text = "Missing scan_games.ps1 — place it beside main.gd."
		return
	var source: String = FileAccess.get_file_as_string(script_path)
	var local_script: String = "user://scan_games.ps1"
	var file: FileAccess = FileAccess.open(local_script, FileAccess.WRITE)
	if file == null:
		scan_status.text = "Could not prepare scanner in the app data folder."
		return
	file.store_string(source)
	file.close()
	if FileAccess.file_exists(SCAN_RESULT):
		if DirAccess.remove_absolute(SCAN_RESULT) != OK:
			scan_status.text = "Could not clear the previous scan result."
			return
	var windows_root: String = OS.get_environment("SystemRoot")
	var powershell: String = windows_root.path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	var arguments: PackedStringArray = ["-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path(local_script), "-OutputPath", ProjectSettings.globalize_path(SCAN_RESULT)]
	scan_pid = OS.create_process(powershell, arguments, false)
	if scan_pid < 0:
		scan_status.text = "Windows PowerShell could not start. Try Browse for a game."
		return
	scan_started = Time.get_ticks_msec()
	scan_button.disabled = true
	scan_status.text = "Scanning Steam, Epic, Xbox, Rockstar, GOG, EA and Ubisoft…"
	scan_notes.text = "Scanning is read-only. You can cancel at any time."


func poll_scan() -> void:
	if scan_pid == -1:
		return
	if Time.get_ticks_msec() - scan_started > SCAN_LIMIT_MS:
		cancel_scan()
		scan_status.text = "Scan timed out. Try again or use Browse for a game."
		return
	if OS.is_process_running(scan_pid):
		return
	scan_pid = -1
	scan_button.disabled = false
	var result: Variant = null
	if FileAccess.file_exists(SCAN_RESULT):
		result = JSON.parse_string(FileAccess.get_file_as_string(SCAN_RESULT))
	if not result is Dictionary or not result.get("games") is Array:
		scan_status.text = "Scan failed. Windows may have blocked PowerShell; Browse is available."
		return
	var retained_manual: Array[Dictionary] = []
	for candidate in candidates:
		if candidate.get("source", "") == "Manual":
			retained_manual.append(candidate)
	candidates.clear()
	var seen: Dictionary = {}
	for value in result["games"]:
		if value is Dictionary and not str(value.get("id", "")).is_empty() and not seen.has(value["id"]):
			candidates.append(value)
			seen[value["id"]] = true
	candidates.append_array(retained_manual)
	scan_note_text = ""
	for note in result.get("notes", []):
		scan_note_text += str(note) + "\n"
	scan_notes.text = scan_note_text
	render_candidates()


func cancel_scan() -> void:
	if scan_pid != -1 and OS.is_process_running(scan_pid):
		OS.kill(scan_pid)
	scan_pid = -1
	if is_instance_valid(scan_button):
		scan_button.disabled = false


func render_candidates() -> void:
	# Preserve choices when adding a manual candidate or refreshing results.
	var checked: Dictionary = {}
	for checkbox in checkboxes:
		if checkbox.button_pressed:
			checked[str(checkbox.get_meta("game_id"))] = true
	for child in result_list.get_children():
		result_list.remove_child(child)
		child.queue_free()
	checkboxes.clear()
	for record in candidates:
		var checkbox: CheckBox = CheckBox.new()
		var duplicate: bool = already_added(record)
		checkbox.text = "%s — %s%s" % [str(record.get("name", "Game")), str(record.get("source", "Unknown")), "  (Already added)" if duplicate else ""]
		checkbox.tooltip_text = str(record.get("install_path", record.get("launch_target", "")))
		checkbox.disabled = duplicate or save_blocked
		checkbox.set_meta("game_id", str(record["id"]))
		checkbox.button_pressed = checked.has(str(record["id"])) and not checkbox.disabled
		checkbox.toggled.connect(func(_pressed: bool) -> void: update_import_count())
		result_list.add_child(checkbox)
		checkboxes.append(checkbox)
	apply_filters()


func apply_filters() -> void:
	var query: String = search_box.text.strip_edges().to_lower()
	var source: String = source_filter.get_item_text(source_filter.selected)
	var visible_count: int = 0
	for index in range(checkboxes.size()):
		var record: Dictionary = candidates[index]
		var matches: bool = (query.is_empty() or str(record.get("name", "")).to_lower().contains(query)) and (source_filter.selected == 0 or str(record.get("source", "")) == source)
		checkboxes[index].visible = matches
		if matches:
			visible_count += 1
	scan_status.text = "%d found • %d shown. Check games, then Add Selected." % [candidates.size(), visible_count]
	if save_blocked:
		scan_status.text = "Import disabled: saved library is unreadable. See INSTALL.md."
	update_import_count()


func select_visible(selected: bool) -> void:
	for checkbox in checkboxes:
		if not checkbox.disabled and (checkbox.visible or not selected):
			checkbox.button_pressed = selected
	update_import_count()


func update_import_count() -> void:
	var count: int = 0
	for checkbox in checkboxes:
		if checkbox.button_pressed and not checkbox.disabled:
			count += 1
	add_button.text = "Add Selected (%d)" % count
	add_button.disabled = count == 0 or save_blocked


func import_selected() -> void:
	var updated: Array[Dictionary] = games.duplicate(true)
	var identifiers: Dictionary = {}
	var paths: Dictionary = {}
	for record in updated:
		identifiers[str(record["id"])] = true
		if not str(record.get("install_path", "")).is_empty():
			paths[normalized_path(str(record["install_path"]))] = true
	for index in range(checkboxes.size()):
		if not checkboxes[index].button_pressed or checkboxes[index].disabled:
			continue
		var record: Dictionary = candidates[index]
		var path: String = normalized_path(str(record.get("install_path", "")))
		if identifiers.has(str(record["id"])) or (not path.is_empty() and paths.has(path)):
			continue
		updated.append(record.duplicate(true))
		identifiers[str(record["id"])] = true
		if not path.is_empty():
			paths[path] = true
	if not save_library(updated):
		scan_status.text = "Could not save. Nothing was added; check folder permissions."
		return
	games = updated
	demo_mode = false
	selected_index = 0
	close_importer()
	rebuild_cases()
	render_candidates()


func choose_cover() -> void:
	if demo_mode or games.is_empty() or save_blocked:
		return
	cover_editor.show_for_game(games[selected_index])


func set_cover(path: String) -> void:
	var image: Image = Image.new()
	if image.load(path) != OK:
		status_label.text = "Could not open that image."
		update_selection()
		return
	var destination_dir: String = "user://covers"
	DirAccess.make_dir_recursive_absolute(destination_dir)
	var destination: String = destination_dir.path_join(cover_game_id.sha256_text() + ".png")
	if image.save_png(destination) != OK:
		status_label.text = "Could not save the cover image."
		update_selection()
		return
	var updated: Array[Dictionary] = games.duplicate(true)
	for record in updated:
		if str(record["id"]) == cover_game_id:
			record["cover"] = destination
			record["cover_layout"] = "wrap"
			record.erase("back_cover")
			record.erase("artwork")
	if save_library(updated):
		games = updated
		rebuild_cases()
	else:
		status_label.text = "Could not save the cover assignment."
	update_selection()


func update_selection() -> void:
	var modal: bool = (is_instance_valid(importer) and importer.visible) or (is_instance_valid(cover_dialog) and cover_dialog.visible) or (is_instance_valid(cover_editor) and cover_editor.visible) or launch_dialog.visible or migration_dialog.visible or remove_dialog.visible or about_dialog.visible or (is_instance_valid(tracking_dialog) and tracking_dialog.visible) or (is_instance_valid(display_dialog) and display_dialog.visible)
	var records: Array[Dictionary] = display_records()
	title_label.text = str(records[selected_index].get("name", "Game")) if not records.is_empty() else "Your next favorite game starts here"
	source_label.text = str(records[selected_index].get("source", "")).to_upper() + "  /  YOUR LIBRARY" if not records.is_empty() else "ADD YOUR FIRST GAME TO GET STARTED"
	library_count.text = "%02d GAMES" % games.size()
	empty_hint.visible = records.is_empty()
	carousel_count.text = "%02d  /  %02d" % [selected_index + 1, records.size()] if not records.is_empty() else "YOUR COLLECTION AWAITS"
	play_button.disabled = demo_mode or games.is_empty() or launch_pid != -1 or tracker.is_busy()
	launch_file_button.disabled = demo_mode or games.is_empty() or save_blocked
	cover_button.disabled = demo_mode or games.is_empty() or save_blocked
	for index in range(cases.size()):
		cases[index].set("dragging", false)
		cases[index].set_process_unhandled_input(index == selected_index and not modal and not scrolling)
	refresh_stats()


func _on_strip_input(event: InputEvent) -> void:
	if cases.is_empty():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		scrolling = true
		update_selection()
		scroll_strip.accept_event()


func _input(event: InputEvent) -> void:
	if not scrolling:
		return
	if event is InputEventMouseMotion:
		scroll_position = clampf(scroll_position + event.relative.x / PIXELS_PER_CASE, 0.0, float(maxi(cases.size() - 1, 0)))
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		finish_scroll()


func finish_scroll() -> void:
	scrolling = false
	selected_index = clampi(int(round(scroll_position)), 0, maxi(cases.size() - 1, 0))
	update_selection()


func _process(delta: float) -> void:
	scan_poll += delta
	if scan_poll >= 0.25:
		scan_poll = 0.0
		poll_scan()
		poll_launch()
	if scrolling and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		finish_scroll()
	if has_node("CaseStage"):
		$CaseStage.position.x = -get_viewport().get_visible_rect().size.aspect() * 0.88
		$CaseRing.position.x = $CaseStage.position.x
	var smoothing: float = 1.0 - exp(-12.0 * delta)
	if not scrolling:
		scroll_position = lerpf(scroll_position, float(selected_index), smoothing)
	for index in range(cases.size()):
		var distance: float = float(index) - scroll_position
		var game_case: Node3D = cases[index]
		var target: Vector3 = Vector3(-distance * 1.35 - get_viewport().get_visible_rect().size.aspect() * 0.88, 0.08, -minf(absf(distance), 3.0) * 0.6)
		var scale_target: float = 1.13 - minf(absf(distance), 1.0) * 0.22
		game_case.scale = game_case.scale.lerp(Vector3.ONE * scale_target * case_size, smoothing)
		game_case.position = game_case.position.lerp(target, smoothing)
		if scrolling or index != selected_index:
			game_case.rotation.y = lerp_angle(game_case.rotation.y, clampf(-distance * 0.3, -0.8, 0.8), smoothing)


func _exit_tree() -> void:
	cancel_scan()


func add_cover(game_case: Node3D, image_path: String, record: Dictionary = {}) -> void:
	var texture: Texture2D = load_cover_texture(image_path)
	if texture == null:
		add_placeholder(game_case, str(record.get("name", "Game")))
		return
	var mode: String = str(record.get("cover_layout", "wrap"))
	if mode in ["front", "front_back"]:
		add_portrait_face(game_case, texture, false)
		var back: Texture2D = load_cover_texture(str(record.get("back_cover", ""))) if mode == "front_back" else null
		if back != null:
			add_portrait_face(game_case, back, true)
		else:
			add_plain_back(game_case, str(record.get("name", "Game")))
		add_title_spine(game_case, str(record.get("name", "Game")))
		return

	# Approximate boundaries measured from your uploaded wrap.
	var back_end: float = 906.0 / 1914.0
	var front_start: float = 1008.0 / 1914.0
	var artwork: Dictionary = record.get("artwork", {})
	var crop: Array = artwork.get("crop", [0.0, 0.0, 1.0, 1.0])
	back_end = float(artwork.get("spine_start", back_end))
	front_start = float(artwork.get("spine_end", front_start))

	# Front: right-hand section of the image.
	add_cover_face(
		game_case,
		texture,
		Vector2(1.4, 2.0),
		Vector3(0.0, 0.0, 0.078),
		0.0,
		front_start,
		1.0 - front_start,
		crop
	)

	# Back: left-hand section, facing backward.
	add_cover_face(
		game_case,
		texture,
		Vector2(1.4, 2.0),
		Vector3(0.0, 0.0, -0.078),
		PI,
		0.0,
		back_end,
		crop
	)

	# Spine: middle section, on the case's left edge.
	add_cover_face(
		game_case,
		texture,
		Vector2(0.15, 2.0),
		Vector3(-0.703, 0.0, 0.0),
		-PI / 2.0,
		back_end,
		front_start - back_end,
		crop
	)

	# Keep the case material authored in the CSG scene.


func add_cover_face(
	parent_case: Node3D,
	texture: Texture2D,
	face_size: Vector2,
	face_position: Vector3,
	y_rotation: float,
	image_start: float,
	image_width: float,
	crop: Array = [0.0, 0.0, 1.0, 1.0]
) -> void:
	var face_mesh := QuadMesh.new()
	face_mesh.size = face_size

	var face := MeshInstance3D.new()
	face.mesh = face_mesh
	face.position = face_position
	face.rotation.y = y_rotation

	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Select the horizontal section of the image for this face.
	material.uv1_scale = Vector3(image_width * float(crop[2]), float(crop[3]), 1.0)
	material.uv1_offset = Vector3(float(crop[0]) + image_start * float(crop[2]), float(crop[1]), 0.0)
	material.texture_repeat = false

	face.set_meta("base_uv_scale", material.uv1_scale)
	face.set_meta("base_uv_offset", material.uv1_offset)
	face.material_override = material
	parent_case.add_child(face)


func modal_is_open() -> bool:
	return importer.visible or cover_dialog.visible or (is_instance_valid(cover_editor) and cover_editor.visible) or launch_dialog.visible or migration_dialog.visible or remove_dialog.visible or about_dialog.visible or (is_instance_valid(tracking_dialog) and tracking_dialog.visible) or (is_instance_valid(display_dialog) and display_dialog.visible)


func navigate(direction: int) -> void:
	if modal_is_open() or cases.is_empty():
		return
	scrolling = false
	selected_index = clampi(selected_index - direction, 0, cases.size() - 1)
	update_selection()


func toggle_fullscreen() -> void:
	var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or modal_is_open():
		return
	match event.keycode:
		KEY_F11:
			toggle_fullscreen()
		KEY_ESCAPE:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		KEY_LEFT:
			navigate(-1)
		KEY_RIGHT:
			navigate(1)
		KEY_ENTER:
			launch_selected()


func _on_menu(id: int) -> void:
	match id:
		0:
			OS.shell_open(ProjectSettings.globalize_path("user://"))
		1:
			migration_dialog.popup_centered_ratio(0.8)
		2:
			about_dialog.popup_centered()
		3:
			get_tree().quit()
	update_selection()


func choose_launch_file() -> void:
	if demo_mode or games.is_empty() or save_blocked:
		return
	launch_game_id = str(games[selected_index]["id"])
	var folder: String = str(games[selected_index].get("install_path", ""))
	if DirAccess.dir_exists_absolute(folder):
		launch_dialog.current_dir = folder
	launch_dialog.popup_centered_ratio(0.8)
	update_selection()


func set_launch_file(path: String) -> void:
	var result: Dictionary = LaunchService.file_plan(path)
	if result.has("error"):
		status_label.text = str(result["error"])
		update_selection()
		return
	var updated: Array[Dictionary] = games.duplicate(true)
	for record in updated:
		if str(record["id"]) == launch_game_id:
			record["launch_override"] = path
	if save_library(updated):
		games = updated
		status_label.text = "Launch file saved. Press Play game when you're ready."
	else:
		status_label.text = "Could not save the launch file."
	update_selection()


func launch_selected() -> void:
	if demo_mode or games.is_empty() or modal_is_open() or launch_pid != -1 or tracker.is_busy() or Time.get_ticks_msec() < launch_debounce:
		return
	if OS.get_name() != "Windows":
		status_label.text = "This desktop build launches games on Windows."
		return
	var record: Dictionary = games[selected_index]
	var plan: Dictionary = LaunchService.plan(record)
	if plan.has("error"):
		status_label.text = str(plan["error"])
		choose_launch_file()
		return
	pending_track_record = record.duplicate(true)
	pending_track_plan = plan.duplicate(true)
	launch_title = str(record.get("name", "Game"))
	launch_debounce = Time.get_ticks_msec() + 2500
	if plan["kind"] == "uri":
		var error: Error = OS.shell_open(str(plan["target"]))
		if error == OK:
			tracker.begin(pending_track_record, pending_track_plan)
		status_label.text = "Launch request sent for " + launch_title + "." if error == OK else "Could not open the launcher. Check it is installed, or set a launch shortcut."
		return
	# Executables need their own working folder. Xbox uses AppsFolder activation.
	var script_source: String = get_script().resource_path.get_base_dir().path_join("launch_game.ps1")
	if not FileAccess.file_exists(script_source):
		status_label.text = "The launch helper is missing from this app build."
		return
	var file: FileAccess = FileAccess.open("user://launch_game.ps1", FileAccess.WRITE)
	if file == null:
		status_label.text = "Could not prepare the launch helper."
		return
	file.store_string(FileAccess.get_file_as_string(script_source))
	file.close()
	file = FileAccess.open("user://launch_request.json", FileAccess.WRITE)
	if file == null:
		status_label.text = "Could not save the launch request."
		return
	file.store_string(JSON.stringify(plan))
	file.close()
	if FileAccess.file_exists("user://launch_result.json"):
		if DirAccess.remove_absolute("user://launch_result.json") != OK:
			status_label.text = "Could not clear the previous launch result."
			return
	var powershell: String = OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	launch_pid = OS.create_process(powershell, PackedStringArray(["-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path("user://launch_game.ps1"), "-RequestPath", ProjectSettings.globalize_path("user://launch_request.json"), "-ResultPath", ProjectSettings.globalize_path("user://launch_result.json")]), false)
	launch_started = Time.get_ticks_msec()
	status_label.text = "Opening " + launch_title + "…" if launch_pid >= 0 else "Could not start the launch helper."
	update_selection()


func poll_launch() -> void:
	if launch_pid == -1:
		return
	if Time.get_ticks_msec() - launch_started > 30000:
		# Do not kill the helper or a game it may have started.
		launch_pid = -1
		status_label.text = "Launch confirmation timed out. Check the game or launcher before trying again."
		update_selection()
		return
	if OS.is_process_running(launch_pid):
		return
	launch_pid = -1
	var result: Variant = null
	if FileAccess.file_exists("user://launch_result.json"):
		result = JSON.parse_string(FileAccess.get_file_as_string("user://launch_result.json"))
	if result is Dictionary:
		if bool(result.get("ok", false)):
			tracker.begin(pending_track_record, pending_track_plan)
		status_label.text = "Launch request sent for " + launch_title + "." if bool(result.get("ok", false)) else str(result.get("message", "Launch failed."))
	else:
		status_label.text = "Launch could not be confirmed. Check the launcher or choose a different launch file."
	update_selection()


func ask_remove_game() -> void:
	if demo_mode or games.is_empty() or save_blocked:
		return
	remove_game_id = str(games[selected_index]["id"])
	remove_dialog.dialog_text = "Remove %s from CoverFlow?\nThe installed game will stay on your PC." % str(games[selected_index].get("name", "this game"))
	remove_dialog.popup_centered()
	update_selection()


func remove_selected_game() -> void:
	var updated: Array[Dictionary] = []
	for record in games:
		if str(record["id"]) != remove_game_id:
			updated.append(record)
	if save_library(updated):
		games = updated
		rebuild_cases()
	else:
		status_label.text = "Could not save the change; the game was not removed."
	update_selection()


func migrate_library(path: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.get("version", 0) != 1 or not parsed.get("games") is Array:
		status_label.text = "That file is not a valid CoverFlow library."
		update_selection()
		return
	var updated: Array[Dictionary] = games.duplicate(true)
	var known: Dictionary = {}
	for record in updated:
		known[str(record["id"])] = true
	var copied: int = 0
	var missing_covers: int = 0
	for source in parsed["games"]:
		if not source is Dictionary or str(source.get("id", "")).is_empty() or str(source.get("name", "")).is_empty():
			continue
		if known.has(str(source["id"])):
			continue
		var record: Dictionary = source.duplicate(true)
		for image_key in ["cover", "back_cover"]:
			var cover: String = str(record.get(image_key, ""))
			if not cover.is_empty():
				var source_cover: String = path.get_base_dir().path_join(cover.trim_prefix("user://")) if cover.begins_with("user://") else cover
				if not cover.begins_with("res://") and FileAccess.file_exists(source_cover):
					DirAccess.make_dir_recursive_absolute("user://covers")
					var destination: String = "user://covers/import_" + str(record["id"]).sha256_text() + "_" + image_key + "_" + str(Time.get_ticks_usec()) + "." + source_cover.get_extension()
					if DirAccess.copy_absolute(source_cover, destination) == OK:
						record[image_key] = destination
					else:
						record[image_key] = ""
						missing_covers += 1
				else:
					record[image_key] = ""
					missing_covers += 1
		updated.append(record)
		known[str(record["id"])] = true
		copied += 1
	if save_library(updated):
		games = updated
		demo_mode = false
		rebuild_cases()
		status_label.text = "Imported %d games. %d covers need reassignment." % [copied, missing_covers]
	else:
		status_label.text = "Could not save the imported library. Existing entries kept."
	update_selection()


func load_cover_image(path: String) -> Image:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var image: Image
	if path.begins_with("res://"):
		var resource: Texture2D = load(path) as Texture2D
		if resource == null:
			return null
		image = resource.get_image()
	else:
		image = Image.new()
		if image.load(path) != OK:
			return null
	if image == null or image.is_empty():
		return null
	if image.is_compressed() and image.decompress() != OK:
		return null
	return image


func load_cover_texture(path: String) -> Texture2D:
	var image: Image = load_cover_image(path)
	if image == null:
		return null
	# Generate progressively smaller versions for smooth distant/angled rendering.
	if not image.has_mipmaps():
		image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func add_portrait_face(game_case: Node3D, texture: Texture2D, is_back: bool) -> void:
	# Fit the complete image inside the face without changing its proportions.
	var factor: float = minf(1.36 / float(texture.get_width()), 1.96 / float(texture.get_height()))
	var face_size: Vector2 = Vector2(texture.get_width(), texture.get_height()) * factor
	add_cover_face(game_case, texture, Vector2(1.36, 1.96), Vector3(0, 0, -0.078 if is_back else 0.078), PI if is_back else 0.0, 0.0, 1.0)
	game_case.get_child(game_case.get_child_count() - 1).set_meta("art_fit", face_size / Vector2(1.36, 1.96))


func add_plain_back(game_case: Node3D, game_name: String) -> void:
	var label: Label3D = Label3D.new()
	label.text = game_name
	label.font_size = 48
	label.outline_size = 0
	label.pixel_size = 0.0035
	label.width = 320
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = Color("c4d5dd")
	label.position.z = -0.08
	label.rotation.y = PI
	game_case.add_child(label)


func add_title_spine(game_case: Node3D, game_name: String) -> void:
	var holder: Node3D = Node3D.new()
	holder.position = Vector3(-0.704, 0, 0)
	holder.rotation.y = -PI / 2.0
	game_case.add_child(holder)
	var label: Label3D = Label3D.new()
	label.text = game_name
	label.font_size = 24
	label.outline_size = 0
	label.pixel_size = 0.0028
	label.width = 620
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.rotation.z = PI / 2.0
	label.modulate = Color("c4d5dd")
	holder.add_child(label)


func apply_local_artwork(identity: String, mode: String, front_path: String, back_path: String = "") -> Dictionary:
	if save_blocked or mode not in ["wrap", "front", "front_back"]:
		return {"error": "Artwork cannot be saved for this library."}
	var index: int = -1
	for number in range(games.size()):
		if str(games[number]["id"]) == identity:
			index = number
			break
	if index < 0:
		return {"error": "That game is no longer in your library."}
	var front: Image = load_cover_image(front_path)
	if front == null:
		return {"error": "Choose a readable front image or full wrap."}
	var back: Image = null
	if mode == "front_back":
		back = load_cover_image(back_path)
		if back == null:
			return {"error": "Choose a readable back image too."}
	DirAccess.make_dir_recursive_absolute("user://covers")
	var prefix: String = "user://covers/" + identity.sha256_text() + "_" + str(Time.get_ticks_usec())
	var front_destination: String = prefix + "_front.png"
	if front.save_png(front_destination) != OK:
		return {"error": "Could not save the front image. Existing artwork kept."}
	var back_destination: String = ""
	if back != null:
		back_destination = prefix + "_back.png"
		if back.save_png(back_destination) != OK:
			DirAccess.remove_absolute(front_destination)
			return {"error": "Could not save the back image. Existing artwork kept."}
	var updated: Array[Dictionary] = games.duplicate(true)
	var keep_crop: bool = mode == "wrap" and str(games[index].get("cover_layout", "wrap")) == "wrap" and front_path == str(games[index].get("cover", ""))
	updated[index]["cover"] = front_destination
	updated[index]["cover_layout"] = mode
	updated[index].erase("back_cover")
	if not back_destination.is_empty():
		updated[index]["back_cover"] = back_destination
	if not keep_crop:
		updated[index].erase("artwork")
	if not save_library(updated):
		DirAccess.remove_absolute(front_destination)
		if not back_destination.is_empty():
			DirAccess.remove_absolute(back_destination)
		return {"error": "Could not save the library. Existing artwork kept."}
	games = updated
	rebuild_cases()
	return {"ok": true}


func create_animated_background() -> void:
	var backdrop := MeshInstance3D.new()
	backdrop.name = "AnimatedBackground"
	var quad := QuadMesh.new()
	quad.size = Vector2(200.0, 200.0)
	backdrop.mesh = quad
	backdrop.position = Vector3(0.0, 0.0, -30.0)
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var background_material := ShaderMaterial.new()
	background_material.shader = preload("res://animated_background.gdshader")
	background_material.set_shader_parameter("alley", preload("res://assets/alley.png"))
	backdrop.material_override = background_material
	$Camera3D.add_child(backdrop)


func refresh_stats() -> void:
	if not is_instance_valid(stats_panel): return
	var records: Array[Dictionary] = display_records()
	var record: Dictionary = records[selected_index] if not records.is_empty() and selected_index < records.size() else {}
	stats_panel.refresh(record, tracker)
	play_button.disabled = demo_mode or games.is_empty() or launch_pid != -1 or tracker.is_busy()

func choose_tracking_file() -> void:
	if demo_mode or games.is_empty() or save_blocked or tracker.is_busy(): return
	tracking_game_id = str(games[selected_index]["id"])
	var folder: String = str(games[selected_index].get("install_path", ""))
	if DirAccess.dir_exists_absolute(folder): tracking_dialog.current_dir = folder
	tracking_dialog.popup_centered_ratio(0.8)
	update_selection()

func set_tracking_file(path: String) -> void:
	if path.get_extension().to_lower() != "exe" or not FileAccess.file_exists(path): return
	var updated: Array[Dictionary] = games.duplicate(true)
	for record in updated:
		if str(record["id"]) == tracking_game_id: record["tracking_exe"] = path
	if save_library(updated):
		games = updated
		status_label.text = "Tracking EXE saved. Press Play game to start a new session."
	else:
		status_label.text = "Could not save the tracking EXE."
	update_selection()


func save_display_preferences() -> void:
	var preferences := ConfigFile.new()
	preferences.set_value("display", "case_size", case_size)
	preferences.set_value("display", "stats_collapsed", stats_collapsed)
	if preferences.save("user://display.cfg") != OK:
		status_label.text = "Display preferences could not be saved."

func toggle_stats() -> void:
	stats_collapsed = not stats_collapsed
	stats_panel.set_collapsed(stats_collapsed)
	save_display_preferences()

func art_settings(record: Dictionary) -> Dictionary:
	return {"art_size": clampf(float(record.get("art_size", record.get("cover_zoom", 1.0))), 0.25, 2.5), "art_width": clampf(float(record.get("art_width", 1.0)), 0.25, 2.5), "art_height": clampf(float(record.get("art_height", 1.0)), 0.25, 2.5)}

func apply_art_dimensions(game_case: Node3D, record: Dictionary) -> void:
	var settings: Dictionary = art_settings(record)
	var overall: float = float(settings.art_size)
	for child in game_case.get_children():
		if child is MeshInstance3D and child.has_meta("base_uv_scale"):
			var material: ShaderMaterial
			if child.material_override is StandardMaterial3D:
				var previous: StandardMaterial3D = child.material_override
				material = ShaderMaterial.new()
				material.shader = preload("res://artwork_transform.gdshader")
				material.set_shader_parameter("art_texture", previous.albedo_texture)
				child.material_override = material
			else:
				material = child.material_override as ShaderMaterial
			var base_scale: Vector3 = child.get_meta("base_uv_scale")
			var base_offset: Vector3 = child.get_meta("base_uv_offset")
			var fit: Vector2 = child.get_meta("art_fit", Vector2.ONE)
			material.set_shader_parameter("atlas_scale", Vector2(base_scale.x, base_scale.y))
			material.set_shader_parameter("atlas_offset", Vector2(base_offset.x, base_offset.y))
			material.set_shader_parameter("image_scale", fit * Vector2(overall * float(settings.art_width), overall * float(settings.art_height)))

func preview_art_dimensions(_value: float = 0.0) -> void:
	if loading_art_controls or cases.is_empty(): return
	apply_art_dimensions(cases[selected_index], {"art_size":size_slider.value, "art_width":width_slider.value, "art_height":height_slider.value})

func display_slider(parent: Node, caption: String, low: float, high: float) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 170
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.01
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var percent := Label.new()
	percent.custom_minimum_size.x = 65
	percent.text = "%d%%" % roundi(slider.value * 100)
	row.add_child(percent)
	slider.value_changed.connect(func(value: float) -> void: percent.text = "%d%%" % roundi(value * 100))
	return slider

func create_display_dialog() -> void:
	display_dialog = Window.new()
	display_dialog.title = "Edit artwork size"
	display_dialog.size = Vector2i(620, 320)
	display_dialog.min_size = Vector2i(520, 300)
	display_dialog.theme = ui_root.theme
	display_dialog.transient = true
	display_dialog.exclusive = true
	display_dialog.visible = false
	add_child(display_dialog)
	var margin := MarginContainer.new()
	display_dialog.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 20)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	var note := Label.new()
	note.text = "Resize this game's artwork. Width and height stretch independently; the case stays the same size. Edges beyond the case are cropped."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	size_slider = display_slider(column, "Artwork size", 0.25, 2.5)
	width_slider = display_slider(column, "Artwork width", 0.25, 2.5)
	height_slider = display_slider(column, "Artwork height", 0.25, 2.5)
	for slider in [size_slider, width_slider, height_slider]: slider.value_changed.connect(preview_art_dimensions)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	make_button(buttons, "Reset", func() -> void: size_slider.value = 1.0; width_slider.value = 1.0; height_slider.value = 1.0)
	make_button(buttons, "Cancel", cancel_display_settings)
	make_button(buttons, "Save", save_display_settings).theme_type_variation = "PrimaryButton"
	display_dialog.close_requested.connect(cancel_display_settings)

func open_display_settings() -> void:
	if games.is_empty() or demo_mode or save_blocked: return
	display_game_id = str(games[selected_index]["id"])
	original_art = art_settings(games[selected_index])
	loading_art_controls = true
	size_slider.value = float(original_art.art_size)
	width_slider.value = float(original_art.art_width)
	height_slider.value = float(original_art.art_height)
	loading_art_controls = false
	display_dialog.popup_centered()
	update_selection()

func cancel_display_settings() -> void:
	if not cases.is_empty(): apply_art_dimensions(cases[selected_index], original_art)
	display_dialog.hide()
	update_selection()

func save_display_settings() -> void:
	if display_game_id.is_empty() or save_blocked: return
	var updated: Array[Dictionary] = games.duplicate(true)
	for record in updated:
		if str(record["id"]) == display_game_id:
			record["art_size"] = size_slider.value
			record["art_width"] = width_slider.value
			record["art_height"] = height_slider.value
			record.erase("cover_zoom")
	if not save_library(updated):
		status_label.text = "Could not save artwork dimensions. Try again or cancel."
		return
	games = updated
	display_dialog.hide()
	update_selection()
