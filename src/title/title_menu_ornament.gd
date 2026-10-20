extends Control
## Real buttons keep their focus/input semantics; this layer paints their frame.
var buttons: Array[Button] = []
var highlighted: Button


func setup(items: Array[Button]) -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	buttons = items
	for button in buttons:
		button.mouse_entered.connect(func(): highlighted = button; queue_redraw())
		button.focus_entered.connect(func(): highlighted = button; queue_redraw())
		button.mouse_exited.connect(func(): highlighted = null; queue_redraw())
	queue_redraw()


func _diamond(at: Vector2, radius: float, color: Color, fill := false, width := 1.2) -> void:
	var shape := PackedVector2Array([at+Vector2(0,-radius),at+Vector2(radius,0),at+Vector2(0,radius),at+Vector2(-radius,0),at+Vector2(0,-radius)])
	if fill: draw_colored_polygon(shape,color)
	else: draw_polyline(shape,color,width,true)


func _draw() -> void:
	if buttons.is_empty() or not is_instance_valid(buttons[0]): return
	var unit := JourneyStyle.touch_scale(self)
	var gold := Color("b18a50"); var pale := Color("ead2a0")
	var columns := {}
	for button in buttons:
		if not button.is_visible_in_tree(): continue
		if button.size.x <= 20 * unit or button.size.y <= 8 * unit: continue
		var box := Rect2(button.get_global_rect().position-global_position,button.size)
		var key := roundi(box.position.x)
		if not columns.has(key): columns[key] = Vector2(box.position.y,box.end.y)
		else: columns[key].y = box.end.y
	for key: int in columns:
		var x := float(key); var ends: Vector2 = columns[key]
		draw_line(Vector2(x,ends.x),Vector2(x,ends.y),Color(gold,0.42),unit,true)
	for button in buttons:
		if not button.is_visible_in_tree(): continue
		if button.size.x <= 20 * unit or button.size.y <= 8 * unit: continue
		var box := Rect2(button.get_global_rect().position-global_position,button.size)
		var x := box.position.x
		var active: bool = button==highlighted or button.has_focus() or highlighted==null and button==buttons[0]
		var at := Vector2(x,box.get_center().y)
		_diamond(at,4*unit,Color(gold,0.7),false,unit)
		if not active: continue
		var inset := 4*unit
		var tip := 10*unit
		var frame := PackedVector2Array([Vector2(x+tip,box.position.y+inset),Vector2(box.end.x-tip,box.position.y+inset),Vector2(box.end.x,box.get_center().y),Vector2(box.end.x-tip,box.end.y-inset),Vector2(x+tip,box.end.y-inset),Vector2(x,box.get_center().y),Vector2(x+tip,box.position.y+inset)])
		draw_colored_polygon(frame,Color(.21,.065,.05,.82))
		draw_polyline(frame,Color("c69156"),unit,true)
		_diamond(at,6*unit,Color("bc4c35"),false,unit)
		_diamond(at,2.5*unit,pale,true)
