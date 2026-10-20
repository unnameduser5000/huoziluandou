extends Control
var passed := 0
var failed := 0
var capture := false
const FOLDER := "user://tutorial-spotlight-qa"
const SLOT := "user://tutorial_regression.save"
var saved_bytes: PackedByteArray
var saved_state: PackedByteArray
var saved_deck: Array


func _ready() -> void:
	Settings.storage_path = "user://tutorial_interaction_test-settings.cfg"
	capture = OS.get_cmdline_user_args().has("--capture")
	get_tree().create_timer(120).timeout.connect(func(): get_tree().quit(2))
	_run.call_deferred()


func frames(count := 4) -> void:
	for i in count: await get_tree().process_frame


func check(value: bool, message: String) -> void:
	if value: passed += 1; print("PASS ", message)
	else: failed += 1; push_error(message)


func state_bytes() -> PackedByteArray:
	var state := {}
	for field in SaveManager.STATE_FIELDS: state[field] = GameState.get(field)
	return var_to_bytes(SaveCodec.new().pack(state))


func touch(point: Vector2, pressed: bool, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = get_viewport().get_final_transform() * point
	event.pressed = pressed
	event.canceled = canceled
	Input.parse_input_event(event)


func tap(control: Control) -> void:
	var center := control.get_global_rect().get_center()
	touch(center, true)
	await frames(1)
	touch(center, false)
	await frames()


func cell(screen: Control, pos: Vector2i) -> Control:
	return screen._board_view.tiles[screen.battle.board.from_xy(pos)]


func drag(screen: Control, path: Array, canceled := false) -> void:
	var a := cell(screen, path[0]).get_global_rect().get_center()
	var b := cell(screen, path[-1]).get_global_rect().get_center()
	touch(a, true)
	await frames(1)
	var event := InputEventScreenDrag.new()
	event.position = get_viewport().get_final_transform() * b
	event.relative = b - a
	Input.parse_input_event(event)
	await frames(1)
	touch(b, false, canceled)
	await frames()


func shot(tag: String) -> void:
	if not capture: return
	await frames(10)
	RenderingServer.force_draw(false)
	DirAccess.make_dir_recursive_absolute(FOLDER)
	check(get_viewport().get_texture().get_image().save_png(FOLDER.path_join(tag + ".png")) == OK, "capture " + tag)


func enter() -> Control:
	Router.goto("res://src/screens/title_screen.gd")
	await frames()
	for button in Router.current._buttons:
		if button.text == "新手教程":
			await tap(button)
			break
	await frames(10)
	check(Router.current_path.ends_with("tutorial_screen.gd"), "title touch entry")
	return Router.current


func untouched(tag: String) -> void:
	SaveManager.flush()
	check(saved_bytes == FileAccess.get_file_as_bytes(SLOT), tag + " save bytes unchanged")
	check(saved_state == state_bytes(), tag + " permanent state and RNG unchanged")
	check(saved_deck == GameState.deck, tag + " permanent card identities unchanged")


func profile(dimensions: Vector2i, dpi: float) -> void:
	get_window().size = dimensions
	# Native desktop mouse emulation clips to the physical monitor. Center an
	# oversized capture window so its action-button centers remain on screen.
	if capture: get_window().position = (DisplayServer.screen_get_size() - dimensions) / 2
	BattleTouchLayout.test_dpi = dpi
	await frames()
	var tag := "%dx%d-%ddpi" % [dimensions.x, dimensions.y, dpi]
	var s := await enter()
	check(s.step == 0 and s.battle.turn == 1, tag + " deterministic lesson start")
	var unit := JourneyStyle.touch_scale(s)
	check(s._exit_btn.size.y >= 48 * unit - 1 and s._confirm_btn.size.y >= 48 * unit - 1, tag + " 48dp touch buttons")
	check(s.get_global_rect().encloses(s._board_view.get_global_rect()) and s.get_global_rect().encloses(s._actions.get_global_rect()), tag + " board and actions within viewport")
	check(not s._board_view.get_global_rect().intersects(s._guide.get_global_rect()), tag + " instructions do not overlap board")
	await shot(tag + "-01-select")
	check(s.battle.enemies[0].enemy_data == Database.get_enemy("ink_spirit") and s._enemy_art.enemy_id == "ink_spirit", tag + " uses the existing enemy resource and animated actor")
	check(s._spotlight.visible and s._spotlight._has_point(s._region(cell(s, Vector2i(1, 1))).get_center()), tag + " mask blocks inactive cells")
	check(not s._spotlight._has_point(s._region(cell(s, Vector2i(0, 0))).get_center()), tag + " spotlight allows the current target")
	# Wrong action cannot consume a practice card or advance.
	await tap(cell(s, Vector2i(1, 1)))
	check(s.step == 0 and s.battle.board.fill_count() == 8 and s._board_view.path.is_empty(), tag + " shaded cells cannot consume cards or advance the lesson")
	s._commit([Vector2i(1, 1)])
	check(not s._feedback.text.is_empty() and s.battle.discard.is_empty(), tag + " wrong submitted path gives recovery without consumption")
	await tap(s._clear_btn)
	await tap(cell(s, Vector2i(0, 0)))
	check(s.step == 0 and s._preview.text.contains("4"), tag + " selection previews before spending")
	await tap(s._confirm_btn)
	check(s.step == 1 and s.battle.enemies[0].hp == s.battle.enemies[0].max_hp - 4 and s.battle.discard.size() == 1, tag + " single glyph uses real damage and consumption")
	await drag(s, s.PATHS[1], true)
	check(s.step == 1 and s._board_view.path.is_empty(), tag + " canceled native drag clears selection")
	await drag(s, s.PATHS[1])
	check(s.step == 1 and s._board_view.path == s.PATHS[1] and Settings.drag_release_play, tag + " tutorial requires confirmation without changing fast input preference")
	check(s._preview.get_global_rect().end.y <= s._guide.get_global_rect().end.y + 1, tag + " selected word preview visible without scrolling")
	check(s._header.get_global_rect().encloses(s._status.get_global_rect()), tag + " player status remains visible in the header")
	await shot(tag + "-02-word")
	await tap(s._confirm_btn)
	check(s.step == 2 and s.battle.enemies[0].hp == s.battle.enemies[0].max_hp - 12, tag + " word uses real eight damage")
	# The real board rejects this pair before gravity, then accepts the same entities.
	var before_gravity := [Vector2i(1, 1), Vector2i(2, 2)]
	check(not s.battle.inspect_play(before_gravity, {"target_index":0}).ok, tag + " separated word is illegal before gravity")
	var strike_uid: int = s.battle.board.get_xy(before_gravity[0]).uid
	var break_uid: int = s.battle.board.get_xy(before_gravity[1]).uid
	await shot(tag + "-03-before-gravity")
	await tap(cell(s, s.PATHS[2][0])); await tap(s._confirm_btn)
	check(s.step == 3 and s.battle.board.get_xy(s.PATHS[3][0]).uid == strike_uid and s.battle.board.get_xy(s.PATHS[3][1]).uid == break_uid, tag + " 重 moves the same two entities into a usable word")
	check(s.battle.enemies[0].hp == s.battle.enemies[0].max_hp - 12 and s.battle.inspect_play(s.PATHS[3], {"target_index":0}).ok, tag + " gravity creates an opportunity without direct damage")
	await shot(tag + "-04-after-gravity")
	await drag(s, s.PATHS[3]); await tap(s._confirm_btn)
	check(s.step == 4 and s.battle.enemies[0].hp == s.battle.enemies[0].max_hp - 20, tag + " player attacks with the word created by gravity")
	# Also cover sequential tapping, rather than drag only.
	await tap(cell(s, s.PATHS[4][0])); await tap(cell(s, s.PATHS[4][1]))
	await tap(s._confirm_btn)
	check(s.step == 5 and s.battle.player.block == 10 and s.battle.player.hp == 30, tag + " defense word grants ten block")
	await shot(tag + "-05-defense")
	await tap(s._end_btn)
	check(s.step == 6 and s.battle.turn == 2 and s.battle.player.hp == 30 and s.battle.player.block == 0, tag + " existing enemy attack is blocked and turn advances")
	check(s.battle.board.fill_count() > 0 and Settings.first_run_tutorial_completed, tag + " next turn refills board and remembers completed onboarding")
	await shot(tag + "-06-complete")
	untouched(tag + " completion")
	await tap(s._replay_btn)
	check(s.step == 0 and s.battle.board.fill_count() == 8 and s.battle.enemies[0].hp == s.battle.enemies[0].max_hp, tag + " replay resets local state")
	await tap(s._exit_btn)
	check(Router.current_path.ends_with("title_screen.gd"), tag + " exit returns title")
	untouched(tag + " exit")


func _run() -> void:
	Settings.reduced_motion = true
	var old_drag := Settings.drag_release_play
	Settings.drag_release_play = true
	SaveManager.activate(SLOT)
	SaveManager.clear_run()
	add_child(preload("res://scenes/main.tscn").instantiate())
	await frames(10)
	GameState.start_new_run()
	GameState.gold = 87
	GameState.player_hp = 39
	GameState.relics = ["slab", "blitz"]
	Router.goto("res://src/screens/map_screen.gd")
	await frames()
	SaveManager.checkpoint()
	SaveManager.flush()
	saved_bytes = FileAccess.get_file_as_bytes(SLOT)
	saved_state = state_bytes()
	saved_deck = GameState.deck.duplicate()
	for p in [[Vector2i(1280, 720), 0], [Vector2i(960, 432), 160], [Vector2i(1280, 720), 320], [Vector2i(2400, 1080), 440], [Vector2i(2532, 1170), 460]]:
		await profile(p[0], p[1])
	var s := await enter()
	check(not get_tree().quit_on_go_back, "practice intercepts Android system back notification")
	s._board_view._on_tile_pressed(Vector2i(0, 0))
	s.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames()
	check(s._board_view.path.is_empty() and s._modal_count == 0, "Android back clears active selection first")
	s.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames()
	check(s._modal_count == 1, "Android system back opens practice pause without quitting")
	s.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await frames()
	check(s._modal_count == 0, "Android back dismisses practice pause")
	PauseMenu.open()
	await frames()
	check(s._modal_count == 1 and not s._board_view._interactable, "global Android back/ESC uses practice pause and locks board")
	var overlay: ChoiceOverlay
	for child in s.get_children():
		if child is ChoiceOverlay: overlay = child
	check(overlay != null and PauseMenu._instance == null, "practice does not expose adventure pause controls")
	overlay._on_choose(0)
	await frames()
	check(s._modal_count == 0 and s._board_view._interactable, "continue unlocks practice")
	s._commit(s.PATHS[0])
	PauseMenu.open()
	await frames()
	for child in s.get_children():
		if child is ChoiceOverlay: child._on_choose(1)
	await frames()
	check(s.step == 0, "pause restart executes after unlocking")
	for i in 6:
		s = await enter()
		for j in mini(i, 5):
			s._commit(s.PATHS[j])
			await frames()
		await frames()
		PauseMenu.open()
		await frames()
		for child in s.get_children():
			if child is ChoiceOverlay: child._on_choose(2)
		await frames()
		check(Router.current_path.ends_with("title_screen.gd"), "can leave step %d using pause menu" % i)
		untouched("skip step %d" % i)
	check(SaveManager.resume_run(), "adventure remains resumable after practice")
	await frames()
	check(get_tree().quit_on_go_back, "leaving practice restores the previous system back policy")
	check(Router.current_path.ends_with("map_screen.gd") and GameState.gold == 87 and GameState.player_hp == 39, "resumes original adventure route and resources")
	Settings.drag_release_play = old_drag
	BattleTouchLayout.test_dpi = 0
	SaveManager.clear_run()
	print("Tutorial interaction: %d passed / %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)
