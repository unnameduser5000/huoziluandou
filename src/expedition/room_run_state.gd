extends RunHarness
## Shared controller for the live courtyard screen and the headless run bridge.
const GRAPH = preload("res://src/expedition/room_route_graph.gd")
const LAYOUT = preload("res://src/expedition/garden_room_layout.gd")
const SAVE = preload("res://src/expedition/room_run_save.gd")
const MAP_SCREEN := "res://src/screens/room_map_screen.gd"
const SAVE_PATH := "user://courtyard-run.tres"
const WORD_BOARD = preload("res://src/expedition/event_word_board.gd")
const LABELS := {"start":"起点","battle":"普通战","elite":"精英","boss":"首领","event":"事件","rest":"火堆","shop":"商店","treasure":"宝藏"}
var graph := {}
var layout: RefCounted
var current_room := "start"
var spawned_battle := false # 事件结算后临时触发的战斗，不新增地图节点
var pending_spawn := "" # 事件选项的即时遭遇：treasure / battle
var pending_spawn_relic := "" # 事件战斗胜利后的遗物奖励
var spawn_battle_relic := "" # 当前事件战斗挂起的遗物奖励
var event_board := {} # 璇玑字盘：seed / glyphs / words / paths
var resolved := {}
var visited_rooms := {}
var choices := {}
var sealed := {}
var contents := {} # Per-room cached event, shop stock and reward resources.
var seen_events: Array = [] # Event IDs already drawn in this run; avoids repeats until the act pool is exhausted.
var event_bags := {}
var last_event_id := ""
var position := Vector2i.ZERO
var autosave := false
var generation_error := ""
var layout_kind := "node_graph"   ## 只有节点图在接线；garden/旧 procedural 已停用
var generation_ms := 0.0
var travel: RefCounted
var planned_route: Array[String] = [] # Preview only; confirmation still advances one encounter.


static func start(seed_value := -1):
	var run = load("res://src/expedition/room_run_state.gd").new()
	if seed_value<0: seed_value = int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec())
	run.reset({"seed":seed_value,"layout":"node_graph"})
	GameState.first_run_tutorial = not Settings.first_run_tutorial_completed
	run.autosave = not bool(GameState.get_meta("courtyard_preview",false))
	if run.phase != "generation_error": Achievements.start_run("courtyard")
	if run.autosave: run.save_run()
	return run


func reset(cfg: Dictionary = {}) -> void:
	super.reset(cfg)
	layout_kind = str(cfg.get("layout","node_graph"))
	GameState.room_run = self
	GameState.expedition = null
	resolved.clear(); visited_rooms.clear(); choices.clear(); sealed.clear(); contents.clear()
	seen_events.clear(); event_bags.clear(); last_event_id = ""
	_load_act(1)


func _load_act(number: int) -> void:
	var began := Time.get_ticks_usec()
	GameState.act_index = number
	GameState.node_index = 1
	travel = null
	generation_error = ""
	var fitted := false
	if layout_kind == "node_graph":
		layout = preload("res://src/expedition/node_route_layout.gd").new()
		graph = preload("res://src/expedition/node_route_plan.gd").generate(seed,number)
		fitted = layout.build(graph)
	else:
		# garden / 旧 procedural 路线已停用：不再生成，只提示（旧存档会走这里）
		layout = preload("res://src/expedition/node_route_layout.gd").new()
		graph = {}
		layout.error = "这条路线已停用（%s），请开始新冒险" % layout_kind
	if not fitted: generation_error = layout.error; phase = "generation_error"; return
	current_room = graph.start
	resolved = {current_room:true}; visited_rooms = {current_room:true}
	choices.clear(); sealed.clear(); contents.clear()
	graph["enemy_history"] = []
	planned_route.clear()
	position = layout.rooms[current_room].stand_cell
	phase = "map"; node = null; battle_h = null; spawned_battle = false
	event_board.clear()
	_restore_travel({})
	generation_ms = (Time.get_ticks_usec()-began)/1000.0
	_log("第%d幕：选择庭门前进，首领守在终庭。" % number)


func _sync_content() -> void:
	if not contents.has(current_room): contents[current_room] = {}
	var data: Dictionary = contents[current_room]
	data["reward"] = reward_options.duplicate()
	data["shop"] = shop_offers.duplicate(true)
	data["event"] = event_data.duplicate(true)
	data["event_board"] = event_board.duplicate(true)


func _start_event() -> void:
	var pool: Array = EventEffects.pool(GameState.act_index)
	var key := str(GameState.act_index)
	var ids: Array = event_bags.get(key,[])
	# Conditional events can leave the pool after a relic is removed.
	ids = ids.filter(func(id): return pool.any(func(event): return str(event.id)==str(id)))
	if ids.is_empty():
		ids = pool.filter(func(event): return not seen_events.has(str(event.id))).map(func(event): return str(event.id))
		if ids.is_empty(): ids = pool.map(func(event): return str(event.id))
	var candidates: Array = pool.filter(func(event):return ids.has(str(event.id)))
	if candidates.size()>1: candidates = candidates.filter(func(event): return str(event.id)!=last_event_id)
	event_data = EventEffects.choose(candidates,GameState.rng)
	event_data = LANTERN.fill(event_data, GameState.rng)
	event_data = SHEFU.fill(event_data, GameState.rng)
	event_node = "start"
	pending_event_next = ""
	var event_id := str(event_data.get("id", ""))
	ids.erase(event_id); event_bags[key] = ids; last_event_id = event_id
	if not event_id.is_empty() and not seen_events.has(event_id): seen_events.append(event_id)
	pending_event_effect.clear()
	pending_event_relics.clear()
	event_board.clear()
	_log("奇遇：" + str(event_data.get("title", "")))
	phase = "event"


func _apply_event(action: Dictionary) -> Dictionary:
	var current := current_event()
	var options: Array = current.get("options", [])
	var index := int(action.get("index", -1))
	if index < 0 or index >= options.size() or not EventEffects.option_available(options[index]): return _fail("无效事件选项")
	var option: Dictionary = options[index]
	var result: Dictionary = EventEffects.resolve(option.get("effects", []), GameState.rng, true)
	if not result.get("ok", false): return _fail(str(result.get("reason", "事件结算失败")))
	for note in (result.get("notes", []) as Array):
		if not event_notes.has(str(note)): event_notes.append(str(note))
	pending_event_effect = result.get("pending", {})
	pending_event_relics = result.get("relic_offers", [])
	pending_event_next = str(option.get("goto", ""))
	_remember_event_note(option)
	pending_spawn = str(option.get("spawn", ""))
	pending_spawn_relic = str(option.get("spawn_relic", ""))
	if pending_event_effect.is_empty():
		if GameState.player_hp <= 0 or not pending_event_relics.is_empty():
			_advance_event()
		elif bool(option.get("board", false)):
			_start_event_board()
		elif pending_spawn.is_empty():
			_advance_event()
		else:
			_spawn_after_event(pending_spawn)
	else:
		pending_glyphs = pending_event_effect.get("glyphs", [])
		phase = "event_choose"
	return {"ok":true,"phase":phase}


func _advance_event() -> void:
	if GameState.player_hp <= 0 or not pending_event_relics.is_empty():
		super._advance_event()
		return
	var spawn := pending_spawn
	pending_spawn = ""
	if not spawn.is_empty() and pending_event_next.is_empty():
		_spawn_after_event(spawn)
		return
	super._advance_event()


func _cancel_pick() -> Dictionary:
	var was_event := phase == "event_choose"
	var result := super._cancel_pick()
	if result.get("ok", false) and was_event:
		pending_spawn = ""
		pending_spawn_relic = ""
	return result


## 璇玑字盘：进入后只做一次选词，选中的词给其中不重复的字。
func _start_event_board() -> void:
	var board_seed := GameState.rng.randi()
	event_board = WORD_BOARD.generate(board_seed)
	event_board["event_id"] = str(event_data.get("id", ""))
	phase = "event_board"
	_log("璇玑图：锦线已亮")
	_sync_content()
	_save_if_enabled()


func _resolve_event_board(path: Array) -> Dictionary:
	if phase != "event_board" or event_board.is_empty():
		return _fail("璇玑字盘已经收起")
	var glyphs: Array = event_board.get("glyphs", [])
	if path.size() < 2 or path.size() > 3:
		return _fail("只可读二至三字的词")
	var used := {}
	var word_glyphs: Array = []
	var prev := Vector2i(-1, -1)
	for raw in path:
		var pos: Vector2i = raw
		if pos.x < 0 or pos.y < 0 or pos.x >= 4 or pos.y >= 4:
			return _fail("锦线超出了字盘")
		if used.has(pos):
			return _fail("同一枚字不能重复经过")
		if prev.x >= 0 and absi(prev.x - pos.x) + absi(prev.y - pos.y) != 1:
			return _fail("锦线只能走四邻")
		used[pos] = true
		prev = pos
		var idx := pos.y * 4 + pos.x
		if idx >= glyphs.size() or str(glyphs[idx]).is_empty():
			return _fail("锦线上没有字")
		word_glyphs.append(str(glyphs[idx]))
	var word: WordData = Database.get_word_by_glyphs(word_glyphs)
	if word == null:
		return _fail("“%s”不成词" % "".join(word_glyphs))
	var unique: Array = []
	for glyph in word_glyphs:
		if unique.has(glyph):
			continue
		var cd: CharacterData = Database.get_character_by_glyph(str(glyph))
		if cd != null and not cd.is_pollution:
			unique.append(str(glyph))
			GameState.add_character(cd)
	_log("璇玑图：读出「%s」，收入 %s" % [word.word, "、".join(unique)])
	Achievements.event_completed(str(event_data.get("id", "")))
	_complete_node()
	return {"ok": true, "phase": phase, "glyphs": unique}


func _leave_event_board() -> Dictionary:
	if phase != "event_board":
		return _fail("璇玑字盘已经收起")
	_complete_node()
	return {"ok": true, "phase": phase}


## 事件附带的宝箱先展示遗物；战斗胜利后也保留领取或放弃的选择。
func _spawn_after_event(kind: String) -> void:
	Achievements.event_completed(str(event_data.get("id", "")))
	pending_spawn = ""
	pending_event_effect.clear()
	pending_event_next = ""
	pending_glyphs.clear()
	match kind:
		"treasure":
			_offer_event_relic("random", 30)
		"battle":
			spawned_battle = true
			spawn_battle_relic = pending_spawn_relic
			pending_spawn_relic = ""
			node = _event_battle_node(true)
			phase = "encounter"
			_log("奇遇：拦路的字影扑了上来")
		_:
			_complete_node()


func _offer_event_relic(mode: String, fallback_gold: int) -> void:
	var result := EventEffects.resolve([{"type":"gain_relic", "relic":mode, "fallback_gold":fallback_gold}], GameState.rng, true)
	pending_event_relics = result.get("relic_offers", [])
	_advance_event()


func _grant_treasure_relic() -> String:
	var choices: Array = Relics.roll_choices(GameState.relics, GameState.rng, 1)
	if choices.is_empty():
		return ""
	var id := str(choices[0])
	if not GameState.add_relic(id):
		return ""
	if Relics.needs_bind(id):
		for inst: CharInstance in GameState.deck:
			if GameState.bind_relic(id, inst.id()): break
	Relics.queue_setup(id)  # 挑字 / 许愿留给地图界面补上（存档里也记着）
	_log("宝箱：获得遗物「%s」" % Relics.name_of(id))
	return id


func _event_battle_node(commit := false) -> MapNodeData:
	var result := MapNodeData.new()
	result.type = MapNodeData.Type.BATTLE
	result.title = "奇遇 · 拦路"
	var pool: Array = EnemyRoster.NORMAL[GameState.act_index] if layout_kind=="node_graph" else Expedition.FOE_ENEMY
	var enemy_id := _select_encounter(current_room, pool, pool, commit, "event_enemy_id")
	var enemy: EnemyData = Database.get_enemy(enemy_id).duplicate(true)
	if layout_kind!="node_graph": enemy.max_hp = roundi(enemy.max_hp * (1 + .25 * (GameState.act_index - 1)))
	result.enemies.append(enemy)
	return result


func next_rooms() -> Array:
	if not graph.rooms.has(current_room) or not resolved.has(current_room): return []
	return graph.rooms[current_room].next.filter(func(id): return not sealed.has(id))


func _room_available(id: String) -> bool:
	if travel!=null or layout_kind=="node_graph": return id==current_room or next_rooms().has(id)
	if sealed.has(id): return false
	if visited_rooms.has(id): return true
	for previous: String in graph.rooms[id].previous:
		if resolved.has(previous): return true
	return false


func walkable(cell: Vector2i) -> bool:
	if layout_kind=="node_graph": return cell==position
	if not layout.cells.has(cell): return false
	if travel!=null:
		if not layout.links.has(cell): return false
		var owner: String = layout.compact.cells[cell]
		return owner.is_empty() or owner==current_room or next_rooms().has(owner)
	var entry: Dictionary = layout.cells[cell]
	for id: String in entry.rooms:
		if _room_available(id): return true
	for edge_id: String in entry.edges:
		var ends := edge_id.split(">")
		if not sealed.has(ends[0]) and not sealed.has(ends[1]) and resolved.has(ends[0]): return true
	return false


func move_path(target: Vector2i) -> Array:
	if phase!="map" or layout_kind=="node_graph": return []
	if travel!=null: _sync_travel(); return travel.path(position,target)
	return layout.path(position,target,walkable)


func step(target: Vector2i) -> bool:
	if layout_kind=="node_graph": return false
	if travel!=null:
		if phase!="map": return false
		_sync_travel()
		if not travel.step(position,target): return false
		position = target
		if travel.current_node!=current_room: _arrive(travel.current_node)
		return true
	if phase!="map" or (target-position).abs().x+(target-position).abs().y!=1 or not walkable(target) or not layout.can_step(position,target): return false
	position = target
	for id: String in layout.cells[target].rooms:
		if id!=current_room and _room_available(id) and layout.rooms[id].bounds.grow(-.1).has_point(layout.point(target)):
			_arrive(id)
			break
	return true


func enter_room(id: String) -> Dictionary:
	# Headless travel uses exactly the same navigation and threshold transitions as walking.
	if phase!="map" or not graph.rooms.has(id) or not _room_available(id): return _fail("这间庭院暂不可达")
	if layout_kind=="node_graph":
		if not next_rooms().has(id): return _fail("只能沿连线向右前进，不能返回已经过的节点")
		_arrive(id)
		position = layout.rooms[id].stand_cell
		_save_if_enabled()
		return {"ok":true,"phase":phase,"current_room":current_room}
	var path: Array = move_path(layout.rooms[id].stand_cell)
	if path.is_empty(): return _fail("没有通向此房间的实体道路")
	for cell: Vector2i in path.slice(1):
		if not step(cell): break
		if phase!="map": break
	_save_if_enabled()
	return {"ok":current_room==id,"phase":phase,"current_room":current_room}


func _arrive(id: String) -> void:
	var spec: Dictionary = graph.rooms[id]
	if not planned_route.is_empty():
		if planned_route[0]==id: planned_route.pop_front()
		else: planned_route.clear()
	if spec.has("group") and not choices.has(spec.group):
		choices[spec.group] = spec.branch
		for b in graph.groups[spec.group].branches.size():
			if b==spec.branch: continue
			for excluded: String in graph.groups[spec.group].branches[b]: sealed[excluded] = true
	current_room = id
	node = null
	visited_rooms[id] = true
	if travel!=null or layout_kind=="node_graph": _seal_abandoned()
	GameState.node_index = visited_rooms.size()
	if resolved.has(id): return
	GameState.rng.seed = spec.content_seed
	_log("进入"+layout.rooms[id].name)
	match spec.kind:
		"battle","elite","boss": node = battle_node("", true); phase = "encounter"
		"event": _start_event()
		"rest": phase = "rest"
		"shop": _start_shop()
		"treasure":
			var found := ""
			if layout_kind=="node_graph":
				var offers: Array = Relics.roll_choices(GameState.relics,GameState.rng,1)
				if not offers.is_empty(): found = str(offers[0])
			else: found = _grant_treasure_relic()
			if found.is_empty():
				GameState.add_gold(30)
				_log("宝箱：普通遗物已收集完，改为铜钱 +30")
			if layout_kind=="node_graph":
				if not contents.has(current_room): contents[current_room] = {}
				contents[current_room]["treasure"] = {"relic":found, "pending":not found.is_empty()}
				phase = "treasure"
			else: _complete_node()

	_sync_content()
	_sync_travel()


func _restore_travel(state: Dictionary) -> void:
	if layout.compact==null: travel = null; return
	travel = preload("res://src/expedition/garden_forward_travel.gd").new(layout.compact)
	travel.current_node = current_room
	travel.history.assign(state.get("history",visited_rooms.keys()))
	travel.departed = bool(state.get("departed",str(layout.compact.cells.get(position,""))!=current_room))
	travel.enabled = phase=="map" and resolved.has(current_room)
	travel._refresh()


func _sync_travel() -> void:
	if travel==null: return
	var enabled: bool = phase=="map" and resolved.has(current_room)
	if travel.current_node==current_room and travel.enabled==enabled: return
	travel.current_node = current_room; travel.enabled = enabled; travel._refresh()


func _seal_abandoned() -> void:
	# Keep future merges reachable while abandoning only nodes that can no
	# longer be reached along a directed continuation of the chosen route.
	var queue: Array = [current_room]; var reachable := {current_room:true}; var cursor := 0
	while cursor<queue.size():
		var id: String = queue[cursor]; cursor += 1
		for next: String in graph.rooms[id].next:
			if not reachable.has(next): reachable[next] = true; queue.append(next)
	for id: String in graph.rooms:
		if not reachable.has(id) and not visited_rooms.has(id): sealed[id] = true


func plan_choices() -> Array:
	var from: String = planned_route[-1] if not planned_route.is_empty() else current_room
	if not graph.rooms.has(from): return []
	return graph.rooms[from].next.filter(func(id):return not sealed.has(id))


func plan_room(id: String) -> Dictionary:
	if (travel==null and layout_kind!="node_graph") or not graph.rooms.has(id) or phase in ["defeat","victory","generation_error"]: return _fail("此时不能预选路线")
	if planned_route.has(id): planned_route.resize(planned_route.find(id)+1)
	elif plan_choices().has(id): planned_route.append(id)
	elif graph.rooms[current_room].next.has(id) and not sealed.has(id): planned_route.assign([id])
	else: return _fail("请先选择亮框标出的接续节点")
	_save_if_enabled()
	return {"ok":true,"planned_route":planned_route.duplicate()}


func _encounter_pools(room_id: String) -> Dictionary:
	var spec: Dictionary = graph.rooms[room_id]
	if spec.kind == "boss":
		return {"preferred":[EnemyRoster.BOSSES[GameState.act_index]], "available":[EnemyRoster.BOSSES[GameState.act_index]]}
	if layout_kind == "node_graph":
		var stage := clampi(floori(float(layout.rooms[room_id].column)/5),0,2)
		return {"preferred": Expedition.ELITE_STAGES[GameState.act_index][stage] if spec.kind=="elite" else Expedition.NORMAL_STAGES[GameState.act_index][stage],
			"available": EnemyRoster.ELITES[GameState.act_index] if spec.kind=="elite" else EnemyRoster.NORMAL[GameState.act_index]}
	var preferred := Expedition.ELITE if spec.kind=="elite" else "ink_spirit"
	if spec.kind != "elite":
		if room_id=="opening_2" or travel!=null and int(spec.row)==1: preferred = "paper_guard"
		elif room_id!="opening_1" and not (travel!=null and int(spec.row)==0): preferred = Expedition.FOE_ENEMY[int(spec.content_seed)%Expedition.FOE_ENEMY.size()]
	return {"preferred":[preferred], "available":[Expedition.ELITE] if spec.kind=="elite" else Expedition.FOE_ENEMY}


func _select_encounter(room_id: String, preferred: Array, available: Array, commit: bool, key := "enemy_id") -> String:
	var cached: Dictionary = contents.get(room_id, {})
	if cached.has(key): return str(cached[key])
	var history: Array = graph.get("enemy_history", [])
	var id := EnemyRoster.pick_encounter(preferred, available, history, int(graph.rooms[room_id].content_seed))
	if commit:
		cached[key] = id
		contents[room_id] = cached
		history.append(id)
		graph["enemy_history"] = history
	return id


## 旧存档保留已走过房间的原选怪结果，后续遭遇才使用去重规则。
func _restore_encounters() -> void:
	if graph.has("enemy_history"): return
	var history: Array = []
	for room_id: String in visited_rooms:
		if not graph.rooms.has(room_id): continue
		var spec: Dictionary = graph.rooms[room_id]
		if spec.kind not in ["battle", "elite", "boss"]: continue
		var pool: Array = _encounter_pools(room_id).preferred
		var id: String = pool[int(spec.content_seed)%pool.size()] if layout_kind=="node_graph" else pool[0]
		var cached: Dictionary = contents.get(room_id, {})
		cached["enemy_id"] = id
		contents[room_id] = cached
		history.append(id)
	if spawned_battle:
		var pool: Array = EnemyRoster.NORMAL[GameState.act_index] if layout_kind=="node_graph" else Expedition.FOE_ENEMY
		var id: String = pool[int(graph.rooms[current_room].content_seed)%pool.size()]
		var cached: Dictionary = contents.get(current_room, {})
		cached["event_enemy_id"] = id
		contents[current_room] = cached
		history.append(id)
	graph["enemy_history"] = history


func battle_node(room_id := "", commit := false) -> MapNodeData:
	if room_id.is_empty(): room_id = current_room
	var spec: Dictionary = graph.rooms[room_id]
	var result := MapNodeData.new()
	result.type = {"battle":MapNodeData.Type.BATTLE,"elite":MapNodeData.Type.ELITE,"boss":MapNodeData.Type.BOSS}[spec.kind]
	var pool := _encounter_pools(room_id)
	var enemy_id := _select_encounter(room_id, pool.preferred, pool.available, commit)
	var enemy: EnemyData = Database.get_enemy(enemy_id).duplicate(true)
	if layout_kind!="node_graph" and spec.kind!="boss": enemy.max_hp = roundi(enemy.max_hp*(1+.25*(GameState.act_index-1)))
	result.title = layout.rooms[room_id].name
	result.enemies.append(enemy)
	return result


func battle_seed() -> int: return int(graph.rooms[current_room].content_seed)^0xBA771E


func begin_live_battle() -> bool:
	if phase!="encounter": return false
	_save_if_enabled() # A restart restores the untouched encounter, never half a battle.
	phase = "battle"
	return true


func _grant_battle_relic(mode: String) -> void:
	var id := mode
	if mode == "random" or mode.is_empty():
		var choices: Array = Relics.roll_choices(GameState.relics, GameState.rng, 1)
		id = str(choices[0]) if not choices.is_empty() else ""
	if id.is_empty():
		GameState.add_gold(35)
		_log("奇遇：遗物已取尽，改为铜钱 +35")
		return
	if not GameState.add_relic(id):
		GameState.add_gold(35)
		_log("奇遇：遗物未能取得，改为铜钱 +35")
		return
	if Relics.needs_bind(id):
		for inst: CharInstance in GameState.deck:
			if GameState.bind_relic(id, inst.id()):
				break
	Relics.queue_setup(id)
	_log("奇遇：战斗得器「%s」" % Relics.name_of(id))


func finish_live_battle(victory: bool) -> void:
	if phase!="battle": return
	if not victory:
		Achievements.finish_run(false)
		phase = "defeat"
		_save_if_enabled()
		return
	# 事件战斗的遗物奖励替代普通战后三选一。
	if spawned_battle and not spawn_battle_relic.is_empty():
		var relic_reward := spawn_battle_relic
		spawn_battle_relic = ""
		_offer_event_relic(relic_reward, 35)
		_save_if_enabled()
		return
	var kind: String = graph.rooms[current_room].kind
	GameState.add_gold(20 if kind=="elite" else (30 if kind=="boss" else 10))
	if kind == "boss" and GameState.act_index >= 3:
		_finish_final_boss()
		return
	GameState.rng.seed = int(graph.rooms[current_room].content_seed)^0xA11CE
	reward_options = _pick_from_db(1 if kind in ["elite","boss"] else 0,4 if kind=="boss" else 2,3)
	phase = "reward"
	_sync_content()
	if kind=="elite" or kind=="boss" and GameState.act_index<3:
		contents[current_room]["battle_relics"] = Relics.roll_choices(GameState.relics,GameState.rng,2 if kind=="boss" else 1)
		if kind=="boss": GameState.heal(roundi(GameState.player_max_hp*.3))
	_save_if_enabled()


func _finish_final_boss() -> void:
	if phase == "victory": return
	_complete_node()
	reward_options.clear()
	if contents.has(current_room):
		contents[current_room]["reward"] = []
		contents[current_room]["battle_relics"] = []
	phase = "victory"
	Achievements.finish_run(true)
	_save_if_enabled()


func _start_battle(_n: MapNodeData) -> void:
	if phase!="encounter": return
	battle_h = BattleHarness.new()
	battle_h.reset({"seed":battle_seed(),"enemies":node.enemies.map(func(e): return e.id),"persistent_run":true,"hp":GameState.player_hp,"gold":GameState.gold})
	# The adapter's act scaling and live/headless setups must be identical.
	battle_h.battle.enemies[0].max_hp = node.enemies[0].max_hp
	battle_h.battle.enemies[0].hp = node.enemies[0].max_hp
	apply_battle_setup(battle_h.battle)
	phase = "battle"


func _end_battle() -> void:
	var b: BattleState = battle_h.battle
	GameState.player_hp = b.player.hp
	if b.is_victory():
		GameState.add_captured(b.captured_chars)
		GameState.settle_victory_economy()
		Relics.on_battle_won()
	finish_live_battle(b.is_victory())


func apply_battle_setup(_b: BattleState) -> void:
	# Glyphs live in the combat deck; retired inventory layouts grant no bonuses.
	pass



func _apply_reward(t: String, action: Dictionary) -> Dictionary:
	if not contents.get(current_room,{}).get("battle_relics",[]).is_empty(): return _fail("请先选择遗物奖励")
	if t=="skip": GameState.add_gold(Expedition.SKIP_GOLD)
	else:
		var index := int(action.get("index",-1))
		if index<0 or index>=reward_options.size(): return _fail("无效奖励")
		var character: CharacterData = reward_options[index]
		GameState.add_character(character)
	_complete_node()
	return {"ok":true,"phase":phase}


func _complete_node() -> void:
	if GameState.player_hp<=0:
		Achievements.finish_run(false)
		phase = "defeat"
		return
	Achievements.node_completed()
	resolved[current_room] = true
	_sync_content()
	reward_options.clear(); shop_offers.clear(); event_data = {}; pending_glyphs.clear(); pending_event_effect.clear(); pending_event_next = ""; event_node = "start"
	pending_event_relics.clear()
	GameState.clear_event_temp_hp()
	phase = "act_end" if current_room==graph.boss else "map"
	battle_h = null
	spawned_battle = false
	pending_spawn = ""
	pending_spawn_relic = ""
	spawn_battle_relic = ""
	event_board.clear()
	_log("庭院已解决，出口开放。")
	_sync_travel()


func legal_actions() -> Array:
	if phase=="map":
		var actions: Array = next_rooms().map(func(id): return {"type":"enter_room","room":id,"label":LABELS[graph.rooms[id].kind]})
		if travel==null and layout_kind!="node_graph":
			for previous: String in graph.rooms[current_room].previous:
				if resolved.has(previous): actions.append({"type":"enter_room","room":previous,"label":"返回已过庭院"})
		return actions
	if phase=="reward":
		var ids: Array = contents.get(current_room,{}).get("battle_relics",[])
		if not ids.is_empty():
			return range(ids.size()).map(func(i):return {"type":"reward_relic","index":i,"relic":ids[i]})
	if phase=="shop":
		var stock: Array = super.legal_actions()
		if GameState.gold>=shop_refresh_cost(): stock.append({"type":"shop_refresh","price":shop_refresh_cost()})
		return stock
	if phase=="encounter": return [{"type":"interact","label":"开战"}]
	if phase=="act_end": return [{"type":"next_act","label":"完成远征" if GameState.act_index==3 else "进入下一幕"}]
	if phase=="treasure":
		var actions: Array = [{"type":"treasure_ack","label":"收下宝藏"}]
		if contents.get(current_room,{}).get("treasure",{}).get("pending",false): actions.append({"type":"treasure_skip","label":"放弃遗物"})
		return actions
	if phase=="rest": return super.legal_actions()+[{"type":"leave_service","label":"不休整，离开"}]
	return super.legal_actions()


func apply(action: Dictionary) -> Dictionary:
	var type := str(action.get("type",""))
	var result: Dictionary
	if type=="plan_room": return plan_room(str(action.get("room","")))
	if type=="clear_plan": planned_route.clear(); _save_if_enabled(); return {"ok":true}
	if type=="undo_plan":
		if planned_route.is_empty(): return _fail("尚未预选路线")
		planned_route.pop_back(); _save_if_enabled(); return {"ok":true}
	if type=="enter_room": return enter_room(str(action.get("room","")))
	if type=="interact" and phase=="encounter": _start_battle(node); result = {"ok":true,"phase":phase}
	elif type=="next_act" and phase=="act_end":
		if GameState.act_index>=3:
			phase = "victory"
			Achievements.finish_run(true)
		else: _load_act(GameState.act_index+1)
		result = {"ok":true,"phase":phase}
	elif type in ["treasure_ack","treasure_skip"] and phase=="treasure":
		var receipt: Dictionary = contents.get(current_room,{}).get("treasure",{})
		var relic := str(receipt.get("relic",""))
		if type=="treasure_ack" and bool(receipt.get("pending",false)) and not GameState.add_relic(relic):
			return _fail("这件遗物已经拥有或已失效，可放弃领取")
		if type=="treasure_ack" and bool(receipt.get("pending",false)) and Relics.needs_bind(relic):
			for inst: CharInstance in GameState.deck:
				if GameState.bind_relic(relic,inst.id()): break
		if type=="treasure_ack" and bool(receipt.get("pending",false)): Relics.queue_setup(relic)
		receipt["pending"] = false
		_complete_node()
		result = {"ok":true,"phase":phase,"relic":relic if type=="treasure_ack" else ""}
	elif type=="leave_service" and phase=="rest": _complete_node(); result = {"ok":true,"phase":phase}
	elif type=="event_word" and phase=="event_board": result = _resolve_event_board(action.get("path", []))
	elif type=="event_board_leave" and phase=="event_board": result = _leave_event_board()
	elif type=="event_leave" and phase=="event":
		if not bool(current_event().get("allow_leave",true)): return _fail("这场遭遇需要作出选择")
		_complete_node()
		result = {"ok":true,"phase":phase}
	elif type=="reward_relic" and phase=="reward":
		var ids: Array = contents.get(current_room,{}).get("battle_relics",[])
		var index := int(action.get("index",-1))
		if index<0 or index>=ids.size(): return _fail("遗物奖励已领取或选项无效")
		_grant_battle_relic(str(ids[index]))
		contents[current_room]["battle_relics"] = []
		result = {"ok":true,"relic":ids[index]}
	else:
		var valid := legal_actions().any(func(a):
			if a.type!=type: return false
			for key in ["index","kind","glyph"]:
				if a.has(key) and a[key]!=action.get(key): return false
			return true)
		if not valid: return _fail("此时不能执行这个动作")
		result = super.apply(action)
	if phase!="battle": _sync_content(); _save_if_enabled()
	return result


func _apply_rest(t: String, action: Dictionary) -> Dictionary:
	var result: Dictionary = super._apply_rest(t, action)
	if result.ok and phase == "rest_choose" and pending_kind == "upgrade":
		pending_glyphs.clear()
		for inst: CharInstance in GameState.deck:
			if not inst.gilded and not pending_glyphs.has(inst.glyph()): pending_glyphs.append(inst.glyph())
		if pending_glyphs.is_empty():
			phase = "rest"
			pending_kind = ""
			return _fail("所有字都已镀金，请选择其他整备。")
	return result


func _apply_upgrade(ch: CharacterData) -> void:
	for inst in GameState.deck:
		if inst.id()==ch.id and not inst.gilded: GameState.gild_character(inst); return


func observe() -> Dictionary:
	var result := super.observe()
	var kind: String = graph.rooms.get(current_room,{}).get("kind","")
	result.merge({"mode":"courtyard","schema":2,"layout":layout_kind,"generation":layout.site.get("generation",{}).duplicate(true),"seed":seed,"current_room":current_room,"room_kind":kind,"next_rooms":next_rooms(),"resolved":resolved.keys(),"branch_choices":choices.duplicate(),"sealed_rooms":sealed.keys(),"position":[position.x,position.y],"generation_error":generation_error,"grid_step":layout.walk_step,"grid_origin":[layout.grid_origin.x,layout.grid_origin.y],"seen_events":seen_events.duplicate()},true)
	result["pending_reward"] = phase=="reward"
	result["candidate_nodes"] = graph.rooms.size()
	result["forward_only"] = travel!=null or layout_kind=="node_graph"
	result["planned_route"] = planned_route.duplicate()
	result["plan_choices"] = plan_choices() if travel!=null or layout_kind=="node_graph" else []
	result["rooms"] = graph.rooms.values().map(func(r):return {"id":r.id,"kind":r.kind,"next":r.next.duplicate(),"visited":visited_rooms.has(r.id),"sealed":sealed.has(r.id)})
	result["node_type"] = kind
	if phase in ["event", "event_choose", "event_relic"]:
		var current: Dictionary = current_event()
		var options: Array = current.get("options", [])
		result["event"] = {
			"id": event_data.get("id", ""),
			"node": event_node,
			"title": current.get("title", event_data.get("title", "")),
			"body": current.get("body", event_data.get("body", "")),
			"illustration": current.get("illustration", event_data.get("illustration", "")),
			"acts": event_data.get("acts", []).duplicate(),
			"tags": event_data.get("tags", []).duplicate(),
			"options": options.duplicate(true),
			"relic_offers": pending_event_relics.duplicate(),
		}
		if phase == "event_choose":
			result["event"]["pending_removal"] = {
				"remaining": int(pending_event_effect.get("remaining", 0)),
				"glyphs": pending_event_effect.get("glyphs", []).duplicate(),
			}
	return result


func summary() -> Dictionary:
	var result := super.summary()
	result.merge({"mode":"courtyard","current_room":current_room,"visited_rooms":visited_rooms.size(),"branch_choices":choices.duplicate()},true)
	return result


func save_run(path := SAVE_PATH) -> Error:
	if phase in ["battle","generation_error"]: return ERR_BUSY
	_sync_content()
	var data := SAVE.new()
	data.run = {"seed":seed,"act":GameState.act_index,"graph":graph,"current_room":current_room,"resolved":resolved,"visited":visited_rooms,"choices":choices,"sealed":sealed,"contents":contents,"seen_events":seen_events,"event_bags":event_bags,"last_event_id":last_event_id,"event_node":event_node,"pending_event_next":pending_event_next,"event_temp_hp":GameState.event_temp_hp,"position":position,"phase":phase,"pending_glyphs":pending_glyphs,"pending_kind":pending_kind,"pending_index":pending_index,"pending_event_effect":pending_event_effect,"pending_spawn":pending_spawn,"pending_spawn_relic":pending_spawn_relic,"spawned_battle":spawned_battle,"spawn_battle_relic":spawn_battle_relic,"event_board":event_board.duplicate(true),"log":log_lines,"rng":GameState.rng.state}
	data.run["achievements"] = Achievements.export_run()
	if travel!=null: data.run["forward"] = {"history":travel.history.duplicate(),"departed":travel.departed}
	data.run["planned_route"] = planned_route.duplicate()
	data.run["pending_event_relics"] = pending_event_relics.duplicate()
	data.player = {"hp":GameState.player_hp,"max_hp":GameState.player_max_hp,"gold":GameState.gold,"sequence":GameState.battle_sequence,"relics":GameState.relics,"binds":GameState.relic_binds,"counters":GameState.relic_counters,"reduction":GameState.permanent_damage_reduction,"deck":[]}
	data.player["revive_charges"] = GameState.revive_charges
	data.player["first_run_tutorial"] = GameState.first_run_tutorial
	for inst in GameState.deck:
		data.player.deck.append({"uid":inst.uid,"data":inst.data,"gilded":inst.gilded,"upgrade":inst.upgrade_level,"modifiers":inst.modifiers.duplicate(),"pollutions":inst.pollutions.duplicate(),"fusion":inst.fusion.duplicate()})
	return ResourceSaver.save(data,path)


static func has_continuable_save(path := SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path): return false
	var data = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if data == null or not data is Resource or data.get("schema") != 1: return false
	var saved: Variant = data.get("run")
	var player: Variant = data.get("player")
	return saved is Dictionary and player is Dictionary and saved.get("phase", "") not in ["defeat", "victory", "generation_error"] and int(player.get("hp", 0)) > 0


static func restore(path := SAVE_PATH, as_nodes := false):
	if not FileAccess.file_exists(path): return null
	var data = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if data==null or not data is Resource or data.get("schema")!=1: return null
	var run = load("res://src/expedition/room_run_state.gd").new()
	var state: Dictionary = data.run
	run.seed = state.seed; run.graph = state.graph
	run.layout_kind = str(run.graph.get("layout_kind","authored_garden" if run.graph.has("authored_site") else "procedural"))
	if as_nodes:
		run.layout_kind = "node_graph"
		run.graph["layout_kind"] = "node_graph"
		for key in ["compact_plan", "authored_site", "site_plan"]: run.graph.erase(key)
	var moved_layout: bool = GRAPH.compact_layout(run.graph) if run.layout_kind!="node_graph" else false
	run.layout = preload("res://src/expedition/node_route_layout.gd").new() if run.layout_kind=="node_graph" else LAYOUT.new()
	var fitted: bool = run.layout.build(run.graph)
	if not fitted: return null
	GameState.start_new_run("v03")
	GameState.room_run = run; GameState.act_index = state.act
	run.current_room = state.current_room; run.resolved = state.resolved; run.visited_rooms = state.visited
	GameState.node_index = run.visited_rooms.size()
	run.choices = state.choices; run.sealed = state.sealed; run.contents = state.contents
	var plan_from: String = run.current_room
	for planned: String in state.get("planned_route",[]):
		if not run.graph.rooms.has(plan_from) or not run.graph.rooms[plan_from].next.has(planned) or run.sealed.has(planned): break
		run.planned_route.append(planned); plan_from = planned
	run.seen_events = state.get("seen_events", [])
	run.event_bags = state.get("event_bags",{}); run.last_event_id = str(state.get("last_event_id",""))
	run.event_node = state.get("event_node", "start"); run.pending_event_next = state.get("pending_event_next", "")
	run.pending_event_relics = state.get("pending_event_relics", [])
	GameState.event_temp_hp = int(state.get("event_temp_hp", 0))
	run.position = state.position; run.phase = state.phase
	run._restore_travel(state.get("forward",{}))
	# Bridge routing may be refined between development builds. Preserve all room
	# progress; only an invalid walking position returns to that room's safe stand.
	if moved_layout or not run.walkable(run.position): run.position = run.layout.rooms[run.current_room].stand_cell
	run.pending_glyphs = state.pending_glyphs; run.pending_kind = state.pending_kind; run.pending_index = state.pending_index; run.pending_event_effect = state.get("pending_event_effect",{}); run.pending_spawn = str(state.get("pending_spawn","")); run.pending_spawn_relic = str(state.get("pending_spawn_relic","")); run.spawned_battle = bool(state.get("spawned_battle",false)); run.spawn_battle_relic = str(state.get("spawn_battle_relic","")); run.event_board = state.get("event_board",{}); run.log_lines = state.log
	var cached: Dictionary = run.contents.get(run.current_room,{})
	run.reward_options = cached.get("reward",[]); run.shop_offers = cached.get("shop",[]); run.event_data = cached.get("event",{})
	run._restore_encounters()
	if run.phase in ["encounter","reward"] and (run.graph.rooms[run.current_room].kind in ["battle","elite","boss"] or run.spawned_battle): run.node = run.battle_node() if not run.spawned_battle else run._event_battle_node()
	var player: Dictionary = data.player
	GameState.deck.clear()
	for entry in player.deck:
		var inst := CharInstance.new(entry.data)
		inst.uid = entry.uid; CharInstance._next_uid = maxi(CharInstance._next_uid,inst.uid+1)
		inst.gilded = entry.gilded; inst.upgrade_level = entry.upgrade
		inst.modifiers.assign(entry.modifiers); inst.pollutions.assign(entry.pollutions); inst.fusion.assign(entry.fusion)
		GameState.deck.append(inst)
	GameState.player_hp = player.hp; GameState.player_max_hp = player.max_hp; GameState.gold = player.gold
	GameState.battle_sequence = player.sequence; GameState.relics = player.relics; GameState.relic_binds = player.binds; GameState.relic_counters = player.counters
	GameState.revive_charges = int(player.get("revive_charges", 0))
	GameState.first_run_tutorial = bool(player.get("first_run_tutorial", false)) and not Settings.first_run_tutorial_completed
	GameState.permanent_damage_reduction = player.reduction
	GameState.rng.state = state.rng
	_restore_legacy_inventory(state)
	Achievements.resume_run(state.get("achievements", {}))
	# 旧版本没有成就快照；从恢复后的实际操作开始记录，不补算历史。
	var migrated_achievements: bool = state.get("achievements", {}).is_empty() and run.phase not in ["victory", "defeat"]
	if migrated_achievements: Achievements.start_run("courtyard")
	Achievements.register_offers(run.shop_offers)
	if run.layout_kind=="node_graph":
		run._seal_abandoned()
	run.autosave = not bool(GameState.get_meta("courtyard_preview",false))
	if run.phase in ["reward", "act_end"] and run.current_room == run.graph.boss and GameState.act_index >= 3:
		run._finish_final_boss()
	if migrated_achievements and run.autosave and not Achievements.run_id.is_empty(): run.save_run(path)
	return run


static func _restore_legacy_inventory(state: Dictionary) -> void:
	# Old trays and plates stored extra glyphs outside the deck. Import them once;
	# new saves omit these fields, so saving and loading cannot duplicate them.
	var glyphs: Array = []
	if state.get("tray") is Array: glyphs.append_array(state.tray)
	if state.get("plate") is Array:
		for row in state.plate:
			if row is Array: glyphs.append_array(row)
	for glyph in glyphs:
		var character := Database.get_character_by_glyph(str(glyph))
		if character != null: GameState.add_character(character)


func use_node_map() -> void:
	if layout_kind=="node_graph": return
	layout_kind = "node_graph"
	graph["layout_kind"] = "node_graph"
	for key in ["compact_plan", "authored_site", "site_plan"]: graph.erase(key)
	layout = preload("res://src/expedition/node_route_layout.gd").new()
	layout.build(graph)
	travel = null
	position = layout.rooms[current_room].stand_cell
	_seal_abandoned()
	_save_if_enabled()


func _start_shop() -> void:
	super._start_shop()
	var ids: Array = RelicRewardFlow.roll(3,RelicRewardFlow.side_rng("shop"))
	for id in ids: shop_offers.append({"kind":"relic","character":null,"relic":id,"price":Relics.price(id)})
	Achievements.register_offers(shop_offers)


func shop_refresh_cost() -> int:
	return Expedition.SHOP_REFRESH_COST * (int(contents.get(current_room, {}).get("shop_refreshes", 0)) + 1)



func _apply_shop(type: String, action: Dictionary) -> Dictionary:
	if type=="shop_refresh":
		if phase!="shop" or not GameState.spend_gold(shop_refresh_cost()): return _fail("铜钱不足或正在处理服务")
		if not contents.has(current_room): contents[current_room] = {}
		contents[current_room]["shop_refreshes"] = int(contents[current_room].get("shop_refreshes", 0)) + 1
		var services: Array = shop_offers.filter(func(item):return item.kind not in ["buy_char","relic"])
		_start_shop()
		shop_offers = shop_offers.filter(func(item):return item.kind in ["buy_char","relic"])+services
		return {"ok":true,"phase":phase}
	var index := int(action.get("index",-1))
	if type=="shop_buy" and index>=0 and index<shop_offers.size() and shop_offers[index].kind=="relic":
		var item: Dictionary = shop_offers[index]
		if not GameState.spend_gold(int(item.price)): return _fail("铜钱不足")
		_grant_battle_relic(str(item.relic))
		Achievements.bought_offer(item)
		shop_offers.remove_at(index)
		return {"ok":true,"phase":phase,"relic":item.relic}
	return super._apply_shop(type,action)


func _save_if_enabled() -> void:
	if autosave: save_run()

func _fail(reason: String) -> Dictionary: return {"ok":false,"reason":reason}
