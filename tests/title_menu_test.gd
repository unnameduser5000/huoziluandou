extends Control
## Exercise the production entry scene, UI routes and physical landscape hit targets.
var _pass := 0
var _fail := 0
var _capture := false
var _saved_motion := false
var _saved_style := ""


func _ready() -> void:
	_capture = OS.get_cmdline_user_args().has("--capture")
	_saved_motion = Settings.reduced_motion
	_saved_style = Settings.visual_style
	Settings.reduced_motion = false
	Ink.apply_style(GameStyle.taopunk())
	_run.call_deferred()


func _frames(count := 8) -> void:
	for i in count: await get_tree().process_frame


func _ok(condition: bool, description: String) -> void:
	if condition:
		_pass += 1
		print("PASS ", description)
	else:
		_fail += 1
		push_error(description)


func _shot(name: String) -> void:
	if not _capture: return
	await _frames()
	RenderingServer.force_draw(false)
	_ok(get_viewport().get_texture().get_image().save_png("res://shots/%s.png" % name) == OK, "capture " + name)


func _press(title: Control, caption: String) -> void:
	for button in title._buttons:
		if button.text == caption:
			button.pressed.emit()
			return
	_ok(false, "button exists: " + caption)


func _escape() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	Input.parse_input_event(key)
	await _frames()
	key = InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = false
	Input.parse_input_event(key)


func _run() -> void:
	var rng_before: int = GameState.rng.state
	var main: Control = preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(20)
	var title: Control = Router.current
	_ok(Router.current_path.ends_with("/title_screen.gd") and title.has_scene_background(), "normal project entry opens the courtyard title")
	var names: Array = []
	for button in title._buttons:
		if button.visible: names.append(button.text)
	var expected: Array = ["开始新冒险","新手教程","字库图鉴","成就总览","设置","离开","自定义构筑","字网图谱"]
	if load("res://src/expedition/room_run_state.gd").has_continuable_save(): expected.insert(1,"继续冒险")
	_ok(names == expected, "all existing title actions retained in the branded menu")
	_ok(GameState.rng.state == rng_before, "title rendering leaves gameplay RNG untouched")
	_ok(title._buttons[0].has_focus(), "keyboard focus starts on the primary action")
	await _shot("title-production-desktop")
	_press(title, "字库图鉴")
	await _frames()
	_ok(title._modal_count == 1 and title.find_children("*", "CollectionOverlay", true, false).size() == 1, "library button opens the real collection overlay")
	var library: CollectionOverlay = title.find_children("*", "CollectionOverlay", true, false)[0]
	_ok(is_instance_valid(library._relic_page), "production library includes the relic subpage")
	library._show_tab("relics")
	await _frames()
	_ok(library._relic_page.is_visible_in_tree() and library._relic_page._grid.get_child_count() == Relics.visible_ids().size(), "production relic tab shows every relic")
	_press(title, "设置")
	title._on_start()
	title._on_custom()
	_ok(not title._starting and Router.current == title and title._modal_count == 1, "modal prevents underlying start, settings and custom actions")
	await _escape()
	_ok(title._modal_count == 0 and not title._buttons[0].disabled, "ESC closes collection and unlocks the menu")
	_press(title, "成就总览")
	await _frames()
	_ok(title._modal_count == 1 and title.find_children("*", "AchievementOverlay", true, false).size() == 1, "achievement button opens the production overview")
	await _escape()
	_ok(title._modal_count == 0 and not title._buttons[0].disabled, "ESC closes achievements and restores title controls")
	_press(title, "设置")
	await _frames()
	_ok(title.find_children("*", "SettingsOverlay", true, false).size() == 1, "settings button opens shared production settings")
	Settings.reduced_motion = true
	Settings.changed.emit()
	var clock: float = title._courtyard.stage.atmosphere.elapsed
	await _frames()
	_ok(title._courtyard.stage.atmosphere.elapsed == clock and not title._courtyard.stage.atmosphere.petals.visible, "live reduced-motion preference pauses scenery and hides falling petals")
	await _escape()
	Settings.reduced_motion = false
	Settings.changed.emit()
	await _frames()
	_ok(title._courtyard.stage.atmosphere.elapsed > clock and title._courtyard.stage.atmosphere.petals.visible, "restoring motion resumes scenery")
	if _capture:
		var desktop_size := get_window().size
		get_window().size = Vector2i(960, 432)
		await _frames(16)
		var physical_scale := float(get_window().size.y) / title.size.y
		var touch_targets := true
		var visible_buttons := true
		for button in title._buttons:
			touch_targets = touch_targets and button.size.y * physical_scale >= 47.9
			visible_buttons = visible_buttons and title.get_global_rect().encloses(button.get_global_rect())
		_ok(touch_targets and visible_buttons, "960x432 landscape keeps every action visible with 48-pixel touch targets")
		await _shot("title-production-mobile")
		get_window().size = desktop_size
		await _frames(16)
	var old_view: WeakRef = weakref(title._courtyard)
	_press(title, "自定义构筑")
	await _frames()
	_ok(Router.current_path.ends_with("/custom_deck_screen.gd"), "custom deck button opens the existing builder")
	var cached_view: Control = old_view.get_ref()
	_ok(cached_view != null and not cached_view._active and cached_view.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "leaving title suspends cached scenery and viewport rendering")
	Router.goto("res://src/screens/title_screen.gd")
	await _frames()
	title = Router.current
	_press(title, "字网图谱")
	await _frames()
	_ok(Router.current_path.ends_with("/glyph_graph_screen.gd"), "glyph graph action still uses the existing route")
	_ok(not Router.study_stage.visible and Router.study_stage.find_children("*", "SubViewport", true, false).is_empty(), "glyph graph keeps the battle backdrop hidden without a legacy 3D viewport")
	Ink.apply_style(GameStyle.taopunk())
	Router.goto("res://src/screens/title_screen.gd")
	await _frames()
	_ok(Router.current._courtyard.visible and not Router.study_stage.visible, "title art stays consistent when the battle theme changes")
	main.queue_free()
	await _frames(16)
	_ok(Router.host == null and Router.current == null and not is_instance_valid(Router.study_stage), "closing main cleans the active screen, router host and persistent study")
	Settings.reduced_motion = _saved_motion
	Settings.visual_style = _saved_style
	Settings.changed.emit()
	Ink.apply_style(GameStyle.get_style(_saved_style))
	print("[title_menu_test] PASS=%d FAIL=%d" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
