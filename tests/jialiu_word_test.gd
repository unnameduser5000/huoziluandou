extends Node
## 甲流：先使目标获得2层易伤，再造成8点伤害（这一击已吃易伤）。

var checks := 0
var failures := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[jialiu_word_test] FAIL: " + message)


func _ready() -> void:
	var w: WordData = Database.get_word_by_glyphs(["甲", "流"])
	check(w != null and w.word == "甲流" and w.implemented, "甲流已入词库")
	var rules: BattleRules = Database.rules.duplicate()
	rules.opening_draw = 0
	rules.turn_draw = 0
	GameState.player_max_hp = 1000
	GameState.player_hp = 1000
	GameState.relics.clear()
	var b := BattleState.new(rules)
	b.start([], [Database.get_enemy("ink_spirit")], 121)
	var e: Combatant = b.enemies[0]
	e.block = 0
	e.hp = 100
	e.max_hp = 100
	for x in 2:
		b.board.set_xy(Vector2i(x, 0), CharInstance.new(Database.get_character_by_glyph("甲流"[x])))
	check(b.try_play([Vector2i(0, 0), Vector2i(1, 0)]).ok, "真实出词成功：甲流")
	check(e.status_stacks("vulnerable") == 2, "目标获得2层易伤")
	# 易伤倍率在数值表里可调，这里只看这一击确实超过了 8
	check(e.hp < 92, "先易伤再出手：8点伤害按易伤结算（实际 %d）" % (100 - e.hp))
	var raw_desc := str(WordDescriptions.TEXT.get("甲流", ""))
	check(raw_desc.contains("易伤") and raw_desc.contains("8点伤害"), "说明写清易伤和伤害（数据侧）")
	check(str(w.describe()) == "【？？？】", "彩蛋词玩家可见文案保持隐藏")
	print("[jialiu_word_test] PASS=%d FAIL=%d TOTAL=%d" % [checks - failures, failures, checks])
	get_tree().quit(1 if failures > 0 else 0)
