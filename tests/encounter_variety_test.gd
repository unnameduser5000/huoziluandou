extends Node
const RUN = preload("res://src/expedition/room_run_state.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	GameState.set_meta("courtyard_preview", true)
	for seed_value in 30:
		for act in [1, 2, 3]:
			var run = RUN.new()
			run.reset({"seed":seed_value,"layout":"node_graph"})
			run._load_act(act)
			var history: Array = []
			while run.current_room != run.graph.boss:
				var next: Array = run.next_rooms()
				var combat: Array = next.filter(func(id): return run.graph.rooms[id].kind in ["battle", "elite", "boss"])
				var id: String = combat[0] if not combat.is_empty() else next[0]
				var kind: String = run.graph.rooms[id].kind
				var before: int = GameState.rng.state
				var preview := ""
				if kind in ["battle", "elite", "boss"]:
					preview = run.battle_node(id).enemies[0].id
					check(run.battle_node(id).enemies[0].id == preview and run.graph.enemy_history == history and GameState.rng.state == before, "preview is stable and read only")
				check(run.enter_room(id).ok, "forward route enters successfully")
				if not preview.is_empty():
					var enemy_id: String = run.node.enemies[0].id
					var available: Array = EnemyRoster.NORMAL[act] if kind == "battle" else (EnemyRoster.ELITES[act] if kind == "elite" else [EnemyRoster.BOSSES[act]])
					check(enemy_id == preview and available.has(enemy_id), "actual encounter matches preview and act/type pool")
					if available.any(func(foe): return not history.has(foe)):
						check(not history.has(enemy_id), "unseen monsters are exhausted before any repeats")
					elif available.size() > 1:
						check(enemy_id != history.back(), "exhausted pool avoids consecutive repeats")
					history.append(enemy_id)
					check(run.graph.enemy_history == history and run.battle_node().enemies[0].id == enemy_id, "encounter is recorded once and remains cached")
				run.resolved[id] = true
				run.phase = "map"
			check(run.graph.enemy_history.size() == history.size(), "noncombat rooms do not consume monsters")
	# Save the selected encounter and verify both current and future choices.
	var run = RUN.new()
	run.reset({"seed":17,"layout":"node_graph"})
	run.enter_room(run.next_rooms()[0])
	var enemy: String = run.node.enemies[0].id
	var history: Array = run.graph.enemy_history.duplicate()
	var future := ""
	for rid in run.graph.rooms[run.current_room].next:
		if ["battle", "elite", "boss"].has(str(run.graph.rooms[rid].kind)):
			future = str(rid); break
	check(not future.is_empty(), "后续房间里有战斗节点")
	var future_enemy: String = run.battle_node(future).enemies[0].id
	var path := "user://encounter-variety-test.tres"
	check(run.save_run(path) == OK, "pending encounter saves")
	var restored = RUN.restore(path)
	check(restored != null and restored.node.enemies[0].id == enemy and restored.graph.enemy_history == history, "reload preserves current enemy and encounter history")
	check(restored.battle_node(future).enemies[0].id == future_enemy, "reload preserves future preview")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# Old saves reconstruct the original selection instead of rerolling it.
	run.graph.erase("enemy_history")
	run.contents[run.current_room].erase("enemy_id")
	var pool: Array = run._encounter_pools(run.current_room).preferred
	var old_id: String = pool[int(run.graph.rooms[run.current_room].content_seed) % pool.size()]
	run._restore_encounters()
	check(run.battle_node().enemies[0].id == old_id and run.graph.enemy_history == [old_id], "old save migrates original enemy and history")
	run._load_act(2)
	check(run.graph.enemy_history.is_empty(), "next floor resets encounter history")
	# Event ambushes share normal encounter history and keep a separate cached key.
	var event: String = run.graph.rooms.keys().filter(func(id): return run.graph.rooms[id].kind == "event")[0]
	run.current_room = event
	var ambush: String = run._event_battle_node(true).enemies[0].id
	check(run._event_battle_node(true).enemies[0].id == ambush and run.graph.enemy_history == [ambush], "event ambush commits exactly once")
	# The legacy expedition follows the same per-floor rule, without changing boss stats.
	var ex := Expedition.start(21)
	for act in [1, 2, 3]:
		ex.load_act(act)
		var seen: Array = []
		for cell in ex.m.encounter_stages:
			var kind := "elite" if ex.m.node.get(cell, {}).get("t", "") == "险" else "foe"
			var available: Array = EnemyRoster.ELITES[act] if kind == "elite" else EnemyRoster.NORMAL[act]
			var preview := ex.encounter_enemy(kind, cell).id
			ex.fight = {"kind":kind,"k":cell}
			var actual: String = ex.battle_node().enemies[0].id
			check(actual == preview, "legacy expedition preview matches actual battle")
			if available.any(func(id): return not seen.has(id)): check(not seen.has(actual), "legacy expedition prioritizes unseen monsters")
			seen.append(actual)
			var count: int = ex.m.enemy_history.size()
			check(ex.battle_node().enemies[0].id == actual and ex.m.enemy_history.size() == count, "legacy revisit does not record or reroll twice")
		check(ex.encounter_enemy("boss", ex.boss).id == EnemyRoster.BOSSES[act], "boss assignment remains unchanged")
	print("[encounter_variety_test] PASS=%d FAIL=%d" % [checks-failures, failures])
	get_tree().quit(1 if failures else 0)
