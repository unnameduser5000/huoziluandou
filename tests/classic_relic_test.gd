extends Control
## Approved reward rules, transaction checkpoints and landscape layout regression.
var checks := 0
var failures := 0
const QA := "res://docs/qa/reward-shop-2026-10-19/"


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	else: print("PASS ", message)


func frames(n := 6) -> void:
	for i in n: await get_tree().process_frame


func overlay(type) -> Node:
	for child in Router.current.get_children():
		if is_instance_of(child, type) and not child.is_queued_for_deletion(): return child
	return null


func open_reward(type: MapNodeData.Type) -> Control:
	var node := MapNodeData.new()
	node.type = type
	Router.goto("res://src/screens/reward_screen.gd", {"node": node})
	await frames()
	if Router.current_path.ends_with("reward_screen.gd") and Router.current._relic_pending:
		Router.current._secondary_action()
		await frames()
	return Router.current


func save_and_resume() -> void:
	check(SaveManager.checkpoint(), "stable reward/shop checkpoint accepted")
	SaveManager.flush()
	check(SaveManager.resume_run(), "checkpoint resumes through real save codec")
	await frames()
	if Router.current.get_script().resource_path.ends_with("reward_screen.gd") and Router.current._relic_pending:
		Router.current._secondary_action()
		await frames()


func finish_binding() -> void:
	var picker: CollectionOverlay = overlay(CollectionOverlay)
	if picker != null:
		picker._close()
		await frames()


func own_all_but(keep: Array) -> void:
	GameState.relics = Relics.DEFS.keys().filter(func(id): return not keep.has(id))
	GameState.relic_binds.clear()


func shot(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"): return
	await frames(10)
	RenderingServer.force_draw(false)
	check(get_viewport().get_texture().get_image().save_png(QA + name + ".png") == OK, "capture " + name)


func _ready() -> void:
	Settings.storage_path = "user://classic-relic-settings.cfg"
	Settings.reduced_motion = true
	SaveManager.activate("user://classic-relic-regression.save")
	Router.host = self
	_run.call_deferred()


func _run() -> void:
	GameState.start_new_run()
	var reward := await open_reward(MapNodeData.Type.BATTLE)
	var before := GameState.deck_size()
	var node_before := GameState.node_index
	check(reward._options.size() == 3, "normal reward offers three glyphs")
	reward._inspect(0)
	reward._accept_pick()
	await frames()
	check(GameState.deck_size() == before + 1 and GameState.node_index == node_before + 1 and Router.current_path.ends_with("map_screen.gd"), "one pick settles once and leaves without a second round")
	GameState.start_new_run()
	reward = await open_reward(MapNodeData.Type.BATTLE)
	var gold := GameState.gold
	reward._on_skip()
	reward._on_skip()
	await frames()
	check(GameState.gold == gold + 16, "double skip grants exactly 16 gold once")

	GameState.start_new_run()
	reward = await open_reward(MapNodeData.Type.ELITE)
	var choice: ChoiceOverlay = overlay(ChoiceOverlay)
	check(choice != null and choice.cfg.options.size() == 1, "elite drops one relic")
	before = GameState.deck_size()
	reward._accept_pick()
	reward._on_skip()
	check(Router.current == reward and GameState.deck_size() == before, "pending relic prevents skipping or claiming glyphs underneath")
	choice._on_choose(0)
	await frames()
	await finish_binding()
	check(GameState.relics.size() == 1 and not reward._hud.action_button.disabled, "elite relic grants once then unlocks glyph reward")

	GameState.start_new_run()
	GameState.player_hp = 1
	reward = await open_reward(MapNodeData.Type.BOSS)
	var healed := GameState.player_hp
	check(healed == 1 + int(round(GameState.player_max_hp * 0.3)), "boss heals 30 percent of maximum HP")
	choice = overlay(ChoiceOverlay)
	check(choice != null and choice.cfg.options.size() == 3, "boss offers three distinct unowned relics")
	var ids: Array = reward._relic_choices.duplicate()
	var glyphs: Array = reward._options.map(func(c): return c.id)
	var rng_state := GameState.rng.state
	await save_and_resume()
	reward = Router.current
	check(GameState.player_hp == healed and reward._relic_choices == ids and GameState.rng.state == rng_state, "resume preserves HP, relic candidates and RNG without another heal")
	check(reward._options.map(func(c): return c.id) == glyphs, "resume preserves glyph candidates")
	choice = overlay(ChoiceOverlay)
	choice._on_choose(2)
	choice._on_choose(0)
	await frames()
	await finish_binding()
	check(GameState.relics.size() == 1 and GameState.has_relic(ids[2]), "boss choice grants exactly one selected relic")
	await save_and_resume()
	check(overlay(ChoiceOverlay) == null and GameState.player_hp == healed and GameState.relics.size() == 1, "claimed relic and heal never repeat after resume")

	GameState.start_new_run()
	own_all_but(["slab"])
	reward = await open_reward(MapNodeData.Type.ELITE)
	await frames()
	check(SaveManager.checkpoint(), "pre-binding offer can be saved")
	SaveManager.flush()
	choice = overlay(ChoiceOverlay)
	choice._on_choose(0)
	await frames()
	check(overlay(CollectionOverlay) != null and not SaveManager.checkpoint(), "unfinished binding does not overwrite the whole transaction")
	check(SaveManager.resume_run(), "interrupted binding resumes preceding offer")
	await frames()
	Router.current._secondary_action()
	await frames()
	check(not GameState.has_relic("slab") and overlay(ChoiceOverlay) != null, "interrupted relic pickup rolls back together")
	choice = overlay(ChoiceOverlay)
	choice._on_choose(0)
	await frames()
	await finish_binding()
	check(GameState.relic_binds.has("slab"), "closing glyph picker binds the relic once")

	GameState.start_new_run()
	own_all_but(["strike", "breach"])
	GameState.player_hp = GameState.player_max_hp - 1
	reward = await open_reward(MapNodeData.Type.BOSS)
	check(GameState.player_hp == GameState.player_max_hp and reward._relic_choices.size() == 2, "boss healing caps at maximum; small relic pool still works")
	GameState.start_new_run()
	own_all_but([])
	reward = await open_reward(MapNodeData.Type.BOSS)
	reward._inspect(0)
	check(overlay(ChoiceOverlay) == null and not reward._hud.action_button.disabled, "exhausted relic pool never blocks reward")
	GameState.start_new_run()
	GameState.act_index = 3
	GameState.player_hp = 1
	reward = await open_reward(MapNodeData.Type.BOSS)
	check(overlay(ChoiceOverlay) == null and GameState.player_hp == 1, "final act retains victory flow without another inter-act reward")

	GameState.start_new_run()
	own_all_but(["strike", "breach", "buckler", "powerbank"])
	GameState.gold = 100
	Router.goto("res://src/screens/shop_screen.gd")
	await frames()
	var shop: Control = Router.current
	var relics: Array = shop._offers.filter(func(o): return o.kind == "relic")
	check(relics.size() == 3 and relics.all(func(o): return o.price == Relics.price(o.relic)), "classic shop stocks three random relics at tier prices")
	var id: String = relics[0].relic
	var relic_price: int = relics[0].price
	shop._buy(shop._offers.find(relics[0]))
	await frames()
	check(GameState.has_relic(id) and GameState.gold == 100 - relic_price and not shop._offers.any(func(o): return o.kind == "relic" and o.relic == id), "relic purchase consumes exact gold and stock")
	shop._refresh_stock()
	await frames()
	var stock := var_to_bytes(SaveCodec.new().pack({"offers": shop._offers}))
	check(GameState.gold == 95 - relic_price and shop._offers.any(func(o): return o.kind == "relic" and o.relic != id), "5 gold refresh restocks unowned relic")
	await save_and_resume()
	check(GameState.gold == 95 - relic_price and var_to_bytes(SaveCodec.new().pack({"offers": Router.current._offers})) == stock, "refresh result and cost survive resume exactly")

	# Render the real three-way choice and seven-slot shop at common landscape sizes.
	for window_size in [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(960, 432), Vector2i(844, 390), Vector2i(640, 360)]:
		get_window().size = window_size
		await frames(10)
		GameState.start_new_run()
		GameState.player_hp = 1
		reward = await open_reward(MapNodeData.Type.BOSS)
		choice = overlay(ChoiceOverlay)
		await frames(10)
		check(reward.get_global_rect().encloses(choice._panel.get_global_rect()), str(window_size) + " three-way relic dialog fits")
		var choice_buttons: Array = choice.relic_choice_buttons()
		check(choice_buttons.size() == 3 and choice_buttons.all(func(button): return choice._panel.get_global_rect().encloses(button.get_global_rect())), str(window_size) + " all three relic buttons visible together")
		await shot("boss-%dx%d" % [window_size.x, window_size.y])
		GameState.start_new_run()
		GameState.gold = 100
		Router.goto("res://src/screens/shop_screen.gd")
		await frames(12)
		shop = Router.current
		var bounds := shop.get_global_rect()
		var factor := float(window_size.y) / shop.size.y
		check(shop._cards.all(func(card): return bounds.encloses(card.get_global_rect()) and card.size.x * factor >= 47.5 and card.size.y * factor >= 47.5), str(window_size) + " eleven shop targets fit and retain touch sizes")
		for button in [shop._hud.action_button, shop._hud.secondary_button, shop._hud.tertiary_button]:
			check(bounds.encloses(button.get_global_rect()) and button.size.y * factor >= 47.5, str(window_size) + " shop action fits and retains 48px height")
		await shot("shop-%dx%d" % [window_size.x, window_size.y])
	SaveManager.clear_run()
	SaveManager.enabled = false
	Router.release_host(self)
	print("[classic_relic_test] PASS=%d FAIL=%d TOTAL=%d" % [checks - failures, failures, checks])
	get_tree().quit(1 if failures else 0)
