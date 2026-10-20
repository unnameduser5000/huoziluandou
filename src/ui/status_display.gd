extends RefCounted
class_name StatusDisplay
## Read-only adapter: gameplay values never live in the HUD.

const ABILITY_NAMES := {
	"armor_plating": "甲", "guard_inject": "护", "prevent_interference": "防护",
	"convert_block": "护甲", "counter": "反击",
	"next_heat_to_block": "过冷", "longword_draw": "能力", "electric_material": "电能",
	"heat_to_energy": "蓄热", "overheat_shield": "蓄冷", "next_copy_layer": "超能",
	"warm_heart": "热心", "strong_heart": "强心",
	"double_next": "超能力", "gold_to_shield": "收息", "inject_bounty": "加收",
	"instant_power": "电力", "heat_pollution_damage": "火热", "heart_power": "心力",
	"next_free_word": "流利", "flow": "流转", "next_compound": "复合", "energy_idle": "蓄能",
	"heat_overload_bonus_armed": "过热", "accel": "加速", "next_rapid": "急速",
	"heat_overload_bonus": "过热待触发",
	"next_double_draw": "超速", "next_overfire": "过火", "electric_overload": "电流过载",
	"fireproof": "防火", "blastproof": "防爆", "joint_funding": "合资", "profit_share": "分利",
	"next_energy_bonus": "蓄力", "gravity_always": "重力",
	"ceasefire": "停火", "serial": "连载", "repeat_zero": "反复", "split_mind": "精分",
	"vigor": "精力", "vigor_next": "精力待补", "auto_refill": "充电过热", "repeat": "重复",
	"next_serial_bonus": "连载待发", "next_draw_bonus": "额外补字",
	"linger_chance": "流连", "energy_regen": "回能", "force_once": "力",
	"block_next_turn": "甲", "energy_gain_once": "能", "link_draw_once": "连",
	"retaliate_once": "反", "energy_next_turn": "蓄", "payment_discount_once": "币",
	"combine_word_once": "合", "speed_word_once": "速", "energy_refund_once": "复",
	"solo_gain_once": "加", "next_gap": "超", "manual_draw": "精心", "shared_attack": "合击"
}

const LAYERED_ABILITIES := ["guard_inject", "counter", "next_energy_bonus", "next_serial_bonus", "vigor_next", "next_draw_bonus", "energy_regen", "force_once", "block_next_turn", "energy_gain_once", "link_draw_once", "retaliate_once", "energy_next_turn", "payment_discount_once", "combine_word_once", "speed_word_once", "energy_refund_once", "solo_gain_once"]
## 按层累计的能力与按收益数量累计的能力分别标注，不能统一显示为1层。
const STACKED_PASSIVES := ["heat_pollution_damage", "electric_overload", "electric_material", "longword_draw"]
const QUANTITY_PASSIVES := {"flow":"字", "energy_idle":"点", "serial":"点"}
## 主能力的参数由主能力详情承接，不另占图标。
const ABILITY_PARAMETERS := ["next_rapid_heat", "next_overfire_per", "heat_overload_bonus_armed"]

static func entry(id: String, name: String, glyph: String, stacks: int, description: String, color: Color, kind := 0, unit_label := "层") -> Dictionary:
	return {"id": id, "name": name, "glyph": glyph, "stacks": stacks, "description": BattleText.clean(description), "color": color, "kind": kind, "unit": unit_label}

static func collect(unit: Combatant, battle: BattleState = null) -> Array:
	var result: Array = []
	if unit.is_player:
		if unit.heat > 0:
			var heat := entry("heat", "热度", "火", unit.heat, "当前热度 %d / 热容 %d。超过热容会产生灼热字。" % [unit.heat, unit.heat_capacity], Palette.VERMILION_DK, 0, "点")
			heat["capacity"] = unit.heat_capacity
			result.append(heat)
		if unit.energy > 0:
			result.append(entry("energy", "储能", "电", unit.energy, "当前储能 %d，用于消耗储能的字与词效。" % unit.energy, Palette.INK, 0, "点"))
	for id in unit.statuses:
		var stacks := int(unit.statuses[id])
		if stacks == 0:
			continue
		var data := Database.get_status(str(id))
		if data != null:
			var description := EffectGlossary.status_description(str(id))
			if id == "vulnerable":
				description = EffectGlossary.vulnerable_damage_text()
			elif id == "heart_corrosion":
				description = "该敌人每次行动后受到%d点非攻击伤害，可被护盾吸收；层数不衰减。" % (stacks * BattleBalance.i("corrosion_per_stack", 1))
			if data.decay_per_turn > 0 and (id == "vulnerable" or (unit.is_player and id in ["poison", "regen"])):
				description += "\n每回合衰减 %d 层。" % data.decay_per_turn
			elif id == "vulnerable":
				description += "\n不按回合衰减。"
			result.append(entry(str(id), data.name, data.glyph, stacks, description, data.color, data.kind))
		else:
			result.append(entry(str(id), str(id), "状", stacks, "未配置状态说明。", Palette.GOLD))
	if unit.is_player:
		var permanent := maxi(unit.permanent_damage_reduction, GameState.permanent_damage_reduction)
		if permanent > 0:
			var description := "本场每次受到伤害时减免%d。" % unit.permanent_damage_reduction
			if permanent > unit.permanent_damage_reduction:
				description += "\n已获得本局永久减伤%d，从下一场战斗生效。" % permanent
			result.append(entry("permanent_guard", "永久减伤", "防", permanent, description, Palette.JADE))
		if unit.turn_damage_reduction > 0:
			result.append(entry("turn_guard", "御", "御", unit.turn_damage_reduction, "本回合每次受到伤害时减免 %d。" % unit.turn_damage_reduction, Palette.BLOCK))
		if unit.next_damage_reduction > 0:
			result.append(entry("guard_once", "御", "御", unit.next_damage_reduction, "下一次受到伤害减免 %d 点，触发后清除。" % unit.next_damage_reduction, Palette.BLOCK))
		if unit.turn_strength > 0:
			result.append(entry("turn_strength", "强", "强", unit.turn_strength, "本回合攻击每段伤害+%d，下回合开始清除。" % unit.turn_strength, Palette.GOLD))
		if unit.turn_damage_halve:
			result.append(entry("guard_halve", "放心", "心", 1, "本回合先用护盾吸收，剩余要扣生命的伤害除以%s，再减%d，最低0。" % [BattleBalance.f("guard_divisor", 2.0), BattleBalance.i("guard_flat", 1)], Palette.BLOCK))
		if unit.turn_damage_double:
			result.append(entry("turn_damage_double", "冷心", "冷", 1, "本回合攻击的基础伤害、力量与热力加成乘%d。" % BattleBalance.i("cold_attack_mult", 2), Palette.GOLD))
		if unit.no_block_turns > 0:
			result.append(entry("no_block", "无法获得防御", "禁", unit.no_block_turns, "含本回合，剩余%d回合不能获得新格挡或持久盾；已有护盾仍可吸收伤害。" % unit.no_block_turns, Palette.PLUM, StatusData.Kind.DEBUFF))
		var has_heart_ability := battle != null and battle.has_ability("heart_power")
		if unit.heart_power > 0 or has_heart_ability:
			var description := "每层可抵挡一次致命伤害。"
			if has_heart_ability:
				description += "\n本场每打出一颗【心】，获得%d层。" % BattleBalance.i("heart_per_use", 1)
			result.append(entry("heart_layers", "心力", "心", unit.heart_power, description, Palette.VERMILION))
		if battle != null:
			for id in battle.abilities:
				if str(id).begins_with("_") or id in ABILITY_PARAMETERS or id == "heart_power" or not battle.has_ability(id):
					continue
				var name: String = ABILITY_NAMES.get(id, "其他能力")
				var value := battle.ability_value(id)
				var word := Database.get_word_by_glyphs_string(name)
				var character := Database.get_character_by_glyph(name) if name.length() == 1 else null
				var description := word.describe() if word != null else (character.description if character != null else "持续能力已生效。")
				if id == "armor_plating":
					description = "每回合获得 %d 点格挡；格挡被击穿时碎裂。" % BattleBalance.i("armor_turn_block", 1)
				elif id == "guard_inject":
					description = "下次敌方塞字减少 %d 个。" % value
				elif id == "counter":
					description = "反击%d层。敌人全部行动后，攻击首个存活敌人一次，伤害=剩余临时格挡+%d。" % [value, value * BattleBalance.i("counter_per_stack", 3)]
				elif id == "next_energy_bonus" or id == "next_serial_bonus":
					description = "下一次攻击每段伤害+%d，可跨回合保留。" % value
				elif id == "next_draw_bonus":
					description = "本回合下一个词用掉字后，先补%d字再发动词效。" % value
				elif id == "vigor_next":
					description = "下回合开始时多补%d字。" % value
				elif id == "energy_regen":
					description = "之后%d回合开始时，各获得%d储能。同回合不重复发放。" % [value, BattleBalance.i("energy_regen", 2)]
				elif id == "retaliate_once":
					description = "本回合下次受敌人攻击后，对攻击者造成%d伤害。多段攻击只生效一次，被护盾全挡也生效。" % value
				elif id == "energy_next_turn":
					description = "下回合开始获得 %d 储能，仅一次。" % value
				elif id == "payment_discount_once":
					description = "本回合下次打出时铜钱费用-%d，最低0。付费成功后失效，免费或失败不消耗。" % value
				elif id == "combine_word_once":
					description = "本回合下一次成功组词后获得 %d 临时格挡、%d 储能；仅一次。" % [BattleBalance.i("combine_block", 2) * value, BattleBalance.i("combine_energy", 1) * value]
				elif id == "speed_word_once":
					description = "本回合下一次成功组词后补 %d 字、热度 +%d；仅一次。" % [BattleBalance.i("speed_draw", 2) * value, BattleBalance.i("speed_heat", 1) * value]
				elif id == "energy_refund_once":
					description = "本回合下次消耗储能时，返还至多%d点，不超过消耗量。" % value
				elif id == "solo_gain_once":
					description = "本回合下一枚单打字的首项伤害、格挡、治疗或储能+%d，不增加费用或热度。" % value
				elif id == "next_gap":
					description = "本回合下一个词可跨过1个横向或竖向空格，不能跨过有字的格子。"
				elif id == "next_overfire":
					description = "本回合下一次攻击按攻击时热度 × %d 追加伤害，仅整次追加一次。当前%d热度，对应追加%d伤害。" % [battle.ability_value("next_overfire_per", 3), unit.heat, unit.heat * battle.ability_value("next_overfire_per", 3)]
				elif id == "next_rapid":
					description = "本回合下一个词先补%d字再发动词效，热度+%d。" % [value, battle.ability_value("next_rapid_heat")]
				elif id == "next_double_draw":
					description = "本回合下一次补字最多额外补%d字，每额外1字升温%d；触发后消耗。" % [value, BattleBalance.i("double_draw_heat", 1)]
				elif id == "heat_overload_bonus":
					description = "本回合首次实际新增溢热污染后，下一次多字词额外补%d字。" % value
				elif id == "strong_heart":
					description = "心力已挡下%d次致命伤；每回合开始回复%d生命。" % [unit.heart_power_triggered, BattleBalance.i("strong_heart_base", 2) + BattleBalance.i("heart_trigger_heal", 1) * unit.heart_power_triggered]
				elif id == "heat_pollution_damage":
					description = "本场持续，当前%d层。每因溢热实际新增1枚灼热【热】，对首个存活敌人造成%d点非攻击伤害。抽到或移动旧【热】不触发。" % [value, value * BattleBalance.i("overheat_damage", 5)]
				elif id == "electric_overload":
					description = "本场持续，当前%d层。每因溢热实际新增1枚灼热【热】，获得%d储能，对首个存活敌人造成%d点非攻击伤害。" % [value, value * BattleBalance.i("overload_energy", 1), value * BattleBalance.i("overload_damage", 3)]
				elif id == "electric_material":
					description = "本场持续，当前%d层。每累计消耗%d储能，在空格生成至多%d枚临时【电】。没有空格则不生成。" % [value, BattleBalance.i("energy_spawn_step", 2), value]
				elif id == "longword_draw":
					description = "本场持续，当前%d层。每打出至少%d字的词，额外补%d字。" % [value, BattleBalance.i("long_word_threshold", 3), value * BattleBalance.i("longword_draw", 1)]
				elif id == "flow":
					description = "本回合每打出%d种不同的词，补%d字。【流转】也计数，重复词不计。重复施放累计补字数。" % [BattleBalance.i("flow_interval", 2), value]
				elif id == "energy_idle":
					description = "本场回合结束时，盘面还有可打出的词则获得%d储能。重复施放累计回合末收益。" % value
				elif id == "serial":
					description = "本场每打出%d个词，下一次攻击每段伤害+%d。重复施放累计奖励数值，奖励可跨回合保留。\n已打出%d词，还需%d词获得奖励。" % [BattleBalance.i("serial_interval", 3), value, battle.serial_words, BattleBalance.i("serial_interval", 3) - battle.serial_words % BattleBalance.i("serial_interval", 3)]
				elif id == "repeat":
					description += "\n" + ("本回合重演可用。" if battle.repeat_armed else "本回合已用，下回合恢复。")
				var layers := maxi(1, value) if id in LAYERED_ABILITIES or id in STACKED_PASSIVES else 1
				var label_unit := "层"
				if id in QUANTITY_PASSIVES:
					layers = value
					label_unit = QUANTITY_PASSIVES[id]
				if id in ["vigor_next", "next_draw_bonus", "next_double_draw", "next_rapid"]:
					layers = value
					label_unit = "字"
				result.append(entry("ability:" + id, name, name.substr(0, 1), layers, description, Palette.GOLD, 1 if id == "split_mind" else 0, label_unit))
			if battle.temporary_heat_capacity > 0:
				result.append(entry("temporary_heat_capacity", "载", "载", battle.temporary_heat_capacity, "本回合热容额外 +%d，下回合开始撤销；热度保持不变。" % battle.temporary_heat_capacity, Palette.GOLD))
			if not battle.reconnect_pending.is_empty():
				var glyphs: Array = battle.reconnect_pending.map(func(item): return "".join(item.inst.glyph_list()))
				result.append(entry("reconnect_pending", "重连待回", "连", battle.reconnect_pending.size(), "【%s】下回合返回原位，被占则找空格，满盘时继续等待。" % "、".join(glyphs), Palette.GOLD))
			for row in battle.flow_speed_rows:
				var remaining := int(battle.flow_speed_rows[row])
				result.append(entry("flow_speed:%d" % int(row), "流速·第 %d 行" % (int(row) + 1), "流", remaining, "本回合此行组词后原位补字，还可生效%d次。" % remaining, Palette.GOLD))
			if battle.base_draw_penalty > 0:
				result.append(entry("reload", "重载", "载", 1, "本场热容 %d；每回合基础补字减少 %d。" % [unit.heat_capacity, battle.base_draw_penalty], Palette.GOLD))
			if battle.next_draw_penalty > 0:
				result.append(entry("draw_penalty", "下回合少抽", "缓", battle.next_draw_penalty, "下回合基础补字减少 %d 字；结算后清除。" % battle.next_draw_penalty, Palette.PLUM, StatusData.Kind.DEBUFF, "字"))
			elif battle.next_draw_penalty < 0:
				result.append(entry("draw_bonus_next", "下回合多抽", "流", -battle.next_draw_penalty, "下回合基础补字增加 %d 字；结算后清除。" % -battle.next_draw_penalty, Palette.INK, StatusData.Kind.BUFF, "字"))
			if battle.manual_draw_pending > 0:
				result.append(entry("manual_draw_pending", "待选补字", "选", battle.manual_draw_pending, "本回合还有 %d 枚补字等待从字袋选择，随机落地。" % battle.manual_draw_pending, Palette.INK, StatusData.Kind.BUFF, "字"))
			if not battle.empowered_glyphs.is_empty():
				result.append(entry("empowered", "强化", "强", 1, "本场【%s】单独打出或参与成词时，都额外触发单字效果。" % "、".join(battle.empowered_glyphs.keys()), Palette.GOLD))
			if battle.bounty_paid:
				result.append(entry("bounty", "重金", "赏", 1, "本回合击败所有敌人后获得%d铜钱；尚余%d名敌人。" % [battle.bounty_reward, battle.alive_enemies().size()], Palette.GOLD))
	result.sort_custom(func(a: Dictionary, b: Dictionary):
		var priority_a := _priority(a)
		var priority_b := _priority(b)
		return str(a.id) < str(b.id) if priority_a == priority_b else priority_a < priority_b)
	return result


static func _priority(item: Dictionary) -> int:
	var resources := ["heat", "energy"]
	if item.id in resources: return resources.find(item.id) - 4
	if int(item.kind) == StatusData.Kind.DEBUFF: return 0
	if item.id in ["draw_bonus_next", "manual_draw_pending", "ability:vigor_next"]: return 1
	if str(item.id).begins_with("ability:next_") or item.id == "ability:double_next": return 2
	return 3
