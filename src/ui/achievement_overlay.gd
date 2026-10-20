extends "res://src/ui/modal_overlay.gd"
class_name AchievementOverlay
signal closed

var panel: PanelContainer
var grid: GridContainer
var summary: Label
var category: OptionButton
var state_filter: OptionButton
var search: LineEdit
var scroll: ScrollContainer
var _updating := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	JourneyStyle.apply(self)
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.04, 0.045, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("102e31")
	style.border_color = Color("8f7c50")
	style.set_border_width_all(1)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	panel.add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	header.add_child(_label("玉符成就", 28, Color("e6d9b8")))
	summary = _label("", 17, Color("a6beb2"))
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(summary)
	var close := JourneyStyle.button("关闭", _close)
	close.custom_minimum_size = Vector2(80, 46)
	header.add_child(close)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 12)
	body.add_child(filters)
	category = OptionButton.new()
	category.name = "AchievementCategory"
	category.add_item("全部分类")
	var categories := []
	for definition in Achievements.definitions:
		if not categories.has(definition.category): categories.append(definition.category); category.add_item(definition.category)
	category.item_selected.connect(func(_index): _refresh())
	filters.add_child(category)
	state_filter = OptionButton.new()
	state_filter.name = "AchievementState"
	for text in ["全部状态", "已解锁", "未解锁"]: state_filter.add_item(text)
	state_filter.item_selected.connect(func(_index): _refresh())
	filters.add_child(state_filter)
	search = LineEdit.new()
	search.name = "AchievementSearch"
	search.placeholder_text = "搜索名称或达成条件"
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(_value): _refresh())
	filters.add_child(search)
	for control in [category, state_filter, search]: control.custom_minimum_size.y = 44
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	grid = GridContainer.new()
	grid.name = "AchievementCards"
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	body.add_child(_label("玉符永久收藏。单局、单战和单回合条件显示历史最高记录；成就不增加战斗数值。", 14, Color("9cab9d")))
	Achievements.changed.connect(_schedule_refresh)
	resized.connect(_layout)
	_layout()
	_refresh()
	close.grab_focus.call_deferred()


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", Ink.serif)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _layout() -> void:
	if panel == null: return
	var margin := 20.0 if size.x >= 700 else 8.0
	panel.position = Vector2(margin, margin)
	panel.size = size - Vector2(margin, margin) * 2
	grid.columns = maxi(1, mini(4, int((panel.size.x - 40) / 265)))


func _schedule_refresh() -> void:
	if _updating: return
	_updating = true
	_refresh.call_deferred()


func _refresh() -> void:
	if grid == null or not is_inside_tree(): return
	_updating = false
	for card in grid.get_children(): grid.remove_child(card); card.queue_free()
	var enabled := 0
	var unlocked_count := 0
	var shown := 0
	for definition in Achievements.definitions:
		if not bool(definition.enabled): continue
		enabled += 1
		var unlocked := Achievements.is_unlocked(definition.id)
		if unlocked: unlocked_count += 1
		if category.selected > 0 and category.get_item_text(category.selected) != definition.category: continue
		if state_filter.selected == 1 and not unlocked or state_filter.selected == 2 and unlocked: continue
		var query := search.text.strip_edges()
		if not query.is_empty() and not (str(definition.name) + AchievementArt.title(definition) + str(definition.description)).contains(query): continue
		grid.add_child(_card(definition, unlocked))
		shown += 1
	summary.text = "已解锁 %d / %d" % [unlocked_count, enabled]
	if shown == 0: grid.add_child(_label("没有符合筛选条件的成就。", 18, Color("b8c4b4")))


func _card(definition: Dictionary, unlocked: bool) -> Control:
	var card := PanelContainer.new()
	card.name = "Achievement_" + str(definition.id)
	card.set_meta("achievement_id", definition.id)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(240, 205)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("163c3a") if unlocked else Color("102f31")
	style.border_color = Color("9ba77b") if unlocked else Color("365452")
	style.set_border_width_all(1)
	style.set_content_margin_all(14)
	card.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	card.add_child(col)
	var top := HBoxContainer.new()
	col.add_child(top)
	top.add_child(AchievementArt.icon(definition, 68, unlocked))
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(names)
	var title := _label(AchievementArt.title(definition), 21, Color("e1d7b8"))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(title)
	names.add_child(_label("已解锁" if unlocked else "未解锁", 16, Color("b0c69a") if unlocked else Color("b8beb0")))
	var condition := _label("达成条件：" + str(definition.description), 16, Color("d0d5c0"))
	condition.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	condition.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(condition)
	var maximum := int(definition.target)
	var amount := mini(maximum, Achievements.progress(definition.id))
	var bar := ProgressBar.new()
	bar.name = "Progress"
	bar.max_value = maximum
	bar.value = maximum if unlocked else amount
	bar.show_percentage = false
	bar.custom_minimum_size.y = 8
	col.add_child(bar)
	var prefix := "累计进度" if definition.scope == "lifetime" else "最高记录"
	col.add_child(_label("%s：%d / %d" % [prefix, amount, maximum], 14, Color("a2b6aa")))
	var pending: Array = []
	for id in definition.prerequisites:
		if not Achievements.is_unlocked(id) and Achievements.by_id.has(id): pending.append(AchievementArt.title(Achievements.by_id[id]))
	if not pending.is_empty():
		var prerequisite := _label("需先解锁：" + "、".join(pending), 13, Color("c7af80"))
		prerequisite.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(prerequisite)
	if unlocked: Achievements.mark_read(definition.id)
	return card


func _close() -> void:
	closed.emit()
	queue_free()
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"): _close()
