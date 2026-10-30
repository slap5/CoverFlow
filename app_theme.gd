extends RefCounted
const BG: Color = Color("101c2a")
const TEXT: Color = Color("e7e3d4")
const MUTED: Color = Color("aaa999")
const ACCENT: Color = Color("c8b54b")
static func box(color: Color, border: Color = Color.TRANSPARENT, radius: int = 10) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style
static func create() -> Theme:
	var theme: Theme = Theme.new()
	theme.default_font_size = 16
	for type in ["Label", "Button", "CheckBox", "LineEdit", "OptionButton", "ItemList", "TextEdit", "PopupMenu"]:
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_disabled_color", type, Color("536577"))
	for type in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type, box(Color("272a26"), Color("515347")))
		theme.set_stylebox("hover", type, box(Color("393d32"), Color("9d9565")))
		theme.set_stylebox("pressed", type, box(Color("56553a"), ACCENT))
		theme.set_stylebox("disabled", type, box(Color("101b28"), Color("1e2b3a")))
		theme.set_stylebox("focus", type, box(Color(0,0,0,0), ACCENT))
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", box(ACCENT, ACCENT, 12))
	theme.set_stylebox("hover", "PrimaryButton", box(Color("e0ce74"), Color("e0ce74"), 12))
	theme.set_stylebox("pressed", "PrimaryButton", box(Color("aa9639"), ACCENT, 12))
	theme.set_color("font_color", "PrimaryButton", Color("24251e"))
	theme.set_color("font_hover_color", "PrimaryButton", Color("24251e"))
	theme.set_color("font_pressed_color", "PrimaryButton", Color("24251e"))
	for type in ["Panel", "PanelContainer", "PopupPanel"]:
		theme.set_stylebox("panel", type, box(Color("0e1926"), Color("273949"), 14))
	for type in ["LineEdit", "TextEdit", "ItemList"]:
		theme.set_stylebox("normal" if type != "ItemList" else "panel", type, box(Color("0b1420"), Color("2a3e50")))
		theme.set_stylebox("focus", type, box(Color(0,0,0,0), ACCENT))
		theme.set_color("font_placeholder_color", type, MUTED)
		theme.set_color("selection_color", type, Color("2e6968"))
	theme.set_stylebox("selected", "ItemList", box(Color("28524e")))
	theme.set_stylebox("selected_focus", "ItemList", box(Color("28524e"), ACCENT))
	theme.set_stylebox("panel", "Window", box(Color("0d1824"), Color("466471")))
	theme.set_color("font_color", "CheckBox", TEXT)
	theme.set_constant("separation", "VBoxContainer", 10)
	theme.set_constant("separation", "HBoxContainer", 10)
	theme.set_stylebox("panel", "PopupMenu", box(Color("152333"), Color("334b5e")))
	var border: StyleBoxFlat = box(Color("152535"), Color("466471"), 12)
	border.expand_margin_top = 30
	theme.set_stylebox("embedded_border", "Window", border)
	theme.set_stylebox("embedded_unfocused_border", "Window", border)
	theme.set_color("title_color", "Window", TEXT)
	theme.set_color("title_outline_modulate", "Window", Color.TRANSPARENT)
	return theme
