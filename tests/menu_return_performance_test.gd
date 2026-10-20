extends Control
## Real pause-menu return path. Timings are evidence, never hardware-dependent assertions.
const TITLE := "res://src/screens/title_screen.gd"
var _pass := 0
var _fail := 0
var _baseline := false
var _report_path := "user://menu-return-performance.json"
var _samples: Array = []


func _ready() -> void:
	Settings.storage_path = "user://menu_return_performance_test-settings.cfg"
	for arg in OS.get_cmdline_user_args():
		if arg == "--baseline": _baseline = true
		if arg.begins_with("--report="): _report_path = arg.trim_prefix("--report=")
	_run.call_deferred()


func _frames(count := 8) -> void:
	for i in count: await get_tree().process_frame


func _ok(value: bool, message: String) -> void:
	if value:
		_pass += 1
		print("PASS ", message)
	else:
		_fail += 1
		push_error(message)


func _run() -> void:
	var saved_motion := Settings.reduced_motion
	Settings.reduced_motion = false
	var started := Time.get_ticks_usec()
	var main: Control = preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	var cold_ms := (Time.get_ticks_usec() - started) / 1000.0
	await _frames(30)
	var title: Control = Router.current
	var view: Control = title._courtyard
	var title_ref: WeakRef = weakref(title)
	var view_ref: WeakRef = weakref(view)
	var atmosphere: Node3D = view.stage.atmosphere
	var counts: Array = []
	for round_index in 10:
		GameState.start_new_run("v03")
		var data := EnemyData.new()
		data.id = "needle_wasp"
		data.name = "连针蜂"
		data.max_hp = 100
		data.moves = [EnemyMoveData.new()]
		var node := MapNodeData.new()
		node.enemies = [data]
		Router.goto("res://src/screens/battle_screen.gd", {"node": node, "seed": 7})
		await _frames(20)
		if not _baseline:
			_ok(title_ref.get_ref() == title and not title.visible and not title.can_process(), "hidden title is retained and cannot process")
			_ok(view.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "hidden courtyard viewport is disabled")
			if view.stage.mirror_viewport != null:
				_ok(view.stage.mirror_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "hidden reflection viewport is disabled")
			var clock: float = atmosphere.elapsed
			Settings.changed.emit()
			get_window().size += Vector2i(2, 0)
			await _frames()
			_ok(atmosphere.elapsed == clock and view.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "settings and resize cannot wake hidden scenery")
			get_window().size -= Vector2i(2, 0)
		PauseMenu.open()
		await _frames()
		var pause: PauseOverlay = PauseMenu._instance
		var battle_ref: WeakRef = weakref(Router.current)
		var button: Button
		for candidate in pause._buttons:
			if candidate.text.contains("返回主界面"): button = candidate
		_ok(button != null, "production pause menu exposes return action")
		# Begin at a frame boundary so the measured interval includes the button callback,
		# end-of-frame deletion, rendering and the next frame; no screenshots inside it.
		await get_tree().process_frame
		started = Time.get_ticks_usec()
		button.pressed.emit()
		var route_ms := (Time.get_ticks_usec() - started) / 1000.0
		var drawn_ms := -1.0
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			drawn_ms = (Time.get_ticks_usec() - started) / 1000.0
		var previous := started
		var gaps: Array = []
		var deadline := Time.get_ticks_usec() + 500000
		while Time.get_ticks_usec() < deadline:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			gaps.append((now - previous) / 1000.0)
			previous = now
		gaps.sort()
		var sample := {
			"round": round_index + 1, "route_cpu_ms": route_ms,
			"first_post_draw_ms": drawn_ms, "max_frame_gap_ms": gaps.back(),
			"p95_frame_gap_ms": gaps[mini(gaps.size() - 1, int(ceil(gaps.size() * 0.95)) - 1)],
			"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			"static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
			"video_memory_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
		}
		_samples.append(sample)
		counts.append(sample.nodes)
		print("MENU_RETURN ", JSON.stringify(sample))
		_ok(battle_ref.get_ref() == null and not is_instance_valid(PauseMenu._instance), "return releases battle and pause overlay")
		_ok(Router.current_path == TITLE and Router.current._can_interact(), "title is interactive after return")
		if not _baseline:
			_ok(Router.current == title_ref.get_ref() and Router.current._courtyard == view_ref.get_ref(), "return reuses the original title and courtyard")
			_ok(is_zero_approx(view.stage.inspection) and not title._buttons[0].disabled and title._menu.modulate.a == 1.0 and title._veil.color.a == 0.0, "return resets camera, buttons, menu and veil")
			_ok((view.is_processing() if view.mobile_quality else view.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS) and atmosphere.elapsed > 0, "visible courtyard resumes rendering")
		else:
			title = Router.current
			view = title._courtyard
	_ok(counts.back() == counts[0], "ten repeated returns keep node count stable")
	if not _baseline:
		# Leaving during the timed start must cancel it even though the title stays alive.
		title._on_start()
		Router.goto("res://src/screens/glyph_graph_screen.gd")
		await get_tree().create_timer(2.2).timeout
		_ok(Router.current_path.ends_with("/glyph_graph_screen.gd"), "suspended title cannot fire its old entry timer")
		Router.goto(TITLE)
		await _frames()
		_ok(not title._starting and title._modal_count == 0, "return clears entry and modal state")
		# Settings changed away from title take effect when it is shown again.
		Router.goto("res://src/screens/glyph_graph_screen.gd")
		Settings.reduced_motion = true
		Settings.changed.emit()
		Router.goto(TITLE)
		await _frames()
		_ok(not atmosphere.motion_enabled and not atmosphere.petals.visible, "resumed title applies current accessibility preferences")
	var report := {
		"platform": OS.get_name(), "model": OS.get_model_name(),
		"debug_build": OS.is_debug_build(), "headless": DisplayServer.get_name() == "headless",
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(), "window_size": str(get_window().size),
		"courtyard_mobile_quality": Router.current._courtyard.mobile_quality,
		"cold_main_cpu_ms": cold_ms, "baseline": _baseline, "samples": _samples
	}
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	_ok(file != null, "performance report is writable")
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
		print("REPORT ", ProjectSettings.globalize_path(_report_path))
	main.queue_free()
	await _frames(20)
	_ok(title_ref.get_ref() == null and view_ref.get_ref() == null and Router.host == null, "closing main releases cached title and courtyard")
	Settings.reduced_motion = saved_motion
	print("[menu_return_performance_test] PASS=%d FAIL=%d" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)
