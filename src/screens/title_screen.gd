extends ScreenBase
## Courtyard title menu. Scenery owns presentation; this screen retains existing run entry.
const CourtyardView := preload("res://src/title/courtyard_view.gd")
var _courtyard: Control
var _menu: GridContainer
var _buttons: Array[Button] = []
var _expedition := false
var _entry_timer: Timer
var _menu_tween: Tween
var _starting := false
var _modal_count := 0
var _veil: ColorRect
var _wordmark: TextureRect
var _ornament: Control
var _utilities: HBoxContainer
var _continue_button: Button
var _main_buttons: Array[Button] = []


func set_route_active(active: bool) -> void:
	visible = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	_reset_entry()
	if active: _refresh_continue()
	if active and _modal_count == 0 and not _buttons.is_empty(): _buttons[0].grab_focus.call_deferred()
	if is_instance_valid(_courtyard):
		_courtyard.set_active(active)
		if active: _courtyard.reset_camera()


func has_scene_background() -> bool:
	return true


func has_run_inventory() -> bool:
	return false


func build(root: Control) -> void:
	_courtyard = CourtyardView.new()
	root.add_child(_courtyard)
	_ornament = preload("res://src/title/title_menu_ornament.gd").new()
	root.add_child(_ornament); _ornament.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wordmark = TextureRect.new(); _wordmark.name = "LianziyuWordmark"
	_wordmark.texture = preload("res://assets/title/branding/lianziyu-wordmark-v1.png")
	_wordmark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; _wordmark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_wordmark.mouse_filter = Control.MOUSE_FILTER_IGNORE; root.add_child(_wordmark)
	_menu = GridContainer.new(); _menu.columns = 1
	root.add_child(_menu)
	_menu.add_child(_button("开始新冒险", _on_start, true))
	_continue_button = _button("继续冒险", _on_continue)
	_menu.add_child(_continue_button)
	_menu.add_child(_button("新手教程",_on_tutorial))
	_refresh_continue()
	SaveManager.availability_changed.connect(_refresh_continue)
	_menu.add_child(_button("字库图鉴",_on_library))
	_menu.add_child(_button("成就总览",_on_achievements))
	_menu.add_child(_button("设置",_open_settings))
	_menu.add_child(_button("离开",_quit))
	_main_buttons.assign(_buttons)
	_ornament.setup(_main_buttons)
	_utilities = HBoxContainer.new(); root.add_child(_utilities)
	for entry in [["自定义构筑",_on_custom],["字网图谱",_on_graph]]:
		_utilities.add_child(_button(entry[0],entry[1]))
	_veil = ColorRect.new()
	_veil.color = Color(0.025, 0.06, 0.075, 0.0)
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_veil)
	_entry_timer = Timer.new()
	_entry_timer.one_shot = true
	_entry_timer.timeout.connect(_finish_start)
	add_child(_entry_timer)
	resized.connect(_layout)
	_menu.minimum_size_changed.connect(_layout.call_deferred)
	_layout.call_deferred()
	_buttons[0].grab_focus.call_deferred()


func _button(text: String, callback: Callable, primary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", Ink.serif)
	var color := Color("e6d8ad") if primary else Color("d0bd92")
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_disabled_color", color)
	button.add_theme_color_override("font_hover_color", Color("f1e6c5"))
	button.add_theme_color_override("font_focus_color", Color("f1e6c5"))
	button.add_theme_color_override("font_pressed_color", Color("c35843"))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color.TRANSPARENT
		style.content_margin_left = 26
		style.content_margin_right = 6
		style.border_width_left = 0
		style.border_color = Color("b5503c")
		button.add_theme_stylebox_override(state, style)
	button.set_meta("primary", primary)
	button.pressed.connect(callback)
	_buttons.append(button)
	return button


func _layout() -> void:
	if _menu == null or content.size.y < 1: return
	# Reserve physical touch targets instead of scaling the entire menu down on phones.
	var touch_scale := JourneyStyle.touch_scale(self)
	var safe := ScreenLayout.safe_rect(content).intersection(Rect2(Vector2.ZERO,content.size))
	var area := safe.size
	var compact := area.y / touch_scale < 600
	_menu.columns = (3 if area.y/touch_scale<300 else 2) if compact else 1
	_menu.add_theme_constant_override("v_separation", int(6 * touch_scale))
	_menu.add_theme_constant_override("h_separation", int(36 * touch_scale))
	for button in _buttons:
		button.custom_minimum_size.y = 48 * touch_scale
		var utility := button.get_parent()==_utilities
		button.add_theme_font_size_override("font_size", int((14 if utility else 23) * touch_scale))
	var width := minf(300 * touch_scale, area.x*.40) if not compact else area.x*(0.80 if _menu.columns==3 else 0.51)
	_menu.custom_minimum_size.x = width
	_menu.size.x = width
	_menu.reset_size()
	var height := _menu.get_combined_minimum_size().y
	var margin := 18*touch_scale
	_utilities.add_theme_constant_override("separation",int(6*touch_scale))
	_utilities.reset_size(); _utilities.position = safe.position+Vector2(maxf(margin,area.x*.10),area.y-margin-_utilities.size.y)
	var logo_top: float = margin+(0.0 if compact else area.y*.03)
	var logo_height := minf(area.y*.44,maxf(64,_utilities.position.y-safe.position.y-height-logo_top-margin-12*touch_scale))
	var logo_width := minf(area.x*.53,logo_height*1.776)
	_wordmark.position = safe.position+Vector2(area.x*.035,logo_top); _wordmark.size = Vector2(logo_width,logo_height)
	_menu.position = Vector2(safe.position.x+maxf(margin+22,area.x*.13),_wordmark.position.y+logo_height+12*touch_scale)
	_ornament.queue_redraw()


func _can_interact() -> bool:
	return not _starting and _modal_count == 0 and not is_queued_for_deletion()


func _lock_buttons() -> void:
	for button in _buttons:
		button.disabled = _starting or _modal_count > 0


func _on_start() -> void:
	if not _can_interact(): return
	_starting = true
	_lock_buttons()
	_wordmark.hide(); _ornament.hide(); _utilities.hide()
	var duration: float = _courtyard.enter()
	if _menu_tween != null: _menu_tween.kill()
	_menu_tween = create_tween()
	_menu_tween.tween_property(_menu, "modulate:a", 0.0, minf(0.22, duration))
	if not Settings.reduced_motion:
		_menu_tween.tween_interval(maxf(0.0, duration - 0.40))
		_menu_tween.tween_property(_veil, "color:a", 1.0, 0.18)
	_entry_timer.start(duration)


func _finish_start() -> void:
	if not _starting or is_queued_for_deletion(): return
	if _expedition:
		Expedition.start()
		Achievements.start_run("expedition")
		goto("res://src/screens/expedition_map_screen.gd")
		return
	if not Settings.first_run_tutorial_completed:
		goto("res://src/screens/tutorial_screen.gd", {"start_adventure": true})
		return
	load("res://src/expedition/room_run_state.gd").start()
	goto("res://src/screens/room_map_screen.gd")



func _cancel_entry() -> void:
	if not _starting: return
	_reset_entry()
	_courtyard.reset_camera()
	_buttons[0].grab_focus.call_deferred()


func _reset_entry() -> void:
	# The title is retained by Router, so restore every part hidden by _on_start.
	_expedition = false
	_starting = false
	if is_instance_valid(_entry_timer): _entry_timer.stop()
	if _menu_tween != null: _menu_tween.kill()
	if is_instance_valid(_menu): _menu.modulate.a = 1.0
	if is_instance_valid(_wordmark): _wordmark.show()
	if is_instance_valid(_ornament): _ornament.show()
	if is_instance_valid(_utilities): _utilities.show()
	if is_instance_valid(_veil): _veil.color.a = 0.0
	_lock_buttons()


func _mount_overlay(overlay: Control) -> void:
	var previous_focus := get_viewport().gui_get_focus_owner()
	_modal_count += 1
	_lock_buttons()
	overlay.tree_exited.connect(func():
		_modal_count = maxi(0, _modal_count - 1)
		if is_inside_tree() and not is_queued_for_deletion():
			_lock_buttons()
			if is_instance_valid(previous_focus): previous_focus.grab_focus.call_deferred())
	add_child(overlay)


func _open_settings() -> void:
	if _can_interact(): _mount_overlay(SettingsOverlay.new())


func _on_custom() -> void:
	if _can_interact(): goto("res://src/screens/custom_deck_screen.gd")


func _on_tutorial() -> void:
	if _can_interact(): goto("res://src/screens/tutorial_screen.gd")


func _on_library() -> void:
	if not _can_interact(): return
	var viewer := CollectionOverlay.new()
	viewer.setup({"title": "字库图鉴", "subtitle": "%d 种实体字 · %d 个词" % [Database.characters.size() - 1, Database.words.size()], "words": Database.words.values(), "show_relics": true})
	_mount_overlay(viewer)


func _on_achievements() -> void:
	if _can_interact(): _mount_overlay(AchievementOverlay.new())


func _on_graph() -> void:
	if _can_interact(): goto("res://src/screens/glyph_graph_screen.gd")


func _quit() -> void:
	if _can_interact(): get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if _starting and event.is_action_pressed("cancel_selection"):
		_cancel_entry()
		get_viewport().set_input_as_handled()


func _on_continue_rooms() -> void:
	if not _can_interact(): return
	var run = load("res://src/expedition/room_run_state.gd").restore(load("res://src/expedition/room_run_state.gd").SAVE_PATH,true)
	if run!=null:
		if run.phase == "defeat" or GameState.player_hp <= 0: goto("res://src/screens/run_result_screen.gd")
		else: goto("res://src/screens/room_map_screen.gd")


func _refresh_continue() -> void:
	if is_instance_valid(_continue_button):
		_continue_button.visible = SaveManager.has_save() or (not bool(GameState.get_meta("courtyard_preview", false)) and load("res://src/expedition/room_run_state.gd").has_continuable_save())


func _on_continue() -> void:
	if not _can_interact(): return
	if SaveManager.has_save(): SaveManager.resume_run()
	else: _on_continue_rooms()
