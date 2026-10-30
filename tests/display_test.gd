extends SceneTree
func _initialize() -> void:
 call_deferred("run_test")
func run_test() -> void:
 var app = load("res://main.tscn").instantiate()
 root.add_child(app)
 await process_frame
 assert(app.game_menu.get_popup().item_count == 6)
 assert(app.play_button.visible)
 assert(not app.cover_button.is_visible_in_tree())
 var image := Image.create(32, 48, false, Image.FORMAT_RGBA8)
 image.fill(Color.CORAL)
 image.save_png("user://display_test.png")
 app.games.assign([{"id":"test:display", "name":"Display test", "source":"Test", "cover":"user://display_test.png", "cover_layout":"front"}])
 app.demo_mode = false
 app.rebuild_cases()
 app.open_display_settings()
 app.size_slider.value = 0.8
 app.width_slider.value = 1.5
 app.height_slider.value = 0.6
 app.save_display_settings()
 assert(is_equal_approx(app.case_size,1.0))
 assert(is_equal_approx(float(app.games[0].art_width),1.5))
 var saved = JSON.parse_string(FileAccess.get_file_as_string("user://coverflow_library.json"))
 assert(is_equal_approx(float(saved.games[0].art_height),0.6))
 app.open_display_settings()
 app.size_slider.value = 1.1
 app.width_slider.value = 2.0
 app.cancel_display_settings()
 assert(is_equal_approx(app.case_size,1.0))
 app.stats_collapsed = false
 app.toggle_stats()
 assert(not app.stats_panel.details.visible)
 assert(app.stats_panel.anchor_bottom == 0.0)
 app.toggle_stats()
 assert(app.stats_panel.details.visible)
 var preferences := ConfigFile.new()
 assert(preferences.load("user://display.cfg") == OK)
 assert(is_equal_approx(float(preferences.get_value("display","case_size")),1.0))
 print("PASS: menu, saved artwork dimensions, cancel, and stats collapse/expand")
 app.queue_free()
 await process_frame
 quit()
