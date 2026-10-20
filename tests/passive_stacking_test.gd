extends Control
## 同一持续词重复施放：实际收益、状态适配器和角标必须一致。
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func battle() -> BattleState:
	var h := BattleHarness.new()
	h.reset({"seed":7,"opening_draw":0,"turn_draw":0,"deck":[],"enemies":["iron_seal"]})
	var b := h.battle
	b.enemies[0].hp = 1000; b.enemies[0].max_hp = 1000
	b.enemies[0].block = 0; b.enemies[0].persistent_block = 0
	return b

func play(b: BattleState, word: String) -> void:
	b.board.cells.fill(null)
	var path: Array = []
	for i in word.length():
		var pos := Vector2i(i,0)
		b.board.set_xy(pos, CharInstance.new(Database.get_character_by_glyph(word[i])))
		path.append(pos)
	check(b.try_play(path).get("ok", false), "成功打出" + word)

func badge(b: BattleState, id: String) -> Dictionary:
	for item: Dictionary in StatusDisplay.collect(b.player, b):
		if item.id == "ability:" + id: return item
	return {}

func seed_bag(b: BattleState, count := 16) -> void:
	b.bag.clear(); b.discard.clear(); b.board.cells.fill(null)
	for i in count: b.bag.append(CharInstance.new(Database.get_character_by_glyph("击")))

func _ready() -> void:
	GameState.set_meta("courtyard_preview", true)
	# 两次火热：真实出词后溢热，旧热字重新抽取不重复触发。
	var b := battle()
	play(b, "火热"); play(b, "火热")
	check(b.ability_value("heat_pollution_damage") == 2, "两次火热保留两层")
	check(badge(b, "heat_pollution_damage").get("stacks") == 2, "火热角标显示2层")
	var hp: int = b.enemies[0].hp
	b.player.heat = b.player.heat_capacity
	b.add_heat(2)
	check(hp - b.enemies[0].hp == 4 * BattleBalance.i("overheat_damage", 5), "两层火热每枚新灼热字造成双倍伤害")
	check(badge(b, "heat_pollution_damage").description.contains(str(2 * BattleBalance.i("overheat_damage", 5))), "火热详情显示叠层后的每枚伤害")
	var after: int = b.enemies[0].hp
	b.draw_to_board(2)
	check(b.enemies[0].hp == after, "抽到已有灼热字不重新触发火热")
	b.begin_player_turn(false)
	check(b.ability_value("heat_pollution_damage") == 2, "火热跨回合保留层数")
	b.enable_ability("double_next", 1)
	hp = b.enemies[0].hp; b.add_heat(1)
	check(hp - b.enemies[0].hp == 4 * BattleBalance.i("overheat_damage", 5) and b.has_ability("double_next"), "超能力放大叠层后的火热收益，且本回合持续有效")
	# 同入口的电流过载，储能与非攻击伤害都叠加。
	b = battle(); play(b, "电流过载"); play(b, "电流过载")
	b.player.heat = b.player.heat_capacity; hp = b.enemies[0].hp
	var energy := b.player.energy
	b.add_heat(1)
	check(b.player.energy - energy == 2 * BattleBalance.i("overload_energy",1) and hp - b.enemies[0].hp == 2 * BattleBalance.i("overload_damage",3), "两层电流过载的两项收益均叠加")
	check(badge(b, "electric_overload").get("stacks") == 2, "电流过载角标显示真实层数")
	# 电能：每个消耗门槛仅计算一次，生成数按层数增加。
	b = battle(); play(b,"电能"); play(b,"电能"); seed_bag(b)
	b.player.energy = 4
	b.spend_energy(1)
	check(b.board.fill_count() == 0, "电能未到消耗门槛不生成")
	b.spend_energy(1)
	check(b.board.fill_count() == 2 and badge(b,"electric_material").get("stacks") == 2, "两层电能每消耗门槛生成2枚临时电")
	# 已经按数值兑现收益的能力，不得在重复施放时覆盖已有值。
	# 能力：长词在原位补字，补字受原格数量限制（两层也只补满已空出的格子）
	b = battle(); play(b,"能力"); play(b,"能力")
	b.bag.clear()
	for i in 3: b.bag.append(CharInstance.new(Database.get_character_by_glyph("击")))
	var long_cells: Array = []
	for i in 3:
		b.board.set_xy(Vector2i(i, 2), CharInstance.new(Database.get_character_by_glyph("超能力"[i])))
		long_cells.append(Vector2i(i, 2))
	b.try_play(long_cells)
	var refilled := 0
	for i in 3:
		if b.board.get_xy(Vector2i(i, 2)) != null: refilled += 1
	check(refilled == 3 and b.bag.is_empty(), "能力：3 字词在原位补 3 字（袋被抽空）")
	check(badge(b,"longword_draw").get("stacks") == 2, "能力角标显示2层")
	b = battle(); play(b,"流转"); play(b,"流转"); seed_bag(b)
	b.words_played_this_turn.assign(["a","b"]); b.abilities.erase("_flow_claimed")
	b._trigger_on_word_abilities(Database.get_word_by_glyphs_string("火热"))
	check(b.board.fill_count() == 4 and badge(b,"flow").get("stacks") == 4, "两次流转实际补4字，角标标明总补字数")
	b.begin_player_turn(false)
	check(not b.has_ability("flow"), "流转回合结束后清除累计值")
	b = battle(); play(b,"蓄能"); play(b,"蓄能")
	b.board.set_xy(Vector2i(0,0),CharInstance.new(Database.get_character_by_glyph("火")))
	b.board.set_xy(Vector2i(1,0),CharInstance.new(Database.get_character_by_glyph("热")))
	energy = b.player.energy; b.enemies.clear(); b.end_player_turn()
	check(b.player.energy - energy == 4 and badge(b,"energy_idle").get("stacks") == 4, "两次蓄能回合末获得4储能并显示真实收益")
	b = battle(); play(b,"连载"); play(b,"连载")
	b.serial_words = BattleBalance.i("serial_interval",3) - 1
	b._trigger_on_word_abilities(Database.get_word_by_glyphs_string("火热"))
	check(b.ability_value("next_serial_bonus") == 12 and badge(b,"serial").get("stacks") == 12, "两次连载奖励叠加至12点并显示真实收益")
	# 明确不叠加的开关保持幂等，已有累加类也不能被重复相加两次。
	b = battle(); play(b,"防火"); play(b,"防火")
	check(b.ability_value("fireproof") == 1, "防火开关重复施放仍仅启用一次")
	play(b,"流连")
	check(b.ability_value("linger_chance") == 1 and is_equal_approx(b.linger_chance(), 0.25), "流连一层：25% 留字")
	play(b,"流连"); play(b,"流连")
	check(b.ability_value("linger_chance") == 2 and is_equal_approx(b.linger_chance(), 0.5), "流连最多叠 2 层：50% 留字")
	play(b,"反击"); play(b,"反击")
	check(b.ability_value("counter") == 6, "已有反击叠层保持正确且不重复累加")
	# 真正创建状态栏，检查2角标及详情；显示过程不改动规则。
	var strip := StatusStrip.new()
	strip.size = Vector2(1000,40); add_child(strip)
	b = battle(); play(b,"火热")
	strip.set_entries(StatusDisplay.collect(b.player,b))
	check(strip.item_for("ability:heat_pollution_damage").tooltip_text.contains("1 层"), "首层HUD显示1层")
	play(b,"火热")
	strip.set_entries(StatusDisplay.collect(b.player,b))
	var button: Button = strip.item_for("ability:heat_pollution_damage")
	check(button.tooltip_text.contains("2 层") and button.find_child("Stacks", true, false).text == "2", "实际HUD角标和悬浮详情一致显示2层")
	check(b.ability_value("heat_pollution_damage") == 2, "HUD刷新不改动叠层")
	strip.queue_free()
	check(not battle().has_ability("heat_pollution_damage"), "下一场战斗不继承本场持续能力")
	# 已有多项持续效果同时触发，各自按层数结算，不互相覆盖。
	b = battle(); play(b,"火热"); play(b,"火热"); play(b,"电流过载"); play(b,"电流过载")
	b.player.heat = b.player.heat_capacity; hp = b.enemies[0].hp; energy = b.player.energy
	b.add_heat(1)
	check(hp - b.enemies[0].hp == 2 * (BattleBalance.i("overheat_damage",5) + BattleBalance.i("overload_damage",3)) and b.player.energy - energy == 2 * BattleBalance.i("overload_energy",1), "火热与电流过载的叠层可以同时正确触发")
	for word in ["火热", "电流过载", "电能", "能力", "流转", "蓄能", "连载"]:
		check(not Database.get_word_by_glyphs_string(word).describe().is_empty(), word + "说明不为空")
	check(checks + 1 == 61, "全部回归检查完整执行")
	print("[passive_stacking_test] PASS=%d FAIL=%d TOTAL=%d" % [checks-failures, failures,checks])
	get_tree().quit(1 if failures else 0)
