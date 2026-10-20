extends ScreenBase
## Live courtyard mode. All actions go through RoomRunState, including headless parity.
const RUN = preload("res://src/expedition/room_run_state.gd")
const VIEW = preload("res://src/map/garden_room_map_view.gd")
const EventArt = preload("res://src/core/event_art.gd")
const SHOP_PORTRAIT := "res://assets/characters/shopkeeper/portrait.png"
var run: RefCounted
var map_view: Control
var drawer: PanelContainer
var drawer_scroll: ScrollContainer
var choices_box: VBoxContainer
var inventory: PanelContainer
var inventory_layer: Control
var inventory_box: VBoxContainer
var navigation: HBoxContainer
var _routing := false
var _show_routes := false
var _art_textures := {}
var _planning_selected := ""
var _plan_message := ""


func suspend_session() -> void:
	_set_inventory_open(false)
	visible = false; process_mode = Node.PROCESS_MODE_DISABLED
	map_view.set_active(false)


func resume_session() -> void:
	var started := Time.get_ticks_usec()
	process_mode = Node.PROCESS_MODE_INHERIT; visible = true
	_routing = false; map_view.set_active(true)
	refresh()
	map_view.profile["resume_ms"] = (Time.get_ticks_usec()-started)/1000.0


func has_scene_background() -> bool: return true


func build(root: Control) -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	run = GameState.room_run
	if run==null: run = RUN.start()
	JourneyStyle.apply(self)
	map_view = VIEW.new(); map_view.run = run
	map_view.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.add_child(map_view)
	map_view.state_changed.connect(refresh)
	map_view.walker_pressed.connect(_toggle_inventory)
	map_view.overview_changed.connect(func(): refresh.call_deferred())
	map_view.node_selected.connect(_select_plan_node)
	map_view.exit_selected.connect(_select_exit)
	drawer = _panel(); root.add_child(drawer)
	drawer_scroll = ScrollContainer.new(); drawer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	drawer_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	drawer.add_child(drawer_scroll)
	choices_box = Ink.vbox(9); choices_box.size_flags_horizontal = SIZE_EXPAND_FILL; drawer_scroll.add_child(choices_box)
	choices_box.size_flags_vertical = SIZE_SHRINK_BEGIN
	choices_box.minimum_size_changed.connect(_layout.call_deferred)
	navigation = Ink.hbox(6); root.add_child(navigation)
	navigation.add_child(_button("回到行者",map_view.recenter))
	navigation.add_child(_button("路线图" if run.travel!=null else "总览",map_view.show_overview))
	navigation.add_child(_button("行囊" if run.travel!=null else "庭门",_toggle_inventory if run.travel!=null else func(): _show_routes = not _show_routes; refresh()))
	# The inventory is a modal overlay, independent of the camera's framing area.
	# Keep this last in the GUI tree so outside clicks cannot reach the map or drawer.
	inventory_layer = Control.new(); root.add_child(inventory_layer)
	inventory_layer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	inventory_layer.mouse_filter = MOUSE_FILTER_STOP
	inventory_layer.mouse_force_pass_scroll_events = false
	inventory_layer.gui_input.connect(_inventory_backdrop_input)
	inventory = _panel(); inventory_layer.add_child(inventory)
	inventory.mouse_filter = MOUSE_FILTER_STOP
	inventory.mouse_force_pass_scroll_events = false
	var scroll := ScrollContainer.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; inventory.add_child(scroll)
	inventory_box = Ink.vbox(8); inventory_box.size_flags_horizontal = SIZE_EXPAND_FILL; scroll.add_child(inventory_box)
	inventory_box.minimum_size_changed.connect(_layout.call_deferred)
	inventory_layer.visible = false; inventory.visible = false
	resized.connect(_layout)
	refresh(); _layout.call_deferred()


func _panel() -> PanelContainer:
	var result := PanelContainer.new()
	var paint := StyleBoxFlat.new(); paint.bg_color = Color(.025,.045,.055,.96)
	paint.set_content_margin_all(18); paint.border_color = Color("6a5840"); paint.border_width_left = 1
	result.add_theme_stylebox_override("panel",paint)
	return result


func _button(text: String, action: Callable, primary := false) -> Button:
	var result := Ink.button(text)
	result.custom_minimum_size.y = 48
	result.add_theme_font_size_override("font_size",16)
	for color in ["font_color","font_hover_color","font_pressed_color"]: result.add_theme_color_override(color,Color("d6c69e"))
	for state in ["normal","hover","pressed","focus","disabled"]:
		var paint := StyleBoxFlat.new(); paint.bg_color = Color(.07,.09,.075,.95) if primary else Color(.05,.075,.08,.93)
		paint.set_content_margin_all(9)
		paint.border_color = Color("d0a45c") if primary else Color("a78448"); paint.border_width_bottom = 1 if primary or state in ["hover","pressed","focus"] else 0
		result.add_theme_stylebox_override(state,paint)
	result.pressed.connect(action)
	return result


func _clear(box: Control) -> void:
	for child in box.get_children(): box.remove_child(child); child.queue_free()


func refresh() -> void:
	if _routing: return
	if run.phase in ["defeat", "victory"]:
		_routing = true
		goto.call_deferred("res://src/screens/run_result_screen.gd")
		return
	if map_view._building:
		drawer.visible = false
		return
	var node_screen: String = {"reward":"reward_screen.gd","event":"event_screen.gd","event_choose":"event_screen.gd","event_board":"event_board_screen.gd","shop":"shop_screen.gd","shop_choose":"shop_screen.gd","rest":"rest_screen.gd","rest_choose":"rest_screen.gd"}.get(run.phase,"") if run.travel!=null else ({"reward":"reward_screen.gd","event_board":"event_board_screen.gd"}.get(run.phase,""))
	if not node_screen.is_empty():
		_routing = true
		goto.call_deferred("res://src/screens/"+node_screen,{"room_run":true,"node":run.node})
		return
	map_view.refresh_run()
	if not map_view.selected_exit.is_empty() and not run.next_rooms().has(map_view.selected_exit): map_view.preview_exit("")
	_clear(choices_box)
	var is_map: bool = run.phase=="map"
	if run.travel!=null and map_view._overview:
		drawer.visible = true
		_build_planner()
		if inventory.visible: _refresh_inventory()
		_layout.call_deferred()
		return
	if run.travel!=null and is_map and not map_view.selected_exit.is_empty() and not map_view._moving:
		drawer.visible = true; _build_exit_preview(map_view.selected_exit)
		_layout.call_deferred(); return
	drawer.visible = not is_map or _show_routes or (run.travel==null and run.next_rooms().size()>1)
	if is_map and map_view._moving and not _show_routes: drawer.visible = false
	if run.phase=="generation_error":
		choices_box.add_child(Ink.body("庭院生成失败："+run.generation_error))
		choices_box.add_child(_button("返回标题",func(): goto("res://src/screens/title_screen.gd")))
	elif run.phase in ["victory","defeat"]:
		choices_box.add_child(Ink.h2("三幕已尽" if run.phase=="victory" else "此程止步"))
		choices_box.add_child(_button("再走一程",func(): RUN.start(); goto(RUN.MAP_SCREEN)))
		choices_box.add_child(_button("返回标题",func(): goto("res://src/screens/title_screen.gd")))
	else:
		choices_box.add_child(Ink.h2(run.layout.rooms[run.current_room].name))
		if run.phase=="encounter":
			choices_box.add_child(Ink.body("庭门暂封。解决此处的敌人后，出口开放。"))
			choices_box.add_child(_button("开战",_start_battle))
		elif run.phase=="event":
			var current_event: Dictionary = run.current_event()
			choices_box.add_child(Ink.h2(current_event.get("title",run.event_data.get("title","庭中奇遇"))))
			var art_path := str(current_event.get("illustration",run.event_data.get("illustration","")))
			if art_path.is_empty(): art_path = EventArt.path_for(str(current_event.get("id","")))
			var event_art := _art_card(art_path,150.0)
			if event_art!=null: choices_box.add_child(event_art)
			if GameState.event_temp_hp>0: choices_box.add_child(Ink.caption("借寿余火：%d" % GameState.event_temp_hp))
			choices_box.add_child(Ink.body(current_event.get("body",run.event_data.get("body",""))))
			_render_actions()
		elif run.phase=="event_relic":
			if not run.pending_event_relics.is_empty():
				var id := str(run.pending_event_relics[0])
				choices_box.add_child(Ink.h2("发现「%s」" % Relics.name_of(id)))
				choices_box.add_child(Ink.body(Relics.desc_of(id)))
				choices_box.add_child(Ink.caption("可放弃遗物；已付代价不返还。"))
			_render_actions()
		elif run.phase=="rest":
			choices_box.add_child(Ink.body("息灯休整，选择一项。")); _render_actions()
		elif run.phase=="shop":
			var shop_art := _art_card(SHOP_PORTRAIT,180.0,"字肆 · 店主")
			if shop_art!=null: choices_box.add_child(shop_art)
			choices_box.add_child(Ink.caption("商品与库存随本间字肆保存。")); _render_actions()
		elif run.phase.ends_with("_choose"):
			if run.phase=="event_choose":
				choices_box.add_child(Ink.caption("奇遇 · "+str(run.current_event().get("title",run.event_data.get("title","")))))
				if GameState.event_temp_hp>0: choices_box.add_child(Ink.caption("借寿余火：%d" % GameState.event_temp_hp))
				var remaining := int(run.pending_event_effect.get("remaining",1))
				choices_box.add_child(Ink.body("选择要删去的字（还需 %d 枚）。" % remaining))
			else:
				choices_box.add_child(Ink.body("选择要处理的字。"))
			_render_actions()
		elif run.phase=="act_end": _render_actions()
		elif is_map:
			if run.next_rooms().size()>1: choices_box.add_child(Ink.caption("选择下一庭后，来路与其余支路关闭。" if run.travel!=null else "越过一扇支路庭门后，另一支路两端封闭。"))
			for id: String in run.next_rooms():
				var preview := _preview(id)
				choices_box.add_child(_button(preview,func():
					if run.travel!=null: _select_plan_node(id); return
					if map_view.walk_to_room(id): drawer.visible = false; _set_inventory_open(false)))
	if inventory.visible: _refresh_inventory()
	_layout.call_deferred()


func _select_plan_node(id: String) -> void:
	if not run.graph.rooms.has(id) or map_view._moving: return
	map_view._set_overview(true)
	_planning_selected = id; _plan_message = ""
	if run.plan_choices().has(id) or run.planned_route.has(id) or run.graph.rooms[run.current_room].next.has(id):
		var result: Dictionary = run.apply({"type":"plan_room","room":id})
		if not result.ok: _plan_message = str(result.reason)
	refresh()


func _select_exit(id: String) -> void:
	if map_view._moving or run.phase!="map" or not run.next_rooms().has(id): return
	if map_view.selected_exit==id: _walk_exit(id); return
	map_view.preview_exit(id)
	refresh()


func _build_exit_preview(id: String) -> void:
	var room: Dictionary = run.graph.rooms[id]
	choices_box.add_child(Ink.h2("%02d · %s" % [room.number,run.LABELS[room.kind]]))
	choices_box.add_child(Ink.caption(room.role))
	choices_box.add_child(Ink.body("此后可去："+map_view.EXITS.following(run,id)))
	choices_box.add_child(Ink.caption("踏出庭门后关闭来路；未过门前可以改选。"))
	choices_box.add_child(_button("走这条路",func(): _walk_exit(id),true))
	choices_box.add_child(_button("查看整幕路线",func(): _planning_selected = id; map_view._set_overview(true)))
	choices_box.add_child(_button("收起",func(): map_view.preview_exit(""); refresh()))


func _walk_exit(id: String) -> void:
	# Choosing a physical exit can revise the first leg of a longer preview.
	# Arrival still consumes one node; nothing auto-runs the rest of the plan.
	if not run.next_rooms().has(id) or run.phase!="map": return
	if run.planned_route.is_empty() or run.planned_route[0]!=id: run.apply({"type":"plan_room","room":id})
	if map_view.walk_to_room(id):
		drawer.visible = false; _set_inventory_open(false); _layout.call_deferred()


func _build_planner() -> void:
	choices_box.add_child(Ink.h2("前路预选"))
	choices_box.add_child(Ink.caption("气血 %d/%d　铜钱 %d · 第%d幕" % [GameState.player_hp,GameState.player_max_hp,GameState.gold,GameState.act_index]))
	if not _planning_selected.is_empty():
		var spec: Dictionary = run.graph.rooms[_planning_selected]
		choices_box.add_child(Ink.label("%02d · %s · %s" % [spec.number,run.LABELS[spec.kind],spec.role]))
		if run.sealed.has(_planning_selected): choices_box.add_child(Ink.caption("此支路已放弃"))
	var route_labels: Array[String] = []
	var counts := {}
	for id: String in run.planned_route:
		var spec: Dictionary = run.graph.rooms[id]
		route_labels.append("%02d%s" % [spec.number,map_view.ATLAS.GLYPHS[spec.kind]])
		counts[spec.kind] = int(counts.get(spec.kind,0))+1
	if route_labels.is_empty():
		choices_box.add_child(Ink.body("先查看各支路，再点亮框节点预选。\n可以逐段规划到首领。"))
	else:
		choices_box.add_child(Ink.body(" → ".join(route_labels)))
		var summary: Array[String] = []
		for kind: String in counts: summary.append("%s%d" % [run.LABELS[kind],counts[kind]])
		choices_box.add_child(Ink.caption("预选 %d 庭 · %s" % [route_labels.size()," / ".join(summary)]))
	if not _plan_message.is_empty(): choices_box.add_child(Ink.caption(_plan_message))
	var choices: Array = run.plan_choices()
	choices_box.add_child(Ink.caption("首领已在路线末端" if choices.is_empty() else "可接续节点"))
	for id: String in choices:
		choices_box.add_child(_button(_preview(id),func(): _select_plan_node(id)))
	if not run.planned_route.is_empty():
		var first: String = run.planned_route[0]
		var go := _button("确认前往 %02d · %s" % [run.graph.rooms[first].number,run.LABELS[run.graph.rooms[first].kind]],_confirm_plan,true)
		go.disabled = run.phase!="map" or not run.next_rooms().has(first)
		choices_box.add_child(go)
		choices_box.add_child(_button("撤回末庭",func(): run.apply({"type":"undo_plan"}); refresh()))
		choices_box.add_child(_button("清空预选",func(): run.apply({"type":"clear_plan"}); refresh()))
	else:
		var go := _button("请先预选下一庭",func():pass,true); go.disabled = true; choices_box.add_child(go)
	if run.phase!="map": choices_box.add_child(Ink.caption("先完成当前节点，才能前往下一庭。"))
	choices_box.add_child(Ink.caption("预选可改；每次只前往第一庭，过门后关闭来路。"))
	choices_box.add_child(_button("返回庭院",map_view.recenter))


func _confirm_plan() -> void:
	if run.phase!="map" or run.planned_route.is_empty(): return
	var first: String = run.planned_route[0]
	if not run.next_rooms().has(first): return
	if map_view.walk_to_room(first):
		_set_inventory_open(false); drawer.visible = false
	else:
		_plan_message = "当前门路尚未开放"; refresh()


func _art_card(path: String, height: float, caption_text := "") -> Control:
	if path.is_empty() or not ResourceLoader.exists(path): return null
	if not _art_textures.has(path): _art_textures[path] = load(path)
	var texture: Texture2D = _art_textures[path]
	if texture == null: return null
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", JourneyStyle.frame("inset", 6))
	var box := Ink.vbox(4); box.mouse_filter = MOUSE_FILTER_IGNORE; panel.add_child(box)
	var image := TextureRect.new()
	image.texture = texture
	image.custom_minimum_size = Vector2(0, height)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_child(image)
	if not caption_text.is_empty():
		var caption := Ink.caption(caption_text); caption.mouse_filter = MOUSE_FILTER_IGNORE; box.add_child(caption)
	return panel


func _preview(id: String) -> String:
	var spec: Dictionary = run.graph.rooms[id]
	var text: String = run.LABELS[spec.kind]
	if run.travel!=null: text = "%02d %s · %s" % [spec.number,text,spec.role]
	var next: Array = spec.next
	if next.size()==1:
		var second: Dictionary = run.graph.rooms[next[0]]
		text += " → "+str(run.LABELS[second.kind])
	if spec.has("group"):
		var branch: Array = run.graph.groups[spec.group].branches[spec.branch]
		text += "　%d间后汇合" % branch.size()
		if branch.any(func(room): return run.graph.rooms[room].kind=="elite"): text += " · 途经精英"
	return text


func _render_actions() -> void:
	for action: Dictionary in run.legal_actions():
		var text := _action_text(action)
		var button := _button(text,func():
			var result: Dictionary = run.apply(action)
			if not result.get("ok",false): run._log(str(result.get("reason","操作失败")))
			if action.type=="event_relic_take" and result.get("ok",false):
				RelicRewardFlow.bind_owned(self,str(result.get("relic","")),func(_id): run._save_if_enabled(); refresh())
			else: refresh(),bool(action.get("primary",false)))
		if action.type=="shop_buy": button.disabled = GameState.gold<int(action.price)
		choices_box.add_child(button)


func _action_text(action: Dictionary) -> String:
	match action.type:
		"shop_buy":
			var name: String = {"buy_char":"活字【%s】" % action.glyph,"remove":"删去一枚字","copy":"拓印一枚字","heal":"回复30%气血"}.get(action.kind,action.kind)
			return "%s　%d钱" % [name,action.price]
		"shop_leave": return "离开字肆"
		"rest": return {"heal":"回复%d气血" % int(action.get("amount",0)),"remove":"删去一枚字","upgrade":"为一枚字镀金"}[action.kind]
		"event": return action.text
		"event_relic_take": return "收下「%s」" % Relics.name_of(str(action.relic))
		"event_relic_skip": return "放弃遗物"
		"pick": return "【%s】" % action.glyph
	return str(action.get("label",action.type))


func _start_battle() -> void:
	if not run.begin_live_battle(): return
	goto("res://src/screens/battle_screen.gd",{"room_run":true,"node":run.node,"seed":run.battle_seed()})


func _toggle_inventory() -> void:
	_set_inventory_open(not inventory.visible)


func _set_inventory_open(value: bool) -> void:
	inventory_layer.visible = value
	inventory.visible = value
	map_view.set_interaction_blocked(value)
	if value: _refresh_inventory()
	_layout.call_deferred()


func _inventory_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		# Consume the opening/closing click; closing must never also start walking.
		inventory_layer.accept_event()
		_set_inventory_open(false)


func _refresh_inventory() -> void:
	_clear(inventory_box)
	inventory_box.add_child(Ink.h2("行囊"))
	inventory_box.add_child(Ink.body("气血 %d / %d　铜钱 %d\n第%d幕 · 已过%d庭" % [GameState.player_hp,GameState.player_max_hp,GameState.gold,GameState.act_index,run.resolved.size()]))
	inventory_box.add_child(_button("查看字袋 · %d枚" % GameState.deck_size(),_open_deck))
	inventory_box.add_child(_button("收起行囊",func(): _set_inventory_open(false)))


func _open_deck() -> void:
	var overlay := CollectionOverlay.new()
	var counts := GameState.glyph_counts()
	var characters: Array = []
	for glyph in counts:
		var character := Database.get_character_by_glyph(glyph)
		if character!=null: characters.append(character)
	overlay.setup({"title":"字袋", "instances":GameState.deck,"characters":characters,"counts":counts})
	add_child(overlay)


func _layout() -> void:
	if drawer==null: return
	var margin := 16.0
	var usable := Rect2(Vector2(margin,margin),content.size-Vector2.ONE*margin*2)
	if OS.has_feature("mobile"):
		var pixels := DisplayServer.get_display_safe_area()
		var display_size := Vector2(DisplayServer.screen_get_size())
		if pixels.has_area() and display_size.x>0 and display_size.y>0:
			usable = Rect2(Vector2(pixels.position)*content.size/display_size,Vector2(pixels.size)*content.size/display_size).grow(-margin)
	navigation.position = Vector2(usable.position.x,usable.end.y-48)
	var narrow := content.size.x<760 or content.size.x/maxf(1,content.size.y)<1.15
	var width := usable.size.x if narrow else clampf(usable.size.x*.25,250,minf(340,usable.size.x))
	drawer.custom_minimum_size = Vector2(width,0)
	var panel_height := minf(choices_box.get_combined_minimum_size().y+36,content.size.y*(.36 if narrow else .60))
	drawer.size = Vector2(width,panel_height)
	var planning: bool = run.travel!=null and map_view._overview and not map_view._building
	if planning:
		panel_height = usable.size.y-64
		width = minf(300,usable.size.x*.36)
		drawer.custom_minimum_size.x = width; drawer.size = Vector2(width,panel_height)
	drawer.position = Vector2(usable.end.x-width,usable.position.y) if planning else (Vector2(usable.position.x,usable.end.y-panel_height-64) if narrow else Vector2(usable.end.x-width,usable.position.y))
	# Keep the event drawer on the opposite side of the walker. Moving the UI
	# preserves the exact camera framing when a new encounter opens its actions.
	if not planning and not narrow and map_view.walker!=null and drawer.visible:
		var foot: Vector2 = map_view.screen_point(map_view.walker.position)
		if foot.x>usable.get_center().x: drawer.position.x = usable.position.x
	drawer.visible = planning or not map_view._building and not map_view._overview and not map_view._moving and (run.phase!="map" or _show_routes or not map_view.selected_exit.is_empty() or (run.travel==null and run.next_rooms().size()>1))
	inventory.custom_minimum_size = Vector2(minf(340,content.size.x-36),0)
	inventory.size = Vector2(inventory.custom_minimum_size.x,minf(inventory_box.get_combined_minimum_size().y+36,content.size.y-margin*2))
	inventory.position = usable.get_center()-inventory.size*.5 if narrow else usable.position
	# Panels overlay the world. A service opening never changes the camera.
	var safe := Rect2(usable.position,usable.size-Vector2(0,64))
	map_view.set_safe_area(safe)
	map_view.set_planner_area(Rect2(usable.position,Vector2(maxf(80,usable.size.x-width-20),usable.size.y-64)) if planning else Rect2())
	map_view.ui_exclusions = [navigation.get_rect()]
	if drawer.visible: map_view.ui_exclusions.append(drawer.get_rect())
	if inventory.visible: map_view.ui_exclusions.append(inventory.get_rect())
	map_view._overlay.queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	for child in get_children():
		if child is CollectionOverlay: return
	if event.keycode==KEY_I:
		_toggle_inventory()
		get_viewport().set_input_as_handled()
	elif inventory.visible:
		if event.is_action_pressed("ui_cancel"): _set_inventory_open(false)
		get_viewport().set_input_as_handled()
	elif event.keycode==KEY_HOME: map_view.recenter()
	elif event.keycode==KEY_M: map_view.show_overview()
