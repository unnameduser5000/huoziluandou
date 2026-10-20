extends Control

const RUN = preload("res://src/expedition/room_run_state.gd")
const SLOT := "user://first_run_tutorial_test-run.tres"
var passed := 0
var failed := 0
var _settings_completed := false


func _ready() -> void:
	Settings.storage_path = "user://first_run_tutorial_test-settings.cfg"
	_run.call_deferred()


func _check(value: bool, label: String) -> void:
	if value:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		push_error(label)


func _frames(count := 4) -> void:
	for i in count:
		await get_tree().process_frame


func _run() -> void:
	_settings_completed = Settings.first_run_tutorial_completed
	Settings.reduced_motion = true
	Settings.first_run_tutorial_completed = false
	GameState.set_meta("courtyard_preview", true)
	SaveManager.enabled = false
	add_child(preload("res://scenes/main.tscn").instantiate())
	await _frames(8)
	var title: Control = Router.current
	_check(title._buttons.any(func(button): return button.text == "新手教程"), "title exposes replayable tutorial entry")
	title._on_start()
	title._entry_timer.stop()
	title._finish_start()
	await _frames(8)
	_check(Router.current_path.ends_with("tutorial_screen.gd") and Router.current.params.get("start_adventure", false), "first new adventure opens the full guided practice")
	Router.current._leave()
	await _frames(8)
	_check(Router.current_path.ends_with("room_map_screen.gd") and Settings.first_run_tutorial_completed and not GameState.first_run_tutorial, "skip starts the adventure without repeating the inline tutorial")
	Settings.first_run_tutorial_completed = false
	RUN.start(4361)
	Router.goto(RUN.MAP_SCREEN)
	await _frames(8)
	_check(GameState.room_run.save_run(SLOT) == OK, "pending tutorial can be saved before the first battle")
	GameState.first_run_tutorial = false
	var run = RUN.restore(SLOT, true)
	_check(run != null and GameState.first_run_tutorial, "continuing a new adventure preserves its pending tutorial")
	Router.goto(RUN.MAP_SCREEN)
	await _frames(8)
	var map: Control = Router.current
	map._select_node(run.next_rooms()[0])
	map._confirm_selected()
	await _frames(8)
	var screen: Control = Router.current
	_check(screen._room_run and screen._first_run_tutorial and screen._tutorial_step == 0, "first room-map battle enables inline tutorial without injected flags")
	_check(screen._bubble._effect_text.contains("第一局引导"), "first battle instruction uses combat hint bubble")
	screen._tutorial_step = 1
	var checkpoint: Dictionary = screen.save_checkpoint()
	_check(checkpoint.screen.get("first_run_tutorial", false) and checkpoint.screen.get("tutorial_step", -1) == 1, "tutorial stage is included in battle checkpoint")
	Router.goto("res://src/screens/battle_screen.gd", {"room_run": true, "node": screen.node, "_saved_screen": checkpoint.screen})
	await _frames(8)
	screen = Router.current
	_check(screen._first_run_tutorial and screen._tutorial_step == 1, "resuming battle restores the active tutorial step")
	var pause := PauseOverlay.new()
	add_child(pause)
	await _frames(2)
	var has_skip := false
	for button in pause._buttons:
		if button.text == "跳过新手引导":
			has_skip = true
	pause.queue_free()
	_check(has_skip, "pause menu exposes skip while first-run tutorial is active")
	await screen._on_end_turn()
	_check(not screen._first_run_tutorial and not GameState.first_run_tutorial, "ending first real turn completes inline tutorial")
	_check(Settings.first_run_tutorial_completed, "completion is remembered for future adventures")
	run = RUN.restore(SLOT, true)
	_check(run != null and not GameState.first_run_tutorial, "an older pending save cannot replay a completed tutorial")
	run = RUN.start(4362)
	_check(not GameState.first_run_tutorial, "later adventures do not repeat completed onboarding")
	GameState.room_run = null
	Router.goto("res://src/screens/battle_screen.gd", {"seed": 4362, "first_run_tutorial": true})
	await _frames(8)
	screen = Router.current
	screen.skip_first_run_tutorial()
	_check(not screen._first_run_tutorial and not GameState.first_run_tutorial, "skip action closes tutorial state")
	_check(not screen.save_checkpoint().screen.get("first_run_tutorial", true), "skip state is saved with battle")
	Settings.first_run_tutorial_completed = false
	Router.goto("res://src/screens/title_screen.gd")
	await _frames(8)
	title = Router.current
	title._on_start(); title._entry_timer.stop(); title._finish_start()
	await _frames(8)
	screen = Router.current
	for path in screen.PATHS: screen._commit(path)
	screen._end_turn()
	_check(screen.step == screen.COMPLETE_STEP and Settings.first_run_tutorial_completed, "automatic tutorial can be completed through every real lesson action")
	screen._leave()
	await _frames(8)
	_check(Router.current_path.ends_with("room_map_screen.gd") and not GameState.first_run_tutorial, "completion begins the new adventure without another tutorial")
	Router.goto("res://src/screens/title_screen.gd")
	await _frames(8)
	title = Router.current
	title._on_start(); title._entry_timer.stop(); title._finish_start()
	await _frames(8)
	_check(Router.current_path.ends_with("room_map_screen.gd"), "future title starts bypass the completed practice")
	DirAccess.remove_absolute(SLOT)
	Settings.first_run_tutorial_completed = _settings_completed
	Settings._save()
	SaveManager.enabled = false
	print("First run tutorial: %d passed / %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)
