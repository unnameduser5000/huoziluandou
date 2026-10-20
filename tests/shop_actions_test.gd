extends Control
## Real shop button flow, transaction persistence and landscape visibility.
var checks := 0
var failures := 0
const QA := "res://docs/qa/shop-five-cards-2026-10-19/"


func check(ok: bool, message: String) -> void:
	checks += 1
	if ok: print("PASS ", message)
	else:
		failures += 1
		push_error(message)


func frames(n := 8) -> void:
	for i in n: await get_tree().process_frame


func click(button: Control) -> void:
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	await frames(2)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = down
		get_viewport().push_input(event, true)
		await frames(2)


func tap(button: Control) -> void:
	for down in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = get_viewport().get_final_transform() * button.get_global_rect().get_center()
		event.pressed = down
		Input.parse_input_event(event)
		await frames(2)


func shot(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"): return
	await frames(12)
	RenderingServer.force_draw(false)
	check(get_viewport().get_texture().get_image().save_png(QA + name + ".png") == OK, "capture " + name)


func _ready() -> void:
	Settings.storage_path = "user://shop-actions-settings.cfg"
	Settings.reduced_motion = true
	SaveManager.activate("user://shop-actions-regression.save")
	Router.host = self
	_run.call_deferred()


func _run() -> void:
	GameState.start_new_run()
	GameState.gold = 4
	Router.goto("res://src/screens/shop_screen.gd")
	await frames()
	var shop = Router.current
	check(shop._hud.tertiary_button.disabled, "refresh disabled below five gold")
	check(shop._offers.filter(func(o): return o.kind == "buy_char").size() == 5, "shop stocks five cards")
	var items: Array = shop._offers.filter(func(o): return o.kind == "relic")
	check(items.size() == 3 and items[0].relic != items[1].relic and items[1].relic != items[2].relic and items[0].relic != items[2].relic, "stock contains three distinct random relics")
	check(items.all(func(o): return o.price == Relics.price(o.relic) and not GameState.has_relic(o.relic)), "stock prices follow relic rarity and exclude owned relics")
	for relic_id in RelicArt.TEXTURES:
		var specimen := preload("res://src/ui/object_stage/relic_specimen.gd").build(shop._showcase.stage, relic_id, Relics.price(relic_id))
		check(specimen.get_meta("relic_id") == relic_id and specimen.get_meta("modelled_parts", 0) > 2, "build complete relic model: " + relic_id)
		specimen.free()
	shop._open_relic_purchase(999)
	shop._open_relic_purchase(0)
	check(not shop._has_shop_dialog(), "only an actual stocked relic can enter purchase confirmation")
	var prices := {}
	var selections := {}
	for seed_value in 20:
		GameState.rng.seed = seed_value
		var before_rng := GameState.rng.state
		var rolled: Array = shop._roll_relic()
		check(GameState.rng.state == before_rng, "stock roll does not advance gameplay RNG")
		for o in rolled: prices[o.price] = true; selections[o.relic] = true
	check(prices.has(35) and prices.has(50) and prices.has(70) and selections.size() > 3, "seed sweep covers distinct stock and all three price tiers")
	var index: int = shop._offers.find_custom(func(o): return o.kind == "relic")
	shop._open_relic_purchase(index)
	check(not shop._has_shop_dialog() and GameState.gold == 4, "insufficient gold cannot purchase")
	GameState.gold = 200
	shop._refresh()
	var offer: Dictionary = shop._offers[index]
	var id: String = offer.relic
	var cost: int = offer.price
	var stock := var_to_bytes(SaveCodec.new().pack({"offers": shop._offers}))
	var rng_state := GameState.rng.state
	shop._cards[index].clicked.emit()
	var confirm: ChoiceOverlay = shop._shop_overlay
	check(confirm.cfg.title.contains(Relics.name_of(id)) and confirm.cfg.options[1].text.contains(str(cost)), "clicked specimen opens its own description and exact price")
	shop._refresh_stock()
	shop._purchase_selected()
	check(GameState.gold == 200 and var_to_bytes(SaveCodec.new().pack({"offers": shop._offers})) == stock, "confirmation blocks underlying refresh and purchase")
	confirm._on_choose(0)
	check(not GameState.has_relic(id) and GameState.gold == 200 and GameState.rng.state == rng_state, "cancel changes no ownership, gold or RNG")
	shop._open_relic_purchase(index)
	confirm = shop._shop_overlay
	confirm._on_choose(1)
	confirm._on_choose(1)
	await frames()
	for child in shop.get_children():
		if child is CollectionOverlay: child._close()
	await frames()
	check(GameState.has_relic(id) and GameState.gold == 200 - cost, "confirmed specimen purchase debits its own price exactly once")
	check(shop._offers.filter(func(o): return o.kind == "relic").size() == 2 and not shop._offers.any(func(o): return o.kind == "relic" and o.relic == id), "bought specimen leaves a gap and other stock remains")
	var kept_slots: Array = shop._offers.filter(func(o): return o.kind == "relic").map(func(o): return o.display_slot)
	check(not kept_slots.has(offer.display_slot), "purchased display slot is not replaced")
	await shot("sold-slot")
	check(SaveManager.checkpoint(), "purchase checkpoint accepted")
	SaveManager.flush()
	check(SaveManager.resume_run(), "purchase checkpoint resumes")
	await frames()
	shop = Router.current
	check(GameState.gold == 200 - cost and GameState.has_relic(id) and shop._offers.filter(func(o): return o.kind == "relic").map(func(o): return o.display_slot) == kept_slots, "ownership, prices and empty slot survive resume")
	var services: Array = shop._offers.filter(func(o): return o.kind not in ["buy_char", "relic"])
	shop._refresh_stock()
	check(GameState.gold == 195 - cost and shop._offers.filter(func(o): return o.kind not in ["buy_char", "relic"]) == services, "first refresh spends five and preserves services")
	check(shop._offers.filter(func(o): return o.kind == "relic").size() == 3 and not shop._offers.any(func(o): return o.kind == "relic" and o.relic == id), "refresh restores three stock items without owned relics")
	check(shop.refresh_cost() == 10 and shop._hud.tertiary_button.model.price_label.text == "10钱" and shop._hud.tertiary_button._caption.text == "换货\n10钱", "refresh model and visible label agree on the ten-copper fee")
	check(SaveManager.checkpoint(), "refresh count checkpoint accepted")
	SaveManager.flush()
	check(SaveManager.resume_run(), "refresh count checkpoint resumes")
	await frames()
	shop = Router.current
	check(shop.refresh_cost() == 10, "resume preserves next refresh fee")
	GameState.gold = 100
	shop._refresh_stock()
	check(GameState.gold == 90 and shop.refresh_cost() == 15, "second refresh costs ten and advances fee to fifteen")
	# Exhausted and small pools remain finite, never expose a full catalogue.
	GameState.relics = Relics.DEFS.keys()
	check(shop._roll_relic().is_empty(), "owned collection produces no stock")
	GameState.relics.erase("slab")
	check(shop._roll_relic().size() == 1 and shop._roll_relic()[0].relic == "slab", "one remaining relic produces one sale item")
	shop._refresh_stock()
	GameState.gold = 100
	shop._refresh()
	index = shop._offers.find_custom(func(o): return o.kind == "relic")
	shop._open_relic_purchase(index)
	shop._shop_overlay._on_choose(1)
	await frames()
	var picker: CollectionOverlay
	for child in shop.get_children():
		if child is CollectionOverlay: picker = child
	check(picker != null and shop._busy and GameState.gold == 30, "rare bound relic costs seventy and opens glyph picker")
	shop._refresh_stock()
	check(GameState.gold == 30, "binding blocks refresh charges")
	if picker != null: picker._close()
	await frames()
	check(GameState.relic_binds.has("slab") and not shop._busy, "closing picker completes binding and unlocks shop")
	for window_size in [Vector2i(1920, 1080), Vector2i(960, 432), Vector2i(640, 360)]:
		get_window().size = window_size
		await frames()
		GameState.start_new_run()
		GameState.gold = 200
		Router.goto("res://src/screens/shop_screen.gd")
		await frames(15)
		shop = Router.current
		# Capture all three price tiers as a deterministic visual fixture.
		var fixture := ["clean", "strike", "slab"]
		var item_index := 0
		for o in shop._offers:
			if o.kind == "relic":
				o.relic = fixture[item_index]
				o.price = Relics.price(o.relic)
				item_index += 1
		shop._refresh()
		await frames()
		var bounds: Rect2 = shop.get_global_rect()
		var scale_factor: float = float(window_size.y) / shop.size.y
		check(shop._offers.filter(func(o): return o.kind == "buy_char").size() == 5, "all five cards remain visible in this viewport")
		check(shop._cards.all(func(card): return bounds.encloses(card.get_global_rect()) and card.size.x * scale_factor >= 47.5 and card.size.y * scale_factor >= 47.5), "all eleven wares fit with 48px targets")
		var glyph_cards: Array = shop._cards.filter(func(card): return card.character != null)
		for a in range(glyph_cards.size() - 1):
			check(not glyph_cards[a].get_global_rect().intersects(glyph_cards[a + 1].get_global_rect()), "adjacent card targets do not overlap")
		check(shop._showcase.stage.shop_actions.size() == 1 and shop._hud.tertiary_button.model.title_label.text == "换货", "one small refresh dial replaces the giant generic buttons")
		for i in shop._cards.size():
			if shop._offers[i].kind != "relic": continue
			var card: Control = shop._cards[i]
			var specimen: Node3D = shop._showcase.stage.objects[i]
			check(bounds.encloses(card.get_global_rect()) and card.size.x * scale_factor >= 47.5 and card.size.y * scale_factor >= 47.5, "individual relic retains 48px target: " + shop._offers[i].relic)
			check(specimen.get_meta("relic_id") == shop._offers[i].relic and specimen.get_meta("modelled_parts", 0) > 2, "displayed specimen matches offered identity")
		check(shop._hud.tertiary_button.size.x / shop.size.x < 0.13 and shop._hud.tertiary_button.size.y * scale_factor >= 47.5, "refresh dial is compact with accessible hit target")
		await shot("shop-%dx%d" % [window_size.x, window_size.y])
		for i in shop._cards.size():
			if shop._offers[i].kind != "buy_char": continue
			await click(shop._cards[i])
			check(shop._selected == i and not shop._has_shop_dialog(), "mouse inspects the correct one of five cards")
		index = shop._offers.find_custom(func(o): return o.kind == "relic")
		await click(shop._cards[index])
		check(shop._has_shop_dialog(), "actual mouse click selects displayed relic")
		if not shop._has_shop_dialog(): continue
		await shot("purchase-%dx%d" % [window_size.x, window_size.y])
		shop._shop_overlay._on_choose(0)
		await frames()
		await click(shop._hud.tertiary_button)
		check(GameState.gold == 195 and shop.refresh_cost() == 10, "mouse activates compact refresh exactly once (gold=%d, next=%d)" % [GameState.gold, shop.refresh_cost()])
		await shot("refreshed-%dx%d" % [window_size.x, window_size.y])
		index = shop._offers.find_custom(func(o): return o.kind == "relic")
		await tap(shop._cards[index])
		check(shop._has_shop_dialog(), "touch selects physical relic")
		if shop._has_shop_dialog(): shop._shop_overlay._on_choose(0)
		await frames()
		shop._cards[index].grab_focus()
		for down in [true, false]:
			var key := InputEventKey.new()
			key.keycode = KEY_ENTER
			key.pressed = down
			get_viewport().push_input(key, true)
			await frames(2)
		check(shop._has_shop_dialog(), "keyboard activates focused relic")
		if shop._has_shop_dialog(): shop._shop_overlay._on_choose(0)
	# Old saved shelves keep their inventory and migrate service/relic slots once.
	var legacy_offers: Array = []
	var seen_chars := 0
	for o in shop._offers:
		if o.kind == "buy_char":
			if seen_chars >= 3: continue
			seen_chars += 1
		var old: Dictionary = o.duplicate()
		if old.kind != "buy_char": old.display_slot = int(old.display_slot) - 2
		legacy_offers.append(old)
	Router.goto("res://src/screens/shop_screen.gd", {"_saved_screen": {"offers": legacy_offers, "refresh_count": 2}})
	await frames()
	shop = Router.current
	check(shop._offers.filter(func(o): return o.kind == "buy_char").size() == 3 and shop.refresh_cost() == 15, "legacy save keeps old inventory and refresh fee")
	check(shop._offers.filter(func(o): return o.kind == "relic").all(func(o): return o.display_slot >= 8 and o.display_slot <= 10) and shop._offers.filter(func(o): return o.kind == "copy")[0].display_slot == 6, "legacy service and relic slots migrate without conflicts")
	check(SaveManager.checkpoint(), "migrated shelf checkpoint accepted")
	SaveManager.flush()
	check(SaveManager.resume_run(), "migrated shelf resumes")
	await frames()
	shop = Router.current
	check(shop._offers.filter(func(o): return o.kind == "relic").all(func(o): return o.display_slot >= 8 and o.display_slot <= 10), "saved layout does not migrate twice")
	shop._refresh_stock()
	check(shop._offers.filter(func(o): return o.kind == "buy_char").size() == 5, "refresh upgrades the legacy shelf to five cards")
	SaveManager.clear_run()
	SaveManager.enabled = false
	Router.release_host(self)
	print("[shop_actions_test] PASS=%d FAIL=%d TOTAL=%d" % [checks - failures, failures, checks])
	get_tree().quit(1 if failures else 0)
