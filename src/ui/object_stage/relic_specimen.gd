extends RefCounted
## Standalone workshop artefacts. Intrinsic feet/handles belong to the object;
## there is no shared display plinth, disc, or pedestal.
const Workshop := preload("res://src/ui/object_stage/relic_mesh.gd")
const PIGMENT := preload("res://src/ui/object_stage/relic_pigment.gdshader")
const FONT := preload("res://assets/fonts/LXGWWenKai-Regular.ttf")
const Expansion := preload("res://src/ui/object_stage/relic_expansion.gd")
const Geometry := preload("res://src/ui/object_stage/counter_assets.gd")
const IDS := ["strike", "breach", "slab", "press", "sleep", "clean", "wheel", "powerbank", "fireman", "fertilizer", "skyfire", "blitz", "egg", "buckler", "barrier", "empty_case", "stay_wax", "amber", "ghost_hand", "cracked_bottle", "rotting_fruit", "chaos_dice", "black_water", "life_lantern", "life_debt", "chain", "question", "goldleaf", "moon", "slot", "death", "ruin", "rubbing", "midas", "monkey", "palindrome", "binding", "proof", "vial"]


static func build(stage: Node3D, id: String, price: int) -> Node3D:
	var library: Resource = Geometry.get_geometry()
	if library != null and library.relics.has(id):
		var specimen: Node3D = library.relics[id].instantiate()
		specimen.set_meta("price", price)
		return specimen
	return _build_authored(stage, id, price)


static func _build_authored(stage: Node3D, id: String, price: int) -> Node3D:
	var node := Node3D.new()
	node.name = "Relic_" + id
	node.set_meta("relic_id", id)
	node.set_meta("display_plinth", false)
	var w := Workshop.new()
	var m := _palette(stage)
	match id:
		"strike": _knife(w, m)
		"breach": _etching(w, m)
		"slab": _weight(w, m)
		"press": _printing(w, m)
		"sleep": _incense(w, m)
		"clean": _cloth(w, m)
		"wheel": _wheel(w, m)
		"powerbank": _battery(w, m)
		"fireman": _fire(w, m, false)
		"fertilizer": _inkpot(w, m)
		"skyfire": _fire(w, m, true)
		"blitz": _stamp(w, m)
		"egg": _seed(w, m)
		"buckler": _shield(w, m)
		"barrier": _screen(w, m)
		_: Expansion.build(w, m, id)
	w.finish(node)
	# Remove the authoring margin, so every object rests directly on the counter.
	if id == "strike":
		for part in node.get_children(): part.transform = Transform3D(Basis(Vector3.FORWARD, 0.45), Vector3.ZERO) * part.transform
	var bounds := bounds_of(node)
	for part in node.get_children(): part.position.y -= bounds.position.y
	node.set_meta("price", price)
	return node


static func bounds_of(node: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for part in node.get_children():
		if part is MeshInstance3D:
			var box: AABB = part.transform * part.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
	return bounds


static func _palette(stage: Node3D) -> Dictionary:
	if stage.has_meta("relic_materials"): return stage.get_meta("relic_materials")
	var roles := {
		"bronze": ["ad7b3e", "eed39b", "395e56", 0.58, 0.46, 0],
		"edge": ["e4c68b", "fff0bd", "936d40", 0.64, 0.38, 0],
		"dark": ["172c30", "49685e", "0c171d", 0.24, 0.65, 0],
		"jade": ["416e60", "99b398", "183f3c", 0.12, 0.48, 0],
		"red": ["973c36", "d58b64", "402627", 0.05, 0.60, 0],
		"paper": ["d7c9a5", "f7e9c5", "918571", 0.0, 0.88, 2],
		"cloth": ["b7c3a4", "e1dec1", "6d8778", 0.0, 0.98, 2],
		"stone": ["3e5553", "90a08a", "203b3c", 0.0, 0.85, 3],
		"wood": ["403d31", "9c8054", "192c2c", 0.0, 0.82, 1],
		"flame": ["e2a951", "ffdf8c", "b35837", 0.1, 0.52, 0],
		"bone": ["ddd0ae", "fff0cb", "918574", 0.0, 0.68, 3],
		"amber": ["b93d1e", "ffc269", "591b16", 0.18, 0.26, 0],
		"silver": ["a8bdb2", "edf2d3", "4a7471", 0.72, 0.27, 0],
	}
	var materials := {}
	for role in roles:
		var spec: Array = roles[role]
		var material := ShaderMaterial.new()
		material.shader = PIGMENT
		for i in 3: material.set_shader_parameter(["base_color", "wear_color", "recess_color"][i], Color(spec[i]))
		material.set_shader_parameter("metallic_amount", spec[3])
		material.set_shader_parameter("roughness_amount", spec[4])
		material.set_shader_parameter("surface_kind", spec[5])
		materials[role] = material
	stage.set_meta("relic_materials", materials)
	return materials


static func _glyph(w, text: String, at: Vector3, size: float, material: Material, rotation := Vector3.ZERO) -> void:
	var mesh := TextMesh.new()
	mesh.font = FONT
	mesh.text = text
	mesh.font_size = 64
	mesh.pixel_size = size / 64.0
	mesh.depth = 0.007
	w.add(mesh, material, Transform3D(Basis.from_euler(rotation), at), "RelicInscription")


static func _stud(w, at: Vector3, m: Dictionary, extent := 0.035) -> void:
	w.orb(at, Vector3.ONE * extent, m.edge)


static func _knife(w, m: Dictionary) -> void:
	w.lathe([Vector2(0, 0.02), Vector2(0.075, 0.02), Vector2(0.09, 0.07), Vector2(0.082, 0.45), Vector2(0.065, 0.51), Vector2(0, 0.51)], m.wood)
	for i in 9: w.ring(Vector3(0, 0.10 + i * 0.038, 0), 0.083, 0.012, m.jade, Vector3(0, 0, 0.08))
	for y in [0.045, 0.47, 0.51]: w.ring(Vector3(0, y, 0), 0.082, 0.014, m.bronze)
	w.rounded(Vector3(0, 0.52, 0), Vector3(0.25, 0.055, 0.15), 0.02, m.bronze)
	w.silhouette(PackedVector2Array([Vector2(-0.06, 0.53), Vector2(0.06, 0.53), Vector2(0.18, 1.10), Vector2(-0.14, 1.18)]), 0.052, m.bronze)
	w.silhouette(PackedVector2Array([Vector2(-0.14, 1.18), Vector2(0.18, 1.10), Vector2(0.17, 1.05), Vector2(-0.13, 1.13)]), 0.057, m.edge)
	w.rod(Vector3(0, 0.61, 0.029), Vector3(0.015, 1.03, 0.029), 0.008, m.dark)
	_glyph(w, "刻", Vector3(0, 0.81, 0.035), 0.13, m.dark)
	for y in [0.13, 0.4]: _stud(w, Vector3(0, y, 0.091), m, 0.033)
	w.ring(Vector3(0, 0.025, 0.03), 0.048, 0.011, m.bronze, Vector3(PI / 2, 0, 0))


static func _etching(w, m: Dictionary) -> void:
	w.rounded(Vector3(0, 0.54, 0), Vector3(0.92, 1.02, 0.10), 0.035, m.dark)
	w.rounded(Vector3(0, 0.54, 0.045), Vector3(0.87, 0.97, 0.035), 0.025, m.bronze)
	w.rounded(Vector3(0, 0.54, 0.069), Vector3(0.73, 0.82, 0.015), 0.018, m.jade)
	for side in [-1.0, 1.0]:
		for y in [0.11, 0.97]: _stud(w, Vector3(side * 0.385, y, 0.075), m)
		w.rod(Vector3(side * 0.34, 0.22, 0.084), Vector3(side * 0.34, 0.86, 0.084), 0.01, m.edge)
	_glyph(w, "蚀", Vector3(0, 0.62, 0.088), 0.40, m.bronze)
	for i in 7:
		var x := -0.25 + i * 0.08
		w.rod(Vector3(x, 0.19, 0.089), Vector3(x + 0.035, 0.31 + (i % 3) * 0.035, 0.089), 0.008, m.dark)
	for i in 4: w.rod(Vector3(-0.24 + i * 0.12, 0.85, 0.09), Vector3(-0.19 + i * 0.12, 0.85, 0.09), 0.009, m.edge)
	w.rod(Vector3(-0.38, 0.07, -0.02), Vector3(-0.25, 0.03, -0.22), 0.025, m.wood)
	w.rod(Vector3(0.38, 0.07, -0.02), Vector3(0.25, 0.03, -0.22), 0.025, m.wood)


static func _weight(w, m: Dictionary) -> void:
	w.rounded(Vector3(0, 0.24, 0), Vector3(1.04, 0.45, 0.69), 0.08, m.stone)
	for x in [-0.38, 0.38]: w.rounded(Vector3(x, 0.25, 0), Vector3(0.075, 0.44, 0.68), 0.025, m.bronze)
	w.rounded(Vector3(0, 0.474, 0), Vector3(0.57, 0.018, 0.44), 0.025, m.bronze)
	_glyph(w, "镇", Vector3(0, 0.49, 0), 0.35, m.dark, Vector3(-PI / 2, 0, 0))
	w.ring(Vector3(0, 0.57, 0), 0.15, 0.035, m.bronze, Vector3(PI / 2, 0, 0))
	for x in [-0.13, 0.13]: w.orb(Vector3(x, 0.47, 0), Vector3(0.11, 0.07, 0.10), m.bronze)
	for i in 7:
		var x := -0.26 + i * 0.085
		w.rod(Vector3(x, 0.14, 0.348), Vector3(x + 0.03, 0.28, 0.348), 0.006, m.jade)
	for x in [-0.38, 0.38]:
		for z in [-0.24, 0.24]: _stud(w, Vector3(x, 0.472, z), m)


static func _printing(w, m: Dictionary) -> void:
	for side in [-1.0, 1.0]:
		var x: float = side * 0.27
		w.rounded(Vector3(x, 0.55, 0), Vector3(0.51, 1.02, 0.12), 0.028, m.wood)
		w.rounded(Vector3(x, 0.55, 0.069), Vector3(0.45, 0.93, 0.024), 0.015, m.bronze)
		w.rounded(Vector3(x, 0.55, 0.085), Vector3(0.39, 0.86, 0.016), 0.008, m.dark)
		for row in 4:
			for col in 2:
				var at := Vector3(x - 0.10 + col * 0.20, 0.20 + row * 0.23, 0.105)
				w.rounded(at, Vector3(0.17, 0.18, 0.042), 0.009, m.paper if (row + col) % 3 == 0 else m.bronze)
				_glyph(w, ["活", "字", "山", "水", "印", "风", "墨", "火"][row * 2 + col], at + Vector3(0, 0, 0.027), 0.13, m.dark)
		for y in [0.08, 1.02]: _stud(w, Vector3(x + side * 0.20, y, 0.09), m, 0.028)
	for y in [0.19, 0.53, 0.87]:
		w.rod(Vector3(0, y - 0.05, 0), Vector3(0, y + 0.05, 0), 0.038, m.bronze)
		w.ring(Vector3(0, y, 0), 0.04, 0.009, m.edge)


static func _incense(w, m: Dictionary) -> void:
	w.lathe([Vector2(0, 0.06), Vector2(0.23, 0.06), Vector2(0.34, 0.17), Vector2(0.39, 0.35), Vector2(0.37, 0.43), Vector2(0.31, 0.43), Vector2(0.29, 0.22), Vector2(0, 0.2)], m.bronze)
	w.ring(Vector3(0, 0.41, 0), 0.35, 0.035, m.edge)
	w.cylinder(Vector3(0, 0.29, 0), 0.285, 0.025, m.stone)
	for angle in [0.0, TAU / 3, TAU * 2 / 3]:
		var foot := Vector3(cos(angle) * 0.24, 0, sin(angle) * 0.24)
		w.orb(foot + Vector3(0, 0.065, 0), Vector3(0.10, 0.13, 0.1), m.bronze)
	for side in [-1.0, 1.0]: w.ring(Vector3(side * 0.39, 0.29, 0), 0.10, 0.026, m.bronze, Vector3(PI / 2, 0, 0))
	for i in 3:
		var a := Vector3(-0.13 + i * 0.13, 0.29, 0)
		var b := Vector3(-0.22 + i * 0.21, 1.20 - (i % 2) * 0.06, 0)
		w.rod(a, b, 0.012, m.red)
		w.rod(b - Vector3(0, 0.055, 0), b, 0.014, m.paper)
		w.orb(b, Vector3.ONE * 0.025, m.flame)
	for i in 12:
		var a := TAU * i / 12.0
		_stud(w, Vector3(cos(a) * 0.374, 0.33, sin(a) * 0.374), m, 0.028)
	_glyph(w, "安", Vector3(0, 0.22, 0.365), 0.12, m.dark)


static func _cloth(w, m: Dictionary) -> void:
	for layer in 4:
		w.rounded(Vector3(0, 0.075 + layer * 0.08, 0), Vector3(0.98 - layer * 0.045, 0.10, 0.67 - layer * 0.015), 0.037, m.cloth if layer % 2 == 0 else m.paper)
		for i in 5:
			w.rod(Vector3(-0.37, 0.07 + layer * 0.08, 0.32 - i * 0.009), Vector3(0.36, 0.07 + layer * 0.08, 0.32 - i * 0.009), 0.004, m.jade)
	w.cloth_surface(Vector3(0, 0.38, 0), 0.83, 0.58, m.cloth)
	for x in [-0.38, 0.38]:
		for i in 15:
			var z := -0.25 + i * 0.036
			w.rod(Vector3(x, 0.375, z), Vector3(x, 0.375, z + 0.016), 0.004, m.jade)
	for i in 14:
		var x := -0.37 + i * 0.055
		w.rod(Vector3(x, 0.28, 0.32), Vector3(x + 0.018 * sin(i * 1.7), 0.22, 0.38), 0.006, m.paper)
	w.rounded(Vector3(0.17, 0.38, -0.11), Vector3(0.26, 0.012, 0.20), 0.015, m.jade)


static func _wheel(w, m: Dictionary) -> void:
	for x in [-0.34, 0.34]:
		w.rounded(Vector3(x, 0.055, 0), Vector3(0.15, 0.11, 0.50), 0.03, m.wood)
		w.rod(Vector3(x, 0.1, 0), Vector3(x * 0.5, 0.57, 0), 0.037, m.bronze)
	w.ring(Vector3(0, 0.66, 0.04), 0.43, 0.052, m.wood, Vector3(PI / 2, 0, 0))
	for z in [-0.015, 0.105]: w.ring(Vector3(0, 0.66, z), 0.43, 0.018, m.edge, Vector3(PI / 2, 0, 0))
	for i in 12:
		var a := TAU * i / 12.0
		var p := Vector3(cos(a) * 0.40, 0.66 + sin(a) * 0.40, 0.04)
		w.rod(Vector3(0, 0.66, 0.04), p, 0.018, m.bronze)
		w.rounded(Vector3(cos(a) * 0.46, 0.66 + sin(a) * 0.46, 0.04), Vector3(0.062, 0.082, 0.13), 0.01, m.bronze, Vector3(0, 0, a - PI / 2))
		_stud(w, p + Vector3(0, 0, 0.079), m, 0.033)
	w.orb(Vector3(0, 0.66, 0.065), Vector3(0.18, 0.18, 0.18), m.bronze)
	w.rod(Vector3(0, 0.66, 0.12), Vector3(0, 0.66, 0.25), 0.044, m.dark)
	w.rod(Vector3(0, 0.66, 0.25), Vector3(0.15, 0.54, 0.25), 0.025, m.bronze)
	w.rod(Vector3(0.15, 0.54, 0.25), Vector3(0.15, 0.54, 0.36), 0.04, m.wood)


static func _battery(w, m: Dictionary) -> void:
	w.lathe([Vector2(0, 0.03), Vector2(0.26, 0.03), Vector2(0.31, 0.09), Vector2(0.31, 0.77), Vector2(0.27, 0.86), Vector2(0.25, 0.89), Vector2(0, 0.89)], m.jade)
	for y in [0.08, 0.16, 0.78, 0.86]: w.ring(Vector3(0, y, 0), 0.30, 0.025, m.bronze)
	for side in [-1.0, 1.0]:
		w.cylinder(Vector3(side * 0.14, 0.94, 0), 0.055, 0.14, m.bronze)
		w.ring(Vector3(side * 0.14, 0.92, 0), 0.065, 0.012, m.dark)
		for i in 3: w.ring(Vector3(side * 0.14, 0.95 + i * 0.025, 0), 0.057, 0.008, m.edge)
	w.rod(Vector3(-0.14, 1.015, 0), Vector3(-0.14, 1.10, 0), 0.022, m.dark)
	w.rod(Vector3(-0.14, 1.10, 0), Vector3(0.22, 1.08, -0.06), 0.022, m.dark)
	w.rod(Vector3(0.22, 1.08, -0.06), Vector3(0.14, 1.015, 0), 0.022, m.dark)
	w.rounded(Vector3(0, 0.46, 0.30), Vector3(0.28, 0.40, 0.025), 0.025, m.bronze)
	w.rounded(Vector3(0, 0.46, 0.318), Vector3(0.23, 0.34, 0.01), 0.01, m.paper)
	_glyph(w, "电", Vector3(0, 0.50, 0.33), 0.22, m.dark)
	for i in 3: w.rounded(Vector3(0, 0.335 + i * 0.035, 0.335), Vector3(0.11, 0.012, 0.008), 0.002, m.jade)
	for i in 8:
		var a := TAU * i / 8.0
		w.rod(Vector3(cos(a) * 0.313, 0.21, sin(a) * 0.313), Vector3(cos(a) * 0.313, 0.72, sin(a) * 0.313), 0.009, m.edge)


static func _fire(w, m: Dictionary, celestial: bool) -> void:
	w.lathe([Vector2(0, 0.03), Vector2(0.19, 0.03), Vector2(0.21, 0.08), Vector2(0.16, 0.17), Vector2(0.29, 0.23), Vector2(0.34, 0.35), Vector2(0.32, 0.40), Vector2(0.27, 0.37), Vector2(0.19, 0.26), Vector2(0, 0.24)], m.bronze)
	w.ring(Vector3(0, 0.38, 0), 0.31, 0.024, m.edge)
	for i in 6:
		var a := TAU * i / 6.0
		w.rod(Vector3(cos(a) * 0.18, 0.16, sin(a) * 0.18), Vector3(cos(a) * 0.30, 0.35, sin(a) * 0.30), 0.018, m.dark)
	w.tongue(Vector3(-0.13, 0.31, 0), 0.62, 0.22, -0.13, m.red)
	w.tongue(Vector3(0.09, 0.31, -0.015), 0.98 if celestial else 0.82, 0.27, 0.10, m.red)
	w.tongue(Vector3(0.17, 0.32, 0.025), 0.53, 0.16, 0.16, m.flame)
	w.tongue(Vector3(-0.02, 0.32, 0.13), 0.67 if celestial else 0.56, 0.19, -0.09, m.flame)
	if celestial:
		w.ring(Vector3(0, 0.76, -0.12), 0.48, 0.023, m.bronze, Vector3(PI / 2, 0, 0))
		for i in 8:
			var a := TAU * i / 8.0
			var p := Vector3(cos(a) * 0.49, 0.76 + sin(a) * 0.49, -0.12)
			w.orb(p, Vector3.ONE * 0.045, m.edge)
			w.rod(p, p + Vector3(cos(a), sin(a), 0) * 0.10, 0.013, m.bronze)


static func _inkpot(w, m: Dictionary) -> void:
	w.lathe([Vector2(0, 0.025), Vector2(0.24, 0.025), Vector2(0.33, 0.14), Vector2(0.34, 0.38), Vector2(0.28, 0.52), Vector2(0.20, 0.55), Vector2(0.20, 0.65), Vector2(0.15, 0.65), Vector2(0.15, 0.50), Vector2(0, 0.50)], m.dark)
	for y in [0.1, 0.54, 0.64]: w.ring(Vector3(0, y, 0), 0.29 if y < 0.2 else 0.20, 0.018, m.bronze)
	w.rounded(Vector3(0, 0.31, 0.33), Vector3(0.28, 0.30, 0.02), 0.018, m.paper)
	_glyph(w, "墨", Vector3(0, 0.35, 0.35), 0.23, m.dark)
	for i in 3:
		var a := Vector3(0, 0.59, 0)
		var b := Vector3(-0.35 + i * 0.33, 1.1 + (i % 2) * 0.18, -0.02)
		w.rod(a, a.lerp(b, 0.5) + Vector3(0.05, 0, 0), 0.015, m.jade)
		w.rod(a.lerp(b, 0.5) + Vector3(0.05, 0, 0), b, 0.012, m.jade)
		for side in [-1.0, 1.0]:
			var root := a.lerp(b, 0.62)
			w.leaf(root, root + Vector3(side * 0.25, 0.19, 0.045), 0.065, m.jade, m.edge)
		w.leaf(b - Vector3(0, 0.13, 0), b + Vector3(0.09, 0.10, 0.015), 0.07, m.jade, m.edge)


static func _stamp(w, m: Dictionary) -> void:
	w.rounded(Vector3(0, 0.14, 0), Vector3(0.74, 0.25, 0.64), 0.045, m.red)
	w.rounded(Vector3(0, 0.28, 0), Vector3(0.78, 0.055, 0.68), 0.018, m.bronze)
	w.rounded(Vector3(0, 0.035, 0), Vector3(0.72, 0.04, 0.62), 0.012, m.dark)
	w.lathe([Vector2(0.20, 0.30), Vector2(0.18, 0.35), Vector2(0.11, 0.46), Vector2(0.10, 0.66), Vector2(0.18, 0.77), Vector2(0.20, 0.85), Vector2(0.16, 0.93), Vector2(0, 0.96)], m.jade)
	for y in [0.34, 0.72, 0.86]: w.ring(Vector3(0, y, 0), 0.18, 0.018, m.bronze)
	_glyph(w, "急", Vector3(0, 0.17, 0.327), 0.17, m.edge)
	for side in [-1.0, 1.0]:
		for x in [-0.30, 0.30]: _stud(w, Vector3(x, 0.18, side * 0.323), m, 0.026)
	w.ring(Vector3(0.22, 0.74, 0), 0.052, 0.012, m.bronze, Vector3(PI / 2, 0, 0))
	for i in 4: w.rod(Vector3(0.25, 0.71, 0.02), Vector3(0.36 + i * 0.012, 0.35, 0.05 + i * 0.01), 0.012, m.red)


static func _seed(w, m: Dictionary) -> void:
	w.lathe([Vector2(0, 0.02), Vector2(0.16, 0.06), Vector2(0.27, 0.20), Vector2(0.32, 0.40), Vector2(0.29, 0.61), Vector2(0.19, 0.80), Vector2(0.06, 0.93), Vector2(0, 0.95)], m.bronze)
	for i in 8:
		var a := TAU * i / 8.0
		var previous := Vector3(0, 0.03, 0)
		for p in [Vector2(0.17, 0.09), Vector2(0.28, 0.27), Vector2(0.32, 0.43), Vector2(0.28, 0.64), Vector2(0.16, 0.85), Vector2(0.02, 0.95)]:
			var at := Vector3(cos(a) * p.x, p.y, sin(a) * p.x)
			w.rod(previous, at, 0.008, m.dark if i % 2 == 0 else m.edge)
			previous = at
	w.rod(Vector3(0, 0.91, 0), Vector3(0.12, 1.16, 0), 0.015, m.jade)
	w.leaf(Vector3(0.05, 1.03, 0), Vector3(0.43, 1.24, 0.025), 0.10, m.jade, m.edge)
	w.leaf(Vector3(0.06, 1.04, 0), Vector3(-0.19, 1.21, -0.02), 0.07, m.jade, m.edge)
	_glyph(w, "字", Vector3(0, 0.49, 0.323), 0.22, m.dark)


static func _shield(w, m: Dictionary) -> void:
	w.lathe([Vector2(0, -0.07), Vector2(0.43, -0.07), Vector2(0.51, -0.015), Vector2(0.51, 0.035), Vector2(0.43, 0.075), Vector2(0.20, 0.15), Vector2(0, 0.18)], m.bronze, Vector3(0, 0.53, 0), Vector3(PI / 2, 0, 0))
	for radius in [0.46, 0.49]: w.ring(Vector3(0, 0.53, 0.037), radius, 0.013, m.edge, Vector3(PI / 2, 0, 0))
	w.orb(Vector3(0, 0.53, 0.16), Vector3(0.25, 0.25, 0.20), m.jade)
	w.ring(Vector3(0, 0.53, 0.17), 0.15, 0.02, m.bronze, Vector3(PI / 2, 0, 0))
	for i in 12:
		var a := TAU * i / 12.0
		var p := Vector3(cos(a) * 0.41, 0.53 + sin(a) * 0.41, 0.08)
		_stud(w, p, m, 0.042)
		if i % 3 == 0: continue
		var from := Vector3(cos(a) * 0.22, 0.53 + sin(a) * 0.22, 0.14)
		w.rod(from, p, 0.012, m.jade)
	for side in [-1.0, 1.0]:
		w.rod(Vector3(side * 0.34, 0.1, -0.01), Vector3(side * 0.27, 0.02, -0.16), 0.022, m.dark)


static func _screen(w, m: Dictionary) -> void:
	for i in 3:
		var x := (i - 1) * 0.36
		var z := -0.07 if i == 1 else 0.04
		w.rounded(Vector3(x, 0.63, z), Vector3(0.35, 1.12, 0.075), 0.02, m.wood)
		w.rounded(Vector3(x, 0.65, z + 0.043), Vector3(0.28, 0.91, 0.015), 0.008, m.bronze)
		w.rounded(Vector3(x, 0.65, z + 0.055), Vector3(0.25, 0.88, 0.01), 0.006, m.paper)
		for y in [0.12, 1.13]: w.rounded(Vector3(x, y, z + 0.047), Vector3(0.30, 0.045, 0.02), 0.008, m.bronze)
		for side in [-1.0, 1.0]:
			w.rounded(Vector3(x + side * 0.125, 0.055, z), Vector3(0.06, 0.13, 0.12), 0.01, m.wood)
		# Three connected ink landscapes, with mountain ridges and bamboo stems.
		w.silhouette(PackedVector2Array([Vector2(-0.12, 0.29), Vector2(-0.12, 0.43), Vector2(-0.05, 0.59 + i * 0.06), Vector2(0.025, 0.47), Vector2(0.065, 0.54), Vector2(0.12, 0.38), Vector2(0.12, 0.29)]), 0.003, m.jade, Vector3(x, 0, z + 0.065))
		w.rod(Vector3(x + 0.055, 0.35, z + 0.071), Vector3(x + 0.038, 0.91, z + 0.071), 0.004, m.dark)
		for j in 4:
			var root := Vector3(x + 0.045, 0.59 + j * 0.065, z + 0.073)
			w.leaf(root, root + Vector3(-0.07, 0.055, 0), 0.014, m.dark, m.jade)
		_glyph(w, "山水静"[i], Vector3(x - 0.055, 1.02, z + 0.07), 0.065, m.red)
	for x in [-0.18, 0.18]:
		for y in [0.25, 0.96]:
			w.rod(Vector3(x, y - 0.04, 0), Vector3(x, y + 0.04, 0), 0.018, m.bronze)
