extends ScreenBase
## A disposable lesson: only local combatants/cards, never GameState.start_new_run.
const SPOTLIGHT = preload("res://src/ui/tutorial_spotlight.gd")
const LESSON_OVERLAY = preload("res://src/ui/tutorial_lesson_overlay.gd")
const RUN = preload("res://src/expedition/room_run_state.gd")
const ENEMY_ID := "ink_spirit"
const END_STEP := 5
const COMPLETE_STEP := 6
const LESSONS := [
	["先用一个字出招", "点亮起的「击」。\n选字后，先看效果。"],
	["相邻两字成词", "沿「击 → 破」连线。\n只连上下左右的字。"],
	["让字落到一起", "这两字还不相邻。\n打出「重」整理字盘。"],
	["新词，再出招", "底行两字已经相邻。\n连出「击 → 破」。"],
	["看意图，先防守", "剑旁数字是攻击伤害。\n连「防 → 御」叠格挡。"],
	["结束回合，迎击", "格挡会先抵消伤害。\n点「结束回合」迎击。"],
	["可以开始冒险了", "单字、连词、防守。\n再用「重」整理字盘。"]
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
var _guide_bounds := Rect2()
var _spotlight: Control
var _audio: BattleAudio
var _animating := false
var _focus_step := -1
var _lesson_overlay: Control
var _seen_lessons: Array[int] = []


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
	_enemy_art.clip_contents = true
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
	_guide_column.minimum_size_changed.connect(_layout_callout.call_deferred)
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
	_end_btn = JourneyStyle.button("结束回合", _end_turn)
	root.add_child(_end_btn)
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
	var safe := ScreenLayout.safe_rect(content).intersection(Rect2(Vector2.ZERO, content.size))
	var pad := 8 * unit
	var row := 48 * unit
	var compact := safe.size.y / unit < 600
	var tight := safe.size.y / unit < 340
	_header.position = safe.position + Vector2.ONE * pad
	_header.size = Vector2(safe.size.x - pad * 2, row)
	_exit_btn.custom_minimum_size.y = row
	# Keep the normal battle's preview / board / enemy composition in practice.
	var body := Rect2(safe.position + Vector2(0, pad * 2), safe.size - Vector2(0, pad * 3))
	var layout := BattleTouchLayout.measure(body.size, unit, false)
	_board_view.position = body.position + layout.board.position
	_board_view.size = layout.board.size
	_guide_bounds = Rect2(body.position + Vector2(pad, layout.board.position.y), Vector2(layout.column, layout.board.size.y))
	var right_width: float = layout.enemy.size.x
	_enemy_card.position = body.position + layout.enemy.position
	_enemy_card.size = layout.enemy.size
	_enemy_name.add_theme_font_size_override("font_size", roundi((20 if tight else 22) * unit))
	_enemy_name.position = Vector2.ZERO
	_enemy_name.size = Vector2(right_width, (24 if tight else 28) * unit)
	_enemy_health.add_theme_font_size_override("font_size", roundi((14 if tight else 16) * unit))
	_enemy_health.position = Vector2(0, (26 if tight else 30) * unit)
	_enemy_health.size = Vector2(right_width, (20 if tight else 24) * unit)
	_intent.set_ui_scale(unit * (0.65 if tight else 0.8))
	_intent.position = Vector2(0, (48 if tight else 56) * unit)
	_intent.size = Vector2(right_width, (38 if tight else 48) * unit)
	_enemy_art.position = Vector2(0, (90 if tight else 108) * unit)
	_enemy_art.size = Vector2(right_width, _enemy_card.size.y - _enemy_art.position.y)
	_guide.size.x = _guide_bounds.size.x - pad * 2
	_guide_column.add_theme_constant_override("separation", int(8 * unit))
	_heading.add_theme_font_size_override("font_size", int((20 if compact else 26) * unit))
	_progress.add_theme_font_size_override("font_size", int((18 if compact else 20) * unit))
	for label in [_instruction, _status, _preview, _feedback]:
		label.add_theme_font_size_override("font_size", int((15 if compact else 18) * unit))
	_status.add_theme_font_size_override("font_size", int((14 if compact else 16) * unit))
	_actions.position = body.position + layout.actions.position
	_actions.size = layout.actions.size
	_end_btn.position = body.position + layout.end.position
	_end_btn.size = layout.end.size
	_actions.add_theme_constant_override("separation", int(8 * unit))
	for button in [_confirm_btn, _clear_btn, _end_btn, _replay_btn]:
		button.custom_minimum_size.y = row
		button.add_theme_font_size_override("font_size", int(19 * unit))
	_update_spotlight.call_deferred()
	_exit_btn.add_theme_font_size_override("font_size", int(19 * unit))
	_layout_callout.call_deferred()


func _layout_callout() -> void:
	if _guide == null or not _guide_bounds.has_area(): return
	var pad := 8 * JourneyStyle.touch_scale(self)
	var height := minf(_guide_bounds.size.y, _guide_column.get_combined_minimum_size().y + pad * 2)
	_guide_frame.size = Vector2(_guide_bounds.size.x, height)
	_guide_frame.position = _guide_bounds.position + Vector2(0, (_guide_bounds.size.y - height) * 0.5)
	_guide.position = _guide_frame.position + Vector2.ONE * pad
	_guide.size = _guide_frame.size - Vector2.ONE * pad * 2
	_update_spotlight.call_deferred()


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
	_feedback.visible = not _feedback.text.is_empty() and (step == COMPLETE_STEP or _animating)
	_board_view.set_interactable(step < END_STEP and _modal_count == 0 and not _animating and _lesson_overlay == null, false)
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
	if LESSON_OVERLAY.PAGES.has(step) and not _seen_lessons.has(step): _show_lesson()


func _show_lesson() -> void:
	_seen_lessons.append(step)
	_lesson_overlay = LESSON_OVERLAY.new()
	_lesson_overlay.lesson = step
	_lesson_overlay.battle = battle
	_lesson_overlay.example = PATHS[step]
	_lesson_overlay.exit_text = _exit_btn.text
	_lesson_overlay.dismissed.connect(_close_lesson)
	_lesson_overlay.exit_requested.connect(func():
		_close_lesson()
		_leave())
	add_child(_lesson_overlay)
	_board_view.set_interactable(false, false)
	_selection_changed(_board_view.path, [], null)


func _close_lesson() -> void:
	if _lesson_overlay == null: return
	_lesson_overlay.queue_free()
	_lesson_overlay = null
	_refresh()


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
	var target := _region(_board_view).get_center()
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
			if not gesture.is_empty(): target = gesture[0]
			if step == 4: accents.append(_region(_intent, 2))
			if step == 2:
				# Reveal both the obstruction and the exact landing cells before the move.
				for pair in [[Vector2i(1, 1), Vector2i(1, 3)], [Vector2i(2, 2), Vector2i(2, 3)]]:
					for pos in pair: holes.append(_region(_tile(pos), 2))
					arrows.append([_region(_tile(pair[0])).get_center(), _region(_tile(pair[1])).get_center()])
		elif step == END_STEP:
			holes.append(_region(_end_btn, 2)); accents.append(_region(_end_btn, 2))
			gesture.append(_region(_end_btn).get_center())
			target = _region(_end_btn).get_center()
			accents.append(_region(_status, 2))
		else:
			holes.append(_region(_board_view)); holes.append(_region(_actions))
	else:
		holes.append(_region(_board_view))
	_spotlight.focus(holes, accents, gesture, arrows, step != _focus_step)
	_spotlight.point_at(_region(_guide_frame), target, JourneyStyle.touch_scale(self))
	_focus_step = step


func _selection_changed(path: Array, _glyphs: Array, _word: WordData) -> void:
	if _confirm_btn == null: return
	_update_spotlight.call_deferred()
	_preview.visible = step < END_STEP and not path.is_empty()
	_confirm_btn.disabled = path.is_empty() or _modal_count > 0 or _animating or step >= END_STEP or _lesson_overlay != null
	_clear_btn.disabled = path.is_empty() or _modal_count > 0 or _animating
	_instruction.text = "点下方的「出字」。" if step < END_STEP and path == PATHS[step] else LESSONS[step][1]
	_layout_callout.call_deferred()
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
	if glyphs == ["重"]: effect = "每列字向下填补空格。"
	_preview.text = "「%s」 · %s" % ["".join(glyphs), effect]


func _commit(path: Array) -> void:
	if step >= END_STEP or _modal_count > 0 or _animating or _lesson_overlay != null: return
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
	_feedback.text = "气血 %d → %d\n新回合已补字。" % [before, battle.player.hp]
	_board_view.rebuild(true)
	_refresh()


func _restart() -> void:
	if _modal_count > 0 or _animating: return
	step = 0
	_seen_lessons.clear()
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
	if _lesson_overlay != null:
		_close_lesson()
		return
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
	if _lesson_overlay != null:
		_close_lesson()
	elif is_instance_valid(_pause_overlay) and _pause_overlay.is_inside_tree():
		_pause_overlay._on_choose(0)
	elif not _board_view.path.is_empty():
		_board_view.clear_selection()
	else:
		open_practice_menu()


func _exit_tree() -> void:
	if _owns_back: get_tree().quit_on_go_back = _back_quit_before
