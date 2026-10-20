extends RefCounted
class_name EffectGlossary
## 纯展示词典：完整词效仍来自 WordData，不能执行效果或创建实体。

const ENTRIES := {
	"instant": ["效果", "一个词当场结算一次的部分：伤害、补字、治疗、护盾、资源等。与「能力」相对。"],
	"ability": ["持续能力", "启用后在指定时间内反复触发的效果，如【蓄能】。效果重演不会重复启用。"],
	"cleanse": ["净化", "移除字块上的污染，不改变字的归属。不能直接解除签或区域标记。"],
	"negative": ["负面状态", "中毒、易伤等不利效果。清心只清除玩家状态；字块污染用净化，怪物标记按要求解除。"],
	"block": [
		"临时格挡",
		"先于持久盾抵挡伤害。所有敌人行动后清空。"
	],
	"shield": [
		"持久盾",
		"临时格挡用完后继续抵挡伤害；剩余数值保留到下回合。"
	],
	"strength": [
		"力量",
		"每层增加攻击每段的伤害。本场保留。"
	],
	"counter": [
		"反击",
		"敌人全部行动后，按剩余临时格挡和反击层数攻击一次。"
	],
	"temporary": [
		"临时字",
		"用后消失，不进字袋或弃字堆；不继承原字的强化。生成时需要空格；仅供组词的临时字不能单打生效。"
	],
	"original": [
		"己方原字",
		"属于你的非临时字。同字的不同字块分别记录强化；移动或回袋时保留。"
	],
	"extra_use": [
		"额外使用",
		"每次使用先扣1次额外使用，字留在原位。额外次数用完后，再次使用才消耗该字。"
	],
	"refined": [
		"精炼",
		"获得额外使用；本场每次从字袋或弃字堆回到盘面时恢复。"
	],
	"pinned": [
		"固定",
		"本场每回合可用一次，用后留在原位。不能移动或替换，下回合恢复。"
	],
	"gold": [
		"铜钱",
		"战斗内货币。支付效果费用、商店与服务时消耗；战外结算时余金按每 5 点 1 分换算分数，不会转成别的资源。"
	],
	"gilded": [
		"镀金",
		"每次打出此字获得铜钱；组词也生效。永久保留。"
	],
	"word_only": [
		"仅供组词",
		"只能参与词语。单打只弃字，不发动单字效果。"
	],
	"fusion": [
		"融合",
		"多个字合成一个字块，占1格，共同移动和使用。镀金只按这个字块计一次。"
	],
	"selection": [
		"选中框",
		"当前选中的出字路径。取消选择即消失，不增加任何属性。"
	],
	"replay": [
		"效果重演",
		"这个词的效果再结算一次。字不再消耗，铜钱与储能照付；能力不会重复触发。"
	],
	"return": [
		"返回原位",
		"优先放回原来的格子，被占则找空格。空格不足时，回放少取回字，重连继续等待。"
	],
	"vulnerable": [
		"易伤",
		"受到的伤害增加；层数不影响增幅。"
	],
	"corrosion": [
		"心蚀",
		"敌人每次行动后受到伤害，伤害随层数增加。本场不减层。"
	],
	"regen": [
		"再生",
		"回合开始时回复生命，再减少层数。"
	],
	"heart": [
		"心力",
		"每层挡住一次致命伤害。触发后消耗1层，保留受击前生命。"
	],
	"bounty": [
		"爆金",
		"目标每受到一次攻击，你获得铜钱；多段攻击逐段计数，被护盾挡住也算。"
	],
	"burn": [
		"灼烧",
		"每层每回合失去「当前热度 × 2」生命，结算后掉 1 层。"
	],
	"scorch": [
		"灼热污染",
		"使用带灼热污染的字会扣除生命；净化可移除此污染。"
	],
	"overflow": [
		"溢热",
		"热度超过热容时，会生成带灼热污染的【热】。抽到或移动旧【热】不算溢热生成。"
	],
	"energy": [
		"储能",
		"供字词效果消耗，本场可跨回合积累；只有写明消耗时才会扣除。"
	],
	"heat": [
		"热度",
		"本场战斗中的资源，可被字词增加、降低或消耗，部分效果按当前热度计算收益。热容是安全上限；升温超过热容时，新增溢热会向字袋加入带灼热污染的【热】。"
	],
	"capacity": [
		"热容",
		"热度的安全上限。超过后会生成灼热【热】；提高热容不会降低现有热度。"
	],
	"non_attack": [
		"非攻击伤害",
		"不受力量或攻击强化加成。仍受护盾、减伤和易伤影响。"
	],
	"double_attack": [
		"超强增幅",
		"增强下一次攻击，用后消耗1层。"
	],
	"double_passive": [
		"能力收益",
		"能力带来的收益：补字、储能、治疗、护盾、伤害、层数、热容等。【超能力】会让本回合的这些收益全部结算两遍；消耗（如清空热度/储能）不翻倍。回合开始才结算的收益（回能、强心）不属于本回合，不受影响。"
	],
	"formation": [
		"结阵",
		"先选词，再点「发动」依次生效。多个词可以共用同一枚【击】。"
	]
}

## 长词优先，避免把“非攻击伤害”拆成“攻击”等片段。
const TERMS := {
	"即时效果": "instant", "持续能力": "ability", "能力": "ability",
	"净化": "cleanse", "负面状态": "negative",
	"临时格挡": "block", "临挡": "block", "持久盾": "shield", "力量": "strength",
	"反击": "counter", "临时字": "temporary", "临时复制": "temporary", "临时副本": "temporary",
	"己方原字": "original", "己方原实体": "original", "原字": "original", "原实体": "original", "字块": "original",
	"额外使用": "extra_use", "精炼效果": "refined", "精炼": "refined", "固定": "pinned", "镀金": "gilded",
	"仅供组词": "word_only", "融合": "fusion", "选中框": "selection",
	"效果重演": "replay", "原格返回": "return", "返回原位": "return", "易伤": "vulnerable", "心蚀": "corrosion",
	"心力": "heart", "爆金": "bounty", "灼烧": "burn", "灼热污染": "scorch",
	"再生": "regen",
	"铜钱": "gold", "金币": "gold",
	"溢热": "overflow", "储能": "energy", "热度": "heat", "热容": "capacity",
	"非攻击伤害": "non_attack", "超强翻倍": "double_attack", "超强增幅": "double_attack", "被动收益": "double_passive", "可翻倍收益": "double_passive", "能力收益": "double_passive",
	"结阵": "formation"
}

static func words_for_glyph(glyph: String) -> Array:
	var words: Array = []
	for word: WordData in Database.words.values():
		if word.glyphs.has(glyph): words.append(word.word)
	return words


static func character_hint(character: CharacterData) -> String:
	var words := words_for_glyph(character.glyph).slice(0, 4)
	if words.is_empty(): return character.description
	return character.description + "
可组：" + " / ".join(words.map(func(word): return "【%s】" % word))


static func brief(word: WordData) -> String:
	return WordDescriptions.brief(word)

static func vulnerable_damage_text() -> String:
	return "受到伤害×%s。层数不影响倍率。" % BattleBalance.f("vulnerable_mult", 1.5)

static func status_description(id: String) -> String:
	match id:
		"vulnerable": return vulnerable_damage_text()
		"strength": return "每层使攻击每段伤害+%d。本场保留，非攻击伤害不受加成。" % BattleBalance.i("strength_per_stack", 1)
		"regen": return "回合开始时，回复层数×%d生命。" % BattleBalance.i("regen_per_stack", 1)
		"poison": return "回合开始时，受到层数×%d伤害，可被护盾抵挡。" % BattleBalance.i("poison_per_stack", 1)
		"heart_corrosion": return "敌人每次行动后受到层数×%d非攻击伤害。本场不减层。" % BattleBalance.i("corrosion_per_stack", 1)
		"gold_burst": return "目标每受到一次攻击，你获得%d铜钱；多段攻击逐段计数，被护盾全挡也算。" % BattleBalance.i("bounty_on_hit", 1)
		"next_double": return "下一次攻击的基础伤害、力量和热力加成×%d；蓄力、连载、过火不放大。攻击后消耗1层，被全挡也消耗。" % BattleBalance.i("double_attack_mult", 2)
	var data := Database.get_status(id)
	if id == "next_extra": return "下一个组词的效果再结算一次，用后消耗1层。字不再消耗，铜钱与储能照付。"
	if id == "next_bonus": return "下一次攻击每段伤害+1/层；攻击后消耗。"
	if id == "burn": return "每层每回合失去「当前热度×%d」生命，结算后掉 1 层。" % BattleBalance.i("burn_heat_mult", 2)
	return data.description if data != null else ""

static func entry(meta: String) -> Dictionary:
	if meta.begins_with("status:"):
		var id := meta.trim_prefix("status:")
		var status := Database.get_status(id)
		if status == null: return {}
		if id == "vulnerable": return entry("term:vulnerable")
		var description := status_description(id)
		if id in ["regen", "poison"]:
			description += "结算后减少%d层。" % status.decay_per_turn if status.decay_per_turn > 0 else "不按回合减层。"
		return {"title": status.name, "text": description}
	if meta.begins_with("pollution:"):
		var pollution := Database.get_pollution(meta.trim_prefix("pollution:"))
		if pollution != null:
			return {"title": pollution.name + "污染", "text": pollution.description}
		return {}
	if meta.begins_with("term:"):
		var key := meta.trim_prefix("term:")
		if ENTRIES.has(key):
			var description: String = ENTRIES[key][1]
			if key == "gilded": description = "每次打出此字获得%d铜钱，组词也算；仅弃字不算，融合字只计一次。永久保留，临时字不继承。" % BattleBalance.i("gild_gold", 1)
			elif key == "vulnerable":
				var status := Database.get_status("vulnerable")
				var decay := status.decay_per_turn if status != null else 1
				description = vulnerable_damage_text()
				description += ("敌我双方每回合开始减少%d层。" % decay if decay > 0 else "敌我双方不按回合减层。")
			elif key == "counter": description = "所有敌人行动后，攻击首个存活敌人一次：伤害=剩余临时格挡+%d×层数。之后清空反击层数。" % BattleBalance.i("counter_per_stack", 3)
			elif key == "refined": description = "立即获得%d次额外使用。本场每次从字袋或弃字堆重新入盘时，恢复至少%d次；移动或换回合不恢复。" % [BattleBalance.i("refined_layers", 2), BattleBalance.i("refined_layers", 2)]
			elif key in ["strength", "regen", "corrosion", "bounty", "double_attack"]:
				var statuses := {"strength": "strength", "regen": "regen", "corrosion": "heart_corrosion", "bounty": "gold_burst", "double_attack": "next_double"}
				description = str(entry("status:" + statuses[key]).get("text", description))
			elif key == "burn": description = "【放火】的灼烧：每层每回合失去当前热度×%d 生命，结算后掉 1 层。" % BattleBalance.i("burn_heat_mult", 2)
			return {"title": ENTRIES[key][0], "text": description}
	elif meta.begins_with("word:"):
		var word := Database.get_word_by_glyphs_string(meta.trim_prefix("word:"))
		if word != null:
			return {"title": word.word, "text": word.describe()}
	return {}

static func escape(text: String) -> String:
	return text.replace("[", "[lb]")

static func format_text(text: String, number_size := 0, exclude := "", local_entries: Dictionary = {}) -> String:
	var term_metas: Dictionary = {}
	for term in TERMS: term_metas[term] = "term:" + TERMS[term]
	for pollution in Database.pollutions.values():
		term_metas[pollution.name + "污染"] = "pollution:" + pollution.id
		term_metas[pollution.name] = "pollution:" + pollution.id
	for status in Database.statuses.values():
		term_metas[status.name + "状态"] = "status:" + status.id
		if not term_metas.has(status.name): term_metas[status.name] = "status:" + status.id
	for meta in local_entries:
		var info: Dictionary = local_entries[meta]
		term_metas[str(info.get("label", info.title))] = str(meta)
	var terms: Array = term_metas.keys()
	terms.sort_custom(func(a, b): return a.length() > b.length())
	var output := ""
	var cursor := 0
	while cursor < text.length():
		# 只有完整的【词语】才转词条链接，避免把【热】等字形当作规则名。
		if text[cursor] == "【":
			var end := text.find("】", cursor + 1)
			if end >= 0:
				var glyphs := text.substr(cursor + 1, end - cursor - 1)
				var literal := text.substr(cursor, end - cursor + 1)
				var meta := "word:" + glyphs
				output += link(literal, meta) if glyphs.length() >= 2 and meta != exclude and not entry(meta).is_empty() else escape(literal)
				cursor = end + 1
				continue
		var matched := false
		for term in terms:
			if text.substr(cursor, term.length()) != term:
				continue
			var meta: String = term_metas[term]
			output += link(term, meta) if meta != exclude else escape(term)
			cursor += term.length()
			matched = true
			break
		if matched:
			continue
		if text[cursor] >= "0" and text[cursor] <= "9":
			var end := cursor + 1
			while end < text.length() and ((text[end] >= "0" and text[end] <= "9") or text[end] == "."):
				end += 1
			var digits := text.substr(cursor, end - cursor)
			output += "[color=#%s]%s%s%s[/color]" % [Palette.VERMILION_DK.to_html(false), "[font_size=%d]" % number_size if number_size > 0 else "", digits, "[/font_size]" if number_size > 0 else ""]
			cursor = end
			continue
		output += escape(text[cursor])
		cursor += 1
	return output

static func link(label: String, meta: String) -> String:
	return "[url=%s][color=#%s]%s[/color][/url]" % [meta, Palette.INDIGO.to_html(false), escape(label)]
