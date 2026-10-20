extends Control

const FOLDER := "res://docs/qa/glyph-graph-2026-10-18/"
const PROFILES := [[960,432,160], [1280,720,0], [1280,720,320], [1920,1080,0], [2400,1080,440], [2532,1170,460], [3440,1440,0]]
var passed := 0
var failed := 0
var before := false

func _ready() -> void:
	Settings.storage_path = "user://glyph_graph_interaction_test-settings.cfg"
	before = "--before" in OS.get_cmdline_user_args()
	get_tree().create_timer(100).timeout.connect(func(): get_tree().quit(2))
	_run.call_deferred()

func frames(n := 6) -> void:
	for i in n: await get_tree().process_frame

func check(value: bool, message: String) -> void:
	if value: passed += 1; print("PASS ", message)
	else: failed += 1; push_error(message)

func _run() -> void:
	Settings.reduced_motion = true
	SaveManager.enabled = false
	Router.host = self
	for p in PROFILES:
		get_window().size = Vector2i(p[0], p[1])
		BattleTouchLayout.test_dpi = p[2]
		await frames()
		Router.goto("res://src/screens/glyph_graph_screen.gd")
		await frames(12)
		var screen = Router.current
		var tag := "%dx%d-%ddpi" % [p[0],p[1],p[2]]
		if not before: _layout_checks(screen, tag)
		await shot(tag, "all")
		screen._set_scope("starter")
		await frames()
		if not before:
			_layout_checks(screen, tag + " starter")
			check(screen._view.nodes.size() == 8, tag + " starter filter keeps eight glyphs")
		await shot(tag, "starter")
		if not before:
			screen._view.select("击")
			await frames()
			if screen._mobile:
				check(is_instance_valid(screen._details_overlay), tag + " mobile node opens dismissible details")
				check(screen.get_global_rect().encloses(screen._details_overlay._panel.get_global_rect()), tag + " details fit viewport")
			await shot(tag, "detail")
			await _close_details(screen)
			screen._set_scope("all")
			await frames()
			screen._view.zoom_at(2, screen._view.size * 0.5)
			screen._view._pan_by(Vector2(45,10))
			await shot(tag, "zoom-pan")
	if not before:
		await _interactions(false)
		await _interactions(true)
		await _resize_and_edge_cases()
	BattleTouchLayout.test_dpi = 0
	print("[glyph_graph_interaction_test] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed else 0)

func _layout_checks(screen: Control, tag: String) -> void:
	var graph: GlyphGraphView = screen._view
	check(not graph.nodes.is_empty() and graph.size.x > 100 and graph.size.y > 100, tag + " graph builds with usable area")
	check(screen.get_global_rect().encloses(graph.get_global_rect()), tag + " graph fits screen")
	var inside := true
	var separated := true
	for i in graph.nodes.size():
		var nd: Dictionary = graph.nodes[i]
		var radius := Vector2.ONE * (float(nd.radius) + 5) * graph.zoom
		inside = inside and Rect2(Vector2.ZERO, graph.size).encloses(Rect2(graph.world_to_canvas(nd.pos) - radius, radius * 2))
		for j in range(i + 1, graph.nodes.size()):
			separated = separated and (nd.pos as Vector2).distance_to(graph.nodes[j].pos) >= nd.radius + graph.nodes[j].radius - 0.5
	check(inside, tag + " every fitted node and selection ring is visible")
	check(separated, tag + " node circles do not overlap")
	var unit := JourneyStyle.touch_scale(screen)
	for button in screen._scope_buttons + screen._navigation_buttons + [screen._details_button, screen._back_button]:
		if button.is_visible_in_tree():
			check(screen.get_global_rect().encloses(button.get_global_rect()) and button.size.y >= 48 * unit - 0.5, tag + " action fits and retains 48dp: " + button.text)
	check(graph.size.x / screen.size.x > (0.90 if screen._mobile else 0.5), tag + " graph uses available width")
	check(26 * graph.zoom / unit >= 13.9, tag + " overview glyph text remains at least 14dp")
	print("LAYOUT ", tag, " viewport=", screen.size, " graph=", graph.size, " unit=", unit, " world=", graph._bounds_for(graph.nodes), " min_font_dp=", 26 * graph.zoom / unit)

func _close_details(screen: Control) -> void:
	if is_instance_valid(screen._details_overlay):
		screen._details_overlay._on_choose(0)
		await frames()

func _input_point(graph: Control, point: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * (graph.get_global_transform() * point)

func mouse(graph: Control, point: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT, device := 0) -> void:
	var event := InputEventMouseButton.new()
	event.position = _input_point(graph, point)
	event.button_index = button
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
	event.pressed = pressed
	event.device = device
	Input.parse_input_event(event)

func motion(graph: Control, point: Vector2, mask := MOUSE_BUTTON_MASK_LEFT) -> void:
	var event := InputEventMouseMotion.new()
	event.position = _input_point(graph, point)
	event.button_mask = mask
	Input.parse_input_event(event)

func touch(graph: Control, point: Vector2, pressed: bool, index := 0, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = _input_point(graph, point)
	event.index = index
	event.pressed = pressed
	event.canceled = canceled
	Input.parse_input_event(event)

func drag(graph: Control, point: Vector2, index := 0) -> void:
	var event := InputEventScreenDrag.new()
	event.position = _input_point(graph, point)
	event.index = index
	Input.parse_input_event(event)

func _interactions(mobile: bool) -> void:
	get_window().size = Vector2i(1600,720) if mobile else Vector2i(1280,720)
	BattleTouchLayout.test_dpi = 320 if mobile else 0
	await frames()
	Router.goto("res://src/screens/glyph_graph_screen.gd")
	await frames(12)
	var screen = Router.current
	var graph: GlyphGraphView = screen._view
	var signals: Array = []
	graph.node_selected.connect(func(info): signals.append(info.glyph))
	var node: Dictionary = graph.nodes[0]
	var point := graph.world_to_canvas(node.pos)
	var tag := "touch" if mobile else "mouse"
	if mobile: touch(graph, point, true)
	else: mouse(graph, point, true)
	await frames(1)
	check(signals.is_empty(), tag + " press does not prematurely select")
	if mobile: touch(graph, point, false)
	else: mouse(graph, point, false)
	await frames()
	check(signals == [node.glyph] and graph.selected == node.glyph, tag + " release selects the correct transformed glyph once")
	await _close_details(screen)
	var positions := graph.nodes.map(func(nd): return nd.pos)
	var previous := graph.pan
	point = graph.world_to_canvas(node.pos)
	var movement := Vector2(70,25) * JourneyStyle.touch_scale(screen)
	if mobile:
		touch(graph, point, true)
		drag(graph, point + movement)
		touch(graph, point + movement, false)
	else:
		mouse(graph, point, true)
		motion(graph, point + movement)
		mouse(graph, point + movement, false)
	await frames()
	check(graph.pan.distance_to(previous + movement) < 1 and signals.size() == 1, tag + " dragging on a node pans without selecting")
	check(positions == graph.nodes.map(func(nd): return nd.pos), tag + " pan does not mutate graph layout")
	graph._fit_to_canvas()
	if mobile:
		touch(graph, Vector2(25,25), true)
		drag(graph, Vector2(25,-25))
		touch(graph, Vector2(25,-25), false)
	else:
		mouse(graph, Vector2(25,25), true)
		motion(graph, Vector2(25,-25))
		mouse(graph, Vector2(25,-25), false)
	await frames()
	check(graph._mouse_button == 0 and graph._touches.is_empty() and signals.size() == 1, tag + " release outside graph cannot leave a stuck drag")
	# Hiding a page during an in-progress gesture must discard the old pointer.
	if mobile: touch(graph, graph.size * 0.5, true)
	else: mouse(graph, graph.size * 0.5, true)
	await frames(1)
	graph.hide()
	graph.show()
	await frames()
	check(graph._mouse_button == 0 and graph._touches.is_empty(), tag + " hiding graph cancels pending gestures")
	graph._fit_to_canvas()
	var center := graph.size * 0.5
	previous = graph.pan
	if mobile:
		touch(graph, Vector2(30,30), true)
		drag(graph, Vector2(85,40))
		touch(graph, Vector2(85,40), false)
	else:
		mouse(graph, Vector2(30,30), true, MOUSE_BUTTON_MIDDLE)
		motion(graph, Vector2(85,40), MOUSE_BUTTON_MASK_MIDDLE)
		mouse(graph, Vector2(85,40), false, MOUSE_BUTTON_MIDDLE)
	await frames()
	check(graph.pan != previous and signals.size() == 1, tag + " background drag pans without a node hit")
	graph._fit_to_canvas()
	var anchor := center + Vector2(25,10)
	var world := graph.canvas_to_world(anchor)
	if mobile:
		touch(graph, center - Vector2(60,0), true, 0)
		touch(graph, center + Vector2(60,0), true, 1)
		drag(graph, center - Vector2(120,0), 0)
		drag(graph, center + Vector2(120,0), 1)
		await frames()
		check(is_equal_approx(graph.zoom_ratio(), 2), "two native fingers double zoom")
		check(graph.canvas_to_world(center).distance_to(graph._bounds_for(graph.nodes).get_center()) < 0.1, "pinch keeps its central world point anchored")
		touch(graph, center + Vector2(120,0), false, 1)
		drag(graph, center - Vector2(100,0), 0)
		touch(graph, center - Vector2(100,0), false, 0)
		await frames()
		check(signals.size() == 1 and graph._touches.is_empty(), "pinch handoff pans and never creates a tap")
		point = graph.world_to_canvas(node.pos)
		mouse(graph, point, true, MOUSE_BUTTON_LEFT, InputEvent.DEVICE_ID_EMULATION)
		mouse(graph, point, false, MOUSE_BUTTON_LEFT, InputEvent.DEVICE_ID_EMULATION)
		await frames()
		check(signals.size() == 1, "emulated mouse cannot duplicate native touch selection")
		graph._fit_to_canvas()
		point = graph.world_to_canvas(node.pos)
		touch(graph, point, true)
		touch(graph, point, false, 0, true)
		await frames()
		check(graph._touches.is_empty() and signals.size() == 1, "canceled finger clears navigation and never selects")
	else:
		mouse(graph, anchor, true, MOUSE_BUTTON_WHEEL_UP)
		await frames()
		check(graph.zoom_ratio() > 1 and graph.canvas_to_world(anchor).distance_to(world) < 0.1, "wheel zoom stays anchored at pointer")
	graph.zoom_at(100, center)
	check(is_equal_approx(graph.zoom_ratio(), 8), tag + " maximum zoom is bounded")
	graph.zoom_at(0.00001, center)
	check(is_equal_approx(graph.zoom_ratio(), 0.5), tag + " minimum zoom is bounded")
	screen._navigation_buttons[2].pressed.emit()
	await frames()
	check(is_equal_approx(graph.zoom_ratio(), 1) and graph._auto_fit and screen._zoom_label.text == "100%", tag + " fit button restores full graph and displayed scale")
	screen._navigation_buttons[1].pressed.emit()
	screen._navigation_buttons[0].pressed.emit()
	check(is_equal_approx(graph.zoom_ratio(), 1), tag + " zoom buttons are reciprocal")
	graph.zoom_at(2, center)
	graph._pan_by(Vector2(25,10))
	point = graph.world_to_canvas(node.pos)
	# Select a node known to be visible at this zoom.
	for nd in graph.nodes:
		var candidate := graph.world_to_canvas(nd.pos)
		if Rect2(Vector2.ZERO, graph.size).grow(-30).has_point(candidate):
			node = nd
			point = candidate
			break
	if mobile:
		touch(graph, point, true)
		touch(graph, point, false)
	else:
		mouse(graph, point, true)
		mouse(graph, point, false)
	await frames()
	check(signals.size() == 2 and graph.selected == node.glyph, tag + " picking remains accurate after zoom and pan")
	await _close_details(screen)
	graph._fit_to_canvas()
	screen._set_scope("implemented")
	await frames()
	check(graph.selected.is_empty() and graph._auto_fit and screen._details_button.disabled, tag + " scope change resets camera and stale selection")
	check(graph.nodes.size() > 9 and graph.edges.size() > 0, tag + " implemented scope retains graph data")
	graph._pan_by(Vector2(100000,-100000))
	var bounds := graph._bounds_for(graph.nodes)
	var canvas_bounds := Rect2(graph.world_to_canvas(bounds.position), bounds.size * graph.zoom)
	check(canvas_bounds.intersects(Rect2(Vector2.ZERO, graph.size)), tag + " excessive pan cannot lose the entire graph")

func _resize_and_edge_cases() -> void:
	BattleTouchLayout.test_dpi = 0
	get_window().size = Vector2i(1280,720)
	await frames()
	Router.goto("res://src/screens/glyph_graph_screen.gd")
	await frames(12)
	var screen = Router.current
	var graph: GlyphGraphView = screen._view
	graph.zoom_at(2, graph.size * 0.5)
	graph._pan_by(Vector2(15,10))
	var world := graph.canvas_to_world(graph.size * 0.5)
	var positions := graph.nodes.map(func(nd): return nd.pos)
	get_window().size = Vector2i(960,432)
	await frames(12)
	check(screen._mobile and not screen._side.visible, "live resize switches to full-width compact graph")
	check(is_equal_approx(graph.zoom_ratio(), 2) and graph.canvas_to_world(graph.size * 0.5).distance_to(world) < 0.1, "live resize preserves explored center and relative zoom")
	check(positions == graph.nodes.map(func(nd): return nd.pos), "live resize never repacks the world")
	graph._fit_to_canvas()
	get_window().size = Vector2i(1920,1080)
	await frames(12)
	check(not screen._mobile and screen._side.visible and graph._auto_fit, "desktop resize restores side details and auto fit")
	_layout_checks(screen, "live resize desktop")
	graph.rebuild([])
	check(graph.nodes.is_empty() and graph.zoom > 0 and graph.pan.is_finite(), "empty graph fits without invalid coordinates")
	graph.rebuild([{"glyphs": ["甲"]}])
	check(graph.nodes.size() == 1 and graph._node_at(graph.world_to_canvas(graph.nodes[0].pos)) == "甲", "single isolated glyph is centered and selectable")
	graph.rebuild([{"glyphs": ["甲"]}, {"glyphs": ["乙"]}, {"glyphs": ["丙"]}, {"glyphs": ["丁"]}])
	_layout_checks(screen, "isolated-only")
	graph.rebuild([{"glyphs": ["甲","甲"]}])
	check(graph.nodes.size() == 1 and graph.edges.size() == 1 and graph.zoom > 0, "single connected self-loop fits safely")
	await frames()

func shot(tag: String, state: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	var folder := FOLDER + ("before/" if before else "after/")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	await frames(2)
	RenderingServer.force_draw(false)
	check(get_viewport().get_texture().get_image().save_png(folder + tag + "-" + state + ".png") == OK, "archive " + tag + " " + state)
