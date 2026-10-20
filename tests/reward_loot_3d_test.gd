extends Control
## Real counter projections, pickup input, single settlement, binding and saved receipts.
const RUN := preload("res://src/expedition/room_run_state.gd")
const QA := "res://docs/qa/reward-loot-3d-2026-10-20/"
const SAVE := "user://reward-loot-3d-test.tres"
var passed := 0
var failed := 0


func _ready() -> void:
	Settings.storage_path = "user://reward-loot-3d-test-settings.cfg"
	SaveManager.enabled = false
	Settings.reduced_motion = true
	GameState.set_meta("courtyard_preview", true)
	Engine.max_fps = 120
	Router.host = self
	DirAccess.make_dir_recursive_absolute(QA)
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if ok: passed += 1; print("PASS ", message)
	else: failed += 1; push_error(message)


func frames(count := 10) -> void:
	for i in count: await get_tree().process_frame


func prepare(kind: String) -> RefCounted:
	var run := RUN.new()
	run.reset({"seed": 129, "layout": "node_graph"})
	run.autosave = false
	for id in run.graph.rooms:
		if run.graph.rooms[id].kind == kind: run.current_room = id; break
	run.node = run.battle_node()
	run.phase = "encounter"
	run.begin_live_battle()
	run.finish_live_battle(true)
	if kind == "elite": run.contents[run.current_room].battle_relics = ["slab"]
	elif kind == "boss": run.contents[run.current_room].battle_relics = ["ghost_hand", "moon"]
	return run


func open_reward(run: RefCounted) -> void:
	Router.goto("res://src/screens/reward_screen.gd", {"room_run": true, "node": run.node})
	await frames(20)


func click(target: Control, touch: bool) -> void:
	var point := target.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	await frames(2)
	for down in [true, false]:
		if touch:
			var event := InputEventScreenTouch.new()
			event.position = get_viewport().get_final_transform() * point
			event.pressed = down
			Input.parse_input_event(event)
		else:
			var event := InputEventMouseButton.new()
			event.position = point
			event.global_position = point
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = down
			get_viewport().push_input(event, true)
		await frames(2)


func shot(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"): return
	await frames()
	RenderingServer.force_draw(false)
	check(get_viewport().get_texture().get_image().save_png(QA + name + ".png") == OK, "capture " + name)


func captions_clear_of_models(screen: Control) -> bool:
	var view: Control = screen._showcase
	var labels: Array = screen._cards + [screen._gold_offer] + screen._relic_offers
	var caption_rects: Array[Rect2] = []
	for offer in labels:
		if not offer.visible or not offer._caption.visible: continue
		var caption: Rect2 = offer._caption.get_global_rect()
		for other in caption_rects:
			if caption.intersects(other):
				print("Caption overlaps caption: ", offer.caption, " ", caption, " ", other)
				return false
		caption_rects.append(caption)
		if not screen.get_global_rect().encloses(caption): return false
		if caption.intersects(screen._hud.status_label.get_global_rect()):
			print("Caption overlaps status: ", offer.caption, " ", caption, " ", screen._hud.status_label.get_global_rect())
			return false
		for node in view.stage.objects:
			if not node.visible: continue
			var bounds: AABB = node.get_meta("reward_bounds")
			var low := Vector2(INF, INF)
			var high := Vector2(-INF, -INF)
			for corner in 8:
				var point: Vector2 = view.stage.camera.unproject_position(node.global_transform * bounds.get_endpoint(corner)) * view.size / Vector2(view.viewport.size)
				low = low.min(point)
				high = high.max(point)
			if caption.intersects(Rect2(low + view.global_position, high - low)):
				print("Caption overlaps model: ", offer.caption, " ", caption, " ", node.name, " ", Rect2(low, high - low))
				return false
	return true


func _run() -> void:
	for resolution in [Vector2i(1280, 720), Vector2i(640, 360)]:
		get_window().size = resolution
		await frames()
		for kind in ["battle", "elite", "boss"]:
			var run := prepare(kind)
			var gold := GameState.gold
			await open_reward(run)
			var screen: Control = Router.current
			var stage: Node3D = screen._showcase.stage
			check(GameState.gold == gold, kind + " model construction never repeats combat gold settlement")
			check(stage.objects.size() == screen._options.size() + 1 + screen._relic_choices.size(), kind + " glyphs, coins and relics share the actual counter")
			check(stage.objects[screen._gold_object].get_meta("gold_amount") == Expedition.SKIP_GOLD and stage.objects[screen._gold_object].get_child_count() > 0, "coin pile has batched 3D meshes and the real gold amount")
			var targets: Array = [screen._gold_offer] + screen._relic_offers
			var scale := JourneyStyle.touch_scale(screen)
			check(targets.all(func(target): return screen.get_global_rect().encloses(target.get_global_rect()) and target.size.x >= 48 * scale - 1 and target.size.y >= 48 * scale - 1), str(resolution) + kind + " all loot targets fit and keep 48px touch areas")
			check(screen.get_children().all(func(child): return not child is ChoiceOverlay), "the counter remains visible without an automatic selection popup")
			check(captions_clear_of_models(screen), str(resolution) + kind + " reward captions stay outside every displayed model")
			await shot(kind + "-%d" % resolution.x)
			if kind != "battle":
				var before := GameState.deck_size()
				screen._accept_pick(); screen._on_skip()
				check(GameState.gold == gold and GameState.deck_size() == before and run.phase == "reward", "pending relic blocks glyph and gold settlement")
				var index := 1 if kind == "boss" else 0
				var id: String = screen._relic_choices[index]
				await click(screen._relic_offers[index], resolution.x == 640)
				await frames()
				if kind == "elite":
					var pickers := screen.get_children().filter(func(child): return child is CollectionOverlay and not child.is_queued_for_deletion())
					check(screen._busy and not pickers.is_empty(), "binding relic keeps the reward locked until its glyph is chosen")
					if not pickers.is_empty(): pickers[0]._close()
					await frames()
				check(GameState.has_relic(id) and not screen._relic_pending and not screen._busy, "real model click grants the displayed relic and completes its continuation")
				check(screen._relic_offers.is_empty() and screen._relic_objects.is_empty() and stage.objects.size() == screen._options.size() + 1 and run.contents[run.current_room].battle_relics.is_empty(), "all claimed relic models and targets leave the counter and the saved candidate list clears")
				check(GameState.gold == gold and GameState.deck_size() == before, "relic pickup never grants gold or a glyph twice")
				check(run.save_run(SAVE) == OK, "claimed relic receipt saves")
				run = RUN.restore(SAVE)
				run.autosave = false
				await open_reward(run)
				screen = Router.current
				check(not screen._relic_pending and screen._relic_taken == id and screen._relic_offers.is_empty() and screen._relic_objects.is_empty(), "resume keeps the receipt without respawning a claimed relic")
			if kind == "battle" and resolution.x == 640:
				var before := GameState.deck_size()
				screen._inspect(1)
				screen._hud.action_button.pressed.emit()
				await frames()
				check(GameState.deck_size() == before + 1 and GameState.gold == gold, "glyph goes straight into the deck as an alternative to the 3D gold pile")
			else:
				var before := GameState.deck_size()
				await click(screen._gold_offer, resolution.x == 640)
				await frames()
				check(GameState.gold == gold + Expedition.SKIP_GOLD and GameState.deck_size() == before and run.phase != "reward", "real coin click settles skip gold exactly once and leaves the reward")
				check(not run.apply({"type": "skip"}).get("ok", false) and GameState.gold == gold + Expedition.SKIP_GOLD, "repeated or stale gold claim is rejected")
	# The classic boss can display three candidates. Hover lift and tilt must
	# also leave the labels readable, rather than only passing at the rest pose.
	for resolution in [Vector2i(1280, 720), Vector2i(640, 360)]:
		get_window().size = resolution
		await frames()
		var three := prepare("boss")
		three.contents[three.current_room].battle_relics = ["ghost_hand", "moon", "midas"]
		await open_reward(three)
		var reward: Control = Router.current
		check(captions_clear_of_models(reward), str(resolution) + " three relic captions remain separate from models, HUD and each other")
		await shot("boss-three-%d" % resolution.x)
		Settings.reduced_motion = false
		var clear := true
		for index in reward._showcase.stage.objects.size():
			reward._showcase.stage.select_object(index)
			await get_tree().create_timer(0.25).timeout
			clear = captions_clear_of_models(reward) and clear
		check(clear, str(resolution) + " all hovered reward poses keep captions readable")
		Settings.reduced_motion = true
		reward._take_relic(0)
		await frames()
		check(captions_clear_of_models(reward), str(resolution) + " received relic caption stays separate after pickup")
	# Deferred take animations must lock both branches until one transaction settles.
	Settings.reduced_motion = false
	var run := prepare("boss")
	await open_reward(run)
	var screen: Control = Router.current
	var gold := GameState.gold
	var deck_size := GameState.deck_size()
	screen._take_relic(0)
	screen._take_relic(1)
	screen._on_skip()
	check(screen._busy and not GameState.has_relic("ghost_hand") and GameState.gold == gold, "animated relic pickup blocks other relics and gold before settlement")
	var deadline := Time.get_ticks_msec() + 5000
	while screen._busy and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	check(GameState.has_relic("ghost_hand") and not GameState.has_relic("moon") and not screen._relic_pending, "animated relic pickup grants only the selected candidate")
	check(screen._relic_objects.is_empty() and screen._relic_offers.is_empty() and screen._showcase.stage.objects.size() == screen._options.size() + 1, "received relic and unselected candidates disappear after the take animation")
	screen._on_skip(); screen._on_skip()
	check(screen._busy and GameState.gold == gold, "coin animation locks repeated clicks before granting gold")
	deadline = Time.get_ticks_msec() + 5000
	while run.phase == "reward" and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	check(GameState.gold == gold + Expedition.SKIP_GOLD and GameState.deck_size() == deck_size, "animated coin pickup grants exactly one gold alternative")
	Settings.reduced_motion = true
	run = prepare("battle")
	await open_reward(run)
	screen = Router.current
	gold = GameState.gold
	run.phase = "map"
	screen._on_skip()
	check(GameState.gold == gold and not screen._busy and not screen._settled, "stale coin claim restores the model and releases controls without granting gold")
	run.phase = "reward"
	screen._on_skip()
	check(GameState.gold == gold + Expedition.SKIP_GOLD and run.phase != "reward", "retrying a rejected coin claim still settles once")
	DirAccess.remove_absolute(SAVE)
	Router.release_host(self)
	print("[reward_loot_3d_test] PASS=%d FAIL=%d TOTAL=%d" % [passed, failed, passed + failed])
	get_tree().quit(1 if failed else 0)
