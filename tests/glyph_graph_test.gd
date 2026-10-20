extends Control

var _pass := 0
var _fail := 0
var _capture := false

func _ready() -> void:
	SaveManager.enabled = false
	get_window().size = Vector2i(1280,720)
	_capture = OS.get_cmdline_user_args().has("--capture")
	get_tree().create_timer(45).timeout.connect(func(): push_error("字网测试超时"); get_tree().quit(1))
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error(label)


func _frames(count := 4) -> void:
	for i in count:
		await get_tree().process_frame


func _positions(view: GlyphGraphView) -> Array:
	return view.nodes.map(func(nd): return nd.pos)


func _separated(view: GlyphGraphView) -> bool:
	for i in view.nodes.size():
		for j in range(i + 1, view.nodes.size()):
			if view.nodes[i].pos.distance_to(view.nodes[j].pos) < view.nodes[i].radius + view.nodes[j].radius + GlyphGraphView.NODE_GAP - 0.1:
				return false
	return true


func _mouse(view: GlyphGraphView, position: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = button
	event.pressed = pressed
	view._gui_input(event)


func _motion(view: GlyphGraphView, position: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.relative = relative
	view._gui_input(event)


func _capture_image(name: String) -> void:
	if _capture:
		RenderingServer.force_draw(false)
		_check(get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join(name)) == OK, "保存实际渲染 " + name)


func _run() -> void:
	var rng_before := GameState.rng.state
	var uid_before := CharInstance._next_uid
	var view := GlyphGraphView.new()
	add_child(view)
	view.rebuild(Database.words.values())
	var positions := _positions(view)
	_check(view.nodes.size() > 40 and view.edges.size() > 100, "完整字网来自真实数据库")
	_check(_separated(view), "完整图布局的字块保留最小间距")
	view.size = Vector2(20, 20)
	view._fit_to_canvas()
	view.size = Vector2(950, 530)
	view._fit_to_canvas()
	_check(positions == _positions(view), "先经历极小容器再展开，不压缩或破坏节点世界坐标")
	for dimensions in [Vector2(1000, 500), Vector2(420, 550), Vector2(950, 530)]:
		view.size = dimensions
		view._fit_to_canvas()
	_check(positions == _positions(view) and _separated(view), "连续缩放窗口保持布局和间距")
	var all_inside := true
	for nd in view.nodes:
		all_inside = all_inside and Rect2(Vector2.ZERO, view.size).has_point(view.world_to_view(nd.pos))
	_check(all_inside, "总览将全部节点放入可见画布")
	var anchor := Vector2(125, 175)
	var world_anchor := view.view_to_world(anchor)
	view.zoom_at(1.2, anchor)
	_check(world_anchor.is_equal_approx(view.view_to_world(anchor)), "鼠标所在世界点在缩放前后保持原位")
	_check(positions == _positions(view), "缩放不改变节点位置")
	view._fit_to_canvas()
	var nd: Dictionary = view.nodes[0]
	var node_pos := view.world_to_view(nd.pos)
	_check(view._node_at(node_pos) == nd.glyph, "节点命中使用与绘图相同的坐标变换")
	_mouse(view, node_pos, true)
	_mouse(view, node_pos, false)
	_check(view.selected == nd.glyph, "点击节点产生选择")
	var node_before: Vector2 = nd.pos
	_mouse(view, node_pos, true)
	_motion(view, node_pos + Vector2(45, 25), Vector2(45, 25))
	_mouse(view, node_pos + Vector2(45, 25), false)
	_check(not node_before.is_equal_approx(nd.pos), "字块可以拖动整理")
	_check(_separated(view), "拖动结束后分离碰撞，不把邻字压在一起")
	var center_before := view.camera_center
	_mouse(view, Vector2(2, 2), true, MOUSE_BUTTON_MIDDLE)
	_motion(view, Vector2(32, 22), Vector2(30, 20))
	_mouse(view, Vector2(32, 22), false, MOUSE_BUTTON_MIDDLE)
	_check(not center_before.is_equal_approx(view.camera_center), "中键拖动平移视野")
	var moved_center := view.camera_center
	var moved_zoom := view.zoom
	view.size = Vector2(800, 500)
	_check(view.camera_center == moved_center and view.zoom == moved_zoom, "手动浏览后调整窗口保持当前视野")
	view.select("击")
	view.set_focus_only(true)
	_check(view._visible_node("击") and view._focus.size() > 1 and view.nodes.size() > view._focus.size(), "相关模式保留选中字与直接邻字，不修改图数据")
	var selected_before := view.selected
	view.select("不存在")
	_check(view.selected == selected_before, "无效字查询不破坏已有选择")
	view.show_overview()
	_check(view.selected.is_empty() and view.nodes.all(func(n): return view._visible_node(n.glyph)), "相关模式中点总览恢复完整网络")
	view.set_focus_only(false)
	view.rebuild(Database.words.values())
	_check(positions == _positions(view), "相同数据重建得到相同布局")
	var repeated := WordData.new()
	repeated.word = "回回"
	repeated.glyphs.assign(["回", "回"])
	view.rebuild([repeated])
	_check(view.nodes.size() == 1 and view.nodes[0].words == 1 and view.edges.size() == 1, "含重复字的词只计一次出现，保留自环")
	await _frames(2)
	view.rebuild(Database.words.values(), ["火", "力"])
	_check(view.nodes.size() == 2 and view.edges.size() == 1 and view.nodes.all(func(n): return n.words == 1), "子图只收入完整可组成的词")
	view.rebuild([])
	view._fit_to_canvas()
	_check(view.nodes.is_empty() and is_finite(view.zoom), "空图与单节点不产生无效坐标")
	view.queue_free()
	await _frames()
	var screen: Control = load("res://src/screens/glyph_graph_screen.gd").new()
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _frames(8)
	print("[graph] screen=", screen.size, " graph=", screen._view.size, " sidebar=", screen._side.size)
	_check(str(Database.words.size()) in screen._scope_buttons.all.text, "范围按钮从数据库读取词数")
	_check(screen._view.size.x > 300 and screen._view.size.y > 200, "图谱保有可操作的画布")
	_check(screen.inventory_bar==null and screen.content.position.is_equal_approx(Vector2.ZERO), "图谱不显示局内资源栏，也不保留空白顶栏")
	_check(_separated(screen._view), "真实页面初次打开后节点不重叠")
	_capture_image("huoziluandou-graph-overview.png")
	screen._find("击")
	await _frames()
	_check(screen._view.selected == "击" and not screen._word_cards.is_empty(), "寻字同步定位并显示相关词效")
	_check(screen._word_cards.all(func(card): return card.word.glyphs.has("击")), "详情仅展示选中字的词")
	var first_card: Dictionary = screen._word_cards[0]
	var word_button: Button = first_card.effect.get_parent().get_child(0).get_child(0)
	word_button.pressed.emit()
	await _frames()
	_check(first_card.effect._cards.size() == 1 and first_card.effect._cards[0].get_meta("entry") == "word:" + first_card.word.word, "词语按钮打开该词的完整规则")
	first_card.effect.close_help()
	var link_preview: EffectText = screen._effect("获得反击")
	_check("[color=#a8cec2]" in link_preview.text, "深色图谱的规则链接使用可读的浅色")
	link_preview.free()
	screen._view._fit_to_canvas()
	await _frames()
	_capture_image("huoziluandou-graph-selected.png")
	screen._find("没有的词")
	_check("没有" in screen._hint.text and screen._view.selected == "击", "查无结果时清楚提示且保留选择")
	screen._find("反击")
	await _frames()
	_check(screen._view.selected == "反" and not get_tree().get_nodes_in_group("effect_help_open").is_empty(), "按词查询打开完整词效浮层")
	screen._set_scope("starter")
	await _frames()
	var starter: Array = screen._starter_glyphs()
	_check(screen._words.all(func(w): return w.glyphs.all(func(g): return starter.has(g))), "初始范围依据实际起始构筑且不包含袋外字词")
	_check(get_tree().get_nodes_in_group("effect_help_open").is_empty(), "切换范围清理词效浮层")
	screen._set_scope("all")
	screen._view.select("火")
	screen._focus_button.button_pressed = true
	await _frames()
	_capture_image("huoziluandou-graph-focused.png")
	if _capture:
		get_window().size = Vector2i(844, 390)
		await _frames(8)
		screen._layout()
		await _frames()
		_capture_image("huoziluandou-graph-phone.png")
	_check(not screen._side.is_visible_in_tree() or screen._side.get_global_rect().end.x <= get_viewport_rect().size.x + 1.0, "可见详情栏不超出视口")
	_check(screen._view.size.y > 160, "窄屏仍保留图谱浏览高度")
	_check(GameState.rng.state == rng_before and CharInstance._next_uid == uid_before, "图谱浏览不消耗随机数、不创建游戏实体")
	screen.queue_free()
	await _frames()
	print("[glyph_graph_test] PASS=%d FAIL=%d" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
