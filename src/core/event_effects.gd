extends RefCounted
## 数据驱动的远征事件效果解释器。选项中需要删字时，先收集所有目标，再原子结算整组选项效果。

const CATALOG = preload("res://src/data/event_catalog.gd")
const SUPPORTED := [
	"damage", "heal", "heal_percent", "gold", "max_hp", "permanent_damage_reduction", "event_temp_hp", "spend_event_temp_hp", "clear_event_temp_hp",
	"gain_character", "gain_pollution", "remove_pollution", "gain_relic", "remove_relic", "remove_character", "if",
	"borrow_life", "repay_life_hp", "repay_life_max_hp", "refuse_debt", "spend_gold",
]


static func all() -> Array:
	return CATALOG.registered_events()


## 返回当前事件节点，并把寿债占位符换成当前数值。
static func node(event: Dictionary, node_id := "start") -> Dictionary:
	var raw: Dictionary = event
	if event.has("nodes"):
		var nodes: Dictionary = event.get("nodes", {})
		raw = nodes.get(node_id, nodes.get("start", {})).duplicate(true)
	var result: Dictionary = raw.duplicate(true)
	for key in ["id", "title", "illustration", "illustration_style", "acts", "tags", "allow_leave"]:
		if not result.has(key) and event.has(key): result[key] = event[key]
	result["body"] = resolve_text(str(result.get("body", "")))
	var options: Array = result.get("options", [])
	for option: Dictionary in options:
		option["text"] = resolve_text(str(option.get("text", "")))
	result["options"] = options
	return result


static func resolve_text(value: String) -> String:
	var debt := debt_amount()
	return value.replace("{debt}", str(debt)).replace("{debt_max}", str(int(ceil(debt / 2.0))))


## 当前幕可用的事件池。没有写 acts 的旧事件默认三幕都可出现。
static func pool(act: int) -> Array:
	return all().filter(func(event: Dictionary) -> bool:
		return (event.get("acts", [1, 2, 3]) as Array).has(act) and float(event.get("weight",1.0))>0 and condition_met(event.get("requires", {}))
	)


## 按幕抽取事件。exclude 中的 ID 会优先避开；如果全部用完则回退到完整池。
static func roll(act: int, rng: RandomNumberGenerator, exclude: Array = []) -> Dictionary:
	var candidates := pool(act)
	if not exclude.is_empty():
		var filtered: Array = candidates.filter(func(event: Dictionary) -> bool:
			return not exclude.has(str(event.get("id", "")))
		)
		if not filtered.is_empty():
			candidates = filtered
	if candidates.is_empty():
		return {}
	return choose(candidates,rng)


static func choose(candidates: Array, rng: RandomNumberGenerator) -> Dictionary:
	if candidates.is_empty(): return {}
	var total := 0.0
	for event: Dictionary in candidates: total += maxf(0,float(event.get("weight",1.0)))
	if total<=0: return {}
	var pick := rng.randf()*total
	for event: Dictionary in candidates:
		var weight := maxf(0,float(event.get("weight",1.0)))
		if weight<=0: continue
		pick -= weight
		if pick<=0: return event.duplicate(true)
	return candidates[-1].duplicate(true)


static func get_event(id: String) -> Dictionary:
	for event: Dictionary in all():
		if str(event.get("id", "")) == id:
			return event
	return {}


static func find_index(id: String) -> int:
	var catalog := all()
	for index in catalog.size():
		if str(catalog[index].get("id", "")) == id:
			return index
	return -1


static func valid_option(event: Dictionary, option_index: int) -> bool:
	var options: Array = event.get("options", [])
	return option_index >= 0 and option_index < options.size()


static func option_available(option: Dictionary) -> bool:
	if not condition_met(option.get("requires", {})): return false
	var effects: Array = option.get("effects", [])
	var plan := _removal_plan(effects)
	return plan.get("ok", false) and _can_complete_removal(effects, plan.get("counts", []), [])


static func condition_met(condition: Variant) -> bool:
	if condition == null or (condition is Dictionary and condition.is_empty()): return true
	if condition is Array:
		return (condition as Array).all(func(item): return condition_met(item))
	if not condition is Dictionary: return bool(condition)
	var data: Dictionary = condition
	if data.has("all"): return (data.get("all", []) as Array).all(func(item): return condition_met(item))
	if data.has("any"): return (data.get("any", []) as Array).any(func(item): return condition_met(item))
	if data.has("not"): return not condition_met(data.get("not"))
	match str(data.get("type", "")):
		"has_glyph": return GameState.glyph_counts().has(str(data.get("glyph", "")))
		"lacks_glyph": return not GameState.glyph_counts().has(str(data.get("glyph", "")))
		"has_relic": return GameState.has_relic(str(data.get("relic", "")))
		"lacks_relic": return not GameState.has_relic(str(data.get("relic", "")))
		"has_normal_relic_choice": return Relics.normal_pool().any(func(id): return not GameState.relics.has(id))
		"pollution_count_at_least": return GameState.deck.filter(func(inst): return inst.data != null and inst.data.is_pollution).size() >= int(data.get("amount", 1))
		"has_character_min_rarity": return GameState.deck.any(func(inst): return inst.data != null and not inst.data.is_pollution and inst.data.rarity >= int(data.get("amount", 0)))
		"gold_at_least": return GameState.gold >= int(data.get("amount", 0))
		"hp_at_most": return GameState.player_hp <= int(data.get("amount", GameState.player_hp))
		"event_temp_hp_at_least": return GameState.event_temp_hp >= int(data.get("amount", 0))
		"has_life_debt": return debt_amount() > 0
	return false


static func resolve(effects: Array, rng: RandomNumberGenerator, offer_relics := false) -> Dictionary:
	## 有目标选择的选项先返回待选数据；不产生任何副作用，取消选择可安全重选。
	var plan := _removal_plan(effects)
	if not plan.get("ok", false): return plan
	var removal_counts: Array = plan.counts
	if not _can_complete_removal(effects, removal_counts, []):
		return {"ok": false, "reason": "字袋中符合条件的字不足，无法完成这次删字"}
	var total := 0
	for count: int in removal_counts: total += count
	if total > 0:
		return {"ok": true, "pending": _pending(effects, removal_counts, [], total, offer_relics)}
	return _execute(effects, removal_counts, [], rng, offer_relics)


static func _removal_plan(effects: Array) -> Dictionary:
	var removal_counts: Array[int] = []
	for effect: Dictionary in effects:
		var kind := str(effect.get("type", ""))
		if kind not in SUPPORTED:
			return {"ok": false, "reason": "不支持的事件效果：%s" % kind}
		if kind == "if":
			var nested := _validate_nested(effect.get("then", []))
			if not nested.get("ok", false): return nested
			nested = _validate_nested(effect.get("else", []))
			if not nested.get("ok", false): return nested
		var count := 0
		if kind == "remove_character":
			count = maxi(1, int(effect.get("count", 1)))
		removal_counts.append(count)
	return {"ok": true, "counts": removal_counts}


static func resume(pending: Dictionary, glyph: String, rng: RandomNumberGenerator, offer_relics := false) -> Dictionary:
	if str(pending.get("type", "")) != "remove_character" or not (pending.get("glyphs", []) as Array).has(glyph):
		return {"ok": false, "reason": "无效删字选择"}
	var plan := _removal_plan(pending.get("effects", []))
	if not plan.get("ok", false) or plan.get("counts", []) != pending.get("removal_counts", []):
		return {"ok": false, "reason": "删字条件已变化，请取消后重新选择"}
	var selected: Array = pending.get("selected", []).duplicate()
	var total := 0
	for count: int in plan.counts: total += count
	if int(pending.get("remaining", 0)) <= 0 or selected.size() + int(pending.get("remaining", 0)) != total:
		return {"ok": false, "reason": "删字进度已失效，请取消后重新选择"}
	selected.append(glyph)
	if not _can_complete_removal(pending.get("effects", []), pending.get("removal_counts", []), selected):
		return {"ok": false, "reason": "可删除的字已变化，请取消后重新选择"}
	var remaining := int(pending.get("remaining", 0)) - 1
	offer_relics = offer_relics or bool(pending.get("offer_relics", false))
	if remaining > 0:
		return {"ok": true, "pending": _pending(pending.get("effects", []), pending.get("removal_counts", []), selected, remaining, offer_relics)}
	return _execute(pending.get("effects", []), pending.get("removal_counts", []), selected, rng, offer_relics)


static func _pending(effects: Array, removal_counts: Array, selected: Array, remaining: int, offer_relics := false) -> Dictionary:
	var counts := remaining_counts({"selected": selected})
	# Only offer a choice if the rest of the required targets can still be filled.
	var glyphs: Array = counts.keys().filter(func(g):
		return int(counts[g]) > 0 and _can_complete_removal(effects, removal_counts, selected + [g]))
	return {"type": "remove_character", "effects": effects.duplicate(true), "removal_counts": removal_counts.duplicate(),
		"selected": selected.duplicate(), "remaining": remaining, "glyphs": glyphs, "offer_relics": offer_relics}


static func remaining_counts(pending: Dictionary) -> Dictionary:
	var counts := GameState.glyph_counts()
	for glyph in pending.get("selected", []):
		counts[str(glyph)] = maxi(0, int(counts.get(str(glyph), 0)) - 1)
	return counts


static func _removal_matches(character: CharacterData, effect: Dictionary) -> bool:
	if character == null: return false
	if not effect.has("min_rarity") and not effect.has("max_rarity"): return true
	return not character.is_pollution and character.rarity >= int(effect.get("min_rarity", 0)) and character.rarity <= int(effect.get("max_rarity", 4))


static func _can_complete_removal(effects: Array, counts: Array, selected: Array) -> bool:
	var targets: Array = []
	for i in mini(effects.size(), counts.size()):
		if targets.size() + int(counts[i]) > GameState.deck_size(): return false
		for _n in int(counts[i]): targets.append(effects[i])
	if selected.size() > targets.size() or targets.size() > GameState.deck_size(): return false
	if targets.is_empty(): return true
	var available := GameState.glyph_counts()
	var reserved := {}
	for i in selected.size():
		var glyph := str(selected[i])
		if int(available.get(glyph, 0)) <= 0 or not _removal_matches(Database.get_character_by_glyph(glyph), targets[i]): return false
		available[glyph] -= 1
		reserved[glyph] = int(reserved.get(glyph, 0)) + 1
	var candidates: Array = []
	for inst: CharInstance in GameState.deck:
		var glyph := inst.glyph()
		if int(reserved.get(glyph, 0)) > 0: reserved[glyph] -= 1
		else: candidates.append(inst.data)
	var assigned: Array = []
	assigned.resize(candidates.size()); assigned.fill(-1)
	for i in range(selected.size(), targets.size()):
		if not _match_removal(i, targets, candidates, assigned, {}): return false
	return true


## Small bipartite match: overlapping rarity filters must not reserve the same entity twice.
static func _match_removal(index: int, targets: Array, candidates: Array, assigned: Array, seen: Dictionary) -> bool:
	for i in candidates.size():
		if seen.has(i) or not _removal_matches(candidates[i], targets[index]): continue
		seen[i] = true
		if int(assigned[i]) < 0 or _match_removal(int(assigned[i]), targets, candidates, assigned, seen):
			assigned[i] = index
			return true
	return false


static func _execute(effects: Array, removal_counts: Array, selected: Array, rng: RandomNumberGenerator, offer_relics := false, reserved: Array = []) -> Dictionary:
	# Random finds are revealed before pickup. Costs and other option effects settle once.
	# Explicitly named relic options retain their stated pickup effect.
	var relic_offers: Array = []
	var notes: Array = []          # 结算后的旁白（选项不提前剧透，选完才告知）
	var selected_index := 0
	for index in effects.size():
		var effect: Dictionary = effects[index]
		var amount := int(effect.get("amount", 0))
		match str(effect.get("type", "")):
			"damage": GameState.damage(maxi(0, amount))
			"heal": GameState.heal(maxi(0, amount))
			"heal_percent":
				GameState.heal(maxi(0, int(round(GameState.player_max_hp * amount / 100.0))))
			"gold": GameState.add_gold(amount)
			"spend_gold":
				if amount <= 0 or not GameState.spend_gold(amount):
					return {"ok": false, "reason": "铜钱不足"}
			"max_hp":
				GameState.player_max_hp = maxi(1, GameState.player_max_hp + amount)
				GameState.player_hp = mini(GameState.player_hp, GameState.player_max_hp)
				EventBus.hp_changed.emit(GameState.player_hp, GameState.player_max_hp)
			"permanent_damage_reduction": GameState.permanent_damage_reduction = maxi(0, GameState.permanent_damage_reduction + amount)
			"event_temp_hp": GameState.add_event_temp_hp(amount)
			"spend_event_temp_hp": GameState.spend_event_temp_hp(amount)
			"clear_event_temp_hp": GameState.clear_event_temp_hp()
			"borrow_life":
				var debt := maxi(1, amount)
				if not GameState.has_relic("life_debt"): GameState.add_relic("life_debt")
				GameState.relic_counters["life_debt"] = debt_amount() + debt
				GameState.heal(debt)
				schedule_event("debt_collector")
			"repay_life_hp":
				var debt := debt_amount()
				if debt <= 0:
					GameState.remove_relic("life_debt")
				else:
					var paid := mini(maxi(0, GameState.player_hp - 1), debt)
					GameState.player_hp -= paid
					var remaining := debt - paid
					if remaining > 0:
						GameState.player_max_hp = maxi(1, GameState.player_max_hp - int(ceil(remaining / 2.0)))
						GameState.player_hp = mini(GameState.player_hp, GameState.player_max_hp)
					EventBus.hp_changed.emit(GameState.player_hp, GameState.player_max_hp)
					GameState.remove_relic("life_debt")
			"repay_life_max_hp":
				var debt := debt_amount()
				if debt <= 0:
					GameState.remove_relic("life_debt")
				else:
					GameState.player_max_hp = maxi(1, GameState.player_max_hp - int(ceil(debt / 2.0)))
					GameState.player_hp = mini(GameState.player_hp, GameState.player_max_hp)
					EventBus.hp_changed.emit(GameState.player_hp, GameState.player_max_hp)
					GameState.remove_relic("life_debt")
			"refuse_debt":
				if not GameState.has_relic("life_debt"): GameState.add_relic("life_debt")
				GameState.relic_counters["life_debt"] = debt_amount() + maxi(1, amount)
				schedule_event("debt_collector")
			"if":
				var branch: Array = effect.get("then", []) if condition_met(effect.get("condition", {})) else effect.get("else", [])
				var branch_counts: Array[int] = []
				for _branch_effect in branch: branch_counts.append(0)
				var branch_result := _execute(branch, branch_counts, [], rng, offer_relics, reserved + relic_offers)
				if not branch_result.get("ok", false): return branch_result
				relic_offers.append_array(branch_result.get("relic_offers", []))
			"gain_character":
				var character: CharacterData = _specific_character(str(effect.get("glyph", "")))
				if character == null:
					character = _random_character(
						int(effect.get("min_rarity", 0)), int(effect.get("max_rarity", 4)), rng
					)
				if character == null:
					return {"ok": false, "reason": "事件字库为空"}
				GameState.add_character(character, maxi(1, int(effect.get("count", 1))))
			"gain_pollution":
				var pollution_id := str(effect.get("character", "pollution"))
				var pollution: CharacterData = Database.get_character(pollution_id)
				if pollution == null or not pollution.is_pollution:
					return {"ok": false, "reason": "污染字资源缺失：%s" % pollution_id}
				GameState.add_character(pollution, maxi(1, int(effect.get("count", 1))))
			"remove_pollution":
				var pollution_uids: Array[int] = []
				for inst: CharInstance in GameState.deck:
					if inst.data != null and inst.data.is_pollution: pollution_uids.append(inst.uid)
				for i in mini(maxi(1, int(effect.get("count", 1))), pollution_uids.size()):
					GameState.remove_by_uid(pollution_uids[i])
			"gain_relic":
				var relic_id := str(effect.get("relic", ""))
				var relic_pool := str(effect.get("pool", "normal"))
				var chance := clampf(float(effect.get("chance", 1.0)), 0.0, 1.0)
				if chance < 1.0 and rng.randf() >= chance:
					var fallback := int(effect.get("fallback_gold", 0))
					if fallback > 0:
						GameState.add_gold(fallback)
						notes.append("开椟（未得遗物，返还 %d 铜钱）" % fallback)
					else:
						notes.append("开椟（空手而归）")
					continue
				if relic_id == "random":
					var choices: Array = Relics.roll_choices(GameState.relics + reserved + relic_offers, rng, 1, relic_pool)
					relic_id = str(choices[0]) if not choices.is_empty() else ""
					if offer_relics and not relic_id.is_empty():
						relic_offers.append(relic_id)
						continue
				if relic_id.is_empty() or not GameState.add_relic(relic_id):
					var fallback2 := int(effect.get("fallback_gold", 0))
					if fallback2 > 0:
						GameState.add_gold(fallback2)
						notes.append("开椟（未得遗物，返还 %d 铜钱）" % fallback2)
					else: return {"ok": false, "reason": "没有可获得的遗物"}
				else:
					if Relics.needs_bind(relic_id):
						for inst: CharInstance in GameState.deck:
							if GameState.bind_relic(relic_id, inst.id()): break
					# 泥金笔 / 复字拓片 / 许愿笺：事件里来不及弹窗，回到能弹窗的界面再补
					Relics.queue_setup(relic_id)
			"remove_relic":
				if not GameState.remove_relic(str(effect.get("relic", ""))):
					return {"ok": false, "reason": "没有这件可献出的遗物"}
			"remove_character":
				var count := int(removal_counts[index]) if index < removal_counts.size() else 0
				for _i in count:
					if selected_index >= selected.size(): return {"ok": false, "reason": "事件删字目标不足"}
					var character: CharacterData = Database.get_character_by_glyph(str(selected[selected_index]))
					if character == null or not GameState.remove_character_id(character.id):
						return {"ok": false, "reason": "所选字已不存在"}
					selected_index += 1
	return {"ok": true, "pending": {}, "relic_offers": relic_offers, "notes": notes}


static func debt_amount() -> int:
	return int(GameState.relic_counters.get("life_debt", 0))


## 把后续事件塞回当前幕的事件袋；事件分发由庭院运行态维护。
static func schedule_event(event_id: String) -> void:
	var run = GameState.room_run
	if run == null: return
	var bags = run.get("event_bags")
	if not bags is Dictionary: return
	var key := str(GameState.act_index)
	var ids: Array = bags.get(key, [])
	if not ids.has(event_id): ids.append(event_id)
	bags[key] = ids


static func _validate_nested(effects: Array) -> Dictionary:
	for effect: Dictionary in effects:
		var kind := str(effect.get("type", ""))
		if kind not in SUPPORTED or kind == "remove_character" or kind == "if":
			return {"ok": false, "reason": "条件效果不支持此嵌套效果：%s" % kind}
	return {"ok": true}


static func _specific_character(glyph: String) -> CharacterData:
	if glyph.is_empty():
		return null
	var character: CharacterData = Database.get_character_by_glyph(glyph)
	if character == null or character.is_pollution or character.pending_design:
		return null
	return character


static func _random_character(min_rarity: int, max_rarity: int, rng: RandomNumberGenerator) -> CharacterData:
	var pool: Array = []
	for character: CharacterData in Database.characters.values():
		if character.is_pollution or character.pending_design or character.tags.has("enemy") or character.tags.has("彩蛋") or character.tags.has("event"):
			continue
		if character.rarity >= min_rarity and character.rarity <= max_rarity:
			pool.append(character)
	if pool.is_empty():
		for character: CharacterData in Database.characters.values():
			if not character.is_pollution and not character.pending_design and not character.tags.has("enemy") and not character.tags.has("彩蛋"):
				pool.append(character)
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]
