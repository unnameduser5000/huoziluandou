extends Node3D
## A small brass refresh dial beside the wares, with restrained world-space text.
const Workshop := preload("res://src/title/courtyard/mesh_workshop.gd")
var stage: Node3D
var cap: Node3D
var title_label: Label3D
var price_label: Label3D
var _face: MeshInstance3D
var _enabled := true
var _motion: Tween


func _ready() -> void:
	var w := Workshop.new()
	for item in [[0.64, 0.20, "ink"], [0.58, 0.12, "gold"]]:
		var disk := CylinderMesh.new()
		disk.top_radius = item[0]
		disk.bottom_radius = item[0]
		disk.height = item[1]
		w.add(disk, stage.pigment(item[2]), Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, 0.05)))
	w.box(Vector3(0, -0.68, 0), Vector3(0.16, 1.0, 0.18), stage.pigment("ink"))
	w.finish(self)
	cap = Node3D.new()
	add_child(cap)
	_face = MeshInstance3D.new()
	var face := CylinderMesh.new()
	face.top_radius = 0.49
	face.bottom_radius = 0.49
	face.height = 0.12
	_face.mesh = face
	_face.rotation.x = PI / 2
	_face.position.z = 0.16
	cap.add_child(_face)
	var arrow := Workshop.new()
	for i in 14:
		var a := -0.6 + i * 5.0 / 14.0
		var b := -0.6 + (i + 1) * 5.0 / 14.0
		arrow.beam(Vector3(cos(a) * 0.29, sin(a) * 0.29, 0.24), Vector3(cos(b) * 0.29, sin(b) * 0.29, 0.24), 0.055, 0.055, stage.pigment("gold"))
	arrow.box(Vector3(0.20, -0.19, 0.24), Vector3(0.16, 0.07, 0.055), stage.pigment("gold"), Vector3(0, 0, 0.3))
	arrow.finish(cap)
	title_label = stage._text("换货", 40, Color("ecdcbb"), 0.007)
	title_label.position = Vector3(0, -0.69, 0.18)
	cap.add_child(title_label)
	price_label = stage._text("", 44, Color("d6ba7d"), 0.007)
	price_label.position = Vector3(0, -1.0, 0.18)
	cap.add_child(price_label)
	set_offer("换货", 5, true)


func set_offer(caption: String, price: int, enabled: bool) -> void:
	_enabled = enabled
	title_label.text = caption
	price_label.text = "%d钱" % price
	_face.material_override = stage.pigment("teal" if enabled else "stone")
	title_label.modulate = Color("ecdcbb") if enabled else Color("82938b")
	price_label.modulate = Color("d6ba7d") if enabled else Color("82938b")
	if not enabled: highlight(false)


func highlight(active: bool) -> void:
	if is_instance_valid(_motion) and _motion.is_valid(): _motion.kill()
	cap.position.z = 0.04 if active and _enabled else 0.0


func press() -> void:
	if not _enabled or Settings.reduced_motion: return
	if is_instance_valid(_motion) and _motion.is_valid(): _motion.kill()
	cap.position.z = -0.07
	_motion = create_tween()
	_motion.tween_property(cap, "position:z", 0.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
