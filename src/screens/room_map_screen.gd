extends ScreenBase
## Horizontal branching scroll, using the saved event/shop/battle controller.
const RUN = preload("res://src/expedition/room_run_state.gd")
const VIEW = preload("res://src/map/node_route_view.gd")
const LABELS := {"start":"起点", "battle":"战斗", "elite":"精英", "boss":"首领", "event":"奇遇", "shop":"字肆", "treasure":"宝藏", "rest":"休息"}
var run: RefCounted
var loaded_act := 0
var map_view: Control
var _stats: Label
var _act_title: Label
var _action: Button
var _planner_button: Button
var _view_button: Button
var _clear_button: Button
var _hint: Label
var _tools: HBoxContainer
var _page: VBoxContainer
var _header: HBoxContainer
var _inventory_slot: HBoxContainer
var _selected := ""
var _routing := false
var _receipt_open := false


func build(root: Control) -> void:
	run = GameState.room_run
	if run==null: run = RUN.start()
	run.use_node_map()
	loaded_act = GameState.act_index
	var page := JourneyStyle.page(root)
	var header := Ink.hbox(18)
	_page = page; _header = header
	var act: ActData = Database.get_act(GameState.act_index)
	_act_title = JourneyStyle.label(act.title if act!=null else "炼字狱", "Heading")
	_act_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_act_title)
	_inventory_slot = Ink.hbox(0)
	_inventory_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_inventory_slot)
	_stats = JourneyStyle.label("", "Stat"); header.add_child(_stats)
	_stats.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_button("菜单",func(): PauseMenu.open()))
	page.add_child(header)
	map_view = VIEW.new(); map_view.run = run
	map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_view.node_selected.connect(_select_node); page.add_child(map_view)
	_hint = JourneyStyle.label("点选节点前往；预选可先规划路线。","Muted")
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_view.add_child(_hint)
	_tools = Ink.hbox(12)
	map_view.add_child(_tools)
	_clear_button = _quiet_button("重选",_clear_plan)
	_clear_button.tooltip_text = "清除路线"
	_tools.add_child(_clear_button)
	_view_button = _quiet_button("近览",_toggle_view)
	_tools.add_child(_view_button)
	_planner_button = _quiet_button("预选模式",_toggle_planning)
	_tools.add_child(_planner_button)
	_action = _button("前往",_confirm_selected,true)
	_action.custom_minimum_size.x = 120*JourneyStyle.touch_scale(self)
	_action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tools.add_child(_action)
	_tools.minimum_size_changed.connect(_place_tools.call_deferred)
	map_view.resized.connect(_place_tools.call_deferred)
	resized.connect(_sync_ui_scale.call_deferred)
	_sync_ui_scale.call_deferred()
	EventBus.gold_changed.connect(_on_gold); EventBus.hp_changed.connect(_on_hp)
	_selected = run.current_room
	refresh()


func _button(caption: String, callback: Callable, primary := false) -> Button:
	var button := JourneyStyle.button(caption,callback,primary)
	button.custom_minimum_size.y = 48*JourneyStyle.touch_scale(self)
	return button


func run_inventory_host() -> Control:
	return _inventory_slot


func _quiet_button(caption: String, callback: Callable) -> Button:
	var button := _button(caption,callback)
	button.flat = true
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.custom_minimum_size.x = 48*JourneyStyle.touch_scale(self)
	return button


func _toggle_view() -> void:
	if map_view._overview: map_view.focus_current()
	else: map_view.show_overview()
	_update_controls()


func _place_tools() -> void:
	if not is_instance_valid(_tools): return
	var unit := JourneyStyle.touch_scale(self)
	var margin := 16*unit
	_tools.reset_size()
	_tools.position = (map_view.size-_tools.size-Vector2.ONE*margin).max(Vector2.ONE*margin)
	_hint.position = Vector2(margin,_tools.position.y)
	_hint.size = Vector2(maxf(0,_tools.position.x-margin*2),_tools.size.y)


func _sync_ui_scale() -> void:
	if not is_instance_valid(_tools): return
	JourneyStyle.apply(self)
	var unit := JourneyStyle.touch_scale(self)
	var compact := ScreenLayout.safe_rect(self).size.y / unit < 600
	_page.add_theme_constant_override("separation",roundi((8 if compact else 20)*unit))
	_header.add_theme_constant_override("separation",roundi((8 if compact else 18)*unit))
	ScreenLayout.margins(_page.get_parent(),self,(12 if compact else 28)*unit)
	_act_title.add_theme_font_size_override("font_size",roundi((22 if compact else 30)*unit))
	_stats.add_theme_font_size_override("font_size",roundi((17 if compact else 23)*unit))
	for button in find_children("*","Button",true,false):
		button.custom_minimum_size.y = 48*unit
	for button in [_view_button,_clear_button]: button.custom_minimum_size.x = 48*unit
	_action.custom_minimum_size.x = 120*unit
	map_view.refresh()
	_place_tools.call_deferred()


func suspend_session() -> void:
	hide(); process_mode = Node.PROCESS_MODE_DISABLED


func resume_session() -> void:
	show(); process_mode = Node.PROCESS_MODE_INHERIT; _routing = false
	if loaded_act!=GameState.act_index:
		loaded_act = GameState.act_index; _selected = run.current_room
		map_view.show_overview()
	refresh()


func refresh() -> void:
	if _routing: return
	if run.phase in ["defeat", "victory"]:
		_routing = true
		goto.call_deferred("res://src/screens/run_result_screen.gd")
		return
	_update_stats()
	if run.phase=="battle": return
	var node_screen: String = {"reward":"reward_screen.gd", "event":"event_screen.gd", "event_choose":"event_screen.gd", "event_relic":"event_screen.gd",
		"event_board":"event_board_screen.gd", "shop":"shop_screen.gd", "shop_choose":"shop_screen.gd",
		"rest":"rest_screen.gd", "rest_choose":"rest_screen.gd"}.get(run.phase,"")
	if not node_screen.is_empty():
		_routing = true
		goto.call_deferred("res://src/screens/"+node_screen,{"room_run":true,"node":run.node})
		return
	if not run.graph.rooms.has(_selected): _selected = run.current_room
	map_view.selected = _selected; map_view.refresh()
	_update_controls()
	if run.phase=="treasure" and not _receipt_open: _treasure_receipt.call_deferred()
	elif not _receipt_open: _drain_relic_setup.call_deferred()


## 事件、宝藏里拿到的泥金笔 / 复字拓片 / 许愿笺：回到地图时补上挑字、许愿
func _drain_relic_setup() -> void:
	if _receipt_open or _routing or not is_inside_tree() or Relics.next_pending_peek().is_empty(): return
	_receipt_open = true
	RelicRewardFlow.drain_pending(self, func():
		_receipt_open = false
		run._save_if_enabled()  # 挑完的结果落盘
		refresh())


func _on_gold(_amount: int) -> void: _update_stats()
func _on_hp(_hp: int, _max_hp: int) -> void: _update_stats()


func _update_stats() -> void:
	if is_instance_valid(_stats): _stats.text = "气血 %d / %d" % [GameState.player_hp,GameState.player_max_hp]
	if is_instance_valid(_act_title):
		var act := Database.get_act(GameState.act_index)
		_act_title.text = act.title if act!=null else "炼字狱"


func _select_node(id: String) -> void:
	if not run.graph.rooms.has(id): return
	if map_view.planning: _plan_click(id); return
	_selected = id; map_view.selected = id; map_view.queue_redraw(); _update_controls()


func _toggle_planning() -> void:
	map_view.set_planning(not map_view.planning and run.phase=="map")
	refresh()


func _plan_click(id: String) -> void:
	if run.phase!="map": return
	var index: int = run.planned_route.find(id)
	var result: Dictionary
	if index>=0 and index==run.planned_route.size()-1: result = run.apply({"type":"undo_plan"})
	elif index>=0 or run.plan_choices().has(id): result = run.plan_room(id)
	elif id==run.current_room: result = run.apply({"type":"clear_plan"})
	else: return
	if not result.get("ok",false): return
	if not GameState.get_meta("courtyard_preview",false): Settings.dismiss_route_hint()
	_selected = run.planned_route[-1] if not run.planned_route.is_empty() else run.current_room
	refresh()


func _update_controls() -> void:
	if map_view.planning and run.phase!="map": map_view.set_planning(false)
	_planner_button.visible = run.phase=="map"
	_planner_button.text = "完成预选" if map_view.planning else "预选模式"
	var at_current: bool = _selected==run.current_room and run.phase=="map"
	_hint.visible = at_current and not Settings.route_hint_seen and run.planned_route.is_empty() and run.visited_rooms.size()==1
	_clear_button.visible = run.phase=="map" and not run.planned_route.is_empty()
	_view_button.text = "近览" if map_view._overview else "全图"
	_action.visible = true
	_action.disabled = false
	if run.phase=="encounter": _action.text = "进入战斗"
	elif run.phase=="act_end": _action.text = "完成此程" if GameState.act_index>=3 else "进入下一幕"
	elif run.phase in ["victory","defeat"]: _action.text = "返回标题"
	elif run.phase!="map": _action.hide()
	else:
		var target := _next_target()
		_action.visible = not target.is_empty()
		_action.text = "前往 · "+LABELS[run.graph.rooms[target].kind] if not target.is_empty() else "前往"
		_action.tooltip_text = "下一站 · "+LABELS[run.graph.rooms[target].kind] if not target.is_empty() else ""
	_place_tools.call_deferred()


func _next_target() -> String:
	if run.next_rooms().has(_selected): return _selected
	return run.planned_route[0] if not run.planned_route.is_empty() else ""


func _confirm_selected() -> void:
	if _routing: return
	if run.phase=="encounter": _start_battle(); return
	if run.phase=="act_end":
		run.apply({"type":"next_act"}); loaded_act = GameState.act_index; _selected = run.current_room
		map_view.show_overview(); refresh(); return
	if run.phase in ["victory","defeat"]: goto("res://src/screens/title_screen.gd"); return
	if run.phase!="map": return
	var target := _next_target()
	if target.is_empty(): return
	var result: Dictionary = run.apply({"type":"enter_room","room":target})
	_selected = run.current_room
	if not result.get("ok",false):
		var overlay := ChoiceOverlay.new()
		overlay.setup({"title":"无法前往","body":str(result.get("reason","")),"options":[{"text":"返回"}]})
		add_child(overlay)
		return
	if run.phase=="encounter": _start_battle()
	else: refresh()


func _start_battle() -> void:
	if not run.begin_live_battle(): return
	_routing = true
	goto("res://src/screens/battle_screen.gd",{"room_run":true,"node":run.node,"seed":run.battle_seed()})


func _clear_plan() -> void:
	run.apply({"type":"clear_plan"}); _selected = run.current_room; refresh()


func _treasure_receipt() -> void:
	if run.phase!="treasure" or _receipt_open: return
	_receipt_open = true
	var receipt: Dictionary = run.contents[run.current_room].get("treasure",{})
	var id := str(receipt.get("relic",""))
	var pending := bool(receipt.get("pending",false))
	var overlay := ChoiceOverlay.new()
	overlay.z_index = 100
	var options: Array = [{"text":"收下，继续前行","primary":true,"disabled":pending and GameState.has_relic(id)}]
	if pending: options.append({"text":"放弃遗物"})
	overlay.setup({"title":"宝藏 · 碑间遗器", "body":("%s遗物「%s」\n%s" % ["发现" if pending else "获得",Relics.name_of(id),Relics.desc_of(id)]) if not id.is_empty() else "普通遗物已取尽，获得 30 铜钱。",
		"relic_id":id,"options":options,"dismissible":pending,"dismiss_on_backdrop":false,"cancel_index":1})
	overlay.chose.connect(func(index: int):
		var result: Dictionary = run.apply({"type":"treasure_ack" if index==0 else "treasure_skip"})
		if not result.get("ok",false): _receipt_open = false; refresh(); return
		if not str(result.get("relic","")).is_empty():
			RelicRewardFlow.bind_owned(self,id,func(_id):
				run._save_if_enabled(); _receipt_open = false; refresh())
		else:
			_receipt_open = false; refresh())
	add_child(overlay)


func _open_deck() -> void:
	var counts := GameState.glyph_counts()
	var chars: Array = []
	for glyph: String in counts:
		var character := Database.get_character_by_glyph(glyph)
		if character!=null: chars.append(character)
	var overlay := CollectionOverlay.new()
	overlay.setup({"title":"字袋", "instances":GameState.deck, "subtitle":"%d 枚实体字" % GameState.deck_size(), "characters":chars, "counts":counts})
	add_child(overlay)
