extends Control
class_name GlyphGraphView
## 节点始终保存在世界坐标中；适配窗口只改变相机，不反复缩放布局。

signal node_selected(info: Dictionary)
signal view_changed

const ITERATIONS := 220
const NODE_GAP := 28.0
const MIN_ZOOM := 0.22
const MAX_ZOOM := 2.6
const BRONZE := Color("a58a54")
const PARCHMENT := Color("f1dfb8")
const INK := Color("102b2b")

var nodes: Array = []
var edges: Array = []
var _index: Dictionary = {}
var selected := ""
var _hover := ""
var zoom := 1.0
var camera_center := Vector2.ZERO
var focus_only := false
var _auto_fit := true
var _drag_node := ""
var _drag_offset := Vector2.ZERO
var _panning := false
var _press_pos := Vector2.ZERO
var _dragged := false
var _focus: Dictionary = {}
var _mouse_button := 0
var _mouse_last := Vector2.ZERO
var _touches: Dictionary = {}
var _touch_origin := Vector2.ZERO
var _touch_candidate := ""
var _touch_tap := false
var _touch_dragged := false
var _last_touch_time := -1000
var readable_start := false
var _overview_requested := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	set_process_input(false)
	resized.connect(_on_resized)
	mouse_exited.connect(func(): _hover = ""; queue_redraw())


func rebuild(words: Array, only_glyphs: Array = []) -> void:
	_cancel_gestures()
	_overview_requested = false
	var out_adj: Dictionary = {}
	var in_adj: Dictionary = {}
	var edge_map: Dictionary = {}
	var word_count: Dictionary = {}
	for w in words:
		# 子图只收入完整可组成的词，避免初始字袋混入袋外词的半条边。
		if not only_glyphs.is_empty() and not w.glyphs.all(func(g): return only_glyphs.has(g)):
			continue
		var counted: Dictionary = {}
		for g in w.glyphs:
			if not counted.has(g):
				word_count[g] = int(word_count.get(g, 0)) + 1
				counted[g] = true
		for i in range(w.glyphs.size() - 1):
			var a := str(w.glyphs[i])
			var b := str(w.glyphs[i + 1])
			if not out_adj.has(a):
				out_adj[a] = {}
			if not in_adj.has(b):
				in_adj[b] = {}
			out_adj[a][b] = int(out_adj[a].get(b, 0)) + 1
			in_adj[b][a] = int(in_adj[b].get(a, 0)) + 1
			var key := a + "|" + b
			edge_map[key] = int(edge_map.get(key, 0)) + 1
	# Starter letters without a complete word still have a single-letter effect.
	for glyph in only_glyphs:
		if not word_count.has(glyph): word_count[glyph] = 0
	nodes.clear()
	edges.clear()
	_index.clear()
	selected = ""
	_hover = ""
	_drag_node = ""
	_panning = false
	_focus.clear()
	var glyphs: Array = word_count.keys()
	glyphs.sort()
	for i in glyphs.size():
		var g: String = glyphs[i]
		var outs: Dictionary = out_adj.get(g, {})
		var ins: Dictionary = in_adj.get(g, {})
		var total: int = outs.size() + ins.size()
		var angle := float(i) * 2.39996323
		var distance := sqrt(float(i) + 0.5) * 84.0
		var nd := {"glyph": g, "layout_index": i, "out": outs.size(), "in": ins.size(),
			"wout": _sum(outs), "win": _sum(ins), "words": int(word_count[g]),
			"color": _node_color(Database.get_character_by_glyph(g)),
			"pos": Vector2(cos(angle) * 1.24, sin(angle) * 0.8) * distance,
			"radius": clampf(29.0 + sqrt(float(total)) * 1.8, 29.0, 39.0)}
		nodes.append(nd)
		_index[g] = nd
	var keys: Array = edge_map.keys()
	keys.sort()
	for key in keys:
		var parts := str(key).split("|")
		edges.append({"a": parts[0], "b": parts[1], "w": int(edge_map[key]),
			"reverse": edge_map.has(parts[1] + "|" + parts[0])})
	_compute_layout()
	_fit_to_canvas()
	queue_redraw()


func _sum(d: Dictionary) -> int:
	var value := 0
	for n in d.values():
		value += int(n)
	return value


func _node_color(cd: CharacterData) -> Color:
	if cd != null:
		for tag in ["heat", "energy", "economy", "defense", "flow", "space", "attack"]:
			if cd.tags.has(tag):
				return {"heat": Color("d58852"), "energy": Color("d9bc6b"),
					"economy": Color("82aa82"), "defense": Color("82acb8"),
					"flow": Color("83aaa2"), "space": Color("b296b0"),
					"attack": Color("da8a75")}[tag]
	return Color("bab09a")


func _compute_layout() -> void:
	# 固定初值与排序，不消耗战斗 / 整局随机数，也不依赖容器的中间尺寸。
	for iteration in ITERATIONS:
		var forces: Array[Vector2] = []
		forces.resize(nodes.size())
		forces.fill(Vector2.ZERO)
		for i in nodes.size():
			for j in range(i + 1, nodes.size()):
				var delta: Vector2 = nodes[i].pos - nodes[j].pos
				var length := maxf(1.0, delta.length())
				var push := delta / length * (19000.0 / (length * length))
				forces[i] += push
				forces[j] -= push
		for e in edges:
			if e.a == e.b:
				continue
			var a: Dictionary = _index[e.a]
			var b: Dictionary = _index[e.b]
			var delta: Vector2 = b.pos - a.pos
			var length := maxf(1.0, delta.length())
			var pull := delta / length * (length - 132.0) * 0.075
			forces[int(a.layout_index)] += pull
			forces[int(b.layout_index)] -= pull
		var step := lerpf(7.0, 0.25, float(iteration) / ITERATIONS)
		for i in nodes.size():
			var pos: Vector2 = nodes[i].pos
			forces[i] -= Vector2(pos.x * 0.002, pos.y * 0.012)
			nodes[i].pos += forces[i].limit_length(step)
		_separate_nodes(1)
	_separate_nodes(160)


func _separate_nodes(iterations: int, fixed := "") -> void:
	for iteration in iterations:
		var moved := false
		for i in nodes.size():
			for j in range(i + 1, nodes.size()):
				var a: Dictionary = nodes[i]
				var b: Dictionary = nodes[j]
				var delta: Vector2 = b.pos - a.pos
				var distance := delta.length()
				var minimum: float = a.radius + b.radius + NODE_GAP
				if distance >= minimum - 0.01:
					continue
				var direction := delta / distance if distance > 0.001 else Vector2.RIGHT.rotated(float(i + j))
				var push := direction * (minimum - distance + 0.02)
				if a.glyph == fixed:
					b.pos += push
				elif b.glyph == fixed:
					a.pos -= push
				else:
					a.pos -= push * 0.5
					b.pos += push * 0.5
				moved = true
		if not moved:
			break


func layout_bounds(visible_only := false) -> Rect2:
	var bounds := Rect2()
	var first := true
	for nd in nodes:
		if visible_only and not _visible_node(nd.glyph):
			continue
		var radius: float = nd.radius + 12.0
		var rect := Rect2(nd.pos - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
		bounds = rect if first else bounds.merge(rect)
		first = false
	return bounds


func _fit_to_canvas() -> void:
	_auto_fit = true
	var bounds := layout_bounds(focus_only)
	if nodes.is_empty() or size.x < 100.0 or size.y < 100.0:
		return
	var available := (size - Vector2(70, 70)).max(Vector2(1, 1))
	zoom = clampf(minf(available.x / maxf(1.0, bounds.size.x), available.y / maxf(1.0, bounds.size.y)), MIN_ZOOM, 1.45)
	camera_center = bounds.get_center()
	# A phone opens at readable, touchable letter sizes; Overview explicitly fits
	# the entire network. Both modes use the same world coordinates and rendering.
	var readable_zoom := minf(MAX_ZOOM,0.75*JourneyStyle.touch_scale(self))
	if readable_start and not _overview_requested and zoom<readable_zoom:
		zoom = readable_zoom
		var center := Vector2.ZERO
		var total := 0.0
		for nd in nodes:
			if not _visible_node(nd.glyph): continue
			var weight := maxf(1,float(nd.words))
			center += (nd.pos as Vector2)*weight
			total += weight
		if total>0: camera_center = center/total
	view_changed.emit()
	queue_redraw()


func _on_resized() -> void:
	_cancel_gestures()
	if _auto_fit:
		_fit_to_canvas()
	queue_redraw()


func world_to_view(p: Vector2) -> Vector2:
	return (p - camera_center) * zoom + size * 0.5


func view_to_world(p: Vector2) -> Vector2:
	return (p - size * 0.5) / zoom + camera_center


func zoom_at(factor: float, anchor: Vector2) -> void:
	var before := view_to_world(anchor)
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	camera_center += before - view_to_world(anchor)
	_auto_fit = false
	view_changed.emit()
	queue_redraw()


func set_focus_only(enabled: bool) -> void:
	focus_only = enabled
	_fit_to_canvas()


func clear_selection() -> void:
	selected = ""
	_focus.clear()
	if focus_only:
		_fit_to_canvas()
	node_selected.emit({})
	queue_redraw()


func show_overview() -> void:
	_overview_requested = true
	clear_selection()
	_fit_to_canvas()


func _visible_node(glyph: String) -> bool:
	return not focus_only or selected.is_empty() or _focus.has(glyph)


func _draw() -> void:
	if size.x < 10.0:
		return
	# 暗青铜板上的定位点，保持足够低的对比，不盖过字与关系。
	for x in range(24, int(size.x), 48):
		for y in range(24, int(size.y), 48):
			draw_circle(Vector2(x, y), 0.8, Color(0.64, 0.57, 0.38, 0.12))
	for e in edges:
		if _visible_node(e.a) and _visible_node(e.b):
			_draw_edge(e, false)
	# 选中字的连接线最后画，避免被全图的交叉线遮住。
	if not selected.is_empty():
		for e in edges:
			if e.a == selected or e.b == selected:
				_draw_edge(e, true)
	for nd in nodes:
		if _visible_node(nd.glyph) and nd.glyph != selected:
			_draw_node(nd)
	if _index.has(selected):
		_draw_node(_index[selected])
	if nodes.is_empty():
		var message := "未找到可显示的词语"
		var width := Ink.serif.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(Ink.serif, size * 0.5 + Vector2(-width * 0.5, 0), message, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, PARCHMENT)
	# 机关板压角，使用实时线条，避免把字或交互烘焙进图片。
	for corner in [Vector2(12, 12), Vector2(size.x - 12, 12), size - Vector2(12, 12), Vector2(12, size.y - 12)]:
		var inward := Vector2(1 if corner.x < size.x * 0.5 else -1, 1 if corner.y < size.y * 0.5 else -1)
		draw_line(corner, corner + Vector2(inward.x * 22, 0), BRONZE, 2.0, true)
		draw_line(corner, corner + Vector2(0, inward.y * 22), BRONZE, 2.0, true)


func _draw_edge(e: Dictionary, highlight: bool) -> void:
	var a: Dictionary = _index[e.a]
	var b: Dictionary = _index[e.b]
	var pa := world_to_view(a.pos)
	var pb := world_to_view(b.pos)
	var tint: Color = a.color if highlight else BRONZE
	tint.a = 0.85 if highlight else (0.18 if selected.is_empty() else 0.065)
	if e.a == e.b:
		var r: float = a.radius * zoom
		var center := pa + Vector2(r * 0.68, -r * 0.75)
		draw_arc(center, r * 0.7, -2.7, 2.4, 24, tint, 1.8 if highlight else 1.0, true)
		return
	var direction := (pb - pa).normalized()
	var normal := Vector2(-direction.y, direction.x)
	var start: Vector2 = pa + direction * (a.radius * zoom + 3.0)
	var end: Vector2 = pb - direction * (b.radius * zoom + 5.0)
	var control := (start + end) * 0.5 + normal * (19.0 * zoom if e.reverse else 7.0 * zoom)
	var points := PackedVector2Array()
	for i in 17:
		var t := float(i) / 16.0
		points.append(start.lerp(control, t).lerp(control.lerp(end, t), t))
	draw_polyline(points, tint, 1.9 if highlight else 1.0, true)
	var tangent := (end - control).normalized()
	var perpendicular := Vector2(-tangent.y, tangent.x)
	var arrow := 6.0 if highlight else 4.0
	draw_colored_polygon(PackedVector2Array([end, end - tangent * arrow + perpendicular * arrow * 0.5,
		end - tangent * arrow - perpendicular * arrow * 0.5]), tint)


func _draw_node(nd: Dictionary) -> void:
	var p := world_to_view(nd.pos)
	var radius: float = nd.radius * zoom
	var active: bool = nd.glyph == selected
	var hovered: bool = nd.glyph == _hover
	var alpha := 1.0 if selected.is_empty() or _focus.has(nd.glyph) else 0.35
	var tint := Color(nd.color, alpha)
	var polygon := _octagon(p, radius)
	draw_colored_polygon(_octagon(p + Vector2(2, 4), radius), Color(0.01, 0.04, 0.04, 0.7 * alpha))
	draw_colored_polygon(polygon, Color("244747") if active else Color("132e30"))
	draw_polyline(polygon, tint, 2.2 if active or hovered else 1.1, true)
	if active or hovered:
		draw_arc(p, radius + 5, 0, TAU, 48, Color(nd.color, 0.75), 1.1, true)
	var font_size := clampi(int(30.0 * zoom), 16, 42)
	var width := Ink.serif.get_string_size(nd.glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := (Ink.serif.get_ascent(font_size) - Ink.serif.get_descent(font_size)) * 0.5
	draw_string(Ink.serif, p + Vector2(-width * 0.5, baseline), nd.glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		Color(PARCHMENT, alpha) if not active else Color("ffe9b1"))


func _octagon(p: Vector2, radius: float) -> PackedVector2Array:
	var cut := radius * 0.28
	return PackedVector2Array([p + Vector2(-radius + cut, -radius), p + Vector2(radius - cut, -radius),
		p + Vector2(radius, -radius + cut), p + Vector2(radius, radius - cut), p + Vector2(radius - cut, radius),
		p + Vector2(-radius + cut, radius), p + Vector2(-radius, radius - cut), p + Vector2(-radius, -radius + cut),
		p + Vector2(-radius + cut, -radius)])


func _gui_input(event: InputEvent) -> void:
	var point: Vector2 = event.position if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag else get_local_mouse_position()
	if EffectText.blocks_pointer(get_viewport(), get_global_transform() * point):
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_touch_input(event)
		accept_event()
		return
	if event is InputEventMouse:
		# Android may emit a mouse event for the same finger; select only once.
		if event.device==InputEvent.DEVICE_ID_EMULATION and Time.get_ticks_msec()-_last_touch_time<800:
			accept_event()
			return
		_mouse_input(event)
	elif event is InputEventMagnifyGesture:
		zoom_at(event.factor, event.position)
		accept_event()
	elif event is InputEventPanGesture:
		_pan_by(-event.delta * 24.0)
		accept_event()


func _mouse_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_at(1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15, event.position)
			accept_event()
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			if event.pressed:
				_mouse_button = event.button_index
				_mouse_last = event.position
				set_process_input(true)
				_press_pos = event.position
				_dragged = false
				_drag_node = _node_at(event.position) if event.button_index == MOUSE_BUTTON_LEFT else ""
				_panning = _drag_node.is_empty()
				if not _drag_node.is_empty():
					_drag_offset = _index[_drag_node].pos - view_to_world(event.position)
			elif _mouse_button==event.button_index:
				if not _drag_node.is_empty():
					var glyph := _drag_node
					if _dragged:
						_separate_nodes(160, glyph)
					if Rect2(Vector2.ZERO,size).has_point(event.position): select(glyph)
				elif _panning and not _dragged and event.button_index == MOUSE_BUTTON_LEFT and Rect2(Vector2.ZERO,size).has_point(event.position):
					clear_selection()
				_drag_node = ""
				_panning = false
				_mouse_button = 0
				set_process_input(not _touches.is_empty())
				mouse_default_cursor_shape = CURSOR_ARROW
				queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion:
		var movement: Vector2 = event.position-_mouse_last
		_mouse_last = event.position
		if _panning or not _drag_node.is_empty():
			_dragged = _dragged or event.position.distance_to(_press_pos) > 4.0
			if _dragged:
				_auto_fit = false
				if _panning:
					_pan_by(movement)
					mouse_default_cursor_shape = CURSOR_DRAG
				else:
					_index[_drag_node].pos = view_to_world(event.position) + _drag_offset
					mouse_default_cursor_shape = CURSOR_MOVE
		else:
			_hover = _node_at(event.position)
			mouse_default_cursor_shape = CURSOR_POINTING_HAND if not _hover.is_empty() else CURSOR_ARROW
		queue_redraw()


func _input(event: InputEvent) -> void:
	# GUI dispatch stops at the view boundary; captured releases must not get lost.
	if not is_visible_in_tree():
		_cancel_gestures()
		return
	var relevant := (_mouse_button!=0 and (event is InputEventMouseMotion or event is InputEventMouseButton)) or (not _touches.is_empty() and (event is InputEventScreenTouch or event is InputEventScreenDrag))
	if not relevant: return
	var local := event.xformed_by(get_global_transform_with_canvas().affine_inverse())
	if local is InputEventScreenTouch or local is InputEventScreenDrag:
		if local is InputEventScreenTouch and local.pressed and not Rect2(Vector2.ZERO,size).has_point(local.position): return
		_touch_input(local)
	else:
		_mouse_input(local)
	get_viewport().set_input_as_handled()


func _touch_input(event: InputEvent) -> void:
	_last_touch_time = Time.get_ticks_msec()
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			set_process_input(true)
			if _touches.size()==1:
				_touch_origin = event.position
				_touch_candidate = _node_at(event.position)
				_touch_tap = true
				_touch_dragged = false
			else: _touch_tap = false
		elif _touches.has(event.index):
			var glyph := _touch_candidate
			var tap: bool = _touches.size()==1 and _touch_tap and not event.canceled and Rect2(Vector2.ZERO,size).has_point(event.position) and event.position.distance_to(_touch_origin)<=8*JourneyStyle.touch_scale(self)
			_touches.erase(event.index)
			_touch_tap = false
			if _touches.is_empty(): set_process_input(_mouse_button!=0)
			else: _touch_dragged = true
			if tap and glyph==_node_at(event.position):
				if glyph.is_empty(): clear_selection()
				else: select(glyph)
	elif event is InputEventScreenDrag and _touches.has(event.index):
		var previous: Vector2 = _touches[event.index]
		var old_center := _touch_center()
		var old_distance := _touch_distance()
		_touches[event.index] = event.position
		if _touches.size()>1:
			_touch_tap = false
			_touch_dragged = true
			if old_distance>1: zoom_at(_touch_distance()/old_distance,old_center)
			_pan_by(_touch_center()-old_center)
		elif _touch_dragged or event.position.distance_to(_touch_origin)>8*JourneyStyle.touch_scale(self):
			_touch_tap = false
			_pan_by(event.position-(previous if _touch_dragged else _touch_origin))
			_touch_dragged = true


func _touch_center() -> Vector2:
	var center := Vector2.ZERO
	for point: Vector2 in _touches.values(): center += point
	return center/maxi(1,_touches.size())


func _touch_distance() -> float:
	var points := _touches.values()
	return (points[0] as Vector2).distance_to(points[1]) if points.size()>1 else 0.0


func _pan_by(movement: Vector2) -> void:
	camera_center -= movement/zoom
	_auto_fit = false
	# Retain a visible strip of the graph when dragged far beyond its bounds.
	var bounds := layout_bounds(focus_only)
	var reach := (size*0.5-Vector2.ONE*24).max(Vector2.ZERO)/zoom
	camera_center = camera_center.clamp(bounds.position-reach,bounds.end+reach)
	queue_redraw()


func _cancel_gestures() -> void:
	_mouse_button = 0
	_drag_node = ""
	_panning = false
	_touches.clear()
	_touch_tap = false
	set_process_input(false)
	mouse_default_cursor_shape = CURSOR_ARROW


func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT or (what==NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
		_cancel_gestures()


func _node_at(p: Vector2) -> String:
	var world := view_to_world(p)
	# 节点为切角方块，命中形状与画面一致。
	for nd in nodes:
		if _visible_node(nd.glyph) and Geometry2D.is_point_in_polygon(world, _octagon(nd.pos, nd.radius + 3.0)):
			return nd.glyph
	return ""


func info_for(glyph: String) -> Dictionary:
	if not _index.has(glyph):
		return {}
	var nd: Dictionary = _index[glyph]
	var outs: Array = []
	var ins: Array = []
	for e in edges:
		if e.a == glyph:
			outs.append(e.b)
		if e.b == glyph:
			ins.append(e.a)
	outs.sort()
	ins.sort()
	return {"glyph": glyph, "out": nd.out, "in": nd["in"], "wout": nd.wout, "win": nd.win,
		"words": nd.words, "color": nd.color, "out_list": outs, "in_list": ins}


func select(glyph: String, center := false) -> void:
	if not _index.has(glyph):
		return
	selected = glyph
	_focus = {glyph: true}
	for e in edges:
		if e.a == glyph:
			_focus[e.b] = true
		if e.b == glyph:
			_focus[e.a] = true
	if focus_only:
		_fit_to_canvas()
	elif center:
		camera_center = _index[glyph].pos
		_auto_fit = false
	node_selected.emit(info_for(glyph))
	queue_redraw()
