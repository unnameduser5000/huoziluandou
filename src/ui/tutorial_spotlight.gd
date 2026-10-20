extends Control
## Cutouts share the same geometry for drawing and input: only lit controls accept taps.
var holes: Array[Rect2] = []
var accents: Array[Rect2] = []
var gesture := PackedVector2Array()
var falls: Array = []
var _callout := Rect2()
var _target := Vector2.ZERO
var _unit := 1.0
var _elapsed := 0.0
var _fade: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func focus(regions: Array[Rect2], targets: Array[Rect2], path: PackedVector2Array, arrows: Array, transition := false) -> void:
	holes = regions
	accents = targets
	gesture = path
	falls = arrows
	if transition:
		_elapsed = 0.0
		if _fade != null: _fade.kill()
		modulate.a = 0.0 if not Settings.reduced_motion else 1.0
		if not Settings.reduced_motion:
			_fade = create_tween()
			_fade.tween_property(self, "modulate:a", 1.0, 0.22)
	queue_redraw()


func _has_point(point: Vector2) -> bool:
	for hole in holes:
		if hole.has_point(point): return false
	return true


func point_at(callout: Rect2, target: Vector2, unit: float) -> void:
	_callout = callout
	_target = target
	_unit = unit
	queue_redraw()


func _process(delta: float) -> void:
	if Settings.reduced_motion: return
	_elapsed += delta
	queue_redraw()


func _draw() -> void:
	# Subtract every cutout from the shade, so overlapping cutouts never double-dim.
	var shade: Array[Rect2] = [Rect2(Vector2.ZERO, size)]
	for hole in holes:
		var remaining: Array[Rect2] = []
		for rect in shade:
			var cut := rect.intersection(hole)
			if not cut.has_area(): remaining.append(rect); continue
			for piece in [Rect2(rect.position, Vector2(rect.size.x, cut.position.y-rect.position.y)),
				Rect2(Vector2(rect.position.x, cut.end.y), Vector2(rect.size.x, rect.end.y-cut.end.y)),
				Rect2(Vector2(rect.position.x, cut.position.y), Vector2(cut.position.x-rect.position.x, cut.size.y)),
				Rect2(Vector2(cut.end.x, cut.position.y), Vector2(rect.end.x-cut.end.x, cut.size.y))]:
				if piece.has_area(): remaining.append(piece)
		shade = remaining
	for rect in shade: draw_rect(rect, Color(0.015, 0.035, 0.045, 0.76))
	if _callout.has_area():
		var center_y := clampf(_target.y, _callout.position.y + 20 * _unit, _callout.end.y - 20 * _unit)
		var base := Vector2(_callout.end.x - 2 * _unit, center_y)
		var tip := base + Vector2(10 * _unit, 0)
		var upper := base - Vector2(0, 8 * _unit)
		var lower := base + Vector2(0, 8 * _unit)
		draw_colored_polygon(PackedVector2Array([upper, tip, lower]), JourneyStyle.SURFACE)
		draw_polyline(PackedVector2Array([upper, tip, lower]), JourneyStyle.GOLD, 1.5 * _unit, true)
	var pulse := 0.65 if Settings.reduced_motion else 0.65 + sin(_elapsed*3.0)*0.2
	for rect in accents:
		draw_style_box(_outline(Color(JourneyStyle.GOLD, pulse)), rect)
		draw_style_box(_outline(Color(JourneyStyle.GOLD, pulse*0.18), 5), rect.grow(4))
	for arrow in falls:
		var from: Vector2 = arrow[0]
		var to: Vector2 = arrow[1]
		draw_dashed_line(from, to, Color(JourneyStyle.GOLD, 0.55), 2, 7)
		var direction := from.direction_to(to)
		draw_line(to, to-direction.rotated(0.5)*13, JourneyStyle.GOLD, 2, true)
		draw_line(to, to-direction.rotated(-0.5)*13, JourneyStyle.GOLD, 2, true)
		if not Settings.reduced_motion:
			var dot := from.lerp(to, fmod(_elapsed*0.55, 1.0))
			draw_circle(dot, 4, JourneyStyle.GOLD, true, -1, true)
	if gesture.is_empty(): return
	var cursor := gesture[0]
	if gesture.size() > 1:
		var travel := 0.5 if Settings.reduced_motion else clampf(fmod(_elapsed, 2.8)/1.6, 0, 1)
		var segment := travel * (gesture.size()-1)
		var index := mini(int(segment), gesture.size()-2)
		cursor = gesture[index].lerp(gesture[index+1], segment-index)
		for i in gesture.size()-1:
			draw_dashed_line(gesture[i], gesture[i+1], Color(JourneyStyle.GOLD, 0.45), 2, 6)
	var ring := 12.0 if Settings.reduced_motion else 11.0 + fmod(_elapsed, 1.0)*10
	draw_circle(cursor, ring, Color(JourneyStyle.GOLD, pulse), false, 2, true)
	draw_circle(cursor, 5, JourneyStyle.TEXT, true, -1, true)
	# A small finger follows the example path without injecting gameplay input.
	var finger := PackedVector2Array([cursor+Vector2(3,7), cursor+Vector2(7,25), cursor+Vector2(16,32), cursor+Vector2(24,27), cursor+Vector2(19,16), cursor+Vector2(11,14)])
	draw_colored_polygon(finger, Color(JourneyStyle.TEXT, 0.9))


func _outline(color: Color, width := 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = color
	style.set_border_width_all(width)
	style.set_corner_radius_all(8)
	return style
