extends Window
# Select a layout explicitly; a portrait photo is never mistaken for a full wrap.
var app: Node
var game_id: String = ""
var front_path: String = ""
var back_path: String = ""
var pick_back: bool = false
var layout: OptionButton
var front_preview: TextureRect
var back_preview: TextureRect
var front_label: Label
var back_label: Label
var front_caption: Label
var back_card: VBoxContainer
var note: Label
var status: Label
var picker: FileDialog
var apply_button: Button
const MODES: Array[String] = ["front", "front_back", "wrap"]

func setup(owner_app: Node, app_theme: Theme) -> void:
	app = owner_app
	theme = app_theme
	title = "Local cover artwork"
	size = Vector2i(860, 580)
	min_size = Vector2i(620, 440)
	exclusive = true
	transient = true
	visible = false
	close_requested.connect(close_editor)
	var margin: MarginContainer = MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	var column: VBoxContainer = VBoxContainer.new()
	margin.add_child(column)
	layout = OptionButton.new()
	layout.add_item("Front only — one portrait image")
	layout.add_item("Front + back — two separate images")
	layout.add_item("Full wrap — back, spine and front in one image")
	column.add_child(layout)
	layout.item_selected.connect(func(_index: int) -> void: update_layout())
	note = Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	var images: HBoxContainer = HBoxContainer.new()
	images.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(images)
	var front_card: VBoxContainer = VBoxContainer.new()
	front_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	images.add_child(front_card)
	front_caption = Label.new()
	front_card.add_child(front_caption)
	front_preview = make_preview(front_card)
	front_label = make_filename(front_card)
	app.make_button(front_card, "Choose front / wrap image", func() -> void: choose(false))
	back_card = VBoxContainer.new()
	back_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	images.add_child(back_card)
	var caption: Label = Label.new()
	caption.text = "BACK"
	back_card.add_child(caption)
	back_preview = make_preview(back_card)
	back_label = make_filename(back_card)
	app.make_button(back_card, "Choose back image", func() -> void: choose(true))
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status)
	var footer: HBoxContainer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(footer)
	app.make_button(footer, "Cancel", close_editor)
	apply_button = app.make_button(footer, "Apply artwork", apply_artwork)
	apply_button.theme_type_variation = "PrimaryButton"
	picker = FileDialog.new()
	picker.theme = app_theme
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	picker.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Cover images"])
	add_child(picker)
	picker.file_selected.connect(image_selected)

func make_preview(parent: Node) -> TextureRect:
	var preview: TextureRect = TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	preview.custom_minimum_size = Vector2(200, 220)
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(preview)
	return preview

func make_filename(parent: Node) -> Label:
	var label: Label = Label.new()
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(label)
	return label

func show_for_game(record: Dictionary) -> void:
	game_id = str(record["id"])
	front_path = str(record.get("cover", ""))
	back_path = str(record.get("back_cover", ""))
	var mode: String = str(record.get("cover_layout", "front" if front_path.is_empty() else "wrap"))
	layout.select(maxi(0, MODES.find(mode)))
	front_preview.texture = app.load_cover_texture(front_path) if not front_path.is_empty() else null
	back_preview.texture = app.load_cover_texture(back_path) if not back_path.is_empty() else null
	front_label.text = "Current image • %d × %d" % [front_preview.texture.get_width(), front_preview.texture.get_height()] if front_preview.texture != null else "No front image selected"
	back_label.text = "Current back • %d × %d" % [back_preview.texture.get_width(), back_preview.texture.get_height()] if back_preview.texture != null else "No back image selected"
	status.text = "Choose full-resolution images for the cleanest result."
	update_layout()
	popup_centered_clamped(Vector2i(860, 580), 0.94)
	app.update_selection()

func update_layout() -> void:
	var mode: String = MODES[layout.selected]
	back_card.visible = mode == "front_back"
	front_caption.text = "FULL WRAP" if mode == "wrap" else "FRONT"
	match mode:
		"front":
			note.text = "Your image fills the front without stretching. The back and spine show the game's name."
		"front_back":
			note.text = "Choose one image for each side. Both keep their proportions; the spine shows the game's name."
		"wrap":
			note.text = "Use a back–spine–front wrap. Existing full-wrap crop settings are retained when you keep the same image."
	apply_button.disabled = front_preview.texture == null or (mode == "front_back" and back_preview.texture == null)

func choose(is_back: bool) -> void:
	pick_back = is_back
	picker.title = "Choose back cover" if is_back else "Choose front cover or full wrap"
	picker.popup_centered_ratio(0.85)

func image_selected(path: String) -> void:
	var texture: Texture2D = app.load_cover_texture(path)
	if texture == null:
		status.text = "That image could not be opened. Choose a JPG, PNG or WebP."
		return
	if pick_back:
		back_path = path
		back_preview.texture = texture
		back_label.text = path.get_file()
	else:
		front_path = path
		front_preview.texture = texture
		front_label.text = path.get_file()
	status.text = "Ready. Nothing changes until you click Apply artwork."
	update_layout()

func apply_artwork() -> void:
	var result: Dictionary = app.apply_local_artwork(game_id, MODES[layout.selected], front_path, back_path)
	if not result.get("ok", false):
		status.text = str(result.get("error", "Could not save artwork."))
		return
	hide()
	app.update_selection()
	app.status_label.text = "Artwork saved. Drag the case to inspect both sides."

func close_editor() -> void:
	hide()
	app.update_selection()
