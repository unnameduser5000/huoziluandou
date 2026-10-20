extends Control
## Exercise shared HUD/modal stacking through the live node map and event page.
const RUN = preload("res://src/expedition/room_run_state.gd")
const EFFECTS = preload("res://src/core/event_effects.gd")
const QA := "res://docs/qa/modal-layering-2026-10-21"
var passed := 0
var failed := 0
var capture := false
var before := false


func _ready() -> void:
	SaveManager.enabled = false
	GameState.set_meta("courtyard_preview", true)
	Settings.storage_path = "user://modal-layering-test-settings.cfg"
	Settings.reduced_motion = true
	AudioServer.set_bus_mute(0, true)
	Engine.max_fps = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	capture = OS.get_cmdline_user_args().has("--capture")
	before = OS.get_cmdline_user_args().has("--before")
	_run.call_deferred()


func frames(count := 5) -> void:
	for index in count: await get_tree().process_frame


func check(value: bool, message: String) -> void:
	if value: passed += 1; print("PASS ", message)
	else: failed += 1; push_error(message)


func effective_z(item: CanvasItem) -> int:
	var result := item.z_index
	var parent := item.get_parent() as CanvasItem
	if item.z_as_relative and parent != null: result += effective_z(parent)
	return result


func above_header(overlay: Control, bar: Control, label: String) -> void:
	check(effective_z(overlay) > effective_z(bar), label+": modal and shade render above resource buttons")
	var button: Button = bar.buttons.deck
	var motion := InputEventMouseMotion.new()
	motion.position = button.get_global_rect().get_center()
	get_viewport().push_input(motion)
	await frames(2)
	var hovered := get_viewport().gui_get_hovered_control()
	check(hovered != null and (hovered==overlay or overlay.is_ancestor_of(hovered)), label+": resource buttons cannot receive pointer input behind modal")


func shot(label: String) -> void:
	if not capture or DisplayServer.get_name()=="headless": return
	DirAccess.make_dir_recursive_absolute(QA)
	var ignore := FileAccess.open(QA.path_join(".gdignore"),FileAccess.WRITE)
	ignore.close()
	await RenderingServer.frame_post_draw
	var path := QA.path_join(("before-" if before else "after-")+label+".png")
	check(get_viewport().get_texture().get_image().save_png(path)==OK,"capture "+label)


func _run() -> void:
	Router.host = self
	var run: RefCounted = RUN.start(29)
	for page in ["room_map", "event"]:
		if page=="event":
			run.current_room = run.graph.rooms.keys().filter(func(id):return run.graph.rooms[id].kind=="event")[0]
			run.event_data = EFFECTS.get_event("ink_pool").duplicate(true)
			run.event_node = "start"
			run.phase = "event"
			run._sync_content()
		Router.goto("res://src/screens/"+page+"_screen.gd",{"room_run":true})
		await frames(10)
		var screen: Control = Router.current
		var bar: Control = screen.inventory_bar
		for resolution in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(844,390)]:
			get_window().size = resolution
			await frames(12)
			var tag := "%s-%dx%d" % [page,resolution.x,resolution.y]
			var rect := bar.get_global_rect()
			PauseMenu.open()
			await frames()
			var menu: PauseOverlay = PauseMenu._instance
			await above_header(menu,bar,tag+" pause")
			await shot(tag+"-pause")
			menu._open_settings()
			await frames()
			await above_header(menu._settings,bar,tag+" nested settings")
			menu._settings.queue_free()
			await frames()
			check(menu._main_layer.visible,tag+": settings close restores the menu")
			menu._close()
			await frames()
			check(bar.is_visible_in_tree() and bar.get_global_rect().is_equal_approx(rect),tag+": closing menu preserves header placement")
			var point: Vector2 = bar.buttons.deck.get_global_rect().get_center()
			for pressed in [true,false]:
				var click := InputEventMouseButton.new()
				click.button_index = MOUSE_BUTTON_LEFT
				click.pressed = pressed
				click.position = point
				get_viewport().push_input(click)
			await frames()
			check(is_instance_valid(bar._overlay),tag+": resource button responds after menu closes")
			if not is_instance_valid(bar._overlay): continue
			await above_header(bar._overlay,bar,tag+" inventory")
			bar._overlay._close()
			await frames()
			check(not get_tree().paused,tag+": closing inventory restores processing")
		# Directly-added modal paths used by deck tools and event pickers.
		for kind in ["collection","choice","settings"]:
			var overlay: Control
			match kind:
				"collection":
					overlay = CollectionOverlay.new()
					overlay.setup({"title":"字袋","characters":[Database.get_character_by_glyph("火")],"counts":{"火":1}})
				"choice":
					overlay = ChoiceOverlay.new()
					overlay.setup({"title":"选择字","scroll_options":true,"options":[{"text":"返回"}]})
				"settings": overlay = SettingsOverlay.new()
			screen.add_child(overlay)
			await frames()
			await above_header(overlay,bar,page+" direct "+kind)
			await shot(page+"-"+kind)
			overlay.queue_free()
			await frames()
	Router.release_host(self)
	Music.stop()
	print("[modal_layering_test] PASS=%d FAIL=%d" % [passed,failed])
	get_tree().quit(0 if before or failed==0 else 1)
