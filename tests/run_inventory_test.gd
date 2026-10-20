extends Control
const RoomRun = preload("res://src/expedition/room_run_state.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func frames(count := 4) -> void:
	for i in count: await get_tree().process_frame

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(50).timeout.connect(func(): get_tree().quit(2))
	_run.call_deferred()

func _run() -> void:
	Router.host = self
	for page in ["title", "map", "reward", "shop", "rest", "event", "custom_deck", "glyph_graph", "expedition_map", "room_map", "room_map_3d", "event_board", "battle"]:
		GameState.start_new_run("v03")
		if page == "expedition_map": Expedition.start(91)
		if page in ["room_map", "room_map_3d", "event_board"]:
			var owner = RoomRun.new()
			owner.reset({"seed":91, "layout":"authored_garden" if page == "room_map_3d" else "node_graph"})
			if page == "event_board":
				owner.phase = "event_board"
				owner.event_board = {"glyphs": ["火", "电", "防", "御"]}
		GameState.add_relic("strike")
		Router.goto("res://src/screens/%s_screen.gd" % page)
		await frames(8)
		var screen: Control = Router.current
		if page == "room_map_3d":
			while screen.map_view._building: await frames()
		var bar: Control = screen.inventory_bar
		if page in ["title", "battle"]:
			check(bar==null, page + " does not display the shared run inventory")
			check(screen.content.position.is_equal_approx(Vector2.ZERO) and screen.content.size.is_equal_approx(screen.size), page + " keeps the full content area without an empty inventory strip")
			continue
		check(bar.is_visible_in_tree() and bar.buttons.size() == 3 and not bar.buttons.has("tray"), page + " exposes deck, relics and coins without a tray entry")
		if page == "room_map":
			check_map_header(screen)
			get_window().size = Vector2i(960, 432)
			await frames(12)
			check_map_header(screen)
			if OS.get_cmdline_user_args().has("--capture-map-header") and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				DirAccess.make_dir_recursive_absolute("res://shots")
				get_viewport().get_texture().get_image().save_png("res://shots/map-unified-header-phone.png")
			get_window().size = Vector2i(1280, 720)
			await frames(12)
		else:
			check(screen.content.position.y >= bar.size.y - 1, page + " reserves space for inventory bar")
		check(bar._relics.get_child_count() == 1 and bar._relics.get_child(0).get_meta("relic_id") == "strike" and bar._relics.get_child(0).get_child_count() == 1, page + " displays an owned relic as a 3D preview")
		var before := [GameState.gold, GameState.deck.duplicate(), GameState.rng.state, CharInstance._next_uid]
		for tab in ["deck", "relics", "gold"]:
			bar.buttons[tab].pressed.emit()
			await frames(2)
			var overlay: Control = bar._overlay
			check(is_instance_valid(overlay) and overlay._tab == tab and get_tree().paused, page + " opens " + tab + " and pauses underlying actions")
			overlay._close()
			await frames(2)
			check(not get_tree().paused, page + " restores processing on close")
		check(before == [GameState.gold, GameState.deck, GameState.rng.state, CharInstance._next_uid], page + " inventory is read only")
		GameState.add_gold(7)
		await frames()
		check(bar.buttons.gold.text == "铜钱 %d" % GameState.gold, page + " gold updates live")
	var run = RoomRun.new()
	run.reset({"seed":92, "layout":"node_graph"})
	GameState.add_character(Database.get_character_by_glyph("火"))
	GameState.add_character(Database.get_character_by_glyph("电"))
	GameState.add_relic("strike")
	Router.goto("res://src/screens/reward_screen.gd")
	await frames(8)
	var bar = Router.current.inventory_bar
	check(not bar.buttons.has("tray") and bar.buttons.deck.text == "牌库 %d" % GameState.deck_size(), "courtyard exposes only the actual combat deck")
	bar.open("tray"); await frames()
	check(not is_instance_valid(bar._overlay), "retired tray route cannot open an empty viewer")
	bar.open("deck"); await frames()
	check(bar._overlay._body.get_child_count() == GameState.deck_size() and not bar._overlay._tabs.has("tray"), "deck viewer shows every owned instance and has no tray tab")
	bar._overlay._close(); await frames()
	get_window().size = Vector2i(960, 432)
	await frames(12)
	check(get_viewport_rect().encloses(bar.get_global_rect()), "phone inventory bar stays in viewport")
	for button in bar.buttons.values():
		check(bar.get_global_rect().encloses(button.get_global_rect()), "phone inventory buttons fit bar")
	if OS.get_cmdline_user_args().has("--capture"):
		RenderingServer.force_draw(false)
		get_viewport().get_texture().get_image().save_png("/tmp/huozi-inventory-phone.png")
		bar.open("relics"); await frames(8)
		RenderingServer.force_draw(false)
		get_viewport().get_texture().get_image().save_png("/tmp/huozi-inventory-relics.png")
		bar._overlay._close(); await frames()
	Router.current.queue_free(); Router.current = null; Router.host = null
	await frames()
	print("[run_inventory_test] PASS=%d FAIL=%d" % [checks-failures, failures])
	get_tree().quit(1 if failures else 0)


func check_map_header(screen: Control) -> void:
	var bar: Control = screen.inventory_bar
	var row: Rect2 = screen._header.get_global_rect()
	check(bar.embedded and screen.content.position.is_equal_approx(Vector2.ZERO), "map integrates inventory without reserving a second header strip")
	check(screen.get_viewport_rect().encloses(row), "map unified header fits the viewport")
	check(not screen._stats.text.contains("铜钱") and screen._header.find_children("*", "Button", true, false).filter(func(b): return b.text == "字袋").is_empty(), "map has one coin display and one deck entry")
	var controls: Array = [screen._act_title, screen._stats, screen._header.get_child(-1)] + bar.buttons.values()
	for control: Control in controls:
		var rect := control.get_global_rect()
		check(row.grow(1).encloses(rect) and absf(rect.get_center().y - row.get_center().y) < 1, "map header aligns " + control.name + " in one row")
	for button: Button in bar.buttons.values():
		var pixels := Vector2(screen.get_window().size) / screen.get_viewport_rect().size
		check(button.size.y * pixels.y >= 47.9, "map inventory retains a physical 48px touch target")
