extends RefCounted
class_name BattleHarness
## 面向自动化/AI 的战斗接口（Gym 风格，纯逻辑、无 UI、可复现）。
##
##   var h := BattleHarness.new()
##   h.reset({"seed": 1, "deck": [{"glyph":"击","count":2}, ...], "enemies": ["ink_spirit"]})
##   while not h.is_done():
##       var acts := h.legal_actions()
##       h.apply(_pick(acts))
##   var s := h.summary()
##
## 也可从 JSON 场景驱动：见 src/tools/agent_bridge.gd。

static var _trie: Dictionary = {}
static var _trie_revision := -1

var battle: BattleState
var scenario: Dictionary = {}
var seed: int = 0
var invalid_tries: int = 0
var word_plays: int = 0
var single_plays: int = 0


func reset(cfg: Dictionary = {}) -> void:
	scenario = cfg.duplicate(true)
	seed = int(cfg.get("seed", 0))
	invalid_tries = 0
	word_plays = 0
	single_plays = 0

	var rules: BattleRules = Database.rules.duplicate()
	for k in ["opening_draw", "turn_draw", "plays_per_turn", "player_max_hp",
			"starting_gold", "gold_cap_per_battle", "heat_capacity"]:
		if cfg.has(k):
			rules.set(k, int(cfg[k]))

	var deck: Array = []
	for e in cfg.get("deck", _default_deck()):
		if typeof(e) == TYPE_DICTIONARY:
			var cd: CharacterData = Database.get_character_by_glyph(str(e.get("glyph", "")))
			if cd != null:
				for i in int(e.get("count", 1)):
					deck.append(CharInstance.new(cd))
		else:
			var cd2: CharacterData = Database.get_character_by_glyph(str(e))
			if cd2 != null:
				deck.append(CharInstance.new(cd2))

	var enemies: Array = []
	for g in cfg.get("enemies", ["ink_spirit"]):
		var ed: EnemyData = Database.get_enemy(str(g))
		if ed != null:
			enemies.append(ed)

	var persistent_run := bool(cfg.get("persistent_run", false))
	if persistent_run:
		deck = GameState.make_battle_deck()
	battle = BattleState.new(rules)
	if not persistent_run:
		GameState.player_max_hp = rules.player_max_hp
		GameState.player_hp = rules.player_max_hp
	GameState.gold = int(cfg.get("gold", rules.starting_gold))
	if not persistent_run:
		GameState.permanent_damage_reduction = 0
	# 血量要在开战前定好：还魂墨等开局回血是在 start 里结算的，开战后再改会把它抹掉
	if cfg.has("hp"):
		GameState.player_hp = int(cfg["hp"])
	battle.start(deck, enemies, seed)
	if cfg.has("gold"):
		GameState.gold = int(cfg["gold"])

	# 强制盘面：board = 16 个字形字符串（""=空），行优先
	if cfg.has("board"):
		var spec: Array = cfg["board"]
		for i in battle.board.cells.size():
			battle.board.cells[i] = null
		for i in mini(battle.board.cells.size(), spec.size()):
			var g := str(spec[i])
			if g.is_empty():
				continue
			var cd3: CharacterData = Database.get_character_by_glyph(g)
			if cd3 != null:
				battle.board.cells[i] = CharInstance.new(cd3)


static func _default_deck() -> Array:
	return ["击", "击", "防", "防", "回", "回", "反", "破", "重", "流", "御"]


# ---------------------------------------------------------------- 观察
func is_done() -> bool:
	return battle == null or battle.is_over()


func observe() -> Dictionary:
	var b := battle
	var board_rows: Array = []
	for r in b.board.size:
		var row: Array = []
		for c in b.board.size:
			row.append(_cell_dict(b.board.get_cell(c, r)))
		board_rows.append(row)
	var enemies: Array = []
	for e in b.enemies:
		enemies.append({
			"name": e.display_name, "hp": e.hp, "max_hp": e.max_hp, "block": e.block, "persistent_block": e.persistent_block, "statuses": e.statuses.duplicate(),
			"alive": e.is_alive(),
			"intent": (b.current_intent(e).intent_text() if e.is_alive() and b.current_intent(e) != null else ""),
		})
	return {
		"turn": b.turn,
		"done": is_done(),
		"board": board_rows,
		"bag": b.bag.size(),
		"discard": b.discard.size(),
		"discard_cards": b.discard.map(_cell_dict),
		"pending_reveal": b.pending_reveal.map(_cell_dict),
		"manual_draw_pending": b.manual_draw_pending,
		"manual_draw_choices": _manual_draw_counts() if b.manual_draw_pending > 0 else {},
		"formation": {"active": b.formation_mode, "reserved": _path_out(b.reserved_cells),
			"queue": b.formation_queue.map(func(p): return {"path": _path_out(p.path), "glyphs": p.glyphs})},
		"repeat_rotate": {"tile": _xy_out(b.repeat_rotate_tile), "count": b.repeat_rotate_count},
		"last_played_glyphs": b.last_played_glyphs.duplicate(),
		"flow_speed_rows": b.flow_speed_rows.duplicate(),
		"pierce_once": b.pierce_once, "enemy_skip_turns": b.enemy_skip_turns,
		"reconnect_pending": b.reconnect_pending.map(func(item): return {
			"card": _cell_dict(item.inst), "pos": _xy_out(item.pos), "return_turn": item.return_turn}),
		"player": {
			"hp": b.player.hp, "max_hp": b.player.max_hp,
			"block": b.player.block, "persistent_block": b.player.persistent_block,
			"energy": b.player.energy, "heat": b.player.heat, "heat_capacity": b.player.heat_capacity,
			"turn_strength": b.player.turn_strength, "next_damage_reduction": b.player.next_damage_reduction,
			"gold": GameState.gold,
			"gold_earned_this_turn": b.gold_earned_this_turn,
			"temporary_heat_capacity": b.temporary_heat_capacity,
			"statuses": b.player.statuses.duplicate(),
		},
		"enemies": enemies,
		"abilities": b.abilities.duplicate(),
	}


func _cell_dict(inst: CharInstance) -> Variant:
	if inst == null:
		return null
	return {
		"uid": inst.uid,
		"glyph": inst.glyph(),
		"owner": inst.owner,
		"temporary": inst.temporary,
		"word_only": inst.word_only,
		"fused": inst.fusion.duplicate(),
		"pollutions": inst.pollutions.duplicate(),
		"temp_uses": inst.temporary_uses,
		"gilded": inst.gilded,
		"refined": inst.refined,
		"pinned": inst.pinned,
		"pinned_exhausted": inst.pinned_exhausted,
	}


# ---------------------------------------------------------------- 合法动作
## 返回形如：
##  {"type":"play","path":[[x,y]...], "word":"击破"|null, "needs":"none|tile|2x2|empty|enemy|discard|glyph|line|fuse|same|merge|three|throw|bag"}
##  {"type":"end_turn"}
func legal_actions(limit := 60) -> Array:
	if is_done():
		return []
	if battle.manual_draw_pending > 0:
		return [{"type": "manual_draw", "glyphs": [], "count": battle.manual_draw_pending,
			"choices": _manual_draw_counts()}]
	var out: Array = []
	if not battle.pending_reveal.is_empty():
		out.append({"type": "cancel_choice"})
	if battle.formation_mode and not battle.formation_queue.is_empty() and battle.pending_reveal.is_empty():
		out.append({"type": "resolve_formation"})
	if battle.repeat_rotate_tile.x >= 0 and battle.repeat_rotate_count < 3:
		out.append({"type": "repeat_rotate"})
		out.append({"type": "end_repeat_rotate"})
	var found := _find_words()
	for f in found:
		if out.size() >= limit:
			break
		var w: WordData = f["word"]
		if not battle.pending_choice.is_empty() and f.path != battle.pending_choice.path:
			continue
		var needs := _needs_of(w)
		var spec := battle.play_options(f.path)
		if spec.reveal_count > 0:
			if not EffectTargets.preparation_error(battle, f.path).is_empty():
				continue
			if not battle.pending_reveal.is_empty() and not battle.inspect_play(f.path, _auto_target(needs, f.path)).ok:
				continue
		elif not battle.inspect_play(f.path, _auto_target(needs, f.path)).ok:
			continue
		out.append({
			"type": "play",
			"path": _path_out(f["path"]),
			"word": w.word,
			"needs": needs,
			"score": _score_word(w),
		})
	# 单字
	for i in battle.board.cells.size():
		if out.size() >= limit:
			break
		var inst: CharInstance = battle.board.cells[i]
		if inst == null or (inst.pinned and inst.pinned_exhausted):
			continue
		var solo := 0
		var pos := battle.board.to_xy(i)
		if not battle.pending_choice.is_empty():
			continue
		var needs: String = battle.play_options([pos]).needs
		if inst.data != null and not inst.word_only:
			for e in inst.data.solo_effects:
				solo += absi(e.amount)
		if not battle.inspect_play([pos], _auto_target(needs, [pos])).ok:
			continue
		var action := {"type": "play", "path": [_xy_out(pos)], "word": null,
			"needs": needs, "score": solo}
		if needs == "bag":
			action["bag_choices"] = battle.solo_bag_candidates(inst).map(func(card): return {
				"card": _cell_dict(card), "target": {"bag_uid": card.uid, "bag_source_uid": inst.uid}})
		out.append(action)
		if inst.data != null and not inst.word_only and inst.data.solo_handler == "solo_release" and inst.glyph_list().size() == 1 and battle.player.energy >= BattleBalance.i("release_cost", 1) and out.size() < limit:
			out.append({"type": "play", "path": [_xy_out(pos)], "word": null,
				"needs": "none", "score": 8, "target": {"release_energy": true}})
	if battle.pending_reveal.is_empty():
		out.append({"type": "end_turn"})
	return out


static func _xy_out(p: Vector2i) -> Array:
	return [p.x, p.y]


func _path_out(path: Array) -> Array:
	var out: Array = []
	for p in path:
		out.append(_xy_out(p))
	return out


## 把外部传入的坐标（[x,y] 数组 / "(x, y)" 字符串 / Vector2i）统一成 Vector2i
static func _to_xy(v) -> Vector2i:
	return EffectTargets.to_xy(v)


func _needs_of(w: WordData) -> String:
	return EffectTargets.needs_of(w)


func _score_word(w: WordData) -> int:
	var s := 0
	for e in w.effects:
		s += e.amount
		if e.semantic_kind() == EffectData.Kind.DAMAGE: s += 6
		if e.semantic_kind() == EffectData.Kind.DAMAGE_ALL: s += 8
		if e.semantic_kind() == EffectData.Kind.BLOCK: s += 3
		if e.semantic_kind() == EffectData.Kind.HEAL: s += 4
	return s


func _find_words() -> Array:
	_build_trie()
	var res: Array = []
	var seen: Dictionary = {}
	for i in battle.board.cells.size():
		if battle.board.cells[i] != null:
			_dfs(battle.board.to_xy(i), _trie, {}, res, seen, 24)
	return res


func _dfs(cell: Vector2i, node: Dictionary, path: Dictionary, res: Array, seen: Dictionary, cap: int) -> void:
	if res.size() >= cap:
		return
	var inst: CharInstance = battle.board.get_xy(cell)
	if inst == null or (inst.pinned and inst.pinned_exhausted) or battle.reserved_cells.has(cell):
		return
	var glyphs := inst.glyph_list()
	var sequences: Array = [glyphs]
	if glyphs.has("过"):
		sequences.append(glyphs.filter(func(g): return g != "过"))
	path[cell] = true
	for sequence in sequences:
		var nn: Dictionary = node
		var matches := true
		for glyph in sequence:
			if not nn.has(glyph):
				matches = false
				break
			nn = nn[glyph]
		if not matches:
			continue
		if nn.has("#"):
			var wid: String = nn["#"]
			if not seen.has(wid):
				seen[wid] = true
				res.append({"word": Database.words[wid], "path": path.keys()})
		for next in battle.board.path_extensions(path.keys()):
			_dfs(next, nn, path, res, seen, cap)
	path.erase(cell)


static func _build_trie() -> void:
	if not _trie.is_empty() and _trie_revision == Database.revision:
		return
	_trie.clear()
	_trie_revision = Database.revision
	for w in Database.words.values():
		var node := _trie
		for g in w.glyphs:
			if not node.has(g):
				node[g] = {}
			node = node[g]
		node["#"] = w.id


# ---------------------------------------------------------------- 执行
func apply(action: Dictionary) -> Dictionary:
	if is_done():
		return {"ok": false, "reason": "战斗已经结束"}
	var type := str(action.get("type", ""))
	if type == "inspect_play":
		return inspect(_norm_path(action.get("path", [])), action.get("target", {}) if action.get("target", {}) is Dictionary else {})
	if battle.manual_draw_pending > 0 and type != "manual_draw":
		return {"ok": false, "reason": "请先完成精心选字（glyphs: [] 为随机补齐）"}
	match type:
		"manual_draw":
			if battle.manual_draw_pending <= 0 or not action.get("glyphs", []) is Array:
				return {"ok": false, "reason": "没有待完成的选字，或 glyphs 格式无效"}
			return {"ok": true, "drawn": battle.place_manual_draw(action.get("glyphs", [])), "turn": battle.turn}
		"resolve_formation":
			if not battle.pending_reveal.is_empty():
				return {"ok": false, "reason": "请先完成或取消选字"}
			if not battle.formation_mode or battle.formation_queue.is_empty():
				return {"ok": false, "reason": "没有待结算的结阵"}
			battle.resolve_formation()
			_settle_forced_end()
			return {"ok": true, "turn": battle.turn}
		"repeat_rotate", "end_repeat_rotate":
			if battle.repeat_rotate_tile.x < 0:
				return {"ok": false, "reason": "没有正在进行的转速"}
			if type == "repeat_rotate":
				battle.do_repeat_rotate()
				if battle.repeat_rotate_count >= 3:
					battle.end_repeat_rotate()
			else:
				battle.end_repeat_rotate()
			return {"ok": true, "turn": battle.turn}
		"cancel_choice":
			if battle.pending_reveal.is_empty():
				return {"ok": false, "reason": "没有待取消的选字"}
			battle.return_pending_reveal()
			return {"ok": true, "turn": battle.turn}
		"end_turn":
			if not battle.pending_reveal.is_empty():
				return {"ok": false, "reason": "请先完成或取消选字"}
			battle.end_player_turn()
			return {"ok": true, "type": "end_turn", "turn": battle.turn}
		"play", "prepare_play":
			pass
		_:
			return {"ok": false, "reason": "未知动作类型：" + type}
	if not action.get("target", {}) is Dictionary:
		return {"ok": false, "reason": "target 必须为对象"}
	var path := _norm_path(action.get("path", []))
	var target := _norm_target(action.get("target", {}))
	var spec := battle.play_options(path)
	if type == "prepare_play":
		var preparation := battle.prepare_interaction(path)
		return {"ok": preparation.ok, "reason": preparation.get("reason", ""), "turn": battle.turn}
	if target.is_empty():
		if spec.reveal_count > 0 and battle.pending_reveal.is_empty():
			var preparation := battle.prepare_interaction(path)
			if not preparation.ok:
				return {"ok": false, "reason": preparation.reason, "turn": battle.turn}
		target = _auto_target(str(spec.needs), path)
	var result := battle.try_play(path, target)
	if not result.ok:
		invalid_tries += 1
		return {"ok": false, "reason": result.reason, "need_target": result.need_target, "turn": battle.turn}
	if result.word != null:
		word_plays += 1
	else:
		single_plays += 1
	_settle_forced_end()
	return {"ok": true, "word": result.word.word if result.word != null else "",
		"messages": result.messages.duplicate(), "queued": result.get("queued", false), "turn": battle.turn}


func _settle_forced_end() -> void:
	if battle.end_turn_requested:
		battle.end_turn_requested = false
		battle.end_player_turn()


func _manual_draw_counts() -> Dictionary:
	var counts := {}
	var cards: Array = battle.bag if not battle.bag.is_empty() else battle.discard
	for card in cards:
		counts[card.glyph()] = int(counts.get(card.glyph(), 0)) + 1
	return counts


func inspect(path: Array, target: Dictionary = {}) -> Dictionary:
	var spec := battle.play_options(path)
	var check := battle.inspect_play(path, target)
	var out := {"ok": check.ok, "reason": check.reason, "needs": spec.needs,
		"interaction": spec.interaction, "need_target": check.need_target,
		"requires_prepare": spec.reveal_count > 0 and battle.pending_reveal.is_empty(),
		"default_target": _json_value(EffectTargets.default_target(battle, str(spec.needs), path)),
		"cells": _path_out(spec.get("cells", [])),
		"cards": (spec.get("cards", []) as Array).map(_cell_dict)}
	if spec.word != null:
		out.word = spec.word.word
		out.preview = EffectDescriptions.word_text(spec.word, battle, path, _norm_target(target))
	elif path.size() == 1:
		out.preview = EffectDescriptions.solo_text(battle.board.get_xy(path[0]), battle, path, _norm_target(target))
	return out


func _json_value(value: Variant) -> Variant:
	if value is Vector2i:
		return _xy_out(value)
	if value is Array:
		return value.map(_json_value)
	if value is Dictionary:
		var out := {}
		for key in value:
			out[key] = _json_value(value[key])
		return out
	return value


func _norm_path(raw) -> Array:
	return EffectTargets.normalize_path(raw)


func _norm_target(d: Dictionary) -> Dictionary:
	return EffectTargets.normalize_target(d)


func _auto_target(needs: String, path: Array = []) -> Dictionary:
	return EffectTargets.default_target(battle, needs, path)


func summary() -> Dictionary:
	return {
		"seed": seed,
		"victory": (battle.is_victory() if battle != null else false),
		"turns": (battle.turn if battle != null else 0),
		"player_hp": (battle.player.hp if battle != null else 0),
		"word_plays": word_plays,
		"single_plays": single_plays,
		"invalid_tries": invalid_tries,
		"gold_earned": (battle.gold_earned if battle != null else 0),
	}
