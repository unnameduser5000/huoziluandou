extends Control
## Current result screen: immutable snapshots, retired saves and accessible layouts.
const SLOT := "user://settlement_regression.save"
const RESULT := "res://src/screens/run_result_screen.gd"
const FOLDER := "user://run-result-regression"
var passed := 0
var failed := 0
var ended := 0


func _ready() -> void:
	Settings.storage_path = "user://run_settlement_test-settings.cfg"
	GameState.set_meta("courtyard_preview", true)
	Achievements.autosave = false
	get_tree().create_timer(45).timeout.connect(func(): get_tree().quit(2))
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	if value: passed += 1; print("PASS ", message)
	else: failed += 1; push_error(message)


func frames(n := 6) -> void:
	for i in n: await get_tree().process_frame


func wait_result() -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while Router.current_path != RESULT and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.02).timeout
	await frames()
	var arrived := Router.current_path == RESULT
	check(arrived, "real defeat routes to the current unified result screen")
	return arrived


func _run() -> void:
	Settings.reduced_motion = true
	get_window().size = Vector2i(1280, 720)
	SaveManager.activate(SLOT)
	SaveManager.clear_run()
	Router.host = self
	EventBus.run_ended.connect(func(victory):
		if not victory: ended += 1)
	GameState.start_new_run()
	GameState.visited = {"1:1": true, "1:2": true}
	GameState.gold = 12
	GameState.add_relic("strike")
	Router.goto("res://src/screens/map_screen.gd")
	await frames()
	check(SaveManager.checkpoint(), "active classic adventure can be checkpointed")
	SaveManager.flush()
	check(FileAccess.file_exists(SLOT), "an actual adventure save exists before defeat")
	Router.goto("res://src/screens/battle_screen.gd", {"seed": 7})
	await frames()
	var battle_screen: Control = Router.current
	var deck_count := GameState.deck_size()
	var sequence := GameState.battle_sequence
	battle_screen.battle.turn = 8
	battle_screen.battle.enemies[0].hp = 0
	battle_screen.battle.player.hp = 0
	battle_screen._check_battle_over()
	battle_screen._check_battle_over()
	if not await wait_result(): finish(); return
	check(ended == 1, "repeated battle completion emits one loss event")
	check(not SaveManager.has_save() and not FileAccess.file_exists(SLOT), "failure clears the adventure save")
	check(not SaveManager.resume_run(), "a finished adventure cannot be resumed")
	var screen: Control = Router.current
	var snapshot: Dictionary = screen.result.duplicate(true)
	check(not snapshot.victory and snapshot.mode == "经典冒险" and snapshot.turn == 8, "snapshot records the actual mode, outcome and final turn")
	check(snapshot.gold == 12 and snapshot.deck_count == deck_count and snapshot.relics.size() == 1, "snapshot preserves copper, deck and relics without score conversion")
	check(not snapshot.has("total") and not snapshot.has("rows"), "current results do not require the removed score table")
	var summary: EffectText = screen.find_child("RunSummary", true, false)
	check(summary.get_parsed_text().contains("铜钱：12") and screen._return_button.text == "返回主菜单", "current summary and return action are shown")
	# Reopening must use the captured result rather than sampling mutable game state.
	GameState.gold = 99
	Router.goto(RESULT)
	await frames()
	check(Router.current.result == snapshot and GameState.last_run_result == snapshot and ended == 1, "reopening preserves the immutable snapshot without settling again")
	GameState.gold = 12
	Router.current._return_button.pressed.emit()
	await frames()
	check(Router.current_path.ends_with("/title_screen.gd"), "return action opens the main menu")
	check(GameState.player_hp == 0 and GameState.gold == 12 and GameState.deck_size() == deck_count and GameState.battle_sequence == sequence, "returning does not restart, heal or change the finished adventure")
	check(GameState.last_run_result == snapshot and not SaveManager.has_save(), "returning retains the result without reviving its save")
	var ex := Expedition.start(77)
	ex.taken = {12: true, 14: true}
	ex.amb_done = {0: true}
	ex.boss_down = true
	ex.push_panel({"kind": "act_end"})
	ex.next_act()
	check(ex.act == 2 and GameState.visited.size() == 3, "expedition archives unique completed locations across acts")
	var packed := SaveCodec.new().pack({"visited": GameState.visited})
	check(SaveCodec.new().unpack(packed).visited == GameState.visited, "archived expedition progress remains save compatible")
	GameState.gold = 19
	Router.goto("res://src/screens/expedition_map_screen.gd")
	await frames()
	check(SaveManager.checkpoint(), "active expedition can be checkpointed")
	SaveManager.flush()
	var cell: int = ex.m.encounter_stages.keys()[0]
	ex.fight = {"kind": "foe", "k": cell, "name": "结算测试敌人"}
	Router.goto("res://src/screens/battle_screen.gd", {"node": ex.battle_node(), "expedition": true, "seed": 7})
	await frames()
	battle_screen = Router.current
	battle_screen.battle.turn = 4
	battle_screen.battle.player.hp = 0
	battle_screen.battle.enemies[0].hp = 0
	battle_screen._check_battle_over()
	if not await wait_result(): finish(); return
	check(ex.over and not ex.won and ex.fight.is_empty(), "real expedition defeat retires its encounter")
	screen = Router.current
	snapshot = screen.result.duplicate(true)
	check(snapshot.mode == "墨途远征" and snapshot.act == 2 and snapshot.turn == 4 and snapshot.gold == 19, "expedition result preserves its final act, turn and copper")
	check(ended == 2 and not SaveManager.has_save() and not FileAccess.file_exists(SLOT), "expedition settles once and retires its save")
	for profile in [[Vector2i(960,432),160], [Vector2i(1280,720),0], [Vector2i(1280,720),320], [Vector2i(1920,1080),0], [Vector2i(2400,1080),440], [Vector2i(2532,1170),460], [Vector2i(3440,1440),0]]:
		await _profile(profile[0], profile[1], snapshot)
	BattleTouchLayout.test_dpi = 0
	# The current screen has no score reveal or skip-animation controls.
	Settings.reduced_motion = false
	Router.goto(RESULT)
	await frames()
	check(Router.current.result == snapshot and not Router.current._return_button.disabled, "normal motion also shows the captured result with an available return action")
	Router.current._return_button.pressed.emit()
	await frames()
	check(Router.current_path.ends_with("/title_screen.gd") and GameState.expedition == null and GameState.room_run == null, "confirming results releases the finished run and returns to menu")
	check(GameState.player_hp == 0 and GameState.last_run_result == snapshot and ended == 2, "confirmation preserves the outcome without starting or settling another run")
	finish()


func finish() -> void:
	BattleTouchLayout.test_dpi = 0
	SaveManager.clear_run()
	SaveManager.enabled = false
	print("[run_settlement_test] PASS=%d FAIL=%d" % [passed, failed])
	get_tree().quit(1 if failed else 0)


func _profile(dimensions: Vector2i, dpi: float, snapshot: Dictionary) -> void:
	get_window().size = dimensions
	BattleTouchLayout.test_dpi = dpi
	await frames()
	Router.goto(RESULT)
	await frames(12)
	var screen: Control = Router.current
	var tag := "%dx%d-%ddpi" % [dimensions.x, dimensions.y, dpi]
	check(screen.result == snapshot and ended == 2, tag + " rebuilding layout cannot change or repeat settlement")
	check(screen.content.get_global_rect().encloses(screen._return_button.get_global_rect()), tag + " return action remains inside the content area")
	var physical_scale := float(dimensions.y) / screen.get_viewport_rect().size.y
	var target_height := 48 * maxf(1, dpi / 160.0)
	check(screen._return_button.size.y * physical_scale >= target_height - 1, tag + " return action retains its physical touch height")
	var scrolls: Array = screen.content.find_children("*", "ScrollContainer", true, false)
	check(scrolls.size() == 1, tag + " result details remain in one scrollable area")
	if scrolls.size() == 1:
		var scroll: ScrollContainer = scrolls[0]
		check(screen.content.get_global_rect().encloses(scroll.get_global_rect()) and not scroll.get_h_scroll_bar().visible, tag + " details stay within the viewport without horizontal overflow")
	if OS.get_cmdline_user_args().has("--capture"):
		RenderingServer.force_draw(false)
		DirAccess.make_dir_recursive_absolute(FOLDER)
		check(get_viewport().get_texture().get_image().save_png(FOLDER.path_join(tag + ".png")) == OK, tag + " screenshot saved")
