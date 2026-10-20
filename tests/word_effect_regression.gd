extends Control
## 词效回归：实体守恒、回合/跨战边界、结阵联动和实际 HUD 多阶段交互。

## 固定数量防止脚本异常中断某个测试函数后得到假通过。
const EXPECTED_CHECKS := 417
var checks: Array = []

func _ready() -> void:
	Settings.storage_path = "user://word_effect_regression-settings.cfg"
	_run_controls()
	_run_logic()
	_run_baojinbi()
	_run_fenhua()
	_run_converge()
	_run_selection_limits()
	_run_word_completion()
	_run_solo_balance()
	_run_solo_balance_two()
	_run_solo_balance_three()
	_run_solo_balance_four()
	_run_word_balance()
	_run_regen()
	_run_vulnerable()
	_run_description_previews()
	_run_reconnect_return()
	_run_flow_row_limits()
	_run_boundaries()
	_run_final_boundaries()
	await _run_ui()
	await _run_ui_completion()
	await _run_ui_spatial_targets()
	await _run_ui_selection_limits()
	await _run_ui_word_completion()
	await _run_ui_solo_balance()
	await _run_ui_solo_throw()
	await _run_ui_solo_balance_three()
	await _run_ui_solo_balance_four()
	await _run_ui_reconnect_return()
	await _run_ui_flow_stacking()
	await _run_ui_word_balance()
	await _run_ui_dynamic_preview()
	var failures := 0
	if checks.size() != EXPECTED_CHECKS:
		failures += 1
		push_error("回归用例未完整执行：%d/%d" % [checks.size(), EXPECTED_CHECKS])
	for check in checks:
		if not check.passed:
			failures += 1
			push_error("[word_effect_regression] %s: %s" % [check.id, check.detail])
	print("[word_effect_regression] PASS=%d FAIL=%d" % [checks.size() - failures, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _check(id: String, passed: bool, detail: String) -> void:
	checks.append({"id": id, "passed": passed, "detail": detail})

func _battle() -> BattleState:
	GameState.player_max_hp = 60
	GameState.player_hp = 60
	GameState.gold = 100
	GameState.permanent_damage_reduction = 0
	GameState.deck.clear()
	var rules: BattleRules = Database.rules.duplicate()
	rules.opening_draw = 0
	rules.turn_draw = 0
	var b := BattleState.new(rules)
	b.start([], [], 7)
	_enemy(b)
	return b

func _enemy(b: BattleState) -> Combatant:
	var ed := EnemyData.new()
	ed.name = "audit_enemy"
	ed.max_hp = 200
	var move := EnemyMoveData.new()
	move.kind = EnemyMoveData.Kind.ATTACK
	move.damage = 5
	ed.moves.append(move)
	var e := Combatant.new("audit_enemy", 200)
	e.enemy_data = ed
	b.enemies.append(e)
	return e

func _place(b: BattleState, pos: Vector2i, glyph: String) -> CharInstance:
	var inst := CharInstance.new(Database.get_character_by_glyph(glyph))
	b.board.set_xy(pos, inst)
	return inst

func _word(b: BattleState, text: String, row: int = 0, target: Dictionary = {}) -> Dictionary:
	var path: Array = []
	for i in text.length():
		var pos := Vector2i(i, row)
		_place(b, pos, text[i])
		path.append(pos)
	var result := b.try_play(path, target)
	assert(result.ok, "Audit setup cannot play " + text + ": " + str(result.reason))
	return result

func _pad(b: BattleState) -> void:
	for i in 50:
		b.bag.append(CharInstance.new(Database.get_character_by_glyph("放")))

func _preview_signature(b: BattleState) -> String:
	return var_to_str({"rng": b.rng.state, "uid": CharInstance._next_uid,
		"board": b.board.cells.map(func(c): return [c.uid, c.temporary_uses, c.pinned_exhausted] if c != null else []),
		"bag": b.bag.map(func(c): return c.uid), "discard": b.discard.map(func(c): return c.uid),
		"temp": b.temp_chars.map(func(c): return c.uid), "gold": GameState.gold,
		"abilities": b.abilities.duplicate(true), "history": b.last_played_glyphs.duplicate(),
		"strengthen": b.strengthen_plays, "spent": b.last_energy_spent,
		"refunded": b.last_energy_refunded, "claimed": b.last_energy_half_claimed,
		"statuses": b.player.statuses.duplicate(true),
		"player": [b.player.hp, b.player.max_hp, b.player.block, b.player.persistent_block],
		"enemies": b.enemies.map(func(enemy): return [enemy.hp, enemy.block, enemy.statuses.duplicate(true)]),
		"energy": b.player.energy, "heat": b.player.heat})

func _run_regen() -> void:
	var b := _battle()
	b.enemies[0].enemy_data.moves[0].damage = 0
	_word(b, "回复")
	_check("regen_word_status", b.player.status_stacks("regen") == 3 and StatusDisplay.collect(b.player, b).any(func(item): return item.id == "regen" and item.stacks == 3), "回复获得 3 层再生，并在 HUD 显示再生层数")
	b.player.hp = 40
	var hp: Array = []
	var stacks: Array = []
	for i in 3:
		b.end_player_turn()
		hp.append(b.player.hp)
		stacks.append(b.player.status_stacks("regen"))
	_check("regen_turn_tick", hp == [43, 45, 46] and stacks == [2, 1, 0], "再生每回合回复层数生命并减 1 层：血 %s，层 %s" % [str(hp), str(stacks)])

func _run_vulnerable() -> void:
	var b := _battle()
	var enemy: Combatant = b.enemies[0]
	_word(b, "破防")
	_check("vulnerable_apply", enemy.status_stacks("vulnerable") == 2 and enemy.take_damage(3) == 5, "破防施加2层易伤，3伤向上取整为5伤")
	b.end_player_turn()
	_check("vulnerable_first_decay", enemy.status_stacks("vulnerable") == 1 and enemy.take_damage(3) == 5, "新回合易伤2变1，伤害增幅保持50%")
	b.end_player_turn()
	_check("vulnerable_expire", not enemy.statuses.has("vulnerable") and enemy.take_damage(3) == 3, "再过一回合易伤耗尽，移除状态并恢复正常伤害")
	_word(b, "破防")
	_word(b, "破防")
	_check("vulnerable_stacks_duration", enemy.status_stacks("vulnerable") == 4 and enemy.take_damage(3) == 5, "重复破防叠加持续层数，不提高易伤倍率")
	b.enemy_skip_turns = 1
	b.end_player_turn()
	_check("vulnerable_skip_turn_decay", enemy.status_stacks("vulnerable") == 3, "停火跳过敌方行动时，易伤仍每回合衰减一次")
	b.player.add_status("vulnerable", 2)
	var stacks: Array = []
	for i in 2:
		b.end_player_turn()
		stacks.append(b.player.status_stacks("vulnerable"))
	_check("vulnerable_both_sides_decay", stacks == [1, 0] and enemy.status_stacks("vulnerable") == 1, "玩家与敌方易伤都每回合减少1层，不重复衰减")
	var other := _enemy(b)
	other.add_status("vulnerable", 1)
	b.end_player_turn()
	_check("vulnerable_multi_enemy_expire", not enemy.statuses.has("vulnerable") and not other.statuses.has("vulnerable"), "多个敌人的易伤各自到期，不会保留零层状态")
	var word := Database.get_word_by_glyphs_string("破防")
	_check("vulnerable_copy_synced", word.describe() == BattleText.word(word) and "易伤" in EffectGlossary.brief(word) and "每回合开始少 1 层" in word.effects[0].note and "敌我双方每回合开始减少1层" in EffectGlossary.entry("term:vulnerable").text, "破防资源、完整说明、精简说明和wiki词条都使用衰减规则")

func _run_description_previews() -> void:
	var unified := true
	for word in Database.words.values():
		unified = unified and word.describe() == BattleText.word(word) and word.description == word.effect_summary
		for stale in ["P23初稿", "尚未收敛", "临时草案", "未定稿", "倾向删除"]:
			unified = unified and not stale in word.describe()
	_check("word_description_source", unified and BattleText.WORDS.size() == Database.words.size(), "全部%d词共享完整说明，游戏介绍没有旧设计草稿" % Database.words.size())
	var b := _battle()
	var pos := Vector2i(3, 3)
	var source := _place(b, pos, "再")
	var text := EffectPreview.solo_text(source, b, [pos])
	_check("preview_again_no_history", "尚未打出任何字" in text and "无法复制" in text, "再在无历史时说明当前无复制效果")
	_place(b, Vector2i.ZERO, "击")
	b.try_play([Vector2i.ZERO])
	text = EffectPreview.solo_text(source, b, [pos])
	_check("preview_again_after_solo", "上一手【击】" in text and "临时【击】" in text, "再显示上一手成功单字及将复制的字")
	_word(b, "防御")
	text = EffectPreview.solo_text(source, b, [pos])
	_check("preview_again_after_word", "上一手【防御】" in text and "末字【御】" in text and "临时【御】" in text, "上一手为词时，再只复制末字")
	_place(b, Vector2i(0, 1), "防")
	_place(b, Vector2i(1, 1), "金")
	var invalid := b.try_play([Vector2i(0, 1), Vector2i(1, 1)])
	text = EffectPreview.solo_text(source, b, [pos])
	_check("preview_again_ignores_invalid", not invalid.ok and "上一手【防御】" in text, "无效出词不覆盖预览引用的成功历史")
	var before := _preview_signature(b)
	for i in 3:
		EffectPreview.solo_text(source, b, [pos])
		for word in Database.words.values():
			EffectPreview.word_text(word, b)
	_check("preview_all_read_only", _preview_signature(b) == before, "反复预览所有词不改随机数、实体、历史、资金、标记或退款状态")
	b.try_play([pos])
	source = _place(b, Vector2i(3, 2), "再")
	text = EffectPreview.solo_text(source, b, [Vector2i(3, 2)])
	_check("preview_again_self_rejection", "上一手【再】" in text and "不能复制自身" in text, "上一手是再时准确说明不能继续复制")
	source.word_only = true
	text = EffectPreview.solo_text(source, b, [Vector2i(3, 2)])
	_check("preview_word_only_suppression", "仅供组词" in text and not "上一手" in text, "只能组词的临时再不预告被禁止的单字效果")
	b = _battle()
	b.player.energy = 5
	b.spend_energy(5)
	var refund_word := Database.get_word_by_glyphs_string("复电")
	before = _preview_signature(b)
	text = EffectPreview.word_text(refund_word, b)
	_check("preview_refund_amount", "本次可再退3点" in text and _preview_signature(b) == before, "复电预览半额向上取整，预览本身不退款或占用资格")
	_word(b, "复电")
	text = EffectPreview.word_text(refund_word, b)
	_check("preview_refund_used", "已用【复电】退款" in text and "可退款0点" in text, "同笔消费已退款时提示零收益")
	b.spend_energy(2)
	text = EffectPreview.word_text(refund_word, b)
	_check("preview_refund_new_expense", "最近消费2储能" in text and "本次可再退1点" in text, "新消费及时替换过期退款预览")
	b = _battle()
	_word(b, "重击")
	_word(b, "防御")
	text = EffectPreview.word_text(Database.get_word_by_glyphs_string("连击"), b)
	_check("preview_replay_attack_source", "再结算一次【重击】" in text, "连击显示最近攻击词，普通防御词不会覆盖来源")
	text = EffectPreview.word_text(Database.get_word_by_glyphs_string("回放"), b)
	_check("preview_replay_materials", "上一词【防御】" in text and "【防】" in text and "【御】" in text, "回放说明上一词及当前仍能返还的实体材料")
	b = _battle()
	_word(b, "加强")
	text = EffectPreview.word_text(Database.get_word_by_glyphs_string("加强"), b)
	_check("preview_growing_strength", "第2次" in text and "获得2层力量" in text and b.strengthen_plays == 1, "加强根据本场历史显示下一次力量，不提前推进计数")
	b.player.energy = 3
	text = EffectPreview.word_text(Database.get_word_by_glyphs_string("电热"), b)
	_check("preview_resource_conversion", "3储能" in text and "9临时格挡" in text and b.player.energy == 3, "转换预览展示当前资源对应收益，不提前消耗")
	b.enable_ability("force_once", 2)
	b.enable_ability("next_energy_bonus", 6)
	b.enable_ability("combine_word_once", 2)
	before = _preview_signature(b)
	text = EffectPreview.word_text(Database.get_word_by_glyphs_string("放电"), b)
	_check("preview_pending_temporary_effects", "首个伤害段额外+2" in text and "每段额外+6" in text and "获得4临挡、2储能" in text and _preview_signature(b) == before, "即将使用的词显示已武装的力、蓄力和合收益，不提前消费")
	b.enable_ability("counter", 2)
	var entries := StatusDisplay.collect(b.player, b)
	_check("preview_counter_stacks", entries.any(func(item): return item.id == "ability:counter" and "+6" in item.description and "敌人全部行动后" in item.description), "反击状态提示按当前层数解释追加伤害和时机")
	b.enemies[0].add_status("vulnerable", 2)
	entries = StatusDisplay.collect(b.enemies[0], b)
	_check("preview_enemy_vulnerable_lifetime", entries.any(func(item): return item.id == "vulnerable" and "每回合衰减 1 层" in item.description and not "不按回合衰减" in item.description), "敌方易伤提示每回合减少1层")

func _run_word_balance() -> void:
	var builder := load("res://src/tools/build_content.gd") as Script
	_check("balance_builder_parse", builder != null and builder.can_instantiate(), "内容生成脚本可解析，仅加载而不执行重建")
	var synced := true
	for text in ContentBuild.BALANCE_SPECS:
		var spec: Dictionary = ContentBuild.BALANCE_SPECS[text]
		var word := Database.get_word_by_glyphs_string(text)
		synced = synced and word != null and word.effect_summary == BattleText.word(word) and word.interaction == spec.interaction and word.effects[0].handler == spec.handler and word.effects[0].amount == spec.amount and word.effects[0].args == spec.args
	_check("word_balance_specs", synced, "当前数值词资源与生成器的效果、数值、参数、描述和交互同步")
	var b := _battle()
	for i in 3:
		_word(b, "加强")
	_check("growing_strength", b.strengthen_plays == 3 and b.player.status_stacks("strength") == 6, "三次加强依次给1/2/3力量，共6")
	b.begin_player_turn(false)
	_word(b, "加强")
	_check("growing_strength_next_turn", b.player.status_stacks("strength") == 10, "递增次数及力量均跨回合保留")
	b = _battle()
	b.enable_ability("repeat")
	b.repeat_armed = true
	_word(b, "加强")
	_check("growing_strength_replay", b.strengthen_plays == 1 and b.player.status_stacks("strength") == 2, "重复重演本次+1，实际出词次数仍为1")
	b = _battle()
	_word(b, "流利")
	var fused := _place(b, Vector2i(3, 3), "防")
	fused.fusion.append("御")
	_place(b, Vector2i(0, 2), "力")
	var result := b.try_play([Vector2i(3, 3), Vector2i(0, 2), Vector2i(3, 3)])
	var rejects_reuse: bool = not result.ok and b.board.free_word_link
	result = b.try_play([Vector2i(3, 3), Vector2i(0, 2)])
	_check("free_link_fused_material", rejects_reuse and result.ok and not b.board.free_word_link, "流利支持远处融合单位，仍不能重复计算同一实体")
	b = _battle()
	_word(b, "反复")
	var original := _place(b, Vector2i(0, 1), "防")
	original.gilded = true
	original.refined = true
	original.temporary_uses = 2
	var fixed := _place(b, Vector2i(1, 1), "御")
	fixed.pinned = true
	b.try_play([Vector2i(0, 1), Vector2i(1, 1)])
	var copies: Array = b.board.cells.filter(func(c): return c != null and c.temporary)
	_check("repeat_whole_word_retained", copies.size() == 2 and b.board.cells.has(original) and b.board.cells.has(fixed) and not b.has_ability("repeat_zero"), "原字保留也复制整词，只触发一次")
	_check("repeat_plain_copies", copies.all(func(c): return not c.refined and not c.gilded and not c.pinned and c.temporary_uses == 0), "整词复制只含字形，不继承实体强化")
	var copy: CharInstance = copies[0]
	b.try_play([b.board.to_xy(b.board.cells.find(copy))])
	_check("repeat_temporary_lifecycle", not b.discard.has(copy) and not b.bag.has(copy) and not b.board.cells.has(copy), "临时字使用后移除，不进入循环")
	b = _battle()
	original = _place(b, Vector2i(0, 2), "电")
	_place(b, Vector2i(1, 2), "电")
	_word(b, "精炼", 0, {"tile": Vector2i(0, 2), "tile2": Vector2i(1, 2)})
	b.try_play([Vector2i(0, 2)])
	b.swap_cells(Vector2i(0, 2), Vector2i(3, 3))
	b.begin_player_turn(false)
	_check("refine_move_no_refresh", original.refined and original.temporary_uses == 1 and b.board.get_cell(3, 3) == original, "普通移动和回合刷新不恢复精炼使用次数")
	b.try_play([Vector2i(3, 3)])
	b.try_play([Vector2i(3, 3)])
	_check("refine_three_uses", b.discard.has(original) and original.temporary_uses == 0 and b.player.energy == 3, "精炼实体本次共用三次后正常弃置")
	b.take_from_discard_by_uid(original.uid)
	b.bag.append(original)
	b.draw_one_to(Vector2i(3, 3))
	_check("refine_reentry_refresh", b.board.get_cell(3, 3) == original and original.temporary_uses == 2 and _occurrences(b, original) == 1 and not original.clone().refined, "重新抽入恢复两次额外使用，原实体唯一，复制不继承精炼")
	var next_battle := BattleState.new(b.rules)
	next_battle.start([original], [], 7)
	_check("refine_battle_lifetime", not original.refined and original.temporary_uses == 0, "精炼强化下一场清除")
	b = _battle()
	original = _place(b, Vector2i(3, 3), "电")
	_word(b, "精铸", 0, {"tile": Vector2i(3, 3)})
	var first := b.try_play([Vector2i(3, 3)])
	var second := b.try_play([Vector2i(3, 3)])
	_check("pin_once_per_turn", first.ok and not second.ok and b.player.energy == 1 and original.pinned_exhausted and b.board.cells.has(original), "精铸固定实体每回合只能使用一次，保留原格")
	b.begin_player_turn(false)
	result = b.try_play([Vector2i(3, 3)])
	_check("pin_turn_refresh", result.ok and b.player.energy == 2, "固定实体下回合可再次使用")
	b = _battle()
	_word(b, "重载")
	_word(b, "重载")
	b.rules.turn_draw = 3
	_pad(b)
	b.begin_player_turn()
	var draw_first := b.drawn_this_turn
	b.begin_player_turn()
	_check("reload_penalty_once", b.player.heat_capacity == b.rules.heat_capacity + 8 and draw_first == 1 and b.drawn_this_turn == 3 and b.base_draw_penalty == 0, "两次重载仅让下一回合少补2字，后续恢复基础补字")
	b = _battle()
	_word(b, "蓄能")
	_place(b, Vector2i(2, 2), "防")
	_place(b, Vector2i(3, 2), "御")
	b.end_player_turn()
	_check("energy_idle_buff", b.player.energy == 3, "蓄能激活+1，有可用词的回合末+2")
	b = _battle()
	_pad(b)
	_word(b, "充电过热")
	var initial_heat := b.player.heat
	b.try_play([Vector2i.ZERO])
	_check("auto_refill_upkeep", initial_heat == 8 and b.player.heat == 9 and b.board.fill_count() == 16, "启用首轮补满免维护热度，后续实际补1字升温1")
	b = _battle()
	b.player.heat = 8
	_word(b, "热力")
	b.player.energy = 3
	_word(b, "放电")
	_check("heat_bonus_multihit_preserved", b.enemies[0].hp == 140, "热力8热转每段+16，三段放电仍造成60伤")
	b = _battle()
	b.player.energy = 3
	_word(b, "蓄力")
	b.begin_player_turn(false)
	b.player.energy = 3
	_word(b, "放电")
	_check("energy_bonus_survives_turn", b.enemies[0].hp == 170, "蓄力3能转换为每段+6，跨回合三段共30伤")
	b = _battle()
	_word(b, "过火")
	b.player.energy = 3
	_word(b, "放电")
	_check("overfire_once_per_attack", b.enemies[0].hp == 182, "过火热2只追加6一次，三段放电共18伤")
	b = _battle()
	b.player.energy = 5
	b.spend_energy(5)
	_word(b, "复电")
	_word(b, "复电")
	_check("refund_ceil_once", b.player.energy == 3 and b.last_energy_half_claimed, "消费5能半额向上取整为3，同笔消费只能复电一次")
	b = _battle()
	b.player.energy = 1
	b.enable_ability("energy_refund_once")
	b.spend_energy(1)
	_word(b, "复电")
	_check("refund_shared_ledger", b.player.energy == 1 and b.last_energy_refunded == 1, "复与复电共用退款记录，消费1已退1不再退")
	b = _battle()
	b.player.energy = 6
	b.enable_ability("energy_refund_once")
	b.spend_energy(6)
	_word(b, "复电")
	_check("refund_deduct_previous", b.player.energy == 3 and b.last_energy_refunded == 3, "6能消费已有复退1，复电只再退2达到半额3")
	b = _battle()
	_word(b, "蓄热")
	_word(b, "超能力", 1)
	_word(b, "防御", 2)
	var pending := b.has_ability("double_next")
	b.add_heat(2)
	b.end_player_turn()
	_check("double_passive_idle", pending and b.player.energy == 4 and b.player.heat == 0 and not b.has_ability("double_next"), "普通出词不空耗超能力，蓄热只降2热但获得4能；跨回合后翻倍结束")
	b = _battle()
	b.player.hp = 40
	_word(b, "强心")
	b.begin_player_turn(false)
	_check("strong_heart_base_heal", b.player.hp == 42, "没有心力触发时，强心每回合也回复2血")
	b = _battle()
	_word(b, "连载")
	_word(b, "防御")
	_word(b, "防御")
	b.begin_player_turn(false)
	_place(b, Vector2i(3, 3), "击")
	b.try_play([Vector2i(3, 3)])
	_check("serial_repeats_and_carry", b.serial_words == 3 and b.enemies[0].hp == 190, "连载重复词推进次数，待兑现6伤跨回合保留")
	b = _battle()
	_word(b, "过热")
	b.add_heat(11)
	b.begin_player_turn(false)
	b.add_heat(1)
	_check("overheat_rearms", b.has_ability("heat_overload_bonus_armed") and b.ability_value("next_draw_bonus") == 2 and not b.has_ability("heat_overload_bonus"), "过热本场每回合重新武装首次溢热奖励")
	b = _battle()
	_word(b, "复利")
	_word(b, "复利")
	b.begin_player_turn(false)
	_check("immediate_profit_no_passive", GameState.gold == 104 and not b.has_ability("compound_equity"), "复利只即时给普通铜钱，没有股权或被动首投奖励")

func _occurrences(b: BattleState, inst: CharInstance) -> int:
	var n := 0
	for arr in [b.bag, b.discard, b.board.cells, b.pending_reveal, b.reconnect_pending.map(func(item): return item.inst)]:
		for c in arr:
			if c == inst:
				n += 1
	return n

func _run_converge() -> void:
	# 前面的字被挡住后，必须利用后面的字在后续轮次让出的空位。
	var b := _battle()
	var anchor := _place(b, Vector2i(3, 3), "击")
	var far := _place(b, Vector2i(3, 0), "防")
	var near := _place(b, Vector2i(3, 1), "御")
	_word(b, "重心", 2, {"tile": Vector2i(3, 3)})
	_check("converge_word_gap", b.board.get_cell(3, 0) == null and b.board.get_cell(3, 1) == far and b.board.get_cell(3, 2) == near, "一次重心就填补列中空隙，防、御依次停在锚点上方")
	_check("converge_anchor_stationary", b.board.get_cell(3, 3) == anchor, "选定的锚点实体留在原格")
	_check("converge_word_count", b.log.has("重心：2 枚字向锚点聚拢"), "移动数量按不同实体计数，不累计移动步数")
	var stable := b.board.cells.duplicate()
	_check("converge_idempotent", b.converge_to(Vector2i(3, 3)) == 0 and b.board.cells == stable, "稳定盘面再次聚拢不发生变化")
	_check("converge_word_conservation", b.board.fill_count() == 3 and b.discard.size() == 2 and _unique_circulation(b), "重心两字正常消耗，其余实体不重复、不丢失")

	# 两字竞争同一个更近的空格：上方优先；同一行则左方优先。
	b = _battle()
	_place(b, Vector2i.ZERO, "击")
	_place(b, Vector2i(0, 1), "回").pinned = true
	var upper := _place(b, Vector2i(2, 0), "防")
	var lower := _place(b, Vector2i(1, 1), "御")
	b.converge_to(Vector2i.ZERO)
	_check("converge_upper_priority", b.board.get_cell(1, 0) == upper and b.board.get_cell(1, 1) == lower, "上方字优先占位，即使后方字位于更左的列")
	b = _battle()
	_place(b, Vector2i(1, 0), "击")
	_place(b, Vector2i(0, 0), "回").pinned = true
	_place(b, Vector2i(2, 0), "回").pinned = true
	var left := _place(b, Vector2i(0, 1), "防")
	var right := _place(b, Vector2i(2, 1), "御")
	b.converge_to(Vector2i(1, 0))
	_check("converge_left_priority", b.board.get_cell(1, 1) == left and b.board.get_cell(2, 1) == right, "同行争位时左方字优先")

	# 一轮只走一步；首选空格已被预约时，可以选择另一条更近的路径。
	b = _battle()
	_place(b, Vector2i.ZERO, "击")
	far = _place(b, Vector2i(3, 0), "防")
	near = _place(b, Vector2i(2, 1), "御")
	_check("converge_round_conflict_fallback", b.converge_to(Vector2i.ZERO) == 2 and b.board.get_cell(1, 0) == far and b.board.get_cell(0, 1) == near, "御避开防本轮预约的空格，从左侧靠近锚点，不被逐字滑到底的顺序卡在外围")

	# 无障碍时保持先上下后左右；多个属性随原实体移动，不重建实例。
	b = _battle()
	anchor = _place(b, Vector2i.ZERO, "击")
	var layered := _place(b, Vector2i(3, 3), "防")
	layered.fusion.assign(["御", "回"])
	layered.temporary_uses = 2
	layered.temporary = true
	layered.gilded = true
	layered.owner = CharInstance.Owner.ENEMY
	layered.add_pollution("scorch")
	layered.modifiers.assign(["audit_modifier"])
	layered.statuses["audit_status"] = 3
	layered.upgrade_level = 1
	var uid := layered.uid
	_check("converge_distinct_count", b.converge_to(Vector2i.ZERO) == 1 and b.board.get_cell(1, 0) == layered, "同一字移动五步仍只计一枚，保持先上下后左右的路径偏好")
	_check("converge_preserve_attributes", layered.uid == uid and layered.fusion == ["御", "回"] and layered.temporary_uses == 2 and layered.temporary and layered.gilded and layered.owner == CharInstance.Owner.ENEMY and layered.pollutions == ["scorch"] and layered.modifiers == ["audit_modifier"] and layered.statuses == {"audit_status": 3} and layered.upgrade_level == 1, "融合、层数、临时、镀金、归属、污染与升级状态随实体保留")
	_check("converge_entity_conservation", b.board.fill_count() == 2 and b.board.get_cell(0, 0) == anchor and _occurrences(b, layered) == 1 and _unique_circulation(b), "聚拢不会复制、拆分或吞掉融合实体")

	# 固定字作为障碍；被挡住的字不能通过远离锚点绕行。
	b = _battle()
	anchor = _place(b, Vector2i(3, 3), "击")
	var fixed := _place(b, Vector2i(3, 2), "御")
	fixed.pinned = true
	var blocked := _place(b, Vector2i(3, 0), "防")
	_check("converge_pinned_obstacle", b.converge_to(Vector2i(3, 3)) == 1 and b.board.get_cell(3, 1) == blocked and b.board.get_cell(3, 2) == fixed and fixed.pinned and b.board.get_cell(3, 3) == anchor, "固定字原地阻挡，后方字停在前一格，不能向左绕过障碍")

	b = _battle()
	for y in b.board.size:
		for x in b.board.size:
			_place(b, Vector2i(x, y), "防")
	stable = b.board.cells.duplicate()
	_check("converge_full_board", b.converge_to(Vector2i(2, 2)) == 0 and b.board.cells == stable, "满盘没有空位时结束，所有实体保持原位")
	b = _battle()
	_check("converge_empty_board", b.converge_to(Vector2i.ZERO) == 0 and b.board.fill_count() == 0, "空盘直接结束")

	# 尺寸来自棋盘，不限制为 4×4。
	b.board = BoardState.new(6)
	anchor = _place(b, Vector2i(5, 5), "击")
	far = _place(b, Vector2i(5, 0), "防")
	near = _place(b, Vector2i(5, 1), "御")
	_check("converge_large_board", b.converge_to(Vector2i(5, 5)) == 2 and b.board.get_cell(5, 3) == far and b.board.get_cell(5, 4) == near and b.board.get_cell(5, 5) == anchor and b.board.fill_count() == 3, "较大棋盘的多轮移动同样填补空隙并保留三枚实体")
	stable = b.board.cells.duplicate()
	_check("converge_invalid_anchor", b.converge_to(Vector2i(-1, 0)) == 0 and b.board.cells == stable, "越界锚点不改动盘面")

func _run_word_completion() -> void:
	for text in ["流速", "重回", "重连", "流连", "回心", "回能", "防反", "回复"]:
		var word := Database.get_word_by_glyphs_string(text)
		_check("word_catalog_" + text, word != null and word.implemented and not word.effects.is_empty() and word.glyphs.all(func(g): return Database.get_character_by_glyph(g) != null), "词条已登记、组成字存在，并有实际词效")

	var b := _battle()
	_pad(b)
	_word(b, "流速", 0, {"row": 1})
	_check("flow_speed_arm", b.flow_speed_rows.get(1, 0) == 2 and b.drawn_this_turn == 0 and StatusDisplay.collect(b.player, b).any(func(item): return item.id == "flow_speed:1" and item.stacks == 2), "选定第二行，HUD 显示后续两词，流速自身不补字")
	var marker := _place(b, Vector2i(3, 1), "回")
	_place(b, Vector2i(2, 1), "防")
	b.try_play([Vector2i(2, 1)])
	_check("flow_speed_ignore_solo", b.flow_speed_rows.get(1, 0) == 2 and b.drawn_this_turn == 0 and b.board.get_cell(2, 1) == null, "单字出牌不补回、不消费补词额度")
	for g in ["御", "防", "御", "防"]:
		b.bag.append(CharInstance.new(Database.get_character_by_glyph(g)))
	_word(b, "防御", 1)
	_check("flow_speed_first_word", b.flow_speed_rows.get(1, 0) == 1 and b.drawn_this_turn == 2 and b.board.get_cell(0, 1).glyph() == "防" and b.board.get_cell(1, 1).glyph() == "御" and b.board.get_cell(3, 1) == marker, "原地补回本词两枚字，同行其他字不位移，只扣一词")
	b.try_play([Vector2i(0, 1), Vector2i(1, 1)])
	_check("flow_speed_repeat_same_word", b.flow_speed_rows.is_empty() and b.drawn_this_turn == 4, "同一防御词可连续打出两次，各原地补回两枚")
	b.try_play([Vector2i(0, 1), Vector2i(1, 1)])
	_check("flow_speed_exhausted", b.drawn_this_turn == 4 and b.board.get_cell(0, 1) == null and b.board.get_cell(1, 1) == null, "两词额度耗尽后，第三词不再补回")
	_word(b, "流速", 0, {"row": 1})
	_word(b, "流速", 0, {"row": 1})
	_check("flow_speed_stack", b.flow_speed_rows.get(1, 0) == 4 and b.drawn_this_turn == 4, "重复施放同一行叠加为四词，施放本身不消耗额度")
	b.begin_player_turn(false)
	_check("flow_speed_turn_reset", b.flow_speed_rows.is_empty() and b.drawn_this_turn == 0, "新回合清理所有未使用的行额度")

	b = _battle()
	_pad(b)
	b.begin_formation()
	_word(b, "流速", 0, {"row": 1})
	_word(b, "防御", 1)
	_place(b, Vector2i(2, 1), "回")
	_place(b, Vector2i(3, 1), "能")
	b.try_play([Vector2i(2, 1), Vector2i(3, 1)])
	b.resolve_formation()
	_check("flow_speed_formation", b.drawn_this_turn == 4 and b.flow_speed_rows.is_empty() and b.board.get_cell(0, 1) != null and b.board.get_cell(3, 1) != null and _unique_circulation(b), "结阵按登记顺序开启，并原地补回同一行两词的四枚实体")
	b = _battle()
	_pad(b)
	_word(b, "流速", 0, {"row": 1})
	b.player.add_status("next_extra", 1)
	_word(b, "击破", 1)
	_check("flow_speed_replay_once", b.drawn_this_turn == 2 and b.flow_speed_rows.get(1, 0) == 1 and b.enemies[0].hp == 184, "超载重演词效仍只算一次出词，原地补两字而不重复扣次数")

	b = _battle()
	var originals: Array = []
	for g in ["防", "御", "电"]:
		var inst := _place(b, Vector2i(3, 3), g)
		originals.append(inst)
		b.try_play([Vector2i(3, 3)])
	originals[2].gilded = true
	_word(b, "重回")
	_check("recover_recent_order", b.bag == [originals[1], originals[2]] and b.discard.has(originals[0]), "重回只取最近两枚，最近的一枚位于字袋顶")
	_check("recover_recent_excludes_self", not b.bag.any(func(inst): return inst.glyph() in ["重", "回"]) and b.discard.size() == 3, "重回不能取回本次施词字")
	b.draw_one_to(Vector2i(3, 3))
	_word(b, "重回", 1)
	_check("recover_recent_identity", b.board.get_cell(3, 3) == originals[2] and originals[2].gilded and originals.all(func(inst): return _occurrences(b, inst) == 1) and _unique_circulation(b), "已抽回盘面的实体不再被回收，实体和属性保持唯一")
	b = _battle()
	_word(b, "重回")
	_check("recover_recent_empty", b.bag.is_empty() and b.discard.size() == 2, "无此前消耗时不凭空复制或取回自身")

	b = _battle()
	var positions := [Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3)]
	var suspended: Array = []
	for i in 3:
		suspended.append(_place(b, positions[i], "防御回"[i]))
	_word(b, "重连", 0, {"cells": positions})
	_check("reconnect_suspend_three", b.reconnect_pending.size() == 3 and positions.all(func(pos): return b.board.get_xy(pos) == null) and b.discard.size() == 2 and _unique_circulation(b), "三个原实体离开棋盘并暂存，施词字正常消耗")
	_check("reconnect_wait_next_turn", b.restore_reconnect_tiles() == 0 and b.reconnect_pending.size() == 3, "本回合不能提前返回")
	var hp_before: int = b.enemies[0].hp
	_word(b, "击破")
	_check("reconnect_no_attack_repeat", hp_before - b.enemies[0].hp == 8 and b.reconnect_pending.size() == 3, "重连不再重复攻击词效果")
	b.begin_player_turn(false)
	_check("reconnect_original_slots", b.reconnect_pending.is_empty() and b.board.get_xy(positions[0]) == suspended[0] and b.board.get_xy(positions[1]) == suspended[1] and b.board.get_xy(positions[2]) == suspended[2] and _unique_circulation(b), "下一回合原实体回到原格")
	_word(b, "流连", 2)
	b.begin_player_turn(false)
	_check("linger_turn_expiry", not b.has_ability("linger_chance"), "流连在下一回合开始时清理")

	b = _battle()
	_word(b, "流连")
	var forecast := RandomNumberGenerator.new()
	forecast.state = b.rng.state
	var keep_solo := forecast.randf() < 0.25
	var solo := _place(b, Vector2i(3, 3), "防")
	b.try_play([Vector2i(3, 3)])
	_check("linger_applies_to_solo", b.ability_value("linger_chance") == 1 and (b.board.get_cell(3, 3) == solo) == keep_solo and b.discard.has(solo) == (not keep_solo), "单字也以 25% 概率保留原实体，流连本回合继续有效")
	var head := _place(b, Vector2i(0, 1), "防")
	var tail := _place(b, Vector2i(1, 1), "御")
	tail.gilded = true
	tail.add_pollution("rush")
	forecast.state = b.rng.state
	var keep_head := forecast.randf() < 0.25
	var keep_tail := forecast.randf() < 0.25
	b.try_play([Vector2i(0, 1), Vector2i(1, 1)])
	_check("linger_independent_originals", (b.board.get_cell(0, 1) == head) == keep_head and (b.board.get_cell(1, 1) == tail) == keep_tail and b.discard.has(head) == (not keep_head) and b.discard.has(tail) == (not keep_tail) and tail.gilded and tail.pollutions == ["rush"] and not tail.temporary and _unique_circulation(b), "每枚字独立判定，留下原实例及属性，不制造临时复制")
	b.begin_player_turn(false)
	solo = _place(b, Vector2i(3, 3), "防")
	b.try_play([Vector2i(3, 3)])
	_check("linger_expired_normal_consumption", b.board.get_cell(3, 3) == null and b.discard.has(solo) and not b.has_ability("linger_chance"), "下一回合恢复正常消耗，不延续保留概率")
	b = _battle()
	_word(b, "流连")
	_place(b, Vector2i(0, 1), "防")
	tail = _place(b, Vector2i(1, 1), "御")
	tail.pinned = true
	b.try_play([Vector2i(0, 1), Vector2i(1, 1)])
	_check("linger_pinned_tail", b.board.get_cell(1, 1) == tail and _occurrences(b, tail) == 1 and b.has_ability("linger_chance") and _unique_circulation(b), "固定字照常原地保留，不因流连制造额外实体")
	b = _battle()
	_word(b, "流连")
	tail = _place(b, Vector2i(3, 3), "防")
	tail.owner = CharInstance.Owner.ENEMY
	tail.temporary = true
	forecast.state = b.rng.state
	keep_tail = forecast.randf() < 0.25
	b.try_play([Vector2i(3, 3)])
	_check("linger_enemy_original", (b.board.get_cell(3, 3) == tail) == keep_tail and tail.owner == CharInstance.Owner.ENEMY and tail.temporary and not b.discard.has(tail) and _unique_circulation(b), "敌方和临时字也独立判定；成功时保留原归属，失败时照常消失")

	b = _battle()
	b.player.energy = 2
	_word(b, "回能")
	var energy_by_turn := [b.player.energy]
	_word(b, "回能", 1)
	var double_cast: bool = b.player.energy == 6 and b.ability_value("energy_regen") == 2
	for i in 3:
		b.begin_player_turn(false)
		energy_by_turn.append(b.player.energy)
	_check("restore_energy_three_turns", energy_by_turn == [4, 8, 10, 10] and double_cast and not b.has_ability("energy_regen") and b.attack_words_this_turn == 0, "打出当回合各给 2 储能（4→6），之后两回合开局各再 +2（8、10），第四回合停止")
	b = _battle()
	_word(b, "防反")
	_check("guard_counter_arm", b.player.block == 6 and b.ability_value("counter") == 1 and b.attack_words_this_turn == 0, "防反先提供六临挡，再预约一层延迟反击")
	b.end_player_turn()
	_check("guard_counter_resolve", b.player.hp == 60 and b.enemies[0].hp == 196 and not b.has_ability("counter") and b.player.block == 0, "挡住五伤后余一临挡，反击造成四伤并正常清理")
	b = _battle()
	_pad(b)
	b.player.hp = 30
	_word(b, "回心")
	_check("restore_heart", b.player.hp == 31 and b.drawn_this_turn == 3 and b.board.fill_count() == 3, "回心保留既有的一血三字效果")

func _run_solo_balance() -> void:
	var b := _battle()
	_place(b, Vector2i.ZERO, "放")
	var result := b.try_play([Vector2i.ZERO])
	_check("solo_release_free", result.ok and b.enemies[0].hp == 198 and b.player.energy == 0, "无储能时放仍造成2伤，不请求额外资源")
	b = _battle()
	b.player.energy = 2
	_place(b, Vector2i.ZERO, "放")
	b.try_play([Vector2i.ZERO], {"release_energy": false})
	_place(b, Vector2i.ZERO, "放")
	b.try_play([Vector2i.ZERO], {"release_energy": true})
	_check("solo_release_optional_energy", b.player.energy == 1 and b.enemies[0].hp == 190 and b.last_energy_spent == 1, "有储能时仍可打2伤，选择释放才消耗1储能打8伤")
	b = _battle()
	var source := _place(b, Vector2i.ZERO, "放")
	result = b.try_play([Vector2i.ZERO], {"release_energy": true})
	_check("solo_release_insufficient_atomic", not result.ok and b.board.get_cell(0, 0) == source and b.discard.is_empty() and b.enemies[0].hp == 200, "不足储能时拒绝释放，保留原字，不攻击")

	b = _battle()
	_place(b, Vector2i.ZERO, "力")
	b.try_play([Vector2i.ZERO])
	b.player.energy = 2
	_word(b, "放电")
	var first_damage: int = 200 - b.enemies[0].hp
	_place(b, Vector2i.ZERO, "击")
	b.try_play([Vector2i.ZERO])
	_check("solo_force_once_total", first_damage == 10 and b.enemies[0].hp == 186 and not b.has_ability("force_once"), "力给两段放电合计只加2伤，之后击恢复4伤")
	b = _battle()
	_word(b, "强力")
	_place(b, Vector2i.ZERO, "强")
	b.try_play([Vector2i.ZERO])
	_place(b, Vector2i.ZERO, "击")
	b.try_play([Vector2i.ZERO])
	var damage_before_reset: int = 200 - b.enemies[0].hp
	b.begin_player_turn(false)
	_place(b, Vector2i.ZERO, "击")
	b.try_play([Vector2i.ZERO])
	_check("solo_strong_turn_only", damage_before_reset == 7 and b.enemies[0].hp == 187 and b.player.turn_strength == 0 and b.player.status_stacks("strength") == 2, "强只加本回合1伤，清除时不影响强力词的持续2伤")

	b = _battle()
	_place(b, Vector2i.ZERO, "能")
	b.try_play([Vector2i.ZERO])
	b.add_energy(0)
	var waiting: bool = b.has_ability("energy_gain_once")
	b.add_energy(2)
	b.add_energy(1)
	_check("solo_energy_bonus_once", waiting and b.player.energy == 4 and not b.has_ability("energy_gain_once"), "能只放大下一次正数储能获得，额外1点且不重复触发")
	_place(b, Vector2i.ZERO, "能")
	b.try_play([Vector2i.ZERO])
	_place(b, Vector2i.ZERO, "连")
	b.try_play([Vector2i.ZERO])
	b.begin_player_turn(false)
	_check("solo_turn_marks_expire", not b.has_ability("energy_gain_once") and not b.has_ability("link_draw_once"), "能和连的未兑现标记到新回合清除")
	b = _battle()
	_pad(b)
	_place(b, Vector2i.ZERO, "连")
	b.try_play([Vector2i.ZERO])
	_place(b, Vector2i.ZERO, "防")
	b.try_play([Vector2i.ZERO])
	var waited_for_word: bool = b.has_ability("link_draw_once") and b.drawn_this_turn == 0
	_word(b, "防御")
	_word(b, "防御")
	_check("solo_link_one_word", waited_for_word and b.drawn_this_turn == 1 and not b.has_ability("link_draw_once"), "连等待成功组词，单字不消耗标记，只补一次")

	b = _battle()
	var neighbor := _place(b, Vector2i(1, 0), "御")
	neighbor.owner = CharInstance.Owner.ENEMY
	neighbor.pollutions.assign(["scorch", "rush"])
	var untouched := _place(b, Vector2i(0, 1), "防")
	untouched.add_pollution("scorch")
	_place(b, Vector2i.ZERO, "清")
	b.try_play([Vector2i.ZERO], {"tile": Vector2i(1, 0)})
	var cleared_one: bool = neighbor.pollutions == ["rush"] and untouched.pollutions == ["scorch"]
	_place(b, Vector2i.ZERO, "洗")
	b.try_play([Vector2i.ZERO], {"tile": Vector2i(1, 0)})
	_check("solo_clean_wash_scope", cleared_one and neighbor.pollutions.is_empty() and neighbor.owner == CharInstance.Owner.ENEMY and b.board.get_cell(1, 0) == neighbor and untouched.pollutions == ["scorch"], "清只去选中字的一个标签，洗去全部标签，其余邻字和归属保留")
	source = _place(b, Vector2i.ZERO, "清")
	var distant := _place(b, Vector2i(3, 3), "防")
	distant.add_pollution("scorch")
	result = b.try_play([Vector2i.ZERO], {"tile": Vector2i(3, 3)})
	_check("solo_clean_invalid_target", not result.ok and b.board.get_cell(0, 0) == source and distant.pollutions == ["scorch"], "清不能选非四邻目标，非法选择不消耗施词字")
	b = _battle()
	for glyph in ["清", "洗", "转"]:
		_place(b, Vector2i.ZERO, glyph)
		result = b.try_play([Vector2i.ZERO])
		assert(result.ok)
	_check("solo_no_neighbor_can_discard", b.board.fill_count() == 0 and b.discard.size() == 3, "没有相邻有效目标时清、洗、转仍可直接打出腾位")

	b = _battle()
	source = _place(b, Vector2i.ZERO, "转")
	neighbor = _place(b, Vector2i(1, 0), "防")
	neighbor.fusion.assign(["御"])
	neighbor.gilded = true
	untouched = _place(b, Vector2i(0, 1), "回")
	untouched.pinned = true
	result = b.try_play([Vector2i.ZERO], {"tile": Vector2i(0, 1)})
	var fixed_rejected: bool = not result.ok and b.board.get_cell(0, 0) == source
	b.try_play([Vector2i.ZERO], {"tile": Vector2i(1, 0)})
	_check("solo_turn_neighbor_original", fixed_rejected and b.board.get_cell(0, 0) == neighbor and b.board.get_cell(1, 0) == null and b.board.get_cell(0, 1) == untouched and neighbor.fusion == ["御"] and neighbor.gilded and _unique_circulation(b), "转仅移动选定四邻原实体，固定字不能移动，融合与镀金保留")
	var h := BattleHarness.new()
	h.battle = _battle()
	h.battle.player.energy = 1
	_place(h.battle, Vector2i.ZERO, "放")
	var offers_release: bool = h.legal_actions().any(func(action): return action.get("target", {}).get("release_energy", false))
	result = h.apply({"type": "play", "path": [[0, 0]], "target": {"release_energy": true}})
	_check("solo_harness_energy_choice", offers_release and result.ok and h.battle.player.energy == 0 and h.battle.enemies[0].hp == 192, "自动化接口公开并执行放的可选储能攻击")

func _run_solo_balance_four() -> void:
	var b := _battle()
	_place(b, Vector2i.ZERO, "加")
	b.try_play([Vector2i.ZERO])
	_word(b, "防御")
	_place(b, Vector2i.ZERO, "火")
	b.try_play([Vector2i.ZERO])
	_check("solo_add_waits_for_direct_solo", b.player.block == 10 and b.player.heat == 1 and b.has_ability("solo_gain_once"), "加不放大词效、热度或持续标记")
	_place(b, Vector2i.ZERO, "爆")
	b.try_play([Vector2i.ZERO])
	_place(b, Vector2i.ZERO, "击")
	b.try_play([Vector2i.ZERO])
	_check("solo_add_damage_once", b.enemies[0].hp == 193 and b.player.heat == 2 and not b.has_ability("solo_gain_once"), "爆首项伤害由2增至3，热度不变；之后击仍然4伤")
	for glyph in ["防", "心", "电", "充", "放", "息", "化"]:
		b = _battle()
		b.player.hp = 50
		b.player.heat = 2
		_place(b, Vector2i.ZERO, "加")
		b.try_play([Vector2i.ZERO])
		_place(b, Vector2i.ZERO, glyph)
		b.try_play([Vector2i.ZERO])
		var increased: bool = b.player.block == 5 if glyph == "防" else (b.player.hp == 52 if glyph in ["心", "息"] else (b.enemies[0].hp == 197 if glyph == "放" else b.player.energy == 2))
		_check("solo_add_numeric_" + glyph, increased and not b.has_ability("solo_gain_once"), "加只增加该单字首项符合条件的直接收益")
	b = _battle()
	_place(b, Vector2i.ZERO, "加")
	b.try_play([Vector2i.ZERO])
	_place(b, Vector2i.ZERO, "超")
	b.try_play([Vector2i.ZERO])
	b.begin_player_turn(false)
	_check("solo_add_gap_expire", not b.has_ability("solo_gain_once") and not b.has_ability("next_gap") and b.board.gap_steps_allowed == 0, "加和超未使用时在下回合失效")

	b = _battle()
	_place(b, Vector2i.ZERO, "防")
	_place(b, Vector2i(2, 0), "御")
	var path := [Vector2i.ZERO, Vector2i(2, 0)]
	var result := b.try_play(path)
	var blocked_without: bool = not result.ok
	b.enable_ability("next_gap")
	var blocker := _place(b, Vector2i(1, 0), "心")
	result = b.try_play(path)
	_check("solo_gap_blocker_rejected", blocked_without and not result.ok and b.has_ability("next_gap") and b.board.cells.has(blocker), "未开超不能跨空格；开启后仍不能跨过有字的格子")
	b.board.clear_xy(Vector2i(1, 0))
	result = b.try_play(path)
	_check("solo_gap_success_consumes", result.ok and b.player.block == 10 and b.board.get_xy(Vector2i(1, 0)) == null and not b.has_ability("next_gap") and b.board.gap_steps_allowed == 0, "跨一个空格正常成词，不消费空格，成功后清除机会")
	b = _battle()
	b.enable_ability("next_gap")
	_place(b, Vector2i.ZERO, "充")
	_place(b, Vector2i(2, 0), "放")
	_place(b, Vector2i(2, 2), "电")
	result = b.try_play([Vector2i.ZERO, Vector2i(2, 0), Vector2i(2, 2)])
	_check("solo_gap_budget_one", not result.ok and b.has_ability("next_gap") and b.board.fill_count() == 3, "一条词不能跨两个空格，失败不消费材料或标记")
	b.board.clear_xy(Vector2i(2, 2))
	_place(b, Vector2i(3, 1), "电")
	b.enable_ability("next_diagonal", 1)
	result = b.try_play([Vector2i.ZERO, Vector2i(2, 0), Vector2i(3, 1)])
	_check("solo_gap_and_diagonal", result.ok and not b.has_ability("next_gap") and not b.has_ability("next_free_word"), "超的跨格与流利的斜连预算独立，能在同一词中配合")
	b = _battle()
	b.enable_ability("next_gap")
	b.begin_formation()
	_place(b, Vector2i.ZERO, "防")
	_place(b, Vector2i(2, 0), "御")
	_place(b, Vector2i(0, 2), "防")
	_place(b, Vector2i(2, 2), "御")
	var queued := b.try_play(path)
	result = b.try_play([Vector2i(0, 2), Vector2i(2, 2)])
	b.resolve_formation()
	_check("solo_gap_formation_reservation", queued.ok and not result.ok and b.player.block == 10 and b.board.get_xy(Vector2i(0, 2)) != null and not b.has_ability("next_gap"), "结阵首个登记词独占跨格机会，后续词不能重复使用")
	var h := BattleHarness.new()
	h.battle = _battle()
	h.battle.enable_ability("next_gap")
	_place(h.battle, Vector2i.ZERO, "防")
	_place(h.battle, Vector2i(0, 2), "御")
	var action: Dictionary = {}
	for offered in h.legal_actions():
		if offered.get("word") == "防御":
			action = offered
	_check("solo_gap_harness_search", not action.is_empty() and h.battle._has_any_word_on_board() and h.apply(action).ok and h.battle.player.block == 10, "词搜索与自动化执行均识别纵向跨空格")

	b = _battle()
	var source := _place(b, Vector2i.ZERO, "精")
	var cards: Array = []
	for glyph in ["击", "防", "防"]:
		cards.append(CharInstance.new(Database.get_character_by_glyph(glyph)))
	b.bag.append_array(cards)
	cards[1].gilded = true
	cards[2].fusion.assign(["御"])
	var state_before := b.rng.state
	var candidates := b.solo_bag_candidates(source)
	_check("solo_precision_preview_entities", candidates == [cards[2], cards[1]] and b.bag == cards and b.rng.state == state_before and b.board.cells.has(source), "精只揭示袋顶两个不同实体，预览不改变字袋、原字或随机数")
	result = b.try_play([Vector2i.ZERO], {"bag_uid": cards[0].uid})
	_check("solo_precision_rejects_other_card", not result.ok and b.board.cells.has(source) and b.bag.size() == 3, "精不能选两枚候选以外的实体，失败保留原字")
	result = b.try_play([Vector2i.ZERO], {"bag_uid": cards[1].uid})
	_check("solo_precision_keeps_attributes", result.ok and b.board.get_xy(Vector2i.ZERO) == cards[1] and cards[1].gilded and b.bag.has(cards[2]) and b.bag.has(cards[0]) and b.discard.has(source) and b.drawn_this_turn == 1 and _unique_circulation(b), "精只移动指定实体，同字形另一实体留袋，属性及数量守恒")
	b = _battle()
	_place(b, Vector2i.ZERO, "精")
	var only := CharInstance.new(Database.get_character_by_glyph("击"))
	b.bag.append(only)
	result = b.try_play([Vector2i.ZERO])
	_check("solo_precision_single_candidate", result.ok and b.board.get_xy(Vector2i.ZERO) == only and b.drawn_this_turn == 1, "精只有一个候选时无需额外选择，直接补入")

	b = _battle()
	source = _place(b, Vector2i.ZERO, "购")
	var bought := CharInstance.new(Database.get_character_by_glyph("防"))
	bought.fusion.assign(["御"])
	bought.gilded = true
	b.bag.append(bought)
	GameState.gold = 1
	result = b.try_play([Vector2i.ZERO], {"bag_uid": bought.uid})
	_check("solo_buy_no_payment_no_consume", not result.ok and GameState.gold == 1 and b.board.cells.has(source) and b.bag.has(bought), "购支付不足时保留原字、候选和铜钱")
	b.enable_ability("payment_discount_once", 1)
	result = b.try_play([Vector2i.ZERO], {"bag_uid": bought.uid})
	_check("solo_buy_discount_and_identity", result.ok and GameState.gold == 0 and b.board.get_xy(Vector2i.ZERO) == bought and bought.gilded and bought.glyph_list() == ["防", "御"] and not b.has_ability("payment_discount_once") and b.drawn_this_turn == 1 and _unique_circulation(b), "购使用正常支付优惠，原实体原属性补入指定格")
	for glyph in ["精", "购"]:
		b = _battle()
		_place(b, Vector2i.ZERO, glyph)
		result = b.try_play([Vector2i.ZERO])
		_check("solo_bag_empty_" + glyph, result.ok and GameState.gold == 100 and b.board.fill_count() == 0 and b.drawn_this_turn == 0, "空袋只弃字，不凭空生成实体或扣费")
	b = _battle()
	b.player.heat = 1
	b.enable_ability("solo_gain_once", 1)
	_place(b, Vector2i.ZERO, "化")
	b.try_play([Vector2i.ZERO])
	_check("solo_conversion_insufficient_heat", b.player.heat == 1 and b.player.energy == 0 and b.has_ability("solo_gain_once"), "化热度不足不进行部分转换，也不消耗加的标记")
	b.player.heat = 3
	_place(b, Vector2i.ZERO, "化")
	b.try_play([Vector2i.ZERO])
	_check("solo_conversion_heat_energy", b.player.heat == 1 and b.player.energy == 2 and not b.has_ability("solo_gain_once"), "化消耗恰好2热，获得1储能，可被加增强储能收益")
	for glyph in ["精", "购"]:
		h = BattleHarness.new()
		h.battle = _battle()
		_place(h.battle, Vector2i.ZERO, glyph)
		var first := CharInstance.new(Database.get_character_by_glyph("防"))
		var second := CharInstance.new(Database.get_character_by_glyph("防"))
		h.battle.bag.append_array([first, second])
		for offered in h.legal_actions():
			if offered.get("needs") == "bag":
				action = offered
		action["target"] = action.bag_choices[1].target
		result = h.apply(action)
		_check("solo_bag_harness_choices_" + glyph, result.ok and action.bag_choices[1].card.uid == first.uid and h.battle.board.get_xy(Vector2i.ZERO) == first and h.battle.bag == [second] and GameState.gold == (98 if glyph == "购" else 100), "自动化公开候选实体及目标UID，能明确选中同字形第二枚候选")

func _run_solo_balance_three() -> void:
	var b := _battle()
	_place(b, Vector2i.ZERO, "合")
	b.try_play([Vector2i.ZERO])
	_place(b, Vector2i.ZERO, "加")
	b.try_play([Vector2i.ZERO])
	_place(b, Vector2i.ZERO, "御")
	_place(b, Vector2i(1, 0), "加")
	var invalid := b.try_play([Vector2i.ZERO, Vector2i(1, 0)])
	_check("solo_combine_waits_for_word", not invalid.ok and b.player.block == 0 and b.player.energy == 0 and b.has_ability("combine_word_once"), "合不立即发资源，单字与非法词不消耗标记")
	_word(b, "防御")
	_check("solo_combine_payout", b.player.block == 12 and b.player.energy == 1 and not b.has_ability("combine_word_once"), "下一次成功组词获得额外2临挡和1储能")
	b.player.block = 0
	_word(b, "防御")
	_check("solo_combine_once", b.player.block == 10 and b.player.energy == 1, "合不对后续词重复发放")
	b = _battle()
	_pad(b)
	_place(b, Vector2i.ZERO, "速")
	b.try_play([Vector2i.ZERO])
	_word(b, "重击")
	_check("solo_speed_word_draw", b.drawn_this_turn == 2 and b.player.heat == 1 and not b.has_ability("speed_word_once"), "速在下一次成词后补2字并升1热")
	_word(b, "重击")
	_check("solo_speed_once", b.drawn_this_turn == 2 and b.player.heat == 1, "速仅触发一次")
	b = _battle()
	for glyph in ["合", "速", "复"]:
		_place(b, Vector2i.ZERO, glyph)
		b.try_play([Vector2i.ZERO])
	b.begin_player_turn(false)
	_check("solo_third_batch_expiry", not b.has_ability("combine_word_once") and not b.has_ability("speed_word_once") and not b.has_ability("energy_refund_once"), "合速复未触发的标记不会跨回合")
	b = _battle()
	b.player.energy = 3
	b.spend_energy(1)
	_place(b, Vector2i.ZERO, "复")
	b.try_play([Vector2i.ZERO])
	b.spend_energy(0)
	_check("solo_refund_requires_future_spend", b.player.energy == 2 and b.has_ability("energy_refund_once"), "复不返还历史花费，零消耗不触发")
	b.spend_energy(2)
	b.spend_energy(1)
	_check("solo_refund_once", b.player.energy == 0 and not b.has_ability("energy_refund_once") and b.last_energy_spent == 1, "复只返还下一次实际花费中的1点")
	b = _battle()
	b.enable_ability("energy_refund_once", 2)
	b.spend_energy(1)
	var remains_when_empty := b.has_ability("energy_refund_once")
	b.player.energy = 1
	b.spend_energy(8)
	_check("solo_refund_actual_limit", remains_when_empty and b.player.energy == 1 and b.last_energy_spent == 1 and not b.has_ability("energy_refund_once"), "无储能不能凭空退款，叠加退款也不超过实际花费")
	b = _battle()
	var capacity := b.player.heat_capacity
	for i in 2:
		_place(b, Vector2i.ZERO, "载")
		b.try_play([Vector2i.ZERO])
	_word(b, "重载")
	b.add_heat(capacity + 6)
	_check("solo_capacity_stacks", b.player.heat_capacity == capacity + 8 and b.temporary_heat_capacity == 4 and b.temp_chars.is_empty(), "两次载增加4临时热容，与重载永久加成独立")
	b.begin_player_turn(false)
	_check("solo_capacity_restore", b.player.heat_capacity == capacity + 4 and b.temporary_heat_capacity == 0 and b.player.heat == capacity + 6 and b.temp_chars.is_empty(), "载到期保留永久热容、保持热度，不立即生成溢热污染")
	b = _battle()
	b.player.heat = 6
	_place(b, Vector2i.ZERO, "停")
	b.try_play([Vector2i.ZERO])
	_check("solo_stop_requests_enemy_phase", b.player.heat == 2 and b.end_turn_requested, "停降4热并请求立即进入敌方阶段")
	b.end_player_turn()
	_check("solo_stop_enemy_acts", b.player.hp == 55 and b.turn == 2 and not b.end_turn_requested, "停不跳过敌方攻击")

	b = _battle()
	var source := _place(b, Vector2i.ZERO, "分")
	var original := _place(b, Vector2i(1, 0), "防")
	original.pollutions.assign(["scorch"])
	original.fusion.assign(["御"])
	original.gilded = true
	original.pinned = true
	original.temporary_uses = 3
	original.upgrade_level = 2
	var enemy := _place(b, Vector2i(0, 1), "心")
	enemy.owner = CharInstance.Owner.ENEMY
	invalid = b.try_play([Vector2i.ZERO], {"tile": Vector2i(0, 1)})
	_check("solo_split_rejects_enemy", not invalid.ok and b.board.get_xy(Vector2i.ZERO) == source and b.solo_target_cells(source, Vector2i.ZERO) == [Vector2i(1, 0)], "分仅接受四邻己方字，无效选择不消费施放字")
	b.try_play([Vector2i.ZERO], {"tile": Vector2i(1, 0)})
	var copy := b.board.get_xy(Vector2i.ZERO)
	_check("solo_split_plain_word_copy", copy != null and copy != original and copy.temporary and copy.word_only and copy.glyph_list() == ["防"] and copy.pollutions.is_empty() and copy.modifiers.is_empty() and not copy.gilded and not copy.pinned and copy.temporary_uses == 0 and copy.upgrade_level == 0 and b.board.get_xy(Vector2i(1, 0)) == original, "分复制主字形，不复制污染、融合、镀金、固定、层数或强化")
	assert(copy != null)
	b.empowered_glyphs["防"] = true
	b.enable_ability("repeat_zero", 1)
	b.bag.append(CharInstance.new(Database.get_character_by_glyph("击")))
	b.try_play([Vector2i.ZERO])
	_check("solo_split_no_solo_effect", b.player.block == 0 and b.board.get_xy(Vector2i.ZERO) == null and not b.discard.has(copy) and not b.temp_chars.has(copy) and copy.clone().word_only, "复制单独打出只弃掉；不触发单字强化或反复补字，复制限制可继承")
	b = _battle()
	_place(b, Vector2i.ZERO, "分")
	_place(b, Vector2i(0, 1), "防")
	b.try_play([Vector2i.ZERO], {"tile": Vector2i(0, 1)})
	copy = b.board.get_xy(Vector2i.ZERO)
	_place(b, Vector2i(1, 0), "御")
	var result := b.try_play([Vector2i.ZERO, Vector2i(1, 0)])
	_check("solo_split_word_works", result.ok and result.word.word == "防御" and b.player.block == 10 and not b.discard.has(copy) and b.board.get_xy(Vector2i(0, 1)) != null, "分的临时复制正常参与词效，消耗后不进弃字堆")

	b = _battle()
	source = _place(b, Vector2i.ZERO, "铸")
	original = _place(b, Vector2i(1, 0), "防")
	original.fusion.assign(["御"])
	original.gilded = true
	original.pollutions.assign(["scorch"])
	var replacement := CharInstance.new(Database.get_character_by_glyph("防"))
	b.discard.append(replacement)
	b.try_play([Vector2i.ZERO], {"tile": Vector2i(1, 0)})
	_check("solo_recast_preserves_identity", b.board.get_xy(Vector2i(1, 0)) == replacement and b.bag.has(original) and original.glyph_list() == ["防", "御"] and original.gilded and original.pollutions == ["scorch"] and b.discard.has(source) and b.drawn_this_turn == 1 and _unique_circulation(b), "铸从弃字堆换入另一原实体，保留原目标全部属性并排除本次铸")
	b = _battle()
	source = _place(b, Vector2i.ZERO, "铸")
	original = _place(b, Vector2i(1, 0), "防")
	b.try_play([Vector2i.ZERO], {"tile": Vector2i(1, 0)})
	_check("solo_recast_no_replacement", b.board.get_xy(Vector2i(1, 0)) == original and b.discard.has(source) and b.bag.is_empty() and b.drawn_this_turn == 0 and _unique_circulation(b), "字袋和弃字堆仅有本次铸时，不换回自身，不破坏目标")
	b = _battle()
	source = _place(b, Vector2i.ZERO, "铸")
	original = _place(b, Vector2i(1, 0), "防")
	original.pinned = true
	copy = _place(b, Vector2i(0, 1), "防")
	copy.temporary = true
	_check("solo_recast_target_limits", b.solo_target_cells(source, Vector2i.ZERO).is_empty() and b.try_play([Vector2i.ZERO]).ok and b.board.cells.has(original) and b.board.cells.has(copy), "铸不替换固定字或临时字，无目标时仅弃掉")

	b = _battle()
	source = _place(b, Vector2i.ZERO, "炼")
	original = _place(b, Vector2i(1, 0), "防")
	original.pollutions.assign(["scorch"])
	copy = _place(b, Vector2i(0, 1), "击")
	copy.temporary = true
	b.temp_chars.append(copy)
	invalid = b.try_play([Vector2i.ZERO], {"tile": Vector2i(1, 0)})
	_check("solo_refine_preserves_permanent", not invalid.ok and b.board.get_xy(Vector2i.ZERO) == source and b.board.get_xy(Vector2i(1, 0)) == original, "炼不能删除污染过的永久己方实体，无效目标不消费")
	b.try_play([Vector2i.ZERO], {"tile": Vector2i(0, 1)})
	_check("solo_refine_junk_reward", GameState.gold == 101 and b.player.heat == 1 and b.board.get_xy(Vector2i(0, 1)) == null and not b.temp_chars.has(copy) and not b.discard.has(copy) and b.board.cells.has(original), "炼移除临时字，不进入循环，成功后才给1铜钱和1热")
	b = _battle()
	_place(b, Vector2i.ZERO, "炼")
	result = b.try_play([Vector2i.ZERO])
	_check("solo_refine_no_target", result.ok and GameState.gold == 100 and b.player.heat == 0, "炼没有合法杂字时只弃掉，无收益或额外热度")
	var self_junk := CharInstance.new(Database.get_character_by_glyph("热"))
	self_junk.owner = CharInstance.Owner.SELF_GENERATED
	self_junk.add_pollution("scorch")
	enemy = CharInstance.new(Database.get_character_by_glyph("心"))
	enemy.owner = CharInstance.Owner.ENEMY
	var can_refine := BattleState.is_refinable_junk(self_junk) and BattleState.is_refinable_junk(enemy)
	enemy.pinned = true
	_check("solo_refine_owner_limits", can_refine and not BattleState.is_refinable_junk(enemy), "炼接受自生污染与敌方实体，但保护所有固定字")

func _run_solo_balance_two() -> void:
	var b := _battle()
	var e: Combatant = b.enemies[0]
	e.enemy_data.moves[0].kind = EnemyMoveData.Kind.MULTI
	e.enemy_data.moves[0].hits = 3
	e.enemy_data.moves[0].damage = 2
	b.player.block = 6
	_place(b, Vector2i.ZERO, "反")
	b.try_play([Vector2i.ZERO])
	var armed_without_damage: bool = e.hp == 200 and b.ability_value("retaliate_once") == 6
	b._enemy_act(e)
	_check("solo_counter_blocked_multi", armed_without_damage and b.player.hp == 60 and e.hp == 194 and not b.has_ability("retaliate_once"), "反不立即攻击；完全挡住三段攻击后，向攻击者仅反击6伤一次")
	b = _battle()
	e = b.enemies[0]
	e.enemy_data.moves[0].kind = EnemyMoveData.Kind.BLOCK
	e.enemy_data.moves[0].block = 1
	var attacker := _enemy(b)
	_place(b, Vector2i.ZERO, "反")
	b.try_play([Vector2i.ZERO])
	b._enemy_act(e)
	var waited_for_attack: bool = b.has_ability("retaliate_once")
	b._enemy_act(attacker)
	_check("solo_counter_actual_attacker", waited_for_attack and e.hp == 200 and attacker.hp == 194 and b.player.hp == 55, "纯防御行动不触发反，反击实际攻击者而不是第一名敌人")
	b = _battle()
	b.enemies[0].enemy_data.moves[0].kind = EnemyMoveData.Kind.BLOCK
	_place(b, Vector2i.ZERO, "反")
	b.try_play([Vector2i.ZERO])
	var polluted := _place(b, Vector2i(3, 3), "防")
	polluted.add_pollution("scorch")
	b.try_play([Vector2i(3, 3)])
	var after_pollution: bool = b.has_ability("retaliate_once") and b.enemies[0].hp == 200
	b.end_player_turn()
	_check("solo_counter_pollution_expiry", after_pollution and not b.has_ability("retaliate_once") and b.enemies[0].hp == 200, "污染掉血不触发反；本回合敌人未攻击则标记失效")
	b = _battle()
	e = b.enemies[0]
	e.hp = 4
	e.enemy_data.moves[0].kind = EnemyMoveData.Kind.MULTI
	e.enemy_data.moves[0].damage = 2
	e.enemy_data.moves[0].hits = 3
	_place(b, Vector2i.ZERO, "反")
	b.try_play([Vector2i.ZERO])
	b._enemy_act(e)
	_check("solo_counter_after_full_action", b.player.hp == 54 and e.hp == 0, "反等待敌人完整三段攻击结束再击杀，不中途打断剩余攻击")

	b = _battle()
	b.enemies[0].block = 6
	_place(b, Vector2i.ZERO, "破")
	b.try_play([Vector2i.ZERO])
	var removed_six: bool = b.enemies[0].block == 0 and b.enemies[0].hp == 200
	_place(b, Vector2i.ZERO, "破")
	b.try_play([Vector2i.ZERO])
	_check("solo_break_shield", removed_six and b.enemies[0].hp == 198, "破先拆4盾再打2伤，无盾时只打2伤")
	b = _battle()
	_place(b, Vector2i.ZERO, "蓄")
	b.try_play([Vector2i.ZERO])
	var deferred: bool = b.player.energy == 0 and b.ability_value("energy_next_turn") == 2
	b.begin_player_turn(false)
	b.begin_player_turn(false)
	_check("solo_stored_energy_next_turn", deferred and b.player.energy == 2 and not b.has_ability("energy_next_turn"), "蓄只在下回合兑现2储能，之后不再发放")

	b = _battle()
	var source := _place(b, Vector2i.ZERO, "收")
	var rng_before := b.rng.state
	b.try_play([Vector2i.ZERO])
	_check("solo_draw_not_self", b.board.fill_count() == 0 and b.discard.has(source) and b.drawn_this_turn == 0 and b.rng.state == rng_before and _occurrences(b, source) == 1, "只有施放的收可循环时不补回自身，不洗牌，不产生补字收益")
	b = _battle()
	source = _place(b, Vector2i.ZERO, "收")
	var same_glyph := CharInstance.new(Database.get_character_by_glyph("收"))
	b.bag.append(same_glyph)
	b.try_play([Vector2i.ZERO])
	_check("solo_draw_other_same_glyph", b.board.cells.has(same_glyph) and b.discard.has(source) and b.drawn_this_turn == 1 and _unique_circulation(b), "排除按实体身份判断，其他同字形的收仍能正常补入")
	b = _battle()
	source = _place(b, Vector2i.ZERO, "急")
	b.bag.append(CharInstance.new(Database.get_character_by_glyph("击")))
	b.enable_ability("next_double_draw", 1)
	b.try_play([Vector2i.ZERO])
	_check("solo_urgent_excludes_bonus_source", b.board.fill_count() == 1 and b.drawn_this_turn == 1 and b.player.heat == 1 and b.discard.has(source) and not b.has_ability("next_double_draw") and _unique_circulation(b), "急补1字升1热，超速追加补字也不能把本次急重新抽回")
	b = _battle()
	_place(b, Vector2i.ZERO, "击")
	b.try_play([Vector2i.ZERO])
	_place(b, Vector2i.ZERO, "再")
	b.try_play([Vector2i.ZERO])
	var copy := b.board.get_cell(0, 0)
	_place(b, Vector2i(1, 0), "再")
	b.try_play([Vector2i(1, 0)])
	_check("solo_again_no_self_copy", copy != null and copy.glyph() == "击" and copy.temporary and b.board.get_cell(1, 0) == null and not b.board.cells.any(func(inst): return inst != null and inst.glyph() == "再"), "再仍复制普通末字，后续不能复制再本身")

	b = _battle()
	GameState.gold = 0
	_place(b, Vector2i.ZERO, "币")
	b.try_play([Vector2i.ZERO])
	EffectUtil.pay(b, 0)
	var failed_without_spending: bool = not EffectUtil.pay(b, 2) and b.ability_value("payment_discount_once") == 1 and GameState.gold == 0
	var waived: bool = EffectUtil.pay(b, 1) and not b.has_ability("payment_discount_once") and GameState.gold == 0
	_place(b, Vector2i.ZERO, "币")
	b.try_play([Vector2i.ZERO])
	GameState.gold = 3
	var discounted: bool = EffectUtil.pay(b, 2) and GameState.gold == 2
	_place(b, Vector2i.ZERO, "币")
	b.try_play([Vector2i.ZERO])
	b.begin_player_turn(false)
	_check("solo_coin_discount_success_only", failed_without_spending and waived and discounted and not b.has_ability("payment_discount_once"), "币优惠只兑现成功正价支付，可减至0；免费、失败支付保留，跨回合未用优惠清除")
	b = _battle()
	_place(b, Vector2i.ZERO, "利")
	b.try_play([Vector2i.ZERO])
	var no_early_profit: bool = GameState.gold == 100
	_place(b, Vector2i.ZERO, "金")
	b.try_play([Vector2i.ZERO])
	EffectUtil.pay(b, 1)
	_place(b, Vector2i.ZERO, "利")
	b.try_play([Vector2i.ZERO])
	var profited_after_spend: bool = GameState.gold == 102 and b.gold_earned_this_turn == 3
	b.begin_player_turn(false)
	_place(b, Vector2i.ZERO, "利")
	b.try_play([Vector2i.ZERO])
	_check("solo_profit_prior_income", no_early_profit and profited_after_spend and GameState.gold == 102, "利需要本回合此前的真实铜钱收入，之后花掉铜钱不取消资格，跨回合重置")

	b = _battle()
	source = _place(b, Vector2i.ZERO, "投")
	var moved := _place(b, Vector2i(1, 0), "防")
	moved.owner = CharInstance.Owner.ENEMY
	moved.add_pollution("scorch")
	moved.fusion.assign(["御"])
	moved.gilded = true
	var result := b.try_play([Vector2i.ZERO], {"tile": Vector2i(1, 0), "tile2": Vector2i(3, 3)})
	_check("solo_throw_original", result.ok and GameState.gold == 99 and b.board.get_cell(3, 3) == moved and b.board.get_cell(1, 0) == null and b.discard.has(source) and moved.owner == CharInstance.Owner.ENEMY and moved.pollutions == ["scorch"] and moved.fusion == ["御"] and moved.gilded and _unique_circulation(b), "投支付1并远移四邻原实体，保留归属、污染、融合与镀金，不触发目标污染代价")
	b = _battle()
	source = _place(b, Vector2i.ZERO, "投")
	moved = _place(b, Vector2i(1, 0), "防")
	moved.pinned = true
	result = b.try_play([Vector2i.ZERO], {"tile": Vector2i(1, 0), "tile2": Vector2i(3, 3)})
	var pinned_rejected: bool = not result.ok and b.board.get_cell(0, 0) == source and GameState.gold == 100
	moved.pinned = false
	GameState.gold = 0
	result = b.try_play([Vector2i.ZERO], {"tile": Vector2i(1, 0), "tile2": Vector2i(3, 3)})
	_check("solo_throw_invalid_atomic", pinned_rejected and not result.ok and b.board.get_cell(0, 0) == source and b.discard.is_empty() and b.board.get_cell(1, 0) == moved, "投的固定目标和不足支付在消耗字之前拒绝")
	b = _battle()
	for pos in b.board.empty_indices():
		_place(b, pos, "防")
	source = _place(b, Vector2i.ZERO, "投")
	moved = b.board.get_cell(1, 0)
	GameState.gold = 0
	b.enable_ability("payment_discount_once", 1)
	result = b.try_play([Vector2i.ZERO], {"tile": Vector2i(1, 0), "tile2": Vector2i.ZERO})
	_check("solo_throw_discount_full_board", result.ok and b.board.get_cell(0, 0) == moved and b.board.get_cell(1, 0) == null and GameState.gold == 0 and not b.has_ability("payment_discount_once") and _unique_circulation(b), "满盘时允许投到本字将腾出的原格，币减免后可零铜钱发动")
	b = _battle()
	b.player.hp = 40
	b.player.heat = 2
	_place(b, Vector2i.ZERO, "息")
	b.try_play([Vector2i.ZERO])
	var rested: bool = b.player.hp == 41 and b.player.heat == 1
	_place(b, Vector2i.ZERO, "击")
	b.try_play([Vector2i.ZERO])
	_place(b, Vector2i.ZERO, "息")
	b.try_play([Vector2i.ZERO])
	_check("solo_rest_after_damage", rested and b.player.hp == 41 and b.player.heat == 0, "息始终降1热，未造成伤害才回复1生命，进攻后不再回血")
	var h := BattleHarness.new()
	h.battle = _battle()
	_place(h.battle, Vector2i.ZERO, "投")
	moved = _place(h.battle, Vector2i(1, 0), "防")
	GameState.gold = 0
	var no_unpayable_action: bool = not h.legal_actions().any(func(action): return action.get("needs") == "throw")
	GameState.gold = 1
	result = h.apply({"type": "play", "path": [[0, 0]], "needs": "throw"})
	_check("solo_throw_harness", no_unpayable_action and result.ok and GameState.gold == 0 and h.battle.board.cells.has(moved) and _occurrences(h.battle, moved) == 1, "自动化不列无法支付的投，自动选择四邻目标和空格后合法发动")
	b = _battle()
	b.empowered_glyphs["投"] = true
	moved = _place(b, Vector2i(0, 1), "防")
	b.bag.append(CharInstance.new(Database.get_character_by_glyph("御")))
	_word(b, "投放", 0, {"tile": Vector2i(3, 3), "bag_uid": b.bag.back().uid})
	_check("solo_throw_empowered_word", b.board.get_cell(0, 0) == moved and b.board.get_cell(0, 1) == null and b.board.get_cell(3, 3).glyph() == "御" and GameState.gold == 97 and _unique_circulation(b), "强化投在成词后自动选剩余邻字投到空格，额外支付1且主词投放效果保留")

func _run_flow_row_limits() -> void:
	var b := _battle()
	_pad(b)
	_word(b, "流速", 0, {"row": 0})
	_word(b, "流速", 0, {"row": 0})
	_check("flow_self_cast_stacks", b.flow_speed_rows.get(0, 0) == 4 and b.drawn_this_turn == 0 and b.board.fill_count() == 0, "流速施放在生效行时也不补自身，两次施放完整累加四词")

	b = _battle()
	_pad(b)
	_word(b, "流速", 0, {"row": 1})
	_word(b, "流速", 0, {"row": 2})
	_word(b, "防御", 1)
	_check("flow_rows_independent", b.flow_speed_rows.get(1, 0) == 1 and b.flow_speed_rows.get(2, 0) == 2 and b.drawn_this_turn == 2, "不同的行独立叠加和扣除次数")
	b = _battle()
	_pad(b)
	_word(b, "流速", 0, {"row": 1})
	_word(b, "流速", 0, {"row": 2})
	_place(b, Vector2i(0, 1), "防")
	_place(b, Vector2i(0, 2), "御")
	b.try_play([Vector2i(0, 1), Vector2i(0, 2)])
	_check("flow_cross_row_word", b.flow_speed_rows == {1: 1, 2: 1} and b.board.get_cell(0, 1) != null and b.board.get_cell(0, 2) != null and b.drawn_this_turn == 2, "跨两行的一个词，分别在两行原地补字，每行只扣一词")
	b = _battle()
	_pad(b)
	_word(b, "流速", 0, {"row": 1})
	_word(b, "防御", 2)
	_check("flow_other_row_ignored", b.flow_speed_rows.get(1, 0) == 2 and b.drawn_this_turn == 0, "其他行出词不扣次数、不补字")

	b = _battle()
	_pad(b)
	_word(b, "流速", 0, {"row": 1})
	var defense := _place(b, Vector2i(0, 1), "防")
	var guard := _place(b, Vector2i(1, 1), "御")
	defense.pinned = true
	guard.pinned = true
	b.try_play([Vector2i(0, 1), Vector2i(1, 1)])
	_check("flow_fixed_no_vacancy", b.flow_speed_rows.get(1, 0) == 2 and b.drawn_this_turn == 0 and b.board.get_cell(0, 1) == defense and b.board.get_cell(1, 1) == guard, "固定字没有腾出空位时不补字、不扣额度")
	b = _battle()
	_pad(b)
	_word(b, "流速", 0, {"row": 1})
	defense = _place(b, Vector2i(0, 1), "防")
	guard = _place(b, Vector2i(1, 1), "御")
	defense.temporary_uses = 1
	guard.temporary_uses = 1
	b.try_play([Vector2i(0, 1), Vector2i(1, 1)])
	_check("flow_layers_no_vacancy", b.flow_speed_rows.get(1, 0) == 2 and b.drawn_this_turn == 0 and _unique_circulation(b), "消耗复制层但实体仍在原格，不产生虚假补字或扣额")
	b = _battle()
	_pad(b)
	_word(b, "流速", 0, {"row": 1})
	defense = _place(b, Vector2i(0, 1), "防")
	defense.temporary_uses = 1
	_place(b, Vector2i(1, 1), "御")
	b.try_play([Vector2i(0, 1), Vector2i(1, 1)])
	_check("flow_partial_consumption", b.flow_speed_rows.get(1, 0) == 1 and b.drawn_this_turn == 1 and b.board.get_cell(0, 1) == defense and b.board.get_cell(1, 1).glyph() == "放", "一层字加一实体出词时，只补实际消耗的实体格，按一词扣额")

	b = _battle()
	_pad(b)
	_word(b, "流速", 0, {"row": 1})
	b.enable_ability("auto_refill", 1)
	_word(b, "防御", 1)
	_check("flow_occupied_slots_preserved", b.flow_speed_rows.get(1, 0) == 2 and b.drawn_this_turn == 16 and b.board.fill_count() == 16 and _unique_circulation(b), "其他效果已补满原格时，流速不覆盖实体、不重复补字和扣额")
	b = _battle()
	var source := _place(b, Vector2i.ZERO, "流")
	_place(b, Vector2i(1, 0), "速")
	var invalid := b.try_play([Vector2i.ZERO, Vector2i(1, 0)], {"row": b.board.size})
	_check("flow_invalid_row_atomic", not invalid.ok and b.board.get_cell(0, 0) == source and b.discard.is_empty() and b.flow_speed_rows.is_empty(), "越界行在施词消耗之前拒绝")
	b = _battle()
	_word(b, "流速", 0, {"row": 1})
	b.discard.clear()
	_place(b, Vector2i(0, 1), "防").temporary = true
	_place(b, Vector2i(1, 1), "御").temporary = true
	b.try_play([Vector2i(0, 1), Vector2i(1, 1)])
	_check("flow_unavailable_draw_keeps_quota", b.flow_speed_rows.get(1, 0) == 2 and b.drawn_this_turn == 0 and b.board.fill_count() == 0, "字袋和弃字都空时无法补字，不浪费补词额度")

	b = _battle()
	_pad(b)
	_word(b, "流速", 0, {"row": 1})
	var marker := _place(b, Vector2i(3, 1), "回")
	_word(b, "防御力", 1)
	_check("flow_long_word_full_refill", b.drawn_this_turn == 3 and b.flow_speed_rows.get(1, 0) == 1 and b.board.get_cell(0, 1) != null and b.board.get_cell(1, 1) != null and b.board.get_cell(2, 1) != null and b.board.get_cell(3, 1) == marker, "三字词原地补三字，仍然只消耗一词次数，不发生位移")
	b = _battle()
	_pad(b)
	_word(b, "流速", 0, {"row": 1})
	marker = _place(b, Vector2i(3, 1), "回")
	b.enable_ability("next_double_draw", 2)
	_word(b, "防御力", 1)
	_check("flow_double_draw_after_primary", b.drawn_this_turn == 5 and b.player.heat == 2 and b.flow_speed_rows.get(1, 0) == 1 and b.board.get_cell(0, 1) != null and b.board.get_cell(1, 1) != null and b.board.get_cell(2, 1) != null and b.board.get_cell(3, 1) == marker and not b.has_ability("next_double_draw"), "先补齐三枚原格字，再结算超速两枚额外补字，次数只扣一词")

	b = _battle()
	_pad(b)
	b.begin_formation()
	_word(b, "流速", 0, {"row": 1})
	_place(b, Vector2i(0, 1), "左")
	var shared := _place(b, Vector2i(1, 1), "击")
	_place(b, Vector2i(2, 1), "破")
	b.try_play([Vector2i(0, 1), Vector2i(1, 1)], {"row": 0})
	b.try_play([Vector2i(1, 1), Vector2i(2, 1)])
	b.resolve_formation()
	_check("flow_shared_formation_entity", b.drawn_this_turn == 3 and b.flow_speed_rows.is_empty() and b.discard.count(shared) == 1 and b.board.get_cell(0, 1) != null and b.board.get_cell(1, 1) != null and b.board.get_cell(2, 1) != null and _unique_circulation(b), "结阵两词共享击时，只补三个实际消耗格，不再次消耗已补回的实体")
	b = _battle()
	_pad(b)
	_word(b, "流速", 0, {"row": 1})
	_word(b, "停息", 1)
	_check("flow_stopped_phase_skips_refill", b.end_turn_requested and b.drawn_this_turn == 0 and b.flow_speed_rows.get(1, 0) == 2, "立即结束出字的词不再触发流速补字")

func _run_selection_limits() -> void:
	var b := _battle()
	var originals: Array = []
	for g in ["击", "防", "御"]:
		var inst := CharInstance.new(Database.get_character_by_glyph(g))
		b.bag.append(inst)
		originals.append(inst)
	b.manual_draw_pending = 2
	_check("manual_draw_quota", b.place_manual_draw(["击", "防", "御"]) == 2 and b.board.fill_count() == 2 and b.bag.size() == 1, "提交超额选择最多使用待补的两枚额度")
	var stable := b.board.cells.duplicate()
	_check("manual_draw_submit_once", b.place_manual_draw(["御"]) == 0 and b.board.cells == stable and b.bag.size() == 1, "待补额度已结算后，重复提交不再拿走字袋实体")
	_check("manual_draw_conservation", originals.all(func(inst): return _occurrences(b, inst) == 1) and _unique_circulation(b), "超额或重复提交后，原有三枚实体仍各出现一次")

	b = _battle()
	for i in 5:
		b.bag.append(CharInstance.new(Database.get_character_by_glyph("御")))
	b.manual_draw_pending = 3
	_check("manual_draw_random_remainder", b.place_manual_draw([]) == 3 and b.board.fill_count() == 3 and b.drawn_this_turn == 3, "选择剩余随机补时实际补满三枚，并计入真实补字数")
	b = _battle()
	for g in ["防", "御", "回"]:
		b.bag.append(CharInstance.new(Database.get_character_by_glyph(g)))
	b.manual_draw_pending = 3
	_check("manual_draw_unavailable_fallback", b.place_manual_draw(["防", "防", "防"]) == 3 and b.board.fill_count() == 3 and _unique_circulation(b), "字袋只有一枚防时不能复制它，失效选择的剩余额度随机补齐")
	b = _battle()
	for g in ["防", "御"]:
		b.discard.append(CharInstance.new(Database.get_character_by_glyph(g)))
	b.manual_draw_pending = 2
	_check("manual_draw_recycles_discard", b.place_manual_draw(["防", "御"]) == 2 and b.discard.is_empty() and b.bag.is_empty() and _unique_circulation(b), "空字袋先洗回弃字，定向补字仍使用原实体")
	b = _battle()
	for i in b.board.cells.size():
		_place(b, b.board.to_xy(i), "防")
	var untouched := CharInstance.new(Database.get_character_by_glyph("御"))
	b.bag.append(untouched)
	b.manual_draw_pending = 3
	_check("manual_draw_full_board", b.place_manual_draw(["御"]) == 0 and b.manual_draw_pending == 0 and b.bag == [untouched], "满盘结束待补流程，不取走字袋里的牌")
	b = _battle()
	for i in 6:
		b.bag.append(CharInstance.new(Database.get_character_by_glyph("御")))
	b.manual_draw_pending = 2
	b.enable_ability("next_double_draw", 2)
	_check("manual_draw_double_draw", b.place_manual_draw(["御", "御"]) == 4 and b.drawn_this_turn == 4 and b.player.heat == 2 and not b.has_ability("next_double_draw"), "精心补字同样触发超速，额外两枚只结算一次")

	b = _battle()
	var source := _place(b, Vector2i.ZERO, "再")
	_place(b, Vector2i(1, 0), "铸")
	var one := _place(b, Vector2i(2, 1), "防")
	var two := _place(b, Vector2i(2, 2), "御")
	var rng_before := b.rng.state
	var result := b.try_play([Vector2i.ZERO, Vector2i(1, 0)], {"cells": [Vector2i(2, 1), Vector2i(2, 1), Vector2i(2, 2)]})
	_check("recast_duplicate_target_atomic", not result.ok and b.board.get_cell(0, 0) == source and b.board.get_cell(2, 1) == one and b.board.get_cell(2, 2) == two and b.discard.is_empty() and b.rng.state == rng_before, "相同格子重复计入三目标时，在消耗词字和随机数之前拒绝")
	# 即使外部调用错误地在不同格引用同一实体，也不能把它算成两枚。
	b.board.set_cell(3, 1, one)
	result = b.try_play([Vector2i.ZERO, Vector2i(1, 0)], {"cells": [Vector2i(2, 1), Vector2i(3, 1), Vector2i(2, 2)]})
	_check("recast_duplicate_entity_atomic", not result.ok and b.board.get_cell(0, 0) == source and b.board.get_cell(2, 1) == one and b.board.get_cell(3, 1) == one and b.rng.state == rng_before, "三个位置必须对应三个不同实体，按 uid 去重")

func _run_baojinbi() -> void:
	var b := _battle()
	var e: Combatant = b.enemies[0]
	_place(b, Vector2i.ZERO, "爆")
	_place(b, Vector2i(1, 0), "金")
	_place(b, Vector2i(2, 0), "币")
	var hp0: int = e.hp
	var gold0: int = GameState.gold
	var r := b.try_play([Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)])
	_check("baojinbi_word", r.ok and r.word != null and r.word.word == "爆金币", "成词=%s" % (r.word.word if r.word != null else "无"))
	_check("baojinbi_multi_hit", hp0 - e.hp == 5, "5 段 1 伤后掉血=%d，预期 5" % (hp0 - e.hp))
	_check("baojinbi_status", e.status_stacks("gold_burst") == 1, "爆金层=%d，预期 1" % e.status_stacks("gold_burst"))
	_check("baojinbi_gold_per_hit", GameState.gold == gold0 + 5, "本词 5 段铜钱 %d→%d，预期 +5" % [gold0, GameState.gold])
	# 敌方有护甲/格挡时，攻击被吸收也照样给钱
	var gold1: int = GameState.gold
	e.add_block(50)
	var hp1: int = e.hp
	b.deal_damage(e, 1, true)
	_check("baojinbi_through_block", e.hp == hp1 and GameState.gold == gold1 + 1, "50 格挡下受击 HP %d→%d、铜钱 %d→%d（预期 HP 不变、铜钱 +1）" % [hp1, e.hp, gold1, GameState.gold])
	# 铜钱收入已开放上限（gold_cap_per_battle = 0）：反复受击可越过旧上限 18
	var b2 := _battle()
	var e2: Combatant = b2.enemies[0]
	e2.add_status("gold_burst", 1)
	var gold_before: int = GameState.gold
	for i in 25:
		b2.deal_damage(e2, 1, true)
	_check("baojinbi_no_gold_cap", GameState.gold == gold_before + 25, "25 次受击铜钱 %d→%d（旧上限 18 已开放）" % [gold_before, GameState.gold])


func _run_fenhua() -> void:
	# 分化：生长出的临时字必须能与「刚被删掉的那个字」组成合法词
	var b := _battle()
	_place(b, Vector2i(1, 1), "击")
	_place(b, Vector2i(0, 3), "分")
	_place(b, Vector2i(1, 3), "化")
	b.try_play([Vector2i(0, 3), Vector2i(1, 3)], {"tile": Vector2i(1, 1)})
	var grown: Array = []
	for c in b.board.cells:
		if c != null and c.temporary:
			grown.append(c.glyph())
	var all_match: bool = not grown.is_empty()
	for g in grown:
		var ga := str(g)
		if Database.get_word_by_glyphs_string(ga + "击") == null and Database.get_word_by_glyphs_string("击" + ga) == null:
			all_match = false
	_check("fenhua_grown_words", all_match, "删除【击】后生长 %s（应全部能与【击】组词）" % ", ".join(grown))


func _run_logic() -> void:
	var b := _battle()
	var inst := _place(b, Vector2i.ZERO, "洗")
	b.try_play([Vector2i.ZERO])
	_word(b, "回收", 1, {"discard_index": 0})
	_check("recover_unique", _occurrences(b, inst) == 1, "回收后同一 uid 在字袋/弃字堆/盘面的出现次数=%d，预期1" % _occurrences(b, inst))

	b = _battle()
	inst = _place(b, Vector2i.ZERO, "洗")
	b.try_play([Vector2i.ZERO])
	_word(b, "回购", 1, {"place_uid": inst.uid, "tile": Vector2i(3, 3)})
	_check("buyback_unique", _occurrences(b, inst) == 1, "回购后同一 uid 出现次数=%d，预期1" % _occurrences(b, inst))

	b = _battle()
	inst = _place(b, Vector2i.ZERO, "防")
	inst.temporary_uses = 1
	_place(b, Vector2i(1, 0), "御")
	b.try_play([Vector2i.ZERO, Vector2i(1, 0)])
	_word(b, "回放", 1)
	_check("replay_layer_unique", _occurrences(b, inst) == 1, "重合层参与防御后回放，同一实体出现次数=%d，预期1" % _occurrences(b, inst))

	b = _battle()
	_word(b, "复合")
	_word(b, "充放电", 1)
	var kept := 0
	for x in 3:
		if b.board.get_cell(x, 1) != null:
			kept += 1
	_check("compound_layer", kept == 1, "复合后打充放电，保留层数=%d，预期1" % kept)

	b = _battle()
	_word(b, "复合")
	_word(b, "防御", 1)
	_check("compound_shortword", b.has_ability("next_compound"), "复合被两字词防御提前消费，标记仍在=%s，预期true" % b.has_ability("next_compound"))

	b = _battle()
	_word(b, "流利")
	_place(b, Vector2i(0, 1), "防")
	_place(b, Vector2i(1, 2), "御")
	var r := b.try_play([Vector2i(0, 1), Vector2i(1, 2)])
	_check("diagonal", r.ok, "流利后斜连防御，ok=%s，reason=%s" % [r.ok, r.reason])

	b = _battle()
	_word(b, "过火")
	_word(b, "重击", 1)
	_check("overfire_damage", b.enemies[0].hp == 188, "热度2时过火→重击，实际伤害=%d，预期12；标记仍在=%s" % [200 - b.enemies[0].hp, b.has_ability("next_overfire")])

	b = _battle()
	_word(b, "防护")
	var injected := b.inject_enemy_glyphs(2, "rush")
	_check("prevent_interference", injected == 0, "防护后敌方注入2字，实际注入=%d，预期0" % injected)

	b = _battle()
	_pad(b)
	_word(b, "流转")
	_word(b, "防御", 1)
	var drawn := b.drawn_this_turn
	_word(b, "防御", 2)
	_check("flow_repeat", b.drawn_this_turn == drawn, "两种词已触发流转后重复防御，额外补字=%d，预期0" % (b.drawn_this_turn - drawn))

	b = _battle()
	_word(b, "加速")
	_word(b, "流转", 1)
	_word(b, "停火", 2)
	_word(b, "复利", 3)
	b.begin_player_turn(false)
	var leftover: Array = []
	for key in ["accel", "flow", "ceasefire"]:
		if b.has_ability(key):
			leftover.append(key)
	_check("turn_lifetime", leftover.is_empty(), "下回合残留本回合能力=%s，预期空" % str(leftover))

	b = _battle()
	b.end_player_turn()
	var hp_lost := 60 - b.player.hp
	_word(b, "爆冷")
	_check("cold_snap_previous_turn", 200 - b.enemies[0].hp == 4 + hp_lost * 2, "敌方上回合实际扣血=%d，爆冷伤害=%d，预期%d" % [hp_lost, 200 - b.enemies[0].hp, 4 + hp_lost * 2])

	b = _battle()
	b.player.heat = 1
	b.drawn_this_turn = 3
	_word(b, "热流")
	_check("heat_flow_actual_heat", b.enemies[0].hp == 198, "当前热1、补字3时热流伤害=%d，预期2" % (200 - b.enemies[0].hp))

	b = _battle()
	b.player.hp = 40
	_word(b, "热心")
	b.add_heat(5)
	var hp_before := b.player.hp
	_word(b, "清热", 1)
	_check("warm_heart_all_cooling", b.player.hp == hp_before - 2, "热心+清热：降热2后的失血=%d，预期2" % (hp_before - b.player.hp))

	b = _battle()
	b.add_heat(b.player.heat_capacity + 3)
	var scorch_before := b.temp_chars.size()
	b.clear_heat()
	b.add_heat(b.player.heat_capacity + 3)
	_check("overflow_after_clear", b.temp_chars.size() - scorch_before == 3, "溢出3→清零→再次溢出3，新增灼热字=%d，预期3" % (b.temp_chars.size() - scorch_before))

	b = _battle()
	b.add_heat(b.player.heat_capacity)
	_word(b, "蓄冷")
	b.add_heat(3)
	scorch_before = b.temp_chars.size()
	b.add_heat(1)
	_check("overflow_after_shield", b.temp_chars.size() - scorch_before == 1, "蓄冷抵消溢出3后再升温1，新增灼热字=%d，预期1" % (b.temp_chars.size() - scorch_before))

	b = _battle()
	inst = _place(b, Vector2i(2, 2), "防")
	_word(b, "精铸", 0, {"tile": Vector2i(2, 2)})
	var b2 := BattleState.new(b.rules)
	b2.start([inst], [b.enemies[0].enemy_data], 7)
	_check("pin_battle_lifetime", not inst.pinned, "精铸固定字进入下一场战斗，pinned=%s，预期false" % inst.pinned)

	b = _battle()
	inst = _place(b, Vector2i(2, 2), "防")
	_word(b, "精铸", 0, {"tile": Vector2i(2, 2)})
	var chosen := CharInstance.new(Database.get_character_by_glyph("御"))
	b.bag.append(chosen)
	b.reveal_from_bag(1)
	var transform_source := _place(b, Vector2i(0, 1), "转")
	_place(b, Vector2i(1, 1), "化")
	var invalid_transform := b.try_play([Vector2i(0, 1), Vector2i(1, 1)], {"tile": Vector2i(2, 2), "transform_uid": chosen.uid})
	_check("pin_transform", not invalid_transform.ok and b.board.get_xy(Vector2i(2, 2)) == inst and b.board.get_xy(Vector2i(0, 1)) == transform_source and b.pending_reveal.has(chosen), "转化在消耗前拒绝固定目标，保留原字、施词字及揭示字")

	b = _battle()
	_word(b, "加速")
	_word(b, "合击", 1)
	_word(b, "防御", 2)
	var heat_before := b.player.heat
	b.resolve_formation()
	_check("formation_auto_abilities", b.player.heat - heat_before == 2, "结阵结算合击+防御，加速实际升温=%d，预期2" % (b.player.heat - heat_before))

	b = _battle()
	inst = _place(b, Vector2i(2, 2), "防")
	_word(b, "精铸", 0, {"tile": Vector2i(2, 2)})
	_word(b, "合击", 1)
	_place(b, Vector2i(3, 2), "御")
	b.try_play([Vector2i(2, 2), Vector2i(3, 2)])
	b.resolve_formation()
	_check("formation_pin", b.board.get_xy(Vector2i(2, 2)) == inst, "合击结阵消耗精铸固定字，原字仍在=%s，预期true" % (b.board.get_xy(Vector2i(2, 2)) == inst))

	b = _battle()
	_word(b, "强化", 0, {"empower_glyph": "防"})
	_place(b, Vector2i(0, 1), "防")
	b.try_play([Vector2i(0, 1)])
	_check("empower_solo", b.player.block == 8, "强化防后单字防，实际格挡=%d，预期8" % b.player.block)

	b = _battle()
	_enemy(b)
	_word(b, "放火", 0, {"target_index": 0})
	b.add_heat(5)
	_word(b, "放火", 1, {"target_index": 1})
	b.end_player_turn()
	_check("burn_per_enemy", b.enemies[0].hp == 190 and b.enemies[1].hp == 190, "灼烧按「结算时」热度掉血：双方都按热5×2 = 10（实际 %d/%d）" % [200 - b.enemies[0].hp, 200 - b.enemies[1].hp])

	b = _battle()
	b.player.energy = 3
	b.player.add_status("strength", 2)
	_word(b, "放电")
	_check("discharge_segments", b.enemies[0].hp == 182, "储能3、强力2时放电，实际伤害=%d，按3段应18" % (200 - b.enemies[0].hp))

	b = _battle()
	_pad(b)
	_word(b, "超速")
	b.enemies[0].block = 8
	_word(b, "击破", 1)
	_check("double_draw_all_sources", b.drawn_this_turn == 2 and not b.has_ability("next_double_draw"), "超速后击破拆盾补字，实际补字=%d，翻倍标记仍在=%s；预期2/false" % [b.drawn_this_turn, b.has_ability("next_double_draw")])

	b = _battle()
	_word(b, "重击")
	_word(b, "防御", 1)
	_word(b, "连击", 2)
	_check("replay_attack_classification", b.enemies[0].hp == 188 and b.player.block == 10, "重击→防御→连击：总伤害=%d、格挡=%d；预期12/10" % [200 - b.enemies[0].hp, b.player.block])

	b = _battle()
	_word(b, "重复")
	b.begin_player_turn(false)
	var cap_before := b.player.heat_capacity
	_word(b, "重载", 1)
	_check("repeat_immediate_only", b.player.heat_capacity - cap_before == 4 and b.base_draw_penalty == 0 and b.next_draw_penalty == 1, "重复触发重载：热容增加=%d，补字惩罚=%d；按只重演即时效果应4/1（仅下回合）" % [b.player.heat_capacity - cap_before, b.next_draw_penalty])

	b = _battle()
	var gild_card := CharInstance.new(Database.get_character_by_glyph("击"))
	GameState.deck.append(gild_card)
	_word(b, "再投资", 0, {"gild_uid": gild_card.uid})
	GameState.settle_victory_economy()
	_check("gild_immediate_cost", GameState.gold == 97 and gild_card.gilded, "再投资即时支付3铜钱并镀金，无当场返还")

func _new_screen():
	GameState.start_new_run("v03")
	var encounter := MapNodeData.new()
	encounter.enemies.append(Database.get_enemy("ink_spirit"))
	var screen = load("res://src/screens/battle_screen.gd").new()
	screen.setup({"node": encounter, "seed": 7})
	add_child(screen)
	for i in 4:
		await get_tree().process_frame
	await _wait_for_screen_idle(screen)
	screen.battle.board.cells.fill(null)
	screen.battle.bag.clear()
	screen.battle.discard.clear()
	screen.battle.consumed_this_turn.clear()
	return screen

func _run_ui() -> void:
	var screen = await _new_screen()
	_place(screen.battle, Vector2i(0, 0), "再")
	_place(screen.battle, Vector2i(1, 0), "铸")
	_place(screen.battle, Vector2i(2, 1), "防")
	_place(screen.battle, Vector2i(2, 2), "御")
	_place(screen.battle, Vector2i(2, 3), "击")
	screen._board_view.rebuild()
	screen._current_word = Database.get_word_by_glyphs_string("再铸")
	screen._on_commit([Vector2i(0, 0), Vector2i(1, 0)])
	_check("ui_recast_deferred", screen.battle.board.get_cell(0, 0) != null and screen._board_view.pick_mode == "three", "再铸选择前保留词字，并进入独立实体选择模式")
	screen.queue_free()
	for i in 4:
		await get_tree().process_frame

	screen = await _new_screen()
	_place(screen.battle, Vector2i(0, 0), "合")
	_place(screen.battle, Vector2i(1, 0), "流")
	screen.battle.bag.append(CharInstance.new(Database.get_character_by_glyph("防")))
	screen.battle.discard.append(CharInstance.new(Database.get_character_by_glyph("御")))
	screen._board_view.rebuild()
	screen._current_word = Database.get_word_by_glyphs_string("合流")
	screen._on_commit([Vector2i(0, 0), Vector2i(1, 0)])
	_check("ui_merge_deferred", screen.battle.board.get_cell(0, 0) != null and screen.battle.pending_reveal.size() == 1, "合流选择弃字前已消耗词字并归还揭示牌，首字仍在=%s，pending_reveal=%d；应true/1" % [screen.battle.board.get_cell(0, 0) != null, screen.battle.pending_reveal.size()])
	screen.queue_free()
	for i in 4:
		await get_tree().process_frame

func _run_controls() -> void:
	var b := _battle()
	_word(b, "防御")
	_check("control_defense", b.player.block == 10, "正常防御获得10格挡")
	b = _battle()
	_word(b, "充电")
	_check("control_charge", b.player.energy == 3, "正常充电获得3储能")
	b = _battle()
	b.add_heat(5)
	_place(b, Vector2i.ZERO, "冷")
	b.try_play([Vector2i.ZERO])
	_check("control_cool", b.player.heat == 3, "正常冷单字降热2")
	b = _battle()
	_word(b, "金币")
	_check("control_gold", GameState.gold == 103, "正常铜钱获得3铜钱")
	b = _battle()
	_word(b, "重击")
	_word(b, "连击", 1)
	_check("control_replay_attack", b.enemies[0].hp == 188, "没有其他词干扰时连击可正常重演重击")
	b = _battle()
	var inst := _place(b, Vector2i(2, 2), "防")
	_word(b, "精铸", 0, {"tile": Vector2i(2, 2)})
	_place(b, Vector2i(3, 2), "御")
	b.try_play([Vector2i(2, 2), Vector2i(3, 2)])
	_check("control_pin_normal_play", b.board.get_xy(Vector2i(2, 2)) == inst, "普通出词保护精铸固定字")


func _unique_circulation(b: BattleState) -> bool:
	var seen := {}
	for arr in [b.board.cells, b.bag, b.discard, b.pending_reveal, b.reconnect_pending.map(func(item): return item.inst)]:
		for inst in arr:
			if inst == null:
				continue
			if seen.has(inst.uid):
				return false
			seen[inst.uid] = true
	return true

func _reconnect_targets(b: BattleState) -> Array:
	var out: Array = []
	for i in 3:
		out.append(_place(b, Vector2i(2, i + 1), "防御回"[i]))
	return out

func _cast_reconnect(b: BattleState) -> void:
	_word(b, "重连", 0, {"cells": [Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3)]})

func _run_reconnect_return() -> void:
	var b := _battle()
	var originals := _reconnect_targets(b)
	originals[0].fusion.assign(["心", "力"])
	originals[0].gilded = true
	originals[0].temporary_uses = 2
	originals[0].upgrade_level = 1
	originals[0].modifiers.assign(["audit_modifier"])
	originals[0].statuses["audit_status"] = 3
	originals[1].owner = CharInstance.Owner.ENEMY
	originals[1].add_pollution("scorch")
	originals[2].temporary = true
	_cast_reconnect(b)
	b.begin_player_turn(false)
	_check("reconnect_preserve_attributes", originals.all(func(inst): return b.board.cells.has(inst) and _occurrences(b, inst) == 1) and originals[0].fusion == ["心", "力"] and originals[0].gilded and originals[0].temporary_uses == 2 and originals[0].upgrade_level == 1 and originals[0].modifiers == ["audit_modifier"] and originals[0].statuses == {"audit_status": 3} and originals[1].owner == CharInstance.Owner.ENEMY and originals[1].pollutions == ["scorch"] and originals[2].temporary and b.player.hp == 60 and b.drawn_this_turn == 0, "返还原实例并保留全部状态，暂移不触发污染代价，返还不计抽字")

	b = _battle()
	originals = _reconnect_targets(b)
	_cast_reconnect(b)
	var blocker := _place(b, Vector2i(2, 1), "放")
	b.begin_player_turn(false)
	_check("reconnect_occupied_origin", b.board.get_cell(2, 1) == blocker and b.board.get_cell(2, 2) == originals[1] and b.board.get_cell(2, 3) == originals[2] and b.board.cells.has(originals[0]) and b.reconnect_pending.is_empty() and _unique_circulation(b), "先归还所有可用原格，原格被占的实体再找空格，不覆盖占格字")

	b = _battle()
	for pos in b.board.empty_indices():
		_place(b, pos, "放")
	originals = _reconnect_targets(b)
	_cast_reconnect(b)
	for i in 3:
		b.bag.append(CharInstance.new(Database.get_character_by_glyph("防")))
	b.rules.turn_draw = 3
	b.begin_player_turn(true)
	_check("reconnect_before_normal_draw", originals.all(func(inst): return b.board.cells.has(inst)) and b.reconnect_pending.is_empty() and b.board.fill_count() == 16 and b.bag.size() == 1 and b.drawn_this_turn == 2 and _unique_circulation(b), "三原实体先返还，剩余两空格才普通补字，不被开局抽字抢占")

	b = _battle()
	originals = _reconnect_targets(b)
	_cast_reconnect(b)
	for pos in b.board.empty_indices():
		_place(b, pos, "防")
	b.board.get_cell(1, 0).data = Database.get_character_by_glyph("御")
	var full := b.board.cells.duplicate()
	b.begin_player_turn(false)
	_check("reconnect_full_board_wait", b.reconnect_pending.size() == 3 and b.board.cells == full and originals.all(func(inst): return _occurrences(b, inst) == 1) and _unique_circulation(b), "满盘不覆盖、不丢字，三个原实体留在待回区")
	b.try_play([Vector2i.ZERO, Vector2i(1, 0)])
	_check("reconnect_partial_return_on_word", b.reconnect_pending.size() == 1 and b.board.fill_count() == 16 and b.board.cells.has(originals[0]) and b.board.cells.has(originals[1]) and b.drawn_this_turn == 0 and _unique_circulation(b), "下一回合出词腾出两格，先归还两个待回字，余下一字继续等待")
	b.try_play([Vector2i.ZERO])
	_check("reconnect_final_return_on_solo", b.reconnect_pending.is_empty() and b.board.cells.has(originals[2]) and b.board.fill_count() == 16 and _unique_circulation(b), "单字腾位也能接回最后一个待回实体")

	b = _battle()
	_reconnect_targets(b)
	_cast_reconnect(b)
	_pad(b)
	b.draw_to_board(3)
	_check("reconnect_no_early_draw_return", b.reconnect_pending.size() == 3 and b.drawn_this_turn == 3, "施词当回合补字不提前归还")

	b = _battle()
	originals = _reconnect_targets(b)
	_cast_reconnect(b)
	var second := _reconnect_targets(b)
	_cast_reconnect(b)
	b.begin_player_turn(false)
	_check("reconnect_multiple_casts", b.reconnect_pending.is_empty() and (originals + second).all(func(inst): return b.board.cells.has(inst) and _occurrences(b, inst) == 1) and b.board.fill_count() == 6 and _unique_circulation(b), "重复施放分别暂存六枚实体，下一回合全部返回，不互相覆盖")

	b = _battle()
	originals = _reconnect_targets(b)
	var source := _place(b, Vector2i.ZERO, "重")
	_place(b, Vector2i(1, 0), "连")
	var path := [Vector2i.ZERO, Vector2i(1, 0)]
	var cells := [Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3)]
	var result := b.try_play(path, {"cells": [cells[0], cells[0], cells[2]]})
	_check("reconnect_duplicate_rejected", not result.ok and b.board.get_xy(path[0]) == source and b.discard.is_empty() and b.reconnect_pending.is_empty(), "同一目标重复占名额时先拒绝，不消耗词字")
	originals[1].pinned = true
	result = b.try_play(path, {"cells": cells})
	_check("reconnect_pinned_rejected", not result.ok and b.board.get_xy(path[0]) == source and b.reconnect_pending.is_empty(), "固定目标不能移出，拒绝时保留施词字")
	originals[1].pinned = false
	result = b.try_play(path, {"cells": [path[0], cells[1], cells[2]]})
	_check("reconnect_caster_excluded", not result.ok and b.board.get_xy(path[0]) == source and b.reconnect_pending.is_empty(), "施词字不能同时成为移出目标")
	result = b.try_play(path)
	_check("reconnect_missing_targets_rejected", not result.ok and b.board.get_xy(path[0]) == source and b.discard.is_empty(), "未提供三目标时拒绝出词，不直接消耗施词字")

	b = _battle()
	originals = _reconnect_targets(b)
	b.begin_formation()
	_cast_reconnect(b)
	b.board.set_xy(cells[0], null)
	b.board.set_xy(Vector2i(3, 1), originals[0])
	blocker = _place(b, cells[0], "放")
	b.resolve_formation()
	var held_original: bool = b.reconnect_pending.any(func(item): return item.inst == originals[0] and item.pos == Vector2i(3, 1))
	b.begin_player_turn(false)
	_check("reconnect_formation_identity", held_original and b.board.get_cell(3, 1) == originals[0] and b.board.get_xy(cells[0]) == blocker and _unique_circulation(b), "结阵锁定所选实体，目标被搬格后仍暂存原实体，不误取原格的新字")

	b = _battle()
	originals = _reconnect_targets(b)
	b.begin_formation()
	_cast_reconnect(b)
	source = b.board.get_xy(path[0])
	b._consume_path([cells[0]], [originals[0]], {})
	blocker = _place(b, cells[0], "放")
	b.resolve_formation()
	_check("reconnect_stale_formation_rejected", b.reconnect_pending.is_empty() and b.board.get_xy(path[0]) == source and b.board.get_xy(cells[0]) == blocker and b.discard == [originals[0]], "所选实体已离盘时整词拒绝，不消耗施词字或移出补进的新字")

	b = _battle()
	originals = _reconnect_targets(b)
	b.begin_formation()
	_cast_reconnect(b)
	result = b.try_play([cells[0], cells[1]])
	b.resolve_formation()
	var blocked_effect: bool = result.ok and b.player.block == 0 and b.reconnect_pending.size() == 3 and b.discard.size() == 2
	b.begin_player_turn(false)
	result = b.try_play([cells[0], cells[1]])
	_check("reconnect_formation_unavailable_source", blocked_effect and result.ok and b.player.block == 10 and b.reconnect_pending.is_empty() and _unique_circulation(b), "后续结阵词不能使用已移出的字；返还后可以正常组词")

	b = _battle()
	originals = _reconnect_targets(b)
	_cast_reconnect(b)
	b.start(originals, [], 7)
	b.begin_player_turn(false)
	_check("reconnect_new_battle_reset", b.reconnect_pending.is_empty() and b.board.fill_count() == 0 and originals.all(func(inst): return b.bag.has(inst) and _occurrences(b, inst) == 1), "新战斗清理旧待回区，原牌组实体只有一份，不出现幽灵返还")

	var h := BattleHarness.new()
	h.battle = _battle()
	_place(h.battle, Vector2i.ZERO, "重")
	_place(h.battle, Vector2i(1, 0), "连")
	_place(h.battle, cells[0], "防")
	_place(h.battle, cells[1], "御")
	var lacked: bool = not h.legal_actions().any(func(action): return action.get("word") == "重连")
	_place(h.battle, cells[2], "回")
	var available: bool = h.legal_actions().any(func(action): return action.get("word") == "重连" and action.needs == "three")
	result = h.apply({"type": "play", "path": [[0, 0], [1, 0]], "needs": "three"})
	_check("reconnect_harness_auto_targets", lacked and available and result.ok and h.battle.reconnect_pending.size() == 3 and h.battle.discard.size() == 2, "自动化只列可完成的三目标词，并选施词外的三个独立实体")
	h.battle = _battle()
	_reconnect_targets(h.battle)
	_place(h.battle, Vector2i.ZERO, "重")
	_place(h.battle, Vector2i(1, 0), "连")
	result = h.apply({"type": "play", "path": [[0, 0], [1, 0]], "target": {"cells": [[2, 1], [2, 2], [2, 3]]}})
	var observation := h.observe()
	_check("reconnect_harness_explicit_targets", result.ok and observation.reconnect_pending.size() == 3 and observation.reconnect_pending[0].pos == [2, 1] and observation.reconnect_pending[0].card.glyph == "防" and observation.reconnect_pending[0].return_turn == h.battle.turn + 1, "JSON 三目标坐标正确转换，观察接口公开待回字和返还回合")

	b = _battle()
	originals = _reconnect_targets(b)
	b.enable_ability("repeat", 1)
	b.repeat_armed = true
	b.player.add_status("next_extra", 1)
	_cast_reconnect(b)
	_check("reconnect_not_replayed", b.reconnect_pending.size() == 3 and originals.all(func(inst): return _occurrences(b, inst) == 1) and b.discard.size() == 2 and b.log.count("重连：三个原实体暂时移出，下回合优先原格返回（满盘时等待空位）") == 1 and _unique_circulation(b), "超载与重复不重演暂移操作，每个原实体仅进入待回区一次")

	b = _battle()
	originals = _reconnect_targets(b)
	_cast_reconnect(b)
	for pos in b.board.empty_indices():
		_place(b, pos, "放")
	b.begin_player_turn(false)
	b._consume_path([Vector2i.ZERO, Vector2i(1, 0)], [], {})
	var discard_before := b.discard.duplicate()
	var rng_before := b.rng.state
	var drawn := b.draw_to_board(1)
	_check("reconnect_draw_return_priority", drawn == 0 and b.drawn_this_turn == 0 and b.reconnect_pending.size() == 1 and b.board.fill_count() == 16 and b.board.cells.has(originals[0]) and b.board.cells.has(originals[1]) and b.bag.is_empty() and b.discard == discard_before and b.rng.state == rng_before and _unique_circulation(b), "普通补字前先返还待回字，空位被占满后不抽字、不洗牌、不消耗随机序列")

func _run_boundaries() -> void:
	var b := _battle()
	var original := _place(b, Vector2i.ZERO, "洗")
	b.try_play([Vector2i.ZERO])
	b.draw_one_to(Vector2i(3, 3))
	_word(b, "回购", 1, {"discard_uid": original.uid})
	_check("recover_stale_rejected", GameState.gold == 100 and _occurrences(b, original) == 1, "已抽回盘面的历史消耗字不能回购，也不能扣铜钱")

	b = _battle()
	original = _place(b, Vector2i.ZERO, "洗")
	b.try_play([Vector2i.ZERO])
	_word(b, "回收", 1, {"discard_uid": original.uid})
	b.draw_one_to(Vector2i(3, 3))
	_check("recover_draw_roundtrip", b.board.get_xy(Vector2i(3, 3)) == original and _unique_circulation(b), "回收后再抽取，实体身份唯一")

	b = _battle()
	_word(b, "防御")
	b.draw_one_to(Vector2i(3, 3))
	_word(b, "回放", 1)
	_check("replay_already_drawn", _unique_circulation(b), "原牌已抽回盘面时回放不能重复引用")

	b = _battle()
	var pinned := _place(b, Vector2i(2, 2), "防")
	var other := _place(b, Vector2i(3, 2), "御")
	_place(b, Vector2i(3, 3), "放")
	_word(b, "精铸", 0, {"tile": Vector2i(2, 2)})
	b.swap_cells(Vector2i(2, 2), Vector2i(3, 2))
	_check("pinned_swap", b.board.get_xy(Vector2i(2, 2)) == pinned and b.board.get_xy(Vector2i(3, 2)) == other, "交换不能移动固定字")
	_word(b, "分化", 1, {"tile": Vector2i(2, 2)})
	_check("pinned_split", b.board.get_xy(Vector2i(2, 2)) == pinned, "分化不能删除固定字")
	_place(b, Vector2i(0, 1), "再")
	_place(b, Vector2i(1, 1), "铸")
	var recast_result := b.try_play([Vector2i(0, 1), Vector2i(1, 1)], {"cells": [Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 3)]})
	_check("pinned_recast_three", not recast_result.ok and b.board.get_xy(Vector2i(0, 1)) != null and b.board.get_xy(Vector2i(2, 2)) == pinned and b.board.get_xy(Vector2i(3, 2)) == other, "再铸包含固定字时在消耗施词字前原子拒绝")
	_word(b, "重铸")
	_check("pinned_recast_board", b.board.get_xy(Vector2i(2, 2)) == pinned, "重铸保留固定字原位")

	b = _battle()
	_pad(b)
	_word(b, "复合")
	b.player.energy = 3
	_place(b, Vector2i(0, 1), "充")
	var chosen := _place(b, Vector2i(1, 1), "放")
	_place(b, Vector2i(2, 1), "电")
	b.try_play([Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)], {"compound_uid": chosen.uid})
	var copy := b.board.get_xy(Vector2i(1, 1))
	_check("compound_before_draw", copy != null and copy.temporary and copy.glyph() == "放" and copy.uid != chosen.uid, "复合保留选中的字，词效补字不能抢占它原格")

	b = _battle()
	_word(b, "流利")
	_place(b, Vector2i(0, 1), "防")
	_place(b, Vector2i(1, 2), "御")
	_place(b, Vector2i(2, 3), "力")
	var result := b.try_play([Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3)])
	_check("free_word_multiple_steps", result.ok and not b.has_ability("next_free_word"), "流利允许多次非相邻选择，成功后消耗机会")
	b.try_play([Vector2i(0, 1), Vector2i(1, 2)])
	_place(b, Vector2i(0, 1), "防")
	_place(b, Vector2i(1, 2), "御")
	result = b.try_play([Vector2i(0, 1), Vector2i(1, 2)])
	_check("diagonal_consumed", not result.ok and b.board.diagonal_steps_allowed == 0, "有效词消费流利，下一条路径恢复四邻接")
	_place(b, Vector2i(1, 1), "御")
	result = b.try_play([Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 1)])
	_check("path_no_reuse", not result.ok, "同一路径不能重复使用一个实体格")

	b = _battle()
	_word(b, "停火")
	b.end_player_turn()
	var hp_before := b.player.hp
	b.end_player_turn()
	_check("ceasefire_expires", b.player.hp == hp_before - 5, "停火只能免疫发动回合，下一回合正常受伤")

	b = _battle()
	b.player.hp = 40
	_word(b, "热心")
	b.add_heat(5)
	b.bag.append(CharInstance.new(Database.get_character_by_glyph("资")))
	_word(b, "炼化", 1, {"remove_glyph": "资"})
	_check("warm_heart_refine", b.player.hp == 42 and b.player.heat == 2, "炼化降热3，热心同步扣3血")
	_word(b, "蓄热", 2)
	hp_before = b.player.hp
	b.end_player_turn()
	_check("warm_heart_turn_end", b.player.hp == hp_before - 7 and b.player.energy == 2, "蓄热降热2扣2血，再承受敌人5伤")

	b = _battle()
	_word(b, "放火")
	b.add_heat(4)
	_word(b, "放火", 1)
	b.end_player_turn()
	b.end_player_turn()
	_check("burn_stacks", b.enemies[0].hp == 184 and b.enemies[0].status_stacks("burn") == 2, "两次放火叠成 4 层：当回合按热度4烧两次、余 2 层（实际 %d）" % (200 - b.enemies[0].hp))

	b = _battle()
	_enemy(b)
	b.enemies[0].hp = 4
	b.player.energy = 3
	_word(b, "放电")
	_check("discharge_retarget", b.enemies[0].hp == 0 and b.enemies[1].hp == 192, "放电击杀目标后，剩余两段攻击另一存活敌人")
	b = _battle()
	b.player.energy = 3
	b.player.add_status("next_bonus", 2)
	_word(b, "放电")
	_check("discharge_next_bonus", b.enemies[0].hp == 182 and b.player.status_stacks("next_bonus") == 0, "热力共用的next_bonus按放电每段+2，整次攻击只消费一次")

	b = _battle()
	_pad(b)
	for i in 16:
		_place(b, b.board.to_xy(i), "放")
	_word(b, "超速")
	_word(b, "回流", 1)
	_check("double_draw_actual_heat", b.board.fill_count() == 16 and b.drawn_this_turn == 4 and b.player.heat == 0, "盘面仅四空格时超速额外落字为0，不虚增热度")
	b = _battle()
	_pad(b)
	_word(b, "超速")
	_place(b, Vector2i(0, 1), "回")
	b.try_play([Vector2i(0, 1)])
	_check("double_draw_fixed_cell", b.drawn_this_turn == 2 and b.player.heat == 1, "回的原格补字同样触发超速和真实补字统计")

	b = _battle()
	var gild_next := CharInstance.new(Database.get_character_by_glyph("击"))
	GameState.deck.append(gild_next)
	_word(b, "再投资", 0, {"gild_uid": gild_next.uid})
	var second := BattleState.new(b.rules)
	second.start(GameState.make_battle_deck(), [b.enemies[0].enemy_data], 7)
	GameState.settle_victory_economy()
	GameState.settle_victory_economy()
	_check("gild_cross_battle", gild_next.gilded and GameState.gold == 97, "永久镀金跨战保留，胜利重复结算不生铜钱")

	b = _battle()
	_pad(b)
	_word(b, "防御")
	_word(b, "回击", 1)
	_check("non_attack_prerequisite", b.drawn_this_turn == 0, "防御不满足回击的此前即时攻击条件")

	b = _battle()
	_word(b, "合击")
	_word(b, "超载", 1)
	_word(b, "击破", 2)
	b.resolve_formation()
	_check("formation_next_extra", b.enemies[0].hp == 184 and b.player.status_stacks("next_extra") == 0, "结阵中的超载强化后续击破")
	_check("formation_last_snapshot", b.last_played_word.word == "击破" and b.last_played_consumed.size() == 2, "结阵也更新最近出词快照")

	b = _battle()
	_word(b, "重复")
	b.begin_player_turn(false)
	b.begin_formation()
	_word(b, "防御", 1)
	b.resolve_formation()
	_check("formation_repeat", b.player.block == 20 and not b.repeat_armed, "结阵复用重复的即时重演流程")

	b = _battle()
	_pad(b)
	b.enable_ability("auto_refill", 1)
	b.begin_formation()
	_place(b, Vector2i(0, 1), "左")
	var shared := _place(b, Vector2i(1, 1), "击")
	_place(b, Vector2i(2, 1), "破")
	b.try_play([Vector2i(0, 1), Vector2i(1, 1)], {"row": 0})
	b.try_play([Vector2i(1, 1), Vector2i(2, 1)])
	b.resolve_formation()
	_check("formation_refill_identity", b.board.get_xy(Vector2i(1, 1)) != null and b.board.get_xy(Vector2i(1, 1)).glyph() == "放" and b.discard.count(shared) == 1 and _unique_circulation(b), "共享击只消费一次，后续词不消耗已补回原格的新字")

	b = _battle()
	b.begin_formation()
	_word(b, "心力")
	_place(b, Vector2i(0, 1), "心")
	b.try_play([Vector2i(0, 1)])
	b.resolve_formation()
	_check("formation_heart_power", b.player.heart_power == 2, "结阵成词和单字都触发心力")

	b = _battle()
	b.begin_formation()
	var polluted := _place(b, Vector2i.ZERO, "击")
	polluted.temporary_uses = 1
	polluted.add_pollution("rush")
	_place(b, Vector2i(1, 0), "破")
	b.try_play([Vector2i.ZERO, Vector2i(1, 0)])
	hp_before = b.player.hp
	b.resolve_formation()
	_check("formation_layer_pollution", b.player.hp == hp_before - 2 and b.board.get_xy(Vector2i.ZERO) == polluted, "结阵使用临时层也结算污染，保留实体原格")

	b = _battle()
	_word(b, "加速")
	b.add_heat(5)
	_word(b, "停息", 1)
	_check("stop_no_post_acceleration", b.player.heat == 0 and b.end_turn_requested, "停息结束出字，不再被后置加速重新升温")

	var h := RunHarness.new()
	GameState.start_new_run("v03")
	GameState.gold = 100
	var encounter := MapNodeData.new()
	encounter.enemies.append(Database.get_enemy("ink_spirit"))
	h.node = encounter
	h._start_battle(encounter)
	var run_card: CharInstance = GameState.deck[0]
	_word(h.battle_h.battle, "再投资", 0, {"gild_uid": run_card.uid})
	h.battle_h.battle.enemies[0].hp = 0
	h._end_battle()
	_check("run_gild_current", GameState.gold == 97 and run_card.gilded, "整局接口镀金即时扣费，无投资返还")
	h._start_battle(encounter)
	h.battle_h.battle.enemies[0].hp = 0
	h._end_battle()
	_check("run_gild_persists", GameState.gold == 97 and run_card.gilded, "整局接口下战保留镀金，不产生自动收益")

	b = _battle()
	var pool := ["放", "防", "盾", "冷"]
	for i in 30:
		b.bag.append(CharInstance.new(Database.get_character_by_glyph(pool[i % pool.size()])))
	var conserved := true
	for step in 100:
		if b.board.fill_count() == 0:
			b.draw_to_board(6)
		var pos := Vector2i(-1, -1)
		for i in b.board.cells.size():
			if b.board.cells[i] != null:
				pos = b.board.to_xy(i)
				break
		b.try_play([pos])
		if step % 10 == 9:
			b.end_player_turn()
		conserved = conserved and _unique_circulation(b) and b.board.fill_count() + b.bag.size() + b.discard.size() == 30
	_check("circulation_100_steps", conserved, "100次真实抽取、单字消耗、洗牌、回合切换保持30实体守恒")

func _choice(screen, title: String) -> ChoiceOverlay:
	for child in screen.get_children():
		if child is ChoiceOverlay and str(child.cfg.get("title", "")).begins_with(title):
			return child
	return null

func _dispose_screen(screen) -> void:
	screen.queue_free()
	for i in 4:
		await get_tree().process_frame

func _wait_for_screen_idle(screen) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while screen._busy and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

func _run_ui_word_balance() -> void:
	var saved_motion := Settings.reduced_motion
	Settings.reduced_motion = true
	for text in ["投放", "回购"]:
		var screen = await _new_screen()
		GameState.gold = 10
		_place(screen.battle, Vector2i.ZERO, text[0])
		_place(screen.battle, Vector2i(1, 0), text[1])
		var original := CharInstance.new(Database.get_character_by_glyph("电"))
		original.gilded = true
		if text == "投放":
			screen.battle.bag.append(original)
		else:
			screen.battle.discard.append(original)
		var rng_before: int = screen.battle.rng.state
		screen._board_view.rebuild()
		screen._board_view._on_tile_pressed(Vector2i.ZERO)
		screen._board_view._on_tile_pressed(Vector2i(1, 0))
		screen._on_primary()
		var picker := _choice(screen, text + "：")
		_check("ui_transfer_preview_" + text, picker != null and GameState.gold == 10 and screen.battle.rng.state == rng_before and screen.battle.board.fill_count() == 2, "选字预览不消费原字、铜钱或随机数")
		assert(picker != null)
		picker._on_choose(1)
		_check("ui_transfer_cancel_" + text, GameState.gold == 10 and screen.battle.rng.state == rng_before and (screen.battle.bag.has(original) or screen.battle.discard.has(original)) and screen._modal_count == 0, "取消选字保持原实体和资源")
		screen._on_primary()
		picker = _choice(screen, text + "：")
		assert(picker != null)
		picker._on_choose(0)
		screen._board_view._on_tile_pressed(Vector2i(3, 3))
		_check("ui_transfer_ready_" + text, not screen._ready_action.is_empty() and screen.battle.board.get_cell(3, 3) == null and GameState.gold == 10, "选完落点仍等待确认")
		_check("ui_transfer_selected_preview_" + text, "已选己方原字【电】" in screen._bubble._effect_text and "需付2" in screen._bubble._effect_text, "确认前预览显示实际选中实体及当前费用")
		screen._on_primary()
		await _wait_for_screen_idle(screen)
		_check("ui_transfer_commit_" + text, screen.battle.board.get_cell(3, 3) == original and original.gilded and original.temporary_uses == 1 and GameState.gold == 8 and _occurrences(screen.battle, original) == 1 and not screen._busy, "确认才支付2，保留原实体属性并加一次使用")
		await _dispose_screen(screen)
	var screen = await _new_screen()
	_place(screen.battle, Vector2i.ZERO, "分")
	_place(screen.battle, Vector2i(1, 0), "流")
	var junk := _place(screen.battle, Vector2i(3, 3), "灰")
	junk.owner = CharInstance.Owner.ENEMY
	var own := _place(screen.battle, Vector2i(2, 2), "电")
	own.add_pollution("scorch")
	screen._board_view.rebuild()
	screen._board_view._on_tile_pressed(Vector2i.ZERO)
	screen._board_view._on_tile_pressed(Vector2i(1, 0))
	screen._on_primary()
	var restricted: bool = screen._collect_junk and not screen._board_view._valid_pick(Vector2i(2, 2)) and screen._board_view._valid_pick(Vector2i(3, 3))
	screen._board_view._on_tile_pressed(Vector2i(3, 3))
	screen._board_view._on_tile_pressed(Vector2i(3, 3))
	screen._board_view._on_tile_pressed(Vector2i(3, 3))
	screen._on_primary()
	await _wait_for_screen_idle(screen)
	_check("ui_divert_junk_only", restricted and screen.battle.board.get_cell(3, 3) == null and screen.battle.board.get_cell(2, 2) == own and own.has_pollution("scorch") and not screen._busy, "分流可点选取消再选择，只移除杂字并保留己方实体及标签")
	await _dispose_screen(screen)
	Settings.reduced_motion = saved_motion

func _run_ui_dynamic_preview() -> void:
	var saved_motion := Settings.reduced_motion
	Settings.reduced_motion = true
	var screen = await _new_screen()
	_place(screen.battle, Vector2i(3, 3), "再")
	_place(screen.battle, Vector2i.ZERO, "防")
	_place(screen.battle, Vector2i(1, 0), "御")
	screen._board_view.rebuild()
	screen._board_view._on_tile_pressed(Vector2i(3, 3))
	_check("ui_again_empty_history", "尚未打出任何字" in screen._bubble._effect_text, "实际HUD无历史时解释再无法复制")
	screen._board_view.clear_selection()
	screen._board_view._on_tile_pressed(Vector2i.ZERO)
	screen._board_view._on_tile_pressed(Vector2i(1, 0))
	screen._on_primary()
	await _wait_for_screen_idle(screen)
	screen._board_view._on_tile_pressed(Vector2i(3, 3))
	var before := _preview_signature(screen.battle)
	_check("ui_again_current_last_glyph", "上一手【防御】" in screen._bubble._effect_text and "末字【御】" in screen._bubble._effect_text and "临时【御】" in screen._bubble._effect_text, "成功出词后，HUD再预览立即显示真实历史和将复制的末字")
	screen._on_selection_changed([Vector2i(3, 3)], ["再"], null)
	_check("ui_again_preview_read_only", _preview_signature(screen.battle) == before, "刷新实际HUD不提前创建临时字或改写历史")
	screen._on_primary()
	await _wait_for_screen_idle(screen)
	var copy: CharInstance = screen.battle.board.get_cell(3, 3)
	_check("ui_again_matches_execution", copy != null and copy.temporary and copy.glyph() == "御", "再的实际复制和发动前预览一致")
	_place(screen.battle, Vector2i(3, 2), "再")
	screen._board_view.rebuild()
	screen._board_view._on_tile_pressed(Vector2i(3, 2))
	_check("ui_again_blocks_self_preview", "上一手【再】" in screen._bubble._effect_text and "不能复制自身" in screen._bubble._effect_text, "再结算后下一次再预览不会保留过期御字")
	await _dispose_screen(screen)
	screen = await _new_screen()
	_place(screen.battle, Vector2i.ZERO, "电")
	_place(screen.battle, Vector2i(1, 0), "热")
	screen.battle.player.energy = 2
	screen._board_view.rebuild()
	screen._board_view._on_tile_pressed(Vector2i.ZERO)
	screen._board_view._on_tile_pressed(Vector2i(1, 0))
	var initial: bool = "6临时格挡" in screen._bubble._effect_text
	screen.battle.player.energy = 4
	screen._on_enemy_clicked(0)
	_check("ui_dynamic_preview_refresh", initial and "12临时格挡" in screen._bubble._effect_text and screen.battle.player.energy == 4, "同一已选词刷新时使用最新资源，不缓存旧数值")
	await _dispose_screen(screen)
	Settings.reduced_motion = saved_motion

func _manual_option(overlay: ChoiceOverlay, glyph: String) -> int:
	if overlay == null:
		return -1
	for i in overlay.cfg.options.size():
		if str(overlay.cfg.options[i].text).begins_with("【%s】" % glyph):
			return i
	return -1

func _run_ui_word_completion() -> void:
	var saved_motion := Settings.reduced_motion
	Settings.reduced_motion = true
	for text in ["流速", "重回", "重连", "流连", "回心", "回能", "防反", "回复"]:
		var screen = await _new_screen()
		var prior: CharInstance = null
		if text == "重回":
			prior = _place(screen.battle, Vector2i(3, 3), "防")
			screen.battle.try_play([Vector2i(3, 3)])
		if text == "回心":
			screen.battle.player.hp = 30
			for g in ["防", "御", "放"]:
				screen.battle.bag.append(CharInstance.new(Database.get_character_by_glyph(g)))
		if text == "重连":
			for y in range(1, 4):
				_place(screen.battle, Vector2i(2, y), "防")
		_place(screen.battle, Vector2i.ZERO, text[0])
		_place(screen.battle, Vector2i(1, 0), text[1])
		screen._board_view.rebuild()
		screen._board_view._on_tile_pressed(Vector2i.ZERO)
		screen._board_view._on_tile_pressed(Vector2i(1, 0))
		_check("ui_recognize_" + text, screen._current_word != null and screen._current_word.word == text and not screen._confirm_btn.disabled, "真实选字可以识别本词，并允许点出字")
		screen._on_primary()
		if text == "流速":
			screen._board_view._on_tile_pressed(Vector2i(0, 1))
			screen._on_primary()
		if text == "重连":
			for y in range(1, 4):
				screen._board_view._on_tile_pressed(Vector2i(2, y))
			screen._on_primary()
		await _wait_for_screen_idle(screen)
		var effected := false
		match text:
			"流速": effected = screen.battle.flow_speed_rows.get(1, 0) == 2
			"重回": effected = screen.battle.bag.has(prior) and not screen.battle.discard.has(prior)
			"重连": effected = screen.battle.reconnect_pending.size() == 3
			"流连": effected = screen.battle.ability_value("linger_chance") == 1
			"回心": effected = screen.battle.player.hp == 31 and screen._player_hp.value == 31 and screen.battle.board.fill_count() == 3
			"回能": effected = screen.battle.player.energy == 2 and screen.battle.ability_value("energy_regen") == 2
			"防反": effected = screen.battle.player.block == 6 and screen.battle.ability_value("counter") == 1
			"回复": effected = screen.battle.player.status_stacks("regen") == 3
		_check("ui_effect_" + text, effected and not screen._busy and screen._modal_count == 0 and screen._board_view._interactable and screen._board_view.path.is_empty(), "从主按钮完成实际词效，HUD 和盘面更新并恢复输入")
		await _dispose_screen(screen)
	Settings.reduced_motion = saved_motion

func _run_ui_solo_balance() -> void:
	var saved_motion := Settings.reduced_motion
	Settings.reduced_motion = true
	var screen = await _new_screen()
	screen.battle.player.energy = 2
	var source := _place(screen.battle, Vector2i.ZERO, "放")
	screen._board_view.rebuild()
	screen._board_view._on_tile_pressed(Vector2i.ZERO)
	screen._on_primary()
	var picker := _choice(screen, "放：")
	_check("ui_solo_release_choose_before_spend", picker != null and screen.battle.board.get_cell(0, 0) == source and screen.battle.player.energy == 2, "放选择攻击方式前保留原字和储能")
	assert(picker != null)
	picker._on_choose(0)
	await _wait_for_screen_idle(screen)
	_check("ui_solo_release_energy_attack", screen.battle.player.energy == 1 and screen.battle.discard.has(source) and not screen._busy and screen._modal_count == 0 and screen._board_view._interactable, "放选择释放后消耗一次储能和原字，完成后恢复输入")
	source = _place(screen.battle, Vector2i.ZERO, "放")
	screen._board_view.rebuild()
	screen._board_view._on_tile_pressed(Vector2i.ZERO)
	screen._on_primary()
	picker = _choice(screen, "放：")
	assert(picker != null)
	picker._on_choose(2)
	_check("ui_solo_release_cancel", screen.battle.board.get_cell(0, 0) == source and screen.battle.player.energy == 1 and not screen._solo_release_picker_active and screen._modal_count == 0, "取消放的选择不消耗原字与储能")
	await _dispose_screen(screen)
	screen = await _new_screen()
	_place(screen.battle, Vector2i.ZERO, "洗")
	var adjacent := _place(screen.battle, Vector2i(1, 0), "防")
	adjacent.pollutions.assign(["scorch", "rush"])
	_place(screen.battle, Vector2i(3, 3), "御").add_pollution("scorch")
	screen._board_view.rebuild()
	screen._board_view._on_tile_pressed(Vector2i.ZERO)
	screen._on_primary()
	var restricted: bool = screen._board_view.pick_mode == "any" and screen._board_view._valid_pick(Vector2i(1, 0)) and not screen._board_view._valid_pick(Vector2i(3, 3))
	screen._board_view._on_tile_pressed(Vector2i(1, 0))
	screen._on_primary()
	await _wait_for_screen_idle(screen)
	_check("ui_solo_adjacent_target", restricted and adjacent.pollutions.is_empty() and screen.battle.board.get_cell(1, 0) == adjacent and screen.battle.board.get_cell(3, 3).pollutions == ["scorch"] and not screen._busy, "洗仅高亮有效四邻目标，实际确认只净化选定实体")
	await _dispose_screen(screen)
	Settings.reduced_motion = saved_motion

func _run_ui_solo_balance_four() -> void:
	var saved_motion := Settings.reduced_motion
	Settings.reduced_motion = true
	var screen = await _new_screen()
	_place(screen.battle, Vector2i.ZERO, "超")
	screen._board_view.rebuild()
	screen._board_view._on_tile_pressed(Vector2i.ZERO)
	screen._on_primary()
	await _wait_for_screen_idle(screen)
	_place(screen.battle, Vector2i.ZERO, "防")
	_place(screen.battle, Vector2i(2, 0), "御")
	screen._board_view.rebuild()
	screen._board_view._on_tile_pressed(Vector2i.ZERO)
	screen._board_view._extend_path(Vector2i(1, 0))
	screen._board_view._extend_path(Vector2i(2, 0))
	_check("ui_solo_gap_drag_path", screen._board_view.path == [Vector2i.ZERO, Vector2i(2, 0)] and screen._current_word != null and screen._current_word.word == "防御" and "超：" in screen._bubble._context_text, "拖动可以经过空格连接两枚实体，并正确预览词与超提示")
	screen._on_primary()
	await _wait_for_screen_idle(screen)
	_check("ui_solo_gap_commit", screen.battle.player.block == 10 and not screen.battle.has_ability("next_gap") and not screen._busy and screen._board_view._interactable, "跨空格词通过界面正常执行，并消耗一次机会")
	await _dispose_screen(screen)
	for glyph in ["精", "购"]:
		screen = await _new_screen()
		var source := _place(screen.battle, Vector2i.ZERO, glyph)
		var first := CharInstance.new(Database.get_character_by_glyph("防"))
		var second := CharInstance.new(Database.get_character_by_glyph("防"))
		first.gilded = true
		screen.battle.bag.append_array([first, second])
		GameState.gold = 10
		var state_before: int = screen.battle.rng.state
		screen._board_view.rebuild()
		screen._board_view._on_tile_pressed(Vector2i.ZERO)
		screen._on_primary()
		var picker := _choice(screen, glyph + "：")
		_check("ui_bag_preview_" + glyph, picker != null and screen.battle.bag == [first, second] and screen.battle.board.cells.has(source) and GameState.gold == 10 and screen.battle.rng.state == state_before, "选字弹窗按实体列出同字形候选，确认前不取牌或扣费")
		assert(picker != null)
		picker._on_choose(2)
		_check("ui_bag_cancel_" + glyph, screen.battle.bag == [first, second] and screen.battle.board.cells.has(source) and GameState.gold == 10 and not screen._solo_bag_picker_active and screen._modal_count == 0, "取消选字保留棋盘、字袋和铜钱，并恢复输入")
		screen._on_primary()
		picker = _choice(screen, glyph + "：")
		assert(picker != null)
		picker._on_choose(1)
		await _wait_for_screen_idle(screen)
		_check("ui_bag_execute_" + glyph, screen.battle.board.get_xy(Vector2i.ZERO) == first and first.gilded and screen.battle.bag == [second] and GameState.gold == (8 if glyph == "购" else 10) and screen.battle.drawn_this_turn == 1 and not screen._busy and screen._modal_count == 0, "确认后补入指定原实体，购支付2铜钱，精不支付")
		await _dispose_screen(screen)
	Settings.reduced_motion = saved_motion

func _run_ui_solo_balance_three() -> void:
	var saved_motion := Settings.reduced_motion
	Settings.reduced_motion = true
	for glyph in ["分", "铸", "炼"]:
		var screen = await _new_screen()
		var source := _place(screen.battle, Vector2i.ZERO, glyph)
		var adjacent := _place(screen.battle, Vector2i(1, 0), "防")
		if glyph == "炼":
			adjacent.temporary = true
		var forbidden := _place(screen.battle, Vector2i(0, 1), "御")
		forbidden.pinned = true
		forbidden.owner = CharInstance.Owner.ENEMY
		var replacement := CharInstance.new(Database.get_character_by_glyph("心"))
		screen.battle.bag.append(replacement)
		screen._board_view.rebuild()
		screen._board_view._on_tile_pressed(Vector2i.ZERO)
		screen._on_primary()
		_check("ui_third_batch_picker_" + glyph, screen._board_view.pick_mode == "any" and screen._board_view._valid_pick(Vector2i(1, 0)) and not screen._board_view._valid_pick(Vector2i(0, 1)) and screen.battle.board.get_xy(Vector2i.ZERO) == source, "先选择合法四邻目标，选择前保留施放字")
		screen._board_view._on_tile_pressed(Vector2i(1, 0))
		screen._on_primary()
		await _wait_for_screen_idle(screen)
		var completed: bool = screen.battle.discard.has(source) and not screen._busy and screen._board_view._interactable and screen._board_view.pick_mode.is_empty()
		if glyph == "分":
			var copy: CharInstance = screen.battle.board.get_xy(Vector2i.ZERO)
			completed = completed and copy != null and copy.word_only and screen.battle.board.get_xy(Vector2i(1, 0)) == adjacent
		elif glyph == "铸":
			completed = completed and screen.battle.board.get_xy(Vector2i(1, 0)) == replacement and screen.battle.bag.has(adjacent)
		else:
			completed = completed and screen.battle.board.get_xy(Vector2i(1, 0)) == null and screen.battle.player.heat == 1
		_check("ui_third_batch_execute_" + glyph, completed, "确认后执行选定目标效果，并恢复输入")
		await _dispose_screen(screen)
	var screen = await _new_screen()
	var copy := _place(screen.battle, Vector2i.ZERO, "放")
	copy.temporary = true
	copy.word_only = true
	screen.battle.player.energy = 2
	screen._board_view.rebuild()
	screen._board_view._on_tile_pressed(Vector2i.ZERO)
	var preview_restricted: bool = "仅供组词" in screen._bubble._effect_text and screen._board_view.tiles[0].art_badges.has("词")
	screen._on_primary()
	await _wait_for_screen_idle(screen)
	_check("ui_word_copy_solo_discard", preview_restricted and screen.battle.board.get_xy(Vector2i.ZERO) == null and screen.battle.player.energy == 2 and not screen._solo_release_picker_active and screen._modal_count == 0, "组词用复制显示词角标；单独打出不弹储能释放选项")
	await _dispose_screen(screen)
	screen = await _new_screen()
	screen.battle.rules.turn_draw = 0
	screen.battle.player.heat = 6
	var turn_before: int = screen.battle.turn
	var hp_before: int = screen.battle.player.hp
	var stop := _place(screen.battle, Vector2i.ZERO, "停")
	screen._board_view.rebuild()
	screen._board_view._on_tile_pressed(Vector2i.ZERO)
	screen._on_primary()
	await _wait_for_screen_idle(screen)
	_check("ui_solo_stop_ends_turn", screen.battle.turn == turn_before + 1 and screen.battle.player.heat == 2 and screen.battle.discard.has(stop) and screen.battle.player.hp < hp_before and not screen._busy and not screen.battle.end_turn_requested, "停实际结束当前阶段、正常结算敌方行动，并恢复下一回合输入")
	await _dispose_screen(screen)
	Settings.reduced_motion = saved_motion

func _run_ui_solo_throw() -> void:
	var saved_motion := Settings.reduced_motion
	Settings.reduced_motion = true
	var screen = await _new_screen()
	GameState.gold = 2
	var source := _place(screen.battle, Vector2i.ZERO, "投")
	var moved := _place(screen.battle, Vector2i(1, 0), "防")
	_place(screen.battle, Vector2i(0, 1), "御").pinned = true
	screen._board_view.rebuild()
	screen._board_view._on_tile_pressed(Vector2i.ZERO)
	screen._on_primary()
	_check("ui_throw_neighbor_picker", screen._solo_throw_active and screen._board_view._valid_pick(Vector2i(1, 0)) and not screen._board_view._valid_pick(Vector2i(0, 1)) and screen.battle.board.get_cell(0, 0) == source and GameState.gold == 2, "投先选非固定四邻字，选择前不消费施词字与铜钱")
	screen._board_view._on_tile_pressed(Vector2i(1, 0))
	var landing_picker: bool = screen._board_view.pick_mode == "throw_destination" and screen._board_view._valid_pick(Vector2i.ZERO) and screen._board_view._valid_pick(Vector2i(3, 3)) and not screen._board_view._valid_pick(Vector2i(1, 0))
	screen._board_view._on_tile_pressed(Vector2i(3, 3))
	_check("ui_throw_ready_after_two_targets", landing_picker and not screen._ready_action.is_empty() and screen.battle.board.get_cell(1, 0) == moved and GameState.gold == 2, "投的第二步只选合法落点，选齐后仍等待确认")
	screen._on_primary()
	await _wait_for_screen_idle(screen)
	_check("ui_throw_complete", screen.battle.board.get_cell(3, 3) == moved and screen.battle.board.get_cell(1, 0) == null and GameState.gold == 1 and screen.battle.discard.has(source) and not screen._busy and screen._board_view._interactable and screen._board_view.pick_mode.is_empty(), "投确认后扣1铜钱并移动原实体，结束选择和演出后恢复输入")
	await _dispose_screen(screen)
	screen = await _new_screen()
	GameState.gold = 2
	source = _place(screen.battle, Vector2i.ZERO, "投")
	moved = _place(screen.battle, Vector2i(1, 0), "防")
	screen._board_view.rebuild()
	screen._board_view._on_tile_pressed(Vector2i.ZERO)
	screen._on_primary()
	screen._board_view._on_tile_pressed(Vector2i(1, 0))
	screen._on_clear_cancel()
	_check("ui_throw_cancel_clean", not screen._solo_throw_active and screen._ready_action.is_empty() and screen._board_view.pick_mode.is_empty() and screen.battle.board.get_cell(0, 0) == source and screen.battle.board.get_cell(1, 0) == moved and GameState.gold == 2, "取消投的两步选择清除临时状态，原字、目标和铜钱保留")
	await _dispose_screen(screen)
	Settings.reduced_motion = saved_motion

func _run_ui_reconnect_return() -> void:
	var saved_motion := Settings.reduced_motion
	Settings.reduced_motion = true
	var screen = await _new_screen()
	var originals := _reconnect_targets(screen.battle)
	var source := _place(screen.battle, Vector2i.ZERO, "重")
	_place(screen.battle, Vector2i(1, 0), "连")
	screen._board_view.rebuild()
	screen._board_view._on_tile_pressed(Vector2i.ZERO)
	screen._board_view._on_tile_pressed(Vector2i(1, 0))
	screen._on_primary()
	_check("ui_reconnect_picker", screen._board_view.pick_mode == "three" and screen._recast_three_active and screen._confirm_btn.text.begins_with("重连") and screen.battle.board.get_cell(0, 0) == source, "真实重连进入三字选择，按钮标注重连并保留词字")
	for i in 4:
		screen._board_view._on_tile_pressed(Vector2i(2, 1))
	_check("ui_reconnect_duplicate_ignored", screen._recast_three_cells == [Vector2i(2, 1)] and screen._board_view.tiles[screen.battle.board.idx(2, 1)].is_selected, "同一目标点四次只计一枚并保留高亮")
	screen._board_view._on_tile_pressed(Vector2i(2, 2))
	screen._board_view._on_tile_pressed(Vector2i(2, 3))
	_check("ui_reconnect_ready_without_consumption", not screen._ready_action.is_empty() and screen._ready_action.target.cells.size() == 3 and originals.all(func(inst): return screen.battle.board.cells.has(inst)) and screen.battle.reconnect_pending.is_empty(), "选齐三个字后等待确认，尚未暂移或消耗")
	screen._on_primary()
	await _wait_for_screen_idle(screen)
	_check("ui_reconnect_suspend_and_badge", screen.battle.reconnect_pending.size() == 3 and screen.battle.board.fill_count() == 0 and screen.battle.discard.size() == 2 and StatusDisplay.collect(screen.battle.player, screen.battle).any(func(item): return item.id == "reconnect_pending" and item.stacks == 3) and not screen._busy and screen._board_view._interactable, "确认后三个原实体移入待回区，HUD 显示待回三枚并恢复输入")
	screen._on_end_turn()
	await _wait_for_screen_idle(screen)
	_check("ui_reconnect_end_turn_return", screen.battle.reconnect_pending.is_empty() and screen.battle.board.get_cell(2, 1) == originals[0] and screen.battle.board.get_cell(2, 2) == originals[1] and screen.battle.board.get_cell(2, 3) == originals[2] and not screen._busy and screen._board_view._interactable and _unique_circulation(screen.battle), "真实结束回合经过敌方行动，再将原实体返还原格，补字和输入正常")
	await _dispose_screen(screen)

	screen = await _new_screen()
	_reconnect_targets(screen.battle)
	source = _place(screen.battle, Vector2i.ZERO, "重")
	_place(screen.battle, Vector2i(1, 0), "连")
	screen._board_view.rebuild()
	screen._board_view._on_tile_pressed(Vector2i.ZERO)
	screen._board_view._on_tile_pressed(Vector2i(1, 0))
	screen._on_primary()
	screen._board_view._on_tile_pressed(Vector2i(2, 1))
	screen._on_clear_cancel()
	_check("ui_reconnect_cancel_clean", screen._board_view.pick_mode.is_empty() and screen._ready_action.is_empty() and screen._recast_three_cells.is_empty() and not screen._recast_three_active and screen.battle.reconnect_pending.is_empty() and screen.battle.discard.is_empty() and screen.battle.board.get_cell(0, 0) == source and not screen._board_view.tiles[screen.battle.board.idx(2, 1)].is_selected, "取消选择清理状态和高亮，不消耗施词字也不暂移目标")
	await _dispose_screen(screen)
	Settings.reduced_motion = saved_motion

func _cast_ui_flow(screen, row: int) -> void:
	_place(screen.battle, Vector2i.ZERO, "流")
	_place(screen.battle, Vector2i(1, 0), "速")
	screen._board_view.rebuild()
	screen._board_view._on_tile_pressed(Vector2i.ZERO)
	screen._board_view._on_tile_pressed(Vector2i(1, 0))
	screen._on_primary()
	screen._board_view._on_tile_pressed(Vector2i(0, row))
	screen._on_primary()
	await _wait_for_screen_idle(screen)

func _run_ui_flow_stacking() -> void:
	var saved_motion := Settings.reduced_motion
	Settings.reduced_motion = true
	var screen = await _new_screen()
	_pad(screen.battle)
	var marker := _place(screen.battle, Vector2i(3, 2), "回")
	await _cast_ui_flow(screen, 2)
	await _cast_ui_flow(screen, 2)
	_check("ui_flow_stack_four_words", screen.battle.flow_speed_rows.get(2, 0) == 4 and screen.battle.drawn_this_turn == 0 and screen._modal_count == 0 and not screen._busy, "从真实界面连续两次选第三行，完整累加四词")
	for x in 3:
		_place(screen.battle, Vector2i(x, 2), "防御力"[x])
	screen._board_view.rebuild()
	for x in 3:
		screen._board_view._on_tile_pressed(Vector2i(x, 2))
	screen._on_primary()
	await _wait_for_screen_idle(screen)
	_check("ui_flow_long_word_refill", screen.battle.drawn_this_turn == 3 and screen.battle.flow_speed_rows.get(2, 0) == 3 and screen.battle.board.get_cell(0, 2) != null and screen.battle.board.get_cell(1, 2) != null and screen.battle.board.get_cell(2, 2) != null and screen.battle.board.get_cell(3, 2) == marker, "三字词三个原格都补回，行内其他字不移动，扣一次额度")
	_check("ui_flow_remaining_badge", StatusDisplay.collect(screen.battle.player, screen.battle).any(func(item): return item.id == "flow_speed:2" and item.stacks == 3) and not screen._busy and screen._board_view._interactable and screen._board_view.path.is_empty(), "HUD 显示第三行剩余三词，结算后恢复输入")
	await _dispose_screen(screen)
	Settings.reduced_motion = saved_motion

func _run_ui_selection_limits() -> void:
	var saved_motion := Settings.reduced_motion
	Settings.reduced_motion = true
	var screen = await _new_screen()
	screen.battle.rules = screen.battle.rules.duplicate()
	screen.battle.rules.turn_draw = 4
	var originals: Array = []
	for g in ["击", "击", "防"]:
		var inst := CharInstance.new(Database.get_character_by_glyph(g))
		screen.battle.bag.append(inst)
		originals.append(inst)
	_place(screen.battle, Vector2i.ZERO, "精")
	_place(screen.battle, Vector2i(1, 0), "心")
	screen._board_view.rebuild()
	screen._board_view._on_tile_pressed(Vector2i.ZERO)
	screen._board_view._on_tile_pressed(Vector2i(1, 0))
	screen._on_primary()
	await _wait_for_screen_idle(screen)
	screen._on_end_turn()
	await _wait_for_screen_idle(screen)
	var first := _choice(screen, "精心")
	var index := _manual_option(first, "击")
	_check("ui_manual_initial_count", first != null and index >= 0 and str(first.cfg.options[index].text) == "【击】×2" and screen.battle.manual_draw_pending == 3, "实际精心跨回合打开定向补字，字袋里两枚击如实显示")
	if index >= 0:
		first._on_choose(index)
	var second := _choice(screen, "精心")
	index = _manual_option(second, "击")
	_check("ui_manual_reserved_count", second != null and index >= 0 and str(second.cfg.options[index].text) == "【击】×1", "选过一枚击后，下一步只剩一枚可选")
	# 旧浮层在本帧尚未释放，重复点击也不能再次回调。
	if is_instance_valid(first):
		first._on_choose(_manual_option(first, "击"))
	_check("ui_manual_stale_overlay", screen._manual_draw_picks == ["击"] and _choice(screen, "精心") == second and screen._modal_count == 1, "旧选择浮层的重复点击不累计选择、不再打开浮层")
	if index >= 0:
		second._on_choose(index)
	var third := _choice(screen, "精心")
	_check("ui_manual_exhausted_hidden", third != null and _manual_option(third, "击") == -1, "两枚击都已预约后，第三步不再提供击")
	index = _manual_option(third, "防")
	if index >= 0:
		third._on_choose(index)
	_check("ui_manual_complete_unique", screen.battle.manual_draw_pending == 0 and screen.battle.board.fill_count() == 3 and originals.all(func(inst): return _occurrences(screen.battle, inst) == 1) and screen._modal_count == 0 and screen._board_view._interactable, "三次选择落地三个不同实体，选择浮层关闭并恢复输入")
	var log_size: int = screen.battle.log.size()
	screen._on_manual_draw_chosen(0, ["击"], 3)
	_check("ui_manual_late_callback", screen._manual_draw_picks.is_empty() and screen.battle.log.size() == log_size and screen.battle.board.fill_count() == 3, "流程结束后的迟到回调不再结算或开启下一次选择")
	await _dispose_screen(screen)

	screen = await _new_screen()
	for g in ["击", "防", "御"]:
		screen.battle.bag.append(CharInstance.new(Database.get_character_by_glyph(g)))
	screen.battle.manual_draw_pending = 3
	screen._start_manual_draw()
	first = _choice(screen, "精心")
	first._on_choose(_manual_option(first, "击"))
	second = _choice(screen, "精心")
	screen._start_manual_draw()
	_check("ui_manual_start_once", screen._manual_draw_picks == ["击"] and screen._modal_count == 1 and _choice(screen, "精心") == second, "流程进行中再次开启精心不会重置已选字或叠加浮层")
	await _dispose_screen(screen)

	screen = await _new_screen()
	for g in ["击", "防", "御"]:
		screen.battle.bag.append(CharInstance.new(Database.get_character_by_glyph(g)))
	screen.battle.manual_draw_pending = 3
	screen._start_manual_draw()
	first = _choice(screen, "精心")
	first._on_choose(_manual_option(first, "击"))
	second = _choice(screen, "精心")
	second._on_choose(second.cfg.options.size() - 1)
	_check("ui_manual_random_remaining", screen.battle.board.fill_count() == 3 and screen.battle.manual_draw_pending == 0 and screen._modal_count == 0 and _unique_circulation(screen.battle), "选一枚后点剩下随机补，确实补齐剩余两枚")
	await _dispose_screen(screen)

	screen = await _new_screen()
	_place(screen.battle, Vector2i.ZERO, "再")
	_place(screen.battle, Vector2i(1, 0), "铸")
	for y in 3:
		_place(screen.battle, Vector2i(2, y + 1), "防")
	screen._board_view.rebuild()
	screen._board_view._on_tile_pressed(Vector2i.ZERO)
	screen._board_view._on_tile_pressed(Vector2i(1, 0))
	screen._on_primary()
	for i in 4:
		screen._board_view._on_tile_pressed(Vector2i(2, 1))
	_check("ui_recast_repeat_ignored", screen._recast_three_cells == [Vector2i(2, 1)] and screen._board_view.tiles[screen.battle.board.idx(2, 1)].is_selected, "同一再铸目标点四次只计一枚，并持续标记已选")
	screen._board_view._on_tile_pressed(Vector2i(2, 2))
	screen._board_view._on_tile_pressed(Vector2i(2, 3))
	_check("ui_recast_three_unique_ready", not screen._ready_action.is_empty() and screen._ready_action.target.cells == [Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3)], "必须选三个不同实体，三个同字形实体可分别占一名额")
	screen._on_primary()
	await _wait_for_screen_idle(screen)
	_check("ui_recast_unique_complete", screen.battle.board.fill_count() == 3 and screen.battle.board.cells.filter(func(inst): return inst != null and inst.temporary).size() == 3 and screen.battle.discard.size() == 2 and screen._board_view.pick_mode.is_empty() and _unique_circulation(screen.battle), "发动仅重铸三个独立目标，消耗词字并结束选择")
	await _dispose_screen(screen)

	screen = await _new_screen()
	var source := _place(screen.battle, Vector2i.ZERO, "再")
	_place(screen.battle, Vector2i(1, 0), "铸")
	_place(screen.battle, Vector2i(2, 1), "防")
	_place(screen.battle, Vector2i(2, 2), "御")
	_place(screen.battle, Vector2i(2, 3), "回").pinned = true
	screen._board_view.rebuild()
	screen._board_view._on_tile_pressed(Vector2i.ZERO)
	screen._board_view._on_tile_pressed(Vector2i(1, 0))
	screen._on_primary()
	_check("ui_recast_insufficient_targets", not screen._recast_three_active and screen._board_view.pick_mode.is_empty() and screen.battle.board.get_cell(0, 0) == source, "不足三个非固定、施词外的目标时保留词字，不进入无法完成的选择")
	_place(screen.battle, Vector2i(3, 3), "防")
	screen._board_view.rebuild()
	screen._on_primary()
	screen._board_view._on_tile_pressed(Vector2i.ZERO)
	screen._board_view._on_tile_pressed(Vector2i(2, 3))
	_check("ui_recast_invalid_targets_ignored", screen._recast_three_active and screen._recast_three_cells.is_empty(), "再铸的施词字和固定字不能占目标名额")
	screen._board_view._on_tile_pressed(Vector2i(2, 1))
	screen._on_clear_cancel()
	_check("ui_recast_cancel_clean", not screen._recast_three_active and screen._recast_three_cells.is_empty() and screen._ready_action.is_empty() and screen._board_view.pick_mode.is_empty() and not screen._board_view.tiles[screen.battle.board.idx(2, 1)].is_selected and screen.battle.board.get_cell(0, 0) == source, "取消再铸清除已选状态和高亮，不消耗词字")
	await _dispose_screen(screen)
	Settings.reduced_motion = saved_motion

func _run_ui_spatial_targets() -> void:
	var saved_motion := Settings.reduced_motion
	Settings.reduced_motion = true
	for text in ["左击", "右击"]:
		var screen = await _new_screen()
		var first := _place(screen.battle, Vector2i.ZERO, text[0])
		_place(screen.battle, Vector2i(1, 0), "击")
		var marker := _place(screen.battle, Vector2i(0, 3), "防")
		var enemy: Combatant = screen.battle.enemies[0]
		var hp_before := enemy.hp
		screen._board_view.rebuild()
		screen._board_view._on_tile_pressed(Vector2i.ZERO)
		screen._board_view._on_tile_pressed(Vector2i(1, 0))
		screen._on_primary()
		_check("ui_" + text + "_row_picker", screen._board_view.pick_mode == "row" and screen._board_view.pick_reselect, "真实出字入口进入整行选择，可直接点盘面改选")
		_check("ui_" + text + "_deferred", enemy.hp == hp_before and screen.battle.board.get_cell(0, 0) == first and screen.battle.discard.is_empty(), "选行之前不造成伤害或消耗词字")
		screen._board_view._on_tile_pressed(Vector2i(0, 3))
		screen._on_primary()
		await _wait_for_screen_idle(screen)
		var dest_x := 3 if text == "左击" else 1
		_check("ui_" + text + "_complete", hp_before - enemy.hp == 6 and screen.battle.board.get_cell(dest_x, 3) == marker and screen.battle.discard.size() == 2, "选第四行后完成 6 伤、正确方向的循环位移和两字消耗")
		_check("ui_" + text + "_unlocked", screen._pending_path.is_empty() and screen._modal_count == 0 and not screen._busy and screen._board_view.path.is_empty() and screen._board_view._interactable, "选择和动效完成后清理待执行路径并恢复盘面输入")
		await _dispose_screen(screen)

	var screen = await _new_screen()
	_place(screen.battle, Vector2i.ZERO, "流")
	_place(screen.battle, Vector2i(1, 0), "速")
	screen._board_view.rebuild()
	screen._board_view._on_tile_pressed(Vector2i.ZERO)
	screen._board_view._on_tile_pressed(Vector2i(1, 0))
	screen._on_primary()
	_check("ui_flow_speed_picker", screen._board_view.pick_mode == "row" and screen.battle.flow_speed_rows.is_empty() and screen.battle.discard.is_empty(), "流速进入整行选择，选择前不消耗施词字")
	screen._board_view._on_tile_pressed(Vector2i(0, 2))
	screen._on_primary()
	await _wait_for_screen_idle(screen)
	_check("ui_flow_speed_complete", screen.battle.flow_speed_rows.get(2, 0) == 2 and screen.battle.discard.size() == 2 and screen._modal_count == 0 and not screen._busy, "流速为所选第三行增加两词，施放自身不扣额度")
	await _dispose_screen(screen)

	for text in ["左转", "右转"]:
		screen = await _new_screen()
		var first := _place(screen.battle, Vector2i(3, 0), text[0])
		_place(screen.battle, Vector2i(3, 1), "转")
		var marker := _place(screen.battle, Vector2i.ZERO, "防")
		screen._board_view.rebuild()
		screen._board_view._on_tile_pressed(Vector2i(3, 0))
		screen._board_view._on_tile_pressed(Vector2i(3, 1))
		screen._on_primary()
		_check("ui_" + text + "_region_picker", screen._board_view.pick_mode == "3x3" and screen.battle.board.get_cell(3, 0) == first, "3×3 目标进入区域选择，选择前保留词字")
		screen._board_view._on_tile_pressed(Vector2i(2, 2))
		_check("ui_" + text + "_reject_edge", screen._board_view.pick_mode == "3x3" and screen._ready_action.is_empty() and screen.battle.board.get_cell(0, 0) == marker, "会使 3×3 区域越界的左上角不可选")
		screen._board_view._on_tile_pressed(Vector2i.ZERO)
		screen._on_primary()
		await _wait_for_screen_idle(screen)
		var dest := Vector2i(0, 2) if text == "左转" else Vector2i(2, 0)
		_check("ui_" + text + "_complete", screen.battle.board.get_xy(dest) == marker and screen.battle.discard.size() == 2 and screen._pending_path.is_empty() and not screen._busy, "选择合法区域并发动后，按本词方向旋转且正常消耗两字")
		await _dispose_screen(screen)
	Settings.reduced_motion = saved_motion

func _run_ui_completion() -> void:
	var screen = await _new_screen()
	_place(screen.battle, Vector2i(0, 0), "再")
	_place(screen.battle, Vector2i(1, 0), "铸")
	var originals: Array = []
	for y in 3:
		originals.append(_place(screen.battle, Vector2i(2, y + 1), "防"))
	screen._board_view.rebuild()
	screen._current_word = Database.get_word_by_glyphs_string("再铸")
	screen._on_commit([Vector2i(0, 0), Vector2i(1, 0)])
	for y in 3:
		screen._board_view._on_tile_pressed(Vector2i(2, y + 1))
	_check("ui_recast_ready", not screen._ready_action.is_empty() and screen.battle.board.get_cell(0, 0) != null, "再铸选满三字只准备操作，不提前消耗词字")
	screen._on_primary()
	var replaced := true
	for y in 3:
		var current: CharInstance = screen.battle.board.get_cell(2, y + 1)
		replaced = replaced and current != null and current.temporary and current.uid != originals[y].uid
	_check("ui_recast_complete", replaced and screen.battle.board.get_cell(0, 0) == null, "再铸发动后替换三字并消耗词字")
	await _dispose_screen(screen)

	screen = await _new_screen()
	_place(screen.battle, Vector2i(0, 0), "合")
	_place(screen.battle, Vector2i(1, 0), "流")
	var from_bag := CharInstance.new(Database.get_character_by_glyph("防"))
	var from_discard := CharInstance.new(Database.get_character_by_glyph("御"))
	screen.battle.bag.append(from_bag)
	screen.battle.discard.append(from_discard)
	screen._board_view.rebuild()
	screen._current_word = Database.get_word_by_glyphs_string("合流")
	screen._on_commit([Vector2i(0, 0), Vector2i(1, 0)])
	var overlay := _choice(screen, "合流")
	assert(overlay != null)
	overlay._on_choose(0)
	screen._board_view._on_tile_pressed(Vector2i(2, 2))
	screen._board_view._on_tile_pressed(Vector2i(3, 2))
	_check("ui_merge_ready", not screen._ready_action.is_empty() and screen.battle.board.get_cell(0, 0) != null, "合流选好弃字和两相邻落点才准备操作")
	screen._on_primary()
	_check("ui_merge_complete", screen.battle.board.get_cell(2, 2) == from_bag and screen.battle.board.get_cell(3, 2) == from_discard and _unique_circulation(screen.battle), "合流发动后按所选顺序落字，实体不重复")
	await _dispose_screen(screen)

	screen = await _new_screen()
	_place(screen.battle, Vector2i(0, 1), "充")
	_place(screen.battle, Vector2i(1, 1), "放")
	_place(screen.battle, Vector2i(2, 1), "电")
	screen.battle.enable_ability("next_compound", 1)
	screen._board_view.rebuild()
	screen._on_commit([Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)])
	overlay = _choice(screen, "复合")
	_check("ui_compound_choice", overlay != null and screen.battle.board.get_cell(0, 1) != null, "复合允许选保留字，选择前不消耗")
	assert(overlay != null)
	overlay._on_choose(1)
	var retained: CharInstance = screen.battle.board.get_cell(1, 1)
	_check("ui_compound_selected", retained != null and retained.temporary and retained.glyph() == "放", "复合保留用户选择的第二个字")
	await _dispose_screen(screen)

	screen = await _new_screen()
	_place(screen.battle, Vector2i.ZERO, "防")
	_place(screen.battle, Vector2i(1, 1), "御")
	screen.battle.enable_ability("next_diagonal", 1)
	screen._board_view.rebuild()
	screen._board_view._on_tile_pressed(Vector2i.ZERO)
	screen._board_view._on_tile_pressed(Vector2i(1, 1))
	_check("ui_diagonal_input", screen._board_view.path == [Vector2i.ZERO, Vector2i(1, 1)], "流利的点击输入与逻辑路径校验一致")
	await _dispose_screen(screen)

	screen = await _new_screen()
	screen.battle.begin_formation()
	screen.battle.add_heat(6)
	_place(screen.battle, Vector2i.ZERO, "停")
	_place(screen.battle, Vector2i(1, 0), "息")
	var turn_before: int = screen.battle.turn
	screen._board_view.rebuild()
	screen._on_commit([Vector2i.ZERO, Vector2i(1, 0)])
	screen._on_primary()
	_check("ui_formation_stop", screen.battle.turn == turn_before + 1 and not screen.battle.end_turn_requested, "结阵中的停息同样立即结束出字并执行敌人行动")
	await _dispose_screen(screen)

func _run_final_boundaries() -> void:
	var b := _battle()
	b.enable_ability("next_diagonal", 1)
	b.begin_formation()
	_place(b, Vector2i.ZERO, "防")
	_place(b, Vector2i(1, 1), "御")
	var first := b.try_play([Vector2i.ZERO, Vector2i(1, 1)])
	_place(b, Vector2i(2, 2), "放")
	_place(b, Vector2i(3, 3), "火")
	var second := b.try_play([Vector2i(2, 2), Vector2i(3, 3)])
	_check("formation_diagonal_reserved", first.ok and not second.ok, "一个流利标记不能供两个结阵词使用斜连")
	b.resolve_formation()

	b = _battle()
	_word(b, "急停")
	var card := _place(b, Vector2i(0, 1), "防")
	var result := b.try_play([Vector2i(0, 1)])
	_check("stopped_phase_rejects_play", not result.ok and b.board.get_xy(Vector2i(0, 1)) == card and b.player.block == 0, "纯逻辑接口也拒绝在急停后继续出字")

	b = _battle()
	_word(b, "强化", 0, {"empower_glyph": "清"})
	var polluted := _place(b, Vector2i(0, 2), "防")
	polluted.add_pollution("rush")
	_word(b, "清热", 1)
	_check("empower_targeted_solo", polluted.pollutions.is_empty(), "强化清参与清热时，额外单字效果按清原格净化相邻污染")

	b = _battle()
	_word(b, "强化", 0, {"empower_glyph": "破"})
	_place(b, Vector2i(2, 2), "击")
	_place(b, Vector2i(3, 2), "破")
	b.fuse_cards(Vector2i(2, 2), Vector2i(3, 2))
	b.try_play([Vector2i(2, 2)])
	_check("empower_fused_glyph", b.enemies[0].hp == 190, "融合击破也触发附带字破的强化：8+2伤")

	var h := BattleHarness.new()
	h.reset({"seed": 7, "deck": [], "opening_draw": 0, "turn_draw": 0})
	_place(h.battle, Vector2i.ZERO, "防")
	_place(h.battle, Vector2i(1, 1), "御")
	h.battle.enable_ability("next_diagonal", 1)
	var actions := h.legal_actions()
	_check("harness_diagonal_actions", actions.any(func(action): return action.get("word", "") == "防御"), "无头合法动作枚举包含流利允许的斜连词")

	b = _battle()
	var source := _place(b, Vector2i.ZERO, "回")
	_place(b, Vector2i(1, 0), "转")
	result = b.try_play([Vector2i.ZERO, Vector2i(1, 0)], {"target_index": 0})
	_check("target_kind_validation", not result.ok and result.need_target == EffectData.Target.BOARD_2X2 and b.board.get_xy(Vector2i.ZERO) == source, "敌人目标参数不能替代回转的区域目标")
