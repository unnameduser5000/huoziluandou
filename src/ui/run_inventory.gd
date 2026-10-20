extends Control
## 所有场景共用的局内资源栏；查看不调用任何构筑或结算操作。
const Viewer = preload("res://src/ui/run_inventory_overlay.gd")
var screen: Control
var embedded := false
var buttons: Dictionary = {}
var _relics: HBoxContainer
var _relic_signature := ""
var _overlay: Control
var _panel: PanelContainer


func _ready() -> void:
	theme = JourneyStyle.get_theme()
	set_meta("journey_ui", true)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 70
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var panel := Ink.panel("PanelInset")
	_panel = panel
	var style: StyleBox = StyleBoxEmpty.new() if embedded else panel.get_theme_stylebox("panel").duplicate()
	style.set_content_margin_all(0 if embedded else 6)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(panel)
	if embedded: panel.minimum_size_changed.connect(update_minimum_size)
	var row := Ink.hbox(6)
	panel.add_child(row)
	for entry in [["deck", "牌库"], ["relics", "遗物"], ["gold", "铜钱"]]:
		var button := JourneyStyle.button(entry[1], open.bind(entry[0]))
		button.custom_minimum_size = Vector2(0, 48 * clampf(JourneyStyle.touch_scale(self), 1.0, 1.85))
		button.add_theme_font_size_override("font_size", int(16 * clampf(JourneyStyle.touch_scale(self), 1.0, 1.85)))
		row.add_child(button)
		buttons[entry[0]] = button
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	_relics = Ink.hbox(6)
	scroll.add_child(_relics)
	refresh()


func _get_minimum_size() -> Vector2:
	return _panel.get_combined_minimum_size() if embedded and is_instance_valid(_panel) else Vector2.ZERO


func _process(_delta: float) -> void:
	refresh()


func refresh() -> void:
	buttons.deck.text = "牌库 %d" % GameState.deck_size()
	buttons.relics.text = "遗物 %d" % GameState.relics.size()
	buttons.gold.text = "铜钱 %d" % GameState.gold
	var signature := str(GameState.relics)
	if signature == _relic_signature: return
	_relic_signature = signature
	for child in _relics.get_children():
		_relics.remove_child(child); child.queue_free()
	for id: String in GameState.relics:
		var button := JourneyStyle.button("", open_relic.bind(id))
		button.set_meta("relic_id", id)
		button.tooltip_text = Relics.text(id)
		button.custom_minimum_size = Vector2.ONE * 48 * clampf(JourneyStyle.touch_scale(self), 1.0, 1.85)
		_relics.add_child(button)
		var preview := preload("res://src/ui/relic_preview.gd").new()
		preview.relic_id = id
		button.add_child(preview)
		preview.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		button.mouse_entered.connect(preview.highlight.bind(true))
		button.mouse_exited.connect(preview.highlight.bind(false))
		button.focus_entered.connect(preview.highlight.bind(true))
		button.focus_exited.connect(preview.highlight.bind(false))


func open_relic(id: String) -> void:
	open("relics", id)


func open(tab: String, relic_id := "") -> void:
	if not buttons.has(tab): return
	if is_instance_valid(_overlay): return
	_overlay = Viewer.new()
	_overlay.initial_tab = tab
	_overlay.initial_relic = relic_id
	_overlay.z_index = 71
	if screen.has_method("_mount_overlay"):
		screen.call("_mount_overlay", _overlay)
	else:
		screen.add_child(_overlay)


func update_scale() -> void:
	var factor := clampf(JourneyStyle.touch_scale(self), 1.0, 1.85)
	for button in buttons.values() + _relics.get_children():
		button.custom_minimum_size.y = 48 * factor
		if button.has_meta("relic_id"): button.custom_minimum_size.x = 48 * factor
		button.add_theme_font_size_override("font_size", int(16 * factor))
