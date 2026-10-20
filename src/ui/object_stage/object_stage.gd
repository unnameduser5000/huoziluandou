extends Node3D
## Authored set dressing and movable specimens. No gameplay state or game RNG.
const Workshop := preload("res://src/title/courtyard/mesh_workshop.gd")
const PIGMENT := preload("res://src/ui/object_stage/pigment.gdshader")
const OUTLINE := preload("res://src/title/courtyard/ink_outline.gdshader")
const Geometry := preload("res://src/ui/object_stage/counter_assets.gd")
var mode := "reward"
var reward_count := 3
var reward_loot_layout := false
var camera: Camera3D
var objects: Array[Node3D] = []
var rests: Array[Vector3] = []
var object_scales: Array[Vector3] = []
var _materials: Dictionary = {}
var _motions: Dictionary = {}
var _lid: Node3D
var _lantern: Node3D
var _clock := 0.0
var _selected := -1
var _lid_motion: Tween
var shop_actions: Dictionary = {}


func _ready() -> void:
	_build_light()
	if mode == "shop":
		var interior: Node3D = Geometry.get_geometry().shop.instantiate()
		add_child(interior)
		_lantern = interior.get_node("CounterLantern")
	else:
		_build_room()
		_build_counter()
	if mode == "shop": _build_shop_actions()
	Settings.changed.connect(_apply_motion)
	_apply_motion()


func pigment(role: String) -> ShaderMaterial:
	if _materials.has(role): return _materials[role]
	var colors: Array = {
		"ink": ["080f19", "14272e", "294747"],
		"wood": ["101f29", "294448", "52675c"],
		"teal": ["0b2730", "245554", "4c7e6c"],
		"gold": ["393a2b", "9c773f", "d6ba7d"],
		"paper": ["8e8a72", "c8b894", "ecdcbb"],
		"red": ["3d1c29", "8d3039", "bb504a"],
		"stone": ["0a1c26", "294148", "4d6563"],
		"light": ["384c43", "a59264", "e9c58a"],
	}.get(role, ["080f19", "14272e", "294747"])
	var material := ShaderMaterial.new()
	material.shader = PIGMENT
	for i in 3: material.set_shader_parameter(["shade_ink", "pigment_mid", "pigment_light"][i], Color(colors[i]))
	material.set_shader_parameter("grain_texture", preload("res://assets/title/courtyard/materials/weathered_planks_diffuse.jpg"))
	material.set_shader_parameter("grain_amount", 0.04)
	material.set_shader_parameter("grain_scale", 0.8)
	material.set_shader_parameter("local_light_gain", 0.85 if mode == "shop" else 0.30)
	var outline := ShaderMaterial.new()
	outline.shader = OUTLINE
	outline.set_shader_parameter("width_pixels", 0.75)
	material.next_pass = outline
	_materials[role] = material
	return material


func _build_light() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("0b1f2b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("598579")
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.ssao_enabled = RenderingServer.get_current_rendering_method() == "forward_plus"
	environment.ssao_radius = 0.25
	environment.ssao_intensity = 1.0
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -34, -12)
	sun.light_color = Color("ffe1ad")
	sun.light_energy = 0.62 if mode == "shop" else 1.0
	sun.shadow_enabled = true
	sun.shadow_normal_bias = 0.8
	sun.shadow_bias = 0.05
	sun.light_angular_distance = 1.4
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 24
	add_child(sun)
	var glow := OmniLight3D.new()
	glow.position = Vector3(-5, 4, 1)
	glow.light_color = Color("ffb86e")
	glow.light_energy = 2.4
	glow.omni_range = 8
	glow.shadow_enabled = false
	add_child(glow)
	if mode == "shop":
		environment.volumetric_fog_enabled = RenderingServer.get_current_rendering_method() == "forward_plus"
		environment.volumetric_fog_density = 0.009
		environment.volumetric_fog_albedo = Color("9bb4a3")
		environment.volumetric_fog_ambient_inject = 0.15
		var window_light := SpotLight3D.new()
		window_light.name = "LatticeWindowLight"
		window_light.position = Vector3(-8.8, 6.0, 0.5)
		window_light.light_color = Color("ffe6b8")
		window_light.light_energy = 38.0
		window_light.spot_range = 18
		window_light.spot_angle = 32
		window_light.spot_attenuation = 0.45
		window_light.shadow_enabled = true
		window_light.shadow_bias = 0.035
		window_light.shadow_normal_bias = 0.16
		window_light.shadow_blur = 1.2
		window_light.light_volumetric_fog_energy = 0.7
		add_child(window_light)
		window_light.look_at(Vector3(-0.8, 0.6, 0.4))
	camera = Camera3D.new()
	camera.position = Vector3(2.8, 7.5, 13)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 34
	camera.size = 8.4
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0, 1.5, 0))
	var lens := CameraAttributesPractical.new()
	lens.dof_blur_far_enabled = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	lens.dof_blur_far_distance = 17.0
	lens.dof_blur_far_transition = 4.0
	lens.dof_blur_amount = 0.12
	camera.attributes = lens


func _build_room() -> void:
	var w := Workshop.new()
	w.box(Vector3(0, -0.8, 0), Vector3(30, 0.4, 24), pigment("stone"))
	w.box(Vector3(0, 3.5, -4.5), Vector3(22, 8, 0.5), pigment("teal"))
	for x in [-8.0, -5.9, 5.9, 8.0]:
		w.box(Vector3(x, 2.8, -3.7), Vector3(0.32, 7.0, 0.5), pigment("ink"))
		for y in [0.0, 0.3, 4.7, 5.0]:
			w.box(Vector3(x, y, -3.65), Vector3(0.46, 0.12, 0.65), pigment("gold"))
	for y in [0.0, 4.8, 5.3]: w.box(Vector3(0, y, -3.7), Vector3(18, 0.22, 0.5), pigment("wood"))
	# Lattice openings and deep joinery create a readable room beyond the counter.
	for x in [-4.3, 4.3]:
		w.box(Vector3(x, 3.0, -4.12), Vector3(2.5, 3.1, 0.1), pigment("stone"))
		for side in [-1.0, 1.0]:
			w.box(Vector3(x + side * 1.3, 3, -3.96), Vector3(0.13, 3.35, 0.16), pigment("wood"))
		for y in [1.35, 4.65]: w.box(Vector3(x, y, -3.96), Vector3(2.7, 0.14, 0.16), pigment("gold"))
		for j in 6:
			var at: float = x - 1.04 + j * 0.42
			w.box(Vector3(at, 3.0, -3.91), Vector3(0.035, 3.1, 0.04), pigment("wood"))
		for j in 7:
			w.box(Vector3(x, 1.65 + j * 0.43, -3.89), Vector3(2.45, 0.035, 0.04), pigment("wood"))
	# Apothecary drawers, with inset panels and bronze ring pulls.
	for row in 3:
		for col in 7:
			var x := -3.3 + col * 1.10
			var y := 1.5 + row * 0.76
			w.box(Vector3(x, y, -3.72), Vector3(1.03, 0.69, 0.25), pigment("ink"))
			w.box(Vector3(x, y, -3.56), Vector3(0.88, 0.53, 0.10), pigment("wood"))
			w.box(Vector3(x, y, -3.48), Vector3(0.19, 0.085, 0.04), pigment("gold"))
			w.cylinder(Vector3(x, y - 0.10, -3.47), 0.035, 0.08, pigment("gold"))
	for i in 19:
		w.box(Vector3(-11 + i * 1.18, -0.57, 1), Vector3(1.14, 0.035, 18), pigment("stone"))
	w.finish(self)
	_build_lantern(Vector3(-5.8, 4.2, -0.7))


func _build_counter() -> void:
	var w := Workshop.new()
	var width := 14.0 if mode == "shop" else 11.0
	w.box(Vector3(0, -0.10, 0.4), Vector3(width, 1.05, 4.2), pigment("ink"))
	for i in 15:
		w.box(Vector3(0, 0.47, -1.55 + i * 0.28), Vector3(width + 0.22, 0.13, 0.26), pigment("wood"))
	for z in [-1.72, 2.58]:
		w.box(Vector3(0, 0.47, z), Vector3(width + 0.5, 0.25, 0.18), pigment("ink"))
		w.box(Vector3(0, 0.61, z), Vector3(width + 0.3, 0.025, 0.035), pigment("gold"))
	for x in [-width * 0.48, width * 0.48]:
		w.box(Vector3(x, 0.32, 0.4), Vector3(0.22, 0.6, 4.5), pigment("gold"))
	for i in 8:
		var x := -width * 0.43 + i * width * 0.12
		w.box(Vector3(x, -0.10, 2.52), Vector3(width * 0.10, 0.62, 0.08), pigment("teal"))
		w.box(Vector3(x, -0.10, 2.58), Vector3(width * 0.075, 0.44, 0.055), pigment("wood"))
		w.box(Vector3(x, -0.10, 2.62), Vector3(0.22, 0.24, 0.035), pigment("gold"), Vector3(0, 0, PI / 4))
	if mode == "reward":
		# A hinged type case, open toward the viewer; the lid is a physical backdrop.
		w.box(Vector3(0, 0.76, -0.15), Vector3(9.3, 0.35, 2.75), pigment("ink"))
		for x in _case_partitions(): w.box(Vector3(x, 0.98, -0.1), Vector3(0.10, 0.17, 2.8), pigment("gold"))
		_build_lid()
		for x in [-3.8, 3.8]:
			w.box(Vector3(x, 0.88, -1.55), Vector3(0.5, 0.18, 0.34), pigment("gold"))
	else:
		w.box(Vector3(-1.4, 0.57, 0.2), Vector3(8.7, 0.045, 2.55), pigment("red"))
		# A raised back ledge carries five smaller letter specimens.
		w.box(Vector3(-1.1, 0.83, -0.30), Vector3(9.05, 0.44, 1.12), pigment("wood"))
		w.box(Vector3(-1.1, 1.055, -0.30), Vector3(9.14, 0.035, 1.18), pigment("gold"))
		for x in [-5.62, 2.82]: w.box(Vector3(x, 0.61, 0.2), Vector3(0.04, 0.015, 2.5), pigment("gold"))
		# Wrapped books, inkstone, brush pot and stacked coin disks.
		for i in 4:
			w.box(Vector3(-5.85, 0.75 + i * 0.16, -1.15), Vector3(1.1, 0.12, 0.66), pigment("paper"))
			w.box(Vector3(-5.85, 0.83 + i * 0.16, -1.15), Vector3(1.16, 0.04, 0.72), pigment("red" if i % 2 == 0 else "teal"))
		w.box(Vector3(5.7, 0.65, 1.5), Vector3(1.2, 0.16, 0.7), pigment("ink"))
		w.cylinder(Vector3(5.9, 1.05, -1.1), 0.30, 0.95, pigment("wood"), 0.88)
		for i in 7:
			w.beam(Vector3(5.72 + i * 0.055, 0.9, -1.1), Vector3(5.45 + i * 0.13, 2.2 + sin(i) * 0.2, -1.1), 0.045, 0.045, pigment("gold"))
		for i in 9: w.cylinder(Vector3(3.4 + (i % 3) * 0.15, 0.65 + (i / 3) * 0.08, 1.8), 0.12, 0.065, pigment("gold"))
	w.finish(self)
	if mode == "shop": _build_keeper()
	var sign := Workshop.new()
	sign.box(Vector3(0, 4, -3.62), Vector3(4.3 if mode == "reward" else 2.4, 0.94, 0.16), pigment("ink"))
	sign.box(Vector3(0, 4, -3.51), Vector3(4.1 if mode == "reward" else 2.2, 0.79, 0.04), pigment("wood"))
	sign.finish(self)
	var plaque := _text("字 肆" if mode == "shop" else "字 归 有 主", 64, Color("cfad71"), 0.012)
	plaque.position = Vector3(0, 4.0, -3.43)
	add_child(plaque)


func _build_lid() -> void:
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.9, -1.55)
	_lid.rotation.x = -0.30
	add_child(_lid)
	var w := Workshop.new()
	w.box(Vector3(0, 1.4, 0), Vector3(9.4, 2.9, 0.24), pigment("wood"))
	w.box(Vector3(0, 1.4, 0.17), Vector3(8.9, 2.45, 0.10), pigment("teal"))
	for y in [0.08, 2.73]: w.box(Vector3(0, y, 0.25), Vector3(9.1, 0.055, 0.035), pigment("gold"))
	for x in [-4.47, 4.47]: w.box(Vector3(x, 1.4, 0.25), Vector3(0.06, 2.7, 0.035), pigment("gold"))
	for x in [-3.0, 0.0, 3.0]:
		w.box(Vector3(x, 1.4, -0.15), Vector3(0.3, 2.8, 0.08), pigment("gold"))
	w.finish(_lid)


func open_case() -> void:
	if _lid == null or Settings.reduced_motion: return
	_lid.rotation.x = PI * 0.48
	_lid_motion = create_tween()
	_lid_motion.tween_property(_lid, "rotation:x", -0.30, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _build_shop_joinery() -> void:
	var modules := Node3D.new()
	modules.name = "ShopJoinery"
	add_child(modules)
	var w := Workshop.new()
	# A real open side window filters the spotlight onto the counter.
	for z in [-2.2, 2.2]:
		w.box(Vector3(-7.5, 4.2, z), Vector3(0.28, 4.6, 0.26), pigment("ink"))
		w.box(Vector3(-7.32, 4.2, z), Vector3(0.06, 4.4, 0.045), pigment("gold"))
	for y in [1.9, 6.5]:
		w.box(Vector3(-7.5, y, 0), Vector3(0.32, 0.24, 4.65), pigment("wood"))
	for i in 8:
		var z := -1.9 + i * 0.54
		w.box(Vector3(-7.5, 4.2, z), Vector3(0.12, 4.35, 0.075), pigment("wood"))
	for y in [2.65, 3.5, 4.35, 5.2, 6.05]:
		w.box(Vector3(-7.5, y, 0), Vector3(0.12, 0.075, 4.35), pigment("wood"))
	# Stepped corner brackets, mortises and a restrained carved apron repeat
	# the same construction across the counter, sign and cabinet.
	for x in [-6.8, 6.8]:
		for step in 3:
			w.box(Vector3(x, 0.22 - step * 0.14, 2.62 - step * 0.09), Vector3(0.42 + step * 0.22, 0.12, 0.18), pigment("wood"))
		for z in [-1.45, 2.3]:
			w.box(Vector3(x, 0.59, z), Vector3(0.32, 0.035, 0.32), pigment("gold"))
			for side in [-1.0, 1.0]:
				w.box(Vector3(x + side * 0.10, 0.62, z), Vector3(0.025, 0.025, 0.20), pigment("ink"))
	for i in 8:
		var x := -6.0 + i * 1.72
		w.box(Vector3(x, -0.13, 2.66), Vector3(0.62, 0.30, 0.045), pigment("ink"))
		for sign_value in [-1.0, 1.0]:
			w.box(Vector3(x + sign_value * 0.22, -0.13, 2.70), Vector3(0.025, 0.22, 0.02), pigment("gold"))
			w.box(Vector3(x, -0.13 + sign_value * 0.11, 2.70), Vector3(0.45, 0.025, 0.02), pigment("gold"))
		w.box(Vector3(x, -0.13, 2.72), Vector3(0.11, 0.11, 0.02), pigment("gold"), Vector3(0, 0, PI / 4))
	# Uneven stacks and recessed shelves break up the drawer wall without
	# adding another set of visual targets beside the purchasable specimens.
	for side in [-1.0, 1.0]:
		var x: float = side * 6.65
		w.box(Vector3(x, 2.3, -3.7), Vector3(1.30, 3.7, 0.40), pigment("ink"))
		for y in [0.6, 1.75, 2.9, 4.05]:
			w.box(Vector3(x, y, -3.35), Vector3(1.4, 0.14, 0.82), pigment("wood"))
			w.box(Vector3(x, y + 0.10, -2.96), Vector3(1.40, 0.035, 0.04), pigment("gold"))
		for i in 5:
			w.box(Vector3(x - 0.4 + i * 0.18, 2.2, -3.3), Vector3(0.14, 0.72 + (i % 3) * 0.12, 0.46), pigment("paper" if i % 2 == 0 else "teal"))
			w.box(Vector3(x - 0.4 + i * 0.18, 2.15, -3.05), Vector3(0.10, 0.16, 0.02), pigment("red"))
		for i in 4:
			w.box(Vector3(x + 0.1 * sin(i), 3.03 + i * 0.13, -3.3), Vector3(0.98, 0.10, 0.52), pigment("paper"))
			w.box(Vector3(x + 0.1 * sin(i), 3.10 + i * 0.13, -3.3), Vector3(1.02, 0.025, 0.56), pigment("red" if i == 2 else "teal"))
	for x in [-1.1, 1.1]:
		w.box(Vector3(x, 4.0, -3.38), Vector3(0.16, 0.69, 0.04), pigment("gold"))
		for y in [3.72, 4.28]: w.box(Vector3(x, y, -3.34), Vector3(0.24, 0.09, 0.03), pigment("ink"))
	w.finish(modules)


func _build_keeper() -> void:
	# Characters retain the enemies' ink illustration treatment. The sprite lives
	# in the world so stock and counter geometry still occlude it naturally.
	var portrait := Sprite3D.new()
	portrait.name = "ShopkeeperPortrait"
	portrait.texture = preload("res://assets/characters/shopkeeper/portrait.png")
	portrait.pixel_size = 3.9 / portrait.texture.get_height()
	portrait.position = Vector3(4.7, 2.4, -2.65)
	portrait.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	portrait.shaded = false
	portrait.modulate = Color("dce2d6")
	portrait.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	portrait.alpha_scissor_threshold = 0.4
	portrait.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	portrait.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	portrait.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(portrait)


func _case_partitions() -> Array:
	var out: Array = [-4.65, 4.65]
	var spacing := minf(2.85, 8.8 / reward_count)
	for i in range(1, reward_count): out.append((i - reward_count * 0.5) * spacing)
	return out


func _build_lantern(at: Vector3) -> void:
	_lantern = Node3D.new()
	_lantern.position = at
	add_child(_lantern)
	var w := Workshop.new()
	w.cylinder(Vector3(0, -0.1, 0), 0.42, 0.95, pigment("red"), 0.78)
	for y in [-0.63, 0.42]: w.cylinder(Vector3(0, y, 0), 0.46, 0.10, pigment("gold"))
	w.beam(Vector3(0, 0.45, 0), Vector3(0, 1.7, 0), 0.04, 0.04, pigment("ink"))
	for i in 8:
		var a := TAU * i / 8.0
		w.box(Vector3(cos(a) * 0.40, -0.1, sin(a) * 0.40), Vector3(0.025, 0.9, 0.025), pigment("gold"))
	for i in 4: w.box(Vector3(-0.09 + i * 0.06, -0.94, 0), Vector3(0.025, 0.58, 0.025), pigment("red"))
	w.finish(_lantern)


func _build_shop_actions() -> void:
	var action := preload("res://src/ui/object_stage/shop_action_3d.gd").new()
	action.name = "StockRefreshDial"
	action.stage = self
	action.position = Vector3(-6.3, 1.5, 1.55)
	action.rotation.x = -0.35
	add_child(action)
	shop_actions.refresh = action


func add_relic(id: String, slot: int, price: int) -> int:
	# Registered relics use their own authored specimen. Keep a readable fallback
	# for future definitions that have not received a model and icon yet.
	if RelicArt.texture(id) == null:
		add_object(Relics.name_of(id).left(1), 0, 0, true)
		var token: Node3D = objects.back()
		token.position = Vector3(-3.9 + slot * 2.8, 0.74, 1.85)
		token.scale = Vector3.ONE * 0.65
		token.set_meta("relic_id", id)
		token.set_meta("price", price)
		rests[-1] = token.position
		object_scales[-1] = token.scale
		return objects.size() - 1
	var node := preload("res://src/ui/object_stage/relic_specimen.gd").build(self, id, price)
	node.position = Vector3(-3.9 + slot * 2.8, 0.74, 1.85)
	add_child(node)
	objects.append(node)
	rests.append(node.position)
	object_scales.append(node.scale)
	return objects.size() - 1


func add_reward_relic(id: String, slot: int, count: int) -> int:
	var index := add_relic(id, slot, 0)
	var node: Node3D = objects[index]
	var bounds := preload("res://src/ui/object_stage/relic_specimen.gd").bounds_of(node)
	var factor := minf(1.35 / maxf(0.01, bounds.size.x), 1.45 / maxf(0.01, bounds.size.y))
	node.scale = Vector3.ONE * factor
	node.position = Vector3(1.5 + (slot - (count - 1) * 0.5) * 2.1, 0.68, 1.6)
	node.set_meta("reward_bounds", bounds)
	rests[index] = node.position
	object_scales[index] = node.scale
	return index


func add_reward_gold(amount: int) -> int:
	var node := preload("res://src/ui/object_stage/reward_coins.gd").build(self, amount)
	node.position = Vector3(-3.25, 0.68, 1.65)
	node.set_meta("reward_bounds", preload("res://src/ui/object_stage/relic_specimen.gd").bounds_of(node))
	add_child(node)
	objects.append(node)
	rests.append(node.position)
	object_scales.append(node.scale)
	return objects.size() - 1


func clear_objects() -> void:
	for motion in _motions.values():
		if motion.is_valid(): motion.kill()
	_motions.clear()
	for object in objects:
		remove_child(object)
		object.queue_free()
	objects.clear()
	rests.clear()
	object_scales.clear()


func remove_object(index: int) -> void:
	if index < 0 or index >= objects.size(): return
	if _motions.has(index) and _motions[index].is_valid(): _motions[index].kill()
	var remaining := {}
	for key in _motions:
		if key != index: remaining[key - 1 if key > index else key] = _motions[key]
	_motions = remaining
	var object := objects[index]
	remove_child(object)
	object.queue_free()
	objects.remove_at(index)
	rests.remove_at(index)
	object_scales.remove_at(index)
	if _selected == index: _selected = -1
	elif _selected > index: _selected -= 1


func add_object(glyph: String, slot: int, rank := 0, service := false) -> int:
	var node := Node3D.new()
	if mode == "shop":
		var library: Resource = Geometry.get_geometry()
		if service:
			node.free()
			node = library.service.instantiate()
		elif rank >= 0 and rank < library.tokens.size():
			node.free()
			node = library.tokens[rank].instantiate()
		else: _author_token(node, rank, service)
	else: _author_token(node, rank, service)
	var shop_slots := [Vector3(-4.6, 1.075, -0.30), Vector3(-2.85, 1.075, -0.30), Vector3(-1.1, 1.075, -0.30), Vector3(0.65, 1.075, -0.30), Vector3(2.4, 1.075, -0.30), Vector3(4.15, 0.65, 0.7), Vector3(5.6, 0.65, 0.7), Vector3(4.8, 1.75, -0.55)]
	node.position = shop_slots[slot % shop_slots.size()] if mode == "shop" else Vector3((slot - (reward_count - 1) * 0.5) * minf(2.85, 8.8 / reward_count), 1.0, 0.1)
	if mode == "reward" and reward_loot_layout:
		node.position.z = -0.65
		node.scale = Vector3.ONE * 0.84
	if mode == "shop" and not service: node.scale = Vector3.ONE * 0.78
	add_child(node)
	if mode == "reward" and reward_loot_layout:
		node.set_meta("reward_bounds", AABB(Vector3(-1.07, 0, -0.23), Vector3(2.14, 2.55, 0.65)))
	var b := 0.53 if service else 1.0
	var text := _text(glyph, 200, Color("14272b") if not service else Color("e4cf9b"), 0.008 * b)
	text.position = Vector3(0, 0.75, 0.24) if service else Vector3(0, 1.42, 0.35)
	node.add_child(text)
	objects.append(node)
	rests.append(node.position)
	object_scales.append(node.scale)
	return objects.size() - 1


func _author_token(node: Node3D, rank: int, service: bool) -> void:
	var w := Workshop.new()
	if service:
		w.cylinder(Vector3(0, 0.10, 0), 0.53, 0.18, pigment("ink"))
		w.cylinder(Vector3(0, 0.53, 0), 0.16, 0.8, pigment("gold"), 0.7)
		var seal := CylinderMesh.new()
		seal.radial_segments = 12
		seal.top_radius = 0.59
		seal.bottom_radius = 0.59
		seal.height = 0.20
		w.add(seal, pigment("gold"), Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.75, 0.08)))
		var face := CylinderMesh.new()
		face.radial_segments = 12
		face.top_radius = 0.52
		face.bottom_radius = 0.52
		face.height = 0.04
		w.add(face, pigment("red"), Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.75, 0.20)))
	else:
		w.box(Vector3(0, 0.07, 0), Vector3(2.14, 0.14, 0.85), pigment("ink"))
		w.box(Vector3(0, 0.15, 0.02), Vector3(1.90, 0.05, 0.8), pigment("gold"))
		w.box(Vector3(0, 1.35, 0), Vector3(2.04, 2.32, 0.42), pigment("wood"))
		w.box(Vector3(0, 1.35, 0.235), Vector3(1.87, 2.14, 0.10), pigment("gold"))
		w.box(Vector3(0, 1.35, 0.30), Vector3(1.76, 2.02, 0.08), pigment("paper"))
		for x in [-0.91, 0.91]:
			for y in [0.32, 2.36]:
				w.box(Vector3(x, y, 0.38), Vector3(0.14, 0.11, 0.045), pigment("gold"))
		for i in rank + 1:
			w.box(Vector3((i - rank * 0.5) * 0.16, 2.43, 0.23), Vector3(0.055, 0.04, 0.05), pigment("gold"))
	w.finish(node)


func _text(value: String, font_size: int, color: Color, pixel_size: float) -> Label3D:
	var label := Label3D.new()
	label.text = value
	label.font = Ink.serif
	label.font_size = int(font_size * 2)
	label.pixel_size = pixel_size * 0.5
	label.modulate = color
	label.outline_size = 0
	label.shaded = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	label.alpha_scissor_threshold = 0.4
	return label


func select_object(index: int) -> void:
	_selected = index
	for i in objects.size():
		if _motions.has(i) and _motions[i].is_valid(): _motions[i].kill()
		var target := rests[i] + Vector3(0, 0.18 if i == index else 0.0, 0)
		if Settings.reduced_motion:
			objects[i].position = target
			objects[i].rotation_degrees = Vector3.ZERO
		else:
			var tw := create_tween().set_parallel(true)
			tw.tween_property(objects[i], "position", target, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(objects[i], "rotation_degrees:z", -2.0 if i == index else 0.0, 0.18)
			_motions[i] = tw


func take(index: int) -> void:
	if index < 0 or index >= objects.size(): return
	if _motions.has(index) and _motions[index].is_valid(): _motions[index].kill()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(objects[index], "position", rests[index] + Vector3(0, 0.8, 2.0), 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(objects[index], "scale", object_scales[index] * 0.55, 0.22)
	_motions[index] = tw


func restore_object(index: int) -> void:
	if index<0 or index>=objects.size(): return
	objects[index].scale = object_scales[index]
	select_object(index)


func _apply_motion() -> void:
	set_process(not Settings.reduced_motion)
	if not Settings.reduced_motion: return
	for action in shop_actions.values(): action.highlight(false)
	if _lid_motion != null and _lid_motion.is_valid(): _lid_motion.kill()
	if _lid != null: _lid.rotation.x = -0.30
	for i in objects.size():
		if _motions.has(i) and _motions[i].is_valid(): _motions[i].kill()
		objects[i].position = rests[i] + Vector3(0, 0.18 if i == _selected else 0.0, 0)
		objects[i].rotation_degrees = Vector3.ZERO
		objects[i].scale = object_scales[i]


func _exit_tree() -> void:
	if Settings.changed.is_connected(_apply_motion): Settings.changed.disconnect(_apply_motion)


func _process(delta: float) -> void:
	_clock += delta
	if _lantern != null: _lantern.rotation.z = sin(_clock * 0.85) * 0.018
