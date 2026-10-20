extends Control
const RUN = preload("res://src/expedition/room_run_state.gd")
const RESULT := "res://src/screens/run_result_screen.gd"
var checks := 0
var failures := 0
var ended := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count := 6) -> void:
	for i in count: await get_tree().process_frame

func wait_result() -> void:
	var deadline := Time.get_ticks_msec() + 4000
	while Router.current_path != RESULT and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.02).timeout
	await frames()
	check(Router.current_path == RESULT, "defeat routes to settlement")

func _ready() -> void:
	get_window().size = Vector2i(1280,720)
	GameState.set_meta("courtyard_preview", true)
	Settings.reduced_motion = true
	Router.host = self
	EventBus.run_ended.connect(func(won: bool):
		if not won: ended += 1)
	for mode in ["classic", "courtyard", "expedition"]:
		GameState.start_new_run("v03")
		var args := {}
		var run: RefCounted
		var ex: Expedition
		if mode == "courtyard":
			run = RUN.new(); run.reset({"seed":17,"layout":"node_graph"})
			run.enter_room(run.next_rooms()[0]); run.begin_live_battle()
			args = {"room_run":true,"node":run.node}
		elif mode == "expedition":
			ex = Expedition.start(17)
			var cell: int = ex.m.encounter_stages.keys()[0]
			ex.fight = {"kind":"foe","k":cell,"name":"拦路怪"}
			args = {"expedition":true,"node":ex.battle_node()}
		GameState.gold = 42
		GameState.add_relic("strike")
		Router.goto("res://src/screens/battle_screen.gd", args)
		await frames()
		var battle_screen: Control = Router.current
		var before := [GameState.deck_size(), GameState.gold, GameState.battle_sequence, GameState.rng.state]
		var ended_before := ended
		battle_screen.battle.turn = 8
		battle_screen.battle.player.hp = 0
		battle_screen._check_battle_over()
		battle_screen._check_battle_over()
		await wait_result()
		var screen: Control = Router.current
		check(screen.result.turn == 8 and screen.result.gold == 42 and screen.result.deck_count == before[0] and screen.result.relics.size() == 1, mode + " settlement displays final run data")
		var summary: EffectText = screen.find_child("RunSummary", true, false)
		check(summary.get_parsed_text().contains("铜钱：42") and not screen.result.has("score"), mode + " current settlement records copper without the legacy score conversion")
		check(GameState.player_hp == 0 and before == [GameState.deck_size(), GameState.gold, GameState.battle_sequence, GameState.rng.state], mode + " defeat does not restart, heal or award rewards")
		check(ended == ended_before + 1 and Music.current == "defeat", mode + " settles once and plays defeat music")
		if run != null: check(run.phase == "defeat", "courtyard remains terminal")
		if ex != null: check(ex.over and not ex.won, "expedition remains terminal")
		if mode == "courtyard" and OS.get_cmdline_user_args().has("--capture"):
			RenderingServer.force_draw(false)
			get_viewport().get_texture().get_image().save_png("/tmp/huozi-defeat-settlement.png")
		check(screen._return_button.text == "返回主菜单", mode + " primary action returns to main menu")
		Router.goto(RESULT)
		await frames()
		check(ended == ended_before + 1, "reopening result cannot settle twice")
		screen = Router.current
		screen._return_button.pressed.emit()
		await frames()
		check(Router.current_path.ends_with("/title_screen.gd") and GameState.player_hp == 0 and GameState.battle_sequence == before[2] and not GameState.last_run_result.is_empty(), mode + " confirmation returns to menu and preserves the finished result")
	# Finished saves stay inspectable but are not offered as a continuable run.
	var run = RUN.new(); run.reset({"seed":29,"layout":"node_graph"})
	var path := "user://defeat-settlement-test.tres"
	check(run.save_run(path) == OK and RUN.has_continuable_save(path), "active save can continue")
	run.phase = "defeat"; GameState.player_hp = 0
	check(run.save_run(path) == OK and not RUN.has_continuable_save(path), "failed save cannot continue")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Router.goto("res://src/screens/room_map_screen.gd")
	await wait_result()
	check(Router.current.result.turn == 0, "noncombat defeat also enters settlement without fabricated battle turns")
	if OS.get_cmdline_user_args().has("--capture"):
		RenderingServer.force_draw(false)
		get_viewport().get_texture().get_image().save_png("/tmp/huozi-defeat-event.png")
	Router.current.queue_free(); Router.current = null; Router.host = null
	await frames()
	print("[defeat_settlement_test] PASS=%d FAIL=%d" % [checks-failures, failures])
	get_tree().quit(1 if failures else 0)
