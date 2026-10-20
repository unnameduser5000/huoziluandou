extends Control
## 核对真实词库、状态和字框的词条入口；查看说明不能改变战斗状态。
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames() -> void:
	for i in 4: await get_tree().process_frame

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	var links := RegEx.new()
	links.compile("\\[url=([^\\]]+)\\]")
	for word in Database.words.values():
		var brief := EffectGlossary.brief(word)
		var text := EffectGlossary.format_text(brief + "\n" + word.describe())
		var valid: bool = not brief.is_empty() and not word.describe().is_empty()
		for found in links.search_all(text): valid = valid and not EffectGlossary.entry(found.get_string(1)).is_empty()
		check(valid, "字词说明非空，所有链接均可查阅：" + word.word)
	for id in Database.statuses:
		var status: StatusData = Database.get_status(id)
		check(not EffectGlossary.entry("status:" + str(id)).is_empty(), "状态有独立定义：" + str(id))
		check(EffectGlossary.format_text(status.name + "状态").contains("url=status:" + str(id)), "状态名可展开：" + str(id))
	for id in Database.pollutions:
		var pollution: PollutionData = Database.get_pollution(id)
		check(EffectGlossary.entry("pollution:" + str(id)).text == pollution.description, "污染作为字块负面状态接入词条：" + str(id))

	GameState.start_new_run("v03")
	var encounter := MapNodeData.new()
	encounter.enemies.append(Database.get_enemy("proof_boss"))
	var screen = load("res://src/screens/battle_screen.gd").new()
	screen.setup({"node": encounter, "seed": 7})
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames()
	var b: BattleState = screen.battle
	# 每种实际登记的能力必须有名称与详情，内部辅助参数不另占图标。
	for id in StatusDisplay.ABILITY_NAMES:
		if id in StatusDisplay.ABILITY_PARAMETERS: continue
		b.abilities.clear()
		b.enable_ability(id, 2)
		var entries := StatusDisplay.collect(b.player, b)
		var expected := "heart_layers" if id == "heart_power" else "ability:" + str(id)
		var matches := entries.filter(func(item): return item.id == expected)
		check(matches.size() == 1 and matches[0].name != "其他能力" and not matches[0].description.contains("持续能力已生效"), "已登记Buff有实际说明：" + str(id))
	b.abilities.clear()
	var tile := CharInstance.new(Database.get_character_by_glyph("连"))
	tile.owner = CharInstance.Owner.ENEMY
	tile.gilded = true
	tile.refined = true
	tile.pinned = true
	tile.pinned_exhausted = true
	tile.temporary_uses = 3
	tile.pollutions.append("replicate")
	tile.statuses = {"replicate_count": 2, "replicate_delay": 3, "inject_cap": 7}
	b.board.set_cell(0, 0, tile)
	var e: Combatant = b.enemies[0]
	var d := EnemyMechanics.data(e)
	d.targets = [tile]
	d.origins = [Vector2i.ZERO]
	d.used = {}
	screen._refresh_all()
	var before := [b.rng.state, CharInstance._next_uid, b.player.energy, b.player.heat, GameState.gold, tile.gilded, tile.pollutions.duplicate()]
	screen._inspect_tile(Vector2i.ZERO)
	var label: EffectText = screen._bubble.frame_details
	check(label.get_parsed_text().length() < 120 and not label.get_parsed_text().contains("每回合复制"), "多个字框只展示短标签，不展开规则墙")
	check(label.text.contains("url=term:gilded") and label.text.contains("url=term:refined") and label.text.contains("url=tile:pinned") and label.text.contains("url=tile:layers"), "镀金、精炼、固定和叠层都有词条入口")
	var marker_links: Array = label._local_entries.keys().filter(func(meta): return str(meta).begins_with("tile:mark:"))
	check(marker_links.size() == 1 and label.get_parsed_text().contains("红签"), "怪物红框与选中框区分，并绑定实际来源")
	label.meta_hover_started.emit(marker_links[0])
	await frames()
	check(not label._pinned and label._cards.size() == 1, "字框词条支持悬浮展开")
	label.close_help()
	for meta in ["term:gilded", "term:refined", "tile:pinned", "tile:layers", "pollution:replicate"] + marker_links:
		label.meta_clicked.emit(meta)
		await frames()
		check(label._pinned and label._cards.size() == 1, "字框可点击固定说明：" + str(meta))
		if meta == "pollution:replicate":
			var body: RichTextLabel = label._cards[0].get_child(0).get_child(1).get_child(0)
			check(body.get_parsed_text().contains("等待3回合") and body.get_parsed_text().contains("复制2字") and body.get_parsed_text().contains("最多7枚"), "蔓生浮层按当前字的制造来源显示参数")
		label.close_help()
	if OS.get_cmdline_user_args().has("--capture"):
		label.meta_clicked.emit(marker_links[0])
		await frames()
		RenderingServer.force_draw(false)
		get_viewport().get_texture().get_image().save_png("/private/tmp/battle-description-audit.png")
		label.close_help()
	var after := [b.rng.state, CharInstance._next_uid, b.player.energy, b.player.heat, GameState.gold, tile.gilded, tile.pollutions.duplicate()]
	check(before == after, "查看字框不改随机数、实体、污染或资源")
	# 空格上的敌方爆破/封印框也必须能读到，而不是因格内无字而隐藏。
	d.targets = []
	d.cells = [Vector2i.ONE]
	b.board.clear_xy(Vector2i.ONE)
	screen._inspect_tile(Vector2i.ONE)
	check(label.visible and label.text.contains("url=tile:mark:"), "空格上的怪物目标框也能点击解释")
	d.cells = []
	screen._inspect_tile(Vector2i.ONE)
	check(not label.visible, "普通空格不会显示无关字框")
	# 状态详情与牌堆字卡复用词条渲染，不再只输出普通文本。
	screen._show_hud_details("状态详情", "力量、再生、蔓生污染、镀金", true)
	await frames()
	var overlay: ChoiceOverlay
	for child in screen.get_children():
		if child is ChoiceOverlay: overlay = child
	var details := overlay.find_child("EffectDetails", true, false) as EffectText
	check(details != null and details.text.contains("url=term:strength") and details.text.contains("url=pollution:replicate"), "Buff点击详情也支持继续悬浮词条")
	overlay._on_choose(0)
	await frames()
	check(screen._modal_count == 0, "关闭详情恢复字盘输入")
	var cd := Database.get_character_by_glyph("连").duplicate() as CharacterData
	cd.description += "\n蔓生污染 · 镀金"
	var card := CharCard.new()
	card.setup(cd, true)
	add_child(card)
	await frames()
	check(card._desc.text.contains("url=pollution:replicate") and card._desc.text.contains("url=term:gilded"), "牌堆字卡的污染和强化同样可查阅")
	var saved_values := BattleBalance.values.duplicate(true)
	BattleBalance.values["core/gild_gold"] = 4
	BattleBalance.values["core/strength_per_stack"] = 3
	BattleBalance.values["core/regen_per_stack"] = 2
	BattleBalance.values["core/corrosion_per_stack"] = 5
	BattleBalance.values["core/burn_heat_mult"] = 3
	BattleBalance.values["core/double_attack_mult"] = 3
	check(EffectGlossary.entry("term:gilded").text.contains("4铜钱") and EffectGlossary.entry("term:gilded").text.contains("临时复制不继承"), "镀金更新数值时保留实体和继承规则")
	check(EffectGlossary.entry("term:strength").text.contains("+3") and EffectGlossary.entry("term:regen").text.contains("×2") and EffectGlossary.entry("term:corrosion").text.contains("×5"), "力量、再生和心蚀词条同步当前倍率")
	check(EffectGlossary.entry("term:burn").text.contains("×3") and EffectGlossary.entry("term:double_attack").text.contains("×3"), "灼烧倍率与超强倍率都从配置读取")
	var strength := Database.get_status("strength")
	var old_decay := strength.decay_per_turn
	strength.decay_per_turn = 2
	b.player.statuses["strength"] = 2
	var strength_entries := StatusDisplay.collect(b.player, b).filter(func(item): return item.id == "strength")
	check(not strength_entries[0].description.contains("衰减"), "不参与玩家减层流程的状态不会声称每回合衰减")
	strength.decay_per_turn = old_decay
	var entity: CharInstance = GameState.deck[0]
	var messages := EffectHandlersActions._gild_glyph(b, {"target": {"gild_uid": entity.uid}}, null)
	check(entity.gilded and str(messages).contains("+4铜钱"), "镀金实际可用，结算提示与配置相符")
	BattleBalance.values = saved_values
	card.queue_free()
	screen.queue_free()
	await frames()
	check(get_tree().get_nodes_in_group("effect_help_open").is_empty(), "离开战斗释放字框说明")
	print("[battle_description_audit_test] WORDS=%d STATUSES=%d POLLUTIONS=%d PASS=%d FAIL=%d" % [Database.words.size(), Database.statuses.size(), Database.pollutions.size(), checks - failures, failures])
	get_tree().quit(1 if failures else 0)
