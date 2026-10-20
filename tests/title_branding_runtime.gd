extends Node
const OUTPUT := "res://docs/art-concepts/2026-10-19-lianziyu-title"
var failures: Array[String] = []
var checks := 0


func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)


func frames(count: int) -> void:
	for i in count: await get_tree().process_frame


func shot(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT.path_join(name))


func _ready() -> void: exercise.call_deferred()


func exercise() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var saved_motion := Settings.reduced_motion
	Settings.reduced_motion = false
	var random_before: int = GameState.rng.state
	get_window().size = Vector2i(1280,720)
	var main := preload("res://scenes/main.tscn").instantiate(); add_child(main)
	await frames(55)
	var title: Control = Router.current
	check(Router.current_path.ends_with("title_screen.gd"),"normal project startup opens the production title")
	check(ProjectSettings.get_setting("application/config/name")=="炼字狱" and title._wordmark.texture.resource_path.ends_with("lianziyu-wordmark-v1.png"),"project and title use the confirmed game name")
	check(title._wordmark.visible and title._menu.find_children("*","Label",true,false).is_empty(),"transparent calligraphic wordmark replaces the old title and subtitle")
	var image: Image = title._wordmark.texture.get_image()
	check(image.get_pixel(0,0).a<.01,"wordmark has genuine transparency")
	var stage: Node3D = title._courtyard.stage
	check(stage.foreground.lamps.size()==2 and stage.foreground.lamps.all(func(light):return light.shadow_enabled),"both foreground lanterns have actual shadow-casting lights")
	check(stage.foreground.leaves.multimesh.instance_count==52,"settled foreground leaves are instanced geometry")
	check(stage.environment.sky.sky_material.get_shader_parameter("gilt_clouds")!=null,"gilt cloud ornament is bound to sky shading")
	check(GameState.rng.state==random_before,"title rendering leaves gameplay random state untouched")
	var names: Array = title._buttons.map(func(button):return button.text)
	for caption: String in ["开始新冒险","字库图鉴","设置","离开","自定义构筑","字网图谱"]:
		check(names.has(caption),"retains action "+caption)
	var reports: Array = []
	for resolution in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(960,432)]:
		get_window().size = resolution; await frames(25)
		var physical_scale := float(resolution.y)/title.size.y
		for button: Button in title._buttons:
			check(title.get_global_rect().encloses(button.get_global_rect()),"action remains on screen at "+str(resolution)+" "+button.text)
			check(button.size.y*physical_scale>=47.9,"physical touch target at least 48 pixels "+button.text)
		check(not title._wordmark.get_global_rect().intersects(title._menu.get_global_rect()),"wordmark and menu do not overlap "+str(resolution))
		check(not title._utilities.get_global_rect().intersects(title._menu.get_global_rect()),"secondary actions do not overlap main menu "+str(resolution))
		await shot("title-%dx%d.png" % [resolution.x,resolution.y])
		reports.append({"size":str(resolution),"memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC)})
	title._open_settings(); await frames(6)
	check(title._modal_count==1,"settings still opens its shared modal")
	title._on_start(); check(not title._starting,"settings modal blocks underlying start")
	for child in title.get_children():
		if child is SettingsOverlay: child.queue_free()
	await frames(6)
	check(title._modal_count==0,"closing settings restores title actions")
	title._on_start()
	check(title._starting and not title._wordmark.visible and not title._utilities.visible,"existing start transition hides new title layers")
	title._cancel_entry()
	check(not title._starting and title._wordmark.visible and title._ornament.visible and title._utilities.visible,"cancel restores all title layers")
	Settings.reduced_motion = true; Settings.changed.emit(); await frames(3)
	var clock: float = stage.atmosphere.elapsed; await frames(5)
	check(is_equal_approx(clock,stage.atmosphere.elapsed) and not stage.atmosphere.petals.visible,"reduced-motion preference pauses falling leaves")
	get_window().size = Vector2i(1280,720); await frames(8)
	title._wordmark.hide(); title._menu.hide(); title._utilities.hide(); title._ornament.hide()
	await shot("courtyard-no-ui.png")
	var lit: Image = title._courtyard.viewport.get_texture().get_image()
	for light: OmniLight3D in stage.foreground.lamps: light.light_energy = 0.0
	await frames(8); await shot("courtyard-foreground-lights-off.png")
	var unlit: Image = title._courtyard.viewport.get_texture().get_image()
	var light_difference := 0.0; var samples := 0
	for y in range(floori(lit.get_height()*.72),lit.get_height(),8):
		for x in range(floori(lit.get_width()*.12),floori(lit.get_width()*.88),8):
			var a := lit.get_pixel(x,y); var b := unlit.get_pixel(x,y)
			light_difference += absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b); samples += 1
	light_difference /= maxf(1,samples*3)
	check(light_difference>.003,"foreground lamps actually illuminate the terrace in the native renderer")
	var report := {"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),"screens":reports,"foreground_light_rgb_difference":light_difference,"android_device_tested":false}
	FileAccess.open(OUTPUT.path_join("runtime-checks.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	main.queue_free(); await frames(12)
	Settings.reduced_motion = saved_motion; Settings.changed.emit()
	print("[TitleBranding] ",report)
	get_tree().quit(0 if failures.is_empty() else 1)
