extends Node
const PLAN = preload("res://src/expedition/node_route_plan.gd")
const RUN = preload("res://src/expedition/room_run_state.gd")
var checks := 0
var failed := 0


func _ready() -> void:
	GameState.set_meta("courtyard_preview",true)
	SaveManager.enabled = false
	Settings.reduced_motion = true
	for seed_value in 40:
		var graph: Dictionary = PLAN.generate(seed_value,1)
		_ok(graph.rooms.size()>=PLAN.MIN_NODES and graph.rooms.size()<=PLAN.MAX_NODES,"variable candidate count, seed %d" % seed_value)
		var reached := {"start":true}
		var all_forward := true
		var incoming := true
		for id: String in graph.rooms:
			if id!="start" and graph.rooms[id].previous.is_empty(): incoming = false
			if id!="boss" and graph.rooms[id].next.is_empty(): incoming = false
		for column in range(-1,16):
			for id: String in graph.rooms:
				var spec: Dictionary = graph.rooms[id]
				if spec.row!=column: continue
				for target: String in spec.next:
					all_forward = all_forward and graph.rooms[target].row==spec.row+1
					if reached.has(id): reached[target] = true
		_ok(all_forward and incoming and reached.size()==graph.rooms.size(),"every candidate lies on a forward route")
		_ok(graph.rooms.values().all(func(spec): return spec.kind in ["start","boss","battle","elite","event","rest","shop","treasure"]),"every route uses playable encounter types")
		var crosses := false
		for edge: Dictionary in graph.edges:
			if PLAN._crosses(graph,edge.from,edge.to): crosses = true
		_ok(not crosses,"unambiguous non-crossing connections")
	_ok(PLAN.generate(29,1)==PLAN.generate(29,1) and PLAN.generate(29,1)!=PLAN.generate(30,1),"repeatable and varied seeds")
	var run = RUN.start(29)
	_ok(run.layout_kind=="node_graph" and run.travel==null,"new run skips all courtyard construction")
	var first: String = run.next_rooms()[0]
	var other: String = run.next_rooms()[1]
	var rng_before: int = GameState.rng.state
	run.plan_room(first)
	run.plan_room(run.plan_choices()[0])
	_ok(run.planned_route.size()==2 and GameState.rng.state==rng_before and run.current_room=="start","planning is read-only for gameplay and RNG")
	_ok(run.enter_room(first).ok and run.phase=="encounter","next node enters encounter")
	_ok(not run.enter_room(other).ok and not run.enter_room("start").ok,"cannot take a sibling or walk backwards")
	var enemy: EnemyData = run.node.enemies[0]
	_ok(EnemyRoster.NORMAL[1].has(enemy.id) and enemy.max_hp==Database.get_enemy(enemy.id).max_hp,"synced roster and Excel HP used")
	run.begin_live_battle(); run.finish_live_battle(true)
	var gold_before := GameState.gold
	run.apply({"type":"skip"})
	_ok(GameState.gold-gold_before==16 and run.phase=="map","skip settlement is 16 gold")
	_ok(not run.apply({"type":"skip"}).ok,"reward cannot be claimed twice")
	_ok(not run.legal_actions().any(func(a):return a.get("room","")=="start"),"headless actions also prohibit backtracking")
	# Persist pending service/reward state without rerolling or assembling a world.
	var shop: String = run.graph.rooms.keys().filter(func(id):return run.graph.rooms[id].kind=="shop")[0]
	run.current_room = shop; run._start_shop(); run._sync_content()
	GameState.gold = 200
	var services: Array = run.shop_offers.filter(func(o):return o.kind not in ["buy_char","relic"])
	_ok(run.apply({"type":"shop_refresh"}).ok and GameState.gold==195,"saved shop refresh charges 5")
	_ok(run.shop_offers.filter(func(o):return o.kind not in ["buy_char","relic"])==services,"shop refresh preserves remaining services")
	var saved_stock: Array = run.shop_offers.duplicate(true)
	var saved_rng: int = GameState.rng.state
	_ok(run.save_run("user://node-route-test.tres")==OK,"pending stock saves")
	var restored = RUN.restore("user://node-route-test.tres",true)
	_ok(restored!=null and restored.phase=="shop" and restored.layout_kind=="node_graph" and restored.travel==null,"node save restores without 3D")
	_ok(restored.shop_offers.map(func(o):return [o.kind,o.price,o.get("relic","")])==saved_stock.map(func(o):return [o.kind,o.price,o.get("relic","")]) and GameState.rng.state==saved_rng,"stock and RNG survive reload")
	var elite: String = restored.graph.rooms.keys().filter(func(id):return restored.graph.rooms[id].kind=="elite")[0]
	restored.current_room = elite; restored.phase = "encounter"; restored.node = restored.battle_node()
	restored.begin_live_battle(); restored.finish_live_battle(true)
	var relics: Array = restored.contents[elite].get("battle_relics",[])
	_ok(relics.size()==1 and restored.legal_actions()[0].type=="reward_relic","elite relic precedes glyph selection")
	_ok(not restored.apply({"type":"skip"}).ok,"cannot bypass pending relic")
	_ok(restored.apply({"type":"reward_relic","index":0}).ok and GameState.has_relic(relics[0]),"elite relic granted once")
	_ok(not restored.apply({"type":"reward_relic","index":0}).ok,"relic cannot be claimed twice")
	restored._load_act(2)
	restored.current_room = restored.graph.boss; restored.phase = "encounter"; restored.node = restored.battle_node()
	GameState.player_hp = 10
	restored.begin_live_battle(); restored.finish_live_battle(true)
	_ok(restored.contents.boss.battle_relics.size()==2 and GameState.player_hp==28,"act boss heals 30 percent and offers two relics")
	var boss_options: Array = restored.contents.boss.battle_relics.duplicate()
	restored.save_run("user://node-route-boss-test.tres")
	restored = RUN.restore("user://node-route-boss-test.tres",true)
	_ok(restored.contents.boss.battle_relics==boss_options and GameState.player_hp==28,"boss choices and healing are not rerolled on reload")
	restored.apply({"type":"reward_relic","index":0}); restored.apply({"type":"skip"})
	_ok(restored.phase=="act_end" and restored.apply({"type":"next_act"}).ok and GameState.act_index==3,"boss settlement advances to third act")
	# A legacy room save retains its pending reward while changing presentation.
	var legacy = RUN.new(); legacy.reset({"seed":17}); legacy.autosave = false
	legacy.enter_room("opening_1"); legacy.begin_live_battle(); legacy.finish_live_battle(true)
	var legacy_offers: Array = legacy.reward_options.map(func(cd):return cd.id)
	legacy.save_run("user://node-route-legacy-test.tres")
	var migrated = RUN.restore("user://node-route-legacy-test.tres",true)
	_ok(migrated!=null and migrated.phase=="reward" and migrated.current_room==legacy.current_room and migrated.layout_kind=="node_graph","legacy pending reward migrates to 2D")
	_ok(migrated.reward_options.map(func(cd):return cd.id)==legacy_offers and migrated.graph.edges==legacy.graph.edges,"legacy offers and connections are preserved")
	# Real UI loads the same run and never creates a 3D viewport.
	GameState.room_run = RUN.start(29)
	var host := Control.new(); host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(host); Router.host = host
	Router.goto(RUN.MAP_SCREEN)
	await get_tree().process_frame
	await get_tree().process_frame
	var screen: Control = Router.current
	_ok(screen!=null and screen.map_view.points.size()==GameState.room_run.graph.rooms.size(),"live map displays all candidates")
	_ok(screen.find_children("*","SubViewport",true,false).is_empty(),"map has no 3D render targets")
	var state: int = GameState.rng.state
	screen._toggle_planning(); screen._select_node(GameState.room_run.next_rooms()[0]); screen._toggle_planning()
	_ok(GameState.rng.state==state and GameState.room_run.current_room=="start","UI preview does not enter a node")
	# 规划模式：从最左一格格点，红圈逐步描出，非候选压暗
	var live = GameState.room_run
	screen._clear_plan(); screen._toggle_planning()
	_ok(screen.map_view.planning and screen._planner_button.text=="完成预选","planner toggles on")
	var far := ""
	for id: String in live.graph.rooms:
		if id!=live.current_room and not live.next_rooms().has(id): far = id; break
	screen._select_node(far)
	_ok(live.planned_route.is_empty(),"planner rejects a node that skips ahead")
	_ok(not screen.map_view.plan_lit(far) and screen.map_view.plan_lit(live.next_rooms()[0]),"non-candidates are dimmed, next stops lit")
	var step1: String = live.plan_choices()[0]
	screen._select_node(step1)
	var step2: String = live.plan_choices()[0]
	screen._select_node(step2)
	_ok(live.planned_route==[step1,step2] and live.current_room=="start","clicks chain left to right without entering")
	_ok(screen.map_view.plan_end()==step2 and screen.map_view.circle_progress(step2)<1.0,"new red circle starts drawing at the plan end")
	await get_tree().create_timer(.5).timeout
	_ok(screen.map_view.circle_progress(step1)==1.0 and screen.map_view.circle_progress(step2)==1.0,"red circles finish drawing")
	_ok(live.graph.rooms[step2].next.has(live.plan_choices()[0]),"candidates follow the plan end")
	screen._select_node(step2)
	_ok(live.planned_route==[step1],"clicking the last planned stop undoes one step")
	screen._select_node(live.current_room)
	_ok(live.planned_route.is_empty(),"clicking the current stop clears the plan")
	screen._toggle_planning()
	_ok(not screen.map_view.planning and screen._planner_button.text=="预选模式","planner toggles off")
	print("[node_route_test] PASS=%d FAIL=%d TOTAL=%d" % [checks-failed,failed,checks])
	Music.stop()
	await get_tree().create_timer(.05).timeout
	get_tree().quit(1 if failed else 0)


func _ok(value: bool, message: String) -> void:
	checks += 1
	if not value: failed += 1; push_error("[node_route_test] "+message)
