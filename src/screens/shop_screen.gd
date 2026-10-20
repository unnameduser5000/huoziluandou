extends ScreenBase
## 商店：定向增字、复制、删字、治疗，外加一件遗物（统一 45 铜钱）。价格取自 GDD V0.3 测试起点。

const SERVICE_SLOT := 5
const RELIC_SLOT := 8
const LAYOUT_VERSION := 2

var node: MapNodeData
var _offers: Array = []       ## [{kind, character, price}]
var _showcase: Control
var _hud: Control
var _cards: Array[GlyphOffer] = []
var _selected := 0
var _busy := false
var _pending_offer_index := -1
var _pending_kind := ""
var _room_session: RefCounted
var _shop_overlay: ChoiceOverlay
var _refresh_count := 0


func has_scene_background() -> bool:
	return true


func build(root: Control) -> void:
	JourneyStyle.apply(self)
	node = params.get("node", null)
	if params.get("room_run", false) and GameState.room_run != null:
		_room_session = preload("res://src/screens/room_node_session.gd").new(GameState.room_run)
	var saved: Dictionary = params.get("_saved_screen", {})
	_refresh_count = maxi(0, int(saved.get("refresh_count", 0)))
	_offers = [] if _room_session != null else (saved.offers if saved.has("offers") else _roll_offers())
	var legacy_layout := not saved.is_empty() and int(saved.get("layout_version", 1)) < LAYOUT_VERSION
	for i in _offers.size():
		if not _offers[i].has("display_slot"): _offers[i]["display_slot"] = i
		if _offers[i].kind == "relic":
			_offers[i].price = Relics.price(_offers[i].relic)
			if legacy_layout: _offers[i].display_slot = int(_offers[i].display_slot) + 2
		elif _offers[i].kind != "buy_char":
			_offers[i].display_slot = SERVICE_SLOT + {"remove": 0, "copy": 1, "heal": 2}[_offers[i].kind]
	if _room_session != null:
		_offers = _room_session.run.shop_offers.duplicate(true)
		_refresh_count = int(_room_session.run.contents[_room_session.run.current_room].get("shop_refreshes", 0))
		_assign_room_slots()
	Achievements.register_offers(_offers)
	_showcase = preload("res://src/ui/object_stage/object_stage_view.gd").new()
	_showcase.mode = "shop"
	root.add_child(_showcase)
	_hud = preload("res://src/ui/object_stage/object_hud.gd").new()
	_hud.heading = "市集 · 字肆"
	_hud.instruction = "柜上择字，印台整备。"
	_hud.action_text = "购入"
	_hud.secondary_text = "离开"
	_hud.on_action = _purchase_selected
	_hud.on_secondary = _leave
	_hud.on_deck = _open_deck


	root.add_child(_hud)
	JourneyStyle.currency(_hud.status_label)
	JourneyStyle.currency(_hud.detail_title)
	var target := preload("res://src/ui/object_stage/shop_action_target.gd").new()
	target.name = "StockRefreshTarget"
	target.model = _showcase.stage.shop_actions.refresh
	target.pressed.connect(_refresh_stock)
	root.add_child(target)
	_hud.tertiary_button = target
	_showcase.layout_changed.connect(_layout_offers)
	_hud.action_button.item_rect_changed.connect(_layout_price_labels.call_deferred)
	_refresh()
	if _room_session!=null and _room_session.run.phase=="shop_choose": _resume_room_choice.call_deferred()



func _roll_offers() -> Array:
	var out := _roll_chars()
	out.append({"kind": "remove", "character": null, "price": GameState.rng.randi_range(16, 20)})
	out.append({"kind": "copy", "character": null, "price": GameState.rng.randi_range(18, 22)})
	out.append({"kind": "heal", "character": null, "price": GameState.rng.randi_range(10, 14)})
	out.append_array(_roll_relic())
	return out


## 随机上架至多三件未拥有的遗物；只能购买当前货架，按稀有度定价。
func _roll_relic() -> Array:
	var out: Array = []
	var ids := RelicRewardFlow.roll(3, RelicRewardFlow.side_rng("shop"))
	for i in ids.size():
		out.append({"kind": "relic", "character": null, "relic": ids[i], "price": Relics.price(ids[i]), "display_slot": RELIC_SLOT + i})
	return out


func _roll_chars() -> Array:
	var out: Array = []
	var pool: Array = []
	for c in Database.characters.values():
		if not c.is_pollution and not c.pending_design and not c.tags.has("enemy") and not c.tags.has("彩蛋") and not c.tags.has("event") and c.rarity <= 2:
			pool.append(c)
	var rng := GameState.rng
	var picked: Array = []
	var guard := 0
	while picked.size() < Expedition.SHOP_CARD_COUNT and guard < 200:
		guard += 1
		var c: CharacterData = pool[rng.randi_range(0, pool.size() - 1)]
		if picked.any(func(x): return x.id == c.id):
			continue
		picked.append(c)
		out.append({"kind": "buy_char", "character": c, "price": rng.randi_range(12, 15)})
	return out


func refresh_cost() -> int:
	return Expedition.SHOP_REFRESH_COST * (_refresh_count + 1)


## 每次成功刷新后涨价 5 铜钱；每家商店单独计数，随货架保存。
func _refresh_stock() -> void:
	if _busy or not _pending_kind.is_empty() or _has_shop_dialog(): return
	if _room_session != null:
		_room_shop_result(_room_session.apply({"type":"shop_refresh"}))
		return
	if not GameState.spend_gold(refresh_cost()): return
	_refresh_count += 1
	var chars := _roll_chars()
	for i in chars.size(): chars[i]["display_slot"] = i
	_offers = chars + _offers.filter(func(o): return o.kind != "buy_char" and o.kind != "relic") + _roll_relic()
	Achievements.register_offers(_offers)
	_selected = 0
	_refresh()
	SaveManager.request_save()


func _refresh() -> void:
	_showcase.stage.clear_objects()
	for card in _cards:
		card.get_parent().remove_child(card)
		card.queue_free()
	_cards.clear()
	_update_action_keys()
	for i in _offers.size():
		var item: Dictionary = _offers[i]
		var ch: CharacterData = item.character
		var glyph: String = ch.glyph if ch != null else (Relics.name_of(item.relic).left(1) if item.kind == "relic" else {"remove": "删", "copy": "拓", "heal": "息"}[item.kind])
		if item.kind == "relic": _showcase.stage.add_relic(item.relic, int(item.display_slot) - RELIC_SLOT, int(item.price))
		else: _showcase.stage.add_object(glyph, int(item.display_slot), ch.rarity if ch != null else 0, ch == null)
		var card := GlyphOffer.new()
		card.character = ch
		card.caption = "%d钱" % item.price
		card.clicked.connect(_on_offer_clicked.bind(i))
		card.hovered.connect(_inspect.bind(i))
		content.add_child(card)
		JourneyStyle.currency(card._caption)
		if item.kind == "buy_char":
			# Price tags sit on the top edge, clear of the physical counter keys.
			var scale := JourneyStyle.touch_scale(self)
			card._caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
			card._caption.offset_top = -4 * scale
			card._caption.offset_bottom = 20 * scale
		elif item.kind == "relic":
			var tier: int = Relics.TIER[item.relic]
			card._caption.text = "%s\n%d钱 · %s" % [Relics.name_of(item.relic), item.price, {1: "常见", 2: "少见", 3: "稀有"}[tier]]
		_cards.append(card)
	_selected = clampi(_selected, 0, maxi(0, _offers.size() - 1))
	_layout_offers.call_deferred()
	_inspect(_selected)


func _update_action_keys() -> void:
	_hud.status_label.text = "铜钱 %d" % GameState.gold
	if _hud.tertiary_button != null:
		_hud.tertiary_button.set_offer("换货", refresh_cost(), not _busy and _pending_kind.is_empty() and GameState.gold >= refresh_cost())
		_hud.tertiary_button.tooltip_text = "花 %d 铜钱更换字和遗物，下次再加 5 铜钱；已购买服务不补回，未购买服务保留。" % refresh_cost()


func _layout_offers() -> void:
	var action_rect: Rect2 = _showcase.action_rect("refresh")
	_hud.tertiary_button.position = action_rect.position
	_hud.tertiary_button.size = action_rect.size
	var rects: Array[Rect2] = []
	var glyph_indices: Array[int] = []
	for i in _cards.size():
		var rect: Rect2 = _showcase.relic_rect(i) if _offers[i].kind == "relic" else _showcase.object_rect(i, _offers[i].kind != "buy_char")
		rects.append(rect)
		if _offers[i].kind == "buy_char": glyph_indices.append(i)
	# Perspective skews the model corners; divide neighboring card targets at
	# their midpoints so one card never steals another card's edge clicks.
	var glyph_rects := rects.duplicate()
	var gap := JourneyStyle.touch_scale(self)
	for n in glyph_indices.size():
		var i: int = glyph_indices[n]
		var left := rects[i].position.x
		var right := rects[i].end.x
		if n > 0: left = maxf(left, (glyph_rects[i].get_center().x + glyph_rects[glyph_indices[n - 1]].get_center().x) * 0.5 + gap)
		if n + 1 < glyph_indices.size(): right = minf(right, (glyph_rects[i].get_center().x + glyph_rects[glyph_indices[n + 1]].get_center().x) * 0.5 - gap)
		rects[i] = Rect2(Vector2(left, rects[i].position.y), Vector2(right - left, rects[i].size.y))
	for i in _cards.size():
		var rect := rects[i]
		_cards[i].position = rect.position
		_cards[i].size = rect.size
		if _offers[i].kind == "relic":
			var scale := JourneyStyle.touch_scale(self)
			var label_width := maxf(rect.size.x, 94 * scale)
			_cards[i]._caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			_cards[i]._caption.position = Vector2((rect.size.x - label_width) * 0.5, rect.size.y - 48 * scale)
			_cards[i]._caption.size = Vector2(label_width, 44 * scale)


func _on_offer_clicked(index: int) -> void:
	if _busy or not _pending_kind.is_empty() or _has_shop_dialog(): return
	if _offers[index].kind == "relic": _open_relic_purchase(index)
	else: _inspect(index)

	_layout_price_labels.call_deferred()


func _layout_price_labels() -> void:
	if not is_inside_tree(): return
	var limit: float = _hud.action_button.global_position.y - 8
	for card in _cards:
		var caption: Label = card._caption
		if caption == null: continue
		# 价签留在柜台上，并避开底部购买按钮。
		var top := minf(6, limit - card.global_position.y - card.size.y - 36)
		caption.offset_top = top
		caption.offset_bottom = top + 36


func _inspect(index: int) -> void:
	if _busy or _offers.is_empty(): return
	_selected = index
	for i in _cards.size(): _cards[i].set_selected(i == index)
	_showcase.stage.select_object(index)
	var item: Dictionary = _offers[index]
	var ch: CharacterData = item.character
	var title: String
	var body: String
	if item.kind == "relic":
		title = "遗物「%s」" % Relics.name_of(item.relic)
		body = Relics.desc_of(item.relic)
	else:
		title = ch.glyph if ch != null else {"remove": "删字", "copy": "复制", "heal": "调息"}[item.kind]
		body = EffectGlossary.character_hint(ch) if ch != null else {"remove": "从字袋中永久移除一枚字。", "copy": "复制字袋中的一枚字。", "heal": "回复 %d 点气血。" % _heal_amount()}[item.kind]
	_hud.set_detail(title + "  ·  " + str(item.price) + " 铜钱", body)
	_hud.action_button.text = "铜钱不足" if GameState.gold < int(item.price) else "购入 · %d 铜钱" % item.price
	_hud.action_button.disabled = GameState.gold < int(item.price)


func _purchase_selected() -> void:
	if _busy or not _pending_kind.is_empty() or _has_shop_dialog() or _offers.is_empty() or GameState.gold < int(_offers[_selected].price): return
	var index := _selected
	if _offers[index].kind == "relic":
		_open_relic_purchase(index)
		return
	if Settings.reduced_motion or _offers[index].kind != "buy_char":
		_buy(index)
		return
	_busy = true
	_hud.action_button.disabled = true
	_hud.secondary_button.disabled = true
	_update_action_keys()
	_showcase.stage.take(index)
	create_tween().tween_interval(0.24).finished.connect(func():
		_busy = false
		_hud.secondary_button.disabled = false
		_buy(index))


func _heal_amount() -> int:
	return int(round(GameState.player_max_hp * 0.3))


func _buy(index: int) -> void:
	if _busy or not _pending_kind.is_empty() or _has_shop_dialog() or index < 0 or index >= _offers.size(): return
	if _room_session!=null:
		var actions: Array = _room_session.run.legal_actions().filter(func(action):return action.type=="shop_buy" and action.index==index)
		if not actions.is_empty(): _room_shop_result(_room_session.apply(actions[0]))
		return
	if _busy or index < 0 or index >= _offers.size(): return
	var offer: Dictionary = _offers[index]
	if offer.kind == "relic" and GameState.has_relic(offer.relic): return
	if offer.kind in ["remove", "copy"] and GameState.deck_size() == 0: return
	if not GameState.spend_gold(int(offer.price)):
		return
	match offer.kind:
		"buy_char":
			GameState.add_character(offer.character, 1)
			_finish_offer(index)
		"heal":
			GameState.heal(_heal_amount())
			_finish_offer(index)
		"relic":
			_busy = true
			_update_action_keys()
			RelicRewardFlow.grant(self, offer.relic, func(_id):
				_busy = false
				if is_inside_tree() and index < _offers.size():
					_finish_offer(index))
		"remove":
			_busy = true
			_pending_offer_index = index
			_pending_kind = "remove"
			_update_action_keys()
			_choose_char("选择要删除的字")
		"copy":
			_busy = true
			_pending_offer_index = index
			_pending_kind = "copy"
			_update_action_keys()
			_choose_char("选择要复制的字")


func _on_char_chosen(ch: CharacterData) -> void:
	if _pending_offer_index < 0 or _pending_offer_index >= _offers.size() or _pending_kind.is_empty(): return
	if _pending_kind == "remove":
		GameState.remove_character_id(ch.id)
	elif _pending_kind == "copy":
		GameState.add_character(ch, 1)
	var idx := _pending_offer_index
	_pending_kind = ""
	_pending_offer_index = -1
	_busy = false
	if idx >= 0 and idx < _offers.size():
		_finish_offer(idx)


func _finish_offer(index: int) -> void:
	Achievements.bought_offer(_offers[index])
	_offers.remove_at(index)
	_refresh()
	SaveManager.request_save()


func _choose_char(title: String) -> void:
	var counts := GameState.glyph_counts()
	var chars: Array = []
	for id in counts.keys():
		var cd: CharacterData = Database.get_character_by_glyph(id)
		if cd != null:
			chars.append(cd)
	var overlay := CollectionOverlay.new()
	overlay.setup({
		"title": title,
		"subtitle": "点击一枚字",
		"characters": chars,
		"counts": counts, "instances": GameState.deck,
		"pick_on_click": true,
		"close_text": "取消选择",
	})
	overlay.picked.connect(_on_char_chosen)
	overlay.closed.connect(_cancel_char_choice)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)


func _cancel_char_choice() -> void:
	if _pending_offer_index < 0 or _pending_kind.is_empty(): return
	GameState.add_gold(int(_offers[_pending_offer_index].price))
	_pending_offer_index = -1
	_pending_kind = ""
	_busy = false
	_refresh()


func _has_shop_dialog() -> bool:
	return is_instance_valid(_shop_overlay) and _shop_overlay.is_inside_tree()


func _show_shop_dialog(config: Dictionary, on_choose: Callable) -> void:
	var overlay := ChoiceOverlay.new()
	overlay.setup(config)
	_shop_overlay = overlay
	overlay.chose.connect(func(index: int):
		_shop_overlay = null
		on_choose.call(index))
	add_child(overlay)


func _open_relic_purchase(index: int) -> void:
	if _busy or not _pending_kind.is_empty() or _has_shop_dialog(): return
	if index < 0 or index >= _offers.size() or _offers[index].kind != "relic": return
	var offer: Dictionary = _offers[index]
	_inspect(index)
	if GameState.has_relic(offer.relic) or GameState.gold < int(offer.price): return
	_show_shop_dialog({"title": "购买「%s」？" % Relics.name_of(offer.relic), "relic_id": offer.relic, "body": Relics.desc_of(offer.relic) + "\n\n售价：%d 铜钱。" % offer.price, "options": [{"text": "取消"}, {"text": "确认购买 · %d 铜钱" % offer.price, "primary": true}], "dismissible": true}, func(choice: int):
		if choice != 1: return
		var current := _offers.find_custom(func(o): return o.kind == "relic" and o.relic == offer.relic)
		if current >= 0: _buy(current))


func _leave() -> void:
	if _busy or not _pending_kind.is_empty() or _has_shop_dialog(): return
	if _room_session!=null:
		var result: Dictionary = _room_session.apply({"type":"shop_leave"})
		if result.ok: goto("res://src/screens/room_map_screen.gd")
		return
	GameState.complete_current_node()
	goto("res://src/screens/map_screen.gd")


func _open_deck() -> void:
	if not _busy and not _has_shop_dialog(): CollectionOverlay.open_deck(self)


func save_checkpoint() -> Dictionary:
	if _busy or not _pending_kind.is_empty(): return {}
	var snapshot := super.save_checkpoint()
	snapshot.screen = {"offers": _offers, "refresh_count": _refresh_count, "layout_version": LAYOUT_VERSION}
	return snapshot


func _room_shop_result(result: Dictionary) -> void:
	if not result.ok:
		if _room_session.current() and _room_session.run.phase == "shop_choose": _room_session.apply({"type":"cancel_pick"})
		_busy = false
		_hud.secondary_button.disabled = false
		_refresh()
		return
	if result.has("relic"):
		_busy = true
		RelicRewardFlow.bind_owned(self,str(result.relic),func(_id):
			_room_session.run._save_if_enabled()
			_room_shop_result({"ok":true}))
		return
	if _room_session.run.phase=="shop_choose": _resume_room_choice(); return
	_busy = false
	_offers = _room_session.run.shop_offers.duplicate(true)
	_refresh_count = int(_room_session.run.contents[_room_session.run.current_room].get("shop_refreshes", 0))
	_assign_room_slots()
	_refresh()


func _resume_room_choice() -> void:
	_busy = true; _hud.action_button.disabled = true; _hud.secondary_button.disabled = true
	_hud.tertiary_button.disabled = true
	_room_session.pick(self,"选择要删去的字" if _room_session.run.pending_kind=="remove" else "选择要拓印的字",func(result):
		_hud.secondary_button.disabled = false
		_room_shop_result(result))


func _assign_room_slots() -> void:
	var card_slot := 0
	var relic_slot := RELIC_SLOT
	for offer in _offers:
		if offer.kind == "buy_char":
			if not offer.has("display_slot"): offer.display_slot = card_slot
			card_slot += 1
		elif offer.kind == "relic":
			if not offer.has("display_slot"): offer.display_slot = relic_slot
			relic_slot += 1
			offer.price = Relics.price(offer.relic)
		else:
			offer.display_slot = SERVICE_SLOT + {"remove": 0, "copy": 1, "heal": 2}[offer.kind]
	_room_session.run.shop_offers = _offers.duplicate(true)
