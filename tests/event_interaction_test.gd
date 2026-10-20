extends Control
## Regression coverage for cancel/back, partial selections and saved event choices.
const RUN = preload("res://src/expedition/room_run_state.gd")
const EFFECTS = preload("res://src/core/event_effects.gd")
var run: RefCounted
var checks := 0
var failures := 0


func _ready() -> void: _run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)


func frames(count := 4) -> void:
	for i in count: await get_tree().process_frame


func picker() -> CollectionOverlay:
	for child in Router.current.get_children():
		if child is CollectionOverlay and not child.is_queued_for_deletion(): return child
	return null


func prepare(kind: String, event_id := "old_bookshop", deck: Array = []) -> void:
	run = RUN.new()
	run.reset({"seed": 7719, "layout": "node_graph", "deck": deck})
	for id: String in run.graph.rooms:
		if run.graph.rooms[id].kind == kind: run._arrive(id); break
	if kind == "event":
		run.event_data = EFFECTS.get_event(event_id).duplicate(true)
		run.event_node = "start"
		run._sync_content()


func open_event(event_id := "old_bookshop", deck: Array = []) -> void:
	prepare("event", event_id, deck)
	Router.goto("res://src/screens/event_screen.gd", {"room_run": true})
	await frames()


func _run() -> void:
	SaveManager.enabled = false
	GameState.set_meta("courtyard_preview", true)
	Settings.reduced_motion = true
	Engine.max_fps = 120
	Router.host = self
	get_window().size = Vector2i(1280, 720)
	await open_event()
	get_window().size = Vector2i(844, 390)
	await frames(8)
	var screen: Control = Router.current
	var physical_scale := float(get_window().size.y) / screen.size.y
	check(screen._buttons.all(func(button): return button.size.y * physical_scale >= 47.9 and screen.get_global_rect().encloses(button.get_global_rect())), "phone landscape keeps all event choices visible with usable touch targets")
	check(is_instance_valid(screen._leave_button) and screen.get_global_rect().encloses(screen._leave_button.get_global_rect()), "phone landscape also keeps the empty-handed exit visible")
	get_window().size = Vector2i(1280, 720)
	await frames()
	var before := GameState.glyph_counts()
	var rng_before := GameState.rng.state
	var room: String = run.current_room
	Router.current._choose(0)
	await frames()
	check(picker() != null and run.phase == "event_choose", "event removal opens its saved picker")
	check(run.legal_actions().any(func(a): return a.type == "cancel_pick"), "automation exposes the same cancel action")
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	get_viewport().push_input(escape)
	await frames()
	check(picker() == null and run.phase == "event" and not Router.current._done, "Escape returns to event options without reopening the picker")
	check(is_instance_valid(Router.current._leave_button) and not Router.current._leave_button.disabled, "cancel restores empty-handed leave")
	check(GameState.glyph_counts() == before and GameState.rng.state == rng_before and not run.resolved.has(room), "cancel does not remove a glyph, consume RNG or complete the node")
	check(PauseMenu._instance == null, "Escape consumed by picker does not also open the pause menu")
	Router.current._leave_event()
	await frames()
	check(run.phase == "map" and run.resolved.has(room), "player can leave after giving up removal")

	await open_event("trim_words", ["火", "火", "击"])
	before = GameState.glyph_counts(); rng_before = GameState.rng.state
	GameState.player_hp = 50
	Router.current._choose(1)
	await frames()
	picker()._on_card_clicked(Database.get_character_by_glyph("火"))
	await frames()
	check(run.phase == "event_choose" and int(run.pending_event_effect.remaining) == 1, "two-target removal waits for the second target")
	check(int(picker().cfg.counts["火"]) == 1 and GameState.glyph_counts() == before, "picker subtracts reserved copies while leaving the actual deck unchanged")
	var old_session: RefCounted = Router.current._room_session
	const SAVE_PATH := "user://event-interaction-pending-test.tres"
	check(run.save_run(SAVE_PATH) == OK, "partial target choice can be saved")
	run = RUN.restore(SAVE_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	Router.goto("res://src/screens/event_screen.gd", {"room_run": true})
	await frames()
	check(picker() != null and run.pending_event_effect.selected == ["火"], "load restores partial removal without reselecting or spending")
	check(not old_session.apply({"type": "cancel_pick"}).ok and run.phase == "event_choose", "stale screen session cannot cancel a new run instance")
	var modal := picker()
	modal._close(); modal._close()
	await frames()
	check(run.phase == "event" and picker() == null and run.pending_event_effect.is_empty(), "repeated close safely cancels a restored partial choice once")
	check(GameState.glyph_counts() == before and GameState.player_hp == 50 and GameState.rng.state == rng_before, "partial cancel rolls out all targets without cost or reward")
	Router.current._choose(1); await frames()
	picker()._on_card_clicked(Database.get_character_by_glyph("火")); await frames()
	modal = picker()
	var glyph: String = run.pending_glyphs[0]
	modal._on_card_clicked(Database.get_character_by_glyph(glyph))
	modal._on_card_clicked(Database.get_character_by_glyph(glyph))
	await frames()
	check(run.phase == "map" and GameState.deck_size() == 2 and GameState.player_hp == 45, "retry settles exactly two removals, five damage and one reward once")

	await open_event("delete_poems", ["火"])
	check(Router.current._buttons[0].disabled and not Router.current._buttons[1].disabled, "insufficient deck disables remove-two without disabling remove-one")
	var hp := GameState.player_max_hp
	var rejected: Dictionary = EFFECTS.resolve(run.current_event().options[0].effects, GameState.rng)
	check(not rejected.ok and GameState.player_max_hp == hp and GameState.deck_size() == 1, "insufficient removal cannot collect a full reward for a partial cost")
	GameState.deck.clear()
	var no_targets := EFFECTS.resolve([{"type": "remove_character", "count": 1}, {"type": "gold", "amount": 20}], GameState.rng)
	check(not no_targets.ok, "empty deck cannot bypass removal and collect its reward")

	await open_event("return_brush", ["火"])
	check(Router.current._buttons[0].disabled, "rare-character removal stays disabled without a rare character")
	var filtered := EFFECTS.resolve([{"type": "remove_character", "count": 1, "min_rarity": 2}], GameState.rng)
	check(not filtered.ok, "unavailable rarity filter does not create an empty stuck picker")
	# One unrestricted target followed by a rare target must reserve different entities.
	var rare: CharacterData
	for ch: CharacterData in Database.characters.values():
		if ch.rarity >= 2 and ch.rarity <= 4 and not ch.is_pollution and not ch.pending_design: rare = ch; break
	GameState.add_character(rare)
	var mixed := EFFECTS.resolve([{"type": "remove_character"}, {"type": "remove_character", "min_rarity": 2}], GameState.rng)
	check(mixed.ok and mixed.pending.glyphs == ["火"], "mixed filters do not offer a first pick that strands the remaining rare target")

	await open_event()
	# A saved choice may contain a character that disappeared elsewhere; validate all targets first.
	var pending := EFFECTS.resolve([{"type":"remove_character", "count":2}], GameState.rng)
	var first: String = pending.pending.glyphs[0]
	var next := EFFECTS.resume(pending.pending, first, GameState.rng)
	var second: String = next.pending.glyphs[0]
	GameState.deck.clear()
	GameState.add_character(Database.get_character_by_glyph(second))
	before = GameState.glyph_counts()
	var stale := EFFECTS.resume(next.pending, second, GameState.rng)
	check(not stale.ok and GameState.glyph_counts() == before, "stale multi-pick fails before deleting any remaining entity")
	var legacy := {"type":"remove_character", "effects":[{"type":"remove_character", "count":2}, {"type":"gold", "amount":20}], "removal_counts":[1,0], "remaining":1, "selected":[], "glyphs":[second]}
	var old_pending := EFFECTS.resume(legacy, second, GameState.rng)
	check(not old_pending.ok and GameState.glyph_counts() == before, "old truncated pending choices cannot bypass the new full-cost check")

	await open_event("jade_case")
	GameState.gold = 100
	Router.current._choose(0); await frames()
	check(run.phase == "event" and run.event_node == "one" and GameState.gold == 92, "multi-stage event keeps its continuation")
	check(Router.current._buttons[0].tooltip_text.contains("15"), "continuation presents the current stage's options")
	await open_event("battle_relic")
	check(not is_instance_valid(Router.current._leave_button), "forced encounter does not expose an empty-handed exit")
	check(not run.apply({"type":"event_leave"}).ok and run.phase == "event", "forced encounter cannot be bypassed through a leave action")
	check(not bool(EFFECTS.node({"allow_leave": false, "nodes": {"start": {"body":"", "options":[]}}}).get("allow_leave", true)), "continuation inherits the event's forced-choice policy")
	await open_event("xuanji_board")
	Router.current._choose(0); await frames(10)
	check(Router.current_path.ends_with("event_board_screen.gd") and run.phase == "event_board", "board event still opens its dedicated interaction screen")
	Router.current._on_leave(); await frames()
	check(run.phase == "map", "board event can give up and return to the node map")
	await open_event("xuanji_board")
	Router.current._choose(0); await frames(10)
	var board_size_before := GameState.deck_size()
	Router.current._view.path = run.event_board.paths[0].duplicate()
	Router.current._on_confirm(); await frames()
	check(run.phase == "map" and GameState.deck_size() > board_size_before, "board event still grants the chosen word's characters")

	prepare("rest")
	Router.goto("res://src/screens/rest_screen.gd", {"room_run": true}); await frames()
	Router.current._do_remove(); await frames()
	picker()._close(); await frames()
	check(run.phase == "rest" and not Router.current._done and picker() == null, "rest cancellation preserves its choice and closes the picker")
	GameState.player_hp = 1
	Router.current._do_heal(); await frames()
	check(run.phase == "map" and GameState.player_hp > 1, "rest can switch to healing after cancelling removal")
	prepare("rest")
	Router.goto("res://src/screens/rest_screen.gd", {"room_run": true}); await frames()
	Router.current._do_remove(); await frames()
	var missing: String = run.pending_glyphs[0]
	var missing_card: CharacterData = Database.get_character_by_glyph(missing)
	while GameState.remove_character_id(missing_card.id): pass
	picker()._on_card_clicked(missing_card); await frames()
	check(run.phase == "rest" and not Router.current._done, "invalidated rest target recovers the options instead of stranding the screen")

	prepare("shop")
	GameState.gold = 100
	Router.goto("res://src/screens/shop_screen.gd", {"room_run": true}); await frames()
	var index := -1
	for i in run.shop_offers.size():
		if run.shop_offers[i].kind == "remove": index = i; break
	var price: int = run.shop_offers[index].price
	var stock: int = run.shop_offers.size()
	Router.current._buy(index); await frames()
	check(run.phase == "shop_choose" and GameState.gold == 100 - price, "shop prepays its pending service")
	modal = picker(); modal._close(); modal._close(); await frames()
	check(run.phase == "shop" and GameState.gold == 100 and run.shop_offers.size() == stock and not Router.current._busy, "shop cancellation refunds once, restores controls and retains stock")
	check(not run.apply({"type":"cancel_pick"}).ok and GameState.gold == 100, "repeating cancellation cannot mint a second refund")
	Router.current._buy(index); await frames()
	before = GameState.glyph_counts()
	picker()._on_card_clicked(Database.get_character_by_glyph(run.pending_glyphs[0])); await frames()
	check(run.phase == "shop" and GameState.gold == 100 - price and run.shop_offers.size() == stock - 1, "shop retry charges once and consumes its completed service")

	GameState.start_new_run("v03")
	GameState.gold = 100
	Router.goto("res://src/screens/shop_screen.gd"); await frames()
	index = -1
	for i in Router.current._offers.size():
		if Router.current._offers[i].kind == "copy": index = i; break
	price = Router.current._offers[index].price
	stock = Router.current._offers.size()
	Router.current._buy(index); await frames()
	modal = picker(); modal._close(); modal._close(); await frames()
	check(GameState.gold == 100 and Router.current._offers.size() == stock and not Router.current._busy, "legacy shop cancellation also refunds and preserves stock")
	Router.current._buy(index); await frames()
	var size_before := GameState.deck_size()
	modal = picker()
	modal._on_card_clicked(GameState.deck[0].data)
	modal._on_card_clicked(GameState.deck[0].data)
	await frames()
	check(GameState.gold == 100 - price and GameState.deck_size() == size_before + 1 and Router.current._offers.size() == stock - 1, "legacy copy retry applies once without duplicate callbacks")

	# Closing via the dimmed background must not treat scrolling as cancellation.
	var overlay := CollectionOverlay.new(); overlay.setup({"characters":[]}); add_child(overlay)
	var wheel := InputEventMouseButton.new(); wheel.pressed = true; wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	overlay._on_dim_input(wheel)
	check(not overlay.is_queued_for_deletion(), "wheel input does not accidentally close a picker")
	overlay._close(); await frames()
	print("[event_interaction_test] CHECKS=%d FAIL=%d" % [checks, failures])
	Music.stop()
	await frames(2)
	get_tree().quit(0 if failures == 0 else 1)
