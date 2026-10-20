extends Control
const OUTPUT := "user://tutorial-spotlight-qa"
var passed := 0
var failed := 0
var capture := false


func _ready() -> void:
	Settings.storage_path = "user://tutorial_spotlight_test-settings.cfg"
	GameState.set_meta("courtyard_preview", true)
	capture = OS.get_cmdline_user_args().has("--capture")
	if capture: DirAccess.make_dir_recursive_absolute(OUTPUT)
	get_tree().create_timer(90).timeout.connect(func(): get_tree().quit(2))
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	if ok: passed += 1; print("PASS ", label)
	else: failed += 1; push_error(label)


func frames(count := 6) -> void:
	for i in count: await get_tree().process_frame


func settle(screen: Control) -> void:
	while screen._animating: await get_tree().process_frame
	await frames()


func shot(name: String) -> void:
	if not capture: return
	await frames(10)
	RenderingServer.force_draw(false)
	var path := OUTPUT.path_join(name + ".png")
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "capture " + name)


func run() -> void:
	Settings.reduced_motion = false
	Ink.apply_style(GameStyle.taopunk())
	Engine.max_fps = 120
	get_window().size = Vector2i(1280, 720)
	Router.host = self
	GameState.start_new_run()
	var before := GameState.rng.state
	var sequence := GameState.battle_sequence
	Router.goto("res://src/screens/tutorial_screen.gd")
	await frames(20)
	var screen: Control = Router.current
	check(screen._enemy_art._actor != null and screen._enemy_art._actor.visible, "existing 墨灵 actor is active")
	check(not screen._spotlight.gesture.is_empty(), "animated gesture targets the first glyph")
	var elapsed: float = screen._spotlight._elapsed
	await get_tree().create_timer(0.15).timeout
	check(screen._spotlight._elapsed > elapsed, "spotlight animation advances without gameplay input")
	await shot("desktop-single")
	screen._commit(screen.PATHS[0])
	check(screen._animating and not screen._board_view._interactable, "play animation locks board input")
	screen._commit(screen.PATHS[0])
	await settle(screen)
	check(screen.step == 1 and screen.battle.discard.size() == 1, "repeated confirmation cannot double-spend a glyph")
	screen._commit(screen.PATHS[1]); await settle(screen)
	check(screen.step == 2 and screen._spotlight.falls.size() == 2, "gravity lesson previews both landing paths")
	var material: CharInstance = screen.battle.board.get_xy(Vector2i(1, 1))
	await shot("desktop-before-gravity")
	screen._commit(screen.PATHS[2])
	check(screen._animating and screen.step == 2, "gravity result is held onscreen before advancing the guide")
	await frames(5)
	await shot("desktop-gravity-motion")
	await settle(screen)
	check(screen.step == 3 and screen.battle.board.get_xy(Vector2i(1, 3)) == material, "gravity animation preserves real card identity")
	await shot("desktop-after-gravity")
	for index in [3, 4]:
		screen._commit(screen.PATHS[index]); await settle(screen)
	await shot("desktop-defense")
	screen._end_turn()
	check(screen._animating and screen.battle.turn == 1, "enemy action is shown before resolving the turn")
	await settle(screen)
	check(screen.step == 6 and screen.battle.player.hp == 30 and screen.battle.turn == 2, "animated lesson finishes with a real blocked enemy attack")
	check(before == GameState.rng.state and sequence == GameState.battle_sequence, "animated practice leaves adventure RNG and battle sequence untouched")
	await shot("desktop-complete")
	get_window().size = Vector2i(844, 390)
	BattleTouchLayout.test_dpi = 160
	Settings.reduced_motion = true
	screen._restart(); await frames(20)
	check(screen.get_global_rect().encloses(screen._enemy_card.get_global_rect()) and screen.get_global_rect().encloses(screen._guide_frame.get_global_rect()), "phone opponent and guidance stay onscreen")
	check(not screen._board_view.get_global_rect().intersects(screen._guide_frame.get_global_rect()), "phone spotlight instructions do not cover the board")
	await shot("phone-single")
	for index in [0, 1]: screen._commit(screen.PATHS[index])
	await frames(10)
	await shot("phone-before-gravity")
	screen._commit(screen.PATHS[2]); await frames(10)
	check(screen.step == 3 and not screen._animating, "reduced motion resolves gravity without a forced animation wait")
	await shot("phone-after-gravity")
	BattleTouchLayout.test_dpi = 0
	Router.release_host(self)
	if capture: print("CAPTURES ", ProjectSettings.globalize_path(OUTPUT))
	print("Tutorial spotlight: %d passed / %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)
