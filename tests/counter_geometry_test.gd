extends Node
## Verify offline geometry against every authoring recipe, including transforms/materials.
const Stage := preload("res://src/ui/object_stage/object_stage.gd")
const Specimen := preload("res://src/ui/object_stage/relic_specimen.gd")
const Assets := preload("res://src/ui/object_stage/counter_assets.gd")
var checks := 0
var failures := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if ok: print("PASS ", message)
	else:
		failures += 1
		push_error(message)


func same_geometry(a: Node3D, b: Node3D) -> bool:
	if not a.transform.is_equal_approx(b.transform) or a.get_child_count() != b.get_child_count(): return false
	if a is MeshInstance3D:
		if a.mesh.get_surface_count() != b.mesh.get_surface_count(): return false
		for surface in a.mesh.get_surface_count():
			var original: Array = a.mesh.surface_get_arrays(surface)
			var baked: Array = b.mesh.surface_get_arrays(surface)
			if original != baked: return false
		var first: ShaderMaterial = a.material_override
		var second: ShaderMaterial = b.material_override
		if first.shader != second.shader: return false
		for uniform in first.shader.get_shader_uniform_list():
			if first.get_shader_parameter(uniform.name) != second.get_shader_parameter(uniform.name): return false
	for i in a.get_child_count():
		if not same_geometry(a.get_child(i), b.get_child(i)): return false
	return true


func _ready() -> void:
	var library: Resource = Assets.get_geometry()
	check(library != null and library.shop != null and library.relics.size() == Specimen.IDS.size(), "geometry library covers the shop and all 39 relics")
	var stage := Stage.new()
	stage.mode = "shop"
	var interior: Node3D = library.shop.instantiate()
	check(interior.has_node("CounterLantern") and interior.has_node("ShopJoinery") and interior.has_node("ShopkeeperPortrait"), "baked shop retains lantern, joinery and keeper")
	interior.free()
	var original_ms := 0.0
	var baked_ms := 0.0
	for id in Specimen.IDS:
		var started := Time.get_ticks_usec()
		var original: Node3D = Specimen._build_authored(stage, id, 0)
		original_ms += (Time.get_ticks_usec() - started) / 1000.0
		started = Time.get_ticks_usec()
		var baked: Node3D = Specimen.build(stage, id, 70)
		baked_ms += (Time.get_ticks_usec() - started) / 1000.0
		check(same_geometry(original, baked), id + " preserves every mesh array, transform and shader parameter")
		check(original.get_meta("modelled_parts") == baked.get_meta("modelled_parts") and baked.get_meta("price") == 70, id + " preserves identity and accepts the current price")
		check(Specimen.bounds_of(original).is_equal_approx(Specimen.bounds_of(baked)), id + " preserves projected bounds")
		original.free()
		baked.free()
	for rank in library.tokens.size():
		var original := Node3D.new()
		stage._author_token(original, rank, false)
		var baked: Node3D = library.tokens[rank].instantiate()
		check(same_geometry(original, baked), "glyph rank %d preserves authored geometry" % rank)
		original.free()
		baked.free()
	var service := Node3D.new()
	stage._author_token(service, 0, true)
	var baked_service: Node3D = library.service.instantiate()
	check(same_geometry(service, baked_service), "service seal preserves authored geometry")
	service.free()
	baked_service.free()
	stage.free()
	print("COUNTER_GEOMETRY ", JSON.stringify({"authored_cpu_ms": original_ms, "baked_cpu_ms": baked_ms}))
	print("[counter_geometry_test] PASS=%d FAIL=%d" % [checks - failures, failures])
	get_tree().quit(1 if failures else 0)
