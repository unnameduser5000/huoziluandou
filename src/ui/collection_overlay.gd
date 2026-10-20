extends Control
class_name CollectionOverlay
## 通用浏览浮层：字库图鉴 / 当前字袋 / 选字。cfg 见 setup()。

signal closed
signal picked(item)

var cfg: Dictionary = {}
var _grid: GridContainer
var _tab_bar: HBoxContainer
var _mode := "chars"
var _word_grid: GridContainer
var _scroll: ScrollContainer
var _counts: Dictionary = {}
var _dim_tap := TouchTap.new()
var _relic_page: RelicCompendiumOverlay
var _closing := false
var _picked := false


static func open_deck(owner: Control) -> void:
	for child in owner.get_children():
		if child is CollectionOverlay: return
	var counts := GameState.glyph_counts()
	var characters: Array = []
	for glyph in counts:
		var character: CharacterData = Database.get_character_by_glyph(glyph)
		if character != null: characters.append(character)
	var overlay := CollectionOverlay.new()
	overlay.setup({"title": "字袋", "subtitle": "共 %d 枚 · 仅查看" % GameState.deck_size(), "characters": characters, "counts": counts})
	owner.add_child(overlay)


func setup(p_cfg: Dictionary) -> void:
	cfg = p_cfg


func _ready() -> void:
	JourneyStyle.apply(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_counts = cfg.get("counts", {})
	_build()
	_show_tab("chars")


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.07, 0.09, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	var frame := MarginContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_constant_override("margin_left", 16)
	frame.add_theme_constant_override("margin_right", 16)
	frame.add_theme_constant_override("margin_top", 16)
	frame.add_theme_constant_override("margin_bottom", 16)
	add_child(frame)

	var panel := Ink.panel("PanelCard")
	frame.add_child(panel)

	var pad := Ink.margin(18)
	panel.add_child(pad)
	var col := Ink.vbox(10)
	pad.add_child(col)

	var head := Ink.hbox(12)
	col.add_child(head)
	var headings := JourneyStyle.flow(12)
	headings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(headings)
	var title := Ink.h2(cfg.get("title", "字库图鉴"))
	headings.add_child(title)
	if not str(cfg.get("subtitle", "")).is_empty():
		var st := Ink.label(str(cfg["subtitle"]), "Muted")
		st.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		st.custom_minimum_size.x = minf(400, size.x * 0.22)
		headings.add_child(st)

	var close := Ink.button(str(cfg.get("close_text", "关闭")))
	close.theme_type_variation = "GhostButton"
	close.custom_minimum_size = Vector2(90, ceilf(48 * JourneyStyle.touch_scale(self)))
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(_close)
	head.add_child(close)

	_tab_bar = Ink.hbox(8)
	col.add_child(_tab_bar)
	_add_tab("实体字", "chars")
	if not (cfg.get("words", []) as Array).is_empty():
		_add_tab("词", "words")

	if cfg.get("show_relics", false) and not cfg.get("pick_on_click", false):
		_add_tab("遗物", "relics")

	col.add_child(Ink.hline())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)

	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(wrap)

	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	wrap.add_child(_grid)

	_word_grid = GridContainer.new()
	_word_grid.columns = 4
	_word_grid.add_theme_constant_override("h_separation", 10)
	_word_grid.add_theme_constant_override("v_separation", 10)
	_word_grid.visible = false
	wrap.add_child(_word_grid)

	if cfg.get("show_relics", false) and not cfg.get("pick_on_click", false):
		_relic_page = RelicCompendiumOverlay.new()
		_relic_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(_relic_page)

	_populate_chars()
	_populate_words()
	_scroll.resized.connect(_layout_columns)
	_layout_columns.call_deferred()


func _add_tab(text: String, mode: String) -> void:
	var b := Ink.button(text)
	b.set_meta("tab", mode)
	b.custom_minimum_size = Vector2(110, 48 * JourneyStyle.touch_scale(self))
	b.pressed.connect(func(): _show_tab(mode))
	_tab_bar.add_child(b)


func _show_tab(mode: String) -> void:
	_mode = mode
	_scroll.visible = mode != "relics"
	if is_instance_valid(_relic_page):
		_relic_page.visible = mode == "relics"
	_grid.visible = mode == "chars"
	_word_grid.visible = mode == "words"
	_scroll.scroll_vertical = 0
	for effect in find_children("*", "RichTextLabel", true, false):
		if effect is EffectText: effect.close_help()
	for button in _tab_bar.get_children():
		button.theme_type_variation = "PrimaryButton" if button.get_meta("tab") == mode else "GhostButton"


func _populate_chars() -> void:
	if cfg.has("instances"):
		_populate_instances()
		return
	var list: Array = cfg.get("characters", [])
	if list.is_empty() and not cfg.has("characters"):
		# 默认展示全部字库（排除污染物）
		for c in Database.characters.values():
			if not c.is_pollution and not c.pending_design and not c.tags.has("enemy"):
				list.append(c)
		list.sort_custom(func(a, b): return a.rarity < b.rarity)
	for ch in list:
		var card := CharCard.new()
		card.setup(ch)
		var cnt := int(_counts.get(ch.glyph, _counts.get(ch.id, 0)))
		if cnt > 0:
			# 若来自字袋，把份数显示在描述里
			var wrapped: CharacterData = ch.duplicate()
			wrapped.description = "×%d  " % cnt + ch.description
			card.setup(wrapped)
		card.clicked.connect(_on_card_clicked.bind(ch))
		_grid.add_child(card)


func _populate_instances() -> void:
	var allowed: Array = (cfg.get("characters", []) as Array).map(func(ch): return ch.id)
	var groups: Dictionary = {}
	for inst: CharInstance in cfg.instances:
		if inst == null or inst.data == null: continue
		if cfg.has("characters") and not allowed.has(inst.id()): continue
		var display := inst.display_data()
		var key := display.id + "|" + display.glyph + "|" + display.description
		if not groups.has(key):
			var source: CharacterData = inst.data
			for candidate: CharacterData in cfg.get("characters", []):
				if candidate.id == inst.id():
					source = candidate
					break
			groups[key] = {"display":display, "source":source, "count":0}
		groups[key].count += 1
	for group: Dictionary in groups.values():
		var display: CharacterData = group.display
		display.description = "×%d  " % group.count + display.description
		if not str(cfg.get("modification_preview", "")).is_empty():
			display.description += "\n修饰后：" + str(cfg.modification_preview)
		var card := CharCard.new()
		card.setup(display)
		card.clicked.connect(_on_card_clicked.bind(group.source))
		_grid.add_child(card)


func _on_dim_input(event: InputEvent) -> void:
	if _dim_tap.matches(event, get_child(0)):
		accept_event()
		_close()


func _on_card_clicked(ch: CharacterData) -> void:
	if _closing or _picked: return
	if cfg.get("pick_on_click", false): _picked = true
	picked.emit(ch)
	if cfg.get("pick_on_click", false):
		_close()


func _populate_words() -> void:
	var words: Array = cfg.get("words", [])
	if words.is_empty():
		words = Database.words.values()
	words.sort_custom(func(a, b): return a.id < b.id)
	for w in words:
		var holder := Ink.card()
		holder.custom_minimum_size = Vector2(268, 0)
		var inner := Ink.vbox(4)
		holder.add_child(inner)
		var top := Ink.hbox(8)
		inner.add_child(top)
		var t := Ink.label(w.glyph_string(), "Subheading", JourneyStyle.GOLD)
		top.add_child(t)
		top.add_child(Ink.expander())
		var meta := JourneyStyle.label(w.group, "Muted")
		inner.add_child(meta)
		var d := EffectText.new()
		d.add_theme_font_size_override("normal_font_size", int(17 * JourneyStyle.touch_scale(self)))
		d.set_effect_text(EffectGlossary.brief(w), 0, w)
		inner.add_child(d)
		_word_grid.add_child(holder)


func _close() -> void:
	if _closing: return
	_closing = true
	closed.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel_selection"):
		get_viewport().set_input_as_handled()
		_close()


func _layout_columns() -> void:
	if _scroll == null: return
	var width := maxf(1, _scroll.size.x - 16)
	var factor := JourneyStyle.touch_scale(self)
	_grid.columns = maxi(1, int((width + 12) / (220 * factor + 12)))
	_word_grid.columns = maxi(1, int((width + 10) / (280 * factor + 10)))
	for grid in [_grid, _word_grid]:
		for item in grid.get_children(): item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
