extends ScreenBase
## A disposable lesson: only local combatants/cards, never GameState.start_new_run.
const SPOTLIGHT = preload("res://src/ui/tutorial_spotlight.gd")
const RUN = preload("res://src/expedition/room_run_state.gd")
const ENEMY_ID := "ink_spirit"
const END_STEP := 5
const COMPLETE_STEP := 6
const LESSONS := [
	["一字，也能出招", "点亮起的「击」，再点「出字」。\n先选字看效果，确认后才消耗。"],
	["相邻两字，连成一招", "沿「击 → 破」连线，再点「出字」。\n按顺序点选或拖动，只连上下左右。"],
	["连不上？让字落下来", "下方的「击」「破」并不相邻。\n单独打出「重」，看看空格如何改变字的位置。"],
	["重排字盘，就有新解", "刚才连不上的两字，现在相邻了！\n沿底行「击 → 破」出字，亲手完成这次变招。"],
	["看敌人意图，先防守", "墨灵即将攻击。沿「防 → 御」出字，\n用临时格挡接住这一击。"],
	["结束回合，看看结果", "点「结束回合」，观察墨灵攻击。\n临时格挡先挡伤害，下一回合会补入新字。"],
	["学会了：字盘也能经营", "单字出招 · 相邻成词 · 用「重」整理字盘。\n没有现成的词时，先想想能否让字落到一起。"]
]
const PATHS := [[Vector2i(0, 0)], [Vector2i(1, 0), Vector2i(2, 0)], [Vector2i(0, 1)],
	[Vector2i(1, 3), Vector2i(2, 3)], [Vector2i(3, 2), Vector2i(3, 3)]]
var battle: BattleState
var step := 0
var _board_view: BoardView
var _header: HBoxContainer
var _progress: Label
var _exit_btn: Button
var _guide: ScrollContainer
var _guide_column: VBoxContainer
var _heading: Label
var _instruction: Label
var _status: Label
var _preview: Label
var _feedback: Label
var _actions: HBoxContainer
var _confirm_btn: Button
var _clear_btn: Button
var _end_btn: Button
var _replay_btn: Button
var _modal_count := 0
var _pause_overlay: ChoiceOverlay
var _back_quit_before := true
var _owns_back := false
var _enemy_card: Control
var _enemy_art: InkSpirit
var _enemy_name: Label
var _enemy_health: Label
var _intent: EnemyIntent
var _guide_frame: Panel
var _spotlight: Control
var _audio: BattleAudio
var _animating := false
var _focus_step := -1


func has_run_inventory() -> bool:
	return false


func build(root: Control) -> void:
	_back_quit_before = get_tree().quit_on_go_back
	get_tree().quit_on_go_back = false
	_owns_back = true
	_create_practice()
	_header = HBoxContainer.new()
	root.add_child(_header)
	_progress = JourneyStyle.label("")
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(_progress)
	_exit_btn = JourneyStyle.button("退出练习", _leave)
	_header.add_child(_exit_btn)
	_board_view = preload("res://src/board/tutorial_board_view.gd").new()
	_board_view.require_confirmation = true
	_board_view.setup(battle.board)
	root.add_child(_board_view)
	_board_view.selection_changed.connect(_selection_changed)
	_board_view.commit.connect(_commit)
	_enemy_card = Control.new(); root.add_child(_enemy_card)
	_enemy_art = InkSpirit.new(); _enemy_art.enemy_id = ENEMY_ID; _enemy_card.add_child(_enemy_art)
	_enemy_name = JourneyStyle.label("", "Heading"); _enemy_card.add_child(_enemy_name)
	_enemy_health = JourneyStyle.label("", "Stat"); _enemy_card.add_child(_enemy_health)
	_intent = EnemyIntent.new(); _enemy_card.add_child(_intent)
	_intent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guide_frame = Panel.new(); _guide_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guide_frame.add_theme_stylebox_override("panel", JourneyStyle.frame("panel", 12))
	root.add_child(_guide_frame)
	_guide = ScrollContainer.new()
	_guide.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_guide)
	_guide_column = VBoxContainer.new()
	_guide_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_guide.add_child(_guide_column)
	_heading = _label("", "Heading")
	_instruction = _label("")
	_preview = _label("", "", JourneyStyle.GOLD)
	_feedback = _label("", "", JourneyStyle.GOLD)
	_status = JourneyStyle.label("")
	_header.add_child(_status)
	_header.move_child(_status, 1)
	_actions = HBoxContainer.new()
	root.add_child(_actions)
	_clear_btn = _action("清空选择", _board_view.clear_selection)
	_confirm_btn = _action("出字", func(): _commit(_board_view.path.duplicate()))
	_confirm_btn.theme_type_variation = "PrimaryButton"
	_end_btn = _action("结束回合", _end_turn)
	_end_btn.theme_type_variation = "PrimaryButton"
	_replay_btn = _action("再练一次", _restart)
	_spotlight = SPOTLIGHT.new(); root.add_child(_spotlight)
	_audio = BattleAudio.new(); add_child(_audio)
	_board_view.resized.connect(_update_spotlight.call_deferred)
	resized.connect(_layout)
	_refresh()
	_layout.call_deferred()


func _create_practice() -> void:
	# start() copies relics and increments the adventure battle sequence; do not use it.
	battle = BattleState.new(Database.rules)
	battle.rng.seed = 20261018
	battle.visual_rng.seed = 18
	battle.player = Combatant.new("玩家", 30, true)
	battle.player.heat_capacity = Database.rules.heat_capacity
	var data: EnemyData = Database.get_enemy(ENEMY_ID)
	var enemy := Combatant.new(data.name, data.max_hp, false)
	enemy.enemy_data = data
	enemy.block = data.initial_block
	battle.enemies.append(enemy)
	# The second 击/破 pair starts diagonally separated. Gravity makes it adjacent.
	for entry in [[Vector2i(0, 0), "击"], [Vector2i(1, 0), "击"], [Vector2i(2, 0), "破"],
		[Vector2i(0, 1), "重"], [Vector2i(1, 1), "击"], [Vector2i(2, 2), "破"],
		[Vector2i(3, 2), "防"], [Vector2i(3, 3), "御"]]:
		battle.board.set_xy(entry[0], CharInstance.new(Database.char_by_glyph[entry[1]]))
	for glyph in ["击", "防", "御", "破", "重"]:
		battle.bag.append(CharInstance.new(Database.char_by_glyph[glyph]))
	battle.begin_player_turn(false)


func _label(text: String, variation := "", color := JourneyStyle.TEXT) -> Label:
	var label := JourneyStyle.label(text, variation, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_guide_column.add_child(label)
	return label


func _action(text: String, callback: Callable) -> Button:
	var button := JourneyStyle.button(text, callback)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions.add_child(button)
	return button


func _layout() -> void:
	if _header == null or size.y < 1: return
	var unit := JourneyStyle.touch_scale(self)
	var pad := 8 * unit
	var row := 48 * unit
	_header.position = Vector2(pad, pad)
	_header.size = Vector2(size.x - pad * 2, row)
	_exit_btn.custom_minimum_size.y = row
	var body_top := pad * 2 + row
	var body_height := size.y - body_top - row - pad * 2
	var compact := body_height / unit < 650
	var side := minf(body_height, size.x * 0.47 - pad * 2)
	_board_view.position = Vector2(pad, body_top + (body_height - side) * 0.5)
	_board_view.size = Vector2.ONE * side
	var right_x := side + pad * 3
	var right_width := size.x - right_x - pad
	var enemy_height := minf(body_height * 0.39, 190 * unit)
	_enemy_card.position = Vector2(right_x, body_top)
	_enemy_card.size = Vector2(right_width, enemy_height)
	_enemy_art.position = Vector2(right_width * 0.52, 0)
	_enemy_art.size = Vector2(right_width * 0.48, enemy_height)
	var info_width := right_width * 0.5
	_enemy_name.position = Vector2(0, 2 * unit); _enemy_name.size = Vector2(info_width, 30 * unit)
	_enemy_name.add_theme_font_size_override("font_size", int(24 * unit))
	_enemy_health.position = Vector2(0, 34 * unit); _enemy_health.size = Vector2(info_width, 28 * unit)
	_enemy_health.add_theme_font_size_override("font_size", int(18 * unit))
	_intent.position = Vector2(0, 67 * unit)
	_intent.size = Vector2(info_width, minf(50 * unit, enemy_height - 67 * unit))
	_intent.set_ui_scale(unit * 0.8)
	_guide_frame.position = Vector2(right_x, body_top + enemy_height + pad)
	_guide_frame.size = Vector2(right_width, body_height - enemy_height - pad)
	_guide.position = _guide_frame.position + Vector2.ONE * pad
	_guide.size = _guide_frame.size - Vector2.ONE * pad * 2
	_guide_column.add_theme_constant_override("separation", int((6 if compact else 8) * unit))
	_heading.add_theme_font_size_override("font_size", int((20 if compact else 26) * unit))
	_progress.add_theme_font_size_override("font_size", int(20 * unit))
	for label in [_instruction, _status, _preview, _feedback]:
		label.add_theme_font_size_override("font_size", int((15 if compact else 18) * unit))
	_status.add_theme_font_size_override("font_size", int((14 if compact else 16) * unit))
	_actions.position = Vector2(pad, size.y - row - pad)
	_actions.size = Vector2(size.x - pad * 2, row)
	_actions.add_theme_constant_override("separation", int(8 * unit))
	for button in [_confirm_btn, _clear_btn, _end_btn, _replay_btn]:
		button.custom_minimum_size.y = row
		button.add_theme_font_size_override("font_size", int(19 * unit))
	_update_spotlight.call_deferred()
	_exit_btn.add_theme_font_size_override("font_size", int(19 * unit))


func _refresh() -> void:
	_progress.text = "新手教程 · %d / %d" % [step + 1, COMPLETE_STEP] if step < COMPLETE_STEP else "新手教程 · 已完成"
	_heading.text = LESSONS[step][0]
	_instruction.text = LESSONS[step][1]
	var enemy: Combatant = battle.enemies[0]
	_enemy_name.text = enemy.display_name
	_enemy_health.text = "气血 %d / %d" % [enemy.hp, enemy.max_hp]
	_intent.set_move(battle.current_intent(enemy), enemy)
	_status.text = "气血 %d · 格挡 %d" % [battle.player.hp, battle.player.block]
	_status.visible = step < COMPLETE_STEP
	_feedback.visible = not _feedback.text.is_empty()
	_board_view.set_interactable(step < END_STEP and _modal_count == 0 and not _animating, false)
	_board_view.allowed_cells = PATHS[step] if step < END_STEP else []
	_clear_btn.visible = step < END_STEP
	_confirm_btn.visible = step < END_STEP
	_end_btn.visible = step == END_STEP
	_end_btn.disabled = _animating or _modal_count > 0
	_replay_btn.visible = step == COMPLETE_STEP
	_exit_btn.text = ("开始冒险" if step == COMPLETE_STEP else "跳过引导") if params.get("start_adventure", false) else ("返回主菜单" if step == COMPLETE_STEP else "退出练习")
	_selection_changed(_board_view.path, [], null)
	_highlight()
	_guide.scroll_vertical = 0
	_update_spotlight.call_deferred()


func _highlight() -> void:
	for tile in _board_view.tiles:
		tile.set_dimmed(false) # The animated mask owns dimming; the board stays true to combat.


func _region(control: Control, margin := 0.0) -> Rect2:
	return Rect2(control.global_position - _spotlight.global_position, control.size).grow(margin)


func _tile(pos: Vector2i) -> Control:
	return _board_view.tiles[battle.board.from_xy(pos)]


func _update_spotlight() -> void:
	if _spotlight == null or not is_node_ready() or _modal_count > 0: return
	var holes: Array[Rect2] = [_region(_header), _region(_guide_frame), _region(_enemy_card)]
	var accents: Array[Rect2] = []
	var gesture := PackedVector2Array()
	var arrows: Array = []
	if not _animating:
		if step < END_STEP:
			for pos in PATHS[step]:
				var rect := _region(_tile(pos), 3)
				holes.append(rect); accents.append(rect); gesture.append(rect.get_center())
			for button in [_clear_btn, _confirm_btn]:
				if button.visible: holes.append(_region(button, 2))
			if _board_view.path == PATHS[step]:
				gesture = PackedVector2Array([_region(_confirm_btn).get_center()])
				accents.append(_region(_confirm_btn, 2))
			if step == 2:
				# Reveal both the obstruction and the exact landing cells before the move.
				for pair in [[Vector2i(1, 1), Vector2i(1, 3)], [Vector2i(2, 2), Vector2i(2, 3)]]:
					for pos in pair: holes.append(_region(_tile(pos), 2))
					arrows.append([_region(_tile(pair[0])).get_center(), _region(_tile(pair[1])).get_center()])
		elif step == END_STEP:
			holes.append(_region(_end_btn, 2)); accents.append(_region(_end_btn, 2))
			gesture.append(_region(_end_btn).get_center())
		else:
			holes.append(_region(_board_view)); holes.append(_region(_actions))
	else:
		holes.append(_region(_board_view))
	_spotlight.focus(holes, accents, gesture, arrows, step != _focus_step)
	_focus_step = step


func _selection_changed(path: Array, _glyphs: Array, _word: WordData) -> void:
	if _confirm_btn == null: return
	_update_spotlight.call_deferred()
	_preview.visible = step < END_STEP and not path.is_empty()
	_confirm_btn.disabled = path.is_empty() or _modal_count > 0 or _animating or step >= END_STEP
	_clear_btn.disabled = path.is_empty() or _modal_count > 0 or _animating
	if path.is_empty():
		_preview.text = "选中后在这里预览效果" if step < END_STEP else ""
		return
	var glyphs := battle.board.glyphs_of(path)
	# A new choice replaces the previous success/error message with its preview.
	_feedback.hide()
	var word := Database.get_word_by_glyphs(glyphs) if glyphs.size() > 1 else null
	var effect := word.description if word != null else battle.board.get_xy(path[0]).data.description if glyphs.size() == 1 else "尚未组成有效词语"
	# This unshielded practice target only needs the immediate result, before
	# introducing shield-breaking and other advanced word details in adventures.
	if word != null and word.word == "击破": effect = "造成 %d 点伤害" % word.effects[0].amount
	_preview.text = "「%s」 · %s" % ["".join(glyphs), effect]


func _commit(path: Array) -> void:
	if step >= END_STEP or _modal_count > 0 or _animating: return
	if path != PATHS[step]:
		_feedback.text = "跟随亮起的字按顺序选择，再点「出字」。选错可清空重试，不会消耗字。"
		_feedback.show()
		_guide.scroll_vertical = 0
		return
	var hp_before: int = battle.enemies[0].hp
	var result := battle.try_play(path, {"target_index": 0})
	if not result.ok:
		_feedback.text = result.reason
		_feedback.show()
		return
	_animating = true
	_board_view.clear_selection()
	_board_view.set_interactable(false, false)
	_board_view.rebuild(true)
	_confirm_btn.disabled = true; _clear_btn.disabled = true
	_update_spotlight()
	var loss: int = hp_before - battle.enemies[0].hp
	if step == 2:
		_feedback.text = "「重」让两字落到一起，创造了新的出招机会。"
		_audio.play_cue("gravity")
	elif step == 4:
		_feedback.text = "获得 %d 点临时格挡，准备迎击。" % battle.player.block
		_audio.play_cue("block")
	else:
		_feedback.text = "墨灵气血 -%d；用过的字进入弃字堆。" % loss
		_audio.play_cue("hit")
		_enemy_art.apply_character_feedback({"kind":"damage", "hp_loss":loss, "hp":battle.enemies[0].hp, "max_hp":battle.enemies[0].max_hp})
	if not Settings.reduced_motion:
		await get_tree().create_timer(0.75 if step == 2 else 0.32).timeout
		if not is_inside_tree(): return
	_animating = false
	step += 1
	_refresh()


func _end_turn() -> void:
	if step != END_STEP or _modal_count > 0 or _animating: return
	_animating = true
	_refresh()
	var move := battle.current_intent(battle.enemies[0])
	_enemy_art.play_action(move)
	_audio.play_cue("block")
	if not Settings.reduced_motion:
		await get_tree().create_timer(0.6).timeout
		if not is_inside_tree(): return
	var before := battle.player.hp
	battle.end_player_turn()
	step = COMPLETE_STEP
	_animating = false
	Settings.complete_first_run_tutorial()
	_feedback.text = "挡住了墨灵的攻击！气血 %d → %d。\n新回合已补字；带着这些技巧开始冒险吧。" % [before, battle.player.hp]
	_board_view.rebuild(true)
	_refresh()


func _restart() -> void:
	if _modal_count > 0 or _animating: return
	step = 0
	_create_practice()
	_board_view.setup(battle.board)
	_board_view.clear_selection()
	_board_view.rebuild()
	_feedback.text = ""
	_refresh()


func _leave() -> void:
	if _modal_count > 0: return
	if params.get("start_adventure", false):
		Settings.complete_first_run_tutorial()
		RUN.start()
		goto(RUN.MAP_SCREEN)
	else:
		goto("res://src/screens/title_screen.gd")


func open_practice_menu() -> void:
	if _modal_count > 0: return
	var overlay := ChoiceOverlay.new()
	_pause_overlay = overlay
	overlay.setup({"title": "练习暂停", "body": "练习进度仅在本次有效，冒险自动存档不受影响。", "dismissible": true, "cancel_index": 0,
		"options": [{"text": "继续练习", "primary": true}, {"text": "重新练习"}, {"text": "退出练习"}]})
	# ChoiceOverlay invokes actions before freeing itself. Defer until input unlocks.
	overlay.chose.connect(func(index):
		if index == 1: _restart.call_deferred()
		elif index == 2: _leave.call_deferred())
	_modal_count += 1
	_board_view.set_interactable(false)
	_exit_btn.disabled = true
	_end_btn.disabled = true
	_replay_btn.disabled = true
	_selection_changed(_board_view.path, [], null)
	overlay.tree_exited.connect(func():
		_modal_count = 0
		if not is_queued_for_deletion():
			_exit_btn.disabled = false
			_end_btn.disabled = false
			_replay_btn.disabled = false
			_refresh())
	add_child(overlay)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("end_turn") and not event.is_echo() and step == END_STEP and _modal_count == 0:
		_end_turn()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_inside_tree():
		_handle_back.call_deferred()


func _handle_back() -> void:
	if Router.current != self or is_queued_for_deletion(): return
	if is_instance_valid(_pause_overlay) and _pause_overlay.is_inside_tree():
		_pause_overlay._on_choose(0)
	elif not _board_view.path.is_empty():
		_board_view.clear_selection()
	else:
		open_practice_menu()


func _exit_tree() -> void:
	if _owns_back: get_tree().quit_on_go_back = _back_quit_before
