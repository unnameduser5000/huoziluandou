extends Node
var checks := 0
var failures := 0
var notifications: Array = []
var original_definitions: Array
var storage := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("[achievement_system_test] " + message)

func fresh() -> void:
	Achievements.suspend_run()
	Achievements.profile = {"version": 1, "unlocked": {}, "lifetime": {}, "best": {}, "sessions": {}}
	GameState.start_new_run("v03")
	Achievements.start_run("test")
	notifications.clear()

func battle(enemy_id := "ink_spirit") -> BattleState:
	var rules := Database.rules.duplicate() as BattleRules
	rules.opening_draw = 0; rules.turn_draw = 0
	var ed := Database.get_enemy(enemy_id).duplicate(true) as EnemyData
	ed.max_hp = 1000; ed.initial_block = 0
	var state := BattleState.new(rules)
	state.start(GameState.deck, [ed], 1234, true)
	return state

func place(state: BattleState, glyphs: String, temporary := false) -> Array:
	state.board.cells.fill(null)
	var path: Array = []
	for i in glyphs.length():
		var inst := CharInstance.new(Database.get_character_by_glyph(glyphs[i]))
		inst.temporary = temporary
		state.board.set_cell(i, 0, inst)
		path.append(Vector2i(i, 0))
	return path

func _ready() -> void:
	storage = "user://achievement-system-test-%d.json" % Time.get_ticks_usec()
	Achievements.storage_path = storage
	Achievements.test_enabled = true
	Achievements.autosave = false
	Achievements.unlocked.connect(func(id): notifications.append(id))
	original_definitions = Achievements.definitions.duplicate(true)
	check(Achievements.definitions.size() == 48, "加载48项可配置成就")
	for definition in Achievements.definitions:
		check(not definition.description.is_empty() and not definition.description.contains("{target}"), "使用目标值渲染的达成条件：" + definition.id)
		check(AchievementArt.texture(definition) != null, "玉符图案已接入：" + definition.id)
	fresh()
	var b := battle()
	check(b.achievement != null, "正式战斗创建观察器")
	check(not b.try_play([Vector2i.ZERO]).ok and Achievements.progress("first_word") == 0, "无效路径不推进成就")
	var path := place(b, "击破")
	check(b.try_play(path).ok, "真实组词成功")
	check(Achievements.is_unlocked("first_word") and notifications.count("first_word") == 1, "首次组词解锁并通知一次")
	b.enable_ability("repeat", 1); b.repeat_armed = true
	b.try_play(place(b, "击破"))
	check(Achievements.progress("words_100") == 2 and Achievements.progress("vocab_10") == 1, "重演不重复记出词；同词不增加种类")
	check(notifications.count("first_word") == 1, "再次达成不重复弹出")
	b.begin_player_turn(false)
	b.try_play(place(b, "击破"))
	check(Achievements.progress("turn_words_5") == 2 and Achievements.progress("words_100") == 3, "回合范围重置，累计和最高记录保留")
	var rng_before := b.rng.state
	var hp_before := b.player.hp
	Achievements.progress("first_word"); AchievementArt.title(Achievements.definitions[0])
	check(b.rng.state == rng_before and b.player.hp == hp_before, "查询与图标不改变随机数或战斗状态")
	# 前置尚未解锁也计数，条件变化后能重新判定完整前置链。
	Achievements.by_id.words_100.target = 2
	Achievements.reload_catalog() # 重载还原原配置，不回退已解锁记录。
	check(Achievements.is_unlocked("first_word") and not Achievements.is_unlocked("words_100"), "配置重载不会误解锁或收回旧成就")
	fresh(); b = battle()
	b.player.add_energy(11)
	b.achievement.sample()
	check(b.try_play(place(b, "充放电")).ok, "实际多段放电")
	check(Achievements.is_unlocked("spend_energy_10") and Achievements.is_unlocked("hits_10"), "实付储能和实际命中段数触发")
	check(Achievements.progress("hits_10") == 11, "一次攻击段数完整合并")
	b.player.heat = 12
	b.try_play(place(b, "冷热"))
	check(Achievements.is_unlocked("cool_10") and Achievements.is_unlocked("shield_20"), "实际降温与持久盾触发")
	fresh(); b = battle()
	var enemy: Combatant = b.enemies[0]
	enemy.hp = 3; enemy.block = 2
	b.deal_damage(enemy, 500, true)
	check(Achievements.progress("damage_20") == 5, "攻击伤害只计实际扣血与吸盾，不含溢出")
	b.achievement.finish(true); b.achievement.finish(true)
	check(Achievements.progress("first_battle") == 1 and Achievements.is_unlocked("flawless_win"), "胜利幂等，无损结算")
	fresh(); b = battle()
	b.player.take_damage(1); b.heal_player(1); b.enemies[0].hp = 0
	b.achievement.finish(true)
	check(not Achievements.is_unlocked("flawless_win"), "先受伤再治疗不能获得无损")
	fresh(); b = battle()
	path = place(b, "击破", true)
	b.board.get_xy(path[0]).add_pollution("rush")
	b.board.get_xy(path[1]).temporary_uses = 2
	b.try_play(path)
	check(Achievements.progress("temp_words_10") == 2 and Achievements.progress("polluted_words_20") == 1, "临时字及污染字按参与字块统计")
	check(Achievements.progress("extra_use_5") == 1, "只记录实际扣除额外次数")
	var inst := CharInstance.new(Database.get_character_by_glyph("击"))
	inst.add_pollution("rush"); inst.add_pollution("block")
	b.board.set_cell(0, 1, inst)
	var clean_before := Achievements.progress("first_cleanse")
	b.cleanse_board()
	var clean_after := Achievements.progress("first_cleanse")
	b.cleanse_board()
	check(clean_after - clean_before == 2 and Achievements.progress("first_cleanse") == clean_after, "净化按标签数计，无污染不重复计")
	place(b, "击击")
	check(b.refine_pair(Vector2i.ZERO, Vector2i.RIGHT).ok and Achievements.is_unlocked("first_refine"), "真实精炼成功触发")
	check(not b.refine_pair(Vector2i.ZERO, Vector2i.RIGHT).ok and Achievements.progress("first_refine") == 1, "失败精炼不触发")
	place(b, "击破")
	check(b.fuse_cards(Vector2i.ZERO, Vector2i.RIGHT).ok and Achievements.is_unlocked("first_fusion"), "真实融合成功触发")
	fresh()
	inst = GameState.deck[0]
	check(GameState.gild_character(inst) and Achievements.is_unlocked("first_gild"), "永久镀金真实入口触发")
	check(not GameState.gild_character(inst) and Achievements.progress("first_gild") == 1, "同字重复镀金不触发")
	var offers: Array = [{"kind":"buy_char"},{"kind":"heal"}]
	Achievements.register_offers(offers)
	Achievements.bought_offer(offers[0]); Achievements.bought_offer(offers[0]); Achievements.bought_offer(offers[1])
	check(Achievements.progress("shop_5") == 2, "交易ID防止重复回调购买")
	Achievements.node_completed("room:1:test"); Achievements.node_completed("room:1:test")
	check(Achievements.progress("nodes_20") == 1, "节点重复访问不重复记")
	Achievements.event_completed("event_a", "room_a"); Achievements.event_completed("event_a", "room_b"); Achievements.event_completed("event_b", "room_c")
	check(Achievements.progress("events_10") == 2, "事件按ID去重")
	for id in Relics.DEFS.keys().slice(0, 5): GameState.add_relic(id)
	check(Achievements.progress("relics_5") == 5, "遗物统计同时持有的不同ID")
	var snapshot := Achievements.export_run()
	Achievements.autosave = true
	check(Achievements.save_progress() == OK and FileAccess.file_exists(storage), "原子保存跨局进度")
	var before := Achievements.progress("nodes_20")
	Achievements.suspend_run(); Achievements.load_progress(); Achievements.resume_run(snapshot)
	Achievements.node_completed("room:1:test")
	check(Achievements.progress("nodes_20") == before, "重启读档后仍然去重")
	Achievements.finish_run(true); Achievements.finish_run(true)
	check(Achievements.progress("first_clear") == 1, "通关只结算一次")
	Achievements.start_run("new")
	check(Achievements.is_unlocked("first_word") == false and Achievements.is_unlocked("first_gild"), "新局保留账号已解锁成就")
	Achievements.invalidate_run(); Achievements.gilded(GameState.deck[1])
	check(Achievements.progress("first_gild") == 1, "作弊局后续不计成就")
	GameState.start_new_run("v03", ["击"]); Achievements.start_run("custom")
	Achievements.commit("fake", [{"metric":"word_plays","amount":10000}])
	check(not Achievements.is_unlocked("words_1000"), "自定义构筑局不计成就")
	GameState.start_new_run("v03"); Achievements.start_run("ui")
	var overlay := AchievementOverlay.new()
	add_child(overlay)
	await get_tree().process_frame
	await get_tree().process_frame
	check(overlay.grid.get_child_count() == 48, "总览展示48项包括隐藏项及其条件")
	var texts := ""
	for card in overlay.grid.get_children():
		for label in card.find_children("*", "Label", true, false): texts += label.text
	check(texts.contains("已解锁") and texts.contains("未解锁") and texts.contains("达成条件") and texts.contains("最高记录") and texts.contains("需先解锁"), "总览明确状态、条件、最高进度与前置")
	var first_card: Control = overlay.grid.get_child(0)
	var blockers: Array = [first_card, first_card.get_child(0), first_card.get_child(0).get_child(0)]
	check(blockers.all(func(n): return n.mouse_filter != Control.MOUSE_FILTER_STOP), "成就卡不拦截滚动事件")
	check(overlay.scroll.get_v_scroll_bar().max_value > 0, "成就列表在可滚动容器里")
	overlay.state_filter.select(1); overlay._refresh()
	check(overlay.grid.get_child_count() == Achievements.profile.unlocked.size(), "已解锁筛选正确")
	overlay.state_filter.select(2); overlay._refresh()
	check(overlay.grid.get_child_count() == 48 - Achievements.profile.unlocked.size(), "未解锁筛选正确")
	overlay.queue_free()
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(storage + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(storage + suffix))
	Achievements.autosave = false
	Achievements.suspend_run()
	print("[achievement_system_test] PASS=%d FAIL=%d TOTAL=%d" % [checks - failures, failures, checks])
	get_tree().quit(1 if failures else 0)
