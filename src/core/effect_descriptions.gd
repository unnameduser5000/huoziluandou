extends RefCounted
class_name EffectDescriptions
## 只读预览：不得执行 handler、抽字、退款、洗牌或消耗随机数。

## b 给了就按出字时的规则补上遗物认的词（反字模倒连、叠字钱三连），预览和实际出字一致
static func word_for(glyphs: Array, b: BattleState = null) -> WordData:
	var word := Database.get_word_by_glyphs(glyphs)
	if word == null and glyphs.has("过"):
		word = Database.get_word_by_glyphs(glyphs.filter(func(g): return g != "过"))
	if word == null and b != null:
		word = Relics.fallback_word(b, glyphs)
	return word

static func word_text(word: WordData, b: BattleState, path: Array = [], target: Dictionary = {}, concise := false) -> String:
	var lines: Array[String] = [EffectGlossary.brief(word) if concise else word.describe()]
	var current := _current(word.effects, b, path, target)
	if not current.is_empty():
		lines.append("当前：" + current)
	lines.append_array(_active_triggers(word.effects, b, word))
	if b.formation_mode and not b.formation_queue.is_empty() and not current.is_empty():
		lines.append("结阵按发动时的状态依次结算。")
	return "\n".join(lines)

static func solo_text(inst: CharInstance, b: BattleState, path: Array = [], target: Dictionary = {}) -> String:
	if inst == null or inst.data == null:
		return ""
	if inst.word_only:
		return "仅供组词的临时字；单独打出只弃掉，不触发单字效果。"
	var lines: Array[String] = [inst.describe()]
	var current := _current(inst.data.solo_effects, b, path, target)
	if not current.is_empty():
		lines.append("当前：" + current)
	lines.append_array(_active_triggers(inst.data.solo_effects, b))
	if b.formation_mode and not b.formation_queue.is_empty() and not current.is_empty():
		lines.append("结阵按发动时的上一手与资源状态依次结算。")
	if inst.pinned:
		lines.append("固定实体本回合已使用，下回合恢复。" if inst.pinned_exhausted else "固定实体本回合还可使用1次，使用后留在原格。")
	elif inst.temporary_uses > 0:
		lines.append("本枚字还可使用%d次，下一次使用后仍留在原格。" % (inst.temporary_uses + 1))
	return "\n".join(lines)

static func _active_triggers(effects: Array, b: BattleState, word: WordData = null) -> Array[String]:
	var lines: Array[String] = []
	if word != null and word.length() >= 2:
		if b.has_ability("link_draw_once"):
			lines.append("连：本词成功后额外补%d字，仅一次。" % b.ability_value("link_draw_once"))
		if b.has_ability("combine_word_once"):
			var count := b.ability_value("combine_word_once")
			lines.append("合：本词成功后获得%d临挡、%d储能，仅一次。" % [BattleBalance.i("combine_block", 2) * count, BattleBalance.i("combine_energy", 1) * count])
		if b.has_ability("speed_word_once"):
			var count := b.ability_value("speed_word_once")
			lines.append("速：本词成功后补%d字、热度+%d，仅一次。" % [BattleBalance.i("speed_draw", 2) * count, BattleBalance.i("speed_heat", 1) * count])
		if b.has_ability("repeat_zero"):
			lines.append("反复：本词将生成【%s】的整套临时字，随机放入空格。" % word.word)
		if b.has_ability("next_free_word"):
			lines.append("流利：本词可按任意位置选字，成功后消耗机会。")
		if b.has_ability("next_gap"):
			lines.append("超：本次组词成功后会消耗跨空格机会，即使没跨格。")
		if b.has_ability("next_draw_bonus"):
			lines.append("过热待补：本词打出后、结算效果前额外补%d字。" % b.ability_value("next_draw_bonus"))
		if b.has_ability("repeat") and b.repeat_armed:
			lines.append("重复：本词的效果再结算一次，铜钱与储能照付。")
		if b.player.status_stacks("next_extra") > 0:
			lines.append("超载：本词的效果再结算一次，铜钱与储能照付。" if not EffectResolver.instant_effects(effects).is_empty() else "超载：本词没有可再结算的效果，仍会消耗一次超载机会。")
		if word.length() >= BattleBalance.i("long_word_threshold", 3) and b.has_ability("next_compound"):
			lines.append("复合：本词可选1枚实际消耗的字，在原格留临时字。")
		if word.length() >= BattleBalance.i("long_word_threshold", 3) and b.has_ability("next_copy_layer"):
			lines.append("超能：本词将按可用的字自动消耗储能，每付%d点保留1枚临时字。" % BattleBalance.i("copy_layer_cost", 1))
	if effects.any(func(effect): return effect.is_attack()):
		if b.player.status_stacks("next_bonus") > 0:
			lines.append("热力待发：若本次发动攻击，每段+%d，计入超强翻倍，整次攻击后消耗。" % b.player.status_stacks("next_bonus"))
		if b.player.status_stacks("next_double") > 0:
			lines.append("超强：本次攻击的基础伤害、力量和热力加成×%d，被全挡也消耗。" % BattleBalance.i("double_attack_mult", 2))
		if b.has_ability("force_once"):
			lines.append("力：若本次发动攻击，首个伤害段额外+%d，仅一次。" % b.ability_value("force_once"))
		if b.has_ability("next_energy_bonus"):
			lines.append("蓄力待发：若本次发动攻击，每段额外+%d，整次攻击后消耗。" % b.ability_value("next_energy_bonus"))
		if b.has_ability("next_serial_bonus"):
			lines.append("连载待发：若本次发动攻击，每段额外+%d，整次攻击后消耗。" % b.ability_value("next_serial_bonus"))
		if b.has_ability("next_overfire"):
			lines.append("过火：若本次发动攻击，按攻击时热度×%d追加一次伤害。" % b.ability_value("next_overfire_per", 3))
	if word == null and b.has_ability("solo_gain_once") and effects.any(func(effect): return effect.handler in ["damage", "chip_shield_damage", "block_temp", "heal", "energy", "solo_release", "heat_to_energy_solo", "rest_cool"]):
		lines.append("加：本次符合条件的首项单字直接收益+%d，触发后消耗。" % b.ability_value("solo_gain_once"))
	if b.player.no_block_turns > 0 and effects.any(func(effect): return effect.handler in ["block_temp", "block_persist", "energy_to_heat_block", "heat_to_persist_block", "suspend", "joint_force", "alloy"]):
		lines.append("冷心禁防生效：本次无法获得新的格挡或持久盾。")
	return lines

static func _glyphs(cards: Array) -> String:
	var names: PackedStringArray = []
	for card in cards:
		names.append("【%s】" % "".join(card.glyph_list()))
	return "、".join(names)

static func replayable(b: BattleState) -> Array:
	var out: Array = []
	for item in b.last_played_consumed:
		var inst: CharInstance = item.inst
		if item.get("kind", "real") in ["layer", "pinned"] or inst.pinned or b.board.cells.has(inst):
			continue
		if inst.is_player_owned() and not inst.temporary and (b.discard.has(inst) or b.bag.has(inst)):
			out.append(inst)
	return out

static func refundable(b: BattleState) -> int:
	if b.last_energy_spent <= 0 or b.last_energy_half_claimed:
		return 0
	return maxi(0, int(ceil(b.last_energy_spent / BattleBalance.f("refund_divisor", 2.0))) - b.last_energy_refunded)

static func _current(effects: Array, b: BattleState, path: Array, target: Dictionary) -> String:
	var lines: Array[String] = []
	for effect in effects:
		var text := EffectRegistry.preview(effect, b, path, target)
		if not text.is_empty() and not lines.has(text):
			lines.append(text)
	return "\n".join(lines)

static func legacy_preview(e: EffectData, b: BattleState, path: Array, target: Dictionary) -> String:
	var energy := b.player.energy
	var heat := b.player.heat
	match e.handler:
		"gold_percent_damage":
			return "当前%d铜钱，对应%d基础伤害（%d%%）。" % [GameState.gold, floori(maxi(0, GameState.gold) * maxi(0, e.amount) / 100.0), e.amount]
		"repeat_last":
			if b.last_played_glyphs.is_empty():
				return "尚未打出任何字，无法复制；本次只弃掉【再】。"
			var last := str(b.last_played_glyphs.back())
			var source := "上一手【%s】" % "".join(b.last_played_glyphs)
			if last == "再":
				return source + "，末字是【再】，不能复制自身；本次只弃掉。"
			return source + "，末字【%s】；本次生成临时【%s】，有空格时才放入。" % [last, last]
		"replay_last_attack":
			return "再结算一次【%s】的效果。" % b.last_attack_word.word if b.last_attack_word != null and not b.last_attack_effects.is_empty() else "没有可再结算的攻击词。"
		"replay_word":
			var cards := replayable(b)
			var source := "上一词【%s】" % b.last_played_word.word if b.last_played_word != null else "尚无上一词"
			return source + "；可返回原字：%s，实际放入数量以空格为限。" % _glyphs(cards) if not cards.is_empty() else source + "；没有仍可返回的原字。"
		"recover_recent":
			var cards := b.recoverable_consumed()
			cards.reverse()
			cards = cards.slice(0, maxi(0, e.amount))
			return "可回袋顶：%s。" % _glyphs(cards) if not cards.is_empty() else "弃字堆没有本回合此前消耗的己方原字。"
		"refund_energy_half":
			if b.last_energy_spent <= 0:
				return "尚无实际储能消费，可退款0点。"
			if b.last_energy_half_claimed:
				return "最近消费%d储能已用【复电】退款，可退款0点；需要一笔新的消费。" % b.last_energy_spent
			return "最近消费%d储能，已退%d点，本次可再退%d点。" % [b.last_energy_spent, b.last_energy_refunded, refundable(b)]
		"strength_growing":
			return "本场下次成功打出为第%d次，获得%d层力量；已有%d层力量。" % [b.strengthen_plays + 1, b.strengthen_plays + 1, b.player.status_stacks("strength")]
		"overdo":
			return "下次结算为本场第%d次，基础伤害%d；效果重演会继续推进次数。" % [b.overdo_count + 1, (b.overdo_count + 1) * e.amount]
		"energy_discharge":
			var text := "%d储能，对应%d段、每段%d基础伤害；消耗全部储能。" % [energy, energy, e.amount]
			if int(e.args.get("draw_per", 0)) > 0:
				text += "对应补字上限%d枚。" % (energy * int(e.args.draw_per))
			return text
		"energy_to_bonus":
			return "%d储能，对应下一次攻击每段+%d；已有待生效加成%d。" % [energy, energy * int(e.args.get("per", 2)), b.ability_value("next_energy_bonus")]
		"heat_to_bonus":
			return "%d热度，对应下一次攻击每段+%d；已有热力加成%d。" % [heat, heat * int(e.args.get("per", 2)), b.player.status_stacks("next_bonus")]
		"energy_to_heat_damage":
			return "%d储能，对应+%d热度、一次%d基础伤害。" % [energy, energy, energy * int(e.args.get("per", 2))]
		"energy_to_heat_block":
			return "%d储能，对应+%d热度、%d临时格挡。" % [energy, energy, energy * BattleBalance.i("energy_heat_block_mult", 3)]
		"heat_to_energy":
			return "%d热度，可转为%d储能。" % [heat, heat]
		"heat_to_energy_damage":
			return "%d热度，可转为%d储能，基础伤害%d。" % [heat, int(heat / BattleBalance.i("fire_electric_divisor", 2)), BattleBalance.i("fire_electric_damage", 5)]
		"heat_to_persist_block", "suspend":
			return "%d热度，对应%d持久盾。" % [heat, heat * BattleBalance.i("heat_block_mult", 2)]
		"electric_strike":
			return "%d储能，对应一次%d基础伤害。" % [energy, e.amount + energy * int(e.args.get("per", 2))]
		"fire_power":
			return "%d热度，对应一次%d基础伤害。" % [heat, e.amount + heat * int(e.args.get("per", 2))]
		"heat_burst":
			return "%d热度，对应一次%d基础伤害。" % [heat, e.amount + heat * int(e.args.get("per", 4))]
		"ability_overfire":
			var after := heat if b.has_ability("next_heat_to_block") else heat + int(e.args.get("heat", 2))
			return "本词升温后为%d热度；若攻击时热度未变，整次攻击追加%d伤害一次。" % [after, after * int(e.args.get("per", 3))]
		"cold_snap":
			return "上回合实际失去%d生命，对应%d基础伤害。" % [b.damage_taken_last_turn, e.amount + b.damage_taken_last_turn * int(e.args.get("per", 2))]
		"shield_smash":
			var shield := b.player.persistent_block
			var bonus := int(floor(shield / float(maxi(1, int(e.args.get("per", 2)))))) * int(e.args.get("bonus", 3))
			return "现有%d持久盾，将全部消耗，对应一次%d基础伤害。" % [shield, e.amount + bonus]

		"permanent_damage_reduction":
			return "本局已获得永久减伤，再打一次不叠加。" if GameState.permanent_damage_reduction > 0 else "本局尚未获得永久减伤，首次打出后从下一场战斗生效。"

		"heat_to_damage_flow":
			var cooled := mini(heat, mini(int(e.args.get("max", 4)), b.drawn_this_turn))
			return "本回合已补%d字、现有%d热度，可降%d热，对应%d基础伤害。" % [b.drawn_this_turn, heat, cooled, cooled * e.amount]
		"flow_energy_or_draw":
			return "本回合已补%d字，本次获得%d储能。" % [b.drawn_this_turn, e.amount] if b.drawn_this_turn > 0 else "本回合尚未补字，本次补%d字。" % e.amount
		"conditional_draw_after_attack":
			return "本回合此前已有攻击词，满足额外补字条件。" if b.attack_words_this_turn > 0 else "本回合此前没有攻击词，不额外补字。"
		"conditional_draw_half_hp":
			var low := b.player.hp * BattleBalance.i("hp_half_divisor", 2) < b.player.max_hp
			return "生命%d/%d，本次补%d字。" % [b.player.hp, b.player.max_hp, int(e.args.get("low", e.amount)) if low else int(e.args.get("high", 1))]
		"profit_if_earned":
			return "本回合已获得%d铜钱，满足额外获得%d铜钱的条件。" % [b.gold_earned_this_turn, e.amount] if b.gold_earned_this_turn > 0 else "本回合此前未获得铜钱，本次无铜钱收益。"
		"rest_cool":
			return "本回合尚未使敌人掉血，本次可回复%d生命。" % BattleBalance.i("rest_heal", 1) if b.damage_dealt_this_turn <= 0 else "本回合已使敌人掉血，本次只降温、不回复生命。"
		"heat_to_energy_solo":
			return "现有%d热度，可消耗%d热度换%d储能。" % [heat, int(e.args.get("heat_cost", 2)), e.amount] if heat >= int(e.args.get("heat_cost", 2)) else "现有%d热度，不足%d，本次只弃掉原字。" % [heat, int(e.args.get("heat_cost", 2))]
		"solo_release":
			return "现有%d储能，可选择免费%d基础伤害，或消耗%d储能打%d基础伤害。" % [energy, e.amount, BattleBalance.i("release_cost", 1), BattleBalance.i("release_damage", 8)] if energy >= BattleBalance.i("release_cost", 1) else "储能不足，本次免费造成%d基础伤害。" % e.amount
		"precision_draw", "buy_bag_solo":
			var source := b.board.get_xy(path[0]) if not path.is_empty() else null
			var candidates := b.solo_bag_candidates(source)
			return "可选原字：%s。" % _glyphs(candidates) if not candidates.is_empty() else "没有可选实体，本次只弃掉原字。"
		"energy_refund_once", "force_once", "energy_gain_once", "link_next_word", "solo_gain_once", "combine_next_word", "speed_next_word":
			var ids := {"energy_refund_once": "energy_refund_once", "force_once": "force_once", "energy_gain_once": "energy_gain_once", "link_next_word": "link_draw_once", "solo_gain_once": "solo_gain_once", "combine_next_word": "combine_word_once", "speed_next_word": "speed_word_once"}
			var existing := b.ability_value(ids[e.handler])
			if existing > 0:
				var total := existing + e.amount
				if e.handler == "combine_next_word":
					return "已有合效果，本次叠加后，下一词获得%d临挡、%d储能，仅触发一次。" % [BattleBalance.i("combine_block", 2) * total, BattleBalance.i("combine_energy", 1) * total]
				if e.handler == "speed_next_word":
					return "已有速效果，本次叠加后，下一词补%d字、热度+%d，仅触发一次。" % [BattleBalance.i("speed_draw", 2) * total, BattleBalance.i("speed_heat", 1) * total]
				var labels := {"energy_refund_once": "返还储能", "force_once": "整次攻击追加伤害", "energy_gain_once": "额外储能", "link_next_word": "补字", "solo_gain_once": "单字首项收益加成"}
				return "已有待用%s%d，本次叠加后为%d；下次触发时一次结算。" % [labels[e.handler], existing, total]
		"spend_gold_damage":
			var payment := mini(EffectUtil.available(b), int(e.args.get("max", 3)))
			return "按%d点原费用计伤，优惠后实际支付%d，基础伤害%d。" % [payment, EffectUtil.discounted_cost(b, payment), payment * e.amount]
		"serial":
			return "本场已累计%d次词，距离下次奖励还需%d次（含本次）。" % [b.serial_words, BattleBalance.i("serial_interval", 3) - b.serial_words % BattleBalance.i("serial_interval", 3)]
		"ability_strong_heart":
			return "本场心力已挡下%d次致命伤，下回合开始可回复%d生命。" % [b.player.heart_power_triggered, BattleBalance.i("strong_heart_base", 2) + BattleBalance.i("heart_trigger_heal", 1) * b.player.heart_power_triggered]
		"energy_around_tail":
			var count := 0
			if not path.is_empty():
				for pos in b.board.neighbors(path.back()):
					var inst := b.board.get_xy(pos)
					if inst != null and inst.is_player_owned() and not path.has(pos):
						count += 1
			return "词尾周围有%d枚未参与的己方字，对应%d储能。" % [count, e.amount + count]
		"reveal_place":
			var candidates := EffectHandlersActions.deploy_candidates(b)
			return _transfer(candidates, int(target.get("bag_uid", -1)), b)
		"buyback":
			var candidates := b.discard.filter(func(c): return c.is_player_owned() and not c.temporary)
			return _transfer(candidates, int(target.get("place_uid", target.get("discard_uid", -1))), b)
		"recover_consumed":
			var candidates := b.recoverable_consumed()
			return "本回合弃字堆可选：%s。" % _glyphs(candidates) if not candidates.is_empty() else "没有仍在弃字堆中的本回合己方消耗字。"
	return ""

static func _transfer(cards: Array, uid: int, b: BattleState) -> String:
	if cards.is_empty():
		return "没有可选原字，本次不支付、不补字。"
	var due := EffectUtil.discounted_cost(b, BattleBalance.i("buy_cost", 2))
	var payment := "需付%d铜钱，可支付%d铜钱。" % [due, EffectUtil.available(b)]
	for card in cards:
		if card.uid == uid:
			return "已选己方原字【%s】，额外使用+%d；%s" % ["".join(card.glyph_list()), BattleBalance.i("buyback_layer", 1), payment]
	return "可选原字：%s；%s" % [_glyphs(cards), payment]
