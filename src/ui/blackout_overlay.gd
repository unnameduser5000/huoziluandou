extends "res://src/ui/modal_overlay.gd"
class_name BlackoutOverlay
## 停电彩蛋：全屏变黑，只剩【开】【灯】两枚字块。
## 拖动（或依次点击）【开】→【灯】即可“来电”，`ESC` 也能摸黑开灯。

signal restored

var _tile_open: Control
var _tile_light: Control
var _armed := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.01, 0.015, 0.99)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var hint := Ink.label("停电了……", "Heading", Color(0.6, 0.6, 0.65))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(hint)
	center.add_child(Ink.label("拖动连出「开灯」", "Muted", Color(0.42, 0.42, 0.48)))

	var row := Ink.hbox(60)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(row)
	_tile_open = _make_tile("开")
	_tile_light = _make_tile("灯")
	row.add_child(_tile_open)
	row.add_child(_tile_light)

	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.35)


func _make_tile(glyph: String) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(128, 128)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := Ink.make_wood_material()
	mat.set_shader_parameter("tile_size", Vector2(128, 128))
	mat.set_shader_parameter("corner_radius", 14.0)
	rect.material = mat
	holder.add_child(rect)
	var lab := Ink.label(glyph, "", Palette.INK)
	lab.set_anchors_preset(Control.PRESET_FULL_RECT)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 72)
	holder.add_child(lab)
	return holder


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _over(_tile_open, event.position):
			_arm()
		elif _armed and _over(_tile_light, event.position):
			_restore()
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if _over(_tile_open, event.position):
			_arm()
		elif _armed and _over(_tile_light, event.position):
			_restore()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel_selection"):
		_restore()
		get_viewport().set_input_as_handled()


func _arm() -> void:
	if _armed:
		return
	_armed = true
	var tw := create_tween()
	tw.tween_property(_tile_open, "scale", Vector2(1.12, 1.12), 0.08)


func _over(ctrl: Control, pos: Vector2) -> bool:
	return ctrl != null and ctrl.get_global_rect().has_point(pos)


func _restore() -> void:
	restored.emit()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)
