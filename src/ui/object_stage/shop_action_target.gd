extends HintButton
## Transparent native input target; the model supplies the face, text and feedback.
var model: Node3D
var _caption: Label


func _ready() -> void:
	super._ready()
	flat = true
	clip_text = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	mouse_entered.connect(func(): model.highlight(not disabled))
	mouse_exited.connect(func(): model.highlight(false))
	focus_entered.connect(func(): model.highlight(not disabled))
	focus_exited.connect(func(): model.highlight(false))
	pressed.connect(func(): model.press())
	_caption = JourneyStyle.label("", "", JourneyStyle.TEXT)
	JourneyStyle.currency(_caption)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", int(14 * JourneyStyle.touch_scale(self)))
	_caption.add_theme_color_override("font_outline_color", Color("10262f"))
	_caption.add_theme_constant_override("outline_size", 4)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.offset_top = -32 * JourneyStyle.touch_scale(self)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)
	model.title_label.hide()
	model.price_label.hide()


func set_offer(caption: String, price: int, enabled: bool) -> void:
	text = caption + (" · %d铜钱" % price if price >= 0 else "")
	disabled = not enabled
	model.set_offer(caption, price, enabled)
	_caption.text = "%s\n%d钱" % [caption, price]
	_caption.modulate = Color.WHITE if enabled else Color("82938b")
