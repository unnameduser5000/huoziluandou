extends Control
class_name ScreenBase
## 全屏基类：行旅皮肤 / 独立场景背景 / 战斗背景，以及内容容器。

var params: Dictionary = {}
var content: Control
var inventory_bar: Control


func setup(p: Dictionary) -> void:
	params = p


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var world_backed := is_instance_valid(Router.study_stage) and Router.study_stage.visible
	var path: String = get_script().resource_path
	var journey := not has_scene_background() and not path.ends_with("/battle_screen.gd")
	if journey:
		JourneyStyle.apply(self)
		add_child(preload("res://src/ui/journey/journey_backdrop.gd").new())
	elif path.ends_with("/battle_screen.gd") and Palette.STYLE_ID == "taopunk" and not world_backed:
		var backdrop := TextureRect.new()
		backdrop.texture = TaopunkArt.background()
		backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(backdrop)
	elif not has_scene_background() and (not world_backed or (not path.contains("title_screen") and not path.contains("battle_screen"))):
		var paper := Ink.paper_layer()
		add_child(paper)
	content = Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(content)
	build(content)
	if has_run_inventory():
		inventory_bar = preload("res://src/ui/run_inventory.gd").new()
		inventory_bar.screen = self
		var host := run_inventory_host()
		inventory_bar.embedded = host != self
		host.add_child(inventory_bar)
	resized.connect(_layout_inventory_bar)
	_layout_inventory_bar()
	if has_method("_layout"):
		content.resized.connect(Callable(self, "_layout"))
		Callable(self, "_layout").call_deferred()


func _layout_inventory_bar() -> void:
	# Reset both ends: a temporary presentation offset must not shrink this region
	# when a window resize changes the inventory height.
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not is_instance_valid(inventory_bar): return
	if inventory_bar.embedded:
		inventory_bar.update_scale()
		return
	var height := 64.0 * clampf(JourneyStyle.touch_scale(self), 1.0, 1.85)
	var safe := ScreenLayout.safe_rect(self)
	inventory_bar.position = safe.position
	inventory_bar.size = Vector2(safe.size.x, height)
	content.offset_top = safe.position.y + height
	inventory_bar.update_scale()


func has_run_inventory() -> bool:
	return true


## Pages with their own header can include the inventory in that same row.
func run_inventory_host() -> Control:
	return self



## 子类重写
func has_scene_background() -> bool:
	return false


func build(_root: Control) -> void:
	pass


func goto(path: String, p: Dictionary = {}) -> void:
	Router.goto(path, p)


func save_checkpoint() -> Dictionary:
	# Persist only route parameters; derived controls/layout are rebuilt on resume.
	var clean := params.duplicate()
	clean.erase("_saved_screen")
	return {"params": clean, "screen": {}}
