extends RefCounted
class_name EffectHandlers
## 词效调度器：按 EffectData.handler 分发。
## 复杂实现见 EffectHandlersActions；共享工具见 EffectUtil。

static func run(handler: String, eff: EffectData, ctx: Dictionary) -> Array:
	return EffectRegistry.execute(handler, eff, ctx)


static func run_builtin(handler: String, eff: EffectData, ctx: Dictionary) -> Array:
	var b: BattleState = ctx.get("battle")
	if b == null:
		return []
	var src: Combatant = ctx.get("source")
	var enemy := EffectUtil.enemy(b, ctx)
	var g: int = (ctx.get("glyphs", []) as Array).size()
	var extra: int = max(0, g - 2)
	var amount: int = eff.amount + eff.amount_per_extra_glyph * extra
	if amount > 0 and handler in ["damage", "chip_shield_damage", "block_temp", "heal", "energy"]:
		amount += b.take_solo_gain_bonus(ctx)

	match handler:
		"strength_growing":
			var gained := maxi(1, int(ctx.get("strengthen_gain", b.strengthen_plays)))
			src.add_status("strength", gained)
			return ["加强：本场第 %d 次打出，获得 %d 层力量" % [b.strengthen_plays, gained]]
		"damage":
			return EffectUtil.damage(b, enemy, amount)
		"gold_percent_damage":
			# Snapshot the wallet at resolution time; this attack never spends coins.
			var gold_damage := floori(maxi(0, GameState.gold) * maxi(0, amount) / 100.0)
			return EffectUtil.damage(b, enemy, gold_damage)
		"self_hp_loss":
			var lost := src.take_damage(amount) if src != null else 0
			return ["失去 %d 生命" % lost]
		"self_draw_penalty":
			b.next_draw_penalty += amount
			return ["下一次正常补字 -%d" % amount]
		"chip_shield_damage":
			if enemy == null:
				return ["破：没有目标"]
			var limit := int(eff.args.get("shield", 4))
			var removed := enemy.remove_block(limit)
			var persistent := mini(enemy.persistent_block, limit - removed)
			if persistent > 0:
				enemy.add_persistent_block(-persistent)
				removed += persistent
			return ["破：移除 %d 点护盾" % removed] + EffectUtil.damage(b, enemy, amount)
		"retaliate_once":
			b.enable_ability("retaliate_once", b.ability_value("retaliate_once") + amount)
			return ["反：本回合下一次受到敌方攻击后，对攻击者反击 %d 伤（整次行动后，仅一次）" % amount]
		"energy_next_turn":
			b.enable_ability("energy_next_turn", b.ability_value("energy_next_turn") + amount)
			return ["蓄：下回合开始获得 %d 储能" % amount]
		"payment_discount_once":
			b.enable_ability("payment_discount_once", b.ability_value("payment_discount_once") + amount)
			return [BattleBalance.fixed_text("币：本回合下一次铜钱费用 -%d，最低 0（仅一次）", "payment_discount_once", eff) % amount]
		"profit_if_earned":
			if b.gold_earned_this_turn <= 0:
				return ["利：本回合此前没有获得铜钱，未获利"]
			return ["利：此前已有铜钱收入，再获得 %d 铜钱" % b.earn_gold(amount)]
		"rest_cool":
			b.add_heat(-amount)
			if b.damage_dealt_this_turn <= 0:
				var rested := BattleBalance.i("rest_heal", 1) + b.take_solo_gain_bonus(ctx)
				b.heal_player(rested) if src == b.player else src.heal(rested)
				return ["息：热度 -%d，本回合未造成伤害，回复 %d 生命" % [amount, rested]]
			return ["息：热度 -%d" % amount]
		"throw_neighbor":
			return EffectHandlersActions._throw_neighbor(b, ctx)
		"solo_release":
			var release := ctx.get("word") == null and bool((ctx.get("target", {}) as Dictionary).get("release_energy", false))
			if release and b.player.energy < BattleBalance.i("release_cost", 1):
				return ["放：储能不足，未释放"]
			if release:
				b.spend_energy(BattleBalance.i("release_cost", 1))
			var release_damage: int = (BattleBalance.i("release_damage", 8) if release else amount) + b.take_solo_gain_bonus(ctx)
			return EffectUtil.damage(b, enemy, release_damage) + [BattleBalance.fixed_text("放：消耗 1 储能", "solo_release", eff) if release else "放：未消耗储能"]
		"force_once":
			b.enable_ability("force_once", b.ability_value("force_once") + amount)
			return ["力：下一次攻击总伤害 +%d（仅一次）" % amount]
		"solo_gain_once":
			b.enable_ability("solo_gain_once", b.ability_value("solo_gain_once") + amount)
			return ["加：本回合下一次单字首项直接伤害、临挡、治疗或储能收益 +%d（仅一次）" % amount]
		"next_gap":
			b.enable_ability("next_gap", 1)
			return ["超：本回合下一次成功组词允许横向或纵向跨过一个空格（最多一次）"]
		"heat_to_energy_solo":
			var heat_cost := int(eff.args.get("heat_cost", 2))
			if src.heat < heat_cost:
				return ["化：热度不足 %d，只弃掉本字" % heat_cost]
			b.add_heat(-heat_cost)
			var converted := amount + b.take_solo_gain_bonus(ctx)
			b.add_energy(converted)
			return ["化：消耗 %d 热度，获得 %d 储能" % [heat_cost, converted]]
		"precision_draw", "buy_bag_solo":
			return EffectHandlersActions._solo_bag_draw(b, ctx, handler)
		"turn_strength":
			src.turn_strength += amount
			return ["强：本回合伤害 +%d，回合结束清除" % amount]
		"energy_gain_once":
			b.enable_ability("energy_gain_once", b.ability_value("energy_gain_once") + amount)
			return ["能：本回合下一次获得储能时额外 +%d（仅一次）" % amount]
		"link_next_word":
			b.enable_ability("link_draw_once", b.ability_value("link_draw_once") + amount)
			return ["连：本回合下一次成功组词后补 %d 字（仅一次）" % amount]
		"combine_next_word":
			b.enable_ability("combine_word_once", b.ability_value("combine_word_once") + amount)
			return [BattleBalance.fixed_text("合：本回合下一次成功组词后获得 2 临时格挡、1 储能（仅一次）", "combine_next_word", eff)]
		"speed_next_word":
			b.enable_ability("speed_word_once", b.ability_value("speed_word_once") + amount)
			return [BattleBalance.fixed_text("速：本回合下一次成功组词后补 2 字、热度 +1（仅一次）", "speed_next_word", eff)]
		"energy_refund_once":
			b.enable_ability("energy_refund_once", b.ability_value("energy_refund_once") + amount)
			return [BattleBalance.fixed_text("复：本回合下一次实际消耗储能时返还 1 点（仅一次，不超过消耗量）", "energy_refund_once", eff)]
		"stop_cool":
			b.add_heat(-amount)
			b.end_turn_requested = true
			return ["停：热度 -%d，立即结束出字阶段，敌人正常行动" % amount]
		"turn_heat_capacity":
			b.temporary_heat_capacity += amount
			src.heat_capacity += amount
			return ["载：本回合热容 +%d，下回合恢复" % amount]
		"split_neighbor", "recast_neighbor", "refine_junk_neighbor":
			return EffectHandlersActions._solo_neighbor_action(b, ctx, handler)
		"overdo":
			b.overdo_count += 1
			var overdo_dmg: int = amount * b.overdo_count
			return EffectUtil.damage(b, enemy, overdo_dmg) + ["过分：第 %d 次，共 %d 伤" % [b.overdo_count, overdo_dmg]]
		"damage_all":
			var out: Array = []
			b.begin_attack_sequence()
			for e in b.alive_enemies():
				out.append_array(EffectUtil.damage(b, e, amount))
			b.end_attack_sequence()
			return out
		"damage_multi":
			# 多段攻击：每段 amount 点，段数由 args.hits 指定（共享一次攻击加成序列）
			var hits: int = max(1, int(eff.args.get("hits", 1)))
			var multi_out: Array = []
			b.begin_attack_sequence()
			for i in hits:
				if enemy == null or not enemy.is_alive():
					break
				multi_out.append_array(EffectUtil.damage(b, enemy, amount))
			b.end_attack_sequence()
			multi_out.append("%d 段 × %d 伤" % [hits, amount])
			return multi_out
		"block_temp":
			src.add_block(amount)
			return ["获得 %d 点临时格挡" % amount]
		"block_persist":
			src.add_persistent_block(amount)
			return ["获得 %d 点持久盾" % amount]
		"guard_reduce":
			src.turn_damage_reduction += amount
			return ["御：本回合每次受伤 -%d" % amount]
		"guard_once":
			src.next_damage_reduction += amount
			return ["御：下一次受到伤害减免 %d 点，触发后消失" % amount]
		"block_next_turn":
			b.enable_ability("block_next_turn", b.ability_value("block_next_turn") + amount)
			return ["甲：下回合开始获得 %d 点格挡（仅一次）" % amount]
		"guard_halve":
			src.turn_damage_halve = true
			return [BattleBalance.fixed_text("放心：本回合受到伤害减半（减半后再 -1）", "guard_halve", eff)]
		"ability_warm_heart":
			b.enable_ability("warm_heart", 1)
			return [BattleBalance.fixed_text("热心：本场持续——每获得 1 热度回复 1 生命，每失去 1 热度扣 1 生命", "ability_warm_heart", eff)]
		"ability_strong_heart":
			b.enable_ability("strong_heart", 1)
			return [BattleBalance.fixed_text("强心：本场每回合开始回复 2 + 已触发心力层数的生命", "ability_strong_heart", eff)]
		"collect_own":
			return EffectHandlersActions._collect_own(b, ctx)
		"cold_heart":
			src.turn_damage_double = true
			src.no_block_turns = BattleBalance.i("cold_no_block", 2)
			return ["冷心：本回合攻击伤害翻倍；本回合及下一回合不能获得新格挡或持久盾，已有护盾仍生效"]
		"cleanse_status":
			var removed: Array = []
			for sid in src.statuses.keys():
				var sd: StatusData = Database.get_status(str(sid))
				if sd != null and sd.kind == StatusData.Kind.DEBUFF:
					removed.append(sd.name)
					src.statuses.erase(sid)
			if removed.is_empty():
				return ["清心：没有可清除的负面状态"]
			return ["清心：清除了 %s" % ", ".join(removed)]
		"ability_armor_plating":
			b.enable_ability("armor_plating", 1)
			return [BattleBalance.fixed_text("甲：每回合获得 1 点格挡，格挡被击穿则碎裂", "ability_armor_plating", eff)]
		"ability_guard_inject":
			b.enable_ability("guard_inject", b.ability_value("guard_inject") + amount)
			return ["护：下次敌方塞字减少 %d 个" % amount]
		"heal":
			b.heal_player(amount) if src == b.player else src.heal(amount)
			return ["回复 %d 点生命" % amount]
		"draw_random":
			var n := b.draw_to_board(amount)
			return ["随机补 %d 字" % n]
		"draw_excluding_source":
			var excluded: Array = (ctx.get("consumed", []) as Array).map(func(item): return item.inst)
			var drawn := b.draw_to_board(amount, excluded)
			return ["补 %d 字（排除本次打出的实体）" % drawn]
		"draw_penalty_next":
			b.next_draw_penalty += amount
			return ["下次补字 -%d" % amount]
		"draw_bonus_next":
			b.next_draw_penalty -= amount
			return ["下回合多抽 %d 字" % amount]
		"manual_draw_next":
			b.next_draw_penalty += amount
			b.enable_ability("manual_draw", 1)
			return ["精心：下回合补字 -%d，但可从字袋定向选字（随机落地）" % amount]
		"gold":
			EffectUtil.add_gold(b, amount)
			return ["获得 %d 铜钱（本战累计 %d）" % [amount, b.gold_earned]]
		"energy":
			b.add_energy(amount)
			return ["储能 +%d（当前 %d）" % [amount, src.energy]]
		"heat":
			b.add_heat(amount)
			if amount >= 0:
				return ["热度 +%d（当前 %d/%d）" % [amount, src.heat, src.heat_capacity]]
			return ["热度 %d（当前 %d）" % [amount, src.heat]]
		"heat_clear":
			var lost := src.heat
			b.clear_heat()
			return ["清空热度（-%d）" % lost]
		"apply_status_self":
			src.add_status(eff.status_id, amount if amount != 0 else 1)
			var self_sd: StatusData = Database.get_status(eff.status_id)
			return ["获得状态【%s】×%d" % [self_sd.name if self_sd != null else eff.status_id, amount if amount != 0 else 1]]
		"apply_status_enemy":
			if enemy != null:
				enemy.add_status(eff.status_id, amount if amount != 0 else 1)
				var foe_sd: StatusData = Database.get_status(eff.status_id)
				return ["使敌人获得【%s】×%d" % [foe_sd.name if foe_sd != null else eff.status_id, amount if amount != 0 else 1]]
			return []
		"permanent_damage_reduction":
			if GameState.permanent_damage_reduction <= 0:
				GameState.permanent_damage_reduction = amount
				return ["获得本局永久能力：从下一场战斗起，每次受到伤害减免%d" % amount]
			return ["防御力已生效，不重复叠加"]

		# --- 防反 ---
		"ability_prevent_interference":
			b.enable_ability("prevent_interference", amount)
			return ["防护：抵消下一次敌方盘面干扰"]
		"ability_convert_block":
			b.enable_ability("convert_block", int(eff.args.get("percent", 50)))
			return ["护甲：本场所有敌人行动结束后，获得剩余临挡%d%%的持久盾" % int(eff.args.get("percent", 50))]
		"counter":
			b.enable_ability("counter", b.ability_value("counter") + (amount if amount != 0 else 1))
			return ["反击：预留 %d 层" % (amount if amount != 0 else 1)]
		"shield_smash":
			var dmg2: int = amount
			var per: int = int(eff.args.get("per", 2))
			var bonus: int = int(eff.args.get("bonus", 3))
			if per > 0:
				dmg2 += int(floor(src.persistent_block / per)) * bonus
			src.persistent_block = 0
			return EffectUtil.damage(b, enemy, dmg2) + ["盾击消耗全部持久盾"]
		"break_shield_damage":
			var out2: Array = []
			if enemy == null:
				return out2
			var dmg3: int = amount
			var broke := false
			if enemy.block > 0:
				var mult: int = int(eff.args.get("mult", 2))
				var absorbed: int = min(enemy.block, dmg3 * mult)
				enemy.remove_block(absorbed)
				var leftover: int = int(ceil((dmg3 * mult - absorbed) / float(mult)))
				if enemy.block <= 0:
					broke = true
				dmg3 = leftover
			if dmg3 > 0:
				out2.append_array(EffectUtil.damage(b, enemy, dmg3))
			else:
				out2.append("击破：拆掉护盾")
			if broke:
				var n3 := b.draw_to_board(int(eff.args.get("draw", 1)))
				out2.append("击破护盾：补 %d 字" % n3)
			return out2
		"remove_enemy_block":
			if enemy != null:
				var removed := enemy.block
				enemy.remove_block(removed)
				return ["移除敌方 %d 点护盾" % removed]
			return []
		"conditional_draw_after_attack":
			if b.attack_words_this_turn > 0:
				var n4 := b.draw_to_board(amount)
				return ["连招奖励：补 %d 字" % n4]
			return ["（此前无即时攻击，未补字）"]
		"conditional_draw_half_hp":
			var low: bool = src.hp * BattleBalance.i("hp_half_divisor", 2) < src.max_hp
			var n5 := b.draw_to_board(int(eff.args.get("low", amount)) if low else int(eff.args.get("high", 1)))
			return ["反超：%s，补 %d 字" % ["低血" if low else "常态", n5]]

		# --- 连携 / 空间 ---
		"gravity":
			b.apply_gravity()
			return ["全盘向下重力"]
		"gravity_left":
			b.apply_gravity_left()
			return ["全盘向左重力"]
		"gravity_right":
			b.apply_gravity_right()
			return ["全盘向右重力"]
		"gravity_damage":
			var moved := b.apply_gravity_count()
			var dmg4: int = amount + int(eff.args.get("per", 2)) * moved
			return EffectUtil.damage(b, enemy, dmg4) + ["重力移动 %d 枚字块" % moved]
		"merge_duplicates":
			return EffectHandlersActions._merge_duplicates(b, ctx)
		"replay_last_attack":
			return EffectHandlersActions._replay_last_attack(b)
		"replay_word":
			return EffectHandlersActions._replay_word(b)
		"recover_recent":
			return EffectHandlersActions._recover_recent(b, ctx, amount)
		"suspend_three":
			return EffectHandlersActions._suspend_three(b, ctx)
		"linger_chance":
			var per := BattleBalance.i("linger_percent", 25)
			var max_layers := BattleBalance.i("linger_layers_max", 2)
			var layers := mini(b.ability_value("linger_chance") + 1, max_layers)
			b.enable_ability("linger_chance", layers)
			return ["流连：本回合后续每枚出字 %d%% 概率留在原位（%d/%d 层）" % [mini(per * layers, 100), layers, max_layers]]
		"energy_regen":
			var gained := b.activate_energy_regen(maxi(1, amount))
			return [BattleBalance.fixed_text("回能：本回合储能 +%d，后续 %d 回合开局各获得 2 点储能", "energy_regen", eff) % [gained, b.ability_value("energy_regen")]]
		"return_enemy":
			return EffectHandlersActions._return_enemy(b, ctx)
		"ability_shared_attack":
			b.enable_ability("shared_attack", 1)
			b.begin_formation()
			return ["合击：进入结阵——之后打出的词只登记，点「发动」一起结算（多词可共享同一枚【击】）"]
		"rotate_2x2":
			var tile := EffectUtil.tile(ctx)
			b.rotate_2x2(tile)
			return [BattleBalance.fixed_text("回转 2×2", "rotate_2x2", eff)]
		"shift_row":
			var row := int((ctx.get("target", {}) as Dictionary).get("row", -1))
			var sdir := int(eff.args.get("dir", -1))
			b.shift_row(row, sdir)
			return ["第 %d 行向%s循环移动一格" % [row + 1, "左" if sdir < 0 else "右"]]
		"rotate_3x3":
			var a3 := EffectUtil.tile(ctx)
			var rdir := int(eff.args.get("dir", 1))
			b.rotate_3x3(a3, rdir)
			return [BattleBalance.fixed_text("3×3 区域%s旋转 90°", "rotate_3x3", eff) % ("顺时" if rdir > 0 else "逆时")]
		"swap_cells":
			var tt: Dictionary = ctx.get("target", {})
			b.swap_cells(tt.get("tile", Vector2i.ZERO), tt.get("tile2", Vector2i.ZERO))
			return ["交换两格"]
		"overcool":
			b.clear_heat()
			b.enable_ability("next_heat_to_block", BattleBalance.i("overcool_mult", 2))
			return [BattleBalance.fixed_text("过冷：热量清零；下次获得的热度转为每点 +2 持久盾", "overcool", eff)]
		"rotate_repeat":
			var rt := EffectUtil.tile(ctx)
			b.start_repeat_rotate(rt)
			return [BattleBalance.fixed_text("转速：旋转一次（可继续「发动」，最多 3 次）", "rotate_repeat", eff)]
		"reshuffle_line":
			return EffectHandlersActions._reshuffle_line(b, ctx)
		"place_two":
			return EffectHandlersActions._place_two(b, ctx)
		"recover_two":
			return EffectHandlersActions._recover_two(b, ctx)
		"ability_longword_draw":
			return EffectUtil.stack_ability(b, "longword_draw", BattleBalance.fixed_text("能力：本场持续——每打出 3 字及以上的词，原位补 3 字", "ability_longword_draw", eff))
		"ability_electric_material":
			return EffectUtil.stack_ability(b, "electric_material", BattleBalance.fixed_text("电能：本场持续——每消耗 2 储能，随机空格生成临时【电】", "ability_electric_material", eff))
		"ability_heat_to_energy":
			return EffectUtil.simple_ability(b, "heat_to_energy", BattleBalance.fixed_text("蓄热：本场持续——回合结束热度 -2，每点转 1 储能", "ability_heat_to_energy", eff))
		"flow_speed":
			var row := int((ctx.get("target", {}) as Dictionary).get("row", -1))
			if row < 0 or row >= b.board.size:
				return ["流速：请选择棋盘内的一行"]
			b.flow_speed_rows[row] = int(b.flow_speed_rows.get(row, 0)) + amount
			return ["流速：第 %d 行本回合后续出词原地补回消耗字，增加 %d 词，剩余 %d 词" % [row + 1, amount, int(b.flow_speed_rows[row])]]
		"fill_board_heat":
			var placed := 0
			while b.board.fill_count() < BattleBalance.i("fill_board_target", 12):
				if not b._draw_one():
					break
				placed += 1
			placed = b.record_draw(placed)
			if placed > 0:
				b.add_heat(placed)
			return ["火速：补至 %d 字（+%d 枚，热度 +%d）" % [BattleBalance.i("fill_board_target", 12), placed, placed]]
		"next_draw_bonus_two":
			var nb2 := b.draw_to_board(BattleBalance.i("next_bonus_draw", 2))
			return ["加急：立即多补 %d 字" % nb2]
		"overheat_shield":
			b.enable_ability("overheat_shield", BattleBalance.i("overheat_block_cap", 4))
			return [BattleBalance.fixed_text("蓄冷：下次过热可抵消 4 点污染【热】", "overheat_shield", eff)]
		"heat_to_persist_block":
			var hb: int = src.heat
			b.clear_heat()
			src.add_persistent_block(hb * BattleBalance.i("heat_block_mult", 2))
			return ["冷热：消耗 %d 热度，获得 %d 持久盾" % [hb, hb * BattleBalance.i("heat_block_mult", 2)]]
		"energy_to_heat_block":
			var e2: int = src.energy
			b.spend_energy(e2)
			b.add_heat(e2)
			src.add_block(e2 * BattleBalance.i("energy_heat_block_mult", 3))
			return ["电热：消耗 %d 储能，热度 +%d，临挡 +%d" % [e2, e2, e2 * BattleBalance.i("energy_heat_block_mult", 3)]]
		"heat_to_energy_damage":
			var h2: int = int(src.heat / BattleBalance.i("fire_electric_divisor", 2))
			b.clear_heat()
			b.add_energy(h2)
			return EffectUtil.damage(b, enemy, BattleBalance.i("fire_electric_damage", 5)) + ["火电：热度转 %d 储能" % h2]
		"refund_energy_half":
			var half := b.refund_half_energy()
			return ["复电：恢复 %d 储能" % half]
		"wash_heat":
			var washed := 0
			for wi in b.board.cells.size():
				var wi_inst: CharInstance = b.board.cells[wi]
				if wi_inst != null and wi_inst.glyph() == "热":
					b.board.cells[wi] = null
					b.bag.append(wi_inst)
					washed += 1
			if washed > 0:
				b._shuffle(b.bag)
			b.add_heat(-BattleBalance.i("wash_heat", 2))
			return [BattleBalance.fixed_text("流火：洗回 %d 枚【热】，热度 -2", "wash_heat", eff) % washed] + Relics.on_wash_heat(b, enemy)
		"next_copy_layer":
			return EffectUtil.simple_ability(b, "next_copy_layer", BattleBalance.fixed_text("超能：下一条 3+ 字词可消耗储能保留临时复制层", "next_copy_layer", eff))
		"double_next_ability":
			b.abilities["double_next"] = 1
			return ["超能力：本回合下一次持续能力触发结算两遍"]
		"gold_to_shield":
			return EffectUtil.simple_ability(b, "gold_to_shield", "收息：本回合每次花铜钱发动词效，同时获得等额持久盾")
		"inject_bounty":
			return EffectUtil.simple_ability(b, "inject_bounty", BattleBalance.fixed_text("加收：本回合敌人每注入 1 枚污染字，获得 2 铜钱", "inject_bounty", eff))
		"instant_power":
			return EffectUtil.simple_ability(b, "instant_power", BattleBalance.fixed_text("电力：本场持续——行列位移后可耗 1 储能额外位移一次", "instant_power", eff))
		"heat_pollution_damage":
			return EffectUtil.stack_ability(b, "heat_pollution_damage", BattleBalance.fixed_text("火热：本场持续——每枚污染【热】造成 5 伤", "heat_pollution_damage", eff))
		"recover_to_bag":
			return EffectHandlersActions._recover_to_bag(b, ctx)
		"move_cell":
			return EffectHandlersActions._move_cell(b, ctx)
		"destroy_2x2":
			var tile2 := EffectUtil.tile(ctx)
			var destroyed := b.destroy_2x2(tile2)
			var dmg5: int = amount * destroyed
			return EffectUtil.damage(b, enemy, dmg5) + ["爆破摧毁 %d 枚字块" % destroyed]
		"clear_board":
			var cleared := b.clear_board()
			var dmg_cb: int = amount * cleared
			return EffectUtil.damage(b, enemy, dmg_cb) + ["超重：清空字盘 %d 枚，每枚 %d 伤" % [cleared, amount]]
		"converge":
			var anchor := EffectUtil.tile(ctx)
			var moved := b.converge_to(anchor)
			return ["重心：%d 枚字向锚点聚拢" % moved]
		"ability_heart_power":
			b.enable_ability("heart_power", 1)
			return ["心力：本场持续——每打出一颗【心】叠加一层心力，可抵挡致命伤害"]
		"fill_board_full":
			var placed_fb := 0
			while b.board.fill_count() < b.board.size * b.board.size:
				if not b._draw_one():
					break
				placed_fb += 1
			placed_fb = b.record_draw(placed_fb)
			return ["心急：补满盘面（+%d 枚）" % placed_fb]
		"heart_link":
			if enemy == null:
				return ["（无目标）"]
			var avg_max := int((src.max_hp + enemy.max_hp) / BattleBalance.i("heart_average_divisor", 2))
			src.max_hp = avg_max
			enemy.max_hp = avg_max
			GameState.player_max_hp = avg_max
			var avg_hp := int((src.hp + enemy.hp) / BattleBalance.i("heart_average_divisor", 2))
			src.hp = avg_hp
			enemy.hp = avg_hp
			GameState.player_hp = avg_hp
			return ["心连心：双方生命上限与当前生命都平均为 %d（上限 %d，跨战保留）" % [avg_hp, avg_max]]
		"ability_diagonal_next":
			b.enable_ability("next_free_word", 1)
			return ["流利：本回合下一次组词可按字序选择任意位置的字，无需相邻"]

		# --- 流转 ---
		"recover_consumed":
			return EffectHandlersActions._recover_consumed(b, ctx)
		"cleanse_all":
			var cn := b.cleanse_board()
			return ["清洗：净化 %d 枚字的污染标记" % cn]
		"cleanse_adjacent":
			return EffectHandlersActions._cleanse_adjacent(b, ctx)
		"wash_adjacent":
			return EffectHandlersActions._cleanse_adjacent(b, ctx, true)
		"move_neighbor":
			return EffectHandlersActions._move_neighbor(b, ctx)
		"ability_flow":
			b.add_ability("flow", amount)
			return [BattleBalance.fixed_text("流转：本回合每 2 种不同多字词补 %d 字", "ability_flow", eff) % amount]
		"ability_compound_next":
			b.enable_ability("next_compound", amount)
			return [BattleBalance.fixed_text("复合：下一次 3 字及以上的词保留一枚临时复制", "ability_compound_next", eff)]

		# --- 蓄放 ---
		"ability_energy_idle":
			b.add_ability("energy_idle", amount)
			b.add_energy(BattleBalance.i("immediate_idle_energy", 1))
			return [BattleBalance.fixed_text("蓄能：立即储能 +1；本场回合结束若有可用多字词，储能 +%d", "ability_energy_idle", eff) % amount]
		"energy_around_tail":
			var tail_n: int = int(ctx.get("tail_neighbors_own", 0))
			var total: int = amount + BattleBalance.i("tail_energy_mult", 1) * tail_n
			b.add_energy(total)
			return ["蓄电：储能 +%d（基础 %d + 词尾周围 %d）" % [total, amount, tail_n]]
		"energy_discharge":
			var spent: int = src.energy
			b.spend_energy(spent)
			var per_point: int = maxi(1, int(eff.args.get("hits_per_energy", 1)))
			var refund: int = maxi(0, int(eff.args.get("refund", 0)))
			var msgs: Array = []
			var landed := 0
			b.begin_attack_sequence()
			for hit in spent * per_point:
				if not src.is_alive():
					break
				if enemy == null or not enemy.is_alive():
					enemy = b.first_alive_enemy()
				if enemy == null:
					break
				var before_hp := enemy.hp
				msgs.append_array(EffectUtil.damage(b, enemy, amount))
				if enemy.hp < before_hp:
					landed += 1
			b.end_attack_sequence()
			msgs.append("放电：消耗 %d 储能，%d 段 %d 伤" % [spent, spent * per_point, amount])
			# 充放电：每命中一段，下回合储能 +refund
			if refund > 0 and landed > 0:
				var gain := landed * refund
				b.enable_ability("energy_next_turn", b.ability_value("energy_next_turn") + gain)
				msgs.append("充放电：命中 %d 段，下回合储能 +%d" % [landed, gain])
			return msgs

		# --- 热暴 ---
		"ability_heat_overload_bonus":
			if not b.has_ability("heat_overload_bonus_armed"):
				b.enable_ability("heat_overload_bonus", amount)
			b.enable_ability("heat_overload_bonus_armed", amount)
			return ["过热：本场每回合首次溢热后，下一次多字词额外补 %d 字" % amount]
		"ability_accel":
			b.enable_ability("accel", amount)
			return [BattleBalance.fixed_text("加速：本回合每次多字词补 1 字并升温 1", "ability_accel", eff)]
		"ability_rapid_next":
			b.enable_ability("next_rapid", amount)
			b.enable_ability("next_rapid_heat", int(eff.args.get("heat", 0)))
			return ["急速：下一次多字词后补至多 %d 字" % amount]
		"ability_double_draw_next":
			b.enable_ability("next_double_draw", amount)
			return ["超速：本回合下一次补字最多额外 %d 字" % amount]
		"heat_burst":
			var heat_spent: int = src.heat
			b.clear_heat()
			var dmg6: int = amount + int(eff.args.get("per", 4)) * heat_spent
			return EffectUtil.damage(b, enemy, dmg6) + ["火爆：消耗 %d 热度" % heat_spent]
		"heat_cleanse":
			b.add_heat(-amount)
			var sc := b.cleanse_scorch()
			return ["清热：热度 -%d，清除 %d 处灼热" % [amount, sc]]
		"heat_to_damage_flow":
			var maxh: int = int(eff.args.get("max", 4))
			var reduce: int = mini(src.heat, mini(maxh, b.drawn_this_turn))
			b.add_heat(-reduce)
			var dmg7: int = amount * reduce
			return EffectUtil.damage(b, enemy, dmg7) + ["热流：降热 %d" % reduce]
		"ability_reload":
			src.heat_capacity += amount * b.passive_multiplier("重载")
			b.add_heat(0)
			b.next_draw_penalty += int(eff.args.get("draw_penalty", 1))
			return ["重载：本场热容 +%d，仅下回合补字 -%d" % [amount, int(eff.args.get("draw_penalty", 1))]]
		"ability_overfire":
			b.enable_ability("next_overfire", 1)
			b.add_heat(int(eff.args.get("heat", 2)))
			b.enable_ability("next_overfire_per", int(eff.args.get("per", 3)))
			return ["过火：本回合下一次攻击整次追加热度×%d伤害，仅一次；当前热度%d" % [int(eff.args.get("per", 3)), src.heat]]
		"ability_electric_overload":
			b.add_ability("electric_overload")
			return ["电流过载：本战每次溢热生成热字并 +储能/+伤害"]

		# --- 经济 ---
		"spend_gold_damage":
			var maxg: int = int(eff.args.get("max", 3))
			var pay: int = min(EffectUtil.available(b), maxg)
			EffectUtil.pay(b, pay)
			return EffectUtil.damage(b, enemy, amount * pay) + ["投币：支付 %d铜钱" % pay]
		"capture_glyph":
			return EffectHandlersActions._capture_glyph(b, ctx, amount)
		"reveal_place":
			return EffectHandlersActions._reveal_place(b, ctx, amount)
		"replace_self":
			return EffectHandlersActions._replace_self(b, ctx)
		"transform_board":
			return EffectHandlersActions._transform_board(b, ctx)
		"split_grow":
			return EffectHandlersActions._split_grow(b, ctx)
		"empower_glyph":
			return EffectHandlersActions._empower_glyph(b, ctx)
		"refine_remove":
			return EffectHandlersActions._refine_remove(b, ctx, eff)
		"cremate":
			return EffectHandlersActions._cremate(b, ctx, eff)
		"fuse_cards":
			return EffectHandlersActions._fuse_cards(b, ctx)
		"refine_layer":
			return EffectHandlersActions._refine_layer(b, ctx)
		"gild_glyph":
			return EffectHandlersActions._gild_glyph(b, ctx, eff)
		"pin_glyph":
			return EffectHandlersActions._pin_glyph(b, ctx)
		"anchor_self":
			return EffectHandlersActions._anchor_self(b, ctx)
		"precision_place":
			return EffectHandlersActions._precision_place(b, ctx, eff)
		"split_mind":
			return EffectHandlersActions._split_mind(b)
		"vigor":
			return EffectHandlersActions._vigor(b)
		"blackout":
			b.blackout_requested = true
			return ["停电了……（拖动连出「开灯」恢复）"]
		"lights_on":
			return ["来电了。"]
		"moon_pull":
			var at: Vector2i = (ctx.get("path", []) as Array)[0] if not (ctx.get("path", []) as Array).is_empty() else Vector2i.ZERO
			var pulled := b.converge_to(at)
			return ["月：%d 枚字向【月】原位聚拢" % pulled]
		"death_word":
			src.hp = 0
			return ["死亡。"]
		"anti_death":
			if GameState.relic_counters.get("anti_death_granted", false):
				return ["反死亡：这一局已经拿过复活机会"]
			GameState.relic_counters["anti_death_granted"] = true
			GameState.revive_charges += 1
			return ["反死亡：本局获得一次满血复活"]
		"charge_overheat":
			return EffectHandlersActions._charge_overheat(b, eff)
		"recast_board":
			return EffectHandlersActions._recast_board(b)
		"recast_copy":
			return EffectHandlersActions._recast_copy(b, ctx)
		"recast_three":
			return EffectHandlersActions._recast_three(b, ctx)
		"repeat_last":
			return EffectHandlersActions._repeat_last(b, ctx)
		"reverse_line":
			return EffectHandlersActions._reverse_line(b, ctx)
		"merge_flow":
			return EffectHandlersActions._merge_flow(b, ctx)
		"hard_stop":
			return EffectHandlersActions._hard_stop(b)
		"repeat_word":
			return EffectHandlersActions._repeat_word(b)
		"fireproof":
			return EffectUtil.simple_ability(b, "fireproof", "防火：本场自己打出的灼热【热】不再扣血")
		"blastproof":
			return EffectUtil.simple_ability(b, "blastproof", "防爆：本场被摧毁的己方字改为回字袋并获得持久盾")
		"joint_funding":
			return EffectUtil.simple_ability(b, "joint_funding", BattleBalance.fixed_text("合资：本场支付铜钱时可用 2 储能抵 1 铜钱（可混合）", "joint_funding", eff))
		"profit_share":
			return EffectUtil.simple_ability(b, "profit_share", "分利：本回合每当实际获得铜钱，同时获得等量储能")
		"suspend":
			return EffectHandlersActions._suspend(b)

		# ---- 蓄放进阶 ----
		"energy_to_bonus":
			var spent_e: int = src.energy
			b.spend_energy(spent_e)
			b.abilities["next_energy_bonus"] = int(b.abilities.get("next_energy_bonus", 0)) + spent_e * int(eff.args.get("per", 2))
			return ["蓄力：消耗%d储能，下一次攻击每段+%d伤害，跨回合保留" % [spent_e, spent_e * int(eff.args.get("per", 2))]]
		"energy_to_heat_damage":
			var spent_e2: int = src.energy
			b.spend_energy(spent_e2)
			b.add_heat(spent_e2)
			return EffectUtil.damage(b, enemy, int(eff.args.get("per", 2)) * spent_e2) + ["放热：储能 %d 转为热度" % spent_e2]
		"heat_to_energy":
			var h2e: int = src.heat
			b.clear_heat()
			b.add_energy(h2e)
			return ["热能：热度 %d 转为储能" % h2e]
		"heat_to_bonus":
			var h2b: int = src.heat
			b.clear_heat()
			src.add_status("next_bonus", h2b * int(eff.args.get("per", 2)))
			return ["热力：消耗%d热度，下一次攻击每段+%d伤害，跨回合保留" % [h2b, h2b * int(eff.args.get("per", 2))]]
		"flow_energy_or_draw":
			if b.drawn_this_turn > 0:
				b.add_energy(amount)
				return ["电流：本回合已补字，储能 +%d" % amount]
			var ncf := b.draw_to_board(amount)
			return ["电流：补 %d 字" % ncf]
		"ability_gravity_always":
			b.enable_ability("gravity_always", 1)
			return ["重力：本战每次有效出字后自动全盘下落"]

		# ---- 普通铜钱 ----
		"alloy":
			src.add_persistent_block(amount)
			EffectUtil.add_gold(b, int(eff.args.get("gold", 2)))
			return ["合金：获得 %d 持久盾与 %d 铜钱" % [amount, int(eff.args.get("gold", 2))]]
		"mint":
			EffectUtil.add_gold(b, amount)
			var cd_mint: CharacterData = Database.get_character_by_glyph("币")
			var path_m: Array = ctx.get("path", [])
			if cd_mint != null and not path_m.is_empty():
				var pos_m: Vector2i = path_m[path_m.size() - 1]
				if b.board.get_xy(pos_m) == null:
					var inst_m := CharInstance.new(cd_mint)
					inst_m.owner = CharInstance.Owner.SELF_GENERATED
					b.board.set_xy(pos_m, inst_m)
					b.temp_chars.append(inst_m)
			return ["铸币：+%d 铜钱并生成临时【币】" % amount]
		"bounty":
			var bcost: int = int(eff.args.get("cost", 5))
			if not EffectUtil.pay(b, bcost):
				return ["重金：支付额不足（需 %d）" % bcost]
			b.bounty_paid = true
			b.bounty_reward = amount
			return ["重金：悬赏 %d，本回合击杀后返还" % amount]

		# ---- 热暴 P3 ----
		"cold_snap":
			var dmg_c: int = amount + int(eff.args.get("per", 2)) * b.damage_taken_last_turn
			b.clear_heat()
			return EffectUtil.damage(b, enemy, dmg_c) + ["爆冷：清空热度"]
		"ceasefire":
			b.enable_ability("ceasefire", 1)
			return ["停火：本回合未造成敌伤则免疫敌方攻击"]
		"ignite":
			if enemy != null:
				var layers: int = BattleBalance.i("burn_layers", 2)
				enemy.add_status("burn", layers)
				return ["放火：【%s】获得 %d 层灼烧（每层每回合失去当前热度×%d 生命）" % [enemy.display_name, layers, BattleBalance.i("burn_heat_mult", 2)]]
			return []

		# ---- 连携 P3 ----
		"electric_strike":
			return EffectUtil.damage(b, enemy, amount + int(eff.args.get("per", 2)) * src.energy)
		"fire_power":
			return EffectUtil.damage(b, enemy, amount + int(eff.args.get("per", 2)) * src.heat)
		"joint_force":
			src.add_block(amount)
			b.add_energy(int(eff.args.get("energy", 2)))
			return ["合力：获得 %d 临挡与 %d 储能" % [amount, int(eff.args.get("energy", 2))]]
		"serial":
			b.add_ability("serial", int(eff.args.get("bonus", 6)))
			return [BattleBalance.fixed_text("连载：本场每累计 3 次有效出词，下一次攻击每段 +6，待兑现奖励可叠加并跨回合保留", "serial", eff)]
		"repeat_zero":
			b.enable_ability("repeat_zero", 1)
			return ["反复：本回合下一次出词后，将整词的临时字复制分别放入随机空格"]

		# ---- 流转 P3 ----
		"divert":
			return EffectHandlersActions._divert_junk(b, ctx)
		"clear_flow":
			var sc2 := b.cleanse_scorch()
			var ncf2 := b.draw_to_board(amount)
			return ["清流：清除 %d 处灼热，补 %d 字" % [sc2, ncf2]]
		"buyback":
			return EffectHandlersActions._buyback(b, ctx)

	return ["（未实现的效果 %s）" % handler]


# ---------------------------------------------------------------- helpers
