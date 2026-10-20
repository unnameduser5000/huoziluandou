extends Node
## 内容数据库：扫描 res://resources 下的 .tres，建立索引。
## 新增字/词/敌人/幕 = 往对应目录丢一个 .tres，不需要改代码。

const CHAR_DIR := "res://resources/characters"
const WORD_DIR := "res://resources/words"
const STATUS_DIR := "res://resources/statuses"
const POLLUTION_DIR := "res://resources/pollutions"
const ENEMY_DIR := "res://resources/enemies"
const ACT_DIR := "res://resources/acts"
const DECK_DIR := "res://resources/starter_decks"
const RULES_PATH := "res://resources/rules/default_rules.tres"

var characters: Dictionary = {}      ## id -> CharacterData
var char_by_glyph: Dictionary = {}   ## glyph -> CharacterData
var words: Dictionary = {}           ## id -> WordData
var words_by_glyphs: Dictionary = {} ## "击破" -> WordData
var statuses: Dictionary = {}        ## id -> StatusData
var pollutions: Dictionary = {}      ## id -> PollutionData
var enemies: Dictionary = {}         ## id -> EnemyData
var acts: Dictionary = {}            ## index -> ActData
var starter_decks: Dictionary = {}   ## id -> StarterDeckData
var rules: BattleRules = null

var warnings: Array[String] = []
var revision := 0


func _ready() -> void:
	reload()


func reload() -> void:
	revision += 1
	characters.clear()
	char_by_glyph.clear()
	words.clear()
	words_by_glyphs.clear()
	statuses.clear()
	pollutions.clear()
	enemies.clear()
	acts.clear()
	starter_decks.clear()
	warnings.clear()
	BattleBalance.load_configuration()
	if not BattleBalance.warning.is_empty():
		warnings.append(BattleBalance.warning)
		push_warning(BattleBalance.warning)

	for res in _load_dir(CHAR_DIR, "CharacterData"):
		for effect in res.solo_effects:
			effect.kind = effect.semantic_kind()
		res.description = BattleText.character(res)
		characters[res.id] = res
		char_by_glyph[res.glyph] = res
	for res in _load_dir(WORD_DIR, "WordData"):
		for effect in res.effects:
			effect.kind = effect.semantic_kind()
		# 玩家可见说明的唯一来源：BattleText.WORDS（.tres 与 WordDescriptions 的 TEXT 字段都作废）
		res.description = BattleText.word(res)
		res.effect_summary = res.description
		words[res.id] = res
		words_by_glyphs[res.glyph_string()] = res
	for res in _load_dir(STATUS_DIR, "StatusData"):
		statuses[res.id] = res
	for res in _load_dir(POLLUTION_DIR, "PollutionData"):
		pollutions[res.id] = res
	for res in _load_dir(ENEMY_DIR, "EnemyData"):
		enemies[res.id] = res
	for res in _load_dir(ACT_DIR, "ActData"):
		acts[res.index] = res
	for res in _load_dir(DECK_DIR, "StarterDeckData"):
		var starter: StarterDeckData = res.duplicate(true)
		for entry in starter.entries:
			if entry.character != null:
				entry.character = characters.get(entry.character.id, entry.character)
		starter_decks[starter.id] = starter
	var balance_warning := EnemyBalance.load_into(enemies, pollutions)
	if not balance_warning.is_empty():
		warnings.append(balance_warning)
		push_warning(balance_warning)
	_bind_act_enemies()


	if ResourceLoader.exists(RULES_PATH):
		rules = BattleBalance.apply_resource(load(RULES_PATH))
	if rules == null:
		rules = BattleRules.default_rules()

	print("[Database] 字 %d / 词 %d / 敌人 %d / 幕 %d / 污染 %d" % [
		characters.size(), words.size(), enemies.size(), acts.size(), pollutions.size()
	])


func _bind_act_enemies() -> void:
	# 地图里的外部 EnemyData 引用仍指向缓存的原始 .tres；调参创建的是新资源。
	# 先复制地图，再将候选池和固定遭遇统一绑定到完成配置的怪物，避免机制参数缺失变0。
	for index in acts:
		var act: ActData = acts[index].duplicate(true)
		for node in act.nodes:
			for i in node.enemy_pool.size():
				var original: EnemyData = node.enemy_pool[i]
				node.enemy_pool[i] = enemies.get(original.id, original)
			for i in node.enemies.size():
				var original: EnemyData = node.enemies[i]
				node.enemies[i] = enemies.get(original.id, original)
		acts[index] = act


func _load_dir(dir_path: String, _expect_class: String) -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(dir_path):
		warnings.append("目录不存在: %s" % dir_path)
		return out
	var files := DirAccess.get_files_at(dir_path)
	for f in files:
		if f.ends_with(".remap"):
			f = f.trim_suffix(".remap")
		if not (f.ends_with(".tres") or f.ends_with(".res")):
			continue
		var full := dir_path.path_join(f)
		var res = load(full)
		if res == null:
			warnings.append("无法加载: %s" % full)
			continue
		out.append(BattleBalance.apply_resource(res))
	return out


func get_character(id: String) -> CharacterData:
	return characters.get(id)


func get_character_by_glyph(glyph: String) -> CharacterData:
	return char_by_glyph.get(glyph)


func get_pollution(id: String) -> PollutionData:
	return pollutions.get(id)


func get_word_by_glyphs(glyphs: Array) -> WordData:
	var key := ""
	for g in glyphs:
		key += str(g)
	return words_by_glyphs.get(key)


func get_word_by_glyphs_string(key: String) -> WordData:
	return words_by_glyphs.get(key)


func get_status(id: String) -> StatusData:
	return statuses.get(id)


func get_enemy(id: String) -> EnemyData:
	return enemies.get(id)


func get_act(index: int) -> ActData:
	return acts.get(index)
