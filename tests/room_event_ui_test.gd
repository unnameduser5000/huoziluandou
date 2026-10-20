extends Control
## Current node-map event flow; no title scene, 3D assembly or old drawer API.
const RUN = preload("res://src/expedition/room_run_state.gd")
const EFFECTS = preload("res://src/core/event_effects.gd")
var failures: Array = []
var checks := 0


func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)


func _ready() -> void:
	SaveManager.enabled = false
	GameState.set_meta("courtyard_preview", true)
	Settings.reduced_motion = true
	Engine.max_fps = 240
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_window().size = Vector2i(1280, 720)
	Router.host = self
	_run.call_deferred()


func _run() -> void:
	var run = RUN.new()
	run.reset({"seed":17})
	check(run.layout_kind=="node_graph" and run.travel==null, "default event run uses the node graph")
	var events: Array = run.graph.rooms.keys().filter(func(id): return run.graph.rooms[id].kind=="event")
	check(not events.is_empty(), "generated graph has event nodes")
	if events.is_empty(): finish(); return
	var event_id: String = events[0]
	run._arrive(event_id)
	check(run.phase=="event", "arrival enters event phase")
	check(run.event_data.get("acts",[]).has(GameState.act_index), "drawn event belongs to the current act")
	check(run.seen_events.has(str(run.event_data.id)), "draw records the stable event ID")
	Router.goto(RUN.MAP_SCREEN)
	await frames(8)
	check(Router.current_path.ends_with("event_screen.gd"), "map routes the pending node into the full event screen")
	if not Router.current_path.ends_with("event_screen.gd"): finish(); return
	var screen: Control = Router.current
	check(screen._title.text==str(run.current_event().title), "event screen displays the catalog title")
	check(screen._body.text==str(run.current_event().body), "event screen displays the catalog body")
	check(screen._buttons.size()==run.current_event().options.size(), "all catalog choices are connected")
	check(find_children("*","SubViewport",true,false).is_empty(), "event UI never constructs a 3D viewport")

	# Exercise the real picker and completion route using a known catalog entry.
	run.event_data = EFFECTS.get_event("old_bookshop").duplicate(true)
	run.event_node = "start"
	run._sync_content()
	Router.goto("res://src/screens/event_screen.gd", {"room_run":true})
	await frames(4)
	screen = Router.current
	check(screen._choice_labels[0].text==str(run.current_event().options[0].text), "removal choice uses the catalog action")
	screen._buttons[0].pressed.emit()
	await frames(4)
	check(run.phase=="event_choose", "click enters saved removal phase")
	check(screen._title.text.contains("旧书肆") and screen._body.text.contains("还需 1 枚"), "picker preserves the event context")
	var observed: Dictionary = run.observe()
	check(str(observed.get("event",{}).get("id",""))=="old_bookshop", "headless observation retains the event ID")
	check(int(observed.get("event",{}).get("pending_removal",{}).get("remaining",0))==1, "headless observation retains the remaining target count")
	var picker: CollectionOverlay
	for child in screen.get_children():
		if child is CollectionOverlay and not child.is_queued_for_deletion(): picker = child; break
	check(is_instance_valid(picker), "full event screen opens the current removal picker")
	if not is_instance_valid(picker): finish(); return
	var before: int = GameState.deck_size()
	picker._on_card_clicked(Database.get_character_by_glyph(run.pending_glyphs[0]))
	await frames(4)
	check(run.phase=="map" and run.resolved.has(event_id), "settlement resolves the node and returns to the map")
	check(Router.current_path==RUN.MAP_SCREEN, "completion restores the cached node map")
	check(GameState.deck_size()==before-1, "completion removes exactly one instance")
	finish()


func finish() -> void:
	print("[RoomEventUI] checks=", checks, " failures=", failures)
	Music.stop()
	get_tree().quit(0 if failures.is_empty() else 1)


func frames(count: int) -> void:
	for i in count: await get_tree().process_frame
