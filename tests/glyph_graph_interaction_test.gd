extends Control
## Current graph page, live catalog and real pointer routing.
const QA := "res://docs/qa/glyph-graph-2026-10-21"
const PROFILES := [[1280,720,0],[1920,1080,0],[844,390,0],[960,432,160],[2400,1080,440]]
var passed := 0
var failed := 0
var capture := false

func _ready() -> void:
	SaveManager.enabled = false
	Settings.storage_path = "user://glyph-graph-review-settings.cfg"
	Settings.reduced_motion = true
	AudioServer.set_bus_mute(0,true)
	Engine.max_fps = 120
	capture = OS.get_cmdline_user_args().has("--capture")
	_run.call_deferred()

func frames(count := 6) -> void:
	for index in count: await get_tree().process_frame

func check(value: bool, message: String) -> void:
	if value: passed += 1; print("PASS ", message)
	else: failed += 1; push_error(message)

func shot(label: String) -> void:
	if not capture or DisplayServer.get_name()=="headless": return
	DirAccess.make_dir_recursive_absolute(QA)
	var ignore := FileAccess.open(QA.path_join(".gdignore"),FileAccess.WRITE)
	ignore.close()
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(QA.path_join("after-"+label+".png"))==OK,"capture "+label)

func close_details(screen: Control) -> void:
	if is_instance_valid(screen._details_overlay):
		screen._details_overlay._close()
		await frames()

func send(graph: Control, event: InputEvent, point: Vector2) -> void:
	event.position = graph.get_global_transform()*point
	get_viewport().push_input(event,true)

func mouse(graph: Control, point: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT, emulated := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	if emulated: event.device = InputEvent.DEVICE_ID_EMULATION
	send(graph,event,point)

func finger(graph: Control, point: Vector2, pressed: bool, index := 0, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.canceled = canceled
	send(graph,event,point)

func drag(graph: Control, point: Vector2, index := 0) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	send(graph,event,point)

func _run() -> void:
	Router.host = self
	var rng_before := GameState.rng.state
	var uid_before := CharInstance._next_uid
	for profile in PROFILES:
		get_window().size = Vector2i(profile[0],profile[1])
		BattleTouchLayout.test_dpi = profile[2]
		await frames()
		Router.goto("res://src/screens/glyph_graph_screen.gd")
		await frames(12)
		var screen: Control = Router.current
		var graph: GlyphGraphView = screen._view
		var tag := "%dx%d-%ddpi" % [profile[0],profile[1],profile[2]]
		check(screen.inventory_bar==null and screen.content.position.is_equal_approx(Vector2.ZERO),tag+" no adventure HUD or empty strip")
		check(screen._words.size()==Database.words.size(),tag+" includes every registered word")
		check(screen.get_global_rect().encloses(graph.get_global_rect()) and graph.size.y>160,tag+" graph fits available space")
		var unit := JourneyStyle.touch_scale(screen)
		var buttons: Array = screen._scope_buttons.values()+screen._navigation_buttons+[screen._back_button]
		check(buttons.all(func(b):return screen.get_global_rect().encloses(b.get_global_rect()) and b.size.y>=48*unit-0.5),tag+" controls fit with 48dp targets")
		check(not screen._mobile or (not screen._side.visible and graph.size.x/screen.size.x>0.90),tag+" compact graph uses full width")
		check(screen._navigation_buttons.all(func(b):return b.size.x>=48*unit-0.5),tag+" zoom controls keep 48dp width")
		check(not screen._mobile or graph.zoom/unit>=0.74,tag+" compact initial view uses readable letter sizes")
		await shot(tag+"-all")
		graph.show_overview()
		check(graph.nodes.all(func(nd):return Rect2(Vector2.ZERO,graph.size).has_point(graph.world_to_view(nd.pos))),tag+" overview fits all letters")
		await shot(tag+"-overview")
		screen._set_scope("starter")
		await frames()
		var starter: Array = screen._starter_glyphs()
		check(graph.nodes.size()==starter.size() and starter.all(func(g):return graph._index.has(g)),tag+" starter scope keeps isolated letters")
		check(screen._words.all(func(w):return w.glyphs.all(func(g):return starter.has(g))),tag+" no partial starter words")
		await shot(tag+"-starter")
		graph.select("击")
		await frames()
		if screen._mobile:
			check(is_instance_valid(screen._details_overlay) and screen.get_global_rect().encloses(screen._details_overlay._panel.get_global_rect()),tag+" details fit compact viewport")
		else: check(screen._side.visible and not screen._word_cards.is_empty(),tag+" desktop sidebar shows word details")
		await shot(tag+"-details")
		await close_details(screen)
		check(screen._detail.get_parent()==screen._detail_scroll,tag+" closing details restores shared content")
		screen._set_scope("all")
		screen._find("反击")
		await frames()
		check(graph.selected=="反" and not get_tree().get_nodes_in_group("effect_help_open").is_empty(),tag+" word search opens full-effect links")
		for effect in get_tree().get_nodes_in_group("effect_help_open"): effect.close_help()
		await close_details(screen)
		var selected := graph.selected
		screen._find("不存在的词")
		check(graph.selected==selected and screen._hint.text.contains("没有"),tag+" failed search preserves selection")
		screen._set_scope("implemented")
		await frames()
		check(screen._words.all(func(w):return w.implemented),tag+" implemented scope uses current flags")
		await close_details(screen)
	await inputs(false)
	await inputs(true)
	check(GameState.rng.state==rng_before and CharInstance._next_uid==uid_before,"graph never changes gameplay RNG or creates entities")
	BattleTouchLayout.test_dpi = 0
	Router.release_host(self)
	Music.stop()
	print("[glyph_graph_interaction_test] PASS=%d FAIL=%d" % [passed,failed])
	get_tree().quit(1 if failed else 0)

func inputs(touch_mode: bool) -> void:
	BattleTouchLayout.test_dpi = 0
	get_window().size = Vector2i(844,390) if touch_mode else Vector2i(1280,720)
	await frames()
	Router.goto("res://src/screens/glyph_graph_screen.gd")
	await frames(12)
	var screen: Control = Router.current
	screen._set_scope("starter")
	await frames()
	var graph: GlyphGraphView = screen._view
	var node: Dictionary = graph._index["击"]
	var point := graph.world_to_view(node.pos)
	var signals: Array = []
	graph.node_selected.connect(func(info):signals.append(info.get("glyph","")))
	var tag := "touch" if touch_mode else "mouse"
	if touch_mode: finger(graph,point,true)
	else: mouse(graph,point,true)
	await frames(1)
	check(signals.is_empty(),tag+" no selection on press")
	if touch_mode: finger(graph,point,false)
	else: mouse(graph,point,false)
	await frames()
	check(graph.selected=="击" and signals==["击"],tag+" release selects visible node once")
	await close_details(screen)
	var positions := graph.nodes.map(func(nd):return nd.pos)
	var center := graph.size*0.5
	var camera_before := graph.camera_center
	if touch_mode:
		finger(graph,center,true)
		drag(graph,center+Vector2(60,20))
		finger(graph,center+Vector2(60,20),false)
	else:
		mouse(graph,center,true,MOUSE_BUTTON_MIDDLE)
		var motion := InputEventMouseMotion.new()
		motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
		send(graph,motion,center+Vector2(60,20))
		mouse(graph,center+Vector2(60,20),false,MOUSE_BUTTON_MIDDLE)
	await frames()
	check(graph.camera_center!=camera_before and signals.size()==1,tag+" pan does not select another node")
	check(positions==graph.nodes.map(func(nd):return nd.pos),tag+" navigation preserves node layout")
	graph.show_overview()
	if touch_mode:
		var world := graph.view_to_world(center)
		var zoom_before := graph.zoom
		finger(graph,center-Vector2(60,0),true,0)
		finger(graph,center+Vector2(60,0),true,1)
		drag(graph,center-Vector2(90,0),0)
		drag(graph,center+Vector2(90,0),1)
		check(graph.zoom>zoom_before and graph.view_to_world(center).distance_to(world)<0.1,"pinch preserves the central world point")
		finger(graph,center+Vector2(90,0),false,1)
		drag(graph,center-Vector2(70,0),0)
		finger(graph,center-Vector2(70,0),false,0)
		await frames()
		check(graph._touches.is_empty() and signals.size()==2,"pinch handoff never creates a tap")
		point = graph.world_to_view(node.pos)
		mouse(graph,point,true,MOUSE_BUTTON_LEFT,true)
		mouse(graph,point,false,MOUSE_BUTTON_LEFT,true)
		await frames()
		check(signals.size()==2,"emulated mouse does not duplicate a finger action")
		finger(graph,center,true)
		finger(graph,center,false,0,true)
		check(graph._touches.is_empty() and signals.size()==2,"canceled finger clears gesture without selecting")
	else:
		var world := graph.view_to_world(center)
		mouse(graph,center,true,MOUSE_BUTTON_WHEEL_UP)
		await frames()
		check(graph.view_to_world(center).distance_to(world)<0.1,"wheel zoom remains anchored")
	if touch_mode:
		finger(graph,Vector2(12,12),true)
		drag(graph,Vector2(12,-20))
		finger(graph,Vector2(12,-20),false)
	else:
		mouse(graph,Vector2(12,12),true,MOUSE_BUTTON_MIDDLE)
		mouse(graph,Vector2(12,-20),false,MOUSE_BUTTON_MIDDLE)
	await frames()
	check(graph._mouse_button==0 and graph._touches.is_empty(),tag+" release outside clears capture")
	if touch_mode: finger(graph,center,true)
	else: mouse(graph,center,true)
	graph.hide()
	graph.show()
	await frames()
	check(graph._mouse_button==0 and graph._touches.is_empty(),tag+" hiding graph cancels gestures")
	var before_positions := graph.nodes.map(func(nd):return nd.pos)
	get_window().size = Vector2i(1280,720) if touch_mode else Vector2i(844,390)
	await frames(12)
	check(before_positions==graph.nodes.map(func(nd):return nd.pos),tag+" resize preserves node positions")
	await shot(tag+"-resized")
