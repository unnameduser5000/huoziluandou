extends Node2D
class_name EnemyAttackActor
## 保留新绘攻击关键姿势；待机、施术和受击/死亡由分部位蒙皮驱动。
const ROOT := "res://assets/taopunk/attacks/"
var enemy_id := ""
var player: AnimationPlayer
var profile: Dictionary
var source_size := Vector2.ONE
var defeated := false:
	set(value):
		if defeated == value: return
		defeated = value
		if _rest_actor != null:
			pose_index = -1
			player.stop()
			_rest_actor.defeated = value
var pose_index := -1:
	set(value):
		pose_index = value
		if is_node_ready(): _show_pose()
var _sheet: Texture2D
var _skin: Polygon2D
var _frames: Array = []
var _anchor := Vector2.ZERO
var _neutral_rect := Rect2()
var _resting := false
var _rest_actor: RosterEnemyActor


static func available(id: String) -> bool:
	return not EnemyAnimationCatalog.DATA.has(id) and EnemyAttackProfiles.DATA.has(id) and ResourceLoader.exists(ROOT + id + ".tres")


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	profile = EnemyAttackProfiles.get_profile(enemy_id)
	var sheet: EnemyAttackSheet = load(ROOT + enemy_id + ".tres")
	_sheet = sheet.texture
	_frames = JSON.parse_string(sheet.index_json).frames
	var bounds := Rect2()
	for i in _frames.size():
		var frame: Dictionary = _frames[i]
		var r: Array = frame.rect
		var anchor := Vector2(frame.anchor[0], frame.anchor[1])
		var box := Rect2(Vector2(r[0], r[1]) - anchor, Vector2(r[2], r[3]))
		bounds = box if i == 0 else bounds.merge(box)
	_anchor = -bounds.position + Vector2(4, 4)
	source_size = bounds.size + Vector2(8, 8)
	var first: Dictionary = _frames[0]
	_neutral_rect = Rect2(Vector2(first.rect[0], first.rect[1]) - Vector2(first.anchor[0], first.anchor[1]) + _anchor, Vector2(first.rect[2], first.rect[3]))
	_skin = Polygon2D.new()
	_skin.texture = _sheet
	add_child(_skin)
	_rest_actor = RosterEnemyActor.new()
	_rest_actor.enemy_id = enemy_id
	_rest_actor.texture_override = TaopunkArt.portrait(enemy_id)
	add_child(_rest_actor)
	_rest_actor.position = _neutral_rect.position
	_rest_actor.scale = _neutral_rect.size / _rest_actor.source_size
	_build_animations()
	player.animation_finished.connect(func(_clip: StringName):
		if not defeated and not Settings.reduced_motion: player.play("idle"))
	_set_resting(Settings.reduced_motion)
	_show_pose()


func _show_pose() -> void:
	if _skin == null: return
	_skin.visible = pose_index >= 0
	if _rest_actor != null: _rest_actor.visible = pose_index < 0
	if pose_index >= 0:
		var frame: Dictionary = _frames[pose_index]
		var anchor := Vector2(frame.anchor[0], frame.anchor[1])
		var vertices := PackedVector2Array()
		var coordinates := PackedVector2Array()
		for point in frame.outline:
			var p := Vector2(point[0], point[1])
			vertices.append(p - anchor + _anchor)
			coordinates.append(p)
		_skin.polygon = vertices
		_skin.uv = coordinates
	queue_redraw()


func _draw() -> void:
	if pose_index < 0 and _rest_actor == null: draw_texture_rect(TaopunkArt.portrait(enemy_id), _neutral_rect, false)


func _build_animations() -> void:
	player = AnimationPlayer.new()
	add_child(player)
	var library := AnimationLibrary.new()
	var idle := Animation.new()
	idle.length = 1
	idle.loop_mode = Animation.LOOP_LINEAR
	_add_poses(idle, [0.0], [-1])
	library.add_animation("idle", idle)
	for name in ["attack", "slam", "followup"]:
		var clip := Animation.new()
		var release: float = profile.release * (0.65 if name == "followup" else 1.0)
		clip.length = profile.length * (0.76 if name == "followup" else 1.0)
		if enemy_id == "ember_imp":
			if name == "followup":
				clip.length = 0.64
				_add_poses(clip, [0.0, 0.10, 0.19, 0.40, 0.58], [4, 5, 6, 7, -1])
			else:
				_add_poses(clip, [0.0, 0.08, 0.15, 0.22, 0.43], [0, 1, 2, 3, 4])
		else:
			_add_poses(clip, [0.0, release * 0.30, release * 0.66, release * 0.86, release, release + 0.17, clip.length * 0.77, clip.length * 0.91, clip.length], [0, 1, 2, 3, 4, 5, 6, 7, -1])
		library.add_animation(name, clip)
	player.add_animation_library("", library)


func _add_poses(clip: Animation, times: Array, poses: Array) -> void:
	var track := clip.add_track(Animation.TYPE_VALUE)
	clip.track_set_path(track, NodePath(":pose_index"))
	clip.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
	for i in times.size(): clip.track_insert_key(track, times[i], poses[i])


func play_action(move: EnemyMoveData, hit_index := 0) -> Dictionary:
	if move.kind not in [EnemyMoveData.Kind.ATTACK, EnemyMoveData.Kind.ATTACK_BLOCK, EnemyMoveData.Kind.MULTI]:
		pose_index = -1
		return _rest_actor.play_action(move,hit_index)
	if Settings.reduced_motion or defeated: return {"release": 0.04, "duration": 0.04}
	var clip := "followup" if hit_index > 0 else ("slam" if move.kind == EnemyMoveData.Kind.ATTACK_BLOCK else "attack")
	player.stop(true)
	player.play(clip)
	var release: float = profile.release * (0.65 if hit_index > 0 else 1.0)
	if enemy_id == "ember_imp" and hit_index > 0: release = 0.19
	return {"release": release, "duration": player.get_animation(clip).length, "action": clip}


func apply_feedback(event: Dictionary) -> void:
	if _rest_actor == null: return
	if int(event.get("hp_loss",0)) > 0 or int(event.get("blocked",0)) > 0 or int(event.get("hp",1)) <= 0:
		player.stop()
		pose_index = -1
		_rest_actor.apply_feedback(event)


func eye_global_position() -> Vector2:
	return global_transform * (_neutral_rect.get_center() + Vector2(-_neutral_rect.size.x * 0.2, -_neutral_rect.size.y * 0.15))


func _set_resting(value: bool) -> void:
	_resting = value
	if value:
		player.stop()
		pose_index = -1
	else: player.play("idle")


func _process(_delta: float) -> void:
	if _resting != (Settings.reduced_motion or defeated): _set_resting(Settings.reduced_motion or defeated)
