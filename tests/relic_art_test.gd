extends Control
## Asset integrity and real-screen integration for the shop specimen renders.
const QA := "res://docs/qa/relic-textures-2026-10-19/"
var passed := 0
var failed := 0


func check(ok: bool, message: String) -> void:
	if ok: passed += 1; print("PASS ", message)
	else: failed += 1; push_error(message)


func frames(n := 10) -> void:
	for i in n: await get_tree().process_frame


func choice() -> ChoiceOverlay:
	for child in Router.current.get_children():
		if child is ChoiceOverlay and not child.is_queued_for_deletion(): return child
	return null


func pictures(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child.get_script() == preload("res://src/ui/relic_preview.gd"): result.append(child)
		result.append_array(pictures(child))
	return result


func shot(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"): return
	await frames()
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(QA + name + ".png") == OK, "capture " + name)


func _ready() -> void:
	Settings.storage_path = "user://relic-art-test-settings.cfg"
	Settings.reduced_motion = true
	SaveManager.activate("user://relic-art-test.save")
	Router.host = self
	_run.call_deferred()


func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/relics/icons/manifest.json"))
	for source in ["res://src/ui/object_stage/relic_specimen.gd", "res://src/ui/object_stage/relic_expansion.gd", "res://src/ui/object_stage/relic_mesh.gd", "res://src/ui/object_stage/relic_pigment.gdshader", "res://src/ui/relic_art.gd", "res://src/ui/relic_preview.gd", "res://src/tools/bake_relic_icons.gd"]:
		check(manifest.get("sources", {}).get(source, "") == FileAccess.get_sha256(source), source.get_file() + " matches the current compendium render sources")
	check(RelicArt.TEXTURES.size() == Relics.DEFS.size() and manifest.icons.size() == Relics.DEFS.size() and RelicArt.TEXTURES.keys().all(func(id): return Relics.DEFS.has(id)), "all current icons map to valid upstream relic IDs")
	var hashes: Array = []
	var provider := preload("res://src/ui/object_stage/object_stage.gd").new()
	var specimen_script := preload("res://src/ui/object_stage/relic_specimen.gd")
	for id in RelicArt.TEXTURES:
		var texture := RelicArt.texture(id)
		check(texture != null and texture.get_size() == Vector2(1024, 1024), id + " imports at 1024 square")
		var png := texture.get_image()
		check(not png.is_invisible() and png.get_pixel(0, 0).a == 0 and png.get_pixel(1023, 1023).a == 0, id + " has visible art on transparent background")
		var entry: Dictionary = manifest.icons.filter(func(item): return item.id == id)[0]
		var digest := FileAccess.get_sha256(entry.path)
		check(entry.sha256 == digest and not hashes.has(digest), id + " has its own intact specimen render")
		hashes.append(digest)
		var specimen := specimen_script.build(provider, id, Relics.price(id))
		check(not specimen.get_meta("display_plinth", true) and absf(specimen_script.bounds_of(specimen).position.y) < 0.001, id + " stands directly on the counter without a display plinth")
		check(int(specimen.get_meta("modelled_parts")) > specimen.get_child_count() and specimen.get_child_count() <= 12, id + " keeps authored components batched into at most twelve material surfaces")
		specimen.free()
	provider.free()
	check(RelicArt.texture("unknown") == null, "unknown relic cannot display an unrelated icon")
	get_window().size = Vector2i(1280, 720)
	GameState.start_new_run()
	GameState.relics = Relics.DEFS.keys().filter(func(id): return not RelicArt.TEXTURES.has(id))
	GameState.gold = 200
	Router.goto("res://src/screens/shop_screen.gd")
	await frames()
	var shop = Router.current
	await shot("shop-refined-1280")
	var index: int = shop._offers.find_custom(func(o): return o.kind == "relic")
	var id: String = shop._offers[index].relic
	shop._open_relic_purchase(index)
	await frames()
	var dialog := choice()
	var art := pictures(dialog)
	check(art.size() == 1 and art[0].specimen.get_meta("relic_id") == id, "purchase confirmation depicts the exact stocked 3D relic")
	await shot("purchase-1280")
	dialog._on_choose(0)
	await frames()
	check(not GameState.has_relic(id) and GameState.gold == 200, "previewing art leaves purchase and gold unchanged")
	for window_size in [Vector2i(1280, 720), Vector2i(640, 360)]:
		get_window().size = window_size
		GameState.start_new_run()
		GameState.relics = Relics.DEFS.keys().filter(func(id): return not RelicArt.TEXTURES.has(id))
		var node := MapNodeData.new()
		node.type = MapNodeData.Type.BOSS
		Router.goto("res://src/screens/reward_screen.gd", {"node": node})
		await frames(20)
		Router.current._secondary_action()
		await frames()
		dialog = choice()
		var buttons: Array = dialog.relic_choice_buttons()
		check(buttons.size() == 3 and buttons.all(func(b): return b.icon == RelicArt.texture(str(b.get_meta("relic_id", ""))) and b.icon != null), str(window_size) + " reward art matches all three candidates")
		check(buttons.all(func(b): return dialog._panel.get_global_rect().encloses(b.get_global_rect())), str(window_size) + " reward icons keep every choice visible")
		await shot("reward-%d" % window_size.x)
	get_window().size = Vector2i(1280, 720)
	GameState.start_new_run()
	GameState.relics = RelicArt.TEXTURES.keys().slice(0, 15)
	Router.goto("res://src/screens/battle_screen.gd")
	await frames(24)
	Router.current.battle.relics = RelicArt.TEXTURES.keys()
	Router.current._open_battle_guide_ready()
	await frames()
	dialog = choice()
	check(dialog != null and pictures(dialog).size() == Relics.DEFS.size(), "battle guide displays the full owned collection")
	await shot("battle-collection-1280")
	GameState.start_new_run()
	Expedition.start(41)
	GameState.relics = RelicArt.TEXTURES.keys()
	Router.goto("res://src/screens/expedition_map_screen.gd")
	await frames()
	Router.current._open_loadout()
	await frames()
	dialog = choice()
	check(dialog != null and pictures(dialog).size() == Relics.DEFS.size(), "expedition loadout displays the full owned collection")
	await shot("loadout-1280")
	SaveManager.clear_run()
	SaveManager.enabled = false
	Router.release_host(self)
	print("[relic_art_test] PASS=%d FAIL=%d TOTAL=%d" % [passed, failed, passed + failed])
	get_tree().quit(1 if failed else 0)
