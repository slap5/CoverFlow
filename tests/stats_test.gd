extends SceneTree
var fails: int = 0
func check(ok: bool, text: String):
 print(('PASS: ' if ok else 'FAIL: ') + text)
 if not ok: fails += 1
func _initialize():
 call_deferred('run')
func run():
 var Store = load('res://stats_store.gd')
 var store = Store.new()
 store.path='user://test_stats.json'
 if FileAccess.file_exists(store.path): DirAccess.remove_absolute(store.path)
 store.load_data()
 check(not store.apply_snapshot('test',{'session':'a','started':false,'seconds':100}), 'Waiting or failed launch does not count')
 var a={'session':'a','started':true,'seconds':0,'last_played':'2026-10-24 20:00:00'}
 check(store.apply_snapshot('test',a), 'First observed game starts session')
 a.seconds=63.5
 store.apply_snapshot('test',a); store.apply_snapshot('test',a)
 check(store.get_stats('test').seconds == 63.5 and store.get_stats('test').sessions == 1, 'Repeated snapshots do not double count')
 a.seconds=20; store.apply_snapshot('test',a)
 check(store.get_stats('test').seconds == 63.5, 'Older snapshots cannot subtract or duplicate time')
 var second=Store.new(); second.path=store.path; second.load_data()
 check(second.get_stats('test').seconds == 63.5, 'Stats survive restart')
 second.apply_snapshot('test',{'session':'b','started':true,'seconds':30,'last_played':'2026-10-25 10:00:00'})
 check(second.get_stats('test').seconds == 93.5 and second.get_stats('test').sessions == 2, 'Next session adds its own time once')
 check(second.get_stats('test').last_session == 30, 'Last session is separate from total')
 var f=FileAccess.open('user://bad_stats.json',FileAccess.WRITE); f.store_string('broken');f.close()
 var bad=Store.new();bad.path='user://bad_stats.json';bad.load_data()
 check(bad.blocked and not bad.apply_snapshot('x',a), 'Corrupt stats are protected')
 var app=load('res://main.tscn').instantiate();root.add_child(app)
 await process_frame
 app.games.clear();app.games.append({'id':'test','name':'Stats Test','source':'Manual','cover':''})
 app.demo_mode=false;app.rebuild_cases()
 check(app.stats_panel != null and app.stats_panel.heading.text == 'STATS TEST', 'Stats panel follows selected game')
 check(app.cases[0].get_node('Shape').transparency == 0, 'Grey case remains opaque')
 app.choose_tracking_file()
 check(app.tracking_dialog.visible and not app.cases[0].is_processing_unhandled_input(), 'Tracking chooser blocks rotation')
 app.tracking_dialog.hide();app.update_selection()
 check(app.cases[0].is_processing_unhandled_input(), 'Rotation restored after chooser')
 app.queue_free();await process_frame
 quit(1 if fails else 0)
