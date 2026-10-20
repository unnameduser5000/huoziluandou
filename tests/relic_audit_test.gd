extends Control
## 遗物审查回归：2026-10-20 全遗物排查发现的问题逐条钉住，外加全部遗物的定义完整性。
const EVENT_EFFECTS = preload("res://src/core/event_effects.gd")

var _pass := 0
var _fail := 0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ " + msg)
	else:
		_fail += 1
		push_error(msg)


func _ready() -> void:
	_test_definitions()
	_test_hidden()
	_test_once_pickup()
	_test_midas()
	_test_wish()
	_test_cracked_bottle()
	_test_ghost_hand()
	_test_amber_vial()
	_test_chain()
	_test_proof()
	_test_blitz()
	_test_pending_setup()
	_test_fallback_preview()
	_test_harness_hp()
	GameState.relics.clear()
	GameState.relic_binds.clear()
	GameState.relic_counters.clear()
	print("[relic_audit_test] PASS=%d FAIL=%d" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


# ---------------------------------------------------------------- 工具
func _reset(relics: Array = []) -> void:
	GameState.start_new_run("v03")
	GameState.player_max_hp = 60
	GameState.player_hp = 60
	for r in relics:
		GameState.add_relic(r)


func _rules() -> BattleRules:
	var rules: BattleRules = Database.rules.duplicate()
	rules.opening_draw = 0
	rules.turn_draw = 0
	return rules


func _enemy_data(dmg := 5, hp := 200) -> EnemyData:
	var ed := EnemyData.new()
	ed.name = "audit_dummy"
	ed.max_hp = hp
	var mv := EnemyMoveData.new()
	mv.kind = EnemyMoveData.Kind.ATTACK
	mv.damage = dmg
	ed.moves.append(mv)
	return ed


## 不经 add_relic（不触发拾取效果）直接开一场
func _battle(relics: Array = [], deck: Array = []) -> BattleState:
	GameState.start_new_run("v03")
	GameState.player_max_hp = 60
	GameState.player_hp = 60
	GameState.relics.assign(relics)
	var b := BattleState.new(_rules())
	b.start(deck, [_enemy_data()], 7)
	return b


func _inst(g: String) -> CharInstance:
	return CharInstance.new(Database.get_character_by_glyph(g))


func _count(g: String) -> int:
	return GameState.deck.filter(func(c): return c.glyph() == g).size()


func _clear_board(b: BattleState) -> void:
	for i in b.board.cells.size():
		b.board.cells[i] = null


func _play_word(b: BattleState, text: String, row := 0) -> Dictionary:
	var path: Array = []
	for i in text.length():
		var p := Vector2i(i, row)
		b.board.set_xy(p, _inst(text[i]))
		path.append(p)
	return b.try_play(path)


# ---------------------------------------------------------------- 定义完整性
func _test_definitions() -> void:
	for id: String in Relics.DEFS:
		var d: Array = Relics.DEFS[id]
		var ok: bool = str(d[0]) != "" and str(d[1]) != "" and Relics.TIER.has(id) and Relics.PRICE.has(int(Relics.TIER[id]))
		_ok(ok and Relics.text(id).contains(str(d[0])) and Relics.sell_price(id) * 2 <= Relics.price(id), "定义完整：%s「%s」档次 %s" % [id, d[0], Relics.TIER.get(id, "?")])
	for id: String in Relics.TIER:
		_ok(Relics.DEFS.has(id), "TIER 里没有多余的 id：%s" % id)
	for id in Relics.EVENT_ONLY + Relics.HIDDEN + Relics.ONCE_PICKUP:
		_ok(Relics.DEFS.has(id), "名单里的 id 都有定义：%s" % id)


# ---------------------------------------------------------------- 隐藏未实现的遗物
func _test_hidden() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var seen := {}
	for i in 400:
		for id in Relics.roll_choices([], rng, 3):
			seen[id] = true
		for id in Relics.roll_event_choices([], rng, 3):
			seen[id] = true
	_ok(not seen.has("black_water") and not seen.has("life_lantern"), "黑水墨、命灯不会从普通池或事件池滚出")
	_ok(seen.size() == Relics.normal_pool().size() + Relics.event_pool().size(), "其余遗物都能滚到（%d 件）" % seen.size())
	_reset(["black_water"])
	_ok(GameState.has_relic("black_water"), "旧存档 / 事件显式给出隐藏遗物时不报错")


# ---------------------------------------------------------------- 一次性拾取
func _test_once_pickup() -> void:
	for pair in [["death", "死"], ["ruin", "亡"]]:
		_reset()
		var n := _count(pair[1])
		GameState.add_relic(pair[0])
		GameState.remove_relic(pair[0])
		GameState.add_relic(pair[0])
		_ok(_count(pair[1]) == n + 1, "%s：卖掉再买只给一枚【%s】（%d）" % [Relics.name_of(pair[0]), pair[1], _count(pair[1]) - n])
	_reset()
	var size := GameState.deck_size()
	GameState.add_relic("chaos_dice")
	_ok(GameState.deck_size() == size + 3, "乱文骨骰：重铸后多 3 枚")
	GameState.remove_relic("chaos_dice")
	GameState.add_relic("chaos_dice")
	_ok(GameState.deck_size() == size + 3, "乱文骨骰：卖掉再买不再重铸（%d）" % GameState.deck_size())
	for id in ["goldleaf", "rubbing"]:
		_reset()
		GameState.add_relic(id)
		_ok(not Relics.pick_spec(id).is_empty() and Relics.needs_setup(id), "%s：第一次拿到要挑字" % Relics.name_of(id))
		GameState.remove_relic(id)
		GameState.add_relic(id)
		_ok(Relics.pick_spec(id).is_empty() and not Relics.needs_setup(id), "%s：卖掉再买不再挑字" % Relics.name_of(id))
	_reset()
	var fire := _count("火")
	GameState.add_relic("fireman")
	GameState.remove_relic("fireman")
	GameState.add_relic("fireman")
	_ok(_count("火") == fire + 4, "火种：卖掉再买不重复给火（+%d）" % (_count("火") - fire))


# ---------------------------------------------------------------- 金字碑
func _test_midas() -> void:
	_reset()
	GameState.deck[0].gilded = true  # 泥金笔镀过的
	GameState.add_relic("midas")
	_ok(GameState.deck.all(func(c): return c.gilded), "金字碑：全部镀金")
	GameState.add_character(Database.get_character_by_glyph("击"))
	_ok(GameState.deck.back().gilded, "金字碑：之后拿到的也镀金")
	GameState.add_captured([_inst("破")])
	_ok(GameState.deck.back().gilded, "金字碑：战斗收购得到的字也镀金")
	GameState.remove_relic("midas")
	_ok(GameState.deck[0].gilded, "金字碑失去后：原本泥金笔镀的仍是金字")
	_ok(GameState.deck.slice(1).all(func(c): return not c.gilded), "金字碑失去后：它镀的金全部退掉，不能卖掉白嫖")
	_reset(["midas"])
	GameState.add_relic("chaos_dice")
	_ok(GameState.deck.all(func(c): return c.gilded), "金字碑 + 乱文骨骰：重铸出的新字也镀金")
	var b := _battle(["midas"])
	b.bounty_paid = true
	b.bounty_reward = 30
	b.deal_damage(b.enemies[0], 9999, false)
	_ok(b.gold_earned >= 30 and not b.player.is_alive(), "金字碑：重金悬赏的收入也算，满 20 化为金像（收入 %d）" % b.gold_earned)


# ---------------------------------------------------------------- 许愿笺
func _test_wish() -> void:
	_reset(["monkey"])
	var ji := Database.get_character_by_glyph("击")
	_ok(Relics.grant_wish("endless_glyph", ji.id), "千字同文：许下【击】")
	var pollution: CharacterData = Database.characters.values().filter(func(cd): return cd.is_pollution)[0]
	GameState.add_character(pollution)
	_ok(GameState.deck.back().data.is_pollution, "千字同文：污染字不会被洗成许愿字")
	GameState.add_relic("chaos_dice")
	_ok(GameState.deck.filter(func(c): return not c.data.is_pollution).all(func(c): return c.glyph() == "击"), "千字同文 + 乱文骨骰：重铸后仍全是【击】")
	GameState.remove_relic("monkey")
	_ok(GameState.relic_counters.has("monkey"), "许愿笺卖掉：愿望记录保留")
	GameState.add_relic("monkey")
	_ok(not Relics.needs_setup("monkey") and not Relics.grant_wish("endless_life"), "许愿笺再买回来：不能重新许愿")
	_ok(Relics.wish_glyph_id() == ji.id, "许愿笺再买回来：原来的千字同文恢复生效")


# ---------------------------------------------------------------- 裂墨瓶
func _test_cracked_bottle() -> void:
	var b := _battle(["cracked_bottle"])
	b.player.energy = 1
	b.enable_ability("energy_refund_once", 1)
	b.spend_energy(1)
	_ok(b.player.energy == 1, "裂墨瓶：【复】返还不翻倍，不会越返越多（%d）" % b.player.energy)
	b.player.energy = 2
	b.spend_energy(2)
	var back := b.refund_half_energy()
	_ok(back == 1 and b.player.energy == 1, "裂墨瓶：返还一半也按实际数（返 %d，余 %d）" % [back, b.player.energy])
	b.add_energy(3)
	_ok(b.player.energy == 7, "裂墨瓶：普通获得储能照常翻倍（%d）" % b.player.energy)
	var deck: Array = []
	for i in 6:
		deck.append(_inst("火"))
	b = _battle(["cracked_bottle"], deck)
	_clear_board(b)
	b.board.set_xy(Vector2i(0, 3), _inst("击"))
	b.board.set_xy(Vector2i(1, 3), _inst("破"))
	b.player.energy = 3
	b.enable_ability("energy_idle", 2)
	b.end_player_turn()
	_ok(b.player.energy == 4, "裂墨瓶：先清空剩下的 3 储能，再结算蓄能 +2×2，留到下回合（%d）" % b.player.energy)
	b = _battle(["cracked_bottle", "powerbank"])
	_ok(b.player.energy == 8, "裂墨瓶 + 蓄电瓶：开局 4×2 = 8 储能（%d）" % b.player.energy)


# ---------------------------------------------------------------- 补字鬼手
func _test_ghost_hand() -> void:
	var b := _battle(["ghost_hand"])
	var left: int = b.magic_hand_left
	b.bag.clear()
	b.discard.clear()
	Relics.on_cards_consumed(b, [{"kind": "real", "inst": _inst("击")}])
	_ok(b.magic_hand_left == left, "补字鬼手：字袋、弃字堆都空，没补上不扣次数（%d/%d）" % [b.magic_hand_left, left])
	var deck: Array = []
	for i in 6:
		deck.append(_inst("火"))
	b = _battle(["ghost_hand"], deck)
	_clear_board(b)
	var bag := b.bag.size()
	_ok(_play_word(b, "击").ok and b.magic_hand_left == left - 1 and bag - b.bag.size() == 1, "补字鬼手：打出 1 枚补 1 枚，扣 1 次")


# ---------------------------------------------------------------- 朱砂印泥 / 还魂墨
func _test_amber_vial() -> void:
	var b := _battle(["amber", "vial"])
	_ok(b.player.hp == 60 and b.player.persistent_block == 2, "还魂墨 + 朱砂印泥：满血开局，2 点回血转成持久盾（%d）" % b.player.persistent_block)
	b.player.no_block_turns = 1
	var shield := b.player.persistent_block
	b.heal_player(5)
	_ok(b.player.persistent_block == shield, "朱砂印泥：不能获得格挡时不给盾")


# ---------------------------------------------------------------- 连字环
func _test_chain() -> void:
	var b := _battle(["chain"])
	for text in ["投币", "合击", "击破"]:
		var w := Database.get_word_by_glyphs(Array(text.split("")))
		if w == null:
			_ok(false, "词库里找不到【%s】，测试需要更新" % text)
			continue
		_clear_board(b)
		for i in text.length():
			b.board.set_xy(Vector2i(i, 0), _inst(text[i]))
		var found: Array = Relics.chain_words(b).map(func(f): return f.word.word)
		if text == "击破":
			_ok(found.has(text), "连字环：普通攻击词【击破】照常自动打")
		else:
			_ok(not found.has(text), "连字环：不自动打【%s】（%s）" % [text, "要花铜钱" if text == "投币" else "会排进合击队列"])
	b.formation_mode = true
	_clear_board(b)
	for i in 2:
		b.board.set_xy(Vector2i(i, 0), _inst("击破"[i]))
	var hp: int = b.enemies[0].hp
	Relics.run_chain(b)
	_ok(b.enemies[0].hp == hp, "连字环：合击队列进行中不自动出词")


# ---------------------------------------------------------------- 校勘尺
func _test_proof() -> void:
	var other := ""
	for pid in Database.pollutions:
		if pid != "scorch":
			other = pid
			break
	var deck: Array = []
	for i in 6:
		deck.append(_inst("火"))
	var b := _battle(["proof"], deck)
	_clear_board(b)
	for x in 2:
		var c := _inst("击")
		c.add_pollution("scorch")
		if not other.is_empty():
			c.add_pollution(other)
		b.board.set_xy(Vector2i(x, 0), c)
	var bag := b.bag.size()
	b.cleanse_scorch()
	_ok(b.cleansed_count == 0 and b.bag.size() == bag, "校勘尺：只洗掉灼痕、还带别的污染，不算净化")
	_clear_board(b)
	for x in 2:
		var c := _inst("击")
		c.add_pollution("scorch")
		b.board.set_xy(Vector2i(x, 0), c)
	b.cleanse_scorch()
	_ok(b.cleansed_count == 0 and bag - b.bag.size() == 1, "校勘尺：两枚洗干净，补 1 字")
	b = _battle(["proof"])
	_clear_board(b)
	for x in 2:
		var c := _inst("击")
		c.add_pollution("scorch")
		b.board.set_xy(Vector2i(x, 0), c)
	b.cleanse_scorch()
	_ok(b.cleansed_count == 2, "校勘尺：字袋空了补不上，净化数先攒着（%d）" % b.cleansed_count)


# ---------------------------------------------------------------- 急就章
func _test_blitz() -> void:
	var b := _battle(["blitz"])
	var e: Combatant = b.enemies[0]
	e.add_status("burn", 2)
	b.player.heat = 2
	var hp := e.hp
	b.end_player_turn()
	_ok(b.player.hp == 60, "急就章：第一回合敌人不出手")
	_ok(e.hp == hp - 4 and e.status_stacks("burn") == 1, "急就章：只跳过行动，灼烧照常结算（当前热度2×2 = -%d）" % (hp - e.hp))
	b.end_player_turn()
	_ok(b.player.hp == 55, "急就章：第二回合恢复行动")


# ---------------------------------------------------------------- 事件 / 宝藏入手后补挑字、许愿
func _test_pending_setup() -> void:
	var run = load("res://src/expedition/room_run_state.gd").new()
	run.reset({"seed": 31})  # 庭院开局会重置本局状态，先开局再拿遗物
	run.autosave = false
	var result: Dictionary = EVENT_EFFECTS.resolve([{"type": "gain_relic", "relic": "goldleaf"}], GameState.rng)
	_ok(result.get("ok", false) and Relics.next_pending_peek() == "goldleaf", "事件给泥金笔：记下待补的挑字")
	EVENT_EFFECTS.resolve([{"type": "gain_relic", "relic": "monkey"}], GameState.rng)
	_ok(GameState.relic_counters.get("_pending_setup", []) == ["goldleaf", "monkey"], "事件给许愿笺：排在后面等许愿")
	run.save_run("user://relic-audit-pending.tres")
	GameState.relic_counters.clear()
	GameState.relics.clear()
	var restored = load("res://src/expedition/room_run_state.gd").restore("user://relic-audit-pending.tres")
	_ok(restored != null and GameState.relics.has("goldleaf") and GameState.relic_counters.get("_pending_setup", []) == ["goldleaf", "monkey"], "待补的挑字 / 许愿随存档保存")
	var first := Relics.next_pending_setup()
	var second := Relics.next_pending_peek()
	_ok(first == "goldleaf" and second == "monkey", "按入手顺序一件件补（%s → %s）" % [first, second])
	Relics.grant_wish("endless_life")
	_ok(Relics.next_pending_setup().is_empty(), "已经许过愿的不再弹")
	_reset()
	GameState.add_relic("goldleaf")
	for c in GameState.deck:
		c.gilded = true
	Relics.queue_setup("goldleaf")
	_ok(Relics.next_pending_peek().is_empty(), "没有可镀的字时不排挑字")


# ---------------------------------------------------------------- 反字模 / 叠字钱：界面预览和实际出字一致
func _test_fallback_preview() -> void:
	var b := _battle(["palindrome", "slot"])
	var word := Database.get_word_by_glyphs(["重", "连"])
	_clear_board(b)
	b.board.set_xy(Vector2i(0, 0), _inst("连"))
	b.board.set_xy(Vector2i(1, 0), _inst("重"))
	var req: Dictionary = EffectTargets.request(b, [Vector2i(0, 0), Vector2i(1, 0)])
	if word == null:
		_ok(false, "词库里找不到【重连】，测试需要更新")
	else:
		_ok(req.word == word and req.interaction == EffectTargets.interaction_of(word), "反字模：倒连【连重】按【重连】取交互（%s）" % req.interaction)
	_ok(EffectDescriptions.word_for(["连", "重"], b) == word and EffectDescriptions.word_for(["连", "重"]) == null, "反字模：只在本场持有时预览认倒连")
	_ok(EffectDescriptions.word_for(["击", "击", "击"], b) != null, "叠字钱：三连相同字的预览不再显示不成词")


# ---------------------------------------------------------------- 无界面开战（庭院模拟）
func _test_harness_hp() -> void:
	_reset()
	GameState.relics.assign(["vial"])
	var h := BattleHarness.new()
	h.reset({"persistent_run": true, "hp": 50, "enemies": ["ink_spirit"]})
	_ok(h.battle.player.hp == 52, "无界面开战：还魂墨的开局回血不被血量设定抹掉（%d）" % h.battle.player.hp)
