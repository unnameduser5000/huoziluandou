extends Control
const RUN := preload("res://src/expedition/room_run_state.gd")
var checks := 0
var failures := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if ok: print("PASS ", message)
	else: failures += 1; push_error(message)


func frames(count := 6) -> void:
	for i in count: await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.enabled = false
	GameState.set_meta("courtyard_preview", true)
	Settings.reduced_motion = true
	Router.host = self
	_run.call_deferred()


func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--capture"): return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://shots")
	get_viewport().get_texture().get_image().save_png("res://shots/" + label + ".png")


func _run() -> void:
	for room_route in [false, true]:
		for scenario in ["fixed", "random", "pollution", "remove_gain", "empty"]:
			GameState.start_new_run()
			var route_params := {}
			if room_route:
				var run := RUN.new()
				run.reset({"seed": 29, "layout": "node_graph"})
				for id in run.graph.rooms:
					if run.graph.rooms[id].kind == "event": run._arrive(id); break
				route_params = {"room_run": true}
			var effects: Array = [{"type":"gain_character", "glyph":"火", "count":2}]
			if scenario == "random": effects = [{"type":"gain_character", "min_rarity":0, "max_rarity":2}, {"type":"gain_character", "min_rarity":1, "max_rarity":3}]
			if scenario == "pollution": effects = [{"type":"gain_character", "glyph":"火"}, {"type":"gain_pollution", "character":"debt"}]
			if scenario == "remove_gain": effects = [{"type":"remove_character", "count":1}, {"type":"gain_character", "glyph":"火", "count":2}]
			if scenario == "empty": GameState.deck.clear()
			var event := {"id":"ink_pool", "title":"获得字卡回归", "body":"确认事件实际增加的字。", "options":[{"text":"取字", "effects":effects}]}
			if room_route:
				GameState.room_run.event_data = event
				GameState.room_run.event_node = "start"
			else: route_params["_saved_screen"] = {"event":event}
			Router.goto("res://src/screens/event_screen.gd", route_params)
			await frames()
			var screen: Control = Router.current
			var before := {}
			for inst: CharInstance in GameState.deck: before[inst.uid] = true
			screen._choose(0)
			await frames()
			if scenario == "remove_gain":
				for child in screen.get_children():
					if child is CollectionOverlay and child.cfg.get("pick_on_click", false): child._on_card_clicked(GameState.deck[0].data); break
				await frames()
			var receipt := screen.get_node_or_null("EventCharacterReceipt") as CollectionOverlay
			check(receipt != null and Router.current == screen, str(room_route) + scenario + " shows a receipt before leaving")
			if receipt == null: get_tree().quit(1); return
			var actual := {}
			for inst: CharInstance in GameState.deck:
				if not before.has(inst.uid): actual[inst.glyph()] = int(actual.get(inst.glyph(), 0)) + 1
			check(receipt.cfg.counts == actual and receipt.cfg.characters.size() == actual.size(), "receipt matches actual gained identities and copy counts")
			var count := GameState.deck_size()
			var rng: int = GameState.rng.state
			screen._choose(0)
			check(GameState.deck_size() == count and GameState.rng.state == rng, "receipt cannot reroll or grant twice")
			if room_route and scenario == "pollution": await shot("event-character-receipt")
			receipt._close()
			await frames(12)
			check(Router.current != screen and GameState.deck_size() == count and GameState.rng.state == rng, "acknowledgement advances without repeating effects")
	GameState.start_new_run()
	GameState.add_relic("strike")
	GameState.add_relic("egg")
	Router.goto("res://src/screens/rest_screen.gd")
	await frames()
	var bar: Control = Router.current.inventory_bar
	check(bar._relics.get_child_count() == 2 and bar._relics.get_child(0).text.is_empty(), "owned relic strip uses models instead of name buttons")
	var button: Button = bar._relics.get_child(1)
	var preview: Control = button.get_child(0)
	check(preview.specimen.get_meta("relic_id") == "egg" and preview.viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "strip shows the correct 3D model with retained rendering")
	var before := [GameState.rng.state, GameState.deck.duplicate(), GameState.gold, GameState.relics.duplicate()]
	button.pressed.emit()
	await frames()
	check(get_tree().paused and bar._overlay.selected_relic == "egg", "clicking a model opens that relic's details")
	bar._overlay._select_relic("strike")
	check(bar._overlay.selected_relic == "strike", "model gallery switches inspected identity")
	await shot("owned-relic-model-details")
	get_window().size = Vector2i(844,390)
	await frames(12)
	var physical_scale: float = float(get_window().size.y) / bar._overlay.size.y
	check(bar._overlay.find_children("*", "Button", true, false).all(func(b): return b.size.y * physical_scale >= 47.9), "resized phone inspector keeps physical touch targets")
	await shot("owned-relic-model-details-phone")
	bar._overlay._close()
	await frames()
	check(not get_tree().paused and before == [GameState.rng.state, GameState.deck, GameState.gold, GameState.relics], "inspection restores processing and never changes gameplay")
	get_window().size = Vector2i(1280,720)
	var gallery := ChoiceOverlay.new()
	gallery.setup({"title":"遗物", "relics":["strike","egg"], "dismissible":true, "options":[{"text":"关闭"}]})
	Router.current.add_child(gallery)
	await frames()
	var models := gallery.find_children("*", "Button", true, false).filter(func(b): return b.has_meta("relic_id"))
	check(models.size() == 2, "information popups also show clickable 3D relics")
	models[0].pressed.emit()
	await frames()
	var detail: ChoiceOverlay
	for child in gallery.get_children():
		if child is ChoiceOverlay: detail = child
	check(detail != null and detail.cfg.relic_id == "strike" and not gallery._chosen, "model click opens exact relic information without choosing the underlying reward")
	detail._on_choose(0)
	await frames()
	check(gallery.is_inside_tree() and not gallery._chosen, "closing relic details preserves the underlying popup")
	gallery._on_choose(0)
	Router.release_host(self)
	print("[event_loot_feedback_test] PASS=%d FAIL=%d" % [checks - failures, failures])
	get_tree().quit(1 if failures else 0)
