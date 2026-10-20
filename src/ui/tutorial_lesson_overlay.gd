extends Control
## Read-only examples use the practice board; dismissing never plays a card.
signal dismissed
signal exit_requested
const SPOTLIGHT = preload("res://src/ui/tutorial_spotlight.gd")
const PAGES := {
	0: ["用字出招", "点字或拖动连线，选择要出的字。\n\n先看效果，再点「出字」。\n相邻两字还能连成更强的词。", 1],
	2: ["让字落到一起", "连不成词时，先整理字盘。\n\n「重」会让每列的字向下落。\n用下落创造新的相邻词。", 2],
	4: ["防守与回合", "剑旁数字是攻击伤害。\n连出「防御」获得临时格挡。\n结束回合时，格挡先抵消伤害。", 3],
}
var lesson := 0
var battle: BattleState
var example: Array
var exit_text := "退出练习"
var _header: HBoxContainer
var _exit_btn: Button
var _demo: BoardView
var _annotation: Control
var _copy: VBoxContainer
var _heading_row: HBoxContainer
var _heading: Label
var _body: Label
var _intent: EnemyIntent
var _progress: Label
var _next_btn: Button
var _copy_bounds := Rect2()


func _ready() -> void:
	z_index = 80
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(JourneyStyle.INK, 0.97)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_header = HBoxContainer.new()
	add_child(_header)
	var title := JourneyStyle.label("新手教程", "Subheading", JourneyStyle.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(title)
	_exit_btn = JourneyStyle.button(exit_text, exit_requested.emit)
	_header.add_child(_exit_btn)
	_demo = BoardView.new()
	_demo.setup(battle.board)
	add_child(_demo)
	_demo.set_interactable(false, false)
	_demo.path = example.duplicate()
	_demo.rebuild()
	_annotation = SPOTLIGHT.new()
	_demo.add_child(_annotation)
	_copy = VBoxContainer.new()
	add_child(_copy)
	_copy.minimum_size_changed.connect(_center_copy.call_deferred)
	_heading_row = HBoxContainer.new()
	_copy.add_child(_heading_row)
	_heading = JourneyStyle.label(PAGES[lesson][0], "Heading")
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading_row.add_child(_heading)
	_intent = EnemyIntent.new()
	_heading_row.add_child(_intent)
	_intent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intent.visible = lesson == 4
	if lesson == 4: _intent.set_move(battle.current_intent(battle.enemies[0]), battle.enemies[0])
	_body = JourneyStyle.label(PAGES[lesson][1])
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_copy.add_child(_body)
	_progress = JourneyStyle.label("%d / 3" % PAGES[lesson][2], "Stat", JourneyStyle.GOLD)
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_progress)
	_next_btn = JourneyStyle.button("开始练习", dismissed.emit, true)
	_next_btn.theme_type_variation = "PrimaryButton"
	add_child(_next_btn)
	resized.connect(_layout)
	_layout()
	_next_btn.grab_focus.call_deferred()


func _layout() -> void:
	if _demo == null or size.y < 1: return
	var unit := JourneyStyle.touch_scale(self)
	var safe := ScreenLayout.safe_rect(self).intersection(Rect2(Vector2.ZERO, size))
	var pad := (12 if safe.size.y / unit < 340 else 16) * unit
	var row := 48 * unit
	_header.position = safe.position + Vector2.ONE * pad
	_header.size = Vector2(safe.size.x - pad * 2, row)
	_exit_btn.custom_minimum_size = Vector2(112 * unit, row)
	_exit_btn.add_theme_font_size_override("font_size", roundi(18 * unit))
	var footer_y := safe.end.y - pad - row
	var top := _header.position.y + row + 12 * unit
	var height := footer_y - 12 * unit - top
	var left_width := (safe.size.x - pad * 2) * 0.46
	var side := minf(left_width, height)
	_demo.position = Vector2(safe.position.x + pad + (left_width - side) * 0.5, top + (height - side) * 0.5)
	_demo.size = Vector2.ONE * side
	var copy_x := safe.position.x + pad + left_width + 24 * unit
	_copy_bounds = Rect2(Vector2(copy_x, top), Vector2(safe.end.x - pad - copy_x, height))
	_copy.size.x = _copy_bounds.size.x
	_copy.add_theme_constant_override("separation", roundi(10 * unit))
	_heading_row.add_theme_constant_override("separation", roundi(10 * unit))
	_heading.add_theme_font_size_override("font_size", roundi(22 * unit))
	_body.add_theme_font_size_override("font_size", roundi(16 * unit))
	_intent.custom_minimum_size = Vector2(72 * unit, 40 * unit)
	_intent.set_ui_scale(unit * 0.6)
	_progress.position = Vector2(safe.position.x + pad, footer_y)
	_progress.size = Vector2(safe.size.x - pad * 2, row)
	_progress.add_theme_font_size_override("font_size", roundi(16 * unit))
	_next_btn.position = Vector2(safe.end.x - pad - 144 * unit, footer_y)
	_next_btn.size = Vector2(144 * unit, row)
	_next_btn.custom_minimum_size = _next_btn.size
	_next_btn.add_theme_font_size_override("font_size", roundi(19 * unit))
	_center_copy.call_deferred()


func _center_copy() -> void:
	if not _copy_bounds.has_area(): return
	_copy.size = Vector2(_copy_bounds.size.x, _copy.get_combined_minimum_size().y)
	_copy.position = _copy_bounds.position + Vector2(0, maxf(0, (_copy_bounds.size.y - _copy.size.y) * 0.5))


func _process(_delta: float) -> void:
	if _annotation == null or _demo.tiles.is_empty(): return
	var accents: Array[Rect2] = []
	var path := PackedVector2Array()
	var arrows: Array = []
	for pos: Vector2i in example:
		var tile: Control = _demo.tiles[battle.board.from_xy(pos)]
		var rect := Rect2(tile.position, tile.size)
		accents.append(rect)
		path.append(rect.get_center())
	if lesson == 2:
		for pair in [[Vector2i(1, 1), Vector2i(1, 3)], [Vector2i(2, 2), Vector2i(2, 3)]]:
			var from: Control = _demo.tiles[battle.board.from_xy(pair[0])]
			var to: Control = _demo.tiles[battle.board.from_xy(pair[1])]
			arrows.append([from.position + from.size * 0.5, to.position + to.size * 0.5])
	var regions: Array[Rect2] = [Rect2(Vector2.ZERO, _demo.size)]
	_annotation.focus(regions, accents, path, arrows)
