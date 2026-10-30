extends PanelContainer
const StatsStore = preload("res://stats_store.gd")
var heading: Label
var source: Label
var total: Label
var last_played: Label
var sessions: Label
var last_session: Label
var status: Label
var first_badge: Label
var hours_badge: Label
var regular_badge: Label
var progress: ProgressBar
var stop_button: Button
var collapse_button: Button
var details: ScrollContainer
var app: Node

func setup(host: Node) -> void:
 app = host
 mouse_filter = Control.MOUSE_FILTER_STOP
 var style := StyleBoxFlat.new()
 style.bg_color = Color(0.04,0.045,0.039,0.985)
 style.border_color = Color(0.65,0.62,0.51,0.42)
 style.set_border_width_all(1)
 style.set_corner_radius_all(5)
 style.content_margin_left = 26
 style.content_margin_right = 26
 style.content_margin_top = 20
 style.content_margin_bottom = 18
 add_theme_stylebox_override("panel", style)
 var wrapper := VBoxContainer.new()
 add_child(wrapper)
 collapse_button = Button.new()
 collapse_button.text = "GAME STATS  ▾"
 collapse_button.tooltip_text = "Collapse or expand game stats"
 collapse_button.pressed.connect(app.toggle_stats)
 wrapper.add_child(collapse_button)
 var scroll := ScrollContainer.new()
 details = scroll
 scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
 scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 wrapper.add_child(scroll)
 var column := VBoxContainer.new()
 column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 column.add_theme_constant_override("separation", 6)
 scroll.add_child(column)
 heading = label(column, "YOUR COLLECTION", 32, Color("e8e2d0"))
 heading.add_theme_font_override("font", preload("res://assets/Anton-Regular.ttf"))
 heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 source = label(column,"TRACKED BY COVERFLOW",11,Color("aaa590"))
 line(column)
 total = label(column,"0m",42,Color("d5aa4b"))
 total.add_theme_font_override("font", preload("res://assets/Anton-Regular.ttf"))
 label(column,"PLAYTIME TRACKED",12,Color("a9a492"))
 line(column)
 last_played = row(column,"Last played")
 sessions = row(column,"Sessions")
 last_session = row(column,"Last session")
 line(column)
 label(column,"COVERFLOW MILESTONES",14,Color("b8b19b"))
 first_badge = label(column,"○  First launch",17)
 label(column,"Play your first tracked session",11,Color("9f9a88"))
 hours_badge = label(column,"○  Night driver",17)
 label(column,"10 hours tracked in this game",11,Color("9f9a88"))
 regular_badge = label(column,"○  Regular — 0 / 25 sessions",17)
 progress = ProgressBar.new()
 progress.show_percentage = false
 progress.max_value = 25
 progress.custom_minimum_size.y = 6
 var fill := StyleBoxFlat.new(); fill.bg_color=Color("d5aa4b"); fill.set_corner_radius_all(3)
 var back := StyleBoxFlat.new(); back.bg_color=Color("33362e"); back.set_corner_radius_all(3)
 progress.add_theme_stylebox_override("fill",fill)
 progress.add_theme_stylebox_override("background",back)
 column.add_child(progress)
 line(column)
 label(column,"Local milestones • not official achievements",11,Color("9f9a88")).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 status = label(column,"Launch a game to start tracking.",12,Color("c2b990"))
 status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 var buttons := HBoxContainer.new(); column.add_child(buttons)
 buttons.hide()
 var configure := Button.new(); configure.text="Track EXE"; configure.tooltip_text="Choose the actual game executable if automatic tracking misses it."; configure.pressed.connect(app.choose_tracking_file); buttons.add_child(configure)
 stop_button = Button.new(); stop_button.text="Stop tracking"; stop_button.pressed.connect(app.tracker.stop); buttons.add_child(stop_button)
 label(column,"Tracks while CoverFlow is open. Existing launcher hours are not imported.",11,Color("8e8b7f")).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func label(parent: Node, text: String, font_size: int, color: Color = Color("ddd8c7")) -> Label:
 var node := Label.new(); node.text=text; node.add_theme_font_size_override("font_size",font_size); node.add_theme_color_override("font_color",color); node.mouse_filter=Control.MOUSE_FILTER_IGNORE; parent.add_child(node); return node
func line(parent: Node) -> void:
 var rule := HSeparator.new(); parent.add_child(rule)
func row(parent: Node, caption: String) -> Label:
 var box := HBoxContainer.new(); parent.add_child(box)
 var key := label(box,caption,15,Color("b7b2a3")); key.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 return label(box,"—",15)

func refresh(record: Dictionary, tracker: Node) -> void:
 var id: String = str(record.get("id", ""))
 var stats: Dictionary = tracker.store.get_stats(id)
 heading.text = str(record.get("name","YOUR COLLECTION")).to_upper()
 source.text = str(record.get("source", "LOCAL LIBRARY")).to_upper() + "  •  TRACKED BY COVERFLOW"
 total.text = StatsStore.duration(float(stats.get("seconds",0)))
 last_played.text = str(stats.get("last_played", "Never")).left(16)
 var count: int = int(stats.get("sessions",0))
 sessions.text = str(count)
 last_session.text = StatsStore.duration(float(stats.get("last_session",0)))
 first_badge.text = ("✓" if count > 0 else "○") + "  First launch"
 hours_badge.text = ("✓" if float(stats.get("seconds",0)) >= 36000 else "○") + "  Night driver"
 regular_badge.text = ("✓" if count >= 25 else "○") + "  Regular — %d / 25 sessions" % count
 progress.value = mini(count,25)
 stop_button.visible = tracker.is_busy()
 if tracker.store.blocked:
  status.text = tracker.store.error
 elif tracker.game_id == id:
  status.text = tracker.message
 elif tracker.is_busy():
  status.text = "Tracking " + tracker.game_title + ". Stop tracking before starting another game."
 else:
  status.text = "Launch this game to start tracking."

func set_collapsed(collapsed: bool) -> void:
 details.visible = not collapsed
 collapse_button.text = "GAME STATS  ▸" if collapsed else "GAME STATS  ▾"
 anchor_bottom = 0.0 if collapsed else 1.0
 offset_bottom = 190.0 if collapsed else -125.0
