extends "res://src/ui/modal_overlay.gd"
## Compact graph details reuse the same read-only content as the desktop sidebar.
var detail: Control
var restore_parent: Control
var _panel: PanelContainer
var _close_button: Button
var _closing := false
var _tap := TouchTap.new()
var _previous_focus: Control


func _ready() -> void:
	_previous_focus = get_viewport().gui_get_focus_owner()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.02,0.04,0.05,0.8)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(func(event):
		if _tap.matches(event,shade): _close())
	add_child(shade)
	_panel = Ink.panel("PanelCard")
	var style := StyleBoxFlat.new()
	style.bg_color = Color("102e30")
	style.border_color = Color("c2a366")
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel",style)
	add_child(_panel)
	var column := Ink.vbox(10)
	_panel.add_child(column)
	var header := Ink.hbox(10)
	column.add_child(header)
	header.add_child(Ink.h2("字录"))
	header.add_child(Ink.expander())
	_close_button = Ink.button("关闭")
	_close_button.focus_mode = Control.FOCUS_ALL
	_close_button.pressed.connect(_close)
	header.add_child(_close_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	detail.reparent(scroll)
	resized.connect(_layout.call_deferred)
	get_window().size_changed.connect(_layout.call_deferred)
	_layout()
	_close_button.grab_focus()


func _layout() -> void:
	if _panel==null: return
	var unit := JourneyStyle.touch_scale(self)
	var safe := ScreenLayout.safe_rect(self)
	_panel.size = Vector2(minf(620 * unit,safe.size.x-24 * unit),safe.size.y-24 * unit)
	_panel.position = safe.position+(safe.size-_panel.size)*0.5
	_close_button.custom_minimum_size = Vector2(80,48) * unit
	_close_button.add_theme_font_size_override("font_size",roundi(18 * unit))


func _close() -> void:
	if _closing: return
	_closing = true
	if is_instance_valid(detail) and is_instance_valid(restore_parent) and not restore_parent.is_queued_for_deletion():
		detail.reparent(restore_parent)
	if is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus.call_deferred()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("cancel_selection"):
		_close()
		get_viewport().set_input_as_handled()
