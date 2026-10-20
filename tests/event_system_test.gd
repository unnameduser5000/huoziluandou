extends Control
const CATALOG = preload("res://src/data/event_catalog.gd")
const EFFECTS = preload("res://src/core/event_effects.gd")
const RUN = preload("res://src/core/run_harness.gd")
const ROOM_RUN = preload("res://src/expedition/room_run_state.gd")
const LANTERN = preload("res://src/data/lantern_riddles.gd")
const SHEFU = preload("res://src/data/shefu_rewards.gd")
var _pass := 0
var _fail := 0


func _ready() -> void:
	SaveManager.enabled = false
	GameState.set_meta("courtyard_preview", true)
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass += 1
		print("  ✓ ", message)
	else:
		_fail += 1
		push_error(message)


func _run() -> void:
	var ids := {}
	for event: Dictionary in CATALOG.EVENTS:
		_check(not ids.has(event.id), "事件 ID 唯一：" + event.id)
		ids[event.id] = true
		_check(not str(event.get("title", "")).is_empty() and not str(event.get("body", "")).is_empty(), event.id + " 有标题和正文")
		_check(event.get("options", []).size() >= 2, event.id + " 至少有两个选项")
		_check(event.get("options", []).size() == 3, event.id + " 保持三个选项的固定结构")
		_check(not (event.get("acts", []) as Array).is_empty(), event.id + " 标注可用幕")
		_check(event.get("tags", []) is Array, event.id + " 带检索标签")
		for option: Dictionary in event.options:
			_check(option.has("effects") and option.effects is Array, event.id + " 的选项效果是可校验的数据")
			for effect: Dictionary in option.effects:
				_check(str(effect.get("type", "")) in ["damage", "heal", "heal_percent", "gold", "max_hp", "permanent_damage_reduction", "event_temp_hp", "clear_event_temp_hp", "gain_character", "gain_pollution", "remove_pollution", "gain_relic", "remove_relic", "remove_character", "if", "borrow_life", "repay_life_hp", "repay_life_max_hp", "refuse_debt", "spend_gold"], "效果类型受支持：" + str(effect.get("type", "")))

	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for act in [1, 2, 3]:
		var pool: Array = EFFECTS.pool(act)
		_check(not pool.is_empty(), "第%d幕有可用事件池" % act)
		for event: Dictionary in pool:
			_check((event.get("acts", []) as Array).has(act), "第%d幕事件池只含本幕事件：%s" % [act, event.id])
	var rolled: Dictionary = EFFECTS.roll(1, rng)
	_check(not rolled.is_empty() and (rolled.get("acts", []) as Array).has(1), "roll 按幕过滤事件")
	var act_one: Array = EFFECTS.pool(1)
	var avoided: Dictionary = EFFECTS.roll(1, rng, [str(act_one[0].id)])
	_check(avoided.id != str(act_one[0].id), "roll 优先避开本局已出现的事件")
	var exhausted: Array = act_one.map(func(event): return str(event.id))
	var fallback: Dictionary = EFFECTS.roll(1, rng, exhausted)
	_check(not fallback.is_empty() and (fallback.get("acts", []) as Array).has(1), "事件全部用完后回退到本幕完整池")

	GameState.player_max_hp = 60
	GameState.player_hp = 20
	var percent: Dictionary = EFFECTS.resolve([{"type": "heal_percent", "amount": 25}], rng)
	_check(percent.ok and GameState.player_hp == 35, "heal_percent 按最大气血结算")
	GameState.player_max_hp = 60
	GameState.player_hp = 60
	var cap: Dictionary = EFFECTS.resolve([{"type": "max_hp", "amount": 4}, {"type": "heal", "amount": 4}], rng)
	_check(cap.ok and GameState.player_max_hp == 64 and GameState.player_hp == 64, "max_hp 提升上限并保留治疗量")
	var deck_before: int = GameState.deck_size()
	var pollution: Dictionary = EFFECTS.resolve([{"type": "gain_pollution", "count": 1}], rng)
	_check(pollution.ok and GameState.deck_size() == deck_before + 1 and GameState.deck[-1].data.is_pollution, "gain_pollution 把污染字加入字袋")
	deck_before = GameState.deck_size()
	var specific: Dictionary = EFFECTS.resolve([{"type": "gain_character", "glyph": "息"}], rng)
	_check(specific.ok and GameState.deck_size() == deck_before + 1 and GameState.deck[-1].glyph() == "息", "gain_character 可以指定字形")
	var unknown: Dictionary = EFFECTS.resolve([{"type": "missing"}], rng)
	_check(not unknown.ok, "未知事件效果被拒绝")
	GameState.event_temp_hp = 0
	GameState.player_hp = 20
	var borrowed: Dictionary = EFFECTS.resolve([{"type": "event_temp_hp", "amount": 12}, {"type": "damage", "amount": 8}], rng)
	_check(borrowed.ok and GameState.event_temp_hp == 4 and GameState.player_hp == 20, "临时气血优先吸收事件伤害")
	GameState.clear_event_temp_hp()
	_check(EFFECTS.condition_met({"type": "has_glyph", "glyph": "息"}), "条件可以检查持有特定字")
	var event_relic: Dictionary = EFFECTS.resolve([{"type": "gain_relic", "relic": "black_water"}], rng)
	_check(event_relic.ok and GameState.has_relic("black_water"), "事件可以获得事件遗物")
	GameState.relics.clear(); GameState.relic_binds.clear(); GameState.relic_counters.clear()
	var random_event_relic: Dictionary = EFFECTS.resolve([{"type": "gain_relic", "relic": "random", "pool": "event"}], rng)
	_check(random_event_relic.ok and GameState.relics.size() == 1 and Relics.is_event_relic(str(GameState.relics[0])), "事件随机池只发事件遗物：%s" % [GameState.relics])
	# 新遗物事件：投钱、概率、随机普通遗物
	GameState.relics.clear(); GameState.relic_binds.clear(); GameState.relic_counters.clear()
	GameState.gold = 3
	var poor_spend: Dictionary = EFFECTS.resolve([{"type": "spend_gold", "amount": 5}], rng)
	_check(not poor_spend.ok and GameState.gold == 3, "铜钱不足时事件投入失败")
	GameState.gold = 20
	var spend: Dictionary = EFFECTS.resolve([{"type": "spend_gold", "amount": 8}], rng)
	_check(spend.ok and GameState.gold == 12, "事件可以投入铜钱")
	var miss: Dictionary = EFFECTS.resolve([{"type": "gain_relic", "relic": "random", "chance": 0.0, "fallback_gold": 7}], rng)
	_check(miss.ok and GameState.relics.is_empty() and GameState.gold == 19, "概率失败时只拿保底铜钱")
	var hit: Dictionary = EFFECTS.resolve([{"type": "gain_relic", "relic": "random", "chance": 1.0}], rng)
	_check(hit.ok and GameState.relics.size() == 1 and not Relics.is_event_relic(str(GameState.relics[0])), "概率成功时只发普通遗物：%s" % [GameState.relics])
	var jade: Dictionary = EFFECTS.get_event("jade_case")
	_check(jade.get("nodes", {}).size() == 5 and jade.options.size() == 3, "韫椟待贾有 5 个连续节点和 3 个入口选项")
	_check(EFFECTS.node(jade, "one").options[1].effects[0].chance == 0.25, "韫椟待贾第二节点显示 25% 概率")
	# 无字灯：谜面随机抽三题，答案和隐藏收益不显示
	var lantern_options: Array = LANTERN.roll(rng)
	_check(lantern_options.size() == 3, "无字灯一次抽三题")
	var answers: Array = []
	for opt: Dictionary in lantern_options:
		var answer := ""
		for effect: Dictionary in opt.effects:
			if str(effect.get("type", "")) == "gain_character": answer = str(effect.get("glyph", ""))
		answers.append(answer)
		_check(not answer.is_empty() and not str(opt.text).contains(answer) and not str(opt.text).contains("气血") and not str(opt.text).contains("铜钱"), "灯谜选项只显示谜面：%s" % opt.text)
	_check(answers.size() == 3 and answers[0] != answers[1] and answers[1] != answers[2] and answers[0] != answers[2], "无字灯三题答案不重复：%s" % [answers])
	GameState.start_new_run("v03")
	GameState.player_max_hp = 60; GameState.player_hp = 50; GameState.gold = 0
	var lantern_answer: String = answers[0]
	var lantern_result: Dictionary = EFFECTS.resolve(lantern_options[0].effects, rng)
	_check(lantern_result.ok and GameState.glyph_counts().has(lantern_answer), "无字灯按谜底发放字：%s" % lantern_answer)
	var shefu_a: Array = SHEFU.build(4242)
	var shefu_b: Array = SHEFU.build(4242)
	_check(shefu_a.size() == 3 and shefu_a[0].effects == shefu_b[0].effects, "射覆用固定种子生成同一组奖励")
	var shefu_character_count := 0
	for opt: Dictionary in shefu_a:
		_check(not str(opt.text).contains("铜钱") and not str(opt.text).contains("气血") and not str(opt.text).contains("遗物"), "射覆选项不显示奖励内容：%s" % opt.text)
		for effect: Dictionary in opt.effects:
			if str(effect.type) == "gain_character": shefu_character_count += 1
	_check(shefu_character_count == 1, "射覆三只碗只有一只藏稀有字")
	var shefu_room = ROOM_RUN.new()
	shefu_room.reset({"seed": 7309}); shefu_room.autosave = false
	shefu_room.phase = "event"; shefu_room.event_node = "start"
	shefu_room.event_data = SHEFU.fill(EFFECTS.get_event("shefu"), rng)
	var sf_deck := GameState.deck_size()
	var sf_index := 0
	for i in shefu_room.event_data.options.size():
		if not shefu_room.event_data.options[i].effects.is_empty(): sf_index = i
	var sf_result: Dictionary = shefu_room.apply({"type": "event", "index": sf_index})
	_check(sf_result.ok and shefu_room.phase == "map" and GameState.deck_size() > sf_deck, "射覆选择有字碗后只结算该碗")
	var leave_room = ROOM_RUN.new()
	leave_room.reset({"seed": 7308}); leave_room.autosave = false
	leave_room.phase = "event"; leave_room.event_node = "start"
	leave_room.event_data = EFFECTS.get_event("old_gardener").duplicate(true)
	var leave_hp: int = GameState.player_hp
	var leave_deck: int = GameState.deck_size()
	var leave_result: Dictionary = leave_room.apply({"type": "event_leave"})
	_check(leave_result.ok and leave_room.phase == "map" and GameState.player_hp == leave_hp and GameState.deck_size() == leave_deck, "纯益事件可以空手离开")
	var lore_room = ROOM_RUN.new()
	lore_room.reset({"seed": 7309}); lore_room.autosave = false
	lore_room.phase = "event"; lore_room.event_node = "start"
	lore_room.event_data = EFFECTS.get_event("old_gardener").duplicate(true)
	var lore_max: int = GameState.player_max_hp
	_check(lore_room.apply({"type": "event", "index": 2}).ok and GameState.player_max_hp == lore_max + 10, "老园丁：听旧事最大气血 +10")
	var battle_relic_room = ROOM_RUN.new()
	battle_relic_room.reset({"seed": 7307}); battle_relic_room.autosave = false
	battle_relic_room.phase = "event"; battle_relic_room.event_node = "start"
	battle_relic_room.event_data = EFFECTS.get_event("battle_relic").duplicate(true)
	var battle_relic_before: int = GameState.relics.size()
	var battle_start: Dictionary = battle_relic_room.apply({"type": "event", "index": 0})
	_check(battle_start.ok and battle_relic_room.phase == "encounter" and battle_relic_room.spawned_battle, "死地取器进入事件战斗")
	battle_relic_room.begin_live_battle()
	battle_relic_room.finish_live_battle(true)
	_check(battle_relic_room.phase == "event_relic" and GameState.relics.size() == battle_relic_before, "死地取器胜利后先展示遗物，不强制拾取")
	var claim: Dictionary = battle_relic_room.apply({"type":"event_relic_take"})
	_check(claim.ok and battle_relic_room.phase == "map" and GameState.relics.size() == battle_relic_before + 1, "死地取器确认后才获得遗物")
	var chaos_room = ROOM_RUN.new()
	chaos_room.reset({"seed": 7306}); chaos_room.autosave = false
	chaos_room.phase = "event"; chaos_room.event_node = "start"
	chaos_room.event_data = EFFECTS.get_event("chaos_dice").duplicate(true)
	var chaos_before: int = GameState.deck_size()
	var chaos_apply: Dictionary = chaos_room.apply({"type": "event", "index": 0})
	_check(chaos_apply.ok and GameState.has_relic("chaos_dice") and GameState.deck_size() == chaos_before + 3, "乱文骨骰事件发放指定遗物并重铸字袋")
	var lantern_room = ROOM_RUN.new()
	lantern_room.reset({"seed": 7305}); lantern_room.autosave = false
	lantern_room.phase = "event"; lantern_room.event_node = "start"
	lantern_room.event_data = LANTERN.fill(EFFECTS.get_event("lantern_riddle"), rng)
	var lantern_room_answer := ""
	for effect: Dictionary in lantern_room.event_data.options[0].effects:
		if str(effect.get("type", "")) == "gain_character": lantern_room_answer = str(effect.get("glyph", ""))
	var lantern_apply: Dictionary = lantern_room.apply({"type": "event", "index": 0})
	_check(lantern_apply.ok and lantern_room.phase == "map" and GameState.glyph_counts().has(lantern_room_answer), "无字灯在庭院事件流程中结算一次")
	var jade_room = ROOM_RUN.new()
	jade_room.reset({"seed": 7304}); jade_room.autosave = false
	jade_room.phase = "event"; jade_room.event_node = "start"
	jade_room.event_data = jade.duplicate(true)
	GameState.gold = 100
	var invest: Dictionary = jade_room.apply({"type": "event", "index": 0})
	_check(invest.ok and jade_room.phase == "event" and jade_room.event_node == "one" and GameState.gold == 92, "韫椟待贾投钱后进入下一节点并扣 8 铜钱")
	_check("玉声近了" in str(jade_room.current_event().get("body", "")), "试椟的玉声反馈写进事件正文，且只有一句")
	var jade_texts: Array = EFFECTS.node(jade, "one").options.map(func(o): return str(o.text))
	_check(jade_texts.all(func(t): return not t.contains("失败得")), "开椟选项不提前说明赌输返还：%s" % [jade_texts])
	var gamble: Dictionary = EFFECTS.resolve([{"type": "gain_relic", "relic": "random", "chance": 0.0, "fallback_gold": 10}], rng, true)
	_check(gamble.ok and (gamble.get("notes", []) as Array).has("开椟（未得遗物，返还 10 铜钱）"), "赌输后才给出「行动（效果）」格式的结果文案")
	# 删字与净化：条件、稀有度过滤、连续删两枚
	GameState.start_new_run("v03")
	GameState.player_max_hp = 60
	GameState.player_hp = 60
	var rare: CharacterData = null
	for c: CharacterData in Database.characters.values():
		if not c.is_pollution and not c.pending_design and not c.tags.has("enemy") and c.rarity >= 2:
			rare = c; break
	_check(rare != null, "找到可测试的稀有字")
	if rare != null:
		GameState.add_character(rare)
	_check(EFFECTS.condition_met({"type": "has_character_min_rarity", "amount": 2}), "可以检查字袋里是否有稀有字")
	var rare_pending: Dictionary = EFFECTS.resolve([{"type": "remove_character", "count": 1, "min_rarity": 2, "max_rarity": 4}], rng)
	var rare_glyphs: Array = rare_pending.get("pending", {}).get("glyphs", [])
	_check(rare_pending.ok and rare_glyphs.has(rare.glyph), "稀有字删除浮层只列出稀有字")
	if not rare_glyphs.is_empty():
		var rare_pick: Dictionary = EFFECTS.resume(rare_pending.pending, str(rare_glyphs[0]), rng)
		_check(rare_pick.ok and rare_pick.get("pending", {}).is_empty(), "稀有字删除可以结算")
	GameState.start_new_run("v03")
	var pollution_before: int = GameState.deck.filter(func(inst): return inst.data != null and inst.data.is_pollution).size()
	GameState.add_character(Database.get_character("debt"))
	_check(EFFECTS.condition_met({"type": "pollution_count_at_least", "amount": 1}), "可以检查污染字数量")
	var purge: Dictionary = EFFECTS.resolve([{"type": "remove_pollution", "count": 99}, {"type": "max_hp", "amount": -3}], rng)
	var pollution_after: int = GameState.deck.filter(func(inst): return inst.data != null and inst.data.is_pollution).size()
	_check(purge.ok and pollution_after == pollution_before and GameState.player_max_hp == 57, "涤除清空污染字并扣 3 最大气血")
	var multi: Dictionary = EFFECTS.resolve([{"type": "remove_character", "count": 2}, {"type": "damage", "amount": 5}, {"type": "gain_character", "min_rarity": 2, "max_rarity": 4}], rng)
	_check(multi.ok and int(multi.get("pending", {}).get("remaining", 0)) == 2, "裁字可以进入连删两枚阶段")
	if multi.ok:
		var first_glyph := str(multi.pending.glyphs[0])
		var first_pick: Dictionary = EFFECTS.resume(multi.pending, first_glyph, rng)
		var second_glyph := str(first_pick.get("pending", {}).get("glyphs", [""])[0])
		var second_pick: Dictionary = EFFECTS.resume(first_pick.pending, second_glyph, rng)
		_check(second_pick.ok and second_pick.get("pending", {}).is_empty() and GameState.player_hp <= 55, "连续删两枚后结算扣血和稀有字")

	var harness = RUN.new()
	harness.reset({"seed": 7301})
	harness.phase = "event"
	harness.event_data = EFFECTS.get_event("ink_pool")
	var gold: int = GameState.gold
	var node_index: int = GameState.node_index
	var invalid: Dictionary = harness.apply({"type": "event", "index": 99})
	_check(not invalid.ok and GameState.gold == gold and GameState.node_index == node_index, "无效事件选择被拒绝且不改变状态")
	var valid: Dictionary = harness.apply({"type": "event", "index": 1})
	_check(valid.ok and GameState.gold == gold + 18 and harness.phase == "map" and GameState.node_index == node_index + 1, "自动化流程按目录结算铜钱并推进")

	harness.reset({"seed": 7302})
	harness.phase = "event"
	harness.event_data = EFFECTS.get_event("old_bookshop")
	var size_before: int = GameState.deck_size()
	var removal: Dictionary = harness.apply({"type": "event", "index": 0})
	var pick_actions: Array = harness.legal_actions()
	_check(removal.ok and harness.phase == "event_choose" and not pick_actions.is_empty(), "删字事件进入显式的待选字阶段")
	var chosen: String = str(pick_actions[0].glyph)
	var picked: Dictionary = harness.apply({"type": "pick", "glyph": chosen})
	_check(picked.ok and harness.phase == "map" and GameState.deck_size() == size_before - 1, "自动化流程完成删字并只推进一次")
	var repeated: Dictionary = harness.apply({"type": "pick", "glyph": chosen})
	_check(not repeated.ok and GameState.deck_size() == size_before - 1, "重复提交旧字选择不会重复结算")

	var room = ROOM_RUN.new()
	room.reset({"seed": 7303})
	var event_rooms: Array = room.graph.rooms.keys().filter(func(id): return room.graph.rooms[id].kind == "event")
	_check(not event_rooms.is_empty(), "房间图生成事件房")
	if not event_rooms.is_empty():
		room.current_room = event_rooms[0]
		room.visited_rooms[room.current_room] = true
		room.resolved[room.current_room] = true
		room.phase = "event"
		room.event_data = EFFECTS.get_event("old_bookshop").duplicate(true)
		size_before = GameState.deck_size()
		var room_pick: Dictionary = room.apply({"type": "event", "index": 0})
		var room_choose: Array = room.legal_actions()
		_check(room_pick.ok and room.phase == "event_choose" and not room_choose.is_empty(), "庭院模式共用事件目录与删字阶段")
		var save_path := "user://event-system-test.tres"
		var save_error: int = room.save_run(save_path)
		_check(save_error == OK, "待选事件效果可以保存")
		if save_error == OK:
			var restored = ROOM_RUN.restore(save_path)
			_check(restored != null and restored.phase == "event_choose" and restored.pending_event_effect.type == "remove_character", "读档恢复事件的待选效果")
			if restored != null:
				room = restored
				room_choose = room.legal_actions()
				var room_chosen: String = str(room_choose[0].glyph)
				var room_result: Dictionary = room.apply({"type": "pick", "glyph": room_chosen})
				_check(room_result.ok and room.phase == "map" and GameState.deck_size() == size_before - 1, "庭院模式读档后共用删字结算")
			DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	var branch_room = ROOM_RUN.new()
	branch_room.reset({"seed": 7304})
	var branch_event_rooms: Array = branch_room.graph.rooms.keys().filter(func(id): return branch_room.graph.rooms[id].kind == "event")
	if not branch_event_rooms.is_empty():
		branch_room.current_room = branch_event_rooms[0]
		branch_room.visited_rooms[branch_room.current_room] = true
		branch_room.resolved[branch_room.current_room] = true
		_check(not EFFECTS.pool(GameState.act_index).any(func(event): return str(event.id) == "debt_collector"), "没有寿契时讨债事件不进池")
		branch_room.phase = "event"
		branch_room.event_data = EFFECTS.get_event("borrow_life").duplicate(true)
		GameState.player_hp = 20
		var hp_before_borrow: int = GameState.player_hp
		var borrow_result: Dictionary = branch_room.apply({"type": "event", "index": 0})
		_check(borrow_result.ok and GameState.has_relic("life_debt") and EFFECTS.debt_amount() == 8 and GameState.player_hp == hp_before_borrow + 8, "借寿立刻回血并记下寿债")
		_check(EFFECTS.pool(GameState.act_index).any(func(event): return str(event.id) == "debt_collector"), "持有寿契后讨债事件进入事件池")
		branch_room.phase = "event"
		branch_room.event_data = EFFECTS.get_event("debt_collector").duplicate(true)
		var max_before_debt: int = GameState.player_max_hp
		var debt_before_pay: int = EFFECTS.debt_amount()
		var repay_result: Dictionary = branch_room.apply({"type": "event", "index": 1})
		_check(repay_result.ok and not GameState.has_relic("life_debt") and GameState.player_max_hp == max_before_debt - int(ceil(debt_before_pay / 2.0)), "讨债可以按 2:1 折算为最大气血")

	var event_probe = ROOM_RUN.new()
	event_probe.reset({"seed": 7304})
	event_probe.autosave = false
	event_probe._start_event()
	var first_event := str(event_probe.event_data.get("id", ""))
	_check(not first_event.is_empty() and event_probe.seen_events.has(first_event), "首次抽取的事件记入已出现列表")
	event_probe._start_event()
	_check(str(event_probe.event_data.get("id", "")) != first_event, "同一局再次抽取时避开已出现事件")
	var seen_path := "user://event-seen-test.tres"
	var seen_saved: int = event_probe.save_run(seen_path)
	_check(seen_saved == OK, "已出现事件列表可以保存")
	if seen_saved == OK:
		var seen_restored = ROOM_RUN.restore(seen_path)
		_check(seen_restored != null and seen_restored.seen_events.has(first_event), "读档恢复已出现事件列表")
		_check(seen_restored.event_bags==event_probe.event_bags and seen_restored.last_event_id==event_probe.last_event_id,"读档保留当前抽取袋和上次事件")
		event_probe._start_event()
		var expected_id: String = event_probe.event_data.id
		seen_restored = ROOM_RUN.restore(seen_path)
		seen_restored._start_event()
		_check(seen_restored.event_data.id==expected_id,"保存的随机状态保证下一事件不因读档重抽")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(seen_path))
	var cycle = ROOM_RUN.new(); cycle.reset({"seed":7310}); cycle.autosave = false
	var cycle_ids := []
	for i in EFFECTS.pool(1).size():
		cycle._start_event()
		_check(not cycle_ids.has(cycle.event_data.id),"本幕抽取袋耗尽前事件不重复")
		cycle_ids.append(cycle.event_data.id)
	var previous_id: String = cycle.event_data.id
	cycle._start_event()
	_check(cycle.event_data.id!=previous_id,"新一轮抽取不紧接着重复上次事件")
	cycle.event_bags["1"] = ["debt_collector"]
	cycle._start_event()
	_check(EFFECTS.pool(1).any(func(event):return event.id==cycle.event_data.id),"条件失效后清理抽取袋，不回退到其他幕")

	var external := preload("res://src/data/event_definition.gd").new()
	external.event = {"id":"test_external","title":"扩展测试","body":"只在测试幕抽取。","acts":[99],"tags":["test"],"weight":4.0,"options":[{"text":"甲","effects":[]},{"text":"乙","effects":[]},{"text":"丙","effects":[]}]}
	var external_path := "user://event-extension-test.tres"
	_check(ResourceSaver.save(external,external_path)==OK and CATALOG.register_file(external_path),"独立事件资源可登记，无需修改解释器")
	_check(not CATALOG.register_file(external_path),"重复稳定 ID 被拒绝")
	_check(EFFECTS.pool(99).size()==1 and EFFECTS.roll(99,rng).id=="test_external","扩展资源沿用幕、标签和权重")
	_check(EFFECTS.choose([{"id":"disabled","weight":0},{"id":"enabled","weight":1}],rng).id=="enabled","零权重事件不被选择")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(external_path))

	print("[event_system_test] PASS=%d FAIL=%d" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
