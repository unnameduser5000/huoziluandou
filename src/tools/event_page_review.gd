extends Control
## Export the production event page and its actual texture/layout for art review.
const EVENTS = preload("res://src/core/event_effects.gd")
const RUN = preload("res://src/expedition/room_run_state.gd")
const ART = preload("res://src/core/event_art.gd")
const RIDDLES = preload("res://src/data/lantern_riddles.gd")
const SHEFU = preload("res://src/data/shefu_rewards.gd")
const PROFILES := {"desktop":Vector2i(1280,720), "phone":Vector2i(844,390)}
var output := "res://docs/qa/event-art-review-2026-10-20"
var limit := 0
var records: Array = []
var run: RefCounted


func _ready() -> void:
	SaveManager.enabled = false
	GameState.set_meta("courtyard_preview",true)
	Settings.reduced_motion = true
	AudioServer.set_bus_mute(0,true)
	Engine.max_fps = 120
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		if argument.begins_with("--limit="): limit = int(argument.trim_prefix("--limit="))
	Router.host = self
	_run.call_deferred()


func frames(count := 6) -> void:
	for index in count: await get_tree().process_frame


func source_hashes() -> Dictionary:
	var result := {}
	for path in ["res://src/screens/event_screen.gd","res://src/data/event_catalog.gd",ART.MANIFEST,"res://src/core/event_art.gd"]:
		result[path] = FileAccess.get_sha256(path)
	return result


func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Event review requires a real renderer, not --headless")
		get_tree().quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.path_join("screens")))
	var ignore := FileAccess.open(output.path_join(".gdignore"),FileAccess.WRITE)
	ignore.close()
	var hashes := source_hashes()
	run = RUN.new()
	run.reset({"seed":20261020,"layout":"node_graph"})
	var slots: Array = run.graph.rooms.keys().filter(func(id): return run.graph.rooms[id].kind=="event")
	if slots.is_empty():
		push_error("Preview fixture has no event slot"); get_tree().quit(2); return
	run.current_room = slots[0]
	GameState.player_max_hp = 60; GameState.player_hp = 45; GameState.gold = 60
	GameState.relic_counters["life_debt"] = 8
	var definitions: Array = EVENTS.all()
	if limit>0: definitions = definitions.slice(0,limit)
	var number := 0
	for definition: Dictionary in definitions:
		var event := definition.duplicate(true)
		var side := RandomNumberGenerator.new(); side.seed = hash("event-review:"+str(event.id))
		event = RIDDLES.fill(event,side)
		event = SHEFU.fill(event,side)
		var nodes: Array = ["start"]
		for node_id: String in event.get("nodes",{}):
			if node_id!="start": nodes.append(node_id)
		for node_id: String in nodes:
			number += 1
			run.event_data = event.duplicate(true); run.event_node = node_id; run.phase = "event"
			run.pending_event_effect = {}; run.pending_event_relics = []
			GameState.act_index = int((event.get("acts",[1]) as Array)[0])
			run._sync_content()
			var current: Dictionary = run.current_event()
			var entry := {"number":number,"id":str(event.id),"node":node_id,"title":str(current.title),
				"body":str(current.body),"options":current.options.map(func(option): return str(option.text)),
				"acts":event.get("acts",[]),"captures":{},"issues":[]}
			var configured := str(current.get("illustration",definition.get("illustration","")))
			var manifest := str(ART.entry(str(event.id)).get("path",""))
			if not manifest.is_empty() and not manifest.begins_with("res://"): manifest = "res://"+manifest
			entry["configured_path"] = configured
			entry["manifest_path"] = manifest
			entry["expected_path"] = configured if not configured.is_empty() else ART.path_for(str(event.id))
			entry["style"] = str(current.get("illustration_style",ART.style_for(str(event.id))))
			for profile: String in PROFILES:
				get_window().size = PROFILES[profile]
				await frames(4)
				Router.goto("res://src/screens/event_screen.gd",{"room_run":true})
				await frames(8)
				var screen: Control = Router.current
				var texture: Texture2D = screen._art.texture
				entry["runtime_path"] = texture.resource_path if texture!=null else ""
				entry["art_visible"] = screen._art.is_visible_in_tree()
				if entry.runtime_path!=entry.expected_path: entry.issues.append(profile+": 实际图片与解析路径不一致")
				if texture==null: entry.issues.append(profile+": 没有实际图片")
				if not configured.is_empty() and not manifest.is_empty() and configured!=manifest and not entry.issues.has("目录与清单指向不同文件"):
					entry.issues.append("目录与清单指向不同文件")
				var filename := "%02d-%s-%s-%s.png" % [number,event.id,node_id,profile]
				var snapshot: Dictionary = await capture(screen,filename)
				var bar: VScrollBar = screen._scroll.get_v_scroll_bar()
				if bar.max_value-bar.page>1:
					snapshot["scroll_needed"] = true
					screen._scroll.scroll_vertical = int(bar.max_value)
					await frames(4)
					var bottom_name := filename.trim_suffix(".png")+"-bottom.png"
					await capture(screen,bottom_name)
					snapshot["bottom_screenshot"] = "screens/"+bottom_name
				entry.captures[profile] = snapshot
				if not snapshot.art_in_view: entry.issues.append(profile+": 插画区域超出首屏")
				if snapshot.art_copy_overlap: entry.issues.append(profile+": 插画与文字区域重叠")
			records.append(entry)
			print("[event_page_review] captured %02d %s/%s -> %s" % [number,event.id,node_id,entry.runtime_path])
	var report := {"schema":1,"captured_at":Time.get_datetime_string_from_system(),"renderer":RenderingServer.get_current_rendering_method(),
		"event_count":definitions.size(),"page_count":records.size(),"entries":records,"source_hashes":hashes,
		"source_hashes_after":source_hashes(),"fixture":{"hp":45,"max_hp":60,"coins":60,"life_debt":8},
		"scope":"实际事件页入口与所有目录文本节点；不结算选项，不更改用户存档。手机为桌面渲染器模拟尺寸。"}
	var file := FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")+"\n"); file.close()
	print("[event_page_review] DONE EVENTS=%d PAGES=%d OUTPUT=%s" % [definitions.size(),records.size(),output])
	Music.stop()
	get_tree().quit()


func pixel_rect(control: Control, scale_factor: Vector2) -> Array:
	var rect := control.get_global_rect()
	return [rect.position.x*scale_factor.x,rect.position.y*scale_factor.y,rect.size.x*scale_factor.x,rect.size.y*scale_factor.y]


func capture(screen: Control, filename: String) -> Dictionary:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(output.path_join("screens").path_join(filename))
	if error!=OK: push_error("Cannot save "+filename)
	var scale_factor := Vector2(image.get_size())/get_viewport_rect().size
	var art: Rect2 = screen._art.get_global_rect()
	var image_rect: Rect2 = art
	if screen._art.texture!=null:
		var original: Vector2 = screen._art.texture.get_size()
		var contained := original * minf(art.size.x/original.x,art.size.y/original.y)
		image_rect = Rect2(art.get_center()-contained*.5,contained)
	var choices: Array = []
	for button: Button in screen._buttons: choices.append(pixel_rect(button,scale_factor))
	return {"screenshot":"screens/"+filename,"viewport":[image.get_width(),image.get_height()],
		"art_rect":pixel_rect(screen._art,scale_factor),"copy_rect":pixel_rect(screen._copy,scale_factor),
		"image_rect":[image_rect.position.x*scale_factor.x,image_rect.position.y*scale_factor.y,image_rect.size.x*scale_factor.x,image_rect.size.y*scale_factor.y],
		"choices":choices,"vertical":screen._vertical,"art_in_view":get_viewport_rect().encloses(art),
		"art_copy_overlap":art.intersects(screen._copy.get_global_rect()),"scroll_needed":false}
