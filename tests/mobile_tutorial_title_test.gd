extends Node
## Render the real screens with phone pixel density, cutouts and touch input.
const OUTPUT := "res://shots/mobile-tutorial-title"
var failures: Array[String] = []
var checks := 0
var results: Array = []
var profile: Dictionary
var viewport: SubViewport
var host: Control


func _ready() -> void:
	Settings.storage_path = "user://mobile_tutorial_title_test-settings.cfg"
	get_tree().create_timer(600).timeout.connect(func(): get_tree().quit(2))
	_run.call_deferred()


func frames(count := 6) -> void:
	for i in count: await get_tree().process_frame


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(profile.id + ": " + message)
		print("FAIL ", failures[-1])


func open_screen(name: String) -> Control:
	Router.goto("res://src/screens/" + name + "_screen.gd")
	await frames(10)
	return Router.current


func within(outer: Control, inner: Control) -> bool:
	return outer.get_global_rect().grow(1).encloses(inner.get_global_rect())


func safe_controls(screen: Control, controls: Array) -> void:
	var safe := screen.get_global_transform() * ScreenLayout.safe_rect(screen)
	var unit := JourneyStyle.touch_scale(screen)
	for control: Control in controls:
		if not control.is_visible_in_tree(): continue
		check(safe.grow(1).encloses(control.get_global_rect()), "safe bounds: " + control.name)
		if control is Button:
			check(control.size.y / unit >= 47.9, "48dp target: " + control.text)
			var ink := control.get_theme_font("font").get_string_size(control.text, HORIZONTAL_ALIGNMENT_LEFT, -1, control.get_theme_font_size("font_size"))
			check(ink.x <= control.size.x - control.get_theme_stylebox("normal").get_minimum_size().x + 1, "button text fits: " + control.text)


func tap(control: Control) -> void:
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = control.get_global_rect().get_center()
		event.pressed = pressed
		viewport.push_input(event, true)
		await frames(2)
	await frames()


func capture(tag: String) -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--capture"): return
	await frames(3)
	RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	image.resize(profile.pixels[0], profile.pixels[1], Image.INTERPOLATE_LANCZOS)
	check(image.save_png(OUTPUT.path_join(profile.id + "-" + tag + ".png")) == OK, "capture " + tag)


func title_checks(screen: Control, with_continue: bool) -> void:
	screen._continue_button.visible = with_continue
	screen._layout()
	await frames()
	safe_controls(screen, screen._buttons)
	check(not screen._wordmark.get_global_rect().intersects(screen._menu.get_global_rect()), "logo clears menu")
	check(not screen._utilities.get_global_rect().intersects(screen._menu.get_global_rect()), "utilities clear menu")
	check(not screen._system_menu.get_global_rect().intersects(screen._utilities.get_global_rect()), "footer groups stay separate")
	var compact: bool = ScreenLayout.safe_rect(screen).size.y / JourneyStyle.touch_scale(screen) < 600
	for button: Button in screen._main_buttons:
		var font_dp: float = button.get_theme_font_size("font_size") / JourneyStyle.touch_scale(screen)
		check(font_dp >= 18 and font_dp <= (21 if compact else 24), "main menu font keeps a consistent reading size")
	await capture("title-continue" if with_continue else "title")


func tutorial_checks(screen: Control) -> void:
	var prefix := "step %d: " % screen.step
	var unit := JourneyStyle.touch_scale(screen)
	safe_controls(screen, [screen._header, screen._board_view, screen._enemy_card, screen._guide_frame, screen._exit_btn, screen._confirm_btn, screen._clear_btn, screen._end_btn, screen._replay_btn])
	var regions: Array[Control] = [screen._header, screen._board_view, screen._enemy_card, screen._guide_frame, screen._actions]
	for i in regions.size():
		for j in range(i + 1, regions.size()):
			check(not regions[i].get_global_rect().intersects(regions[j].get_global_rect()), prefix + "panels do not overlap")
	check(screen._guide_frame.get_global_rect().end.x < screen._board_view.global_position.x, prefix + "callout stays beside the battle board")
	check(screen._enemy_card.global_position.x > screen._board_view.get_global_rect().end.x, prefix + "opponent stays to the right of the board")
	check(is_equal_approx(screen._enemy_card.size.y, screen._board_view.size.y), prefix + "opponent keeps the full battle column")
	check(screen._enemy_art.size.y / unit >= 85, prefix + "opponent portrait keeps a usable height")
	check(screen._enemy_art.clip_contents, prefix + "animated portrait cannot cover end-turn button")
	check(screen._end_btn.global_position.y > screen._enemy_card.get_global_rect().end.y, prefix + "end-turn stays beneath opponent")
	var battle_rects := [screen._board_view.get_global_rect(), screen._enemy_card.get_global_rect(), screen._actions.get_global_rect()]
	if not screen.has_meta("battle_rects"): screen.set_meta("battle_rects", battle_rects)
	check(battle_rects == screen.get_meta("battle_rects"), prefix + "guidance and preview do not move combat controls")
	for info: Control in [screen._enemy_name, screen._enemy_health, screen._intent, screen._enemy_art]:
		check(within(screen._enemy_card, info), prefix + "opponent contains %s %s in %s" % [info.name, info.get_global_rect(), screen._enemy_card.get_global_rect()])
	var intent_row: Control = screen._intent._row
	check(within(screen._intent, intent_row), prefix + "attack symbol and number fit intent row")
	for label: Label in [screen._heading, screen._instruction, screen._preview, screen._feedback]:
		if label.is_visible_in_tree(): check(within(screen._guide, label), prefix + "guidance visible: %s %s in %s" % [label.text, label.get_global_rect(), screen._guide.get_global_rect()])
	check(screen._board_view.size.is_equal_approx(Vector2.ONE * screen._board_view.size.x), prefix + "board stays square")
	check(screen._board_view.tiles.all(func(tile): return within(screen._board_view, tile)), prefix + "all board cells fit")


func lesson_checks(screen: Control) -> void:
	var page: Control = screen._lesson_overlay
	if page == null: return
	await frames()
	safe_controls(screen, [page._header, page._exit_btn, page._demo, page._heading, page._body, page._next_btn])
	check(page._copy_bounds.grow(1).encloses(page._copy.get_rect()), "lesson copy fits without scrolling")
	check(not page._demo.get_global_rect().intersects(page._copy.get_global_rect()), "lesson diagram clears copy")
	check(not page._copy.get_global_rect().intersects(page._next_btn.get_global_rect()), "lesson copy clears continue button")
	check(not page._demo._interactable, "lesson example is read-only")
	var count: int = screen.battle.discard.size()
	screen._commit(screen.PATHS[screen.step])
	check(screen.battle.discard.size() == count, "explanation blocks underlying combat input")
	await capture("lesson-page-%d" % page.lesson)
	await tap(page._next_btn)
	check(screen._lesson_overlay == null and screen._board_view._interactable, "lesson continue returns to practice")


func _run() -> void:
	SaveManager.enabled = false
	GameState.set_meta("courtyard_preview", true)
	Settings.reduced_motion = true
	Ink.apply_style(GameStyle.taopunk())
	Engine.max_fps = 240
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var profiles: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mobile_screen_profiles.json")).profiles
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="): profiles = profiles.filter(func(p): return p.id == arg.trim_prefix("--profile="))
	for value: Dictionary in profiles:
		profile = value
		var before := failures.size()
		ScreenLayout.preview_density = profile.density
		ScreenLayout.preview_window_size = Vector2i(profile.pixels[0], profile.pixels[1])
		ScreenLayout.preview_insets = Vector4(profile.insets[0], profile.insets[1], profile.insets[2], profile.insets[3])
		var pixels := Vector2(ScreenLayout.preview_window_size)
		var stretch := minf(pixels.x / 1280, pixels.y / 720)
		viewport = SubViewport.new()
		viewport.size = Vector2i((pixels / stretch).round())
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		host = Control.new()
		host.theme = Ink.theme
		host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		viewport.add_child(host)
		Router.host = host
		var screen := await open_screen("title")
		await title_checks(screen, false)
		await title_checks(screen, true)
		if OS.get_cmdline_user_args().has("--title-only"):
			results.append({"id": profile.id, "failures": failures.slice(before), "viewport": [viewport.size.x, viewport.size.y]})
			print("[title_only] ", profile.id, " failures=", failures.size() - before)
			Router.release_host(host)
			viewport.queue_free()
			await frames(2)
			continue
		# Enter by native screen-touch events, then complete all six actual lessons.
		await tap(screen._main_buttons.filter(func(button): return button.text == "新手教程")[0])
		screen = Router.current
		check(Router.current_path.ends_with("tutorial_screen.gd"), "touch opens tutorial")
		if Router.current_path.ends_with("tutorial_screen.gd"):
			for step in 5:
				await lesson_checks(screen)
				if step == 0: await capture("tutorial-start")
				tutorial_checks(screen)
				for pos: Vector2i in screen.PATHS[step]:
					await tap(screen._tile(pos))
				check(screen._board_view.path == screen.PATHS[step], "touch selects lesson path %d" % step)
				tutorial_checks(screen)
				if step in [0, 2, 4]: await capture("tutorial-%d" % step)
				await tap(screen._confirm_btn)
				check(screen.step == step + 1, "touch confirms lesson %d" % step)
			tutorial_checks(screen)
			await capture("tutorial-end-turn")
			await tap(screen._end_btn)
			check(screen.step == 6 and screen.battle.player.hp == 30, "touch finishes guarded turn")
			tutorial_checks(screen)
			await capture("tutorial-complete")
			await tap(screen._replay_btn)
			check(screen.step == 0 and screen.battle.board.fill_count() == 8, "touch replays practice")
			await lesson_checks(screen)
			await tap(screen._exit_btn)
			check(Router.current_path.ends_with("title_screen.gd"), "touch exits practice")
		results.append({"id": profile.id, "failures": failures.slice(before), "viewport": [viewport.size.x, viewport.size.y]})
		print("[tutorial_title] ", profile.id, " failures=", failures.size() - before)
		Router.release_host(host)
		viewport.queue_free()
		await frames(2)
	ScreenLayout.preview_density = 0
	ScreenLayout.preview_window_size = Vector2i.ZERO
	ScreenLayout.preview_insets = Vector4.ZERO
	var result_name := "results-title-only.json" if OS.get_cmdline_user_args().has("--title-only") else "results.json"
	var report := FileAccess.open(OUTPUT.path_join(result_name), FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks": checks, "failures": failures, "profiles": results}, "\t"))
	report.close()
	print("[mobile_tutorial_title_test] CHECKS=%d FAIL=%d" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
