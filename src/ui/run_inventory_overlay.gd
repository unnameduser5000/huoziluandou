extends "res://src/ui/modal_overlay.gd"
## 只读行囊：牌库按永久实体逐枚展示，不合并有不同强化的同名字。
var initial_tab := "deck"
var initial_relic := ""
var selected_relic := ""
var _relic_detail: VBoxContainer
var _tab := ""
var _body: VBoxContainer
var _tabs: Dictionary = {}
var _summary: Label
var _was_paused := false
var _previous_focus: Control
var _touch_scale := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_was_paused = get_tree().paused
	_previous_focus = get_viewport().gui_get_focus_owner()
	get_tree().paused = true
	tree_exiting.connect(func():
		get_tree().paused = _was_paused
		if is_instance_valid(_previous_focus): _previous_focus.grab_focus.call_deferred())
	JourneyStyle.apply(self)
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.07, 0.09, 0.92)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var margin := Ink.margin(16)
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(margin)
	var panel := Ink.panel("PanelCard")
	margin.add_child(panel)
	var col := Ink.vbox(10)
	panel.add_child(col)
	var header := Ink.hbox(12)
	col.add_child(header)
	header.add_child(JourneyStyle.label("行囊", "Heading", JourneyStyle.GOLD))
	header.add_child(Ink.expander())
	var close := JourneyStyle.button("关闭", _close)
	close.custom_minimum_size.y = 48 * JourneyStyle.touch_scale(self)
	header.add_child(close)
	_summary = JourneyStyle.label("牌库 %d 枚 · 遗物 %d 件 · 铜钱 %d" % [GameState.deck_size(), GameState.relics.size(), GameState.gold], "Muted")
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_summary)
	var tabs := HBoxContainer.new()
	col.add_child(tabs)
	for entry in [["deck", "牌库"], ["relics", "遗物"], ["gold", "铜钱"]]:
		var button := JourneyStyle.button(entry[1], show_tab.bind(entry[0]))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 48 * JourneyStyle.touch_scale(self)
		tabs.add_child(button)
		_tabs[entry[0]] = button
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_body = Ink.vbox(10)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	show_tab(initial_tab if _tabs.has(initial_tab) else "deck")
	resized.connect(_sync_scale.call_deferred)
	get_window().size_changed.connect(_sync_scale.call_deferred)
	_sync_scale()
	close.grab_focus()


func show_tab(tab: String) -> void:
	if not _tabs.has(tab): return
	_tab = tab
	for child in _body.get_children():
		_body.remove_child(child); child.queue_free()
	for key in _tabs: _tabs[key].theme_type_variation = "PrimaryButton" if key == tab else "GhostButton"
	match tab:
		"deck":
			if GameState.deck.is_empty(): _entry("牌库为空", "开始冒险后可查看本局持有的所有实体字。")
			for inst: CharInstance in GameState.deck:
				_entry("%s · %s　#%d" % [inst.glyph(), inst.data.pinyin, inst.uid], inst.describe())
		"relics":
			if GameState.relics.is_empty(): _entry("暂无遗物", "获得的遗物会按获得顺序显示在这里和常驻栏中。")
			else: _build_relics()
		"gold": _entry("铜钱 %d" % GameState.gold, "本局当前持有的铜钱，可在商店和部分事件中使用。")


func _build_relics() -> void:
	_relic_detail = Ink.vbox(8)
	_body.add_child(_relic_detail)
	var grid := HFlowContainer.new()
	grid.name = "OwnedRelicModels"
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_body.add_child(grid)
	var scale := JourneyStyle.touch_scale(self)
	for id: String in GameState.relics:
		var button := JourneyStyle.button("", _select_relic.bind(id))
		button.set_meta("relic_id", id)
		button.tooltip_text = Relics.text(id)
		button.custom_minimum_size = Vector2.ONE * 88 * scale
		grid.add_child(button)
		var preview := preload("res://src/ui/relic_preview.gd").new()
		preview.relic_id = id
		button.add_child(preview)
		preview.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		button.mouse_entered.connect(preview.highlight.bind(true))
		button.mouse_exited.connect(preview.highlight.bind(false))
	_select_relic(selected_relic if GameState.relics.has(selected_relic) else (initial_relic if GameState.relics.has(initial_relic) else GameState.relics[0]))


func _sync_scale() -> void:
	if not is_inside_tree(): return
	var factor := JourneyStyle.touch_scale(self)
	if is_equal_approx(factor, _touch_scale): return
	_touch_scale = factor
	JourneyStyle.apply(self)
	for button in find_children("*", "Button", true, false):
		button.custom_minimum_size = Vector2.ONE * 88 * factor if button.has_meta("relic_id") else Vector2(0,48*factor)
	for effect in find_children("*", "RichTextLabel", true, false):
		if effect is EffectText: effect.add_theme_font_size_override("normal_font_size", int(17*factor))
	if _tab == "relics" and GameState.relics.has(selected_relic): _select_relic(selected_relic)


func _select_relic(id: String) -> void:
	if not GameState.relics.has(id): return
	selected_relic = id
	for child in _relic_detail.get_children():
		_relic_detail.remove_child(child)
		child.queue_free()
	var scale := JourneyStyle.touch_scale(self)
	var preview := preload("res://src/ui/relic_preview.gd").new()
	preview.relic_id = id
	preview.custom_minimum_size = Vector2(0, minf(180 * scale, size.y * 0.28))
	_relic_detail.add_child(preview)
	var title := JourneyStyle.label(Relics.name_of(id), "Subheading", JourneyStyle.GOLD)
	_relic_detail.add_child(title)
	var body := Relics.desc_of(id)
	if Relics.needs_bind(id):
		var inst := GameState.relic_bound_inst(id)
		body += "\n绑定：【%s】 #%d" % [inst.glyph(), inst.uid] if inst != null else "\n绑定的字不在牌库中，当前不生效。"
	if id == "egg":
		var interval := maxi(1, BattleBalance.i("egg_interval", Relics.EGG_EVERY))
		body += "\n获胜进度：%d / %d" % [int(GameState.relic_counters.get(id, 0)) % interval, interval]
	var effects := EffectText.new()
	effects.set_effect_text(body)
	effects.add_theme_font_size_override("normal_font_size", int(17 * scale))
	_relic_detail.add_child(effects)


func _entry(title: String, body: String) -> void:
	var panel := Ink.panel("PanelInset")
	_body.add_child(panel)
	var col := Ink.vbox(6)
	panel.add_child(col)
	var label := JourneyStyle.label(title, "Subheading", JourneyStyle.GOLD)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(label)
	var effects := EffectText.new()
	effects.set_effect_text(body)
	effects.add_theme_font_size_override("normal_font_size", int(17 * JourneyStyle.touch_scale(self)))
	col.add_child(effects)


func _close() -> void:
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel_selection") or event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
