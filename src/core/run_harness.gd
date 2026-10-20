extends RefCounted
class_name RunHarness
## 整局（run）无头驱动：地图推进 + 战斗 + 奖励 + 商店 + 事件 + 修整 + 跨战状态。
## 供 AI / 外部程序逐步试玩（配合 src/tools/run_bridge.gd）。
##
##   var h := RunHarness.new()
##   h.reset({"seed": 1})
##   while not h.is_done():
##       var acts := h.legal_actions()   # 按当前 phase 给可选项
##       h.apply(选择的一项)
##
## phase 流程：map → (enter) → battle/event/shop/rest/fork → … → complete_node → map … → victory/defeat

const EventEffects := preload("res://src/core/event_effects.gd")
const LANTERN := preload("res://src/data/lantern_riddles.gd")
const SHEFU := preload("res://src/data/shefu_rewards.gd")

var phase := "map"
var node: MapNodeData = null
var battle_h: BattleHarness = null
var reward_options: Array = []
var shop_offers: Array = []
var event_data: Dictionary = {}
var event_node := "start"
var event_notes: Array[String] = []   ## 事件选项自带的“正文附言”（每次选择追加一行，如韫椟的“玉声近一寸”）
var pending_event_next := ""
var pending_glyphs: Array = []
var pending_kind := ""
var pending_index := -1
var pending_event_effect: Dictionary = {}
var pending_event_relics: Array = []
var seed := 1
var log_lines: Array = []


func reset(cfg: Dictionary = {}) -> void:
	seed = int(cfg.get("seed", 1))
	reward_options.clear()
	shop_offers.clear()
	event_data = {}
	event_node = "start"
	pending_event_next = ""
	pending_glyphs.clear()
	pending_kind = ""
	pending_index = -1
	pending_event_effect.clear()
	pending_event_relics.clear()
	log_lines.clear()
	GameState.rng.seed = seed
	GameState.start_new_run(str(cfg.get("starter", "v03")), cfg.get("deck", []))
	if cfg.has("hp"):
		GameState.player_hp = clampi(int(cfg["hp"]), 1, GameState.player_max_hp)
	if cfg.has("gold"):
		GameState.gold = int(cfg["gold"])
	battle_h = null
	phase = "map"
	node = _node_at(GameState.act_index, GameState.node_index)
	_log("开局 seed=%d，字袋 %d 枚" % [seed, GameState.deck_size()])


func is_done() -> bool:
	return phase == "victory" or phase == "defeat"


func _node_at(act: int, order: int) -> MapNodeData:
	var a := Database.get_act(act)
	if a == null:
		return null
	for n in a.nodes:
		if n.order == order:
			return n
	return null


func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 80:
		log_lines.pop_front()


func _type_name(t: int) -> String:
	match t:
		MapNodeData.Type.BATTLE: return "battle"
		MapNodeData.Type.ELITE: return "elite"
		MapNodeData.Type.BOSS: return "boss"
		MapNodeData.Type.EVENT: return "event"
		MapNodeData.Type.SHOP: return "shop"
		MapNodeData.Type.REST: return "rest"
		MapNodeData.Type.FORK: return "fork"
	return "?"


func _heal_amount() -> int:
	return int(round(GameState.player_max_hp * 0.3)) + Relics.rest_bonus()


func _deck_cfg() -> Array:
	var counts := {}
	for inst in GameState.deck:
		var g: String = inst.glyph()
		counts[g] = int(counts.get(g, 0)) + 1
	var out: Array = []
	for g in counts.keys():
		out.append({"glyph": g, "count": int(counts[g])})
	return out


func _pool(min_r: int, max_r: int) -> Array:
	var pool: Array = []
	for c in Database.characters.values():
		if c.is_pollution or c.pending_design or c.tags.has("enemy") or c.tags.has("彩蛋") or c.tags.has("event"):
			continue
		if c.rarity >= min_r and c.rarity <= max_r:
			pool.append(c)
	if pool.is_empty():
		pool = Database.characters.values()
	return pool


func _pick_from_db(min_r: int, max_r: int, count: int) -> Array:
	var pool := _pool(min_r, max_r)
	var out: Array = []
	var guard := 0
	while out.size() < count and guard < 300:
		guard += 1
		var c: CharacterData = pool[GameState.rng.randi_range(0, pool.size() - 1)]
		if out.any(func(x): return x.id == c.id):
			continue
		out.append(c)
	return out


func _random_char(min_r: int, max_r: int) -> CharacterData:
	var pool := _pool(min_r, max_r)
	return pool[GameState.rng.randi_range(0, pool.size() - 1)]


# ---------------------------------------------------------------- 观察
func observe() -> Dictionary:
	var d := {
		"phase": phase, "act": GameState.act_index, "node": GameState.node_index,
		"node_type": _type_name(node.type) if node != null else "",
		"node_title": node.title if node != null else "",
		"hp": (battle_h.battle.player.hp if (phase == "battle" and battle_h != null) else GameState.player_hp),
		"max_hp": GameState.player_max_hp,
		"gold": GameState.gold, "deck_size": GameState.deck_size(),
		"event_temp_hp": GameState.event_temp_hp,
		"deck": GameState.glyph_counts(), "done": is_done(),
		"log": log_lines.slice(max(0, log_lines.size() - 6)),
	}
	if phase == "battle" and battle_h != null:
		d["battle"] = battle_h.observe()
	if phase == "reward":
		d["reward"] = reward_options.map(func(c): return {"glyph": c.glyph, "rarity": c.rarity})
	if phase == "shop":
		d["shop"] = shop_offers.map(func(o): return {"kind": o.kind, "price": o.price, "glyph": (o.character.glyph if o.character != null else "")})
	if phase in ["event", "event_choose", "event_relic"]:
		var current: Dictionary = current_event()
		var options: Array = current.get("options", [])
		d["event"] = {
			"id": event_data.get("id", ""),
			"node": event_node,
			"title": current.get("title", event_data.get("title", "")),
			"body": current.get("body", event_data.get("body", "")),
			"illustration": current.get("illustration", event_data.get("illustration", "")),
			"options": options.map(func(option): return str(option.get("text", ""))),
			"option_effects": options.map(func(option): return option.get("effects", []).duplicate(true)),
			"relic_offers": pending_event_relics.duplicate(),
		}
		if phase == "event_choose":
			d["event"]["pending_removal"] = {
				"remaining": int(pending_event_effect.get("remaining", 0)),
				"glyphs": pending_event_effect.get("glyphs", []).duplicate(),
			}
	return d


# ---------------------------------------------------------------- 合法动作
func legal_actions() -> Array:
	match phase:
		"map":
			return [{"type": "enter", "node_type": _type_name(node.type) if node != null else "", "title": node.title if node != null else ""}]
		"battle":
			return battle_h.legal_actions() if battle_h != null else []
		"reward":
			var out: Array = []
			for i in reward_options.size():
				out.append({"type": "reward", "index": i, "glyph": reward_options[i].glyph})
			out.append({"type": "skip", "gold": Expedition.SKIP_GOLD})
			return out
		"shop":
			var out2: Array = []
			for i in shop_offers.size():
				var o: Dictionary = shop_offers[i]
				out2.append({"type": "shop_buy", "index": i, "kind": o.kind, "price": o.price, "glyph": (o.character.glyph if o.character != null else "")})
			out2.append({"type": "shop_leave"})
			return out2
		"shop_choose", "event_choose", "rest_choose":
			var out3: Array = []
			for g in pending_glyphs:
				out3.append({"type": "pick", "glyph": g})
			out3.append({"type": "cancel_pick"})
			return out3
		"event":
			var opts: Array = current_event().get("options", [])
			var out4: Array = []
			for i in opts.size():
				if not EventEffects.option_available(opts[i]): continue
				out4.append({"type": "event", "index": i, "text": opts[i].text, "primary": bool(opts[i].get("primary", false))})
			if bool(current_event().get("allow_leave", true)): out4.append({"type": "event_leave"})
			return out4
		"event_relic":
			if pending_event_relics.is_empty(): return []
			return [{"type":"event_relic_take", "relic":pending_event_relics[0]}, {"type":"event_relic_skip"}]
		"rest":
			return [
				{"type": "rest", "kind": "heal", "amount": _heal_amount()},
				{"type": "rest", "kind": "remove"},
				{"type": "rest", "kind": "upgrade"},
			]
		"fork":
			return [{"type": "fork", "index": 0, "label": "挑战精英"}, {"type": "fork", "index": 1, "label": "寻访事件"}]
	return []


# ---------------------------------------------------------------- 执行
func apply(action: Dictionary) -> Dictionary:
	var t := str(action.get("type", ""))
	match phase:
		"map":
			if t != "enter": return {"ok": false, "reason": "此时不能执行这个动作"}
			return _apply_enter()
		"battle": return _apply_battle(action)
		"reward": return _apply_reward(t, action)
		"shop": return _apply_shop(t, action)
		"shop_choose", "event_choose", "rest_choose": return _apply_pick(action)
		"event": return _apply_event(action)
		"event_relic": return _apply_event_relic(t)
		"rest": return _apply_rest(t, action)
		"fork": return _apply_fork(action)
	return {"ok": false, "reason": "phase=%s 无动作" % phase}


func _apply_enter() -> Dictionary:
	if node == null:
		return {"ok": false, "reason": "无节点"}
	match node.type:
		MapNodeData.Type.BATTLE, MapNodeData.Type.ELITE, MapNodeData.Type.BOSS:
			_start_battle(node)
		MapNodeData.Type.EVENT:
			_start_event()
		MapNodeData.Type.SHOP:
			_start_shop()
		MapNodeData.Type.REST:
			phase = "rest"
		MapNodeData.Type.FORK:
			phase = "fork"
	return {"ok": true, "phase": phase}


func _start_battle(n: MapNodeData) -> void:
	var ids: Array = []
	for e in n.select_enemies(seed * 997 + GameState.act_index * 100 + GameState.node_index):
		ids.append(e.id)
	if ids.is_empty():
		ids = ["ink_spirit"]
	battle_h = BattleHarness.new()
	battle_h.reset({
		"seed": seed * 997 + GameState.act_index * 100 + GameState.node_index,
		"deck": _deck_cfg(), "enemies": ids,
		"hp": GameState.player_hp, "gold": GameState.gold,
		"persistent_run": true,
	})
	phase = "battle"
	_log("战斗：%s（%s）" % [n.title, str(ids)])


func _apply_battle(action: Dictionary) -> Dictionary:
	var r: Dictionary = battle_h.apply(action)
	if battle_h.is_done():
		_end_battle()
	return r


func _end_battle() -> void:
	var b: BattleState = battle_h.battle
	GameState.player_hp = b.player.hp
	if b.is_victory():
		GameState.add_captured(b.captured_chars)
		GameState.settle_victory_economy()
		_log("胜利：HP %d/%d，金 %d" % [GameState.player_hp, GameState.player_max_hp, GameState.gold])
		if node != null and node.type == MapNodeData.Type.BOSS and GameState.act_index >= 3:
			reward_options.clear()
			_complete_node()
			return
		if node != null and node.type == MapNodeData.Type.BOSS:
			GameState.player_hp = GameState.player_max_hp
			_log("首领已破：回满生命")
		reward_options = _pick_from_db(1 if (node != null and node.type == MapNodeData.Type.BOSS) else 0, 4 if (node != null and node.type == MapNodeData.Type.BOSS) else 2, 3)
		phase = "reward"
	else:
		_log("战败于 %s" % (node.title if node != null else "?"))
		phase = "defeat"


func _apply_reward(t: String, action: Dictionary) -> Dictionary:
	if t == "skip":
		GameState.add_gold(8)
		_log("跳过奖励：+8 金")
	else:
		var i := int(action.get("index", -1))
		if i < 0 or i >= reward_options.size():
			return {"ok": false, "reason": "无效奖励"}
		GameState.add_character(reward_options[i], 1)
		_log("获得字：%s" % reward_options[i].glyph)
	_complete_node()
	return {"ok": true, "phase": phase}


func _start_shop() -> void:
	shop_offers.clear()
	for c in _pick_from_db(0, 2, Expedition.SHOP_CARD_COUNT):
		shop_offers.append({"kind": "buy_char", "character": c, "price": GameState.rng.randi_range(12, 15)})
	shop_offers.append({"kind": "remove", "character": null, "price": GameState.rng.randi_range(16, 20)})
	shop_offers.append({"kind": "copy", "character": null, "price": GameState.rng.randi_range(18, 22)})
	shop_offers.append({"kind": "heal", "character": null, "price": GameState.rng.randi_range(10, 14)})
	phase = "shop"
	Achievements.register_offers(shop_offers)


func _apply_shop(t: String, action: Dictionary) -> Dictionary:
	if t == "shop_leave":
		_log("离开市集")
		_complete_node()
		return {"ok": true, "phase": phase}
	var i := int(action.get("index", -1))
	if i < 0 or i >= shop_offers.size():
		return {"ok": false, "reason": "无效商品"}
	var o: Dictionary = shop_offers[i]
	if GameState.gold < int(o.price):
		return {"ok": false, "reason": "铜钱不足"}
	if o.kind == "remove" or o.kind == "copy":
		if GameState.deck_size() == 0: return {"ok": false, "reason": "字袋中没有可选择的字"}
		GameState.spend_gold(int(o.price))
		pending_kind = o.kind
		pending_index = i
		pending_glyphs = GameState.glyph_counts().keys()
		phase = "shop_choose"
		return {"ok": true, "phase": phase}
	GameState.spend_gold(int(o.price))
	if o.kind == "buy_char":
		GameState.add_character(o.character, 1)
		_log("买入字：%s" % o.character.glyph)
	elif o.kind == "heal":
		# 商店治疗不算休息，不加安神香
		var shop_heal := int(round(GameState.player_max_hp * 0.3))
		GameState.heal(shop_heal)
		_log("治疗 +%d" % shop_heal)
	shop_offers.remove_at(i)
	Achievements.bought_offer(o)
	return {"ok": true, "phase": phase}


func _apply_pick(action: Dictionary) -> Dictionary:
	if str(action.get("type", "")) == "cancel_pick": return _cancel_pick()
	if str(action.get("type", "")) != "pick": return {"ok": false, "reason": "此时不能执行这个动作"}
	var g := str(action.get("glyph", ""))
	if not pending_glyphs.has(g):
		return {"ok": false, "reason": "无效字 %s" % g}
	var modification := ""
	var cd: CharacterData = Database.get_character_by_glyph(g)
	if cd == null or not GameState.glyph_counts().has(g):
		return {"ok": false, "reason": "所选字已不存在，请取消后重新选择"}
	if phase == "shop_choose":
		if pending_kind == "remove":
			GameState.remove_character_id(cd.id)
		elif pending_kind == "copy":
			GameState.add_character(cd, 1)
		_log("市集 %s：%s" % [pending_kind, g])
		if pending_index >= 0 and pending_index < shop_offers.size():
			Achievements.bought_offer(shop_offers[pending_index])
			shop_offers.remove_at(pending_index)
		pending_kind = ""
		pending_index = -1
		pending_glyphs.clear()
		phase = "shop"
	elif phase == "event_choose":
		var result: Dictionary = EventEffects.resume(pending_event_effect, g, GameState.rng, true)
		if not result.get("ok", false): return {"ok": false, "reason": str(result.get("reason", "事件选择失败"))}
		pending_event_effect = result.get("pending", {})
		pending_event_relics = result.get("relic_offers", [])
		_log("事件删字：%s" % g)
		if pending_event_effect.is_empty():
			pending_glyphs.clear()
			_advance_event()
		else:
			pending_glyphs = pending_event_effect.get("glyphs", [])
	elif phase == "rest_choose":
		if pending_kind == "remove":
			GameState.remove_character_id(cd.id)
			_log("休整删字：%s" % g)
		elif pending_kind == "upgrade":
			var before := {}
			for inst: CharInstance in GameState.deck:
				if inst.id() == cd.id: before[inst.uid] = inst.describe()
			_apply_upgrade(cd)
			var changed := {}
			for inst: CharInstance in GameState.deck:
				if inst.id() != cd.id or before.get(inst.uid, "") == inst.describe(): continue
				var description := inst.describe()
				changed[description] = int(changed.get(description, 0)) + 1
			var details: Array[String] = []
			for description: String in changed:
				details.append("【%s】×%d\n%s" % [g, changed[description], description])
			modification = "\n\n".join(details)
			_log("休整修饰完成：" + modification)
		pending_kind = ""
		pending_glyphs.clear()
		_complete_node()
	return {"ok": true, "phase": phase, "modification": modification}


func _cancel_pick() -> Dictionary:
	match phase:
		"event_choose":
			# Until all targets are chosen, none of the option's effects have run.
			pending_event_effect.clear()
			pending_event_next = ""
			phase = "event"
		"shop_choose":
			if pending_index < 0 or pending_index >= shop_offers.size():
				return {"ok": false, "reason": "待选商品已不存在"}
			# The service was prepaid on entry; leave its stock intact and refund once.
			GameState.add_gold(int(shop_offers[pending_index].price))
			phase = "shop"
		"rest_choose": phase = "rest"
		_: return {"ok": false, "reason": "此时没有待取消的选择"}
	pending_glyphs.clear()
	pending_kind = ""
	pending_index = -1
	return {"ok": true, "phase": phase}


func _apply_upgrade(ch: CharacterData) -> void:
	GameState.upgrade_character_type(ch.id)


func current_event() -> Dictionary:
	var node_event: Dictionary = EventEffects.node(event_data, event_node)
	if not event_notes.is_empty():
		node_event["body"] = str(node_event.get("body", "")) + "\n" + "\n".join(event_notes)
	return node_event


func _start_event() -> void:
	event_data = EventEffects.roll(GameState.act_index, GameState.rng)
	event_data = LANTERN.fill(event_data, GameState.rng)
	event_data = SHEFU.fill(event_data, GameState.rng)
	event_node = "start"
	event_notes.clear()
	pending_event_next = ""
	pending_event_effect.clear()
	pending_event_relics.clear()
	pending_glyphs.clear()
	phase = "event"


## 选项可用 "append" 把反馈写进正文（每次选择追加一行，只看当前事件）。
func _remember_event_note(option: Dictionary) -> void:
	var note := str(option.get("append", ""))
	if not note.is_empty() and not event_notes.has(note):
		event_notes.append(note)


func _apply_event(action: Dictionary) -> Dictionary:
	if str(action.get("type", "")) == "event_leave":
		if not bool(current_event().get("allow_leave", true)): return {"ok": false, "reason": "这场遭遇需要作出选择"}
		_complete_node()
		return {"ok": true, "phase": phase}
	if str(action.get("type", "")) != "event": return {"ok": false, "reason": "此时不能执行这个动作"}
	var current := current_event()
	var index := int(action.get("index", -1))
	var options: Array = current.get("options", [])
	if index < 0 or index >= options.size() or not EventEffects.option_available(options[index]): return {"ok": false, "reason": "无效事件选项"}
	var option: Dictionary = options[index]
	var result: Dictionary = EventEffects.resolve(option.get("effects", []), GameState.rng, true)
	if not result.get("ok", false): return {"ok": false, "reason": str(result.get("reason", "事件结算失败"))}
	for note in (result.get("notes", []) as Array):
		if not event_notes.has(str(note)): event_notes.append(str(note))
	pending_event_effect = result.get("pending", {})
	pending_event_relics = result.get("relic_offers", [])
	pending_event_next = str(option.get("goto", ""))
	_remember_event_note(option)
	if pending_event_effect.is_empty():
		_advance_event()
	else:
		pending_glyphs = pending_event_effect.get("glyphs", [])
		phase = "event_choose"
	return {"ok": true, "phase": phase}


func _apply_event_relic(action_type: String) -> Dictionary:
	if pending_event_relics.is_empty() or action_type not in ["event_relic_take", "event_relic_skip"]:
		return {"ok":false, "reason":"没有待领取的事件遗物"}
	var id := str(pending_event_relics[0])
	if action_type == "event_relic_take":
		if not GameState.add_relic(id): return {"ok":false, "reason":"这件遗物已经拥有或已失效，可放弃领取"}
		# Headless callers retain a valid default binding; the UI may select another entity.
		if Relics.needs_bind(id):
			for inst: CharInstance in GameState.deck:
				if GameState.bind_relic(id, inst.id()): break
		Relics.queue_setup(id)
		_log("事件：获得遗物「%s」" % Relics.name_of(id))
	else:
		_log("事件：放弃遗物「%s」" % Relics.name_of(id))
	pending_event_relics.pop_front()
	_advance_event()
	return {"ok":true, "phase":phase, "relic":id if action_type == "event_relic_take" else ""}


func _apply_rest(t: String, action: Dictionary) -> Dictionary:
	var kind := str(action.get("kind", ""))
	if kind == "heal":
		GameState.heal(_heal_amount())
		_log("休整治疗 +%d" % _heal_amount())
		_complete_node()
	elif kind == "remove" or kind == "upgrade":
		if GameState.deck_size() == 0: return {"ok": false, "reason": "字袋中没有可选择的字"}
		pending_kind = kind
		pending_glyphs = GameState.glyph_counts().keys()
		phase = "rest_choose"
	return {"ok": true, "phase": phase}


func _apply_fork(action: Dictionary) -> Dictionary:
	if int(action.get("index", 0)) == 0:
		_log("岔路：精英")
		_start_battle(node)
	else:
		_log("岔路：事件")
		_start_event()
	return {"ok": true, "phase": phase}


func _advance_event() -> void:
	if GameState.player_hp <= 0:
		pending_event_relics.clear()
		Achievements.finish_run(false)
		phase = "defeat"
		return
	if not pending_event_relics.is_empty():
		phase = "event_relic"
		return
	pending_event_effect.clear()
	pending_glyphs.clear()
	var next := pending_event_next
	pending_event_next = ""
	if not next.is_empty():
		event_node = next
		phase = "event"
		_log("事件继续：" + str(current_event().get("title", event_data.get("title", ""))))
	else:
		Achievements.event_completed(str(event_data.get("id", "")))
		_complete_node()


func _complete_node() -> void:
	pending_event_effect.clear()
	pending_event_relics.clear()
	pending_event_next = ""
	pending_glyphs.clear()
	event_node = "start"
	event_notes.clear()
	GameState.clear_event_temp_hp()
	GameState.complete_current_node()
	if GameState.run_complete():
		phase = "victory"
		_log("通关！字袋 %d 枚" % GameState.deck_size())
		return
	phase = "map"
	node = _node_at(GameState.act_index, GameState.node_index)


func summary() -> Dictionary:
	return {
		"seed": seed, "phase": phase, "act": GameState.act_index, "node": GameState.node_index,
		"hp": GameState.player_hp, "max_hp": GameState.player_max_hp, "gold": GameState.gold,
		"deck_size": GameState.deck_size(), "victory": phase == "victory",
	}
