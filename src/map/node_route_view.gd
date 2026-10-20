extends Control
## Screen-space route scroll: every future stop and connection stays visible.
signal node_selected(id: String)
const GLYPHS := {"start":"入", "battle":"战", "elite":"精", "event":"？", "shop":"商", "treasure":"藏", "rest":"息", "boss":"狱"}
const LABELS := {"start":"起点", "battle":"战斗", "elite":"精英", "event":"奇遇", "shop":"字肆", "treasure":"宝藏", "rest":"休息", "boss":"首领"}
var run: RefCounted
var selected := ""
var points := {}
var _offset := 0.0
var _overview := true
var _unit := 1.0
var _node_scale := 1.0
var _pitch := 100.0
var _span := 0.0
var _down := Vector2.ZERO
var _pressed := false
var _dragged := false
var _pointer := -1
var _hover := ""
## 规划模式：从当前往右一格格点选，候选亮起、其余压暗，选中的格子描一圈红
var planning := false
var _circles := {} # id -> 红圈描画进度 0..1
const CIRCLE_TIME := .35


func _ready() -> void:
	set_process(planning)
	clip_contents = true
	custom_minimum_size.y = 220
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(_layout)
	mouse_exited.connect(func(): _hover = ""; queue_redraw())
	_layout()


func refresh() -> void:
	_sync_circles()
	_layout()


func set_planning(on: bool) -> void:
	planning = on
	_sync_circles()
	set_process(on)
	queue_redraw()


## 新预选的格子从 0 开始描红圈；已撤掉的去掉
func _sync_circles() -> void:
	if run == null: return
	for id: String in _circles.keys():
		if not run.planned_route.has(id): _circles.erase(id)
	for id: String in run.planned_route:
		if not _circles.has(id): _circles[id] = 0.0 if planning else 1.0


func circle_progress(id: String) -> float:
	return float(_circles.get(id, 0.0))


func _process(delta: float) -> void:
	for id: String in _circles: _circles[id] = minf(1.0, _circles[id] + delta / CIRCLE_TIME)
	queue_redraw() # 候选格的呼吸光也要一直刷新


func show_overview() -> void:
	_overview = true; _offset = 0
	_layout()


func focus_current() -> void:
	_overview = false
	_layout()
	if points.has(run.current_room):
		_offset += points[run.current_room].x - size.x * .24
		_clamp_offset(); _layout()


func _layout() -> void:
	if run == null or size.x < 10: return
	_unit = JourneyStyle.touch_scale(self)
	var last := 0
	for data: Dictionary in run.layout.rooms.values(): last = maxi(last, int(data.column) + 1)
	var margin := 54.0 * _unit
	_pitch = maxf(68 * _unit, (size.x - margin * 2) / maxf(1, last)) if _overview else 116 * _unit
	_span = last * _pitch + margin * 2
	_clamp_offset()
	points.clear()
	var compact := _unit>1.1
	var top := (24.0 if compact else 64.0)*_unit
	# Reserve a clear corner for the floating actions, without a separate footer.
	var bottom := (88.0 if compact else 104.0)*_unit
	var height := maxf(0, size.y - top - bottom)
	var lane_min := INF
	var lane_max := -INF
	for data: Dictionary in run.layout.rooms.values():
		lane_min = minf(lane_min, float(data.lane))
		lane_max = maxf(lane_max, float(data.lane))
	var lane_span := maxf(1, lane_max - lane_min)
	for id: String in run.graph.rooms:
		var data: Dictionary = run.layout.rooms[id]
		var spec: Dictionary = run.graph.rooms[id]
		var lane := float(data.lane)
		var jitter: float = float(spec.get("jitter",0)) if id not in [run.graph.start,run.graph.boss] else 0
		if compact: jitter *= .4
		var offset_x: float = float(spec.get("offset_x", 0))
		points[id] = Vector2(margin + (data.column + 1 + offset_x) * _pitch - _offset, top + clampf((lane + jitter - lane_min) / lane_span, 0, 1) * height)
	_node_scale = clampf(height/(maxf(3, lane_span)*56*_unit),0.3 if compact else 0.5,1.0)
	queue_redraw()


func _clamp_offset() -> void:
	_offset = clampf(_offset, 0, maxf(0, _span - size.x))


func _hit(at: Vector2) -> String:
	var best := ""
	var nearest := 35.0 * _unit
	for id: String in points:
		var distance := at.distance_to(points[id])
		if distance < nearest: best = id; nearest = distance
	return best


func _node_radius(id: String) -> float:
	return (27 if run.graph.rooms[id].kind=="boss" else 23) * _unit * _node_scale


func _connection_points(from: String, to: String) -> PackedVector2Array:
	var a: Vector2 = points[from]
	var b: Vector2 = points[to]
	var direction := a.direction_to(b)
	# Match the drawn faces, including compact phone nodes and the larger boss.
	return PackedVector2Array([a + direction * (_node_radius(from) + 3 * _unit), b - direction * (_node_radius(to) + 3 * _unit)])


func _focus_source() -> String:
	if planning: return plan_end()
	return _hover if not _hover.is_empty() else selected


func _preview_target(id: String) -> bool:
	var source := _focus_source()
	return run.graph.rooms.has(source) and not run.sealed.has(source) and not run.sealed.has(id) and run.graph.rooms[source].next.has(id)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			_offset += (-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1) * 100 * _unit
			_clamp_offset(); _layout(); accept_event()
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed: _down = event.position; _pressed = true; _dragged = false
			else:
				if _pressed and not _dragged:
					var id := _hit(event.position)
					if not id.is_empty(): node_selected.emit(id)
				_pressed = false
			accept_event()
	elif event is InputEventMouseMotion:
		if _pressed:
			if event.position.distance_to(_down)>8*_unit: _dragged = true
			if _dragged: _offset -= event.relative.x; _clamp_offset(); _layout()
		else:
			var id := _hit(event.position)
			if id!=_hover: _hover = id; queue_redraw()
	elif event is InputEventScreenTouch:
		if event.pressed and _pointer<0:
			_pointer = event.index; _down = event.position; _dragged = false
		elif not event.pressed and event.index==_pointer:
			if not _dragged:
				var id := _hit(event.position)
				if not id.is_empty(): node_selected.emit(id)
			_pointer = -1
		accept_event()
	elif event is InputEventScreenDrag and event.index==_pointer:
		if event.position.distance_to(_down)>8*_unit: _dragged = true
		if _dragged: _offset -= event.relative.x; _clamp_offset(); _layout()
		accept_event()
	elif event is InputEventPanGesture:
		_offset += event.delta.x * 36 * _unit
		_clamp_offset(); _layout(); accept_event()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_left"):
		_offset += 100 * _unit * (1 if event.is_action_pressed("ui_right") else -1)
		_clamp_offset(); _layout(); accept_event()
	elif event.is_action_pressed("ui_accept") and not selected.is_empty():
		node_selected.emit(selected); accept_event()


func _draw() -> void:
	if run==null or points.is_empty(): return
	draw_rect(Rect2(Vector2.ZERO,size),Color("10262f"))
	var margin := 22.0 * _unit
	for y in [(3.0 if _unit>1.1 else 18.0)*_unit,size.y-8.0*_unit]:
		draw_line(Vector2(0,y),Vector2(size.x,y),Color(JourneyStyle.GOLD,.28),1,true)
	var last_column := -100
	for id: String in run.graph.rooms:
		var data: Dictionary = run.layout.rooms[id]
		if data.column==last_column or id==run.graph.start: continue
		last_column = data.column
		var x: float = 54 * _unit + (data.column + 1) * _pitch - _offset
		_text("首领" if id==run.graph.boss else "%02d" % (data.column+1),Vector2(x,(9 if _unit>1.1 else 32)*_unit),11 if _unit>1.1 else 13,Color(JourneyStyle.GOLD,.5))
	for edge: Dictionary in run.graph.edges:
		var a: Vector2 = points[edge.from]
		var b: Vector2 = points[edge.to]
		var walked: bool = run.visited_rooms.has(edge.from) and run.visited_rooms.has(edge.to)
		var reachable: bool = edge.from==run.current_room and run.next_rooms().has(edge.to)
		if planning: reachable = edge.from==plan_end() and run.plan_choices().has(edge.to)
		var planned: bool = _planned_edge(edge.from,edge.to)
		var abandoned: bool = run.sealed.has(edge.from) or run.sealed.has(edge.to)
		var inspected: bool = edge.from==_focus_source() and not abandoned
		var color := Color(JourneyStyle.GOLD,.62)
		if planning and not (walked or planned or reachable): color = Color(JourneyStyle.GOLD,.4)
		if abandoned: color = Color(JourneyStyle.EDGE,.2)
		elif walked: color = JourneyStyle.RED
		elif planned: color = JourneyStyle.RED if planning else JourneyStyle.GOLD
		elif reachable or inspected: color = Color(JourneyStyle.GOLD,.95)
		var segment := _connection_points(edge.from,edge.to)
		var width := (2.2 if reachable or inspected or walked else (1.8 if planned else 1.2)) * _unit
		if abandoned: draw_dashed_line(segment[0],segment[1],color,width,4*_unit,true)
		else: draw_line(segment[0],segment[1],color,width,true)
		if reachable or planned or inspected:
			var middle := segment[0].lerp(segment[1],.7)
			var axis := a.direction_to(b)
			draw_polyline(PackedVector2Array([middle-axis.rotated(-.48)*6*_unit,middle,middle-axis.rotated(.48)*6*_unit]),color,1.6*_unit,true)
	for id: String in points: _draw_node(id)
	if planning: _draw_planning()
	if _span>size.x+2:
		var width := (size.x-margin*2)*size.x/_span
		var x := margin+(size.x-margin*2-width)*_offset/maxf(1,_span-size.x)
		draw_line(Vector2(x,size.y-8),Vector2(x+width,size.y-8),Color(JourneyStyle.GOLD,.6),3,true)


## 规划走到的最右一格：还没点就是当前
func plan_end() -> String:
	return run.planned_route[-1] if not run.planned_route.is_empty() else run.current_room


## 规划模式下这一格是否亮着：当前、已规划的、下一步候选
func plan_lit(id: String) -> bool:
	return id==run.current_room or run.planned_route.has(id) or run.plan_choices().has(id)


func _draw_planning() -> void:
	var pulse := .55 + .45 * sin(Time.get_ticks_msec() * .006)
	var end := plan_end()
	for id: String in points:
		var center: Vector2 = points[id]
		var radius := _node_radius(id)
		if not plan_lit(id):
			# 压暗：不在这一步能走到的格子
			draw_circle(center, radius + 3 * _unit, Color(0.04, 0.07, 0.08, .28))
			continue
		if run.plan_choices().has(id):
			draw_arc(center, radius + 7 * _unit, 0, TAU, 40, Color(JourneyStyle.GOLD, .35 + .5 * pulse), 2 * _unit, true)
		if run.planned_route.has(id):
			_draw_red_circle(center, radius + 9 * _unit, circle_progress(id))
			_text(str(run.planned_route.find(id) + 1), center + Vector2(radius + 14 * _unit, -radius), 13, JourneyStyle.RED)
		if id==end:
			# 规划走到的位置：外加一道呼吸的细圈（还没点时标在当前）
			var color: Color = JourneyStyle.RED if id!=run.current_room else JourneyStyle.GOLD
			draw_arc(center, radius + 16 * _unit, 0, TAU, 48, Color(color, .35 + .45 * pulse), 1.5 * _unit, true)


## 手绘红圈：从左上起笔顺时针描一圈，略微收尾出头，半径随笔画轻微起伏
func _draw_red_circle(center: Vector2, radius: float, progress: float) -> void:
	if progress <= 0: return
	var sweep := TAU * 1.08 * progress
	var steps := maxi(2, int(48 * progress))
	var line := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / steps
		var angle := -PI * .75 + sweep * t
		line.append(center + Vector2.from_angle(angle) * radius * (1.0 + .06 * t + .02 * sin(angle * 3)))
	draw_polyline(line, JourneyStyle.RED, 3 * _unit, true)


func _planned_edge(from: String, to: String) -> bool:
	var index: int = run.planned_route.find(to)
	return index>=0 and (from==run.current_room if index==0 else from==run.planned_route[index-1])


func _draw_node(id: String) -> void:
	var center: Vector2 = points[id]
	var spec: Dictionary = run.graph.rooms[id]
	var current: bool = id==run.current_room
	var available: bool = run.next_rooms().has(id) or run.plan_choices().has(id)
	var past: bool = run.visited_rooms.has(id) and not current
	var abandoned: bool = run.sealed.has(id)
	var planned: bool = run.planned_route.has(id)
	var marked: bool = selected==id or _hover==id
	var preview := _preview_target(id)
	var radius := _node_radius(id)
	var ink := Color("152e35")
	var line := JourneyStyle.GOLD if current or available or planned or preview else Color("7f8b7e")
	var text := JourneyStyle.TEXT
	if current: ink = Color("84382f"); line = JourneyStyle.GOLD
	elif past: ink = Color("3d3330"); line = JourneyStyle.RED
	elif abandoned: ink = Color("142930"); line = Color("35494b"); text = Color("66736e")
	elif spec.kind in ["elite","boss"]: ink = Color("3d2a2b"); line = Color("ba7360")
	if marked: line = JourneyStyle.TEXT
	var polygon := PackedVector2Array()
	var sides := 4 if spec.kind in ["elite","treasure"] else 8
	for i in sides: polygon.append(center+Vector2.from_angle(-PI*.5+TAU*i/sides)*radius)
	draw_colored_polygon(polygon,ink)
	polygon.append(polygon[0]); draw_polyline(polygon,line,(2 if current or marked or preview else 1.3)*_unit,true)
	if current or planned or marked:
		draw_arc(center,radius+5*_unit,PI*.15,PI*.85,12,line,1.2*_unit,true)
		draw_arc(center,radius+5*_unit,PI*1.15,PI*1.85,12,line,1.2*_unit,true)
	var glyph_size := maxi(11, roundi(26 * _node_scale))
	_text(GLYPHS.get(spec.kind,"？"),center+Vector2(0,glyph_size*.35*_unit),glyph_size,text)
	var caption: String = "当前" if current else ("已行" if past else LABELS[spec.kind])
	if current or marked and _unit<=1.1:
		_text(caption,center+Vector2(0,43*_unit),14,JourneyStyle.GOLD if current or available else text)
	if abandoned:
		draw_line(center+Vector2(-14,13)*_unit,center+Vector2(14,-13)*_unit,Color(JourneyStyle.EDGE,.8),1.5*_unit,true)


func _text(caption: String, at: Vector2, font_size: int, color: Color) -> void:
	var fs := roundi(font_size*_unit)
	var width := Ink.serif.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
	draw_string(Ink.serif,at-Vector2(width*.5,0),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,color)
