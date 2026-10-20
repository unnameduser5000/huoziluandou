extends "res://src/ui/modal_overlay.gd"
class_name PauseOverlay
## 唯一的游戏菜单：常用入口集中于此，设置关闭后回到菜单。
var _main_layer: Control
var _panel: PanelContainer
var _padding: MarginContainer
var _column: VBoxContainer
var _heading: Label
var _buttons: Array[Button] = []
var _settings: SettingsOverlay
var _ui_scale := 0.0


func _ready() -> void:
	JourneyStyle.apply(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main_layer = Control.new()
	_main_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_main_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.04, 0.06, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_main_layer.add_child(dim)
	_panel = Ink.panel("PanelCard")
	_main_layer.add_child(_panel)
	var sheet: StyleBox = _panel.get_theme_stylebox("panel").duplicate()
	sheet.set_content_margin_all(0)
	_panel.add_theme_stylebox_override("panel", sheet)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	_padding = Ink.margin(16)
	_padding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_padding)
	_column = Ink.vbox(6)
	_padding.add_child(_column)
	_heading = Ink.h2("菜单")
	_column.add_child(_heading)
	_column.add_child(Ink.hline())
	_column.add_child(_button("继续", _close, true))
	var host: Control = Router.current
	var tools := Ink.hbox(10)
	if host != null and host.has_method("_open_deck"):
		tools.add_child(_button("字袋", _open_tool.bind("_open_deck")))
	if host != null and host.has_method("_toggle_log"):
		tools.add_child(_button("战报", _open_tool.bind("_toggle_log")))
	if tools.get_child_count() > 0:
		_column.add_child(tools)
	else:
		tools.free()
	if host != null and host.has_method("_open_battle_guide"):
		_column.add_child(_button("战斗与遗物说明", _open_tool.bind("_open_battle_guide")))
	if host != null and host.has_method("can_skip_first_run_tutorial") and host.can_skip_first_run_tutorial():
		_column.add_child(_button("跳过新手引导", _skip_first_run_tutorial.bind(host)))
	_column.add_child(_button("设置", _open_settings))
	_column.add_child(_button("保存并返回主界面", func():
		SaveManager.checkpoint()
		SaveManager.flush()
		Router.goto("res://src/screens/title_screen.gd")))
	var quit := _button("退出游戏", func():
		SaveManager.checkpoint()
		SaveManager.flush()
		get_tree().quit())
	quit.theme_type_variation = "DangerButton"
	_column.add_child(quit)
	resized.connect(_layout)
	_column.minimum_size_changed.connect(_layout.call_deferred)
	_layout.call_deferred()


func _button(text: String, action: Callable, primary := false) -> Button:
	var button := Ink.button(text, primary)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	_buttons.append(button)
	return button


func _layout() -> void:
	if _panel == null or size.x < 1:
		return
	var factor := JourneyStyle.touch_scale(self)
	if not is_equal_approx(factor, _ui_scale):
		_ui_scale = factor
		for button in _buttons:
			button.custom_minimum_size.y = 48 * factor
			button.add_theme_font_size_override("font_size", int(20 * factor))
		_heading.add_theme_font_size_override("font_size", int(28 * factor))
		_column.add_theme_constant_override("separation", int(6 * factor))
		for edge in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
			_padding.add_theme_constant_override(edge, int(16 * factor))
	var width := minf(360 * factor, size.x - 32 * factor)
	var height := minf(_column.get_combined_minimum_size().y + 32 * factor, size.y - 24 * factor)
	_panel.size = Vector2(width, height)
	_panel.position = (size - _panel.size) * 0.5


func _open_tool(method: String) -> void:
	var host: Control = Router.current
	_close()
	if host != null and host.has_method(method):
		host.call(method)


func _skip_first_run_tutorial(host: Control) -> void:
	if is_instance_valid(host) and host.has_method("skip_first_run_tutorial"):
		host.call("skip_first_run_tutorial")
	_close()


func _open_settings() -> void:
	if is_instance_valid(_settings):
		return
	_main_layer.hide()
	_settings = SettingsOverlay.new()
	add_child(_settings)
	_settings.tree_exited.connect(func():
		_settings = null
		if is_inside_tree():
			_main_layer.show())


func _close() -> void:
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel_selection"):
		_close()
		get_viewport().set_input_as_handled()
