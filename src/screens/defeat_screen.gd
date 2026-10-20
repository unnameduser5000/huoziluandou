extends ScreenBase
## One snapshot, six explicit score lines, and a short cancellable reveal.
var _rows: Array = []
var _total := 0
var _expedition := false
var _score_label: Label
var _row_lines: Array[VBoxContainer] = []
var _buttons: HBoxContainer
var _skip_button: Button
var _restart_button: Button
var _title_button: Button
var _page: PanelContainer
var _body: HBoxContainer
var _score_column: VBoxContainer
var _rows_scroll: ScrollContainer
var _rows_column: GridContainer
var _rules_overlay: ChoiceOverlay
var _revealing := true
var _reveal_tween: Tween
var _leaving := false
var _layout_unit := -1.0
var _layout_columns := 0


func build(root: Control) -> void:
	var result: Dictionary = params.get("settlement", {"rows": [], "total": 0})
	_rows = result.get("rows", []).duplicate(true)
	_total = int(result.get("total", 0))
	_expedition = bool(params.get("expedition", false))
	_page = Ink.panel("PanelCard")
	root.add_child(_page)
	var column := Ink.vbox(12)
	_page.add_child(column)
	var header := Ink.body("%s  /  %s" % [result.get("mode", "行旅结算"), result.get("location", "未竟之途")])
	header.theme_type_variation = "Muted"
	column.add_child(header)
	column.add_child(Ink.hline(JourneyStyle.EDGE))
	_body = Ink.hbox(32)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_body)
	var score_center := CenterContainer.new()
	score_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(score_center)
	_score_column = Ink.vbox(10)
	score_center.add_child(_score_column)
	var title := Ink.h2("力竭")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_column.add_child(title)
	var caption := Ink.label("终局分数", "Muted")
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_column.add_child(caption)
	_score_label = Ink.label("0", "Stat")
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_column.add_child(_score_label)
	var epilogue := Ink.label("字散墨枯，余响未息。", "Muted")
	epilogue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_column.add_child(epilogue)
	_rows_scroll = ScrollContainer.new()
	_rows_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rows_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_scroll.size_flags_stretch_ratio = 1.8
	_body.add_child(_rows_scroll)
	_rows_column = GridContainer.new()
	_rows_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_column.add_theme_constant_override("h_separation", 18)
	_rows_column.add_theme_constant_override("v_separation", 8)
	_rows_scroll.add_child(_rows_column)
	for row in _rows:
		var line := Ink.vbox(0)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var heading := Ink.hbox(12)
		var label := Ink.label(str(row.get("label", "")))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_child(label)
		var score := Ink.label("+%d" % int(row.get("score", 0)), "Stat")
		heading.add_child(score)
		line.add_child(heading)
		var detail := Ink.body(str(row.get("detail", "")))
		detail.theme_type_variation = "Muted"
		line.add_child(detail)
		_rows_column.add_child(line)
		_row_lines.append(line)
		line.modulate.a = 0.0
	_buttons = Ink.hbox(12)
	column.add_child(Ink.hline(JourneyStyle.EDGE))
	column.add_child(_buttons)
	_restart_button = JourneyStyle.button("重新开始", _restart, true)
	_restart_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buttons.add_child(_restart_button)
	_title_button = JourneyStyle.button("返回标题", _return_title)
	_title_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buttons.add_child(_title_button)
	_skip_button = JourneyStyle.button("跳过动画", _on_auxiliary)
	_buttons.add_child(_skip_button)
	resized.connect(_layout)
	_page.minimum_size_changed.connect(_layout.call_deferred)
	_layout.call_deferred()
	_reveal.call_deferred()


func _layout() -> void:
	if _page == null: return
	var unit := JourneyStyle.touch_scale(self)
	var margin := 12 * unit
	var columns := 2 if size.y / unit < 500 else 1
	# Font overrides invalidate minimum sizes; only change them when density/layout changes.
	if not is_equal_approx(_layout_unit, unit) or columns != _layout_columns:
		_layout_unit = unit
		_layout_columns = columns
		_rows_column.columns = columns
		_rows_column.add_theme_constant_override("h_separation", int(20 * unit))
		for line in _row_lines:
			line.get_child(1).add_theme_font_size_override("font_size", int((14 if columns == 2 else 16) * unit))
		_body.add_theme_constant_override("separation", int(24 * unit))
		_score_column.custom_minimum_size.x = 180 * unit
		_score_label.add_theme_font_size_override("font_size", int(64 * unit))
		for button in [_restart_button, _title_button, _skip_button]:
			button.custom_minimum_size.y = 48 * unit
	_page.size = Vector2(minf(1080 * unit, size.x - margin * 2), minf(620 * unit, size.y - margin * 2))
	_page.position = (size - _page.size) * 0.5


func _reveal() -> void:
	if not _revealing or not is_inside_tree(): return
	if Settings.reduced_motion:
		_reveal_all()
		return
	_reveal_tween = create_tween()
	var subtotal := 0
	for i in _rows.size():
		_reveal_tween.tween_property(_row_lines[i], "modulate:a", 1.0, 0.12)
		var next_total := subtotal + int(_rows[i].get("score", 0))
		_reveal_tween.tween_method(_set_score, subtotal, next_total, 0.20)
		subtotal = next_total
	_reveal_tween.tween_callback(_finish_reveal)


func _set_score(value: int) -> void:
	_score_label.text = str(value)


func _finish_reveal() -> void:
	_revealing = false
	_set_score(_total)
	_skip_button.text = "计分规则"


func _reveal_all() -> void:
	if not _revealing: return
	if _reveal_tween != null: _reveal_tween.kill()
	for line in _row_lines: line.modulate.a = 1.0
	_finish_reveal()


func _input(event: InputEvent) -> void:
	# Resolve ESC/Android back here, before the global adventure pause menu.
	if is_instance_valid(_rules_overlay): return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _revealing: _reveal_all()
		else: _return_title()
	elif _revealing and event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_reveal_all()


func _on_auxiliary() -> void:
	if _revealing:
		_reveal_all()
	else:
		_rules_overlay = ChoiceOverlay.show_details(self, "计分规则", "行旅足迹：每个已完成节点或远征地点 100 分，同一地点只算一次。远征伏兵单独计数。\n破关：每个击败首领的幕 500 分。\n末战击倒：最后一战中，每个已倒下的敌人 30 分。\n末战攻坚：敌方当前净损失气血占总气血的比例 × 战斗基分，向下取整。普通战 30、精英 75、首领 150。护盾、重复伤害、耗时和回合数不计分。\n收集遗物：每件现有遗物 40 分。\n剩余铜钱：每枚铜钱 5 分，最多 300 分。\n\n分数是本次冒险的成绩，不会转换为铜钱或恢复已经结束的存档。")


func _restart() -> void:
	if _leaving: return
	_leaving = true
	if params.get("room_run", false):
		load("res://src/expedition/room_run_state.gd").start()
		goto("res://src/screens/room_map_screen.gd")
	elif _expedition:
		Expedition.start()
		goto("res://src/screens/expedition_map_screen.gd")
	else:
		GameState.start_new_run("v03")
		goto("res://src/screens/map_screen.gd")


func _return_title() -> void:
	if _leaving: return
	_leaving = true
	goto("res://src/screens/title_screen.gd")
