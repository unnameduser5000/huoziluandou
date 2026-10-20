extends VBoxContainer
class_name RelicCompendiumOverlay
## 字库图鉴的遗物子页面；只读取遗物数据，不修改对局。

const TIER_NAMES := {1: "常见", 2: "少见", 3: "稀有"}
var _grid: GridContainer
var _scroll: ScrollContainer


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	var normal_count := Relics.normal_pool().size()
	var summary := Ink.label("共 %d 件 · 普通遗物 %d 件 · 事件专属 %d 件" % [Relics.visible_ids().size(), normal_count, Relics.event_pool().size()], "Muted")
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(summary)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.columns = 1
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_scroll.add_child(_grid)
	var ids := Relics.visible_ids()
	ids.sort_custom(func(a, b):
		var ta := int(Relics.TIER.get(a, 2))
		var tb := int(Relics.TIER.get(b, 2))
		return ta < tb or (ta == tb and str(a) < str(b)))
	for id in ids:
		_grid.add_child(_card(str(id)))
	_scroll.resized.connect(_layout_columns)
	visibility_changed.connect(_on_visibility_changed)
	_layout_columns.call_deferred()


func _card(id: String) -> Control:
	var holder := Ink.card()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.set_meta("relic_id", id)
	# 卡面不拦截拖动，滚动交给外层 ScrollContainer（预览按钮仍可点开详情）
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	var inner := Ink.vbox(6)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_child(inner)
	var model := Button.new()
	model.custom_minimum_size.y = 100 * JourneyStyle.touch_scale(self)
	model.tooltip_text = Relics.text(id)
	model.pressed.connect(ChoiceOverlay.show_relic_details.bind(self,id))
	inner.add_child(model)
	var preview := preload("res://src/ui/relic_preview.gd").new()
	preview.relic_id = id
	model.add_child(preview)
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var title := Ink.label(Relics.name_of(id), "Subheading", JourneyStyle.GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(title)
	var tier := Ink.label(_tier_text(id), "Muted")
	tier.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(tier)
	var description := EffectText.new()
	description.add_theme_font_size_override("normal_font_size", int(17 * JourneyStyle.touch_scale(self)))
	description.set_effect_text(Relics.desc_of(id))
	inner.add_child(description)
	var tags: Array[String] = []
	if Relics.is_event_relic(id): tags.append("事件专属")
	if Relics.needs_bind(id): tags.append("需绑定一枚字")
	if GameState.has_relic(id): tags.append("持有中")
	for text in tags:
		var tag := Ink.label(text, "Muted")
		tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		inner.add_child(tag)
	return holder


func _tier_text(id: String) -> String:
	var tier := int(Relics.TIER.get(id, 2))
	return "◆".repeat(tier) + " " + str(TIER_NAMES.get(tier, "少见"))


func _layout_columns() -> void:
	if _scroll == null or not is_visible_in_tree(): return
	# 留出滚动条宽度；按实际可用宽度分配每张卡片，避免最小宽度撑出视口。
	var width := maxf(1, _scroll.size.x - _scroll.get_v_scroll_bar().size.x - 4)
	var columns := maxi(1, int((width + 12) / (280 * JourneyStyle.touch_scale(self) + 12)))
	_grid.columns = columns
	var card_width := maxf(1, (width - 12 * (columns - 1)) / columns)
	for item in _grid.get_children():
		item.custom_minimum_size.x = card_width


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_layout_columns.call_deferred()
	else:
		for effect in find_children("*", "RichTextLabel", true, false):
			if effect is EffectText: effect.close_help()
