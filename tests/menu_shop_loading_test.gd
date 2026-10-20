extends Control
## Production start -> map -> pause return, plus first/repeated shop entry timings.
const TITLE := "res://src/screens/title_screen.gd"
const SHOP := "res://src/screens/shop_screen.gd"
const RUN := preload("res://src/expedition/room_run_state.gd")
var failures := 0
var checks := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if ok: print("PASS ", message)
	else:
		failures += 1
		push_error(message)


func frames(count := 8) -> void:
	for i in count: await get_tree().process_frame


func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--capture"): return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://shots")
	get_viewport().get_texture().get_image().save_png("res://shots/" + label + ".png")


func _ready() -> void:
	Settings.storage_path = "user://menu-shop-loading-settings.cfg"
	# This suite starts an adventure directly; first-run routing is covered separately.
	Settings.first_run_tutorial_completed = true
	Settings.reduced_motion = true
	GameState.set_meta("courtyard_preview", true)
	SaveManager.activate("user://menu-shop-loading.save")
	SaveManager.clear_run()
	_run.call_deferred()


func _run() -> void:
	var main: Control = preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(20)
	var title: Control = Router.current
	for round_index in 2:
		Settings.reduced_motion = round_index == 0
		title._on_start()
		var deadline := Time.get_ticks_msec() + 3500
		while Router.current == title and Time.get_ticks_msec() < deadline: await frames(1)
		check(Router.current_path.ends_with("/room_map_screen.gd"), "start opens the production adventure map")
		PauseMenu.open()
		await frames()
		var pause: PauseOverlay = PauseMenu._instance
		if not is_instance_valid(pause):
			check(false, "map opens the pause menu")
			break
		for button in pause._buttons:
			if button.text.contains("返回主界面"):
				button.pressed.emit()
				break
		await frames()
		check(Router.current == title and Router.current_path == TITLE, "return reuses the production title")
		check(title._wordmark.is_visible_in_tree() and title._ornament.is_visible_in_tree() and title._utilities.is_visible_in_tree(), "return restores logo, menu ornament and utility entries")
		check(title._menu.modulate.a == 1.0 and title._veil.color.a == 0.0 and title._can_interact(), "return restores menu opacity and interaction")
		check(title._buttons[0].has_focus(), "return restores keyboard focus")
		check(not title._expedition and title._entry_timer.is_stopped(), "return clears entry mode and timer")
		await shot("menu-return-%d" % round_index)
	Settings.reduced_motion = true
	for round_index in 3:
		GameState.start_new_run()
		GameState.rng.seed = 20261020 + round_index
		GameState.gold = 200
		var route_params := {}
		if round_index == 2:
			var run := RUN.new()
			run.reset({"seed": 129, "layout": "node_graph"})
			for id in run.graph.rooms:
				if run.graph.rooms[id].kind == "shop": run.current_room = id; break
			run.contents[run.current_room] = {}
			run._start_shop()
			GameState.gold = 200
			route_params = {"room_run": true}
		var started := Time.get_ticks_usec()
		Router.goto(SHOP, route_params)
		var route_ms := (Time.get_ticks_usec() - started) / 1000.0
		var first_draw_ms := -1.0
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			first_draw_ms = (Time.get_ticks_usec() - started) / 1000.0
		print("SHOP_ENTRY ", JSON.stringify({"round": round_index, "route_cpu_ms": route_ms, "first_draw_ms": first_draw_ms}))
		await frames(15)
		var shop: Control = Router.current
		check(shop._cards.size() == shop._offers.size() and shop._offers.size() == 11, "shop enters with all eleven wares ready")
		check(shop._showcase.stage.objects.size() == shop._offers.size(), "shop has a model for every offer")
		check(shop._cards.all(func(card): return card.size.x > 0 and card.size.y > 0), "all wares have laid out hit targets")
		await shot("shop-entry-%d" % round_index)
		Router.goto(TITLE)
		await frames()
	# A suspended legacy start must not leak into the next normal start.
	title._expedition = true
	title._on_start()
	Router.goto("res://src/screens/glyph_graph_screen.gd")
	Router.goto(TITLE)
	await frames()
	check(not title._expedition and not title._starting and title._entry_timer.is_stopped(), "interrupted entry resets its mode and stops the timer")
	check(title._wordmark.is_visible_in_tree() and title._utilities.is_visible_in_tree(), "interrupted entry restores the complete title")
	SaveManager.clear_run()
	SaveManager.enabled = false
	main.queue_free()
	await frames()
	print("[menu_shop_loading_test] PASS=%d FAIL=%d" % [checks - failures, failures])
	get_tree().quit(1 if failures else 0)
