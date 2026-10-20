extends Node
## Run: godot --headless --path . res://src/tools/bake_counter_geometry.tscn
const Stage := preload("res://src/ui/object_stage/object_stage.gd")
const Specimen := preload("res://src/ui/object_stage/relic_specimen.gd")
const Geometry := preload("res://src/ui/object_stage/counter_geometry.gd")
const OUTPUT := "res://assets/object_stage/counter_geometry.res"


func _ready() -> void:
	var library := Geometry.new()
	var stage := Stage.new()
	stage.mode = "shop"
	# Author without entering the tree: no lights, camera, input, RNG or settings signals.
	stage._build_room()
	stage._build_counter()
	stage._build_shop_joinery()
	stage._lantern.name = "CounterLantern"
	var shop := Node3D.new()
	shop.name = "ShopInterior"
	for child in stage.get_children():
		clear_owner(child)
		stage.remove_child(child)
		shop.add_child(child)
	library.shop = pack(shop)
	shop.free()
	for id in Specimen.IDS:
		var relic: Node3D = Specimen._build_authored(stage, id, 0)
		library.relics[id] = pack(relic)
		relic.free()
	for rank in 4:
		var token := Node3D.new()
		stage._author_token(token, rank, false)
		library.tokens.append(pack(token))
		token.free()
	var service := Node3D.new()
	stage._author_token(service, 0, true)
	library.service = pack(service)
	service.free()
	stage.free()
	DirAccess.make_dir_recursive_absolute(OUTPUT.get_base_dir())
	var result := ResourceSaver.save(library, OUTPUT, ResourceSaver.FLAG_COMPRESS)
	print("[bake_counter_geometry] relics=%d result=%d path=%s" % [library.relics.size(), result, OUTPUT])
	get_tree().quit(0 if result == OK else 1)


func pack(root: Node3D) -> PackedScene:
	assign_owner(root, root)
	var scene := PackedScene.new()
	var result := scene.pack(root)
	assert(result == OK, "Could not pack counter geometry")
	return scene


func assign_owner(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		assign_owner(child, root)


func clear_owner(node: Node) -> void:
	node.owner = null
	for child in node.get_children(): clear_owner(child)
