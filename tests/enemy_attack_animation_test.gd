extends Control
## 经真实敌人回合验证攻击、攻击附盾和连击；截图只读取原生视口。
var _pass := 0
var _fail := 0
var _screen: Control
var _capture := false
var _hashes: Dictionary = {}
var _observed_effects: Dictionary = {}
const GLYPHS := ["击", "破", "回", "流", "防", "御", "加", "速", "充", "电", "火", "爆", "金", "币", "冷", "转"]


func _ready() -> void:
	Settings.storage_path = "user://enemy_attack_animation_test-settings.cfg"
	_capture = OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless"
	_run.call_deferred()


func _ok(condition: bool, message: String) -> void:
	if condition:
		_pass += 1
		print("  ✓ ", message)
	else:
		_fail += 1
		push_error(message)


func _frames(count: int) -> void:
	for i in count: await get_tree().process_frame


func _record(id: String, primary: bool) -> void:
	var i := -1
	var deadline := Time.get_ticks_msec()+12000
	# A multi-hit sequence can outlast seventy-two frames on a fast renderer.
	# Observe its complete lifetime, including recovery, rather than a fixed FPS.
	while (i < 71 or _screen._busy) and Time.get_ticks_msec() < deadline:
		i += 1
		await get_tree().process_frame
		for child in _screen._effects.get_children():
			if child is EnemyAttackEffect: _observed_effects[child.get_instance_id()] = true
		if not _capture or not primary: continue
		RenderingServer.force_draw(false)
		var image := get_viewport().get_texture().get_image()
		var paper: Rect2 = _screen._enemy_paper.get_global_rect()
		var density := Vector2(image.get_size()) / _screen.size
		var bounds := Rect2i((paper.position * density).floor(), (paper.size * density).ceil()).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		image.get_region(bounds).save_png("res://shots/enemy-attacks-redraw/%s-%03d.png" % [id, i])
		if id in ["ember_imp", "boss_lead_plate"]:
			image.save_png("res://shots/enemy-attacks-redraw/full-%s-%03d.png" % [id, i])
		if i == 12: image.save_png("res://shots/enemy-attacks-redraw/battle-%s.png" % id)


func _settled() -> void:
	var deadline := Time.get_ticks_msec() + 6000
	while _screen._busy and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	_ok(not _screen._busy, "攻击后恢复输入")


func _poses_valid(actor: RosterEnemyActor) -> bool:
	return actor != null and actor.mesh.get_bone_count() == actor.bones.size() and actor.player.get_animation("attack").get_track_count() >= 7 and is_equal_approx(actor.scale.x, actor.scale.y)


func _case(id: String, move_index: int, primary: bool) -> void:
	var data := MapNodeData.new()
	data.enemies = [Database.get_enemy(id)]
	Router.goto("res://src/screens/battle_screen.gd", {"node": data, "seed": 17})
	_screen = Router.current
	var battle: BattleState = _screen.battle
	battle.bag.clear()
	for i in 16: battle.board.cells[i] = GameState.deck[i]
	battle.enemies[0].move_index = move_index
	_screen._refresh_all()
	await _frames(16)
	await _settled()
	var actor: RosterEnemyActor = _screen._enemy_widgets[0]._visual._character_actor
	var move: EnemyMoveData = data.enemies[0].moves[move_index]
	var hits: int = move.hits if move.kind == EnemyMoveData.Kind.MULTI else 1
	var portrait := TaopunkArt.portrait(id)
	_ok(actor != null and actor.enemy_id == id and actor.mesh.texture == (portrait.atlas if portrait is AtlasTexture else portrait), id + " 攻击与待机使用同一当前立绘")
	_ok(_poses_valid(actor), id + " 连续关节动作等比适配")
	if hits > 1: _ok(_poses_valid(actor), id + " 连击姿势轮廓有效")
	if primary:
		var state := battle.rng.state
		await _frames(5)
		_ok(battle.rng.state == state, id + " 待机和姿势采样不消耗规则随机数")
	var started: Array[StringName] = []
	actor.player.animation_started.connect(func(clip: StringName): started.append(clip))
	var before := battle.player.hp
	_observed_effects.clear()
	_screen._on_end_turn()
	await _record(id, primary)
	await _settled()
	_ok(before - battle.player.hp == move.damage * hits, "%s %s：真实伤害保持 %d × %d" % [id, move.title, move.damage, hits])
	_ok(_observed_effects.size() == hits, id + " 每次实际命中发出独立材质轨迹")
	_ok(started.count("followup") == hits - 1 and started.has("attack"), id + " 每次实际命中有独立发力，防御不冒充攻击")
	_ok(_screen._enemy_attack_context.is_empty() and actor.player.current_animation == "idle", id + " 回收后回到待机并清理演出上下文")
	if primary:
		get_window().size = Vector2i(844, 390)
		await _frames(12)
		_ok(_poses_valid(actor), id + " 手机尺寸姿势仍然有效")
		if _capture:
			RenderingServer.force_draw(false)
			get_viewport().get_texture().get_image().save_png("res://shots/enemy-attacks-redraw/phone-%s.png" % id)
		get_window().size = Vector2i(1280, 720)
		await _frames(12)
		Settings.reduced_motion = true
		await _frames(2)
		var resting := not actor.player.is_playing()
		resting = resting and actor.bones.Body.position.is_equal_approx(actor._rest.Body)
		_ok(resting, id + " 减少动效恢复原姿态")
		Settings.reduced_motion = false
		await _frames(2)
		actor.defeated = true
		await get_tree().create_timer(1.2).timeout
		_ok(not actor.player.is_playing(), id + " 击败后停止待机")


func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	var old_motion := Settings.reduced_motion
	Settings.reduced_motion = false
	Ink.apply_style(GameStyle.taopunk())
	DirAccess.make_dir_recursive_absolute("res://shots/enemy-attacks-redraw")
	get_window().size = Vector2i(1280, 720)
	await _frames(12)
	var stage := StudyStage.new()
	add_child(stage)
	Router.study_stage = stage
	Router.host = self
	GameState.start_new_run("v03", GLYPHS + GLYPHS)
	for id in EnemyAttackProfiles.DATA:
		var path := "res://assets/taopunk/enemies/%s.png" % id
		_hashes[path] = FileAccess.get_sha256(path)
		var enemy: EnemyData = Database.get_enemy(id)
		var primary := true
		for i in enemy.moves.size():
			if enemy.moves[i].kind in [EnemyMoveData.Kind.ATTACK, EnemyMoveData.Kind.ATTACK_BLOCK, EnemyMoveData.Kind.MULTI]:
				await _case(id, i, primary)
				primary = false
	var unchanged := true
	for path in _hashes: unchanged = unchanged and FileAccess.get_sha256(path) == _hashes[path]
	_ok(unchanged, "八只敌人的 PNG 均逐字节保留")
	Settings.reduced_motion = old_motion
	Router.study_stage = null
	print("ENEMY ATTACK ANIMATION: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)
