extends ScreenBase
## 战后奖励：三选一增字，或跳过换铜钱。
## 经典模式：精英先给 1 件遗物；首领（最后一幕除外）先回血，再三选一遗物。
## 庭院路线的首领沿用控制器提供的两件候选。

## 首领战后回复最大气血的比例
const BOSS_HEAL_RATIO := 0.3

var node: MapNodeData
var _options: Array = []
var _room_run := false
var _expedition := false   ## 墨途远征：选中的字直接入字袋，回远征地图
var _cards: Array[GlyphOffer] = []
var _showcase: Control
var _hud: Control
var _selected := -1
var _busy := false
var _boss_heal := 0
var _settled := false
var _reward_owner: RefCounted
var _reward_room := ""
var _relic_kind := ""
var _relic_choices: Array = []
var _relic_pending := false
var _relic_taken := ""
var _selected_kind := "glyph"
var _selected_relic := 0
var _gold_object := -1
var _gold_offer: GlyphOffer
var _relic_objects: Array[int] = []
var _relic_offers: Array[GlyphOffer] = []
var _relic_ids: Array = []
var _comparison_open := false


func has_scene_background() -> bool:
	return true


func build(root: Control) -> void:
	JourneyStyle.apply(self)
	node = params.get("node", null)
	_expedition = params.get("expedition", false) and GameState.expedition != null
	var is_boss := node != null and node.type == MapNodeData.Type.BOSS
	var reward_act: int = GameState.expedition.act if _expedition else GameState.act_index
	if is_boss and reward_act >= 3:
		if params.get("room_run", false) and GameState.room_run != null:
			GameState.room_run._finish_final_boss()
		elif not _expedition and not GameState.run_complete():
			GameState.complete_current_node()
		goto.call_deferred("res://src/screens/run_result_screen.gd", {"victory":true, "location":node.title})
		return
	var saved: Dictionary = params.get("_saved_screen", {})
	_room_run = params.get("room_run", false) and GameState.room_run != null
	if _room_run:
		_reward_owner = GameState.room_run
		_reward_room = _reward_owner.current_room
		# Settlement clears the run's pending list. The displayed offers must keep
		# their own stable snapshot throughout the take animation and callbacks.
		_options = _reward_owner.reward_options.duplicate()
		_relic_choices = _reward_owner.contents[_reward_room].get("battle_relics", []).duplicate()
		_relic_pending = not _relic_choices.is_empty()
		_relic_taken = str(_reward_owner.contents[_reward_room].get("battle_relic_taken", ""))
	else:
		_options = saved.options if saved.has("options") else _roll_options(is_boss, int(params.get("count", 3)))
		if saved.has("relic_kind"):
			_relic_kind = str(saved.relic_kind)
			_relic_choices = saved.get("relic_choices", [])
			_relic_pending = bool(saved.get("relic_pending", false))
			_relic_taken = str(saved.get("relic_taken", ""))
			_boss_heal = int(saved.get("boss_heal", 0))
		else:
			if not _room_run and not _expedition and node != null and not params.get("relic_done", false):
				if node.type == MapNodeData.Type.ELITE: _relic_kind = "elite"
				elif is_boss and GameState.act_index < 3: _relic_kind = "boss"
			if _relic_kind == "boss":
				_boss_heal = mini(GameState.player_max_hp - GameState.player_hp, int(round(GameState.player_max_hp * BOSS_HEAL_RATIO)))
				GameState.heal(_boss_heal)
			if not _relic_kind.is_empty():
				_relic_choices = RelicRewardFlow.roll(3 if _relic_kind == "boss" else 1)
				_relic_pending = not _relic_choices.is_empty()
	_showcase = preload("res://src/ui/object_stage/object_stage_view.gd").new()
	_showcase.mode = "reward"
	_showcase.reward_loot_layout = true
	_showcase.reward_count = _options.size()
	root.add_child(_showcase)
	_hud = preload("res://src/ui/object_stage/object_hud.gd").new()
	_hud.heading = "幕末 · 馈赠" if is_boss else "战后 · 馈赠"
	if _room_run and GameState.room_run.graph.rooms[GameState.room_run.current_room].kind=="treasure": _hud.heading = "荷池 · 藏字"
	_hud.instruction = "活字与铜钱择一；遗物候选中选一件。" if _relic_pending else "选择一枚活字收入字袋，或不择字换铜钱。"
	_hud.status = "气血 %d / %d    铜钱 %d" % [GameState.player_hp, GameState.player_max_hp, GameState.gold]
	_hud.action_text = "收入字袋"
	_hud.secondary_text = "收下这幕的馈赠" if is_boss else "跳过 · 获得 %d 铜钱" % Expedition.SKIP_GOLD
	if _room_run: _hud.secondary_text = "跳过 · 获得 %d 铜钱" % Expedition.SKIP_GOLD
	_hud.on_action = _accept_selected
	_hud.on_secondary = _secondary_action
	root.add_child(_hud)
	for i in _options.size():
		var ch: CharacterData = _options[i]
		_showcase.stage.add_object(ch.glyph, i, ch.rarity)
		var offer := GlyphOffer.new()
		offer.character = ch
		offer.caption = "%02d   %s" % [i + 1, ch.glyph]
		offer.clicked.connect(_inspect.bind(i))
		root.add_child(offer)
		_cards.append(offer)
	_build_loot(root)
	_showcase.layout_changed.connect(_layout_cards)
	_layout_cards.call_deferred()
	_hud.set_detail("点击活字选中", "左键点击一枚活字查看效果并选中，再点击领取按钮确认。")
	_set_busy(false)
	_showcase.stage.open_case()
	if _relic_pending:
		_inspect_relic(0)



func _build_loot(root: Control) -> void:
	_gold_object = _showcase.stage.add_reward_gold(Expedition.SKIP_GOLD)
	_gold_offer = GlyphOffer.new()
	_gold_offer.name = "GoldReward"
	_gold_offer.caption = "不择字 · +%d 铜钱" % Expedition.SKIP_GOLD
	_gold_offer.tooltip_text = "放弃本次活字奖励，换取 %d 铜钱。" % Expedition.SKIP_GOLD
	_gold_offer.clicked.connect(_take_gold)
	root.add_child(_gold_offer)
	_relic_ids = _relic_choices.duplicate() if _relic_pending else []
	for i in _relic_ids.size():
		var id: String = _relic_ids[i]
		_relic_objects.append(_showcase.stage.add_reward_relic(id, i, _relic_ids.size()))
		var offer := GlyphOffer.new()
		offer.name = "RelicReward_" + id
		offer.caption = ("已领 · " if not _relic_pending else "") + Relics.name_of(id)
		offer.tooltip_text = Relics.text(id)
		offer.clicked.connect(_take_relic.bind(i))
		root.add_child(offer)
		_relic_offers.append(offer)


func _layout_loot_offer(offer: GlyphOffer, object_index: int) -> void:
	var rect: Rect2 = _showcase.loot_rect(object_index)
	offer.position = rect.position
	offer.size = rect.size
	var scale := JourneyStyle.touch_scale(self)
	var width := maxf(rect.size.x, (112 if offer == _gold_offer else 84) * scale)
	offer._caption.add_theme_font_size_override("font_size", int((13 if scale > 1.1 else 15) * scale))
	offer._caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	offer._caption.position = Vector2((rect.size.x - width) * 0.5, rect.size.y + 2 * scale)
	offer._caption.size = Vector2(width, 30 * scale)
	offer._caption.add_theme_color_override("font_shadow_color", Color("10262f"))
	offer._caption.add_theme_constant_override("shadow_offset_y", maxi(1, int(scale)))


func _clear_loot_selection() -> void:
	_gold_offer.set_selected(false)
	for offer in _relic_offers: offer.set_selected(false)


func _inspect_gold() -> void:
	if _busy: return
	_selected_kind = "gold"
	_clear_loot_selection()
	for card in _cards: card.set_selected(false)
	_gold_offer.set_selected(true)
	_showcase.stage.select_object(_gold_object)
	_hud.set_detail("铜钱 · +%d" % Expedition.SKIP_GOLD, "放弃本次活字奖励，换取 %d 铜钱。%s" % [Expedition.SKIP_GOLD, "请先领取遗物，再决定是否择字。" if _relic_pending else "点击钱堆或确认按钮领取。"])
	_update_reward_actions()


func _inspect_relic(index: int) -> void:
	if _busy or index < 0 or index >= _relic_ids.size(): return
	_selected_kind = "relic"
	_selected_relic = index
	_clear_loot_selection()
	for card in _cards: card.set_selected(false)
	_relic_offers[index].set_selected(true)
	_showcase.stage.select_object(_relic_objects[index])
	var id: String = _relic_ids[index]
	_hud.set_detail(Relics.name_of(id) + ("" if _relic_pending else " · 已领取"), Relics.desc_of(id))
	_update_reward_actions()


func _update_reward_actions() -> void:
	_hud.action_button.disabled = _busy or (_selected_kind == "glyph" and _selected < 0) or (_selected_kind == "relic" and not _relic_pending) or (_relic_pending and _selected_kind != "relic")
	_hud.secondary_button.disabled = _busy
	_hud.secondary_button.text = "比较遗物" if _relic_pending else "不择字 · +%d 铜钱" % Expedition.SKIP_GOLD
	if _selected_kind == "relic": _hud.action_button.text = "领取遗物" if _relic_pending else "已领取"
	elif _selected_kind == "gold": _hud.action_button.text = "换取 %d 铜钱" % Expedition.SKIP_GOLD
	else: _hud.action_button.text = "收入字袋"


func _selected_object() -> int:
	if _selected_kind == "gold": return _gold_object
	if _selected_kind == "relic": return _relic_objects[_selected_relic]
	return _selected


func _accept_selected() -> void:
	match _selected_kind:
		"relic": _take_relic(_selected_relic)
		"gold": _take_gold()
		_: _accept_pick()


func _secondary_action() -> void:
	if _relic_pending:
		if _room_run: _offer_room_relics()
		else: _offer_relics()
	else: _on_skip()


func _take_relic(index: int) -> void:
	if _busy or _settled or not _relic_pending or index < 0 or index >= _relic_choices.size(): return
	_inspect_relic(index)
	_set_busy(true)
	if Settings.reduced_motion:
		_grant_relic(index)
	else:
		_showcase.stage.take(_relic_objects[index])
		create_tween().tween_interval(0.24).finished.connect(_grant_relic.bind(index))


func _grant_relic(index: int) -> void:
	if not is_inside_tree() or not _relic_pending or _settled: return
	var id: String = _relic_choices[index]
	if _room_run:
		if GameState.room_run != _reward_owner or _reward_owner.current_room != _reward_room:
			_claim_failed("当前遗物奖励已变化，请返回当前路线。")
			return
		var result: Dictionary = _reward_owner.apply({"type": "reward_relic", "index": index})
		if not result.get("ok", false):
			_claim_failed(str(result.get("reason", "遗物领取失败")))
			return
		RelicRewardFlow.bind_owned(self, id, _on_relic_taken)
	else:
		RelicRewardFlow.grant(self, id, _on_relic_taken)


func _offer_room_relics() -> void:
	if _busy or not _relic_pending: return
	_comparison_open = true
	_set_busy(true)
	var ids: Array = _reward_owner.contents[_reward_room].get("battle_relics",[]).duplicate()
	var overlay := ChoiceOverlay.new()
	var options: Array = ids.map(func(id):return {"text":"遗物「%s」" % Relics.name_of(id),"relic_id":id,"hint":Relics.desc_of(id)})
	overlay.setup({"title":"幕末 · 遗物" if node.type==MapNodeData.Type.BOSS else "精英战利品", "body":"选择一件遗物，然后择字。", "options":options,"compact":true,"physical_relics":true})
	overlay.chose.connect(func(index: int):
		_comparison_open = false
		if GameState.room_run!=_reward_owner or _reward_owner.current_room!=_reward_room: return
		var result: Dictionary = _reward_owner.apply({"type":"reward_relic","index":index})
		if not result.get("ok",false):
			_claim_failed(str(result.get("reason", "遗物领取失败")))
			return
		RelicRewardFlow.bind_owned(self,str(ids[index]),func(_id):
			_reward_owner._save_if_enabled()
			_set_busy(false)
			_on_relic_taken(_id)))
	add_child(overlay)


func _offer_relics() -> void:
	if _busy or not _relic_pending: return
	_comparison_open = true
	_set_busy(true)
	var title := "精英战利品" if _relic_kind == "elite" else "幕末 · 遗物"
	var body := "击败精英，得到一件遗物。" if _relic_kind == "elite" else "首领倒下，气血回复 %d 点。从三件遗物中选一件。" % _boss_heal
	if _relic_kind == "boss" and _relic_choices.size() < 3:
		body = "首领倒下，气血回复 %d 点。剩余未拥有的遗物不足三件，选择一件。" % _boss_heal
	RelicRewardFlow.offer(self, title, body, _relic_choices, _on_relic_taken)
	for child in get_children():
		if child is ChoiceOverlay and child.cfg.get("physical_relics", false):
			child.chose.connect(func(_index): _comparison_open = false)


func _on_relic_taken(id: String) -> void:
	if not is_inside_tree(): return
	_comparison_open = false
	if id.is_empty():
		_claim_failed("遗物未能领取，请重新选择。")
		return
	_relic_pending = false
	_relic_taken = id
	params["relic_done"] = true
	if _room_run and GameState.room_run == _reward_owner and _reward_owner.current_room == _reward_room:
		_reward_owner.contents[_reward_room]["battle_relic_taken"] = id
		_reward_owner._save_if_enabled()
	while not _relic_objects.is_empty(): _showcase.stage.remove_object(_relic_objects.pop_back())
	for offer in _relic_offers:
		offer.get_parent().remove_child(offer)
		offer.queue_free()
	_relic_offers.clear()
	_relic_ids.clear()
	_selected_kind = "glyph"
	_selected = -1
	_hud.instruction_label.text = "选择一枚活字收入字袋，或不择字换铜钱。"
	_hud.status_label.text = "气血 %d / %d    铜钱 %d" % [GameState.player_hp, GameState.player_max_hp, GameState.gold]
	_set_busy(false)
	_inspect(0)
	SaveManager.request_save()



func _layout_cards() -> void:
	var scale := JourneyStyle.touch_scale(self)
	var compact := scale > 1.1
	for i in _cards.size():
		var rect: Rect2 = _showcase.object_rect(i)
		_cards[i].position = rect.position
		_cards[i].size = rect.size
		# Rear-row captions sit above the boards, clear of the front-row relics.
		var caption := _cards[i]._caption
		# On phones the board face already names the glyph; a duplicate label
		# cannot fit between the top HUD and the selected board's raised pose.
		caption.visible = not compact
		caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		caption.position = Vector2(0, -40 * scale)
		caption.size = Vector2(rect.size.x, 22 * scale)
		caption.add_theme_font_size_override("font_size", int(15 * scale))
		caption.add_theme_color_override("font_shadow_color", Color("10262f"))
		caption.add_theme_constant_override("shadow_offset_y", maxi(1, int(scale)))
	if is_instance_valid(_gold_offer): _layout_loot_offer(_gold_offer, _gold_object)
	for i in _relic_offers.size(): _layout_loot_offer(_relic_offers[i], _relic_objects[i])


func _inspect(index: int) -> void:
	if _busy or _relic_pending or index < 0 or index >= _options.size(): return
	_selected = index
	_selected_kind = "glyph"
	_clear_loot_selection()
	for i in _cards.size(): _cards[i].set_selected(i == index)
	_showcase.stage.select_object(index)
	var ch: CharacterData = _options[index]
	_hud.set_detail("%s  ·  %s" % [ch.glyph, ch.pinyin], _with_hint(ch).description)
	_update_reward_actions()


func _accept_pick() -> void:
	if _busy or _relic_pending or _settled or _selected<0 or _selected>=_options.size(): return
	_set_busy(true)
	var choice: CharacterData = _options[_selected]
	if Settings.reduced_motion:
		_on_pick(choice)
	else:
		_showcase.stage.take(_selected)
		create_tween().tween_interval(0.24).finished.connect(_on_pick.bind(choice))


func _set_busy(value: bool) -> void:
	_busy = value
	_update_reward_actions()


func _claim_failed(reason: String) -> void:
	_set_busy(false)
	_showcase.stage.restore_object(_selected_object())
	_hud.set_detail("奖励未领取",reason)


func _claim_room_reward(action: Dictionary) -> bool:
	if GameState.room_run!=_reward_owner or _reward_owner.current_room!=_reward_room:
		_claim_failed("当前奖励已变化，请重新打开当前庭院的奖励。")
		return false
	var result: Dictionary = _reward_owner.apply(action)
	if not result.get("ok",false):
		_claim_failed(str(result.get("reason","领取失败，请重试。")))
		return false
	_settled = true
	return true


func _roll_options(is_boss: bool, count := 3) -> Array:
	var pool := _reward_pool(is_boss)
	var out: Array = []
	var rng := GameState.rng
	var guard := 0
	while out.size() < count and guard < 200:
		guard += 1
		var c: CharacterData = pool[rng.randi_range(0, pool.size() - 1)]
		if out.any(func(x): return x.id == c.id):
			continue
		out.append(c)
	return out


func _reward_pool(is_boss: bool) -> Array:
	var pool: Array = []
	for c in Database.characters.values():
		if c.is_pollution or c.pending_design or c.tags.has("enemy") or c.tags.has("彩蛋") or c.tags.has("event"):
			continue
		if is_boss:
			if c.rarity >= 1:
				pool.append(c)
		else:
			if c.rarity <= 2:
				pool.append(c)
	if pool.is_empty():
		pool = Database.characters.values()
	return pool


func _with_hint(c: CharacterData) -> CharacterData:
	var copy: CharacterData = c.duplicate()
	copy.description = EffectGlossary.character_hint(c)
	return copy


func _words_for(glyph: String) -> Array:
	return EffectGlossary.words_for_glyph(glyph)


func _on_pick(c: CharacterData) -> void:
	if _relic_pending or _settled: return
	_set_busy(true)
	if c==null or not _options.has(c):
		_claim_failed("无效奖励，请重新选择。")
		return
	if _room_run:
		if not _claim_room_reward({"type":"reward","index":_options.find(c),"glyph":c.glyph}): return
		goto("res://src/screens/room_map_screen.gd")
		return
	_settled = true
	if _expedition:
		GameState.expedition.receive_reward_glyph(c)
	else:
		GameState.add_character(c, 1)
	_leave()


func _on_skip() -> void:
	_take_gold()


func _take_gold() -> void:
	if _busy or _relic_pending or _settled: return
	_inspect_gold()
	_set_busy(true)
	if Settings.reduced_motion:
		_finish_skip()
	else:
		_showcase.stage.take(_gold_object)
		create_tween().tween_interval(0.24).finished.connect(_finish_skip)


func _finish_skip() -> void:
	if _relic_pending or _settled: return
	if _room_run:
		if not _claim_room_reward({"type":"skip"}): return
		goto("res://src/screens/room_map_screen.gd")
		return
	_settled = true
	GameState.add_gold(Expedition.SKIP_GOLD)
	_leave()


func _leave() -> void:
	if _expedition:
		goto("res://src/screens/expedition_map_screen.gd")
		return
	GameState.complete_current_node()
	if GameState.run_complete():
		_try_victory()
	else:
		goto("res://src/screens/map_screen.gd")


func _try_victory() -> void:
	goto("res://src/screens/run_result_screen.gd", {"victory":true})


func save_checkpoint() -> Dictionary:
	if _busy and not _comparison_open: return {}
	# A binding picker has already granted the relic; keep the preceding whole transaction.
	for child in get_children():
		if child is CollectionOverlay: return {}
	var snapshot := super.save_checkpoint()
	snapshot.screen = {"options": _options, "relic_kind": _relic_kind, "relic_choices": _relic_choices, "relic_pending": _relic_pending, "boss_heal": _boss_heal, "relic_taken": _relic_taken}
	return snapshot
