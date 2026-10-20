extends Control
var checks := 0
var failures := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if ok: print("PASS ", message)
	else: failures += 1; push_error(message)


func frames(count := 3) -> void:
	for i in count: await get_tree().process_frame


func sample(actor: RosterEnemyActor, time: float) -> void:
	actor._reset_pose()
	actor.player.play("attack")
	actor.player.seek(time, true)
	actor.player.pause()


func folded_pixels(actor: RosterEnemyActor) -> int:
	var original := actor.mesh.polygon
	var points := PackedVector2Array()
	points.resize(original.size())
	var weights: Array = []
	var transforms: Array[Transform2D] = []
	for id in actor.bones:
		var bone: Bone2D = actor.bones[id]
		transforms.append(actor.global_transform.affine_inverse() * bone.global_transform * bone.get_skeleton_rest().affine_inverse())
		weights.append(actor.mesh.get_bone_weights(weights.size()))
	for i in original.size():
		var point := Vector2.ZERO
		for b in weights.size(): point += (transforms[b] * original[i]) * float(weights[b][i])
		points[i] = point
	var image := actor.mesh.texture.get_image()
	var folded := 0
	for triangle in actor.mesh.polygons:
		var a: int = triangle[0]; var b: int = triangle[1]; var c: int = triangle[2]
		if (points[b]-points[a]).cross(points[c]-points[a]) >= 0: continue
		var uv: Vector2 = (actor.mesh.uv[a]+actor.mesh.uv[b]+actor.mesh.uv[c])/3.0
		var pixel := Vector2i(uv).clamp(Vector2i.ZERO, image.get_size()-Vector2i.ONE)
		if image.get_pixelv(pixel).a > 0.15: folded += 1
	return folded


func _ready() -> void:
	SaveManager.enabled = false
	Settings.reduced_motion = false
	Ink.apply_style(GameStyle.taopunk())
	get_window().size = Vector2i(1440,960)
	_run.call_deferred()


func _run() -> void:
	var ids: Array = EnemyAnimationCatalog.DATA.keys()
	for page in ceili(ids.size()/4.0):
		var models: Array = []
		var cell := size / Vector2(3,4)
		for row in 4:
			var index := page*4+row
			if index >= ids.size(): break
			var id: String = ids[index]
			for phase in 3:
				var label := Label.new()
				label.text = id + " · " + ["idle", "windup", "impact"][phase]
				label.position = Vector2(phase*cell.x+12,row*cell.y+4)
				label.add_theme_color_override("font_color", Color("e8d6ad"))
				add_child(label)
				models.append(label)
				var art := InkSpirit.new()
				art.enemy_id = id
				art.position = Vector2(phase*cell.x+12,row*cell.y+24)
				art.size = cell - Vector2(24,28)
				add_child(art)
				models.append(art)
				var actor: RosterEnemyActor = art._character_actor
				check(actor != null and art._attack_actor == null, id + " uses one continuous current-art actor")
				var release := float(actor.profile.release)
				sample(actor,[0.0,release*0.60,release][phase])
				if phase == 2:
					var folded := 0
					for time in [release*0.60,release,release+0.09,float(actor.profile.length)*0.80,float(actor.profile.length)]:
						sample(actor,time)
						folded = maxi(folded,folded_pixels(actor))
					check(folded == 0, id + " windup, impact and recovery preserve visible skin triangles (folded=%d)" % folded)
					sample(actor,release)
					var origin: Vector2 = actor.action_global_position()
					check(is_finite(origin.x) and is_finite(origin.y), id + " effect originates at an animated anatomical point")
		await frames()
		if DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().has("--capture"):
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://shots")
			get_viewport().get_texture().get_image().save_png("res://shots/enemy-action-poses-%d.png" % page)
		for model in models: remove_child(model); model.queue_free()
		await frames()
	print("[enemy_action_pose_test] PASS=%d FAIL=%d" % [checks-failures, failures])
	get_tree().quit(1 if failures else 0)
