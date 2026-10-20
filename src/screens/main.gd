extends Control
## 启动入口：设置路由宿主，进入标题界面。
##
## 支持命令行自定义起始字袋（调试 / 自定义模式）：
##   godot --path . -- --deck 火火电电防防        # 逐字；也支持 火x2,电x2
##   godot --path . -- --deck-file res://deck.json  # JSON 数组 ["火","火","电"] 或 {"deck":"火火电"}
# Retain script dependencies from startup; they must not be parsed on shop entry.
const SHOP_SCRIPT := preload("res://src/screens/shop_screen.gd")

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Test harnesses may instantiate Main; only normal startup uses the real save slot.
	if get_parent() == get_tree().root:
		SaveManager.activate()
	var study := StudyStage.new()
	add_child(study)
	Router.study_stage = study
	Router.host = self
	var glyphs := _deck_from_cmdline()
	if not glyphs.is_empty():
		GameState.start_new_run("v03", glyphs)
		print("[main] 自定义字袋 %d 枚：%s" % [GameState.deck_size(), JSON.stringify(GameState.glyph_counts())])
		Router.goto("res://src/screens/map_screen.gd")
		return
	Router.goto("res://src/screens/title_screen.gd")
	# Decode shared counter meshes while the player is on the title screen.
	preload("res://src/ui/object_stage/counter_assets.gd").warm(get_tree())


func _deck_from_cmdline() -> Array:
	var args := OS.get_cmdline_user_args()
	var out: Array = []
	var i := 0
	while i < args.size():
		var a := str(args[i])
		if a == "--deck" and i + 1 < args.size():
			out.append_array(_parse_deck_spec(str(args[i + 1])))
			i += 2
			continue
		if a == "--deck-file" and i + 1 < args.size():
			out.append_array(_load_deck_file(str(args[i + 1])))
			i += 2
			continue
		i += 1
	return out


## "火火电电" → 逐字；"火x2,电x2" / "火*2 电2" → 带数量
func _parse_deck_spec(spec: String) -> Array:
	var out: Array = []
	var s := spec.strip_edges()
	if s.is_empty():
		return out
	var tokens: Array = []
	if s.contains(",") or s.contains(" ") or s.contains("，"):
		tokens = s.replace("，", ",").replace(" ", ",").split(",", false)
	else:
		for k in s.length():
			tokens.append(s.substr(k, 1))
	for tok in tokens:
		var t := str(tok).strip_edges()
		if t.is_empty():
			continue
		var mult := 1
		var glyph := t
		var m := t.find("x")
		if m < 0:
			m = t.find("*")
		if m > 0:
			glyph = t.substr(0, m)
			mult = maxi(1, int(t.substr(m + 1)))
		elif t.length() > 1 and t.substr(t.length() - 1, 1).is_valid_int():
			glyph = t.substr(0, t.length() - 1)
			mult = maxi(1, int(t.substr(t.length() - 1, 1)))
		for k in mult:
			out.append(glyph)
	return out


func _load_deck_file(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_warning("[main] 字袋文件不存在: %s" % path)
		return []
	var text := FileAccess.get_file_as_string(path)
	var trimmed := text.strip_edges()
	if trimmed.begins_with("["):
		var data = JSON.parse_string(trimmed)
		var out: Array = []
		if typeof(data) == TYPE_ARRAY:
			for g in data:
				if typeof(g) == TYPE_DICTIONARY:
					for k in int(g.get("count", 1)):
						out.append(str(g.get("glyph", "")))
				else:
					out.append(str(g))
		return out
	if trimmed.begins_with("{"):
		var data2 = JSON.parse_string(trimmed)
		if typeof(data2) == TYPE_DICTIONARY and data2.has("deck"):
			return _parse_deck_spec(str(data2["deck"]))
		return []
	return _parse_deck_spec(trimmed.replace("\n", ","))


func _exit_tree() -> void:
	Router.release_host(self)
