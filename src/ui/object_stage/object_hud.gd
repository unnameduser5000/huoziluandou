extends Control
## One inspection strip, rather than repeating a complete rules panel on every object.
var heading := ""
var instruction := ""
var status := ""
var action_text := ""
var secondary_text := ""
var on_action: Callable
var on_secondary: Callable
var tertiary_text := ""
var on_tertiary: Callable
var tertiary_button: Button
var on_deck: Callable


var detail_title: Label
var description: EffectText
var action_button: Button
var secondary_button: Button
var status_label: Label
var instruction_label: Label
var _body_scroll: ScrollContainer
var _column: VBoxContainer
var _pad: MarginContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var factor := JourneyStyle.touch_scale(self)
	var pad := Ink.margin(24)
	_pad = pad
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(pad)
	var main := Ink.vbox(10)
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(main)
	var header := Ink.hbox(20)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(header)
	var titles := Ink.vbox(2)
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	var title := JourneyStyle.label(heading, "Heading", JourneyStyle.GOLD)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_child(title)
	var hint := JourneyStyle.label(instruction, "Muted")
	instruction_label = hint
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_child(hint)
	hint.visible = factor <= 1.1
	status_label = JourneyStyle.label(status, "Stat", JourneyStyle.TEXT)
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(status_label)
	if on_deck.is_valid(): header.add_child(JourneyStyle.button("字袋", on_deck))
	var empty := Ink.expander()
	empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(empty)
	var footer := Ink.hbox(32)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(footer)
	_column = Ink.vbox(5)
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(_column)
	detail_title = JourneyStyle.label("", "Subheading", JourneyStyle.GOLD)
	detail_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(detail_title)
	_body_scroll = ScrollContainer.new()
	_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body_scroll.custom_minimum_size.y = 78 * factor
	_column.add_child(_body_scroll)
	description = EffectText.new()
	description.add_theme_font_size_override("normal_font_size", int(17 * factor))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_scroll.add_child(description)
	var actions := Ink.vbox(8)
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.custom_minimum_size.x = 228 * factor
	footer.add_child(actions)
	action_button = JourneyStyle.button(action_text, on_action, true)
	action_button.custom_minimum_size.y = 48 * factor
	actions.add_child(action_button)
	secondary_button = JourneyStyle.button(secondary_text, on_secondary)
	secondary_button.custom_minimum_size.y = 48 * factor
	if tertiary_text.is_empty():
		actions.add_child(secondary_button)
	else:
		var row := Ink.hbox(8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		actions.add_child(row)
		tertiary_button = JourneyStyle.button(tertiary_text, on_tertiary)
		for button in [tertiary_button, secondary_button]:
			button.custom_minimum_size.y = 48 * factor
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(button)
	resized.connect(_layout)
	_layout.call_deferred()


func set_detail(title: String, body: String) -> void:
	detail_title.text = title
	description.set_effect_text(body)
	_body_scroll.scroll_vertical = 0


func _layout() -> void:
	if _body_scroll == null: return
	var unit := JourneyStyle.touch_scale(self)
	ScreenLayout.margins(_pad,self,(12 if unit>1.1 else 24)*unit)
	_body_scroll.custom_minimum_size.y = minf(78 * JourneyStyle.touch_scale(self), size.y * 0.16)
