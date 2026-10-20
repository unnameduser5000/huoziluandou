extends Control
## 效果协议：新效果完整接入、查询无副作用、UI / AI 一致、多阶段选择与 JSON 边界。

var _checks := 0
var _failures := 0
var _executions := 0
const CUSTOM := "contract_test:block"


func _ready() -> void:
	get_tree().create_timer(40).timeout.connect(func(): push_error("效果协议测试超时"); get_tree().quit(1))
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(text)


func _frames(n := 4) -> void:
	for i in n:
		await get_tree().process_frame


func _h(word := "击破") -> BattleHarness:
	var h := BattleHarness.new()
	var board: Array = []
	board.resize(16)
	board.fill("")
	for i in word.length():
		board[i] = word[i]
	board[6] = "防"
	h.reset({"seed": 7, "opening_draw": 0, "turn_draw": 3, "enemies": ["iron_seal"],
		"deck": ["火", "回", "流", "连"], "board": board, "gold": 30})
	return h


func _signature(b: BattleState) -> String:
	return var_to_str({"rng": b.rng.state, "uid": CharInstance._next_uid, "gold": GameState.gold,
		"board": b.board.cells.map(func(c): return c.uid if c != null else 0),
		"bag": b.bag.map(func(c): return c.uid), "discard": b.discard.map(func(c): return c.uid),
		"reveal": b.pending_reveal.map(func(c): return c.uid), "choice": b.pending_choice,
		"player": [b.player.hp, b.player.block, b.player.energy, b.player.heat],
		"abilities": b.abilities, "history": b.last_played_glyphs, "log": b.log,
		"queue": b.formation_queue, "reserved": b.reserved_cells, "double_armed": b.get("_double_armed")})


func _cards(b: BattleState) -> Array:
	var cards := b.bag + b.discard + b.pending_reveal + b.board.cells.filter(func(c): return c != null)
	for play in b.formation_queue:
		cards.append_array(play.get("revealed", []))
	var ids := cards.map(func(c): return c.uid)
	ids.sort()
	return ids


func _custom_data() -> CharacterData:
	var cd := Database.get_character_by_glyph("击").duplicate() as CharacterData
	var effect := EffectData.new()
	effect.handler = CUSTOM
	effect.amount = 3
	cd.description = "获得3临时格挡。"
	cd.solo_handler = CUSTOM
	cd.solo_effects.assign([effect])
	return cd


func _register() -> void:
	var definition := {"kind": EffectData.Kind.BLOCK, "required_target": EffectData.Target.BOARD_TILE,
		"execute": func(effect: EffectData, context: Dictionary) -> Array:
			_executions += 1
			context.battle.player.add_block(effect.amount)
			return ["协议获得%d临挡" % effect.amount],
		"validate": func(_effect: EffectData, context: Dictionary) -> String:
			var tile: Vector2i = context.target.get("tile", Vector2i(-1, -1))
			var c: CharInstance = context.battle.board.get_xy(tile)
			return "请选择另一枚非固定字" if c == null or c.pinned or context.path.has(tile) else "",
		"targets": func(_effect: EffectData, _context: Dictionary) -> Dictionary:
			return {"cells": [Vector2i(2, 1)], "default": {"tile": Vector2i(2, 1)}},
		"preview": func(effect: EffectData, _context: Dictionary) -> String:
			return "协议预览%d临挡" % effect.amount,
		"describe": func(effect: EffectData) -> String:
			return "协议说明%d临挡" % effect.amount,
	}
	_check(EffectRegistry.register_handler(CUSTOM, definition), "新效果可一次注册分类、目标、预览和执行")
	_check(not EffectRegistry.register_handler(CUSTOM, definition), "重复注册不会覆盖既有定义")
	_check(not EffectRegistry.register_handler("damage", definition), "内置旧名称不会被扩展隐式覆盖")
	_check(not EffectRegistry.register_handler("contract_test:invalid", {}), "缺少执行回调的定义被拒绝")
	_check(not EffectRegistry.register_handler("contract_test:invalid", {"execute": 123}), "错误回调类型不会触发运行错误")
	_check(not EffectRegistry.register_handler("contract_test:invalid", {"execute": definition.execute, "preview": Callable()}), "失效的可选回调在注册时被拒绝")
	_check(not EffectRegistry.register_handler("contract_test:invalid", {"execute": definition.execute, "required_target": 999}), "未知目标类别在注册时被拒绝")


func _test_custom() -> void:
	var h := _h()
	var cd := _custom_data()
	var effect: EffectData = cd.solo_effects[0]
	var source := CharInstance.new(cd)
	h.battle.board.set_cell(0, 0, source)
	h.battle.board.set_cell(1, 0, null)
	_check(effect.semantic_kind() == EffectData.Kind.BLOCK and not effect.is_attack(), "自定义分类不被旧资源默认 DAMAGE 误判")
	_check(effect.describe() == "协议说明3临挡", "说明来自同一效果定义")
	var before := _signature(h.battle)
	var spec := h.battle.play_options([Vector2i.ZERO])
	var preview := EffectPreview.solo_text(source, h.battle, [Vector2i.ZERO])
	var options := h.apply({"type": "inspect_play", "path": [[0, 0]]})
	var legal := h.legal_actions()
	_check(_signature(h.battle) == before and _executions == 0, "候选、预检、AI 观察和预览都不提前执行或改变状态")
	_check(spec.required_target == EffectData.Target.BOARD_TILE and spec.cells == [Vector2i(2, 1)], "新效果的目标约束被统一识别")
	_check("协议预览3临挡" in preview and options.cells == [[2, 1]], "UI 预览与 JSON 候选来自同一注册定义")
	_check(legal.any(func(a): return a.type == "play" and a.path == [[0, 0]]), "AI 能发现需要自定义目标的单字")
	var invalid := h.apply({"type": "play", "path": [[0, 0]], "target": {"tile": [0, 0]}})
	_check(not invalid.ok and _signature(h.battle) == before, "非法目标在消耗字和资源之前拒绝")
	var r := h.apply({"type": "play", "path": [[0, 0]]})
	_check(r.ok and h.battle.player.block == 3 and _executions == 1 and h.battle.discard.has(source), "AI 的默认目标与正式执行共用规则，恰好执行一次")
	var row_id := "contract_test:row"
	EffectRegistry.register_handler(row_id, {"execute": func(_e, _ctx): return [], "required_target": EffectData.Target.BOARD_ROW})
	h = _h()
	cd = _custom_data()
	cd.solo_effects[0].handler = row_id
	h.battle.board.set_cell(0, 0, CharInstance.new(cd))
	before = _signature(h.battle)
	_check(not h.apply({"type": "play", "path": [[0, 0]], "target": {"row": 99}}).ok and _signature(h.battle) == before, "注册的选行规则也在消耗前检查棋盘范围")
	EffectRegistry.unregister_handler(row_id)


func _test_interactions() -> void:
	for word in ["火急", "转化", "合流"]:
		var h := _h(word)
		h.battle.discard.append(CharInstance.new(Database.get_character_by_glyph("御")))
		var before := _signature(h.battle)
		var actions := h.legal_actions()
		_check(_signature(h.battle) == before, word + "的合法动作查询不揭示、不洗牌")
		var action: Dictionary = {}
		for a in actions:
			if a.get("word", "") == word:
				action = a
		_check(not action.is_empty(), word + "在材料满足时可被 AI 发现")
		var old_target: CharInstance = h.battle.board.get_cell(2, 1)
		var r := h.apply(JSON.parse_string(JSON.stringify(action)))
		var worked: bool = h.battle.board.get_cell(2, 1) != old_target if word == "转化" else h.battle.board.fill_count() == 3
		_check(r.ok and worked and h.battle.pending_reveal.is_empty() and h.battle.pending_choice.is_empty(), word + "经真实 JSON 往返完成揭示与落地，不再空放：" + str(r))
	var h := _h("收复")
	var card := CharInstance.new(Database.get_character_by_glyph("御"))
	h.battle.discard.append(card)
	var before := _signature(h.battle)
	var duplicate: Dictionary = JSON.parse_string(JSON.stringify({"type": "play", "path": [[0, 0], [1, 0]], "target": {"places": [[card.uid, [0, 2]], [card.uid, [1, 2]]]}}))
	_check(not h.apply(duplicate).ok and _signature(h.battle) == before, "收复重复 UID 先拒绝，施词字和弃字保持原状")
	var valid: Dictionary = JSON.parse_string(JSON.stringify({"type": "play", "path": [[0, 0], [1, 0]], "target": {"places": [[card.uid, [0, 2]]]}}))
	_check(h.apply(valid).ok and h.battle.board.get_cell(0, 2) == card, "JSON 嵌套 places 坐标正确转换为原实体落地")
	h = _h("火急")
	var ids := _cards(h.battle)
	_check(h.apply({"type": "prepare_play", "path": [[0, 0], [1, 0]]}).ok and h.battle.pending_reveal.size() == 2, "UI 与 AI 可以显式开始多阶段选字")
	before = _signature(h.battle)
	_check(h.apply({"type": "prepare_play", "path": [[0, 0], [1, 0]]}).ok and _signature(h.battle) == before, "同一选字重复开始不会覆盖或丢失揭示字")
	h.apply({"type": "cancel_choice"})
	_check(_cards(h.battle) == ids and h.battle.pending_choice.is_empty(), "取消选字归还全部实体并清理选择状态")
	before = _signature(h.battle)
	_check(not h.apply({"type": "unknown"}).ok and _signature(h.battle) == before, "未知动作不会被当成出字或结束回合")
	_check(not h.apply({"type": "cancel_choice"}).ok and _signature(h.battle) == before, "没有选字时取消不会意外洗牌")


func _test_special_phases() -> void:
	var h := _h("精心")
	h.apply({"type": "play", "path": [[0, 0], [1, 0]]})
	h.apply({"type": "end_turn"})
	_check(h.observe().manual_draw_pending == 2 and h.legal_actions()[0].type == "manual_draw", "精心选字阶段可被 AI 观察和完成")
	_check(h.apply(h.legal_actions()[0]).ok and h.battle.manual_draw_pending == 0, "放弃指定字时也按规则随机补齐额度")
	h = _h("合击")
	h.apply({"type": "play", "path": [[0, 0], [1, 0]]})
	_check(not h.legal_actions().any(func(a): return a.get("word", "") == "合击"), "登记过的结阵词不会继续作为合法动作返回")
	_check(h.apply({"type": "resolve_formation"}).ok and h.battle.formation_queue.is_empty() and h.battle.turn == 1, "结阵可以在同一回合主动结算")
	h = _h("转速")
	h.apply({"type": "play", "path": [[0, 0], [1, 0]], "target": {"tile": [0, 0]}})
	_check(h.apply({"type": "repeat_rotate"}).ok and h.battle.repeat_rotate_count == 2, "转速可通过 AI 接口继续旋转")
	_check(h.apply({"type": "end_repeat_rotate"}).ok and h.battle.repeat_rotate_tile.x < 0, "转速可通过 AI 接口提前结束")
	# 结阵各自持有揭示字；队列中另一条效果不能覆盖它。
	h = _h("火急")
	h.battle.begin_formation()
	var ids := _cards(h.battle)
	h.apply({"type": "play", "path": [[0, 0], [1, 0]]})
	_check(h.battle.pending_reveal.is_empty() and _cards(h.battle) == ids, "结阵登记后揭示字由该队列条目独立保存")
	h.apply({"type": "resolve_formation"})
	_check(h.battle.board.fill_count() == 3 and _cards(h.battle) == ids, "带揭示选择的词在结阵结算时仍能正确补字并守恒")
	_test_formation_reveals()


func _test_formation_reveals() -> void:
	var h := _h("火急")
	h.battle.board.set_cell(0, 1, CharInstance.new(Database.get_character_by_glyph("火")))
	h.battle.board.set_cell(1, 1, CharInstance.new(Database.get_character_by_glyph("急")))
	h.battle.begin_formation()
	var ids := _cards(h.battle)
	for row in 2:
		var path := [[0, row], [1, row]]
		h.apply({"type": "prepare_play", "path": path})
		var result := h.apply({"type": "play", "path": path, "target": {"cell1": [row * 2, 2], "cell2": [row * 2 + 1, 2]}})
		_check(result.ok and _cards(h.battle) == ids, "两次火急分别登记，不覆盖另一批揭示实体")
	h.battle.resolve_formation()
	_check(h.battle.board.fill_count() == 5 and _cards(h.battle) == ids and h.battle.bag.is_empty(), "两批揭示字在结阵中分别落地且实体守恒")
	h = _h("火急")
	h.battle.begin_formation()
	h.apply({"type": "prepare_play", "path": [[0, 0], [1, 0]]})
	ids = _cards(h.battle)
	var before := _signature(h.battle)
	_check(not h.apply({"type": "resolve_formation"}).ok and _signature(h.battle) == before, "正在选择的揭示字不会被提前发动结阵覆盖")
	h.apply({"type": "play", "path": [[0, 0], [1, 0]], "target": {"cell1": [0, 2], "cell2": [1, 2]}})
	h.battle.board.set_cell(0, 2, h.battle.board.get_cell(2, 1))
	h.battle.board.set_cell(2, 1, null)
	h.battle.resolve_formation()
	_check(h.battle.board.get_cell(0, 0) != null and h.battle.bag.size() == 4 and _cards(h.battle) == ids, "结阵落点失效时保留施词字，并归还该条目的全部揭示字")
	h = _h("停")
	h.battle.board.set_cell(0, 1, CharInstance.new(Database.get_character_by_glyph("火")))
	h.battle.board.set_cell(1, 1, CharInstance.new(Database.get_character_by_glyph("急")))
	h.battle.begin_formation()
	ids = _cards(h.battle)
	h.apply({"type": "play", "path": [[0, 0]]})
	h.apply({"type": "play", "path": [[0, 1], [1, 1]]})
	h.battle.resolve_formation()
	_check(h.battle.end_turn_requested and h.battle.board.get_cell(0, 1) != null and h.battle.bag.size() == 4 and _cards(h.battle) == ids, "提前结束结阵时，未执行条目的揭示字全部归还")


func _test_ui() -> void:
	GameState.start_new_run()
	var screen: Control = load("res://src/screens/battle_screen.gd").new()
	screen.setup({"seed": 7})
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _frames()
	var b: BattleState = screen.battle
	b.board.cells.fill(null)
	b.bag.clear()
	b.discard.clear()
	b.board.set_cell(0, 0, CharInstance.new(_custom_data()))
	b.board.set_cell(2, 1, CharInstance.new(Database.get_character_by_glyph("防")))
	screen._refresh_all()
	var executed := _executions
	screen._on_commit([Vector2i.ZERO])
	_check(screen._board_view.pick_mode == "any" and not screen._board_view.pick_excluded.has(Vector2i(2, 1)), "新效果在真实 UI 自动使用公共目标候选")
	_check(b.board.get_cell(0, 0) != null and _executions == executed, "打开选择阶段不会提前执行效果")
	screen._on_tile_picked(Vector2i(2, 1))
	_check("协议预览3临时格挡" in screen._bubble.body.get_parsed_text(), "选目标后的真实 UI 预览来自同一效果定义")
	screen._on_primary()
	var deadline := Time.get_ticks_msec() + 5000
	while screen._busy and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.01).timeout
	_check(not screen._busy and b.player.block == 3 and _executions == executed + 1 and b.board.get_cell(0, 0) == null, "同一自定义效果可从 UI 完整选择、预览并执行一次")
	screen.queue_free()
	await _frames()


func _run() -> void:
	_register()
	_test_custom()
	_test_interactions()
	_test_special_phases()
	await _test_ui()
	EffectRegistry.unregister_handler(CUSTOM)
	var h := _h()
	h.battle.board.set_cell(0, 0, CharInstance.new(_custom_data()))
	var before := _signature(h.battle)
	var missing := h.apply({"type": "play", "path": [[0, 0]], "target": {"tile": [2, 1]}})
	_check(not missing.ok and "未注册" in missing.reason and before == _signature(h.battle), "缺失的扩展效果明确报错并保留施放状态")
	_check(_checks >= 40, "所有协议用例完整执行")
	print("[effect_contract_test] PASS=%d FAIL=%d" % [_checks - _failures, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
