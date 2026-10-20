extends RefCounted
class_name EffectHandlersActions
## 复杂词效的具体实现：盘面改造、融合/叠层、揭示与回收、持续能力等。

const CREMATE_FLAVOR := [
	"……走好。",
	"烧得很干净。",
	"这词到底有什么用？",
	"尘归尘，土归土。",
	"至少它很上镜。",
	"建议配合【热】一起使用（开玩笑的）。",
	"亡者安息。",
]

## 预览不取牌、不洗牌、不支付。所有多阶段选择确认后再统一结算。
static func deploy_candidates(b: BattleState) -> Array:
	return EffectTargets.deploy_candidates(b)

static func discard_candidate(b: BattleState, target: Dictionary) -> CharInstance:
	return EffectTargets.discard_candidate(b, target)

static func validate_word_target(b: BattleState, handler: String, path: Array, target: Dictionary) -> String:
	var effect := EffectData.new()
	effect.handler = handler
	return EffectRegistry.validate(effect, b, path, target)

static func scatter_word_copy(b: BattleState, glyphs: Array) -> void:
	var spaces := b.board.empty_indices()
	b._shuffle(spaces)
	var count := 0
	for glyph in glyphs:
		if spaces.is_empty():
			break
		var data := Database.get_character_by_glyph(str(glyph))
		if data == null:
			continue
		var copy := CharInstance.new(data)
		copy.temporary = true
		b.board.set_xy(spaces.pop_back(), copy)
		b.temp_chars.append(copy)
		count += 1
	b._log("反复：将【%s】的 %d 枚临时字分别放入随机空格" % ["".join(glyphs), count])

static func _divert_junk(b: BattleState, ctx: Dictionary) -> Array:
	var count := 0
	for pos in (ctx.get("target", {}) as Dictionary).get("cells", []):
		var inst := b.board.get_xy(pos)
		if count >= BattleBalance.i("divert_limit", 2) or not BattleState.is_refinable_junk(inst):
			continue
		b.board.clear_xy(pos)
		b.temp_chars.erase(inst)
		count += 1
	return ["分流：移除 %d 枚杂字" % count]

static func _buyback(b: BattleState, ctx: Dictionary) -> Array:
	var target: Dictionary = ctx.get("target", {})
	var inst := discard_candidate(b, target)
	var pos: Vector2i = target.get("tile", Vector2i(-1, -1))
	if inst == null or not b.board.in_bounds(pos.x, pos.y) or b.board.get_xy(pos) != null:
		return ["回购：没有可放入的弃字或空格，未支付"]
	var due := EffectUtil.discounted_cost(b, BattleBalance.i("buy_cost", 2))
	if EffectUtil.available(b) < due:
		return ["回购：支付额不足"]
	b.take_from_discard_by_uid(inst.uid)
	b.place_from_pool(pos, inst)
	inst.temporary_uses += 1
	EffectUtil.pay(b, BattleBalance.i("buy_cost", 2))
	b.record_draw(1)
	return ["回购：实际支付%d，原实体【%s】补入指定格，额外使用+1" % [due, inst.glyph()]]

static func _merge_duplicates(b: BattleState, ctx: Dictionary) -> Array:
	var anchor: Vector2i = EffectUtil.tile(ctx)
	var inst: CharInstance = b.board.get_xy(anchor)
	if inst == null or inst.pinned or not inst.is_player_owned():
		return ["重合：目标格没有字"]
	var glyph := inst.glyph()
	var tiles: Array = []
	for i in b.board.cells.size():
		var c: CharInstance = b.board.cells[i]
		if c != null and not c.pinned and c.glyph_list() == inst.glyph_list() and c.is_player_owned():
			tiles.append(b.board.to_xy(i))
	if tiles.size() < 2:
		return ["重合：没有重复的己方【%s】" % glyph]
	var total := 0
	for pos in tiles:
		var c: CharInstance = b.board.get_xy(pos)
		total += 1 + c.temporary_uses
	for pos in tiles:
		if pos == anchor:
			continue
		var c: CharInstance = b.board.get_xy(pos)
		b.bag.append(c)
		b.board.clear_xy(pos)
	inst.temporary_uses = total - 1
	b._shuffle(b.bag)
	return ["重合：保留 1 枚【%s】，获得 %d 次临时使用，其余 %d 枚回字袋" % [glyph, total - 1, tiles.size() - 1]]

static func _replay_last_attack(b: BattleState) -> Array:
	if b.last_attack_word == null or b.last_attack_effects.is_empty():
		return ["连击：此前没有可重演的即时攻击"]
	var msgs: Array = []
	# 刻刀（打击增强）：重演不算「带【击】」的出字
	var strike_was := b.strike_active
	b.strike_active = false
	for e in b.last_attack_effects:
		if e.handler == "replay_last_attack" or e.timing == "persistent":
			continue  # 禁止递归
		var sub := {"battle": b, "source": b.player, "glyphs": b.last_attack_glyphs,
			"target": b.last_attack_target_data, "target_index": b.last_attack_target,
			"path": b.last_attack_path, "word": b.last_attack_word, "consumed": []}
		msgs.append_array(EffectResolver.resolve_all([e], sub))
	b.strike_active = strike_was
	if msgs.is_empty():
		msgs.append("连击：重演【%s】" % b.last_attack_word.word)
	return msgs


## 回放：把上一个词用过的字放回盘面（原格优先，被占则找空格）。
static func _replay_word(b: BattleState) -> Array:
	if b.last_played_consumed.is_empty():
		return ["回放：此前没有可回放的词"]
	var placed := 0
	for item in b.last_played_consumed:
		var inst: CharInstance = item["inst"]
		if item.get("kind", "real") in ["layer", "pinned"] or inst.pinned or b.board.cells.has(inst):
			continue
		if inst.temporary or not inst.is_player_owned() or not (b.discard.has(inst) or b.bag.has(inst)):
			continue
		var pos: Vector2i = item["pos"]
		if b.board.get_xy(pos) != null:
			var empties: Array = b.board.empty_indices()
			if empties.is_empty():
				break
			pos = empties[0]
		b.discard.erase(inst)
		b.bag.erase(inst)
		b.consumed_this_turn.erase(inst)
		inst.owner = CharInstance.Owner.PLAYER
		b.place_from_pool(pos, inst)
		placed += 1
	return ["回放：将上一个词用过的 %d 枚字放回盘面" % placed]


## 放回：移除字盘上一枚敌方实体字，将其退回（不造成伤害、不触发污染）。
static func _return_enemy(b: BattleState, ctx: Dictionary) -> Array:
	var pos: Vector2i = EffectUtil.tile(ctx)
	var inst: CharInstance = b.board.get_xy(pos)
	if inst == null or not inst.is_enemy_owned():
		return ["放回：请选择一枚敌方实体字"]
	b.temp_chars.erase(inst)
	b.board.set_xy(pos, null)
	return ["放回：将敌方【%s】退回" % inst.glyph()]

static func _recover_consumed(b: BattleState, ctx: Dictionary) -> Array:
	var inst := b.recoverable_card(ctx.get("target", {}))
	if inst == null:
		return ["回收：所选字已不在本回合可回收的弃字堆中"]
	b.take_from_discard_by_uid(inst.uid)
	b.bag.append(inst)   # 放回抽字袋顶（原型：袋顶=数组尾）
	return ["回收：把【%s】放回抽字袋顶" % inst.glyph()]

## 重回只恢复本词之前的消耗；移动原实体，保持最近的一枚在袋顶。
static func _recover_recent(b: BattleState, ctx: Dictionary, limit: int) -> Array:
	var excluded := {}
	for item in ctx.get("consumed", []):
		excluded[item.inst.uid] = true
	var chosen: Array = []
	var seen := {}
	var candidates := b.recoverable_consumed()
	for i in range(candidates.size() - 1, -1, -1):
		var inst: CharInstance = candidates[i]
		if excluded.has(inst.uid) or seen.has(inst.uid):
			continue
		seen[inst.uid] = true
		chosen.append(inst)
		if chosen.size() >= limit:
			break
	for i in range(chosen.size() - 1, -1, -1):
		var inst: CharInstance = chosen[i]
		b.take_from_discard_by_uid(inst.uid)
		b.bag.append(inst)
	return ["重回：把此前最近消耗的 %d 枚己方实体字放回字袋顶" % chosen.size()]

## 分/铸/炼共用四邻选择；强化触发时自动挑选仍在盘面上的合法邻字。
static func _solo_neighbor_action(b: BattleState, ctx: Dictionary, handler: String) -> Array:
	var name: String = {"split_neighbor": "分", "recast_neighbor": "铸", "refine_junk_neighbor": "炼"}[handler]
	var path: Array = ctx.get("path", [])
	if path.is_empty():
		return ["%s：没有相邻目标" % name]
	var origin: Vector2i = path[0]
	var candidates: Array = []
	for pos in b.board.neighbors(origin):
		var inst := b.board.get_xy(pos)
		if inst == null:
			continue
		match handler:
			"split_neighbor":
				if inst.is_player_owned():
					candidates.append(pos)
			"recast_neighbor":
				if inst.is_player_owned() and not inst.temporary and not inst.pinned:
					candidates.append(pos)
			"refine_junk_neighbor":
				if BattleState.is_refinable_junk(inst):
					candidates.append(pos)
	var chosen: Vector2i = (ctx.get("target", {}) as Dictionary).get("tile", Vector2i(-1, -1))
	if ctx.get("word") != null and not candidates.has(chosen) and not candidates.is_empty():
		chosen = candidates[0]
	if not candidates.has(chosen):
		return ["%s：四邻没有有效目标，只弃掉本字" % name]
	var target := b.board.get_xy(chosen)
	match handler:
		"split_neighbor":
			if b.board.get_xy(origin) != null:
				return ["分：原格未腾空，未生成复制"]
			var copy := CharInstance.new(target.data)
			copy.temporary = true
			copy.word_only = true
			b.board.set_xy(origin, copy)
			b.temp_chars.append(copy)
			return ["分：原格生成临时【%s】，仅供组词，单独打出只弃掉" % copy.glyph()]
		"recast_neighbor":
			var excluded: Array = [target]
			for item in ctx.get("consumed", []):
				excluded.append(item.inst)
			var replacement := BattleOps.take_real_replacement(b, excluded)
			if replacement == null:
				return ["铸：字袋及弃字堆没有其他可替换的实体，保留目标字"]
			b.place_from_pool(chosen, replacement)
			b.bag.append(target)
			b._shuffle(b.bag)
			b.record_draw(1, 1, excluded)
			return ["铸：将原实体【%s】放回字袋，原格换为【%s】" % [target.glyph(), replacement.glyph()]]
		"refine_junk_neighbor":
			b.board.clear_xy(chosen)
			b.temp_chars.erase(target)
			var earned := b.earn_gold(BattleBalance.i("refine_junk_gold", 1))
			b.add_heat(BattleBalance.i("refine_junk_heat", 1))
			return ["炼：移除杂字【%s】，获得 %d 铜钱、热度 +1" % [target.glyph(), earned]]
	return []

## 精/购移动选定原实体；候选预览不改变字袋，只有确认成功才记补字或支付。
static func _solo_bag_draw(b: BattleState, ctx: Dictionary, handler: String) -> Array:
	var name := "精" if handler == "precision_draw" else "购"
	var path: Array = ctx.get("path", [])
	var consumed: Array = ctx.get("consumed", [])
	if path.is_empty() or consumed.is_empty() or b.board.get_xy(path[0]) != null:
		return ["%s：原格未腾空，未补字" % name]
	var source: CharInstance = consumed[0].inst
	# 强化融合牌时按附带字的效果查候选，而非主字的 solo_handler。
	var candidates := b.solo_bag_candidates(source, handler)
	var chosen_uid := int((ctx.get("target", {}) as Dictionary).get("bag_uid", -1))
	var chosen: CharInstance = null
	for inst in candidates:
		if inst.uid == chosen_uid:
			chosen = inst
			break
	if chosen == null and ctx.get("word") != null and not candidates.is_empty():
		chosen = candidates[0] # 强化附效自动选择；无目标的普通单字不偷选另一张牌。
	if chosen == null:
		return ["%s：字袋没有可选实体，只弃掉本字" % name]
	var due := EffectUtil.discounted_cost(b, BattleBalance.i("buy_cost", 2)) if handler == "buy_bag_solo" else 0
	if handler == "buy_bag_solo" and EffectUtil.available(b) < due:
		return ["购：支付额不足，未补字"]
	var index := b.bag.find(chosen)
	b.bag.remove_at(index)
	b.place_from_pool(path[0], chosen) # 先占住落点，支付触发电能时不会占用它。
	if handler == "buy_bag_solo" and not EffectUtil.pay(b, BattleBalance.i("buy_cost", 2)):
		b.board.clear_xy(path[0])
		b.bag.insert(index, chosen)
		return ["购：支付失败，保留字袋实体"]
	var excluded: Array = consumed.map(func(item): return item.inst)
	b.record_draw(1, 1, excluded)
	var selection_note := "二选一，" if candidates.size() >= 2 else "只有一枚候选，"
	return ["%s：%s在原格补入【%s】" % [name, "支付 %d，" % due if handler == "buy_bag_solo" else selection_note, "".join(chosen.glyph_list())]]

static func _cleanse_adjacent(b: BattleState, ctx: Dictionary, all_tags := false) -> Array:
	var name := "洗" if all_tags else "清"
	var path: Array = ctx.get("path", [])
	if path.is_empty():
		return ["%s：没有相邻目标" % name]
	var neighbors := b.board.neighbors(path[0])
	var target: Dictionary = ctx.get("target", {})
	var chosen: Vector2i = target.get("tile", Vector2i(-1, -1))
	# 强化触发单字时，以参与字的原格为中心自动选一枚邻字。
	if ctx.get("word") != null and (not neighbors.has(chosen) or b.board.get_xy(chosen) == null or b.board.get_xy(chosen).pollutions.is_empty()):
		chosen = Vector2i(-1, -1)
		for pos in neighbors:
			var candidate := b.board.get_xy(pos)
			if candidate != null and not candidate.pollutions.is_empty():
				chosen = pos
				break
	var inst := b.board.get_xy(chosen)
	if not neighbors.has(chosen) or inst == null or inst.pollutions.is_empty():
		return ["%s：四邻没有可净化的污染" % name]
	var n := inst.pollutions.size() if all_tags else 1
	if b.achievement != null: b.achievement.emit_metrics([{"metric": "pollution_cleansed", "amount": n}])
	if all_tags:
		inst.clear_pollutions()
	else:
		inst.pollutions.remove_at(0)
	if inst.pollutions.is_empty():
		Relics.on_cleansed(b, 1)
	return ["%s：清除【%s】的 %d 个污染标签（保留原字与归属）" % [name, inst.glyph(), n]]

static func _move_neighbor(b: BattleState, ctx: Dictionary) -> Array:
	var path: Array = ctx.get("path", [])
	if path.is_empty() or b.board.get_xy(path[0]) != null:
		return ["转：原格未腾空，未移动"]
	var origin: Vector2i = path[0]
	var chosen: Vector2i = (ctx.get("target", {}) as Dictionary).get("tile", Vector2i(-1, -1))
	var inst := b.board.get_xy(chosen)
	if ctx.get("word") != null and (not b.board.is_adjacent(origin, chosen) or inst == null or inst.pinned):
		for pos in b.board.neighbors(origin):
			var candidate := b.board.get_xy(pos)
			if candidate != null and not candidate.pinned:
				chosen = pos
				inst = candidate
				break
	if inst == null or inst.pinned or not b.board.is_adjacent(origin, chosen):
		return ["转：四邻没有可移动的字"]
	b.board.set_xy(chosen, null)
	b.board.set_xy(origin, inst)
	return ["转：把相邻【%s】移入原格" % "".join(inst.glyph_list())]

static func _throw_neighbor(b: BattleState, ctx: Dictionary) -> Array:
	var path: Array = ctx.get("path", [])
	var t: Dictionary = (ctx.get("target", {}) as Dictionary).duplicate()
	# 强化投作为成词附加效果时，自动选择一枚剩余邻字与空格。
	if not path.is_empty() and ctx.get("word") != null:
		var from: Vector2i = t.get("tile", Vector2i(-1, -1))
		var to: Vector2i = t.get("tile2", Vector2i(-1, -1))
		var selected := b.board.get_xy(from)
		if selected == null or selected.pinned or not b.board.is_adjacent(path[0], from) or not b.board.in_bounds(to.x, to.y) or b.board.get_xy(to) != null:
			var empties := b.board.empty_indices()
			for pos in b.board.neighbors(path[0]):
				var candidate := b.board.get_xy(pos)
				if candidate != null and not candidate.pinned and not empties.is_empty():
					t = {"tile": pos, "tile2": empties[0]}
					break
	if path.is_empty() or not t.has("tile") or not t.has("tile2"):
		return ["投：没有可用目标或空格，未移动"]
	var inst := b.board.get_xy(t.tile)
	if inst == null or inst.pinned or not b.board.is_adjacent(path[0], t.tile) or b.board.get_xy(t.tile2) != null:
		return ["投：目标或空格已改变，未移动、未支付"]
	if t.has("throw_uid") and inst.uid != int(t.throw_uid):
		return ["投：目标实体已改变，未移动、未支付"]
	var due := EffectUtil.discounted_cost(b, BattleBalance.i("throw_cost", 1))
	if not EffectUtil.pay(b, BattleBalance.i("throw_cost", 1)):
		return ["投：支付额不足，未移动"]
	b.board.set_xy(t.tile, null)
	b.board.set_xy(t.tile2, inst)
	return ["投：支付 %d，将【%s】投到空格" % [due, "".join(inst.glyph_list())]]

static func _capture_glyph(b: BattleState, ctx: Dictionary, cost: int) -> Array:
	var tile: Vector2i = ctx.get("target", {}).get("enemy_glyph", EffectUtil.tile(ctx))
	var inst: CharInstance = b.board.get_xy(tile)
	if inst == null or not inst.is_enemy_owned():
		return ["收购：请选择一枚敌方实体字"]
	if not EffectUtil.pay(b, cost):
		return ["收购：支付额不足（需 %d）" % cost]
	inst.owner = CharInstance.Owner.PLAYER
	inst.clear_pollutions()
	b.board.clear_xy(tile)
	b.captured_chars.append(inst)
	return ["收购：支付 %d 铜钱，永久收编【%s】" % [cost, inst.glyph()]]

static func _empower_glyph(b: BattleState, ctx: Dictionary) -> Array:
	var g: String = str(ctx.get("target", {}).get("empower_glyph", ""))
	if g.is_empty():
		return ["强化：请选择一个字"]
	b.empowered_glyphs[g] = true
	return ["强化：本场【%s】被打出时额外触发其单字效果" % g]

static func _refine_remove(b: BattleState, ctx: Dictionary, eff: EffectData) -> Array:
	var heat_down: int = int(eff.args.get("heat", 3))
	var gold_up: int = int(eff.args.get("gold", 4))
	b.add_heat(-heat_down)
	EffectUtil.add_gold(b, gold_up)
	var msgs: Array = ["炼化：热度 -%d，获得 %d 铜钱" % [heat_down, gold_up]]
	var g: String = str(ctx.get("target", {}).get("remove_glyph", ""))
	var removed: CharInstance = b.remove_from_battle_glyph(g)
	if removed != null:
		msgs.append("将【%s】移出本场战斗循环（战后回归）" % g)
	else:
		msgs.append("（未指定要移除的牌）")
	return msgs

static func _cremate(b: BattleState, ctx: Dictionary, _eff: EffectData) -> Array:
	var path: Array = ctx.get("path", [])
	var glyphs: Array = ctx.get("glyphs", [])
	if path.is_empty():
		return ["火化：无处安放骨灰"]
	var new_glyphs: Array = ["骨", "灰"]
	var placed: Array = []
	for i in path.size():
		var pos: Vector2i = path[i]
		if i >= new_glyphs.size():
			continue
		if b.board.get_xy(pos) != null:
			continue
		var ci: CharInstance = b.create_temp_glyph(new_glyphs[i])
		if ci == null:
			continue
		b.board.set_xy(pos, ci)
		placed.append(new_glyphs[i])
	if placed.is_empty():
		return ["火化：没有留下骨灰"]
	var line: String = CREMATE_FLAVOR[b.visual_rng.randi_range(0, CREMATE_FLAVOR.size() - 1)]
	return ["火化：【%s】原地化为【%s】。%s" % ["".join(glyphs), "".join(placed), line]]

static func _fuse_cards(b: BattleState, ctx: Dictionary) -> Array:
	var t: Dictionary = ctx.get("target", {})
	var p1: Vector2i = t.get("tile", Vector2i(-1, -1))
	var p2: Vector2i = t.get("tile2", Vector2i(-1, -1))
	var res: Dictionary = b.fuse_cards(p1, p2)
	return [str(res.get("msg", "化合失败"))]

static func _refine_layer(b: BattleState, ctx: Dictionary) -> Array:
	var t: Dictionary = ctx.get("target", {})
	var p1: Vector2i = t.get("tile", Vector2i(-1, -1))
	var p2: Vector2i = t.get("tile2", Vector2i(-1, -1))
	var res: Dictionary = b.refine_pair(p1, p2)
	return [str(res.get("msg", "精炼失败"))]

static func gild_candidate(target: Dictionary) -> CharInstance:
	var uid := int(target.get("gild_uid", -1))
	for inst in GameState.deck:
		if inst.uid == uid and inst.is_player_owned() and not inst.temporary and not inst.gilded:
			return inst
	return null

static func _gild_glyph(b: BattleState, ctx: Dictionary, eff: EffectData) -> Array:
	var inst := gild_candidate(ctx.get("target", {}))
	if inst == null:
		return ["镀金：未选择合法实体字"]
	var cost := int(eff.args.get("cost", 0)) if eff != null else 0
	if not EffectUtil.pay(b, cost):
		return ["镀金：铜钱不足"]
	GameState.gild_character(inst)
	EventBus.deck_changed.emit()
	return ["镀金：【%s】#%d 永久镀金，每次有效单字或组词打出+%d铜钱" % [inst.glyph(), inst.uid, BattleBalance.i("gild_gold", 1)]]

## 精铸：把盘面一枚己方实体字固定（本场不消耗、可反复使用；不可移动/换字）。
static func _pin_glyph(b: BattleState, ctx: Dictionary) -> Array:
	var pos: Vector2i = EffectUtil.tile(ctx)
	var inst: CharInstance = b.board.get_xy(pos)
	if inst == null or not inst.is_player_owned() or inst.temporary:
		return ["精铸：请选择一枚己方实体字"]
	if inst.pinned:
		return ["精铸：【%s】已经固定" % inst.glyph()]
	inst.pinned = true
	inst.pinned_exhausted = false
	return ["精铸：将【%s】固定（每回合使用一次，不消耗，不可移动/换字）" % inst.glyph()]

static func _anchor_self(b: BattleState, ctx: Dictionary) -> Array:
	var path: Array = ctx.get("path", [])
	if path.is_empty(): return ["础：没有可安放的字"]
	var origin: Vector2i = path[0]
	var inst: CharInstance = b.board.get_xy(origin)
	if inst == null or not inst.is_player_owned() or inst.temporary:
		return ["础：请选择己方永久实体字"]
	var tile: Vector2i = EffectUtil.tile(ctx)
	if not b.board.in_bounds(tile.x, tile.y) or b.board.get_xy(tile) != null or tile == origin:
		return ["础：请选择棋盘内的空格"]
	# 在消耗前把原实体搬到目标格；随后它作为固定字留在盘面。
	b.board.set_xy(origin, null)
	b.board.set_xy(tile, inst)
	inst.pinned = true
	inst.pinned_exhausted = false
	return ["础：将【础】安放在 (%d,%d)，固定本场，不受重力/位移影响。" % [tile.x, tile.y]]


static func _precision_place(b: BattleState, ctx: Dictionary, eff: EffectData) -> Array:
	var cost: int = eff.amount
	var tile: Vector2i = EffectUtil.tile(ctx)
	if b.board.get_xy(tile) != null:
		return ["放回：目标格已被占用"]
	if EffectUtil.available(b) < EffectUtil.discounted_cost(b, cost):
		return ["放回：支付额不足（需 %d）" % cost]
	var uid: int = int(ctx.get("target", {}).get("place_uid", -1))
	var inst: CharInstance = b.take_from_discard_by_uid(uid)
	if inst == null:
		return ["放回：请选择弃字堆中的一枚己方字"]
	EffectUtil.pay(b, cost)
	inst.owner = CharInstance.Owner.PLAYER
	b.place_from_pool(tile, inst)
	return ["放回：支付 %d，将【%s】放入指定空格" % [cost, inst.glyph()]]

## 急流：选一行/列，将己方实体字洗回字袋，再向原位置随机补入相同数量。
static func _reshuffle_line(b: BattleState, ctx: Dictionary) -> Array:
	var t: Dictionary = ctx.get("target", {})
	var positions: Array = []
	if t.has("row"):
		var row: int = int(t["row"])
		for x in b.board.size:
			positions.append(Vector2i(x, row))
	elif t.has("col"):
		var col: int = int(t["col"])
		for y in b.board.size:
			positions.append(Vector2i(col, y))
	else:
		return ["急流：请选择一行或一列"]
	var returned: Array = []
	for p in positions:
		var inst: CharInstance = b.board.get_xy(p)
		if inst != null and not inst.pinned and inst.is_player_owned() and not inst.temporary:
			returned.append(inst)
			b.board.clear_xy(p)
	for inst2 in returned:
		b.bag.append(inst2)
	if not returned.is_empty():
		b._shuffle(b.bag)
	var filled := 0
	for p2 in positions:
		if filled >= returned.size():
			break
		if b.board.get_xy(p2) != null:
			continue
		if b.bag.is_empty():
			break
		b.place_from_pool(p2, b.bag.pop_back())
		filled += 1
	b.record_draw(filled)
	return ["急流：洗回 %d 枚，原格补入 %d 枚" % [returned.size(), filled]]


## 火急：把揭示的 2 枚字放进指定空格。
static func _place_two(b: BattleState, ctx: Dictionary) -> Array:
	var t: Dictionary = ctx.get("target", {})
	var cells: Array = [t.get("cell1", Vector2i(-1, -1)), t.get("cell2", Vector2i(-1, -1))]
	var reveal: Array = b.pending_reveal
	var placed := 0
	for i in mini(reveal.size(), 2):
		var inst: CharInstance = reveal[i]
		if inst == null:
			continue
		if b.board.get_xy(cells[i]) != null:
			continue
		inst.owner = CharInstance.Owner.PLAYER
		b.place_from_pool(cells[i], inst)
		placed += 1
	for inst in reveal:
		if not b.board.cells.has(inst):
			b.bag.append(inst)
	b.pending_reveal = []
	b.record_draw(placed)
	return ["火急：补入 %d 字（热度 +2）" % placed]


## 收复：把弃字堆中的 1～2 枚己方实体字放回指定空格。
static func _recover_two(b: BattleState, ctx: Dictionary) -> Array:
	var t: Dictionary = ctx.get("target", {})
	var places: Array = t.get("places", [])
	var placed := 0
	for item in places:
		var uid: int = int(item[0])
		var cell: Vector2i = item[1]
		if b.board.get_xy(cell) != null:
			continue
		var inst: CharInstance = b.take_from_discard_by_uid(uid)
		if inst == null:
			continue
		inst.owner = CharInstance.Owner.PLAYER
		b.place_from_pool(cell, inst)
		placed += 1
	return ["收复：从弃字堆放回 %d 枚" % placed]


## 收回：把盘上一枚己方实体字置于字袋顶，再从弃字堆放一枚到原格。
static func _recover_to_bag(b: BattleState, ctx: Dictionary) -> Array:
	var t: Dictionary = ctx.get("target", {})
	var tile: Vector2i = t.get("tile", Vector2i(-1, -1))
	var inst: CharInstance = b.board.get_xy(tile)
	if inst == null or inst.pinned or not inst.is_player_owned() or inst.temporary:
		return ["收回：请选择一枚己方实体字"]
	b.board.clear_xy(tile)
	b.bag.append(inst)
	var uid: int = int(t.get("place_uid", -1))
	var di: CharInstance = b.take_from_discard_by_uid(uid)
	if di != null:
		di.owner = CharInstance.Owner.PLAYER
		b.place_from_pool(tile, di)
		return ["收回：【%s】回袋顶，从弃字堆放入【%s】" % [inst.glyph(), di.glyph()]]
	return ["收回：【%s】回袋顶" % inst.glyph()]


## 收放：把盘上一枚字移动到任意空格。
static func _move_cell(b: BattleState, ctx: Dictionary) -> Array:
	var t: Dictionary = ctx.get("target", {})
	var a: Vector2i = t.get("tile", Vector2i(-1, -1))
	var c: Vector2i = t.get("tile2", Vector2i(-1, -1))
	var inst: CharInstance = b.board.get_xy(a)
	if inst == null:
		return ["收放：请选择要移动的字"]
	if inst.pinned:
		return ["收放：固定的字不可移动"]
	if b.board.get_xy(c) != null:
		return ["收放：目标格已被占用"]
	b.board.clear_xy(a)
	b.board.set_xy(c, inst)
	return ["收放：将【%s】移动一格" % inst.glyph()]


static func _split_mind(b: BattleState) -> Array:
	b.enable_ability("split_mind", 1)
	return ["精分：本回合敌我攻击都打向自己……"]

static func _vigor(b: BattleState) -> Array:
	b.enable_ability("vigor", 1)
	return ["精力：本回合每种不同多字词，使下回合基础补字 +1"]

static func _charge_overheat(b: BattleState, eff: EffectData) -> Array:
	var en: int = int(eff.args.get("energy", 8)) * b.passive_multiplier("充电过热")
	var ht: int = int(eff.args.get("heat", 8)) * b.passive_multiplier("充电过热")
	b.add_energy(en)
	b.add_heat(ht)
	b.enable_ability("auto_refill", 1)
	return ["充电过热：获得 %d 储能 + %d 热度；此后每次出字立即补位" % [en, ht]]

static func _recast_board(b: BattleState) -> Array:
	var count := 0
	for inst in b.board.cells:
		if inst != null and not inst.pinned:
			count += 1
	if count == 0:
		return ["重铸：盘面没有字"]
	for i in b.board.cells.size():
		var c: CharInstance = b.board.cells[i]
		if c == null or c.pinned:
			continue
		if c.temporary or not c.is_player_owned():
			b.temp_chars.erase(c)
		else:
			b.bag.append(c)
		b.board.cells[i] = null
	b._shuffle(b.bag)
	var drawn := b.draw_to_board(count)
	return ["重铸：盘面 %d 枚字全部重新替换（补回 %d）" % [count, drawn]]

static func _recast_copy(b: BattleState, ctx: Dictionary) -> Array:
	var tile: Vector2i = EffectUtil.tile(ctx)
	if b.board.get_xy(tile) != null:
		return ["再铸：目标格已被占用"]
	var uid: int = int(ctx.get("target", {}).get("place_uid", -1))
	var src: CharInstance = b.get_discard_by_uid(uid)
	if src == null:
		return ["再铸：请选择弃字堆中的一枚字"]
	var copy: CharInstance = src.clone()
	copy.owner = CharInstance.Owner.PLAYER
	copy.temporary = true
	b.temp_chars.append(copy)
	b.board.set_xy(tile, copy)
	return ["再铸：将【%s】的临时复制放入指定空格（原牌留在弃字堆）" % src.glyph()]


## 收心：将所选盘面己方牌放回抽字袋，每选 1 枚回复 1 生命（可 0 张）。
static func _collect_own(b: BattleState, ctx: Dictionary) -> Array:
	var cells: Array = ctx.get("target", {}).get("cells", [])
	var n := 0
	for cell in cells:
		var pos: Vector2i = cell
		var inst: CharInstance = b.board.get_xy(pos)
		if inst == null or not inst.is_player_owned() or inst.temporary or inst.pinned:
			continue
		b.board.set_xy(pos, null)
		b.bag.append(inst)
		n += 1
	if n > 0:
		b.heal_player(n * BattleBalance.i("collect_heal", 1))
	return ["收心：将 %d 枚字放回抽字袋，回复 %d 生命" % [n, n * BattleBalance.i("collect_heal", 1)]]


## 再铸：将所选 3 个盘面字替换为随机临时字（随机字不一定在玩家牌组里）。
static func valid_recast_targets(b: BattleState, cells: Array, excluded: Array = []) -> bool:
	if cells.size() != BattleBalance.i("recast_target_count", 3):
		return false
	var selected := {}
	for cell in cells:
		var inst := b.board.get_xy(cell)
		if inst == null or inst.pinned or excluded.has(cell) or selected.has(inst.uid):
			return false
		selected[inst.uid] = true
	return true

static func valid_suspend_targets(b: BattleState, instances: Array) -> bool:
	if instances.size() != BattleBalance.i("recast_target_count", 3):
		return false
	var seen := {}
	for inst in instances:
		if not inst is CharInstance or inst.pinned or not b.board.cells.has(inst) or seen.has(inst.uid):
			return false
		seen[inst.uid] = true
	return true

static func _suspend_three(b: BattleState, ctx: Dictionary) -> Array:
	var instances: Array = ctx.get("suspend_targets", [])
	if not valid_suspend_targets(b, instances):
		return ["重连：所选实体已离开棋盘或被固定，请重新选择"]
	for inst in instances:
		var index: int = b.board.cells.find(inst)
		b.reconnect_pending.append({"inst": inst, "pos": b.board.to_xy(index), "return_turn": b.turn + 1})
		b.board.cells[index] = null
	return ["重连：三个原实体暂时移出，下回合优先原格返回（满盘时等待空位）"]

static func _recast_three(b: BattleState, ctx: Dictionary) -> Array:
	var cells: Array = ctx.get("target", {}).get("cells", [])
	if not valid_recast_targets(b, cells):
		return ["再铸：请选择三个不同的非固定字"]
	var pool: Array = []
	for c in Database.characters.values():
		if not c.is_pollution and not c.pending_design and not c.tags.has("enemy"):
			pool.append(c)
	if pool.is_empty():
		return ["再铸：无可用随机字"]
	var replaced := 0
	for cell in cells:
		var pos: Vector2i = cell
		if b.board.get_xy(pos) == null:
			continue
		var cd: CharacterData = pool[b.rng.randi_range(0, pool.size() - 1)]
		var copy := CharInstance.new(cd)
		copy.owner = CharInstance.Owner.PLAYER
		copy.temporary = true
		b.temp_chars.append(copy)
		b.board.set_xy(pos, copy)
		replaced += 1
	return ["再铸：将 %d 枚字替换为随机临时字" % replaced]

static func _repeat_last(b: BattleState, ctx: Dictionary) -> Array:
	if b.last_played_glyphs.is_empty():
		return ["再：此前没有可重复的字"]
	var g: String = str(b.last_played_glyphs[b.last_played_glyphs.size() - 1])
	if g == "再":
		return ["再：不能复制【再】本身，仅腾位"]
	var copy: CharInstance = b.create_temp_glyph(g)
	if copy == null:
		return ["再：无法重复【%s】" % g]
	var path: Array = ctx.get("path", [])
	var placed_pos := Vector2i(-1, -1)
	if not path.is_empty() and b.board.get_xy(path[0]) == null:
		placed_pos = path[0]
	else:
		var empties := b.board.empty_indices()
		if not empties.is_empty():
			placed_pos = empties[0]
	if placed_pos == Vector2i(-1, -1):
		return ["再：没有空格放置重复的字"]
	b.board.set_xy(placed_pos, copy)
	return ["再：重复上一个字的【%s】（临时）" % g]

static func _reverse_line(b: BattleState, ctx: Dictionary) -> Array:
	var t: Dictionary = ctx.get("target", {})
	var n := b.board.size
	if t.has("row"):
		var y: int = int(t["row"])
		if y < 0 or y >= n:
			return ["反转：无效行"]
		for x0 in n:
			var c0 := b.board.get_cell(x0, y)
			if c0 != null and c0.pinned:
				return ["反转：该行有固定字，不可移动"]
		for x in n / 2:
			var a := Vector2i(x, y)
			var c := Vector2i(n - 1 - x, y)
			var ta = b.board.get_xy(a)
			var tc = b.board.get_xy(c)
			b.board.set_xy(a, tc)
			b.board.set_xy(c, ta)
		return ["反转：倒转第 %d 行（含空格与叠层）" % (y + 1)]
	if t.has("col"):
		var x2: int = int(t["col"])
		if x2 < 0 or x2 >= n:
			return ["反转：无效列"]
		for y0 in n:
			var c3 := b.board.get_cell(x2, y0)
			if c3 != null and c3.pinned:
				return ["反转：该列有固定字，不可移动"]
		for y2 in n / 2:
			var a2 := Vector2i(x2, y2)
			var c2 := Vector2i(x2, n - 1 - y2)
			var ta2 = b.board.get_xy(a2)
			var tc2 = b.board.get_xy(c2)
			b.board.set_xy(a2, tc2)
			b.board.set_xy(c2, ta2)
		return ["反转：倒转第 %d 列（含空格与叠层）" % (x2 + 1)]
	return ["反转：请选择一行或一列"]

static func _merge_flow(b: BattleState, ctx: Dictionary) -> Array:
	var t: Dictionary = ctx.get("target", {})
	var c1: Vector2i = t.get("cell1", Vector2i(-1, -1))
	var c2: Vector2i = t.get("cell2", Vector2i(-1, -1))
	var bag_uid: int = int(t.get("merge_bag_uid", -1))
	var disc_uid: int = int(t.get("merge_discard_uid", -1))
	if c1 == c2 or not b.board.is_adjacent(c1, c2) or b.board.get_xy(c1) != null or b.board.get_xy(c2) != null:
		b.return_pending_reveal()
		return ["合流：需要两个相邻空格，未移动"]
	var bag_card: CharInstance = b.take_revealed(bag_uid)
	var disc_card: CharInstance = b.take_from_discard_by_uid(disc_uid)
	if bag_card == null or disc_card == null:
		if bag_card != null:
			b.pending_reveal.append(bag_card)
		if disc_card != null:
			b.discard.append(disc_card)
		b.return_pending_reveal()
		return ["合流：选择无效"]
	b.return_pending_reveal()
	b.place_from_pool(c1, bag_card)
	b.place_from_pool(c2, disc_card)
	b.record_draw(2)
	return ["合流：将【%s】【%s】放入相邻空格" % [bag_card.glyph(), disc_card.glyph()]]

static func _hard_stop(b: BattleState) -> Array:
	b.clear_heat()
	var removed := b.remove_scorch_in_circulation()
	b.end_turn_requested = true
	return ["急停：清空热度，移除 %d 枚未打出的灼热【热】；立即结束出字阶段" % removed]

static func _repeat_word(b: BattleState) -> Array:
	b.enable_ability("repeat", 1)
	return ["重复：本场从下回合起，每回合首次多字词的即时效果额外结算一次，费用再付"]

static func _suspend(b: BattleState) -> Array:
	var h: int = b.player.heat
	b.clear_heat()
	b.player.add_persistent_block(h * BattleBalance.i("heat_block_mult", 2))
	b.end_turn_requested = true
	return ["停息：清零 %d 热度，获得 %d 持久盾；立即结束出字阶段" % [h, h * BattleBalance.i("heat_block_mult", 2)]]

static func _split_grow(b: BattleState, ctx: Dictionary) -> Array:
	var tile: Vector2i = EffectUtil.tile(ctx)
	var center: CharInstance = b.board.get_xy(tile)
	if center == null:
		return ["分化：请选择一个盘面字"]
	if center.pinned:
		return ["分化：固定字不可删除或换字"]
	var old_glyph: String = center.glyph()
	b.temp_chars.erase(center)
	b.board.clear_xy(tile)   # 删除该字（不入弃字堆）
	var spawned := b.spawn_word_neighbors(tile, BattleBalance.i("split_spawn_limit", 4), old_glyph)
	var glyphs: Array = []
	for s in spawned:
		glyphs.append(s.glyph())
	if spawned.is_empty():
		return ["分化：删除【%s】，但周围没有空格" % old_glyph]
	return ["分化：删除【%s】，周围生长 %d 枚临时字：%s" % [old_glyph, spawned.size(), "、".join(glyphs)]]

static func _transform_board(b: BattleState, ctx: Dictionary) -> Array:
	var tile: Vector2i = EffectUtil.tile(ctx)
	if b.board.get_xy(tile) == null:
		b.return_pending_reveal()
		return ["转化：请选择一个盘面字"]
	if b.board.get_xy(tile).pinned:
		b.return_pending_reveal()
		return ["转化：固定字不可换字"]
	var uid: int = int(ctx.get("target", {}).get("transform_uid", -1))
	var chosen: CharInstance = b.take_revealed(uid)
	if chosen == null:
		b.return_pending_reveal()
		return ["转化：未选择要变成的字"]
	b.return_pending_reveal()
	var old: CharInstance = b.board.get_xy(tile)
	if old != null:
		if old.is_player_owned():
			b.discard.append(old)
		else:
			b.temp_chars.erase(old)
	var old_glyph: String = old.glyph() if old != null else "空"
	chosen.owner = CharInstance.Owner.PLAYER
	b.place_from_pool(tile, chosen)
	return ["转化：将【%s】定向改为【%s】" % [old_glyph, chosen.glyph()]]

static func _replace_self(b: BattleState, ctx: Dictionary) -> Array:
	# 【回】固定用在它自己被打出的那一格（原位），不需要选目标
	var tile: Vector2i = EffectUtil.tile(ctx)
	var path: Array = ctx.get("path", [])
	if not path.is_empty():
		tile = path[0]
	if b.board.get_xy(tile) != null:
		return ["回：目标格已被占用"]
	if b.bag.is_empty():
		if b.discard.is_empty():
			return ["回：字袋为空，无法换字"]
		b.bag = b.discard.duplicate()
		b.discard.clear()
		b._shuffle(b.bag)
	var inst: CharInstance = b.draw_one_to(tile)
	if inst == null:
		return ["回：字袋为空，无法换字"]
	return ["回：原位换成【%s】" % inst.glyph()]

static func _reveal_place(b: BattleState, ctx: Dictionary, cost: int) -> Array:
	var tile: Vector2i = EffectUtil.tile(ctx)
	if b.board.get_xy(tile) != null:
		return ["投放：目标格已被占用"]
	var chosen: CharInstance = null
	var uid := int((ctx.get("target", {}) as Dictionary).get("bag_uid", -1))
	for inst in deploy_candidates(b):
		if inst.uid == uid:
			chosen = inst
	if chosen == null:
		return ["投放：没有可选实体，未支付"]
	var due := EffectUtil.discounted_cost(b, cost)
	if EffectUtil.available(b) < due:
		return ["投放：支付额不足（需%d）" % due]
	b.bag.erase(chosen)
	b.place_from_pool(tile, chosen)
	chosen.temporary_uses += BattleBalance.i("buyback_layer", 1)
	EffectUtil.pay(b, cost)
	b.record_draw(1)
	return ["投放：实际支付%d，选定原实体【%s】落盘，额外使用+1" % [due, chosen.glyph()]]
