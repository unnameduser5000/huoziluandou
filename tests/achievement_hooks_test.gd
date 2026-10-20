extends "res://tests/achievement_system_test.gd"

func _ready() -> void:
	Achievements.test_enabled = true
	Achievements.autosave = false
	# 折页：移动不算，真正组词解签才记一次。
	fresh()
	var b := battle("fold_moth")
	var path := place(b, "击破")
	EnemyMechanics.begin_phase(b)
	var enemy: Combatant = b.enemies[0]
	var task := EnemyMechanics.data(enemy)
	task.targets = [b.board.get_xy(Vector2i.ZERO)]
	task.origins = [Vector2i.ZERO]
	EnemyMechanics.update_targets(b, enemy)
	check(Achievements.progress("fold_unseal") == 0, "看题目不解锁折页成就")
	check(b.try_play(path).ok and Achievements.is_unlocked("fold_unseal"), "真实折页成词解签触发")
	EnemyMechanics.update_targets(b, enemy)
	check(Achievements.progress("fold_unseal") == 1, "同一折页签不重复发奖")
	# 对校：单签不计完整组，两签都完成后计一组。
	fresh(); b = battle("proof_boss")
	enemy = b.enemies[0]; enemy.move_index = 1
	path = place(b, "击破")
	EnemyMechanics.begin_phase(b)
	task = EnemyMechanics.data(enemy)
	check(task.targets.size() == 2, "对校准备两签")
	b.board.clear_xy(task.origins[0])
	EnemyMechanics.update_targets(b, enemy)
	check(Achievements.progress("proof_3") == 0, "只解一签不计一整组")
	b.board.clear_xy(task.origins[1])
	EnemyMechanics.update_targets(b, enemy); EnemyMechanics.update_targets(b, enemy)
	check(Achievements.progress("proof_3") == 1, "对校全组只记一次")
	# 压轨：有题且所有原字撤离，攻击后真实拆盾路径触发。
	fresh(); b = battle("rail_boss")
	enemy = b.enemies[0]
	path = place(b, "击破")
	EnemyMechanics.begin_phase(b)
	task = EnemyMechanics.data(enemy)
	check(not task.targets.is_empty(), "压轨有合法目标")
	for inst in task.targets: b.board.clear_xy(EnemyMechanics.pos(b, inst))
	EnemyMechanics.after_action(b, enemy, enemy.enemy_data.moves[0])
	EnemyMechanics.after_action(b, enemy, enemy.enemy_data.moves[0])
	check(Achievements.progress("rail_clear") == 1, "清轨真实奖励路径只记一次")
	# 蔓生：使用与净化都能阻止；已实际复制的母字不能刷该条件。
	fresh(); b = battle()
	b.board.cells.fill(null)
	b.inject_enemy_glyphs(1, "replicate", "连", 11)
	var inst: CharInstance = b.board.cells.filter(func(c): return c != null)[0]
	check(b.try_play([EnemyMechanics.pos(b, inst)]).ok and Achievements.progress("replicate_stop_3") == 1, "首次复制前实际用掉蔓生字")
	b.inject_enemy_glyphs(1, "replicate", "连", 11)
	inst = b.board.cells.filter(func(c): return c != null)[0]
	inst.statuses.achievement_replicated = true
	b.try_play([EnemyMechanics.pos(b, inst)])
	check(Achievements.progress("replicate_stop_3") == 1, "已复制母字不再算提前阻止")
	b.board.cells.fill(null)
	b.inject_enemy_glyphs(1, "replicate", "连", 11)
	inst = b.board.cells.filter(func(c): return c != null)[0]
	var pos := EnemyMechanics.pos(b, inst)
	var clean_pos := b.board.neighbors(pos)[0] as Vector2i
	b.board.set_xy(clean_pos, CharInstance.new(Database.get_character_by_glyph("洗")))
	b.try_play([clean_pos], {"tile":pos})
	check(Achievements.progress("replicate_stop_3") == 2 and inst.is_enemy_owned() and inst.pollutions.is_empty(), "实际净化保留敌方字也计提前阻止")
	# 灼烧死亡与指定Boss死亡均来自真实扣血路径。
	fresh(); b = battle("boss_lead_plate")
	enemy = b.enemies[0]; enemy.hp = 1
	b.deal_damage(enemy, 2, false)
	check(Achievements.is_unlocked("boss_plate"), "指定首领死亡触发对应成就")
	fresh(); b = battle()
	enemy = b.enemies[0]; enemy.hp = 1; enemy.add_status("burn", 1); b.player.heat = 1
	b._enemy_act(enemy)
	check(Achievements.is_unlocked("burn_kill"), "敌人因实际灼烧死亡触发")
	# 镀金收益按实际入账，不把触及本场金币上限的部分算进去。
	fresh(); b = battle()
	b.rules.gold_cap_per_battle = 1
	path = place(b, "击")
	b.board.get_xy(path[0]).gilded = true
	var prior = BattleBalance.values.get("core/gild_gold", 1)
	BattleBalance.values["core/gild_gold"] = 3
	b.try_play(path)
	check(Achievements.progress("gild_gold_10") == 1, "镀金只计实际入账1，未按配置3虚增")
	BattleBalance.values["core/gild_gold"] = prior
	# 作用域：单战记录不能跨战凑；账号最好记录继续展示。
	fresh(); b = battle()
	b.achievement.emit_metrics([{"metric":"pollution_cleansed","amount":3}])
	b.achievement.finish(false)
	GameState.node_index += 1
	b = battle()
	b.achievement.emit_metrics([{"metric":"pollution_cleansed","amount":3}])
	check(not Achievements.is_unlocked("cleanse_5") and Achievements.progress("cleanse_50") == 6, "单战重置但累计叠加")
	# 修改阈值/前置时重新判定，已解锁不收回。
	Achievements.by_id.cleanse_5.target = 3
	Achievements._recheck()
	check(Achievements.is_unlocked("cleanse_5"), "降低Excel目标后可按既有记录重判")
	Achievements.by_id.cleanse_5.target = 999
	Achievements._recheck()
	check(Achievements.is_unlocked("cleanse_5"), "提高目标不收回已解锁")
	Achievements.reload_catalog()
	# 同一流回放、旧档及损坏备份防护。
	fresh()
	Achievements.commit("", [{"metric":"word_plays","amount":1}], {}, "test_stream", 1)
	Achievements.commit("", [{"metric":"word_plays","amount":1000}], {}, "test_stream", 1)
	check(Achievements.progress("words_100") == 1, "重复事实流不再次累计")
	check(not Achievements._valid_save({"version":1,"unlocked":{},"best":{},"sessions":{"bad":null},"lifetime":{}}), "损坏的作用域快照拒绝加载")
	# 提示队列，不拦截输入，长文不会拉成满屏卡片。
	fresh()
	var previous_toast: CanvasLayer = Achievements._toast
	var toast := preload("res://src/ui/achievement_toast.gd").new()
	add_child(toast)
	Achievements._toast = toast
	Achievements.commit("real_unlock", [{"metric":"word_plays","amount":100}])
	toast.enqueue("words_100")
	for i in 5: await get_tree().process_frame
	check(toast.pending.size() == 1 and toast.current_id == "first_word", "真实解锁自动提示，连续解锁排队并去重")
	check(toast.card.size.y < 170 and toast.card.mouse_filter == Control.MOUSE_FILTER_IGNORE, "提示紧凑且不挡操作")
	toast._process(5)
	check(toast.current_id == "words_100", "提示队列依次显示")
	Achievements._toast = previous_toast
	toast.queue_free()
	Achievements.suspend_run()
	print("[achievement_hooks_test] PASS=%d FAIL=%d TOTAL=%d" % [checks - failures, failures, checks])
	get_tree().quit(1 if failures else 0)
