extends Control
## 词条显示、悬浮信号、嵌套阅读、点按固定与棋盘点击隔离。

var _checks := 0
var _failures := 0
var _capture := false

func _ready() -> void:
	_capture = OS.get_cmdline_user_args().has("--capture")
	get_tree().create_timer(40).timeout.connect(func():
		push_error("词条测试未完整执行")
		get_tree().quit(1))
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(label)

func _frames(count := 4) -> void:
	for i in count:
		await get_tree().process_frame

func _run() -> void:
	# Headless starts at 64×64; exercise a supported landscape viewport explicitly.
	get_window().size = Vector2i(1280, 720)
	await _frames()
	var all_valid := true
	for key in EffectGlossary.TERMS.values():
		all_valid = all_valid and not EffectGlossary.entry("term:" + str(key)).is_empty()
	for word in WordDescriptions.BRIEF_TEXT:
		all_valid = all_valid and Database.get_word_by_glyphs_string(word) != null
	_check(all_valid, "所有短词效和关键词指向存在的词条")
	_check(EffectGlossary.entry("https://example.com").is_empty() and EffectGlossary.entry("term:missing").is_empty(), "未知词条或外部地址不执行任何动作")
	var formatted := EffectGlossary.format_text("临时格挡6；非攻击伤害3；【防御】；【热】；[b]原样[/b]", 24)
	_check("url=term:block" in formatted and "url=term:non_attack" in formatted and "url=word:防御" in formatted and not "url=word:热" in formatted, "关键词按最长匹配，词语与单字字形正确区分")
	_check("[lb]b]原样[lb]/b]" in formatted and "[font_size=24]6" in formatted, "普通文本安全转义，数字强调保留")
	_check(not "url=term:counter" in EffectGlossary.format_text("获得反击。", 0, "term:counter"), "当前词条不生成指向自身的规则链接")
	var screen = load("res://src/screens/battle_screen.gd").new()
	GameState.start_new_run("v03")
	screen.setup({"seed": 7})
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _frames()
	var b: BattleState = screen.battle
	var word := Database.get_word_by_glyphs_string("防反")
	var full := word.describe()
	_check(EffectGlossary.brief(word).length() <= full.length() and "反击" in full, "防反主文简化，完整说明仍保留详细结算时机")
	var before := [b.rng.state, CharInstance._next_uid, b.player.energy, b.player.heat, GameState.gold, b.board.cells.duplicate()]
	var label := EffectText.new()
	label.position = Vector2(40, 50)
	label.size = Vector2(280, 80)
	label.add_theme_font_size_override("normal_font_size", 24)
	label.set_effect_text("反击")
	add_child(label)
	await _frames()
	label.meta_hover_started.emit("term:counter")
	await _frames()
	_check(label._cards.size() == 1 and label._cards[0].get_meta("entry") == "term:counter", "悬浮关键词打开规则浮层")
	if label._cards.is_empty():
		# 出错后仍完成后续断言，最终以非零退出。
		label._on_link_entered("term:counter", 0)
		await _frames()
	var card := label._cards[0]
	_check(Rect2(Vector2.ZERO, get_viewport_rect().size).encloses(card.get_global_rect()), "浮层完整限制在视口内")
	var card_body: RichTextLabel = card.get_child(0).get_child(1).get_child(0)
	_check(card_body.get_theme_color("default_color") == Palette.INK, "独立浮层继承当前主题的可读文字颜色")
	_check(card_body.get_parsed_text() == EffectGlossary.entry("term:counter").text and "url=term:block" in card_body.text, "规则浮层含完整定义与可继续查看的关联词条")
	label._on_link_exited("term:counter", 0)
	label._update_help(0.4, card.get_global_rect().get_center())
	_check(not label._cards.is_empty(), "从关键词移入浮层后保持可阅读")
	# 后续模拟子词条信号；无头环境没有系统鼠标，暂停自动的光标离开计时。
	label.set_process(false)
	card_body.meta_hover_started.emit("term:block")
	await _frames()
	_check(label._cards.size() == 2 and label._cards[1].get_meta("entry") == "term:block", "浮层内关联关键词可以继续展开")
	card_body.meta_hover_ended.emit("term:block")
	label.close_help()
	label.meta_clicked.emit("term:counter")
	await _frames()
	label._hovered.clear()
	label._process(0.4)
	_check(label._pinned and label._cards.size() == 1, "点按关键词固定浮层，移开不关闭")
	var escape_event := InputEventAction.new()
	escape_event.action = "cancel_selection"
	escape_event.pressed = true
	label._input(escape_event)
	_check(label._cards.is_empty(), "Esc关闭规则浮层")
	var detailed_word := Database.get_word_by_glyphs_string("反复")
	label.set_effect_text(EffectGlossary.brief(detailed_word), 0, detailed_word)
	_check("完整词效" in label.get_parsed_text() and "url=word:反复" in label.text, "精简说明保留完整词效入口")
	label.meta_clicked.emit("word:反复")
	await _frames()
	card = label._cards[0]
	card_body = card.get_child(0).get_child(1).get_child(0)
	_check(card_body.get_parsed_text() == detailed_word.describe(), "完整词效浮层与规范原文一致")
	# 把浮层放到真实字盘上，覆盖一个能被点击的格子。
	screen._board_view.clear_selection()
	var cell_point: Vector2 = screen._board_view.tiles[0].get_global_rect().get_center()
	card.position = cell_point - Vector2(30, 30)
	var click := InputEventMouseButton.new()
	click.position = cell_point
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	screen._board_view._input(click)
	_check(screen._board_view.path.is_empty() and EffectText.blocks_pointer(get_viewport(), cell_point), "浮层上的鼠标点击不会穿透选中字块")
	var touch := InputEventScreenTouch.new()
	touch.position = cell_point
	touch.pressed = true
	screen._board_view._input(touch)
	_check(screen._board_view.path.is_empty(), "浮层上的触屏点按不会穿透选中字块")
	var outside := InputEventMouseButton.new()
	outside.button_index = MOUSE_BUTTON_LEFT
	outside.pressed = true
	# Help cards have a 12px viewport inset. The lower right corner can be
	# covered after deliberately moving a wide card onto the illustrated board.
	outside.position = Vector2(5, 5)
	label._input(outside)
	_check(label._cards.is_empty() and not EffectText.blocks_pointer(get_viewport(), cell_point), "点击外部关闭浮层并恢复棋盘点击")
	label.meta_clicked.emit("term:counter")
	await _frames()
	label.set_effect_text("新的选择")
	_check(label._cards.is_empty(), "切换预览文本关闭旧词条")
	label.meta_clicked.emit("term:counter")
	await _frames()
	label.hide()
	label._process(0.1)
	_check(label._cards.is_empty(), "隐藏来源控件关闭其浮层")
	label.queue_free()
	var after := [b.rng.state, CharInstance._next_uid, b.player.energy, b.player.heat, GameState.gold, b.board.cells.duplicate()]
	_check(before == after, "查看所有词条不改变随机数、实体身份、盘面或资源")
	# 战斗预览保留实时来源与额外触发提示。
	b.last_played_glyphs.assign(["防", "御"])
	var again := CharInstance.new(Database.get_character_by_glyph("再"))
	screen._bubble.set_text("再", EffectPreview.solo_text(again, b))
	_check("上一手【防御】" in screen._bubble.body.get_parsed_text() and "末字【御】" in screen._bubble.body.get_parsed_text(), "再的动态来源不会因精简丢失")
	b.enable_ability("force_once", 2)
	var attack := Database.get_word_by_glyphs_string("击破")
	_check("首个伤害段额外+2" in EffectPreview.word_text(attack, b, [], {}, true), "短说明仍显示本次攻击的临时强化")
	screen._bubble.set_text("防反", EffectPreview.word_text(word, b, [], {}, true), SpeechBubble.State.PREVIEW, word)
	screen._bubble.body.meta_clicked.emit("term:counter")
	await _frames()
	_check(screen._bubble.body._cards.size() == 1, "战斗词效区接入同一词条浮层")
	if _capture:
		RenderingServer.force_draw(false)
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("huoziluandou-wiki-battle.png"))
		get_window().size = Vector2i(844, 390)
		await _frames(8)
		screen._layout()
		screen._bubble.body.meta_clicked.emit("term:double_passive")
		await _frames()
		var phone_card: PanelContainer = screen._bubble.body._cards[0]
		var phone_scale := get_viewport().get_screen_transform().get_scale().y
		_check(Rect2(Vector2.ZERO, get_viewport_rect().size).encloses(phone_card.get_global_rect()), "844×390小屏浮层完整限制在视口内")
		var phone_body: RichTextLabel = phone_card.get_child(0).get_child(1).get_child(0)
		_check(phone_body.get_theme_font_size("normal_font_size") * phone_scale >= 17, "小屏词条字号保持至少17屏幕像素")
		RenderingServer.force_draw(false)
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("huoziluandou-wiki-phone.png"))
	screen._bubble.body.close_help()
	var collection := CollectionOverlay.new()
	collection.setup({"words": [word, Database.get_word_by_glyphs_string("精炼")]})
	add_child(collection)
	collection._show_tab("words")
	await _frames()
	var collection_body: EffectText = collection._word_grid.get_child(0).get_child(0).get_child(2)
	_check("url=term:block" in collection_body.text and "url=term:counter" in collection_body.text, "词语图鉴也使用精简文本与词条链接")
	# 词页与实体字页一样要能拖动滚动：卡面不得拦截鼠标/触摸
	var word_card: Control = collection._word_grid.get_child(0)
	var blocking: Array = [word_card, collection_body].filter(func(n): return n.mouse_filter == Control.MOUSE_FILTER_STOP)
	_check(blocking.is_empty(), "词页卡片不拦截滚动事件")
	_check(collection._scroll.visible and collection._word_grid.get_child_count() == 2, "词页内容都在同一个可滚动容器里")
	collection_body.meta_clicked.emit("term:counter")
	await _frames()
	collection._show_tab("chars")
	await _frames()
	_check(collection_body._cards.is_empty(), "图鉴切换页签不会遗留词条浮层")
	collection.queue_free()
	# 污染只常驻短词条；详细规则来自当前配置，点击后使用统一浮层。
	for pid in Database.pollutions:
		var pd: PollutionData = Database.get_pollution(pid)
		var meta := "pollution:" + str(pid)
		var entry := EffectGlossary.entry(meta)
		_check(entry.text == pd.description, "污染词条读取当前配置：" + str(pid))
		_check(EffectGlossary.format_text(pd.name + "污染").contains("url=" + meta), "污染名可点击：" + str(pid))
		_check(not EffectGlossary.format_text(pd.name + "污染", 0, meta).contains("url=" + meta), "污染浮层不链接自身：" + str(pid))
	var polluted := CharInstance.new(Database.get_character_by_glyph("连"))
	polluted.pollutions.append("replicate")
	b.board.set_cell(0, 0, polluted)
	screen._inspect_tile(Vector2i.ZERO)
	var frame: EffectText = screen._bubble.frame_details
	_check(frame.visible and frame.text.contains("url=pollution:replicate") and not frame.get_parsed_text().contains("每回合复制"), "点击污染字只显示短链接，不常驻长规则")
	frame.meta_clicked.emit("pollution:replicate")
	await _frames()
	_check(frame._pinned and frame._cards.size() == 1, "点击污染链接打开并固定浮层")
	var pollution_body: RichTextLabel = frame._cards[0].get_child(0).get_child(1).get_child(0)
	_check(pollution_body.get_parsed_text() == Database.get_pollution("replicate").description, "蔓生完整复制规则仍可查看")
	frame.close_help()
	screen._bubble.set_context(screen._selection_context([Vector2i.ZERO]))
	_check(not screen._bubble._context.visible and not screen._bubble._context_rule.visible and frame.text.contains("url=pollution:replicate"), "移除目标和污染摘要行及分隔线，字块污染词条仍可查看")
	# Excel 已改数值也保持短说明；每个数字绑定自己的参数，避免相同默认数字串位。
	var resource_values := BattleBalance.values.duplicate(true)
	BattleBalance.values["words/extra_fangfan/e/0/amount"] = 19
	BattleBalance.values["words/extra_fangfan/e/1/amount"] = 7
	var tuned := BattleBalance.apply_resource(load("res://resources/words/extra_fangfan.tres")) as WordData
	BattleBalance.values = resource_values
	_check(tuned.has_meta("balance_changed") and tuned.describe().contains("当前配置"), "真实配置覆盖保留完整描述供词条查看")
	_check(EffectGlossary.brief(tuned) == "获得19临时格挡、7层反击。", "Excel调过的多效果词保留短说明和各自当前数值")
	var tuned_text := EffectText.new()
	add_child(tuned_text)
	tuned_text.set_effect_text(EffectGlossary.brief(tuned), 0, tuned)
	_check(tuned_text.text.contains("url=word:防反") and not tuned_text.get_parsed_text().contains("当前配置"), "调参后的短说明仍提供完整词效链接，不展开配置清单")
	tuned_text.queue_free()
	for glyphs in WordDescriptions.BRIEF_TEXT:
		var changed := Database.get_word_by_glyphs_string(glyphs).duplicate(true) as WordData
		changed.set_meta("balance_changed", true)
		changed.effect_summary = "不应回退的完整描述"
		_check(not EffectGlossary.brief(changed).contains("不应回退"), "调参不丢短说明：" + glyphs)
	var saved_values := BattleBalance.values.duplicate(true)
	BattleBalance.values["core/buy_cost"] = 9
	BattleBalance.values["core/deploy_choices"] = 6
	BattleBalance.values["core/buyback_layer"] = 4
	var deploy_brief := EffectGlossary.brief(Database.get_word_by_glyphs_string("投放"))
	_check(deploy_brief.contains("支付9铜钱") and deploy_brief.contains("袋顶6字") and deploy_brief.contains("选1字") and deploy_brief.contains("额外使用+4"), "费用、候选数和复制层单独绑定，选一枚不被误改")
	BattleBalance.values["core/vulnerable_mult"] = 2.25
	var vulnerability := Database.get_status("vulnerable")
	var saved_decay := vulnerability.decay_per_turn
	vulnerability.decay_per_turn = 2
	var vulnerable_help: String = EffectGlossary.entry("term:vulnerable").text
	_check(vulnerable_help.contains("2.25") and vulnerable_help.contains("每回合开始减少2层") and vulnerable_help.contains("敌我双方"), "易伤浮层显示当前倍率和敌我双方减层规则")
	b.player.statuses["vulnerable"] = 5
	b.enemies[0].statuses["vulnerable"] = 5
	var player_debuff: Dictionary = StatusDisplay.collect(b.player, b).filter(func(item): return item.id == "vulnerable")[0]
	var enemy_debuff: Dictionary = StatusDisplay.collect(b.enemies[0], b).filter(func(item): return item.id == "vulnerable")[0]
	_check(player_debuff.description.contains("2.25") and player_debuff.description.contains("衰减 2 层"), "玩家状态浮层显示当前倍率和减层")
	_check(enemy_debuff.description.contains("2.25") and enemy_debuff.description.contains("衰减 2 层"), "敌方状态浮层显示当前倍率与减层")
	b.begin_player_turn(false, false)
	_check(b.player.status_stacks("vulnerable") == 3 and b.enemies[0].status_stacks("vulnerable") == 3, "易伤说明与实际敌我双方减层一致")
	vulnerability.decay_per_turn = 0
	vulnerable_help = EffectGlossary.entry("term:vulnerable").text
	_check(vulnerable_help.contains("敌我双方不按回合减层") and not vulnerable_help.contains("减少0层"), "衰减设0时明确不衰减")
	vulnerability.decay_per_turn = saved_decay
	BattleBalance.values = saved_values
	screen.queue_free()
	await _frames()
	_check(get_tree().get_nodes_in_group("effect_help_open").is_empty(), "离开界面释放所有词条浮层")
	_check(_checks >= 28, "词条测试完整执行")
	print("[effect_help_test] PASS=%d FAIL=%d" % [_checks - _failures, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
