extends ScreenBase
signal presentation_step_finished
## 简洁活字 HUD + 独立表现队列。规则同步结算，动效逐次播放真实结果。
var battle: BattleState
var node: MapNodeData
var _board_view: BoardView
var _enemy_row: VBoxContainer
var _enemy_widgets: Array[EnemyView] = []
var _player_hp: StatBar
var _player_hp_caption: Label
var _player_hp_value: Label
var _hp_icon: BattleSymbol
var _menu_btn: Button
var _player_status: StatusStrip
var _player_defense: DefenseDisplay
var _gold_strip: ResourceStrip
var _pile_label: ResourceStrip
var _turn_label: Label
var _bubble: SpeechBubble
var _confirm_btn: Button
var _clear_btn: Button
var _end_btn: Button
var _log_box: VBoxContainer
var _log_scroll: ScrollContainer
var _log_lines: Array[String] = []
var _log_text: Label
var _log_dirty := false
var _log_refresh_queued := false
var _log_overlay: Control
var _topbar: Control
var _player_panel: Control
var _preview_panel: Control
var _enemy_panel: ScrollContainer
var _enemy_paper: ArtPaper
var _footer: Control
var _hint: Label
var _selection_actions: HBoxContainer
var _effects: BattleEffects
var _audio: BattleAudio
var _target_kind := -1
var _target_title := ""
var _target_effect := ""
var _last_selection: Array = []
var _placement_mode := ""
var _placement_uid := -1
var _placement_places: Array = []
var _target_index := 0
var _pending_path: Array = []
var _row_choice: Dictionary = {} # 单次出词的显式选行，发动或取消后作废。
var _ready_action: Dictionary = {}   ## 待发动：已选好路径+目标，点「发动」才执行
var _recast_three_active := false    ## 再铸/重连共用三字选择
var _recast_three_cells: Array = []
var _three_tiles_word := ""
var _collect_own_active := false     ## 收心：正在选盘面牌回袋
var _collect_own_cells: Array = []
var _collect_junk := false
var _word_transfer_target: Dictionary = {}
var _compound_picker_active := false ## 复合：正在选保留的临时字
var _solo_release_picker_active := false ## 放：正在选择是否消耗储能
var _solo_bag_picker_active := false ## 精/购：按原实体选择字袋字。
var _solo_throw_active := false
var _solo_throw_from := Vector2i(-1, -1)
var _solo_throw_uid: int = -1
var _manual_draw_picks: Array = []   ## 精心：已选的定向字
var _manual_draw_active := false
var _current_word: WordData
var _transform_uid := -1
var _fuse_stage := 0
var _fuse_first := Vector2i(-1, -1)
var _pair_mode := "fuse"
var _pending_place_uid := -1
var _merge_active := false
var _merge_bag_uid := -1
var _merge_discard_uid := -1
var _merge_cell1 := Vector2i(-1, -1)
var _finished := false
var _busy := false
var _collecting := false
var _active_fx_profile: Dictionary = {}
var _modal_count := 0
var _compact := false
var _events: Array[Dictionary] = []
var _pending_enemy_action: Dictionary = {}
var _enemy_attack_context: Dictionary = {}
var _feedback_watches: Array = []
var _confirm_motion: Tween
var _confirm_ink: ShaderMaterial
var _step_timer: Timer
var _exiting := false
var _room_run := false
var _expedition := false   ## 墨途远征的遭遇：战后回远征地图，不走奖励页
var _first_run_tutorial := false
var _tutorial_step := 0
var _entrance: BattleEntrance


func has_run_inventory() -> bool:
	return false


func save_checkpoint() -> Dictionary:
	# Multi-stage interactions own temporary model changes; keep the last completed
	# action until the entire picker/placement/animation has resolved.
	if battle == null or _busy or _finished or battle.is_over() or _modal_count > 0: return {}
	if _board_view == null or _board_view.pick_mode != "" or not _ready_action.is_empty() or not _pending_path.is_empty(): return {}
	if _recast_three_active or _collect_own_active or _compound_picker_active or _solo_release_picker_active or _solo_bag_picker_active or _solo_throw_active or _manual_draw_active or _merge_active: return {}
	if battle.pending_place != null or not battle.pending_reveal.is_empty() or battle.manual_draw_pending > 0 or battle.end_turn_requested or battle.blackout_requested: return {}
	var snapshot := super.save_checkpoint()
	snapshot.params["node"] = node
	snapshot.screen = {"battle": battle, "first_run_tutorial": _first_run_tutorial, "tutorial_step": _tutorial_step}
	if battle.achievement != null: snapshot.screen["achievement_battle"] = battle.achievement.export_snapshot()
	return snapshot


func build(root: Control) -> void:
	_step_timer = Timer.new()
	_step_timer.one_shot = true
	_step_timer.timeout.connect(func(): presentation_step_finished.emit())
	add_child(_step_timer)
	node = params.get("node", null)
	if node == null:
		var act := Database.get_act(GameState.act_index)
		if act != null and GameState.node_index - 1 < act.nodes.size():
			node = act.nodes[GameState.node_index - 1]
	if node == null:
		node = MapNodeData.new()
	_room_run = params.get("room_run", false) and GameState.room_run != null
	_expedition = params.get("expedition", false) and GameState.expedition != null
	var saved: Dictionary = params.get("_saved_screen", {})
	_first_run_tutorial = bool(saved.get("first_run_tutorial", GameState.first_run_tutorial or params.get("first_run_tutorial", false)))
	_tutorial_step = clampi(int(saved.get("tutorial_step", 0)), 0, 1)
	if saved.get("battle") is BattleState:
		battle = saved.battle
		if saved.has("achievement_battle") and Achievements.eligible():
			battle.achievement = preload("res://src/core/achievement_battle.gd").new(Achievements, battle, str(saved.achievement_battle.key))
			battle.achievement.restore_snapshot(saved.achievement_battle)
	else:
		battle = BattleState.new(Database.rules)
		var enemy_datas: Array = node.select_enemies(int(params.get("seed", GameState.battle_sequence * 997 + GameState.node_index)))
		if enemy_datas.is_empty():
			enemy_datas = [Database.get_enemy("ink_spirit")]
		battle.start(GameState.make_battle_deck(), enemy_datas, int(params.get("seed", -1)), true)
		if _room_run: GameState.room_run.apply_battle_setup(battle)
		if _expedition:
			GameState.expedition.apply_battle_setup(battle)
	if battle.achievement != null: battle.achievement.sample()
	_topbar = _build_topbar()
	root.add_child(_topbar)
	root.move_child(_player_panel, root.get_child_count() - 1)
	_preview_panel = _build_left()
	root.add_child(_preview_panel)
	_selection_actions.reparent(root)
	_board_view = _build_center()
	_board_view.tile_inspected.connect(_inspect_tile)
	root.add_child(_board_view)
	_enemy_panel = ScrollContainer.new()
	_enemy_panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_enemy_row = Ink.vbox(16)
	_enemy_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enemy_panel.add_child(_enemy_row)
	_enemy_paper = ArtPaper.new()
	_enemy_paper.open_scene = true
	root.add_child(_enemy_paper)
	# 两侧底板都位于字盘后方，避免右侧底板盖住外沿、左侧却在外沿下。
	root.move_child(_enemy_paper, _board_view.get_index())
	root.add_child(_enemy_panel)
	root.move_child(_player_panel, _enemy_panel.get_index())
	_footer = _build_bottombar()
	root.add_child(_footer)
	for source in [_player_status, _player_defense, _gold_strip, _pile_label]:
		source.details_requested.connect(_show_hud_details)
	_pile_label.activated.connect(_open_pile)
	_end_btn = Ink.button("结束回合")
	_end_btn.add_theme_font_size_override("font_size", 22)
	var end_style := StyleBoxFlat.new()
	end_style.bg_color = Color("24231e") if Palette.STYLE_ID == "taopunk" else Palette.PANEL_DARK
	end_style.border_color = Palette.GOLD_DK
	end_style.set_border_width_all(1)
	end_style.set_corner_radius_all(4)
	end_style.set_content_margin_all(10)
	_end_btn.add_theme_stylebox_override("normal", end_style)
	_end_btn.add_theme_color_override("font_color", Palette.PAPER_WARM)
	_end_btn.pressed.connect(_on_end_turn)
	root.add_child(_end_btn)
	_log_overlay = _build_log_panel()
	root.add_child(_log_overlay)
	_log_overlay.hide()
	_effects = BattleEffects.new()
	root.add_child(_effects)
	_effects.setup_impact(content, Router.study_stage)
	_audio = BattleAudio.new()
	add_child(_audio)
	EventBus.log_message.connect(_on_log)
	battle.enemy_acting.connect(_on_enemy_acting)
	battle.play_resolving.connect(_on_play_resolving)
	_watch_combatant(battle.player)
	_refresh_all()
	for line in battle.log:
		_on_log(line)
	_bubble.set_idle(_tutorial_hint() if _first_run_tutorial else _preview_hint())
	resized.connect(_layout)
	_layout()
	# A resumed fight should immediately restore the exact saved interaction state.
	if not Settings.reduced_motion and not saved.get("battle") is BattleState:
		_play_entrance()
	else:
		_board_view.call_deferred("play_opening")
	_on_log("战斗开始：%s" % node.title)
	# 开局就可能分出胜负：连字环自动打死敌人、生生不息反噬、金字碑开局化金
	if battle.is_over():
		_check_battle_over.call_deferred()
		return
	_offer_question.call_deferred()


## 问字签：开局从三枚字里挑一枚，作为本场临时字落盘
func _offer_question() -> void:
	var choices: Array = battle.question_choices.duplicate()
	if choices.is_empty() or not is_inside_tree():
		return
	var options: Array = []
	for g in choices:
		var cd: CharacterData = Database.get_character_by_glyph(g)
		options.append({"text": "【%s】" % g, "hint": cd.description if cd != null else ""})
	var overlay := ChoiceOverlay.new()
	overlay.setup({"title": Relics.name_of("question"), "body": "挑一枚字，作为本场临时字落到盘上。", "options": options})
	overlay.chose.connect(func(index: int):
		battle.take_question(choices[index])
		_refresh_all(true))
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mount_overlay(overlay)


func _play_entrance() -> void:
	_set_busy(true)
	_entrance = BattleEntrance.new()
	_entrance.setup(node, bool(params.get("elite", false)))
	_entrance.stamp_hit.connect(func(): _audio.play_cue("play"))
	_entrance.reveal_started.connect(_board_view.play_opening)
	_entrance.finished.connect(func():
		if not _exiting:
			_entrance = null
			_set_busy(false))
	add_child(_entrance)


func _exit_tree() -> void:
	_exiting = true
	_step_timer.stop()
	presentation_step_finished.emit()
	if EventBus.log_message.is_connected(_on_log):
		EventBus.log_message.disconnect(_on_log)
	for watch in _feedback_watches:
		if is_instance_valid(watch[0]) and watch[0].feedback.is_connected(watch[1]):
			watch[0].feedback.disconnect(watch[1])
	_feedback_watches.clear()
	_events.clear()
	if battle != null and battle.play_resolving.is_connected(_on_play_resolving):
		battle.play_resolving.disconnect(_on_play_resolving)


func _build_topbar() -> Control:
	var bar := Control.new()
	var surface := ArtPaper.new()
	surface.strip = true
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(surface)
	var title := Ink.label("活字战斗", "Heading")
	title.name = "Title"
	bar.add_child(title)
	_turn_label = Ink.label("回合 1", "Stat")
	bar.add_child(_turn_label)
	_gold_strip = ResourceStrip.new()
	bar.add_child(_gold_strip)
	var rule := Ink.hline()
	rule.name = "Rule"
	bar.add_child(rule)
	_menu_btn = Ink.button("菜单")
	_menu_btn.custom_minimum_size = Vector2(80, 48)
	_menu_btn.pressed.connect(_open_menu)
	bar.add_child(_menu_btn)
	_player_panel = Control.new()
	_player_hp_caption = Ink.label("玩家气血", "", Palette.INK)
	_player_hp_caption.add_theme_font_override("font", Ink.serif)
	_player_hp_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_player_panel.add_child(_player_hp_caption)
	_player_hp_caption.hide()
	_hp_icon = BattleSymbol.new()
	_hp_icon.symbol = "health"
	_hp_icon.ink = Palette.VERMILION_DK
	_player_panel.add_child(_hp_icon)
	_player_hp_value = Ink.label("", "", Palette.VERMILION_DK)
	_player_hp_value.clip_text = true
	_player_hp_value.add_theme_font_override("font", Ink.serif)
	_player_hp_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_player_panel.add_child(_player_hp_value)
	_player_hp = StatBar.new()
	_player_hp.show_text = false
	_player_panel.add_child(_player_hp)
	_player_panel.move_child(_player_hp, 0)
	_player_defense = DefenseDisplay.new()
	_player_panel.add_child(_player_defense)
	_player_status = StatusStrip.new()
	_player_panel.add_child(_player_status)
	content.add_child(_player_panel)
	return bar


func _make_enemy_card(i: int, e: Combatant) -> EnemyView:
	var view := EnemyView.new()
	view.setup(i, e)
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.clicked.connect(_on_enemy_clicked)
	view.details_requested.connect(_show_hud_details)
	_watch_combatant(e)
	return view


func _build_left() -> Control:
	var col := Control.new()
	var surface := ArtPaper.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_child(surface)
	_bubble = SpeechBubble.new()
	col.add_child(_bubble)
	_selection_actions = Ink.hbox(12)
	_confirm_btn = Ink.button("出字", true)
	_confirm_btn.custom_minimum_size = Vector2(128, 56)
	_confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_btn.add_theme_font_size_override("font_size", 28)
	_confirm_btn.disabled = true
	_confirm_btn.add_theme_color_override("font_disabled_color", Palette.INK_SOFT)
	_confirm_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_confirm_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	_confirm_btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	_confirm_btn.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	var stamp := ColorRect.new()
	stamp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamp.show_behind_parent = true
	_confirm_ink = ShaderMaterial.new()
	_confirm_ink.shader = load("res://src/shaders/seal_button.gdshader")
	_confirm_ink.set_shader_parameter("seal_color", Palette.VERMILION)
	_confirm_ink.set_shader_parameter("disabled_color", Palette.PAPER_DARK)
	_confirm_ink.set_shader_parameter("illustrated", Palette.STYLE_ID == "taopunk")
	stamp.material = _confirm_ink
	_confirm_btn.add_child(stamp)
	_confirm_btn.mouse_entered.connect(func(): _confirm_ink.set_shader_parameter("hovered", true))
	_confirm_btn.tooltip_text = "拖动连字后点击出字，或按回车。\n需要目标的词请按提示选择，再点「发动」。"
	_confirm_btn.mouse_exited.connect(func(): _confirm_ink.set_shader_parameter("hovered", false))
	_confirm_btn.button_down.connect(func(): _confirm_ink.set_shader_parameter("pressed", true))
	_confirm_btn.button_up.connect(func(): _confirm_ink.set_shader_parameter("pressed", false))
	_confirm_btn.pressed.connect(_on_primary)
	_selection_actions.add_child(_confirm_btn)
	_clear_btn = Ink.button("清除")
	var clear_style := StyleBoxFlat.new()
	clear_style.bg_color = Color(Palette.PAPER, 0.96)
	clear_style.border_color = Color(Palette.INK_SOFT, 0.65)
	clear_style.set_border_width_all(1)
	clear_style.set_content_margin_all(10)
	_clear_btn.add_theme_stylebox_override("normal", clear_style)
	_clear_btn.add_theme_stylebox_override("disabled", clear_style)
	_clear_btn.custom_minimum_size = Vector2(72, 56)
	_clear_btn.pressed.connect(_on_clear_cancel)
	_selection_actions.add_child(_clear_btn)
	col.add_child(_selection_actions)
	return col


func _build_center() -> BoardView:
	var view := BoardView.new()
	view.setup(battle.board)
	view.commit.connect(_on_commit)
	view.selection_changed.connect(_on_selection_changed)
	view.tile_picked.connect(_on_tile_picked)
	view.pick_cancelled.connect(_on_pick_cancelled)
	return view


func _build_log_panel() -> Control:
	var overlay := Control.new()
	overlay.z_index = 100
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(Palette.INK, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim_tap := TouchTap.new()
	dim.gui_input.connect(func(event: InputEvent):
		if dim_tap.matches(event, dim):
			_toggle_log())
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := Ink.panel()
	var factor := JourneyStyle.touch_scale(self)
	panel.custom_minimum_size = Vector2(minf(600 * factor, size.x - 32 * factor), minf(420 * factor, size.y - 32 * factor))
	center.add_child(panel)
	var col := Ink.vbox(12)
	panel.add_child(col)
	var head := Ink.hbox(10)
	var heading := Ink.h2("战报 · 近 %d 条" % RecentLog.MAX_ENTRIES)
	heading.add_theme_font_size_override("font_size", int(28 * factor))
	head.add_child(heading)
	head.add_child(Ink.expander())
	var close := Ink.button("关闭")
	close.custom_minimum_size.y = 48 * factor
	close.add_theme_font_size_override("font_size", int(20 * factor))
	close.pressed.connect(_toggle_log)
	head.add_child(close)
	col.add_child(head)
	_log_scroll = ScrollContainer.new()
	_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_log_scroll.get_v_scroll_bar().changed.connect(_scroll_log_to_end)
	col.add_child(_log_scroll)
	_log_box = Ink.vbox(6)
	_log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_scroll.add_child(_log_box)
	return overlay


func _build_bottombar() -> Control:
	var bar := Control.new()
	var surface := ArtPaper.new()
	surface.strip = true
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(surface)
	var line := Ink.hline()
	line.name = "Rule"
	bar.add_child(line)
	_hint = Ink.label("拖动连词 · 回车出字 · ESC 取消", "Muted")
	bar.add_child(_hint)
	_pile_label = ResourceStrip.new()
	bar.add_child(_pile_label)
	return bar


func _refresh_all(animate_board := false) -> void:
	SaveManager.request_save()
	_refresh_enemies()
	_refresh_player()
	_refresh_piles()
	_turn_label.text = "回合 %d" % battle.turn
	_turn_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_turn_label.tooltip_text = ("遗物：\n" + "\n".join(battle.relics.map(func(r): return Relics.text(r)))) if not battle.relics.is_empty() else ""
	_board_view.rebuild(animate_board)
	_update_input()
	_layout()


func _refresh_enemies() -> void:
	if _enemy_widgets.size() != battle.enemies.size():
		for widget in _enemy_widgets:
			_enemy_row.remove_child(widget)
			widget.queue_free()
		_enemy_widgets.clear()
		for i in battle.enemies.size():
			var widget := _make_enemy_card(i, battle.enemies[i])
			_enemy_row.add_child(widget)
			_enemy_widgets.append(widget)
	for widget in _enemy_widgets:
		widget.refresh()
	_refresh_intents()
	if is_node_ready() or _end_btn != null:
		_layout()


func _refresh_intents() -> void:
	_board_view.enemy_markers = EnemyMechanics.markers(battle)
	_board_view.queue_redraw()
	if _board_view._path_layer != null: _board_view._path_layer.queue_redraw()
	if _target_index >= battle.enemies.size() or not battle.enemies[_target_index].is_alive():
		var first := battle.first_alive_enemy()
		_target_index = battle.enemies.find(first) if first != null else 0
	for i in _enemy_widgets.size():
		_enemy_widgets[i].set_intent(battle.current_intent(battle.enemies[i]))
		_enemy_widgets[i].set_targeted(i == _target_index)


func _refresh_player() -> void:
	_show_player_hp(battle.player.hp, battle.player.max_hp)
	_player_status.set_entries(StatusDisplay.collect(battle.player, battle))
	_show_defense(battle.player.block, battle.player.persistent_block)
	var wallet: Array = [{"id": "gold", "title": "铜钱", "value": GameState.gold, "color": Palette.GOLD_DK, "description": "可用铜钱 %d，本战获得 %d。" % [GameState.gold, battle.gold_earned]}]

	_gold_strip.set_entries(wallet)


func _show_player_hp(hp: int, max_hp: int) -> void:
	_player_hp.setup_bar(hp, max_hp, Palette.HP)
	_player_hp_value.text = "%d / %d" % [hp, max_hp]


func _show_defense(block: int, persistent: int) -> void:
	_player_defense.set_values(block, persistent)
	_layout()


func _refresh_piles() -> void:
	if _pile_label == null:
		return
	_pile_label.set_entries([
		{"id": "bag", "title": "抽牌堆", "action": true, "value": battle.bag.size(), "color": Palette.INK_SOFT, "description": "点击查看剩余 %d 枚字，不显示抽取顺序。" % battle.bag.size()},
		{"id": "discard", "title": "弃牌堆", "action": true, "value": battle.discard.size(), "color": Palette.INK_SOFT, "description": "点击查看已弃置的 %d 枚字。" % battle.discard.size()}])


func _on_log(text: String) -> void:
	text = BattleText.clean(text)
	RecentLog.append(_log_lines, text)
	_log_dirty = true
	_queue_log_refresh()


func _queue_log_refresh() -> void:
	if not is_instance_valid(_log_overlay) or not _log_overlay.is_visible_in_tree() or _log_refresh_queued: return
	_log_refresh_queued = true
	_render_log.call_deferred()


func _render_log() -> void:
	_log_refresh_queued = false
	if not _log_dirty or not _log_overlay.is_visible_in_tree(): return
	if not is_instance_valid(_log_text):
		_log_text = Ink.caption("")
		_log_text.add_theme_font_size_override("font_size", int(16 * JourneyStyle.touch_scale(self)))
		_log_box.add_child(_log_text)
	_log_text.text = RecentLog.display_text(_log_lines)
	_log_dirty = false
	_scroll_log_to_end.call_deferred()


func _scroll_log_to_end() -> void:
	if is_inside_tree() and is_instance_valid(_log_scroll) and is_instance_valid(_log_overlay) and _log_overlay.is_visible_in_tree():
		_log_scroll.scroll_vertical = int(_log_scroll.get_v_scroll_bar().max_value)


# ---------------------------------------------------------------- 独立词效预览
func _on_selection_changed(path: Array, glyphs: Array, word: WordData, preview_target: Dictionary = {}) -> void:
	if preview_target.is_empty() and _board_view.pick_mode.is_empty():
		_row_choice = {}
	if path.is_empty():
		_bubble.frame_details.set_effect_text("")
		_bubble.frame_details.hide()
	if preview_target.is_empty() and not path.is_empty() and _board_view.pick_mode.is_empty() and not _ready_action.is_empty() and not _ready_action.get("repeat_rotate", false):
		if not battle.pending_reveal.is_empty():
			battle.return_pending_reveal()
		_ready_action = {}
		_pending_path = []
		_target_kind = -1
		_board_view.picked_cells = []
	if path != _last_selection and not path.is_empty() and _audio != null:
		_audio.play_cue("select")
	_last_selection = path.duplicate()
	if glyphs.is_empty():
		_current_word = null
		_bubble.set_idle(_preview_hint())
		_update_input()
		return
	if word == null and glyphs.size() >= 2:
		word = EffectPreview.word_for(glyphs, battle)
	var word_changed := _current_word != word
	_current_word = word
	var text := ""
	for g in glyphs:
		text += str(g)
	_update_input()
	_bubble.set_context(_selection_context(path))
	if word != null and word_changed and not Settings.drag_release_play:
		_pop_confirm()

	if word == null:
		if glyphs.size() >= 2:
			_bubble.set_text("「%s」" % text, "不成词。调整路径后重试，不消耗字块。", SpeechBubble.State.ERROR)
		else:
			var inst: CharInstance = battle.board.get_xy(path[0])
			var solo_description := EffectPreview.solo_text(inst, battle, path, preview_target)
			_bubble.set_text("「%s」" % text, "单字：%s" % solo_description, SpeechBubble.State.PREVIEW)
		return
	if not word.implemented:
		_bubble.set_text("《%s》" % word.word, "效果待定。", SpeechBubble.State.PREVIEW)
		return
	var req := ""
	if preview_target.is_empty() and (word.requires_target != EffectData.Target.NONE or not word.interaction.is_empty()):
		req = "　→ 需选目标"
	var body_text := EffectPreview.word_text(word, battle, path, preview_target, true)
	_bubble.set_text("《%s》" % word.word, "%s%s" % [body_text, req], SpeechBubble.State.PREVIEW, word)


# ---------------------------------------------------------------- 交互
func _on_enemy_clicked(index: int) -> void:
	if _busy or _finished or _modal_count > 0 or not battle.enemies[index].is_alive():
		return
	_target_index = index
	_refresh_intents()
	var path: Array = _ready_action.get("path", _board_view.path)
	if not path.is_empty():
		_on_selection_changed(path, battle.board.glyphs_of(path), EffectPreview.word_for(battle.board.glyphs_of(path), battle), _ready_action.get("target", {}))
	else:
		_bubble.set_context(_selection_context(path))




func _on_primary() -> void:
	if _finished or _busy:
		return
	if _collect_own_active:
		var cp := _pending_path
		_collect_own_active = false
		_collect_junk = false
		var cells := _collect_own_cells.duplicate()
		_collect_own_cells = []
		_board_view.end_pick()
		_on_commit(cp, {"cells": cells})
		return
	# 转速：继续旋转（最多 3 次）；转满自动结束，也可点「清除」提前停下
	if _ready_action.get("repeat_rotate", false):
		var rotating_at := _board_effect_point({"target": {"tile": battle.repeat_rotate_tile}, "effects": [], "path": []}, 2)
		battle.do_repeat_rotate()
		_effects.glyph_impact(GlyphVfxProfile.for_glyph("转"), rotating_at, 38)
		if battle.repeat_rotate_count >= BattleBalance.i("rotate_limit", 3):
			battle.end_repeat_rotate()
			_ready_action = {}
			_on_log("转速：已转满 3 次，结束")
		else:
			_ready_action = {"repeat_rotate": true, "path": [], "target": {}}
		_refresh_all(true)
		_update_input()
		_check_battle_over()
		return
	if not _ready_action.is_empty():
		var a := _ready_action
		_ready_action = {}
		_board_view.end_pick()
		_pending_path = []
		_target_kind = -1
		_on_commit(a.path, a.target)
		return
	if _board_view.pick_mode != "":
		return
	# 合击·结阵：点「发动」时才把登记的词一起结算
	if battle.formation_mode and not battle.formation_queue.is_empty() and _board_view.path.is_empty():
		_set_busy(true)
		var count := battle.formation_queue.size()
		var before := [battle.player.energy, battle.player.heat, GameState.gold]
		_events.clear()
		_collecting = true
		battle.resolve_formation()
		_collecting = false
		_audio.play_cue("play")
		if _handle_effect_requests():
			return
		if not await _replay_feedback():
			return
		_board_view.clear_selection()
		_refresh_all(true)
		_bubble.set_text("结阵发动", "%d 个词已结算。" % count, SpeechBubble.State.RESULT)
		_resource_feedback(before)
		_set_busy(false)
		if _handle_effect_requests():
			return
		_check_battle_over()
		return
	_on_commit(_board_view.path.duplicate())


## 选好路径+目标后进入「待发动」：不立即结算，可继续点别处改选，或点「发动」执行。
func _fill_ready(path: Array, target: Dictionary) -> void:
	_pending_path = path.duplicate() if _board_view.pick_reselect else []
	_ready_action = {"path": path, "target": target}
	if not _board_view.pick_reselect:
		_board_view.picked_cells = target.get("cells", []).duplicate()
		for key in ["tile", "tile2", "cell1", "cell2"]:
			if target.has(key):
				_board_view.picked_cells.append(target[key])
		for place in target.get("places", []):
			_board_view.picked_cells.append(place[1])
	_on_selection_changed(path, battle.board.glyphs_of(path), EffectPreview.word_for(battle.board.glyphs_of(path), battle), target)
	var hint := "已选目标 · 按发动确认"
	if _target_kind >= 0:
		var tile: Vector2i = target.get("tile", Vector2i(-1, -1))
		var chosen := "第%d行" % (int(target.row) + 1) if target.has("row") else "第%d行 · 第%d列" % [tile.y + 1, tile.x + 1]
		hint = "已选：" + chosen + " · 点字盘改选 · 按发动确认"
	_bubble.set_context(_selection_context(path) + "\n" + hint)
	_update_input()


func _on_clear_cancel() -> void:
	if _collect_own_active or _recast_three_active or not _ready_action.is_empty() or _board_view.pick_mode != "":
		_on_pick_cancelled()
		_board_view.end_pick()
		_update_input()
		return
	_board_view.clear_selection()


func _on_commit(path: Array, target: Dictionary = {}) -> void:
	if _finished or _compound_picker_active or _solo_release_picker_active or _solo_bag_picker_active or _busy or (_modal_count > 0 and target.is_empty()):
		return
	if _board_view.pick_mode != "" and _ready_action.is_empty():
		return
	if _choose_solo_release(path, target):
		return
	if _choose_solo_throw(path, target):
		return
	if _choose_solo_bag(path, target):
		return
	if _choose_word_transfer(path, target):
		return
	var request := battle.play_options(path)
	if int(request.required_target) == EffectData.Target.BOARD_ROW:
		if not _matches_row_choice(path, target):
			_ready_action = {}
			_pending_path = path.duplicate()
			_request_target(EffectData.Target.BOARD_ROW)
			return
		# 选行凭据只能使用一次；后续同名词也必须重新选择。
		_row_choice = {}
	var interaction: String = request.interaction
	if target.is_empty() and not interaction.is_empty():
		match interaction:
			"reveal_pick_board":
				_run_transform(path)
				return
			"choose_glyph_empower":
				_open_glyph_picker(path, "empower_glyph", GameState.glyph_counts(), "强化：选择一个字（本场额外触发单字效果）")
				return
			"choose_battle_card_remove":
				_open_glyph_picker(path, "remove_glyph", battle.battle_card_counts(), "炼化：选择一张牌移出本场战斗")
				return
			"choose_fuse_pair":
				_run_pair(path, "fuse")
				return
			"choose_same_pair":
				_run_pair(path, "same")
				return
			"choose_any_pair", "choose_row_pair", "choose_move":
				_run_pair(path, {"choose_any_pair": "any", "choose_row_pair": "row", "choose_move": "move"}[interaction])
				return
			"choose_place_two":
				_run_place_two(path)
				return
			"choose_recover_two", "choose_recover_to_bag":
				_run_recover(path, interaction)
				return
			"choose_glyph_gild":
				_open_gild_picker(path)
				return
			"choose_discard_place":
				_open_discard_place(path)
				return
			"choose_line":
				_run_line_pick(path)
				return
			"choose_merge_flow":
				_run_merge_flow(path)
				return
			"choose_three_tiles":
				_run_three_tiles(path, _current_word.word)
				return
			"choose_own_tiles":
				_run_collect_own(path)
				return
			"choose_junk_tiles":
				_run_collect_own(path, true)
				return
	if _choose_compound_copy(path, target):
		return
	var play_target := target.duplicate()
	var needs_target := int(request.required_target) != EffectData.Target.NONE
	if not play_target.is_empty() or not needs_target:
		# 规则层索引针对存活列表；HUD 索引针对固定敌人列表。
		play_target["target_index"] = battle.alive_enemies().find(battle.enemies[_target_index]) if not battle.enemies.is_empty() else 0
	var old_resources := [battle.player.energy, battle.player.heat, GameState.gold]
	_events.clear()
	_collecting = true
	var result := battle.try_play(path, play_target)
	_collecting = false
	if not result.ok:
		if int(result.need_target) >= 0:
			_pending_path = path
			_request_target(int(result.need_target))
			return
		_board_view.flash_invalid()
		_on_log("× " + str(result.reason))
		_bubble.set_error(str(result.reason))
		return
	# 合击·结阵：本词只登记，不结算（点「发动」后一起结算）
	if result.get("queued", false):
		_ready_action = {}
		_board_view.end_pick()
		_board_view.clear_selection()
		_refresh_all(true)
		var queued_text := ""
		for g in result.glyphs:
			queued_text += str(g)
		_bubble.set_text("结阵登记：《%s》" % queued_text, "点「发动」与本回合其他词一起结算。", SpeechBubble.State.PREVIEW)
		return
	_set_busy(true)
	_ready_action = {}
	_target_kind = -1
	_board_view.end_pick()
	_audio.play_cue("play")
	_board_view.release_selected(path)
	# 停息/停电等即时请求：在演出前即刻结算，保证逻辑与输入时机、动画开关无关
	if _handle_effect_requests():
		return
	if not await _wait_step(0.11 if not Settings.reduced_motion else 0.01):
		return
	if not await _replay_feedback():
		return
	_board_view.clear_selection()
	_refresh_all(true)
	var played_profile := GlyphVfxProfile.for_play(result.glyphs, result.word)
	if played_profile.board and not result.zero_effect:
		_effects.glyph_impact(played_profile, _board_effect_point({"target": play_target, "path": path, "effects": result.word.effects if result.word != null else []}), 38)
	elif played_profile.focus == "ability" and not result.zero_effect:
		_effects.glyph_impact(played_profile, _effects.point_of(_player_status) + Vector2(0, 34), 20)
	if _gravity_in_play(result):
		if not await _wait_step(0.18 if not Settings.reduced_motion else 0.01):
			return
		_effects.table_impact(7.0)
		_audio.play_cue("gravity")
	_hint.text = "拖动连词 · 回车出字 · ESC 取消"
	_bubble.set_result(result.word, result.glyphs, result.messages)
	if _first_run_tutorial and _tutorial_step == 0:
		_tutorial_step = 1
		_bubble.set_context("新手引导：留意敌人头像旁的意图；结束回合后，防御会抵挡攻击。")
	else:
		_bubble.set_context(_selection_context([]))
	_resource_feedback(old_resources)
	if result.word != null:
		_on_log("成词：%s" % result.word.word)
	_set_busy(false)

	if result.zero_effect:
		_on_log("（该字/词没有效果，仅消耗）")
	if _handle_effect_requests():
		return
	# 转速：本词结算后保留「发动」，可继续旋转同一处（最多 3 次）；点「清除」即停下。
	if battle.repeat_rotate_tile.x >= 0 and battle.repeat_rotate_count < BattleBalance.i("rotate_limit", 3):
		_ready_action = {"repeat_rotate": true, "path": [], "target": {}}
		_update_input()
		_check_battle_over()
		return
	_check_battle_over()


## 处理「停息/停电」等需要立即结算的请求。返回 true 表示应中断后续演出/检查。
func _handle_effect_requests() -> bool:
	if battle.blackout_requested:
		battle.blackout_requested = false
		_show_blackout()
	if battle.end_turn_requested:
		battle.end_turn_requested = false
		_effects.glyph_impact(GlyphVfxProfile.for_glyph("停"), _effects.point_of(_board_view), 28)
		_on_end_turn(true)
		return true
	return false


func _show_blackout() -> void:
	var ov := BlackoutOverlay.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.restored.connect(func(): _on_log("来电了。"))
	_mount_overlay(ov)


func _matches_row_choice(path: Array, target: Dictionary) -> bool:
	if _row_choice.is_empty() or not target.has("row") or _row_choice.path != path or int(_row_choice.row) != int(target.row):
		return false
	var uids: Array = []
	for cell in path:
		var inst := battle.board.get_xy(cell)
		if inst == null: return false
		uids.append(inst.uid)
	return uids == _row_choice.uids


func _request_target(target_kind: int) -> void:
	_row_choice = {}
	_target_kind = target_kind
	_target_title = "".join(battle.board.glyphs_of(_pending_path))
	_target_effect = _current_word.effect_summary if _current_word != null else _bubble._effect_text
	var instruction := "请选择盘面目标"
	match target_kind:
		EffectData.Target.BOARD_2X2:
			_board_view.begin_pick("2x2", false, true)
			instruction = "点击 2×2 区域左上格；金色框内四格一起旋转。"
		EffectData.Target.BOARD_3X3:
			_board_view.begin_pick("3x3", false, true)
			instruction = "点击 3×3 区域左上格；金色框内九格一起旋转。"
		EffectData.Target.BOARD_ROW:
			_board_view.begin_pick("row", false, true)
			instruction = "点击任意格，选择它所在的整行。"
		EffectData.Target.EMPTY_TILE:
			_board_view.begin_pick("empty", false, true)
			instruction = "请选择空格。"
		EffectData.Target.ENEMY_GLYPH:
			_board_view.begin_pick("enemy", false, true)
			instruction = "请选择敌方字。"
		EffectData.Target.BOARD_TILE:
			var choice_spec := battle.play_options(_pending_path)
			var inst: CharInstance = battle.board.get_xy(_pending_path[0]) if _pending_path.size() == 1 else null
			if choice_spec.has("cells") and (inst == null or inst.data.solo_handler != "throw_neighbor"):
				var candidates: Array = choice_spec.cells
				var excluded: Array = []
				for i in battle.board.cells.size():
					var pos := battle.board.to_xy(i)
					if not candidates.has(pos):
						excluded.append(pos)
				_board_view.begin_pick("any", false, excluded, true)
			else:
				_board_view.begin_pick("any", false, true)
		EffectData.Target.DISCARD_GLYPH:
			_choose_discard()
		EffectData.Target.BAG_GLYPH:
			_choose_solo_bag(_pending_path, {})
			return
	_bubble.set_text(_target_title, _target_effect + "\n" + instruction, SpeechBubble.State.PREVIEW)
	_bubble.set_context(_selection_context(_pending_path))
	_hint.text = instruction
	_update_input()


func _on_tile_picked(pos: Vector2i) -> void:
	if not _placement_mode.is_empty():
		_finish_placement_cell(pos)
		return
	if not _word_transfer_target.is_empty():
		var path := _pending_path
		var chosen := _word_transfer_target.duplicate()
		_word_transfer_target.clear()
		chosen["tile"] = pos
		_fill_ready(path, chosen)
		return
	if _solo_throw_active:
		if _solo_throw_from == Vector2i(-1, -1):
			_solo_throw_from = pos
			_solo_throw_uid = battle.board.get_xy(pos).uid
			var origin := battle.board.get_xy(_pending_path[0])
			_pick_only("throw_destination", battle.solo_throw_destinations(origin, _pending_path[0]))
			_on_log("投：选择落点空格（可选本字发动后腾出的原格）")
		else:
			var path := _pending_path
			var chosen := {"tile": _solo_throw_from, "tile2": pos, "throw_uid": _solo_throw_uid}
			_solo_throw_active = false
			_solo_throw_from = Vector2i(-1, -1)
			_solo_throw_uid = -1
			_fill_ready(path, chosen)
		return
	if _collect_own_active:
		if battle.board.get_xy(pos) == null:
			return
		if _collect_junk and (_pending_path.has(pos) or not BattleState.is_refinable_junk(battle.board.get_xy(pos))):
			return
		if _collect_own_cells.has(pos):
			_collect_own_cells.erase(pos)   # 再点已选格 = 取消该格
		else:
			if _collect_junk and _collect_own_cells.size() >= 2:
				return
			_collect_own_cells.append(pos)
		_board_view.picked_cells = _collect_own_cells.duplicate()
		_on_log("%s：已选 %d 枚（再点可取消），点「发动」结束" % ["分流" if _collect_junk else "收心", _collect_own_cells.size()])
		_update_input()
		return
	if _recast_three_active:
		var rc: CharInstance = battle.board.get_xy(pos)
		if rc == null or rc.pinned or _pending_path.has(pos):
			_on_log("%s：请选择施词以外的非固定字（%d/%d）" % [_three_tiles_word, _recast_three_cells.size(), BattleBalance.i("recast_target_count", 3)])
			return
		for chosen in _recast_three_cells:
			var inst := battle.board.get_xy(chosen)
			if inst != null and inst.uid == rc.uid:
				return
		_recast_three_cells.append(pos)
		_board_view.picked_cells = _recast_three_cells.duplicate()
		if _recast_three_cells.size() >= BattleBalance.i("recast_target_count", 3):
			var rp := _pending_path
			_recast_three_active = false
			var cells := _recast_three_cells.duplicate()
			_recast_three_cells = []
			_fill_ready(rp, {"cells": cells})
		else:
			_on_log("%s：已选 %d/3（点清除可重新选择）" % [_three_tiles_word, _recast_three_cells.size()])
			_update_input()
		return
	if _merge_active:
		if _merge_cell1 == Vector2i(-1, -1):
			_merge_cell1 = pos
			var excluded: Array = []
			for i in battle.board.cells.size():
				var cell := battle.board.to_xy(i)
				if not battle.board.is_adjacent(pos, cell): excluded.append(cell)
			_board_view.begin_pick("empty", false, excluded)
			_pick_prompt(_pending_path, "合流 · 3/3：点金框中的相邻空格作为第二个落点，再点「发动」。")
			return
		if not battle.board.is_adjacent(_merge_cell1, pos):
			_bubble.set_error("合流：第二个空格必须与第一个四邻相接，请选择金框内的空格。")
			return
		var mp := _pending_path
		_pending_path = []
		_merge_active = false
		_fill_ready(mp, {"cell1": _merge_cell1, "cell2": pos, "merge_bag_uid": _merge_bag_uid, "merge_discard_uid": _merge_discard_uid})
		return
	if _pending_place_uid >= 0:
		var pp := _pending_path
		_pending_path = []
		var uidp := _pending_place_uid
		_pending_place_uid = -1
		_fill_ready(pp, {"tile": pos, "place_uid": uidp})
		return
	if _fuse_stage == 1:
		if _pair_mode == "move":
			var source: CharInstance = battle.board.get_xy(pos)
			if source == null or source.pinned or _pending_path.has(pos):
				_board_view.begin_pick("any")
				_pick_prompt(_pending_path, "请选择未固定、未参与本词的盘面字。")
				return
		_fuse_first = pos
		_fuse_stage = 2
		if _pair_mode == "place_two" and battle.pending_reveal.size() == 1:
			_fuse_stage = 0
			_fill_ready(_pending_path, {"cell1": pos})
			return
		if _pair_mode == "same":
			var first := battle.board.get_xy(pos)
			var matches: Array = []
			for i in battle.board.cells.size():
				var other: CharInstance = battle.board.cells[i]
				var cell := battle.board.to_xy(i)
				if other != null and cell != pos and not _pending_path.has(cell) and other.is_player_owned() and not other.temporary and not other.pinned and other.glyph_list() == first.glyph_list():
					matches.append(cell)
			_pick_only("own", matches)
		else:
			_board_view.begin_pick("empty" if _pair_mode in ["move", "place_two"] else ("slot" if _pair_mode in ["any", "row"] else "own"))
		_board_view.picked_cells = [_fuse_first]
		_pick_prompt(_pending_path, {"fuse": "再选相邻己方字", "same": "再选同字的另一枚", "any": "再选另一个格子", "row": "再选同一行的另一格", "move": "选择移入的空格", "place_two": "选择第二个空格"}[_pair_mode])
		return
	if _fuse_stage == 2:
		var ok := false
		if _pair_mode == "fuse":
			ok = battle.board.is_adjacent(_fuse_first, pos)
		elif _pair_mode == "same":
			var c1: CharInstance = battle.board.get_xy(_fuse_first)
			var c2: CharInstance = battle.board.get_xy(pos)
			ok = c2 != null and pos != _fuse_first and c1 != null and c2.glyph_list() == c1.glyph_list() and not c1.temporary and not c2.temporary and not c1.pinned and not c2.pinned and not _pending_path.has(pos) and not _pending_path.has(_fuse_first)
		elif _pair_mode == "row":
			ok = pos.y == _fuse_first.y and pos != _fuse_first
		else:
			ok = pos != _fuse_first
		if not ok:
			_board_view.begin_pick("empty" if _pair_mode in ["move", "place_two"] else ("slot" if _pair_mode in ["any", "row"] else "own"))
			_board_view.picked_cells = [_fuse_first]
			_pick_prompt(_pending_path, "选择不合法，请重选第二格。")
			return
		var fp := _pending_path
		_pending_path = []
		_fuse_stage = 0
		_fill_ready(fp, {"cell1": _fuse_first, "cell2": pos} if _pair_mode == "place_two" else {"tile": _fuse_first, "tile2": pos})
		return
	var path := _pending_path
	_pending_path = []
	if path.is_empty():
		return
	var t := {"tile": pos, "enemy_glyph": pos}
	if _target_kind == EffectData.Target.BOARD_ROW:
		t["row"] = pos.y
		_row_choice = {"path":path.duplicate(), "uids":path.map(func(cell): return battle.board.get_xy(cell).uid), "row":pos.y}
	if _transform_uid >= 0:
		t["transform_uid"] = _transform_uid
		t["chosen_uid"] = _transform_uid
	_transform_uid = -1
	_fill_ready(path, t)


func _run_pair(path: Array, mode: String) -> void:
	if mode == "same":
		var candidates: Array = []
		for i in battle.board.cells.size():
			var first: CharInstance = battle.board.cells[i]
			var pos := battle.board.to_xy(i)
			if first == null or path.has(pos) or not first.is_player_owned() or first.temporary or first.pinned:
				continue
			for j in battle.board.cells.size():
				var second: CharInstance = battle.board.cells[j]
				if i != j and not path.has(battle.board.to_xy(j)) and second != null and second.is_player_owned() and not second.temporary and not second.pinned and first.glyph_list() == second.glyph_list():
					candidates.append(pos)
					break
		if candidates.is_empty():
			_bubble.set_error("精炼：需要两枚施词以外、字形相同的己方原实体")
			return
		_pending_path = path
		_pair_mode = mode
		_fuse_stage = 1
		_pick_only("own", candidates)
		_on_log("精炼：选择要持续强化的第一枚实体")
		return
	_pending_path = path
	_pair_mode = mode
	_fuse_stage = 1
	_board_view.begin_pick("slot" if mode in ["any", "row"] else ("any" if mode == "move" else "own"))
	_pick_prompt(path, "选择要移动的字" if mode == "move" else ("选择第一个格子" if mode in ["any", "row"] else "选择第一枚己方字"))


func _pick_prompt(path: Array, instruction: String) -> void:
	var glyphs := battle.board.glyphs_of(path)
	var word := EffectPreview.word_for(glyphs, battle)
	_bubble.set_text("".join(glyphs), (EffectPreview.word_text(word, battle, path, {"picking": true}, true) + "\n" if word != null else "") + instruction, SpeechBubble.State.PREVIEW)
	_bubble.set_context(_selection_context(path))
	_update_input()


func _run_place_two(path: Array) -> void:
	if battle.board.empty_indices().is_empty():
		_bubble.set_error("火急需要字袋中的字和盘面空格。")
		return
	_pending_path = path.duplicate()
	var preparation := battle.prepare_interaction(path)
	if not preparation.ok:
		_pending_path = []
		_bubble.set_error(str(preparation.reason))
		return
	_pair_mode = "place_two"
	_fuse_stage = 1
	_board_view.begin_pick("empty")
	_pick_prompt(path, "选择第一个空格；取消会把揭示的字放回。")


func _run_recover(path: Array, mode: String) -> void:
	if mode == "choose_recover_two" and battle.board.empty_indices().is_empty():
		_bubble.set_error("收复需要盘面空格。")
		return
	_pending_path = path.duplicate()
	_placement_mode = mode
	_placement_places = []
	_choose_placement_card()


func _choose_placement_card() -> void:
	var list := battle.discard_instances().filter(func(entry): return not _placement_places.any(func(place): return place.uid == entry.uid))
	if list.is_empty():
		if _placement_places.is_empty():
			_on_pick_cancelled()
			_bubble.set_error("弃字堆没有可放回的己方字。")
		else:
			_finish_recover()
		return
	var options: Array = []
	for entry in list:
		options.append({"text": "【%s】" % entry.glyph})
	options.append({"text": "只放回一枚并确认" if not _placement_places.is_empty() else "取消"})
	var overlay := ChoiceOverlay.new()
	overlay.setup({"title": "从弃字堆选字", "options": options})
	overlay.chose.connect(func(index: int):
		if index >= list.size():
			if _placement_places.is_empty():
				_on_pick_cancelled()
			else:
				_finish_recover()
			return
		_placement_uid = int(list[index].uid)
		_board_view.begin_pick("own" if _placement_mode == "choose_recover_to_bag" else "empty")
		_pick_prompt(_pending_path, "选择回袋的己方实体字" if _placement_mode == "choose_recover_to_bag" else ("选择放回的空格" if _placement_places.is_empty() else "选择与第一格相邻的空格")))
	_mount_overlay(overlay)


func _finish_placement_cell(pos: Vector2i) -> void:
	if _placement_mode == "choose_recover_to_bag":
		var inst: CharInstance = battle.board.get_xy(pos)
		if inst == null or inst.temporary or inst.pinned or _pending_path.has(pos):
			_board_view.begin_pick("own")
			_pick_prompt(_pending_path, "请选择未固定、未参与本词的己方实体字。")
			return
		_placement_mode = ""
		_fill_ready(_pending_path, {"tile": pos, "place_uid": _placement_uid})
		return
	if not _placement_places.is_empty() and not battle.board.is_adjacent(_placement_places[0].cell, pos):
		_board_view.begin_pick("empty")
		_pick_prompt(_pending_path, "第二个空格必须与第一个相邻。")
		return
	_placement_places.append({"uid": _placement_uid, "cell": pos})
	if _placement_places.size() >= 2 or not battle.has_adjacent_empty_pair():
		_finish_recover()
	else:
		_choose_placement_card()


func _finish_recover() -> void:
	_placement_mode = ""
	_fill_ready(_pending_path, {"places": _placement_places.map(func(place): return [place.uid, place.cell])})
	_placement_places = []


func _open_discard_place(path: Array) -> void:
	var list := battle.discard_instances()
	if list.is_empty():
		_on_log("放回：弃字堆为空")
		return
	_pending_path = path
	var options: Array = []
	for d in list:
		options.append({"text": "【%s】" % d["glyph"]})
	var overlay := ChoiceOverlay.new()
	overlay.setup({"title": "放回：选择弃字堆中的一枚己方字", "options": options})
	overlay.chose.connect(_on_discard_place_chosen.bind(list))
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mount_overlay(overlay)


func _on_discard_place_chosen(index: int, list: Array) -> void:
	if index < 0 or index >= list.size():
		_pending_path = []
		return
	_pending_place_uid = int(list[index]["uid"])
	_board_view.begin_pick("empty")
	_on_log("放回：选择放置的空格")


func _on_pick_cancelled() -> void:
	_row_choice = {}
	if not battle.pending_reveal.is_empty():
		battle.return_pending_reveal()
	_pending_path = []
	_transform_uid = -1
	_fuse_stage = 0
	_pending_place_uid = -1
	_merge_active = false
	_merge_cell1 = Vector2i(-1, -1)
	_ready_action = {}
	_recast_three_active = false
	_recast_three_cells = []
	_three_tiles_word = ""
	_collect_own_active = false
	_collect_own_cells = []
	_collect_junk = false
	_word_transfer_target.clear()
	_solo_throw_active = false
	_solo_throw_from = Vector2i(-1, -1)
	_solo_throw_uid = -1
	_placement_mode = ""
	_placement_places = []
	_placement_uid = -1
	_target_kind = -1
	_board_view.end_pick()
	_board_view.clear_selection()
	_hint.text = "拖动连词 · 回车出字 · ESC 取消"
	_update_input()
	if battle.repeat_rotate_tile.x >= 0:
		battle.end_repeat_rotate()   # 转速：点「清除」= 提前停下


func _run_line_pick(path: Array, rows_only := false) -> void:
	_pending_path = path
	var options: Array = []
	for i in battle.board.size:
		options.append({"text": "第 %d 行" % (i + 1)})
	if not rows_only:
		for i in battle.board.size:
			options.append({"text": "第 %d 列" % (i + 1)})
	var word_name := _current_word.word if _current_word != null else "目标选择"
	var ov := ChoiceOverlay.new()
	ov.setup({"title": "%s：选择%s" % [word_name, "一行" if rows_only else "一行或一列"], "options": options, "board_peek": true})
	ov.chose.connect(_on_line_chosen.bind(rows_only))
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mount_overlay(ov)


func _on_line_chosen(index: int, rows_only := false) -> void:
	var p := _pending_path
	_pending_path = []
	var n := battle.board.size
	if index < 0 or index >= (n if rows_only else n * 2):
		return
	var t: Dictionary = {}
	if index < n:
		t["row"] = index
	else:
		t["col"] = index - n
	_on_commit(p, t)


func _pick_only(mode: String, allowed: Array) -> void:
	var excluded: Array = []
	for i in battle.board.cells.size():
		var pos := battle.board.to_xy(i)
		if not allowed.has(pos):
			excluded.append(pos)
	_board_view.begin_pick(mode, false, excluded)

func _choose_solo_throw(path: Array, target: Dictionary) -> bool:
	if target.has("tile2") or path.size() != 1 or not battle.board.valid_path(path):
		return false
	var inst := battle.board.get_xy(path[0])
	if inst == null or inst.word_only or inst.glyph_list().size() != 1 or inst.data.solo_handler != "throw_neighbor":
		return false
	var candidates := battle.solo_target_cells(inst, path[0])
	if candidates.is_empty():
		return false
	var due := EffectUtil.discounted_cost(battle, BattleBalance.i("throw_cost", 1))
	if EffectUtil.available(battle) < due or battle.solo_throw_destinations(inst, path[0]).is_empty():
		_bubble.set_error("投：需要可用空格与 %d 铜钱支付额" % due)
		return true
	_pending_path = path
	_solo_throw_active = true
	_solo_throw_from = Vector2i(-1, -1)
	_solo_throw_uid = -1
	_pick_only("any", candidates)
	_on_log("投：选择一枚四邻非固定字，发动时支付 %d" % due)
	_update_input()
	return true

## 精/购预览现有字袋实体，选择与取消均不提前改变任何资源。
func _choose_word_transfer(path: Array, target: Dictionary) -> bool:
	if not target.is_empty() or not battle.board.valid_path(path):
		return false
	var request := battle.play_options(path)
	var word: WordData = request.word
	if word == null or request.needs not in ["deploy", "buyback"]:
		return false
	var deploying: bool = request.needs == "deploy"
	var cards: Array = request.cards
	if cards.is_empty():
		_on_commit(path, {"skip_transfer": true})
		return true
	if EffectUtil.available(battle) < EffectUtil.discounted_cost(battle, BattleBalance.i("buy_cost", 2)):
		_bubble.set_error("%s：需要 2 铜钱支付额" % word.word)
		return true
	var spaces: Array = request.cells
	if spaces.is_empty():
		_bubble.set_error("%s：没有可用落点" % word.word)
		return true
	var options: Array = []
	for card in cards:
		options.append({"text": "【%s】 · 额外使用 +1" % "".join(card.glyph_list())})
	options.append({"text": "取消"})
	var overlay := ChoiceOverlay.new()
	_solo_bag_picker_active = true
	overlay.setup({"title": "%s：选择原实体" % word.word, "body": "选好字和空格后支付%d铜钱，保留原有强化。" % BattleBalance.i("buy_cost", 2), "options": options, "scroll_options":true, "cancel_index":cards.size()})
	overlay.chose.connect(func(index):
		_solo_bag_picker_active = false
		if index < 0 or index >= cards.size():
			return
		_pending_path = path.duplicate()
		_word_transfer_target = {"bag_uid": cards[index].uid} if deploying else {"place_uid": cards[index].uid}
		_pick_only("throw_destination", spaces)
		_on_log("%s：选择落点，再点确认发动" % word.word))
	_mount_overlay(overlay)
	return true

func _choose_solo_bag(path: Array, target: Dictionary) -> bool:
	if target.has("bag_uid") or path.size() != 1 or not battle.board.valid_path(path):
		return false
	var source := battle.board.get_xy(path[0])
	if source == null or source.word_only or source.glyph_list().size() != 1 or source.data.solo_handler not in EffectRegistry.SOLO_BAG:
		return false
	var cards := battle.solo_bag_candidates(source)
	if cards.is_empty():
		return false
	var buying := source.data.solo_handler == "buy_bag_solo"
	var due := EffectUtil.discounted_cost(battle, BattleBalance.i("buy_cost", 2)) if buying else 0
	if buying and EffectUtil.available(battle) < due:
		_bubble.set_error("购：支付额不足（需要 %d 铜钱支付额）" % due)
		return true
	if not buying and cards.size() == 1:
		var chosen := target.duplicate()
		chosen["bag_uid"] = cards[0].uid
		chosen["bag_source_uid"] = source.uid
		_on_commit(path, chosen)
		return true
	var options: Array = []
	for card in cards:
		var traits: Array = []
		if card.gilded:
			traits.append("镀金")
		if card.temporary:
			traits.append("临时")
		if not card.pollutions.is_empty():
			traits.append("有污染")
		options.append({"text": "【%s】%s" % ["".join(card.glyph_list()), " · " + "、".join(traits) if not traits.is_empty() else ""]})
	options.append({"text": "取消"})
	_solo_bag_picker_active = true
	var overlay := ChoiceOverlay.new()
	overlay.setup({"title": "购：选择字袋实体" if buying else "精：二选一补入原格", "body": "确认时支付 %d，保留所选字的原属性。" % due if buying else "选一枚补入原格，另一枚留在字袋。", "options": options, "scroll_options":true, "cancel_index":cards.size()})
	overlay.chose.connect(func(index):
		_solo_bag_picker_active = false
		if index == cards.size():
			return
		if battle.board.get_xy(path[0]) != source:
			_bubble.set_error("选字：原字已离开所选格，请重新选择")
			return
		var chosen := target.duplicate()
		chosen["bag_uid"] = cards[index].uid
		chosen["bag_source_uid"] = source.uid
		_on_commit(path, chosen))
	_mount_overlay(overlay)
	return true

## 放有储能时选择释放或普通攻击；选择/取消前保留字块和资源。
func _choose_solo_release(path: Array, target: Dictionary) -> bool:
	if target.has("release_energy") or path.size() != 1 or battle.player.energy < BattleBalance.i("release_cost", 1) or not battle.board.valid_path(path):
		return false
	var inst := battle.board.get_xy(path[0])
	if inst == null or inst.word_only or inst.glyph_list().size() != 1 or inst.data.solo_handler != "solo_release":
		return false
	_solo_release_picker_active = true
	var overlay := ChoiceOverlay.new()
	overlay.setup({"title": "放：选择攻击方式", "body": "当前储能：%d" % battle.player.energy, "options": [
		{"text": "消耗 %d 储能，造成 %d 伤害" % [BattleBalance.i("release_cost", 1), BattleBalance.i("release_damage", 8)], "primary": true},
		{"text": "不消耗储能，造成 %d 伤害" % inst.data.solo_effects[0].amount},
		{"text": "取消"}]})
	overlay.chose.connect(func(index):
		_solo_release_picker_active = false
		if index == 2:
			return
		if battle.board.get_xy(path[0]) != inst:
			_bubble.set_error("放：原字已离开所选格，请重新选择")
			return
		var chosen := target.duplicate()
		chosen["release_energy"] = index == 0
		_on_commit(path, chosen))
	_mount_overlay(overlay)
	return true

## 复合（next_compound）：让玩家选定要保留为临时字的盘面字，选定前不结算。
func _choose_compound_copy(path: Array, target: Dictionary) -> bool:
	if target.has("compound_uid") or not battle.has_ability("next_compound") or not battle.board.valid_path(path):
		return false
	var word := EffectPreview.word_for(battle.board.glyphs_of(path), battle)
	if word == null or word.length() < BattleBalance.i("long_word_threshold", 3):
		return false
	var cards: Array = []
	var options: Array = []
	for pos in path:
		var inst: CharInstance = battle.board.get_xy(pos)
		if inst != null and not inst.pinned and inst.temporary_uses == 0:
			cards.append(inst)
			options.append({"text": "保留【%s】" % "".join(inst.glyph_list())})
	if cards.is_empty():
		return false
	_compound_picker_active = true
	var overlay := ChoiceOverlay.new()
	overlay.setup({"title": "复合：选择保留的临时字", "options": options})
	overlay.chose.connect(func(index):
		_compound_picker_active = false
		if index >= 0 and index < cards.size():
			var chosen := target.duplicate()
			chosen["compound_uid"] = cards[index].uid
			_on_commit(path, chosen))
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mount_overlay(overlay)
	return true


func _run_three_tiles(path: Array, word_name: String) -> void:
	var eligible := EffectTargets.recast_candidates(battle, path)
	if eligible.size() < BattleBalance.i("recast_target_count", 3):
		_bubble.set_error("%s：需要三个施词以外的非固定字" % word_name)
		return
	_pending_path = path
	_recast_three_active = true
	_recast_three_cells = []
	_three_tiles_word = word_name
	_board_view.begin_pick("three", true, path)
	_on_log("%s：选择三个不同的非固定字，点清除可重新选择" % word_name)
	_update_input()


func _run_collect_own(path: Array, junk := false) -> void:
	_pending_path = path
	_collect_own_active = true
	_collect_junk = junk
	_collect_own_cells = []
	if junk:
		var excluded := path.duplicate()
		for i in battle.board.cells.size():
			if not BattleState.is_refinable_junk(battle.board.cells[i]):
				excluded.append(battle.board.to_xy(i))
		_board_view.begin_pick("any", true, excluded)
	else:
		_board_view.begin_pick("any", true)
	_on_log("分流：选择至多两枚杂字移出，点「发动」确认" if junk else "收心：点选盘面字放回字袋（可 0 张，再点取消），点「发动」结束")
	_update_input()


func _run_merge_flow(path: Array) -> void:
	if not battle.has_adjacent_empty_pair():
		_bubble.set_error("合流需要盘面已有两个相邻空格。请先腾出位置；本次未消耗所选字。")
		return
	var preparation := battle.prepare_interaction(path)
	var revealed: Array = preparation.get("cards", [])
	if revealed.is_empty():
		_on_log(str(preparation.get("reason", "合流：没有可揭示的字")))
		return
	_pending_path = path
	_merge_active = true
	_merge_bag_uid = revealed[0].uid
	_merge_discard_uid = -1
	_merge_cell1 = Vector2i(-1, -1)
	var list := battle.discard_instances()
	if list.is_empty():
		_abort_merge()
		_bubble.set_error("合流：揭示后弃字堆没有可选字。请先积累弃字，再尝试；所选字未消耗。")
		return
	var options: Array = []
	for d in list:
		options.append({"text": "【%s】" % d["glyph"]})
	options.append({"text": "取消（不消耗字）"})
	var ov := ChoiceOverlay.new()
	ov.setup({"title": "合流 · 1/3 选择弃字", "body": "已揭示【%s】。再选1枚弃字，依次点两个相邻空格，最后点「发动」。" % revealed[0].glyph(), "options": options, "board_peek": true})
	ov.chose.connect(_on_merge_discard_chosen.bind(list))
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mount_overlay(ov)


func _on_merge_discard_chosen(index: int, list: Array) -> void:
	if index < 0 or index >= list.size():
		_abort_merge()
		_bubble.set_text("合流", "已取消，所选字未消耗，揭示字已放回。", SpeechBubble.State.PREVIEW)
		return
	_merge_discard_uid = int(list[index]["uid"])
	_board_view.begin_pick("empty")
	_pick_prompt(_pending_path, "合流 · 2/3：点第一个空格，再点与它四邻相接的第二个空格。选好后点「发动」。")
	_on_log("合流：选择第一个空格")


func _abort_merge() -> void:
	if not battle.pending_reveal.is_empty():
		battle.return_pending_reveal()
	_merge_active = false
	_merge_cell1 = Vector2i(-1, -1)
	_pending_path = []


# ---------------------------------------------------------------- 转化（揭示 5 选 1 再定点改造）
func _run_transform(path: Array) -> void:
	_pending_path = path
	var preparation := battle.prepare_interaction(path)
	var revealed: Array = preparation.get("cards", [])
	if revealed.is_empty():
		_pending_path = []
		_on_log(str(preparation.get("reason", "转化：没有可揭示的字")))
		return
	var options: Array = []
	for inst in revealed:
		options.append({"text": "【%s】" % inst.glyph()})
	options.append({"text": "取消（把揭示的字放回）"})
	var overlay := ChoiceOverlay.new()
	overlay.setup({"title": "转化：从揭示的 %d 枚中选择 1 枚" % revealed.size(), "options": options})
	overlay.chose.connect(_on_transform_chosen)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mount_overlay(overlay)


func _on_transform_chosen(index: int) -> void:
	if index < 0 or index >= battle.pending_reveal.size():
		battle.return_pending_reveal()
		_pending_path = []
		return
	_transform_uid = battle.pending_reveal[index].uid
	_board_view.begin_pick("any")


func _open_glyph_picker(path: Array, key: String, glyph_counts: Dictionary, title: String) -> void:
	_pending_path = path
	var chars: Array = []
	var counts: Dictionary = {}
	for g in glyph_counts.keys():
		var cd: CharacterData = Database.get_character_by_glyph(g)
		if cd == null:
			continue
		chars.append(cd)
		counts[cd.id] = glyph_counts[g]
	if chars.is_empty():
		_pending_path = []
		_on_log("没有可选的牌")
		return
	var overlay := CollectionOverlay.new()
	overlay.setup({"title": title, "characters": chars, "counts": counts, "pick_on_click": true})
	overlay.picked.connect(_on_glyph_chosen.bind(key))
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mount_overlay(overlay)


func _on_glyph_chosen(cd: CharacterData, key: String) -> void:
	var path := _pending_path
	_pending_path = []
	if path.is_empty() or cd == null:
		return
	var t: Dictionary = {}
	t[key] = cd.glyph
	_on_commit(path, t)


func _choose_discard() -> void:
	var options: Array = []
	for inst in battle.consumed_this_turn:
		options.append({"text": "【%s】" % inst.glyph()})
	if options.is_empty():
		options.append({"text": "（本回合没有消耗过的字）", "disabled": true})
	var overlay := ChoiceOverlay.new()
	overlay.setup({"title": "回收：选择本回合消耗过的一枚字", "options": options})
	overlay.chose.connect(_on_discard_chosen)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mount_overlay(overlay)


func _on_discard_chosen(index: int) -> void:
	var path := _pending_path
	_pending_path = []
	if path.is_empty():
		return
	if index < 0 or index >= battle.consumed_this_turn.size():
		return
	_on_commit(path, {"discard_uid": battle.consumed_this_turn[index].uid})


func _on_end_turn(from_effect: bool = false) -> void:
	# 强制结束来自正在结算的出字，不应被该出字自身的 busy 状态挡住。
	if _finished or (_busy and not from_effect) or _modal_count > 0:
		return
	if _board_view.pick_mode != "" or not _ready_action.is_empty() or not battle.pending_reveal.is_empty():
		_board_view.end_pick()
		_on_pick_cancelled()
	_board_view.clear_selection()
	_set_busy(true)
	_events.clear()
	_collecting = true
	_active_fx_profile = GlyphVfxProfile.for_glyph("污")
	battle.end_player_turn()
	_collecting = false
	if not await _replay_feedback():
		return
	_refresh_all(true)
	if not battle.is_over():
		_bubble.set_text("你的回合", "新字已落盘，继续连词。", SpeechBubble.State.IDLE)
		_bubble.set_context(_tutorial_hint() if _first_run_tutorial and _tutorial_step == 1 else _selection_context([]))
		_effects.number("回合 %d" % battle.turn, _effects.point_of(_board_view), Palette.INK_SOFT)
	if _first_run_tutorial and _tutorial_step == 1:
		_complete_first_run_tutorial()
	# 精心：本回合补字改由玩家从字袋定向选择（随机落地）
	if battle.manual_draw_pending > 0:
		_start_manual_draw()
		_set_busy(false)
		return
	_set_busy(false)
	_check_battle_over()


func _start_manual_draw() -> void:
	if _manual_draw_active or battle.manual_draw_pending <= 0:
		return
	_manual_draw_active = true
	_manual_draw_picks = []
	battle.ensure_bag()
	_show_manual_draw_pick(1)


func _manual_draw_counts() -> Dictionary:
	var counts: Dictionary = {}
	for inst in battle.bag:
		var g: String = inst.glyph()
		counts[g] = int(counts.get(g, 0)) + 1
	for g in _manual_draw_picks:
		var remaining: int = int(counts.get(g, 0)) - 1
		if remaining > 0:
			counts[g] = remaining
		else:
			counts.erase(g)
	return counts


func _show_manual_draw_pick(n: int) -> void:
	var total: int = mini(battle.manual_draw_pending, battle.board.free_count())
	if n > total:
		_finish_manual_draw()
		return
	var counts := _manual_draw_counts()
	var glyphs: Array = counts.keys()
	if glyphs.is_empty():
		_finish_manual_draw()
		return
	var options: Array = []
	for g in glyphs:
		options.append({"text": "【%s】×%d" % [g, counts[g]]})
	options.append({"text": "（剩下随机补）"})
	var ov := ChoiceOverlay.new()
	ov.setup({"title": "精心：从字袋选第 %d/%d 枚（随机落地）" % [n, total], "options": options})
	ov.chose.connect(_on_manual_draw_chosen.bind(glyphs, n))
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mount_overlay(ov)


func _on_manual_draw_chosen(index: int, glyphs: Array, n: int) -> void:
	if not _manual_draw_active or n != _manual_draw_picks.size() + 1:
		return
	if index < 0 or index >= glyphs.size():
		_finish_manual_draw()
		return
	if int(_manual_draw_counts().get(glyphs[index], 0)) <= 0:
		_show_manual_draw_pick(n)
		return
	_manual_draw_picks.append(glyphs[index])
	_show_manual_draw_pick(n + 1)


func _finish_manual_draw() -> void:
	if not _manual_draw_active:
		return
	_manual_draw_active = false
	battle.place_manual_draw(_manual_draw_picks)
	_manual_draw_picks = []
	_refresh_all()
	_check_battle_over()


func _check_battle_over() -> void:
	if _finished:
		return
	if battle.is_over():
		if _first_run_tutorial:
			_complete_first_run_tutorial()
		_finished = true
		_update_input()
		var victory := battle.is_victory()
		if battle.achievement != null: battle.achievement.finish(victory)
		if not victory: Achievements.finish_run(false)
		GameState.player_hp = battle.player.hp
		EventBus.hp_changed.emit(GameState.player_hp, GameState.player_max_hp)
		if victory:
			GameState.add_captured(battle.captured_chars)

			GameState.settle_victory_economy()
			Relics.on_battle_won()
		var settlement := {}
		if not victory:
			settlement = RunSettlement.from_run(battle, node, GameState.expedition if _expedition else null, bool(params.get("elite", false)))
		if _room_run: GameState.room_run.finish_live_battle(victory)
		var ex_result := {}
		if _expedition:
			ex_result = GameState.expedition.finish_battle(victory)
		var final_victory: bool = victory and ((_room_run and GameState.room_run.phase == "victory")
			or (_expedition and GameState.expedition.over and GameState.expedition.won)
			or (not _room_run and not _expedition and node != null and node.type == MapNodeData.Type.BOSS and GameState.act_index >= 3))
		if final_victory and not _room_run and not _expedition:
			GameState.complete_current_node()
		if not await _wait_step(0.35):
			return
		if final_victory:
			_show_run_result(true)
		elif victory and _room_run:
			if GameState.room_run.phase=="reward": goto("res://src/screens/reward_screen.gd", {"node": node, "room_run": true})
			else: goto("res://src/screens/room_map_screen.gd")
		elif victory and _expedition and ex_result.get("reward", false):
			# 战后按现有字袋提供三选一奖励，选中的字直接收入字袋。
			goto("res://src/screens/reward_screen.gd", {"node": node, "expedition": true, "count": ex_result.count})
		elif victory and _expedition:
			goto("res://src/screens/expedition_map_screen.gd")
		elif victory:
			goto("res://src/screens/reward_screen.gd", {"node": node})
		else:
			_show_run_result(false)


func _show_run_result(victory: bool) -> void:
	goto("res://src/screens/run_result_screen.gd", {
		"victory":victory, "location":node.title if node != null else "",
		"enemies":" / ".join(battle.enemies.map(func(enemy): return enemy.display_name)),
		"turn":battle.turn})


func _preview_hint() -> String:
	if Settings.drag_release_play:
		return "拖动连线，松手即出字；也可按「出字」或回车确认。"
	return "拖动选择后松手保留；按「出字」或回车 / 空格确认，ESC 取消。"


func _tutorial_hint() -> String:
	if _tutorial_step == 0:
		return "第一局引导 · 沿相邻字块连线组成词语，选好后点「出字」。"
	return "观察敌人头像旁的意图，再结束回合；防御可以抵挡攻击。"


func can_skip_first_run_tutorial() -> bool:
	return _first_run_tutorial and not _finished


func skip_first_run_tutorial() -> void:
	if not can_skip_first_run_tutorial():
		return
	_complete_first_run_tutorial()
	_bubble.set_idle(_preview_hint())
	SaveManager.request_save()


func _complete_first_run_tutorial() -> void:
	_first_run_tutorial = false
	_tutorial_step = 0
	GameState.first_run_tutorial = false
	Settings.complete_first_run_tutorial()
	SaveManager.request_save()


func _pop_confirm() -> void:
	if _confirm_btn == null or _confirm_btn.disabled or Settings.reduced_motion:
		return
	if _confirm_motion != null:
		_confirm_motion.kill()
	_confirm_btn.pivot_offset = _confirm_btn.size * 0.5
	_confirm_motion = create_tween()
	_confirm_motion.tween_property(_confirm_btn, "scale", Vector2(1.025, 1.025), 0.06)
	_confirm_motion.tween_property(_confirm_btn, "scale", Vector2.ONE, 0.10)


func _open_gild_picker(path: Array) -> void:
	var cards: Array = GameState.deck.filter(func(c): return not c.gilded and c.is_player_owned() and not c.temporary)
	if cards.is_empty():
		_bubble.set_error("字袋中没有尚未镀金的实体字。")
		return
	var options: Array = []
	for card in cards:
		options.append({"text": "【%s】 · 第%d枚" % [card.glyph(), options.size() + 1]})
	options.append({"text": "取消"})
	var overlay := ChoiceOverlay.new()
	overlay.setup({"title": "选择1字永久镀金", "body": "此字每次打出获得%d铜钱，组词也算；不影响同字的其他字块。" % BattleBalance.i("gild_gold", 1), "options": options})
	overlay.chose.connect(func(index):
		if index >= cards.size(): return
		_on_commit(path, {"gild_uid": cards[index].uid}))
	_mount_overlay(overlay)


func _open_deck() -> void:
	var counts := GameState.glyph_counts()
	var chars: Array = []
	for id in counts.keys():
		var cd: CharacterData = Database.get_character_by_glyph(id)
		if cd != null:
			chars.append(cd)
	var overlay := CollectionOverlay.new()
	overlay.setup({
		"title": "字袋", "instances": GameState.deck,
		"subtitle": "字袋共%d字" % GameState.deck_size(),
		"characters": chars,
		"counts": counts,
		"words": Database.words.values(),
	})
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mount_overlay(overlay)

func _layout() -> void:
	if _end_btn == null or size.x < 100:
		return
	var w := content.size.x
	var h := content.size.y
	# A touchscreen Windows laptop still has desktop space and mouse/keyboard.
	# Choose the mobile composition by platform/explicit preview and size budget.
	var touch_device := OS.has_feature("android") or OS.has_feature("ios") or bool(params.get("touch_layout", false))
	var illustrated_desktop := (Palette.STYLE_ID == "taopunk" and w >= 1100
		and get_window().size.y > 540 and not touch_device)
	_compact = (touch_device
		or w / maxf(1.0, h) >= 1.95 or w < 1100 or get_window().size.y <= 540
		or Palette.STYLE_ID == "taopunk")
	var ui_scale := BattleTouchLayout.unit_for(size, get_window().size) if _compact else 1.0
	if Palette.STYLE_ID == "taopunk" and get_window().size.y > 540:
		ui_scale = maxf(1.2, ui_scale)
	var touch := BattleTouchLayout.measure(content.size, ui_scale, not _player_status.entries.is_empty()) if _compact else {}
	if illustrated_desktop:
		touch = TaopunkBattleLayout.measure(content.size, not _player_status.entries.is_empty())
		# 既有紧凑组件保留行为；桌面采用定稿自己的字号和构图比例。
		ui_scale = touch.scale * 1.55
	var margin := 24.0
	var top := 88.0 if not _compact else maxf(66.0, 54 * ui_scale)
	var footer := maxf(70.0, 48 * ui_scale + 22)
	var action_h := 48.0 * ui_scale
	var side := minf(h - top - footer - action_h - 22, w * 0.44)
	var column := (w - side) * 0.5 - margin * 2
	var board_x := (w - side) * 0.5
	if _compact:
		side = touch.board.size.x
		board_x = touch.board.position.x
		column = touch.column
	_topbar.position = Vector2(margin, 12)
	_topbar.size = Vector2(w - margin * 2, top - 12)
	if _compact:
		_topbar.position = touch.topbar.position
		_topbar.size = touch.topbar.size
	_topbar.get_node("Title").hide()
	_topbar.get_node("Title").position = Vector2(320, 0)
	_topbar.get_node("Title").size = Vector2(150, 36)
	_turn_label.position = Vector2((w - margin * 2) * 0.5 - 60, 48 * ui_scale if not _compact else 4)
	_turn_label.size = Vector2(120, 24 * ui_scale)
	_turn_label.show()
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_turn_label.clip_text = true
	_turn_label.add_theme_font_size_override("font_size", int(15 * ui_scale))
	var menu_width := 80 * ui_scale
	_menu_btn.position = Vector2(_topbar.size.x - menu_width, 0)
	_menu_btn.custom_minimum_size = Vector2(menu_width, 48 * ui_scale)
	_menu_btn.size = _menu_btn.custom_minimum_size
	_menu_btn.add_theme_font_size_override("font_size", int(minf(34, 20 * ui_scale)))
	_gold_strip.set_ui_scale(ui_scale, _compact and _gold_strip.entries.size() > 1)
	var gold_width := _gold_strip.get_combined_minimum_size().x
	_gold_strip.position = Vector2(_menu_btn.position.x - gold_width - (8 * ui_scale if _compact else 28), 0)
	_gold_strip.size = Vector2(gold_width, 48 * ui_scale)
	if _compact:
		var turn_x := maxf(board_x, touch.player.end.x + 6 * ui_scale) - _topbar.position.x
		_turn_label.position = Vector2(turn_x, 0)
		_turn_label.size = Vector2(maxf(0, minf(80 * ui_scale, _gold_strip.position.x - turn_x - 6 * ui_scale)), 48 * ui_scale)
		_turn_label.visible = _turn_label.size.x >= 48 * ui_scale
	_topbar.get_node("Rule").position = Vector2(0, _topbar.size.y - 1)
	_topbar.get_node("Rule").size = Vector2(_topbar.size.x, 1)
	_board_view.position = Vector2(board_x, top + 12)
	_board_view.size = Vector2(side, side)
	var right_x := board_x + side + margin
	if _compact:
		_board_view.position = touch.board.position
		_player_panel.position = touch.player.position
		_player_panel.size = touch.player.size
		_enemy_panel.position = touch.enemy.position
		_enemy_panel.size = touch.enemy.size
		_preview_panel.position = touch.preview.position
		_preview_panel.size = touch.preview.size
		_end_btn.position = touch.end.position
		_end_btn.size = touch.end.size
	else:
		_player_panel.position = Vector2(margin + 8, 12)
		_player_panel.size = Vector2(460, 76)
		_enemy_panel.position = Vector2(right_x, top + 12)
		_enemy_panel.size = Vector2(column, side)
		_preview_panel.position = Vector2(margin, top + 46)
		_preview_panel.size = Vector2(column, side - 48)
		_end_btn.position = Vector2(w - margin - 196, h - 60)
		_end_btn.size = Vector2(196, 48)
	var shield_cell := (48.0 if _compact else 40.0) * ui_scale
	_player_defense.set_cell_size(shield_cell)
	var defense_width := _player_defense.display_width()
	_player_defense.position = Vector2(0, (48 * ui_scale - shield_cell) * 0.5)
	_player_defense.size = Vector2(defense_width, shield_cell)
	var hp_x := maxf(0, defense_width - 3 * ui_scale)
	_player_hp.position = Vector2(hp_x, 8 * ui_scale)
	_player_hp.custom_minimum_size.y = 0
	_player_hp.size = Vector2(_player_panel.size.x - hp_x if _compact else 220, 32 * ui_scale)
	_hp_icon.position = _player_hp.position + Vector2(8, 6) * ui_scale
	_hp_icon.size = Vector2.ONE * 20 * ui_scale
	_hp_icon.ink = Palette.PAPER
	_player_hp_value.position = Vector2(_player_hp.position.x + 34 * ui_scale, 0)
	_player_hp_value.size = Vector2(_player_hp.size.x - 42 * ui_scale, 48 * ui_scale)
	_player_hp_value.add_theme_color_override("font_color", Palette.PAPER)
	var hp_font := int(27 * ui_scale)
	_player_hp_value.add_theme_font_size_override("font_size", hp_font)
	while _player_hp_value.get_combined_minimum_size().x > _player_hp_value.size.x and hp_font > int(18 * ui_scale):
		hp_font -= 1
		_player_hp_value.add_theme_font_size_override("font_size", hp_font)
	var status_x := _player_hp.position.x + _player_hp.size.x + 24
	# 桌面绘卷的状态行只有 48 * unit 高，不能沿用手机组件的放大比例。
	var status_scale: float = touch.scale * 4.0 / 3.0 if illustrated_desktop else ui_scale * (4.0 / 3.0 if _compact else 1.0)
	_player_status.set_ui_scale(status_scale)
	_player_status.position = touch.status.position - _player_panel.position if _compact else Vector2(status_x, 6)
	_player_status.size = touch.status.size if _compact else Vector2(maxf(36, _topbar.position.x + _gold_strip.position.x - _player_panel.position.x - status_x - 24), 36 * ui_scale)
	_player_status.visible = not _player_status.entries.is_empty()
	_bubble.illustrated_scale = touch.scale if illustrated_desktop else 0.0
	_bubble.set_ui_scale(ui_scale, _compact and not illustrated_desktop)
	var paper_pad := 22.0 * ui_scale if _compact else 26.0
	var paper_height := _preview_panel.size.y
	_bubble.position = Vector2(paper_pad, paper_pad)
	_bubble.size = Vector2(column - paper_pad * 2, paper_height - paper_pad * 2)
	_selection_actions.position = Vector2(board_x + side * 0.12, _board_view.position.y + side + 10)
	_selection_actions.size = Vector2(side * 0.76, action_h)
	if _compact:
		_selection_actions.position = touch.actions.position
		_selection_actions.size = touch.actions.size
	_confirm_btn.custom_minimum_size.x = 0
	_clear_btn.custom_minimum_size.x = 64 * ui_scale
	_confirm_btn.custom_minimum_size.y = action_h
	_clear_btn.custom_minimum_size.y = action_h
	_confirm_btn.add_theme_font_size_override("font_size", int(minf(36, 24 * ui_scale)))
	_clear_btn.add_theme_font_size_override("font_size", int(18 * ui_scale))
	_end_btn.add_theme_font_size_override("font_size", int(22 * ui_scale))
	_footer.position = Vector2(margin, h - footer + 10)
	_footer.size = Vector2(w - margin * 2, footer - 10)
	if _compact:
		_footer.position = touch.footer.position
		_footer.size = touch.footer.size
	_footer.get_node("Rule").visible = not _compact
	_footer.get_node("Rule").size = Vector2(w - margin * 2, 1)
	_hint.visible = not _compact
	_hint.position = Vector2(8, 6)
	_hint.size = Vector2(w - 260, 22)
	_pile_label.set_ui_scale(ui_scale, true)
	_pile_label.position = Vector2(8, 30) if not _compact else Vector2(6 * ui_scale, 0)
	_pile_label.size = Vector2(_pile_label.get_combined_minimum_size().x, (48 if _compact else 24) * ui_scale)
	_enemy_paper.position = _enemy_panel.position - Vector2(12, 8)
	_enemy_paper.size = _enemy_panel.size + Vector2(24, 16)
	_enemy_paper.open_scene = _enemy_widgets.size() == 1
	_enemy_panel.position += Vector2(14, 0 if _compact else 16)
	_enemy_panel.size -= Vector2(28, 0 if _compact else 32)
	if Palette.STYLE_ID == "taopunk" and not illustrated_desktop:
		_enemy_panel.position += Vector2(14, 10) * ui_scale
		_enemy_panel.size -= Vector2(28, 10) * ui_scale
	for widget in _enemy_widgets:
		widget.illustrated_scale = 0.0
		widget.ui_scale = ui_scale
		widget.show_compact_portrait = _compact and _enemy_widgets.size() == 1
		widget.set_compact(_compact or _enemy_widgets.size() > 1)
		if widget.show_compact_portrait:
			# ScrollContainer 按整数分配空间，避免取整差产生一条无内容可滚的滚动条。
			widget.custom_minimum_size.y = floorf(_enemy_panel.size.y) - 1
		else:
			widget.custom_minimum_size.y = 156 * ui_scale if _compact or _enemy_widgets.size() > 1 else _enemy_panel.size.y
	_board_view._layout()
	if Palette.STYLE_ID == "taopunk":
		_board_view._presentation.set_illustrated_framing(illustrated_desktop)
	if illustrated_desktop:
		_layout_illustrated_desktop(touch)
	_reserve_status_space()
	if _effects != null:
		_effects.set_ui_scale(ui_scale)


func _reserve_status_space() -> void:
	if not _player_status.visible: return
	# Container minimum sizes can exceed the nominal row after DPI/font scaling.
	_player_status.size.y = maxf(_player_status.size.y, _player_status.get_combined_minimum_size().y)
	var occupied := _player_status.get_global_rect().grow(6.0)
	var preview := _preview_panel.get_global_rect()
	if not occupied.intersects(preview): return
	var shift := maxf(0, occupied.end.y - preview.position.y)
	_preview_panel.position.y += shift
	_preview_panel.size.y = maxf(0, _preview_panel.size.y - shift)
	_bubble.size = (_preview_panel.size - _bubble.position * 2).max(Vector2.ZERO)


func _update_input() -> void:
	var locked := _busy or _finished or _modal_count > 0
	_board_view.set_interactable(not locked, false)
	if _recast_three_active:
		_confirm_btn.text = "%s（%d/%d）" % [_three_tiles_word, _recast_three_cells.size(), BattleBalance.i("recast_target_count", 3)]
		_confirm_btn.disabled = true
	elif _collect_own_active:
		_confirm_btn.text = "发动（%s %d）" % ["分流" if _collect_junk else "收心", _collect_own_cells.size()]
		_confirm_btn.disabled = locked
	elif battle.formation_mode and not battle.formation_queue.is_empty() and _board_view.path.is_empty():
		_confirm_btn.text = "发动结阵（%d）" % battle.formation_queue.size()
		_confirm_btn.disabled = locked
	elif not _ready_action.is_empty():
		if _ready_action.get("repeat_rotate", false):
			_confirm_btn.text = "发动（转速 %d/%d）" % [battle.repeat_rotate_count, BattleBalance.i("rotate_limit", 3)]
		else:
			_confirm_btn.text = "发动"
		_confirm_btn.disabled = locked
	elif _board_view.pick_mode != "":
		_confirm_btn.text = "发动"
		_confirm_btn.disabled = true
	else:
		_confirm_btn.text = "出字"
		_confirm_btn.disabled = locked or _board_view.path.is_empty()
	if _confirm_ink != null:
		_confirm_ink.set_shader_parameter("disabled", _confirm_btn.disabled)
	_clear_btn.disabled = locked or (_board_view.path.is_empty() and _ready_action.is_empty() and not _recast_three_active and not _collect_own_active and _board_view.pick_mode == "")
	_end_btn.disabled = locked
	_menu_btn.disabled = locked
	if _board_view.pick_mode != "":
		_board_view._apply_pick_highlight()


func _set_busy(value: bool) -> void:
	_busy = value
	_update_input()
	if not value: SaveManager.request_save()


func _mount_overlay(overlay: Control) -> void:
	# 部件立绘含多级相对 z_index；模态遮罩和内容必须整体高于战斗绘制。
	overlay.z_index = 100
	_modal_count += 1
	_update_input()
	overlay.tree_exited.connect(func():
		_modal_count = maxi(0, _modal_count - 1)
		if is_inside_tree():
			_update_input()
			SaveManager.request_save())
	add_child(overlay)


func _open_menu() -> void:
	if _busy:
		return
	PauseMenu.open()


func _toggle_log() -> void:
	if _busy:
		return
	_log_overlay.visible = not _log_overlay.visible
	if _log_overlay.visible: _queue_log_refresh()
	_modal_count += 1 if _log_overlay.visible else -1
	_update_input()


func _inspect_tile(pos: Vector2i) -> void:
	if _bubble.frame_details == null or battle == null: return
	var inst := battle.board.get_xy(pos)
	var lines: Array[String] = ["当前字 · 第%d行%d列" % [pos.y + 1, pos.x + 1]]
	var entries := {}
	if inst != null:
		lines[0] += "【%s】" % "".join(inst.glyph_list())
		if inst.gilded: lines.append("镀金")
		if inst.temporary: lines.append("临时字")
		if inst.word_only: lines.append("仅供组词")
		if inst.is_fused(): lines.append("融合")
		if inst.temporary_uses > 0:
			var label := "额外使用×%d" % inst.temporary_uses
			lines.append(label)
			entries["tile:layers"] = {"title": "额外使用", "label": label, "text": EffectGlossary.entry("term:extra_use").text + "剩余%d次。" % inst.temporary_uses}
		if inst.refined: lines.append("精炼效果")
		if inst.pinned:
			var label := "固定 · 已用" if inst.pinned_exhausted else "固定 · 可用"
			lines.append(label)
			entries["tile:pinned"] = {"title": "固定", "label": label, "text": EffectGlossary.entry("term:pinned").text + ("本回合已用，下回合恢复。" if inst.pinned_exhausted else "本回合仍可使用。")}
		for pid in inst.pollutions:
			var pd := Database.get_pollution(pid)
			if pd == null: continue
			var label := pd.name + "污染"
			lines.append(label)
			var description := EnemyBalance.pollution_description(pd, inst.statuses) if pid == "replicate" and inst.is_enemy_owned() else pd.description
			entries["pollution:" + str(pid)] = {"title": label, "text": description}
		for sid in inst.statuses:
			var sd := Database.get_status(str(sid))
			if sd != null: lines.append(sd.name + "状态")
	for mark in EnemyMechanics.markers(battle):
		if mark.cell == pos:
			var label := "%s · %s" % [mark.name, mark.source]
			lines.append(label)
			entries["tile:mark:%d" % entries.size()] = {"title": label, "text": mark.description}
	var has_effect := lines.size() > 1
	_bubble.frame_details.set_effect_text("\n".join(lines) if has_effect else "", 0, null, entries)
	_bubble.frame_details.visible = has_effect


func _selection_context(_path: Array) -> String:
	var hints: Array[String] = []
	if battle.board.gap_steps_allowed > 0:
		hints.append("超：下次组词可跨一个横／竖空格。")
	if battle.board.free_word_link:
		hints.append("流利：下次组词可按字序点击任意位置，无需相邻。")
	return "\n".join(hints)


func _watch_combatant(combatant: Combatant) -> void:
	for watch in _feedback_watches:
		if watch[0] == combatant:
			return
	var listener := _on_feedback.bind(combatant)
	combatant.feedback.connect(listener)
	_feedback_watches.append([combatant, listener])


func _on_feedback(event: Dictionary, target: Combatant) -> void:
	if not _collecting:
		return
	var captured := event.duplicate(true)
	captured["target"] = target
	captured["profile"] = _active_fx_profile if not _active_fx_profile.is_empty() else GlyphVfxProfile.for_glyph("")
	# 连续结阵或前置伤害改变存活列表时，图标的终点跟随真实结算对象。
	if not target.is_player and (event.kind == "damage" or (event.kind == "shield" and int(event.get("gain", 0)) < 0)):
		for index in range(_events.size() - 1, -1, -1):
			if _events[index].kind == "cast":
				if _events[index].get("actual_target", false):
					break
				var view: Control = _view_for(target)
				if view is EnemyView:
					_events[index].destination = _effects.get_global_transform().affine_inverse() * view.impact_point()
					_events[index]["actual_target"] = true
				break
	_events.append(captured)


func _on_play_resolving(play: Dictionary) -> void:
	if not _collecting:
		return
	_active_fx_profile = GlyphVfxProfile.for_play(play.glyphs, play.word, play.effects)
	var source := Vector2.ZERO
	for cell in play.path:
		source += _effects.point_of(_board_view.tiles[battle.board.from_xy(cell)])
	source /= maxf(1, play.path.size())
	_events.append({"kind": "cast", "profile": _active_fx_profile, "source": source, "destination": _cast_destination(_active_fx_profile, play),
		"play": {"path": play.path.duplicate(), "target": play.target.duplicate(), "effects": play.effects}})


func _cast_destination(profile: Dictionary, play: Dictionary) -> Vector2:
	match profile.focus:
		"enemy":
			var alive_index := int(play.target.get("target_index", 0))
			var alive := battle.alive_enemies()
			if alive_index >= 0 and alive_index < alive.size():
				var view: Control = _view_for(alive[alive_index])
				if view is EnemyView:
					return _effects.get_global_transform().affine_inverse() * view.impact_point()
		"shield": return _defense_point("block")
		"heal": return _effects.point_of(_player_hp_value)
		"energy", "heat": return _status_point(profile.focus)
		"gold": return _effects.point_of(_gold_strip.item_for(profile.focus))
		"board": return _board_effect_point(play)
	return _effects.point_of(_player_status)


func _status_point(id: String) -> Vector2:
	return _effects.get_global_transform().affine_inverse() * _player_status.anchor_for(id)


func _defense_point(id: String) -> Vector2:
	var badge := _player_defense.badge_for(id)
	return _effects.point_of(badge) if badge.visible else _effects.get_global_transform().affine_inverse() * (_player_hp.global_position + Vector2(0, _player_hp.size.y * 0.5))


func _board_effect_point(play: Dictionary, span_override := 0) -> Vector2:
	var target: Dictionary = play.get("target", {})
	var cells: Array = []
	var span := span_override if span_override > 0 else 1
	for effect in play.get("effects", []):
		if effect.target == EffectData.Target.BOARD_2X2: span = 2
		elif effect.target == EffectData.Target.BOARD_3X3: span = 3
	if target.has("tile"):
		for y in span:
			for x in span:
				var cell: Vector2i = target.tile + Vector2i(x, y)
				if battle.board.in_bounds(cell.x, cell.y): cells.append(cell)
	elif target.has("row"):
		for x in 4: cells.append(Vector2i(x, int(target.row)))
	else:
		cells = play.get("path", [])
	if cells.is_empty():
		return _effects.point_of(_board_view)
	var point := Vector2.ZERO
	for cell in cells:
		point += _effects.point_of(_board_view.tiles[battle.board.from_xy(cell)])
	return point / cells.size()


func _on_enemy_acting(enemy: Combatant, move: EnemyMoveData) -> void:
	if _collecting:
		_finish_enemy_action_capture()
		_active_fx_profile = GlyphVfxProfile.for_glyph("")
		_pending_enemy_action = {"kind": "enemy_action", "target": enemy, "move": move,
			"before": EnemyActionCapture.board_snapshot(battle.board)}
		_events.append(_pending_enemy_action)


func _view_for(target: Combatant) -> Control:
	if target.is_player:
		return _player_panel
	var index := battle.enemies.find(target)
	return _enemy_widgets[index] if index >= 0 and index < _enemy_widgets.size() else _preview_panel


func _replay_feedback() -> bool:
	_finish_enemy_action_capture()
	for event in _events:
		if event.kind == "cast":
			var destination: Vector2 = event.destination
			if not event.get("actual_target", false):
				destination = _cast_destination(event.profile, event.play)
			_effects.cast(event.profile, event.source, destination)
			if not await _wait_step(0.20 if not Settings.reduced_motion else 0.01):
				return false
			continue
		var view := _view_for(event.target)
		if event.kind == "enemy_action":
			var move: EnemyMoveData = event.move
			_bubble.set_text(event.target.display_name, "使用「%s」。" % move.title, SpeechBubble.State.PREVIEW)
			if not await _replay_enemy_action(view, event): return false
			continue
		var strike_timing: Dictionary = {}
		if event.kind == "damage" and not _enemy_attack_context.is_empty() and int(_enemy_attack_context.remaining) > 0:
			strike_timing = await _replay_enemy_strike(event)
			if _exiting: return false
		var point := _effects.point_of(view)
		var profile: Dictionary = event.get("profile", GlyphVfxProfile.for_glyph(""))
		var radius := 16.0 if event.target.is_player else 42.0
		var shield_id := "persistent_block" if event.has("persistent_block") and int(event.persistent_block) != _player_defense.persistent_block else "block"
		if event.target.is_player:
			point = _defense_point(shield_id) if event.kind == "shield" else _effects.point_of(_player_hp_value)
		if view is EnemyView:
			view.apply_feedback(event)
			point = _effects.get_global_transform().affine_inverse() * view.impact_point()
		else:
			if event.has("hp"):
				_show_player_hp(int(event.hp), int(event.max_hp))
			if event.has("block"):
				_show_defense(int(event.block), int(event.persistent_block))
				# HBoxContainer 下一帧完成排版；新出现的盾值要在实际图标旁反馈。
				await get_tree().process_frame
				if _exiting: return false
				if event.kind == "shield" and _player_defense.badge_for(shield_id).visible: point = _defense_point(shield_id)
		var number_point := point + Vector2(0, 62 if event.target.is_player else -26)
		match event.kind:
			"damage":
				var loss := int(event.hp_loss)
				var blocked := int(event.blocked)
				if loss > 0 or blocked > 0:
					_audio.play_cue("hit" if loss > 0 else "block")
					if loss + blocked >= 9:
						_effects.table_impact(3.5)
				if loss > 0:
					_effects.number("−%d" % loss, number_point, Palette.VERMILION_DK)
					_effects.glyph_impact(profile, point, radius)
				if blocked > 0:
					_effects.number("格挡 %d" % blocked, number_point + Vector2(0, 18), Palette.INK)
					_effects.glyph_impact(GlyphVfxProfile.feedback(profile, "shield"), point, radius)
				elif loss == 0:
					_effects.number("免疫", point, Palette.INK_SOFT)
			"shield":
				var gain := int(event.gain)
				_audio.play_cue("block")
				_effects.number("护盾 +%d" % gain if gain > 0 else ("破盾" if int(event.block) == 0 else "拆盾 %d" % -gain), point + Vector2(0, 32 if event.target.is_player else 0), Palette.INK if gain > 0 else Palette.VERMILION_DK)
				_effects.glyph_impact(GlyphVfxProfile.feedback(profile, "shield", gain), point, radius)
			"heal":
				_audio.play_cue("heal")
				_effects.number("+%d" % int(event.gain), number_point, Palette.INK)
				_effects.glyph_impact(GlyphVfxProfile.feedback(profile, "heal"), point, radius)
		if not await _wait_step(0.16 if not Settings.reduced_motion else 0.045):
			return false
		if not strike_timing.is_empty() and int(_enemy_attack_context.remaining) == 0 and not Settings.reduced_motion:
			var recovery: float = maxf(0.01, float(strike_timing.duration) - float(strike_timing.release) - 0.30)
			if not await _wait_step(recovery): return false
	_events.clear()
	_enemy_attack_context.clear()
	return true


func _wait_step(duration: float) -> bool:
	if _exiting:
		return false
	_step_timer.start(duration)
	await presentation_step_finished
	return not _exiting


func _resource_feedback(before: Array) -> void:
	var after := [battle.player.energy, battle.player.heat, GameState.gold]
	var ids := ["energy", "heat", "gold"]
	var played := _active_fx_profile.duplicate(true)
	# 等新数值控件完成排版，再在实际图标旁反馈，避免第一帧落在旧位置。
	await get_tree().process_frame
	if _exiting:
		return
	for i in mini(before.size(), after.size()):
		var change := int(after[i]) - int(before[i])
		if change != 0:
			var point := (_effects.point_of(_gold_strip.item_for(ids[i])) if i >= 2 else _status_point(ids[i])) + Vector2(0, 28)
			_effects.number("%+d" % change, point, Palette.GOLD_DK)
			var resource_glyph := "电" if i == 0 else ("冷" if i == 1 and change < 0 else ("火" if i == 1 else ("资" if i == 3 else "金")))
			var profile := GlyphVfxProfile.for_glyph(resource_glyph)
			if played.get("family", "") == profile.family:
				profile = played
			_effects.glyph_impact(profile, point, 16)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_echo() and event.is_action_pressed("confirm_word") and (not _ready_action.is_empty() or _collect_own_active or (battle.formation_mode and not battle.formation_queue.is_empty())):
		if not _busy and _modal_count == 0:
			_on_primary()
			get_viewport().set_input_as_handled()
	elif _log_overlay.visible and event.is_action_pressed("cancel_selection"):
		_toggle_log()
		get_viewport().set_input_as_handled()
	elif not event.is_echo() and event.is_action_pressed("end_turn"):
		_on_end_turn()
		get_viewport().set_input_as_handled()


func _gravity_in_play(result: Dictionary) -> bool:
	if battle.has_ability("gravity_always"):
		return true
	var effects: Array = result.word.effects if result.word != null else []
	if result.solo:
		var data := Database.get_character_by_glyph(str(result.glyphs[0]))
		if data != null:
			effects = data.solo_effects
	for effect in effects:
		if effect.handler in ["gravity", "gravity_left", "gravity_right", "gravity_damage"]:
			return true
	return false


func _layout_illustrated_desktop(layout: Dictionary) -> void:
	var unit: float = layout.scale
	_topbar.get_node("Rule").hide()
	_menu_btn.position = Vector2(_topbar.size.x - 140 * unit, 0)
	_menu_btn.custom_minimum_size = Vector2(140, 80) * unit
	_menu_btn.size = _menu_btn.custom_minimum_size
	_menu_btn.add_theme_font_size_override("font_size", int(34 * unit))
	_gold_strip.set_ui_scale(1.5 * unit, false)
	var gold_width := maxf(100 * unit, _gold_strip.get_combined_minimum_size().x)
	_gold_strip.position = Vector2(_menu_btn.position.x - gold_width - 8 * unit, 0)
	_gold_strip.size = Vector2(gold_width, 80 * unit)
	_turn_label.add_theme_font_size_override("font_size", int(30 * unit))
	var face := _turn_label.get_theme_font("font")
	var turn_width := maxf(100 * unit, face.get_string_size(_turn_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(30 * unit)).x + 12 * unit)
	_turn_label.position = Vector2(_gold_strip.position.x - 12 * unit - turn_width, 0)
	_turn_label.size = Vector2(turn_width, 80 * unit)
	_turn_label.show()
	_player_hp.position.y = 7 * unit
	_player_hp.size.y = 58 * unit
	_player_defense.position.y = _player_hp.position.y + (_player_hp.size.y - _player_defense.cell_size) * 0.5
	_hp_icon.position = _player_hp.position + Vector2(14, 15) * unit
	_hp_icon.size = Vector2.ONE * 30 * unit
	_player_hp_value.position = _player_hp.position + Vector2(58, -7) * unit
	_player_hp_value.size = Vector2(_player_hp.size.x - 66 * unit, 76 * unit)
	var hp_font := int(48 * unit)
	var hp_face := _player_hp_value.get_theme_font("font")
	while hp_font > int(18 * unit) and hp_face.get_string_size(_player_hp_value.text, HORIZONTAL_ALIGNMENT_LEFT, -1, hp_font).x > _player_hp_value.size.x:
		hp_font -= 1
	_player_hp_value.add_theme_font_size_override("font_size", hp_font)
	_player_status.position = layout.status.position - _player_panel.position
	# 从右向左预算菜单、铜钱、回合，剩余区域才用于 Buff。
	var status_end := minf(layout.status.end.x, _topbar.position.x + _turn_label.position.x - 12 * unit)
	_player_status.size = Vector2(maxf(0, status_end - layout.status.position.x), layout.status.size.y)
	var pad := Vector2(42, 24) * unit
	_bubble.position = pad
	_bubble.size = _preview_panel.size - pad * 2
	_bubble.set_ui_scale(1.28 * unit, false)
	_clear_btn.custom_minimum_size.x = 140 * unit
	for button in [_confirm_btn, _clear_btn, _end_btn]:
		button.custom_minimum_size.y = 86 * unit
		button.add_theme_font_size_override("font_size", int((40 if button != _clear_btn else 32) * unit))
	_selection_actions.add_theme_constant_override("separation", int(16 * unit))
	_selection_actions.size = layout.actions.size
	_end_btn.size = layout.end.size
	_pile_label.set_ui_scale(1.6 * unit, true)
	_pile_label.position = Vector2(24, 7) * unit
	_pile_label.size.y = 72 * unit
	_enemy_paper.position = layout.enemy.position - Vector2(18, 12) * unit
	_enemy_paper.size = layout.enemy.size + Vector2(36, 20) * unit
	_enemy_panel.position = layout.enemy.position + Vector2(24, 0) * unit
	_enemy_panel.size = layout.enemy.size - Vector2(48, 0) * unit
	for widget in _enemy_widgets:
		widget.illustrated_scale = unit if _enemy_widgets.size() == 1 else 0.0
		widget.custom_minimum_size.y = floorf(_enemy_panel.size.y) - 1 if _enemy_widgets.size() == 1 else 180 * unit
		widget._layout()




func _finish_enemy_action_capture() -> void:
	if _pending_enemy_action.is_empty(): return
	_pending_enemy_action["injected"] = EnemyActionCapture.injected(_pending_enemy_action.before, EnemyActionCapture.board_snapshot(battle.board))
	_pending_enemy_action.erase("before")
	_pending_enemy_action = {}




func _replay_enemy_action(view: Control, event: Dictionary) -> bool:
	var move: EnemyMoveData = event.move
	_enemy_attack_context.clear()
	if view is EnemyView and view.has_attack_actor() and move.kind in [EnemyMoveData.Kind.ATTACK, EnemyMoveData.Kind.ATTACK_BLOCK, EnemyMoveData.Kind.MULTI]:
		_enemy_attack_context = {"view": view, "move": move, "style": view.attack_effect(),
			"index": 0, "remaining": move.hits if move.kind == EnemyMoveData.Kind.MULTI else 1}
		return true
	var timing := {"release": 0.12, "duration": 0.22}
	if view is EnemyView: timing = view.play_action(move)
	var guardian: bool = event.target.enemy_data != null and event.target.enemy_data.id == "ink_spirit" and Palette.STYLE_ID == "taopunk" and view is EnemyView
	var injecting := move.kind == EnemyMoveData.Kind.INJECT
	if guardian and injecting and not Settings.reduced_motion:
		var source: Vector2 = _effects.get_global_transform().affine_inverse() * view.action_origin()
		_effects.enemy_ink("charge", source, source)
	if not await _wait_step(float(timing.release) if not Settings.reduced_motion else 0.04): return false
	if guardian and not Settings.reduced_motion:
		var source: Vector2 = _effects.get_global_transform().affine_inverse() * view.action_origin()
		if injecting:
			var additions: Array = event.get("injected", [])
			for i in additions.size():
				var item: Dictionary = additions[i]
				var tile: Control = _board_view.tiles[battle.board.from_xy(item.cell)]
				_effects.enemy_ink("pollution", source, _effects.point_of(tile), item.glyph, i * 0.06)
			if not additions.is_empty():
				if not await _wait_step(0.34 + maxf(0, additions.size() - 1) * 0.06): return false
				for item in additions:
					var inst: CharInstance = battle.board.get_xy(item.cell)
					if inst != null and inst.uid == item.uid:
						var tile: TileView = _board_view.tiles[battle.board.from_xy(item.cell)]
						tile.set_instance(inst)
						tile.enter(Vector2(0, -4), true, 0)
						_effects.enemy_ink("land", source, _effects.point_of(tile))
			else:
				_effects.number("未注入", source, Palette.INK_SOFT)
			# 完成施法回收，再更新下一回合的意图，避免直接截断动作。
			if not await _wait_step(maxf(0.04, float(timing.duration) - float(timing.release) - (0.34 if not additions.is_empty() else 0.0))): return false
		elif move.kind in [EnemyMoveData.Kind.ATTACK, EnemyMoveData.Kind.ATTACK_BLOCK, EnemyMoveData.Kind.MULTI]:
			# 精分等规则可能改变伤害对象；从已捕获的真实伤害事件确定终点。
			var target: Control = _player_hp_value
			var start := _events.find(event)
			for i in range(start + 1, _events.size()):
				if _events[i].kind == "enemy_action": break
				if _events[i].kind == "damage":
					target = _view_for(_events[i].target)
					if _events[i].target.is_player: target = _player_hp_value
					break
			_effects.enemy_ink("attack", source, _effects.point_of(target))
			if not await _wait_step(0.14): return false
	if move.kind == EnemyMoveData.Kind.SPECIAL and not Settings.reduced_motion:
		# Non-damaging actions have no damage event to wait for their recovery.
		if not await _wait_step(maxf(0.01,float(timing.duration) - float(timing.release))): return false
	return true




func _replay_enemy_strike(event: Dictionary) -> Dictionary:
	var attacker: EnemyView = _enemy_attack_context.view
	var timing := attacker.play_attack_hit(_enemy_attack_context.move, int(_enemy_attack_context.index))
	_enemy_attack_context.index += 1
	_enemy_attack_context.remaining -= 1
	if not await _wait_step(float(timing.get("release", 0.04))): return timing
	if Settings.reduced_motion: return timing
	var source: Vector2 = _effects.get_global_transform().affine_inverse() * attacker.action_origin()
	var target: Vector2 = _effects.point_of(_player_hp_value) if event.target.is_player else _effects.get_global_transform().affine_inverse() * _view_for(event.target).impact_point()
	_effects.enemy_attack(_enemy_attack_context.style, source, target)
	await _wait_step(0.14)
	return timing




func _open_pile(id: String) -> void:
	if _busy or _finished or _modal_count > 0 or id not in ["bag", "discard"]:
		return
	var overlay := BattlePileOverlay.new()
	overlay.setup("抽牌堆" if id == "bag" else "弃牌堆", battle.bag if id == "bag" else battle.discard)
	_mount_overlay(overlay)




func _open_battle_guide() -> void:
	# Pause menu releases its modal lock when queue_free runs at frame end.
	await get_tree().process_frame
	_open_battle_guide_ready.call_deferred()


func _open_battle_guide_ready() -> void:
	if not is_inside_tree(): return
	var body := "当前遗物：\n"
	if battle.relics.is_empty(): body += "暂无遗物。\n\n"
	else: body += "点击上方遗物模型查看具体效果。\n\n"
	body += "触屏操作：\n点按字块选择单字；沿相邻字块滑动可预览词语。\n"
	body += "松手后会尝试出字。\n" if Settings.drag_release_play else "松手只预览，点「出字」才会执行。\n"
	body += "\n点按敌人可选择目标；需要目标的词请按提示选择，再点「发动」。状态图标、敌人意图、防御图标与资源均可点按查看详情；带下划线的词条可点按阅读。"
	_show_hud_details("战斗与遗物说明", body, true, battle.relics)


func _show_hud_details(title: String, body: String, scroll_body: bool, relic_ids: Array = []) -> void:
	if _busy or _modal_count > 0:
		return
	var overlay := ChoiceOverlay.new()
	overlay.setup({"title": title, "body": body, "relics": relic_ids, "hud_details": true, "scroll_body": scroll_body, "dismissible": true, "options": [{"text": "返回战斗", "primary": true}]})
	_mount_overlay(overlay)
