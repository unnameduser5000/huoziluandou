extends Node2D
class_name RosterEnemyActor
## Illustration skin with anatomical joints; no gameplay state or random numbers.
const CATALOG := preload("res://src/battle/enemy_animation_catalog.gd")
const CHOREOGRAPHY := preload("res://src/battle/enemy_action_choreography.gd")
const CLIPS := ["idle","attack","followup","special","guard","hit","death","phase"]
var enemy_id := ""
var texture_override: Texture2D
var source_size := Vector2.ONE
var profile: Dictionary
var player: AnimationPlayer
var skeleton: Skeleton2D
var mesh: Polygon2D
var bones: Dictionary = {}
var _zones: Dictionary
var _rest: Dictionary = {}
var _resting := false
var _phase := 1
var effect := 0.0
var defeated := false:
	set(value):
		if defeated == value: return
		defeated = value
		if not is_node_ready(): return
		_reset_pose()
		if value:
			if Settings.reduced_motion: modulate.a = 0.18
			else: player.play("death")
		elif not Settings.reduced_motion: player.play("idle")


func _ready() -> void:
	profile = CATALOG.profile(enemy_id)
	_zones = CATALOG.zones(profile)
	var texture: Texture2D = texture_override if texture_override != null else TaopunkArt.portrait(enemy_id)
	source_size = texture.get_size()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	skeleton = Skeleton2D.new()
	skeleton.name = "Skeleton"
	add_child(skeleton)
	_add_bone("Body",Vector2(0.5,0.80),skeleton)
	for id in _zones: _add_bone(id,_zones[id][0],bones.Body)
	_build_skin(texture)
	_build_animations()
	player.animation_finished.connect(_on_finished)
	_resting = Settings.reduced_motion
	if not _resting: player.play("idle")


func framing() -> Dictionary:
	return {"rect":Rect2(Vector2.ZERO,source_size),"fill":0.86,"bottom":0.0}


func attack_effect() -> String:
	return str(profile.effect)


func _add_bone(id: String, normalized: Vector2, parent: Node) -> void:
	var bone := Bone2D.new()
	bone.name = id
	var absolute := normalized * source_size
	bone.position = absolute if id == "Body" else absolute - Vector2(0.5,0.80) * source_size
	bone.set_autocalculate_length_and_angle(false)
	bone.set_length(40)
	parent.add_child(bone)
	bone.rest = bone.transform
	bones[id] = bone
	_rest[id] = bone.position


func skin_weights(uv: Vector2) -> Dictionary:
	var weights := {}
	var remaining := 1.0
	for id in _zones:
		var box: Rect2 = _zones[id][1]
		var weight := 0.0
		if box.has_area():
			var edge := minf(minf(uv.x-box.position.x,box.end.x-uv.x),minf(uv.y-box.position.y,box.end.y-uv.y))
			weight = smoothstep(0,0.11,edge) * remaining
		weights[id] = weight
		remaining -= weight
	weights.Body = maxf(0,remaining)
	return weights


func _build_skin(texture: Texture2D) -> void:
	mesh = Polygon2D.new()
	mesh.name = "IllustrationSkin"
	mesh.texture = texture.atlas if texture is AtlasTexture else texture
	var vertices := PackedVector2Array()
	var polygons: Array[PackedInt32Array] = []
	var weights := {}
	for id in bones: weights[id] = PackedFloat32Array()
	const COLS := 36
	const ROWS := 36
	for y in ROWS + 1:
		for x in COLS + 1:
			var uv := Vector2(float(x)/COLS,float(y)/ROWS)
			vertices.append(uv * source_size)
			var local := skin_weights(uv)
			for id in weights: weights[id].append(float(local[id]))
	for y in ROWS:
		for x in COLS:
			var a := y * (COLS + 1) + x
			polygons.append(PackedInt32Array([a,a+1,a+COLS+2]))
			polygons.append(PackedInt32Array([a,a+COLS+2,a+COLS+1]))
	mesh.polygon = vertices
	var coordinates := PackedVector2Array()
	for vertex in vertices: coordinates.append(vertex + (texture.region.position if texture is AtlasTexture else Vector2.ZERO))
	mesh.uv = coordinates
	mesh.polygons = polygons
	add_child(mesh)
	mesh.skeleton = mesh.get_path_to(skeleton)
	for id in bones: mesh.add_bone(skeleton.get_path_to(bones[id]),weights[id])


func _track(clip: Animation, bone: String, property: String, times: Array, values: Array) -> void:
	var track := clip.add_track(Animation.TYPE_VALUE)
	clip.track_set_path(track,NodePath("%s:%s" % [get_path_to(bones[bone]),property]))
	clip.track_set_interpolation_type(track,Animation.INTERPOLATION_CUBIC)
	for i in times.size(): clip.track_insert_key(track,times[i],values[i])


func _rotation(clip: Animation, bone: String, times: Array, values: Array) -> void:
	_track(clip,bone,"rotation",times,values)


func _shift(clip: Animation, bone: String, times: Array, offsets: Array) -> void:
	var values: Array = []
	for offset in offsets: values.append(_rest[bone] + offset * source_size)
	_track(clip,bone,"position",times,values)


func _build_animations() -> void:
	player = AnimationPlayer.new()
	player.name = "AnimationPlayer"
	add_child(player)
	var library := AnimationLibrary.new()
	var idle := Animation.new()
	idle.length = 3.2
	idle.loop_mode = Animation.LOOP_LINEAR
	var times := [0.0,0.8,1.6,2.4,3.2]
	var breath := 0.0 if profile.kind in ["press","rail","official","slips","stone","roller","tribunal","guillotine"] else 1.0
	_shift(idle,"Body",times,[Vector2.ZERO,Vector2(0,-0.004)*breath,Vector2.ZERO,Vector2(0,0.003)*breath,Vector2.ZERO])
	_rotation(idle,"Head",times,[0.0,-0.012,0.0,0.009,0.0])
	_rotation(idle,"LimbL",times,[0.0,0.012,0.0,-0.007,0.0])
	_rotation(idle,"LimbR",times,[0.0,-0.012,0.0,0.007,0.0])
	_rotation(idle,"Detail",times,[0.0,0.009,0.0,-0.009,0.0])
	if profile.kind == "moth":
		idle = Animation.new()
		idle.length = 0.55
		idle.loop_mode = Animation.LOOP_LINEAR
		times = [0.0,0.14,0.28,0.42,0.55]
		_rotation(idle,"LimbL",times,[0.0,0.16,0.0,-0.12,0.0])
		_rotation(idle,"LimbR",times,[0.0,-0.16,0.0,0.12,0.0])
		_shift(idle,"Body",times,[Vector2.ZERO,Vector2(0,-0.009),Vector2.ZERO,Vector2(0,0.006),Vector2.ZERO])
	# The reset clip provides every animated property before an action is sampled.
	var reset := Animation.new()
	for id in bones:
		_track(reset,id,"position",[0.0],[_rest[id]])
		_track(reset,id,"rotation",[0.0],[0.0])
		_track(reset,id,"scale",[0.0],[Vector2.ONE])
	library.add_animation("RESET",reset)
	library.add_animation("idle",idle)
	for action in ["attack","followup","special","guard","phase"]:
		library.add_animation(action,_action_clip(action))
	var hit := Animation.new()
	hit.length = 0.42
	times = [0.0,0.055,0.13,0.25,0.42]
	_shift(hit,"Body",times,[Vector2.ZERO,Vector2(0.018,0.004),Vector2(-0.006,0),Vector2(0.003,0),Vector2.ZERO])
	_rotation(hit,"Head",times,[0.0,0.11,-0.04,0.015,0.0])
	_rotation(hit,"LimbL",times,[0.0,-0.10,0.03,-0.01,0.0])
	_rotation(hit,"LimbR",times,[0.0,0.10,-0.03,0.01,0.0])
	library.add_animation("hit",hit)
	var death := Animation.new()
	death.length = 1.15
	times = [0.0,0.18,0.48,0.80,1.15]
	var limb_fall := 0.25 if profile.kind in CATALOG.OBJECT_KINDS else 1.0
	_shift(death,"Body",times,[Vector2.ZERO,Vector2(0,-0.012),Vector2(0.015,0.05),Vector2(0.025,0.12),Vector2(0.03,0.15)])
	_rotation(death,"Body",times,[0.0,-0.025,0.04,0.085,0.09])
	_rotation(death,"Head",times,[0.0,-0.02*limb_fall,0.18*limb_fall,0.26*limb_fall,0.28*limb_fall])
	_rotation(death,"LimbL",times,[0.0,0.06*limb_fall,-0.20*limb_fall,-0.26*limb_fall,-0.28*limb_fall])
	_rotation(death,"LimbR",times,[0.0,-0.06*limb_fall,0.20*limb_fall,0.26*limb_fall,0.28*limb_fall])
	var fade := death.add_track(Animation.TYPE_VALUE)
	death.track_set_path(fade,NodePath(":modulate:a"))
	for i in times.size(): death.track_insert_key(fade,times[i],[1.0,1.0,0.85,0.38,0.18][i])
	library.add_animation("death",death)
	player.add_animation_library("",library)


func _action_clip(action: String) -> Animation:
	if action in ["attack", "followup"]: return CHOREOGRAPHY.build(self, action)
	var clip := Animation.new()
	var fast := 0.76 if action == "followup" else 1.0
	clip.length = float(profile.length) * fast
	var release := float(profile.release) * fast
	var times := [0.0,release*0.62,release,release+0.13*fast,clip.length*0.78,clip.length]
	var power := 0.65 if action == "guard" else 1.0
	var forward := Vector2(-0.035,0.008) * power
	if action == "special": forward = Vector2(0,-0.018)
	if action == "phase": forward = Vector2(0,-0.028)
	if profile.kind in ["official","rail"]: forward = Vector2.ZERO
	match profile.kind:
		"guillotine": forward = Vector2.ZERO
		"crane": forward = Vector2(-0.018,0)
		"stone": forward = Vector2(-0.012,0.004)*power
		"edict": forward = Vector2(0,0.035)*power
		"roller": forward = Vector2(-0.045,0)*power
		"tribunal": forward = Vector2.ZERO
	_shift(clip,"Body",times,[Vector2.ZERO,-forward*0.4,forward,forward*0.75,-forward*0.1,Vector2.ZERO])
	_rotation(clip,"Head",times,[0.0,0.04,-0.10*power,-0.07*power,0.015,0.0])
	var left := -0.26 * power
	var right := 0.20 * power
	var detail := 0.08 * power
	match profile.kind:
		"crane": left = -0.08; right = 0.09; detail = 0.0
		"guillotine": left = 0.0; right = 0.0; detail = 0.0
		"debt": left = 0.08; right = -0.08; detail = 0.0
		"stone": left = -0.05; right = -0.09; detail = 0.0
		"edict": left = -0.045; right = 0.045; detail = 0.0
		"roller": left = -0.07; right = 0.0; detail = 0.0
		"tribunal": left = -0.08; right = 0.0; detail = -0.20
		"archive": left = -0.045; right = 0.045; detail = 0.0
		"robe": left = -0.35; right = 0.35; detail = 0.015
		"beetle": left = -0.19; right = 0.22; detail = -0.035
		"jaw":
			left = 0.13; right = -0.13; detail = 0.21 if action == "special" else -0.14
			_shift(clip,"Detail",times,[Vector2.ZERO,Vector2(0,0.014),Vector2(-0.015,0.05),Vector2(-0.01,0.04),Vector2.ZERO,Vector2.ZERO])
		"furnace":
			left = -0.23; right = 0.24; detail = 0.025
			_track(clip,"Detail","scale",times,[Vector2.ONE,Vector2(0.96,0.93),Vector2(1.09,1.07),Vector2(1.06,1.04),Vector2.ONE,Vector2.ONE])
		"badger": left = -0.27; right = -0.17; detail = -0.12
		"ledger": left = 0.12; right = -0.30; detail = -0.20
		"slips": left = 0.26 if action == "special" else -0.20; right = -left; detail = 0
		"moth": left = 0.30; right = -0.30; detail = 0.075
		"press":
			left = -0.12; right = -0.17; detail = -0.24
			_shift(clip,"LimbL",times,[Vector2.ZERO,Vector2(0,-0.04),Vector2(0,0.07),Vector2(0,0.06),Vector2(0,-0.01),Vector2.ZERO])
			_shift(clip,"LimbR",times,[Vector2.ZERO,Vector2(0,-0.03),Vector2(0,0.055),Vector2(0,0.07),Vector2.ZERO,Vector2.ZERO])
		"rubbing": left = -0.38; right = 0.10; detail = 0.025
		"seal": left = -0.32; right = 0.06; detail = -0.20
		"wheel": left = -0.14; right = -0.15; detail = -0.35 if action != "followup" else 0.28
		"leech":
			left = -0.13; right = 0.07; detail = 0.025
			_shift(clip,"Head",times,[Vector2.ZERO,Vector2(0.025,0.02),Vector2(-0.075,-0.015),Vector2(-0.06,-0.01),Vector2(0.01,0.01),Vector2.ZERO])
		"official": left = -0.22; right = -0.32; detail = 0.01
		"rail":
			left = -0.025; right = 0.025; detail = 0
			_shift(clip,"Detail",times,[Vector2.ZERO,Vector2(0.025,-0.045),Vector2(-0.035,0.07),Vector2(-0.03,0.07),Vector2(0,0.01),Vector2.ZERO])
		"scrolls":
			# Long scrolls cross the hem at larger angles and invert skin triangles.
			left = -0.09 if action == "special" else 0.08
			right = -left
			detail = 0.0
	_rotation(clip,"LimbL",times,[0.0,-left*0.35,left,left*0.85,-left*0.12,0.0])
	_rotation(clip,"LimbR",times,[0.0,-right*0.35,right,right*0.85,-right*0.12,0.0])
	_rotation(clip,"Detail",times,[0.0,-detail*0.25,detail,detail*0.8,-detail*0.1,0.0])
	_rotation(clip,"HemL",times,[0.0,-0.02,0.045,0.055,-0.015,0.0])
	_rotation(clip,"HemR",times,[0.0,0.02,-0.045,-0.055,0.015,0.0])
	return clip


func _reset_pose() -> void:
	if player != null: player.stop()
	for bone in bones.values(): bone.apply_rest()
	modulate = Color.WHITE
	effect = 0


func play_action(move: EnemyMoveData, hit_index := 0) -> Dictionary:
	var action := "attack"
	if move.kind == EnemyMoveData.Kind.BLOCK: action = "guard"
	elif move.kind in [EnemyMoveData.Kind.SPECIAL,EnemyMoveData.Kind.INJECT,EnemyMoveData.Kind.BUFF,EnemyMoveData.Kind.DEBUFF]: action = "special"
	elif hit_index > 0: action = "followup"
	if Settings.reduced_motion or defeated: return {"release":0.04,"duration":0.04,"action":action}
	_reset_pose()
	player.play(action)
	return {"release":float(profile.release)*(0.76 if action=="followup" else 1.0),"duration":player.get_animation(action).length,"action":action}


func apply_feedback(event: Dictionary) -> void:
	if event.has("hp") and int(event.hp) <= 0: defeated = true
	elif not defeated and not Settings.reduced_motion and (int(event.get("hp_loss",0)) > 0 or int(event.get("blocked",0)) > 0):
		_reset_pose()
		player.play("hit")


func set_phase(value: int) -> void:
	if _phase == value: return
	_phase = value
	if not defeated and not Settings.reduced_motion:
		_reset_pose()
		player.play("phase")


func action_global_position() -> Vector2:
	var bone := "Head"
	var tip: Vector2 = profile.head + Vector2(-0.08,0)
	if profile.has("origin"):
		bone = profile.origin_bone
		tip = profile.origin
	match profile.kind:
		"debt": bone = "Body"; tip = Vector2(0.45,0.27)
		"stone": bone = "LimbR"; tip = Vector2(0.90,0.59)
		"edict": bone = "Body"; tip = Vector2(0.40,0.73)
		"roller": bone = "Body"; tip = Vector2(0.15,0.30)
		"tribunal": bone = "Detail"; tip = Vector2(0.64,0.32)
		"archive": bone = "Body"; tip = Vector2(0.55,0.35)
		"press": bone = "LimbL"; tip = Vector2(0.15,0.65)
		"rail": bone = "Detail"; tip = Vector2(0.54,0.52)
		"badger": bone = "LimbL"; tip = Vector2(0.20,0.80)
		"jaw": bone = "Detail"; tip = Vector2(0.23,0.48)
		"furnace": bone = "Detail"; tip = Vector2(0.48,0.70)
		"seal": bone = "LimbL"; tip = Vector2(0.24,0.40)
		"rubbing": bone = "LimbL"; tip = Vector2(0.30,0.40)
		"official": bone = "LimbR"; tip = Vector2(0.75,0.36)
		"scrolls": bone = "LimbL"; tip = Vector2(0.20,0.40)
		"ledger": bone = "LimbR"; tip = Vector2(0.78,0.35)
	var pivot: Vector2 = Vector2(0.5,0.80) if bone == "Body" else _zones[bone][0]
	return bones[bone].global_transform * ((tip-pivot)*source_size)


func _on_finished(action: StringName) -> void:
	if action == "death" or defeated or Settings.reduced_motion: return
	_reset_pose()
	player.play("idle")


func _process(_delta: float) -> void:
	if _resting == Settings.reduced_motion: return
	_resting = Settings.reduced_motion
	_reset_pose()
	if defeated: modulate.a = 0.18
	elif not _resting: player.play("idle")
