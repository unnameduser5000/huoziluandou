extends Control
class_name ChoiceOverlay
## 通用选择浮层：岔路、事件选项、商店确认都用它。
## cfg = { title, body, options: [{text, primary, disabled, hint}], on_choose: Callable(index) }

signal chose(index)

var cfg: Dictionary = {}
var _chosen := false
var _sheet: Control
var _options_scroll: ScrollContainer
var _options_content: VBoxContainer
var _panel: PanelContainer
var _padding: MarginContainer
var _peek_button: Button
var _peeking := false
var _dim_tap := TouchTap.new()
var _relic_scale := -1.0
var _relic_compact := false


static func show_details(host: Control, title: String, body: String) -> ChoiceOverlay:
	var overlay := ChoiceOverlay.new()
	overlay.setup({"title": title, "body": body, "hud_details": true, "scroll_body": true, "dismissible": true, "options": [{"text": "关闭", "primary": true}]})
	overlay.z_index = 100
	if host.has_method("_mount_overlay"): host.call("_mount_overlay", overlay)
	else: host.add_child(overlay)
	return overlay


static func show_relic_details(host: Control, id: String) -> ChoiceOverlay:
	var overlay := ChoiceOverlay.new()
	overlay.setup({"title":Relics.name_of(id), "relic_id":id, "body":Relics.desc_of(id), "hud_details":true, "scroll_body":true, "dismissible":true, "options":[{"text":"关闭", "primary":true}]})
	overlay.z_index = 100
	if host.has_method("_mount_overlay"): host.call("_mount_overlay", overlay)
	else: host.add_child(overlay)
	return overlay


func setup(p_cfg: Dictionary) -> void:
	cfg = p_cfg


func _ready() -> void:
	JourneyStyle.apply(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	resized.connect(_layout)
	# Canvas stretching can keep the logical size unchanged while the physical
	# window shrinks, so its touch scale also needs an explicit layout update.
	get_window().size_changed.connect(_layout.call_deferred)
	_layout.call_deferred()


func _build() -> void:
	var hud_scale := JourneyStyle.touch_scale(self)
	_sheet = Control.new()
	_sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_sheet)
	var dim := ColorRect.new()
	dim.color = Color(0.07, 0.06, 0.05, 0.66)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event):
		if cfg.get("dismissible", false) and cfg.get("dismiss_on_backdrop", true) and _dim_tap.matches(event, dim):
			_on_choose(int(cfg.get("cancel_index", 0))))
	_sheet.add_child(dim)

	_panel = Ink.panel("PanelCard")
	_sheet.add_child(_panel)
	var sheet_scroll := ScrollContainer.new()
	sheet_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	if cfg.get("scroll_options", false): sheet_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(sheet_scroll)

	var pad := Ink.margin(12 if cfg.get("compact", false) else 24)
	_padding = pad
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_scroll.add_child(pad)
	var col := Ink.vbox(4 if cfg.get("compact", false) else 14)
	pad.add_child(col)
	col.minimum_size_changed.connect(_layout.call_deferred)

	if not str(cfg.get("title", "")).is_empty():
		var heading := Ink.h2(BattleText.clean(str(cfg["title"])))
		if cfg.get("hud_details", false):
			heading.add_theme_font_size_override("font_size", int(24 * hud_scale))
			heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var relic_id := str(cfg.get("relic_id", ""))
		if RelicArt.texture(relic_id) != null:
			var header := HBoxContainer.new()
			header.add_theme_constant_override("separation", int(10 * hud_scale))
			var preview := preload("res://src/ui/relic_preview.gd").new()
			preview.relic_id = relic_id
			preview.custom_minimum_size = Vector2.ONE * 72 * hud_scale
			header.add_child(preview)
			heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			header.add_child(heading)
			col.add_child(header)
		else:
			col.add_child(heading)
	var relic_ids: Array = cfg.get("relics", [])
	if not relic_ids.is_empty():
		var specimens := HFlowContainer.new()
		for id in relic_ids:
			if RelicArt.texture(str(id)) == null: continue
			var button := Button.new()
			button.set_meta("relic_id", str(id))
			button.custom_minimum_size = Vector2.ONE * 56 * hud_scale
			button.tooltip_text = Relics.text(str(id))
			button.pressed.connect(ChoiceOverlay.show_relic_details.bind(self,str(id)))
			specimens.add_child(button)
			var preview := preload("res://src/ui/relic_preview.gd").new()
			preview.relic_id = str(id)
			button.add_child(preview)
			preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		col.add_child(specimens)
	if not str(cfg.get("body", "")).is_empty():
		var b: Control
		if cfg.get("hud_details", false):
			var effects := EffectText.new()
			effects.name = "EffectDetails"
			effects.set_effect_text(str(cfg["body"]))
			effects.add_theme_font_size_override("normal_font_size", int(18 * hud_scale))
			b = effects
		else:
			b = Ink.body(BattleText.clean(str(cfg["body"])))
		b.custom_minimum_size.x = 0
		if cfg.get("scroll_body", false):
			var scroll := ScrollContainer.new()
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			scroll.custom_minimum_size = Vector2(0, minf(320, get_viewport_rect().size.y * 0.4))
			col.add_child(scroll)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll.add_child(b)
		else:
			col.add_child(b)
	col.add_child(Ink.hline())

	var options: Array = cfg.get("options", [])
	if cfg.get("physical_relics", false):
		_build_relic_options(col, options, hud_scale)
		return
	var scroll_options := bool(cfg.get("scroll_options", false))
	var cancel_index := int(cfg.get("cancel_index", -1))
	var option_parent: VBoxContainer = col
	if scroll_options:
		z_index = 80
		_options_scroll = ScrollContainer.new()
		_options_scroll.name = "OptionsScroll"
		_options_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_options_scroll.follow_focus = true
		_options_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(_options_scroll)
		_options_content = Ink.vbox(10)
		_options_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_options_scroll.add_child(_options_content)
		option_parent = _options_content
	for i in options.size():
		if scroll_options and i == cancel_index: continue
		_add_option(option_parent, i, hud_scale)
	if scroll_options and cancel_index >= 0 and cancel_index < options.size():
		col.add_child(Ink.hline())
		_add_option(col, cancel_index, hud_scale)
	if scroll_options:
		_layout.call_deferred()

	if cfg.get("board_peek", false):
		_peek_button = JourneyStyle.button("查看棋盘", _toggle_peek)
		add_child(_peek_button)


func _build_relic_options(col: VBoxContainer, options: Array, scale: float) -> void:
	var compact := size.y / scale < 600
	var row := HBoxContainer.new()
	row.name = "RelicChoices"
	row.add_theme_constant_override("separation", int(14 * scale))
	col.add_child(row)
	for i in options.size():
		var opt: Dictionary = options[i]
		var id := str(opt.get("relic_id", ""))
		if id.is_empty():
			var skip := Ink.button(str(opt.get("text", "不要")))
			skip.custom_minimum_size.y = 48 * scale
			skip.pressed.connect(_on_choose.bind(i))
			col.add_child(skip)
			continue
		var card := VBoxContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_constant_override("separation", int(5 * scale))
		row.add_child(card)
		var object_button := Button.new()
		object_button.name = "Take_" + id
		object_button.custom_minimum_size.y = (86 if compact else 210) * scale
		object_button.flat = true
		object_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		object_button.focus_mode = Control.FOCUS_NONE
		object_button.tooltip_text = Relics.text(id)
		object_button.disabled = bool(opt.get("disabled", false))
		object_button.pressed.connect(_on_choose.bind(i))
		card.add_child(object_button)
		var preview := preload("res://src/ui/relic_preview.gd").new()
		preview.relic_id = id
		object_button.add_child(preview)
		preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var button := Ink.button(Relics.name_of(id), bool(opt.get("primary", false)))
		button.focus_mode = Control.FOCUS_ALL
		button.set_meta("relic_choice_index", i)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size.y = 48 * scale
		button.add_theme_font_size_override("font_size", int(18 * scale))
		button.disabled = object_button.disabled
		button.tooltip_text = Relics.text(id)
		RelicArt.apply_button(button, id, 28 * scale)
		button.pressed.connect(_on_choose.bind(i))
		card.add_child(button)
		object_button.mouse_entered.connect(preview.highlight.bind(true))
		object_button.mouse_exited.connect(preview.highlight.bind(false))
		button.focus_entered.connect(preview.highlight.bind(true))
		button.focus_exited.connect(preview.highlight.bind(false))
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size.y = (66 if compact else 100) * scale
		card.add_child(scroll)
		var hint := Ink.label(BattleText.clean(str(opt.get("hint", ""))), "Muted")
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hint.add_theme_font_size_override("font_size", int(16 * scale))
		scroll.add_child(hint)


func relic_choice_buttons() -> Array:
	return find_children("*", "Button", true, false).filter(func(button): return button.has_meta("relic_choice_index"))


func _resize_relic_options(scale: float) -> void:
	var compact := size.y / scale < 600
	if is_equal_approx(scale, _relic_scale) and compact == _relic_compact: return
	_relic_scale = scale
	_relic_compact = compact
	JourneyStyle.apply(self)
	var row := find_child("RelicChoices", true, false) as HBoxContainer
	if row == null: return
	row.add_theme_constant_override("separation", int(14 * scale))
	for card in row.get_children():
		card.add_theme_constant_override("separation", int(5 * scale))
		card.get_child(0).custom_minimum_size.y = (86 if compact else 210) * scale
		var button: Button = card.get_child(1)
		button.custom_minimum_size.y = 48 * scale
		button.add_theme_font_size_override("font_size", int(18 * scale))
		RelicArt.apply_button(button, str(button.get_meta("relic_id")), 28 * scale)
		var scroll: ScrollContainer = card.get_child(2)
		scroll.custom_minimum_size.y = (66 if compact else 100) * scale
		scroll.get_child(0).add_theme_font_size_override("font_size", int(16 * scale))


func _layout() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or _panel == null or size.y < 1: return
	var scale := JourneyStyle.touch_scale(self)
	var safe := ScreenLayout.safe_rect(self)
	var area := safe.size
	if cfg.get("physical_relics", false): _resize_relic_options(scale)
	var top := 16.0 * scale
	if _peek_button != null:
		_peek_button.size = Vector2(200, 48) * scale
		_peek_button.position = safe.position + Vector2(area.x - _peek_button.size.x - 16 * scale, top)
		top += _peek_button.size.y + 8 * scale
	_fit_scroll_options()
	var skin := _panel.get_theme_stylebox("panel")
	var width := 520.0
	if cfg.get("physical_relics", false):
		var count: int = cfg.get("options", []).filter(func(option): return option.has("relic_id")).size()
		width = 400.0 if count == 1 else 1000.0
	_panel.size = Vector2(minf(width * scale, area.x - 32 * scale), minf(_padding.get_combined_minimum_size().y + skin.get_minimum_size().y, area.y - top - 16 * scale))
	_panel.position = safe.position + Vector2((area.x - _panel.size.x) * 0.5, top + (area.y - top - 16 * scale - _panel.size.y) * 0.5)


func _toggle_peek() -> void:
	_peeking = not _peeking
	_sheet.visible = not _peeking
	_peek_button.text = "返回选择" if _peeking else "查看棋盘"
	_peek_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _peeking and event.is_action_pressed("cancel_selection"):
		_toggle_peek()
		get_viewport().set_input_as_handled()
	elif cfg.get("dismissible", false) and event.is_action_pressed("cancel_selection"):
		get_viewport().set_input_as_handled()
		_on_choose(int(cfg.get("cancel_index", 0)))


func _add_option(parent: VBoxContainer, index: int, hud_scale: float) -> void:
	var opt: Dictionary = cfg.options[index]
	var btn := Ink.button(BattleText.clean(str(opt.get("text", "选项 %d" % (index + 1)))), bool(opt.get("primary", false)))
	btn.name = "Option_%d" % index
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if opt.has("relic_id"): RelicArt.apply_button(btn, str(opt.relic_id), 48 * hud_scale)
	btn.focus_mode = Control.FOCUS_ALL
	btn.custom_minimum_size.y = 48 * hud_scale
	btn.add_theme_font_size_override("font_size", int(20 * hud_scale))
	btn.disabled = bool(opt.get("disabled", false))
	btn.pressed.connect(_on_choose.bind(index))
	parent.add_child(btn)
	if not str(opt.get("hint", "")).is_empty():
		var hint := Ink.label(BattleText.clean(str(opt.hint)), "Muted")
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		parent.add_child(hint)


func _fit_scroll_options() -> void:
	if _options_scroll == null or not is_inside_tree(): return
	# 标题、说明与取消固定在列表外；只有候选区按剩余高度滚动。
	var fixed_height := _padding.get_combined_minimum_size().y - _options_scroll.custom_minimum_size.y + _panel.get_theme_stylebox("panel").get_minimum_size().y
	var available := maxf(48, size.y - 32 * JourneyStyle.touch_scale(self) - fixed_height)
	_options_scroll.custom_minimum_size.y = minf(_options_content.get_combined_minimum_size().y, available)


func _unhandled_key_input(event: InputEvent) -> void:
	if not cfg.get("scroll_options", false): return
	var cancel_index := int(cfg.get("cancel_index", -1))
	if event.is_action_pressed("ui_cancel") and cancel_index >= 0:
		accept_event()
		_on_choose(cancel_index)



func _on_choose(index: int) -> void:
	var options: Array = cfg.get("options", [])
	if _chosen or index < 0 or index >= options.size() or bool(options[index].get("disabled", false)):
		return
	_chosen = true
	chose.emit(index)
	var cb = cfg.get("on_choose", null)
	if cb is Callable and cb.is_valid():
		cb.call(index)
	# 立即从场景树摘除，让父级（如战斗页的 _modal_count）在本次点击内即可恢复盘面交互。
	if is_inside_tree():
		get_parent().remove_child(self)
	queue_free()
