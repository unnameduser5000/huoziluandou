extends RefCounted
class_name ContentBuild
## 内容构建表：EffectData 构造、默认文案、以及全部多字词的效果映射。
## 从 build_content.gd 抽出，便于单独编辑内容（新增/修改词效只动这里）。

const EffectDataS := preload("res://src/data/effect_data.gd")
const WordDescriptionsS := preload("res://src/data/word_descriptions.gd")

## 已确认的词语平衡覆盖；资源和生成器共用同一份最终规格。
const BALANCE_SPECS := {
	"回购": {
		"handler": "buyback",
		"amount": 2,
		"desc": WordDescriptionsS.TEXT["回购"],
		"target": 0,
		"timing": "immediate",
		"args": {
			"cost": 2
		},
		"interaction": "choose_buyback"
	},
	"投放": {
		"handler": "reveal_place",
		"amount": 2,
		"desc": WordDescriptionsS.TEXT["投放"],
		"target": 0,
		"timing": "immediate",
		"args": {},
		"interaction": "choose_bag_deploy"
	},
	"资金": {
		"handler": "gold",
		"amount": 5,
		"desc": WordDescriptionsS.TEXT["资金"],
		"target": 0,
		"timing": "immediate",
		"args": {},
		"interaction": ""
	},
	"反复": {
		"handler": "repeat_zero",
		"amount": 1,
		"desc": WordDescriptionsS.TEXT["反复"],
		"target": 0,
		"timing": "next_word",
		"args": {},
		"interaction": ""
	},
	"流利": {
		"handler": "ability_diagonal_next",
		"amount": 1,
		"desc": WordDescriptionsS.TEXT["流利"],
		"target": 0,
		"timing": "next_word",
		"args": {},
		"interaction": ""
	},
	"加强": {
		"handler": "strength_growing",
		"amount": 1,
		"desc": WordDescriptionsS.TEXT["加强"],
		"target": 3,
		"timing": "immediate",
		"args": {},
		"interaction": ""
	},
	"重载": {
		"handler": "ability_reload",
		"amount": 4,
		"desc": WordDescriptionsS.TEXT["重载"],
		"target": 0,
		"timing": "persistent",
		"args": {
			"draw_penalty": 1
		},
		"interaction": ""
	},
	"精炼": {
		"handler": "refine_layer",
		"amount": 0,
		"desc": WordDescriptionsS.TEXT["精炼"],
		"target": 0,
		"timing": "immediate",
		"args": {},
		"interaction": "choose_same_pair"
	},
	"蓄能": {
		"handler": "ability_energy_idle",
		"amount": 2,
		"desc": WordDescriptionsS.TEXT["蓄能"],
		"target": 0,
		"timing": "persistent",
		"args": {},
		"interaction": ""
	},
	"精铸": {
		"handler": "pin_glyph",
		"amount": 0,
		"desc": WordDescriptionsS.TEXT["精铸"],
		"target": 5,
		"timing": "immediate",
		"args": {},
		"interaction": ""
	},
	"充电过热": {
		"handler": "charge_overheat",
		"amount": 8,
		"desc": WordDescriptionsS.TEXT["充电过热"],
		"target": 0,
		"timing": "persistent",
		"args": {
			"energy": 8,
			"heat": 8
		},
		"interaction": ""
	},
	"热力": {
		"handler": "heat_to_bonus",
		"amount": 2,
		"desc": WordDescriptionsS.TEXT["热力"],
		"target": 0,
		"timing": "immediate",
		"args": {
			"per": 2
		},
		"interaction": ""
	},
	"蓄力": {
		"handler": "energy_to_bonus",
		"amount": 2,
		"desc": WordDescriptionsS.TEXT["蓄力"],
		"target": 0,
		"timing": "immediate",
		"args": {
			"per": 2
		},
		"interaction": ""
	},
	"过火": {
		"handler": "ability_overfire",
		"amount": 0,
		"desc": WordDescriptionsS.TEXT["过火"],
		"target": 0,
		"timing": "next_word",
		"args": {
			"per": 3,
			"heat": 2
		},
		"interaction": ""
	},
	"复电": {
		"handler": "refund_energy_half",
		"amount": 0,
		"desc": WordDescriptionsS.TEXT["复电"],
		"target": 0,
		"timing": "immediate",
		"args": {},
		"interaction": ""
	},
	"分流": {
		"handler": "divert",
		"amount": 2,
		"desc": WordDescriptionsS.TEXT["分流"],
		"target": 0,
		"timing": "immediate",
		"args": {},
		"interaction": "choose_junk_tiles"
	},
	"超能力": {
		"handler": "double_next_ability",
		"amount": 0,
		"desc": WordDescriptionsS.TEXT["超能力"],
		"target": 0,
		"timing": "next_word",
		"args": {},
		"interaction": ""
	},
	"强心": {
		"handler": "ability_strong_heart",
		"amount": 1,
		"desc": WordDescriptionsS.TEXT["强心"],
		"target": 0,
		"timing": "persistent",
		"args": {},
		"interaction": ""
	},
	"连载": {
		"handler": "serial",
		"amount": 6,
		"desc": WordDescriptionsS.TEXT["连载"],
		"target": 0,
		"timing": "persistent",
		"args": {
			"bonus": 6
		},
		"interaction": ""
	},
	"过热": {
		"handler": "ability_heat_overload_bonus",
		"amount": 2,
		"desc": WordDescriptionsS.TEXT["过热"],
		"target": 0,
		"timing": "persistent",
		"args": {},
		"interaction": ""
	}
}

static func e(handler: String, amount := 0, target := -1, status := "", note := "", args := {}, kind := -1, timing := "immediate", pre_consume := false) -> EffectData:
	var e: EffectData = EffectDataS.new()
	e.handler = handler
	e.amount = amount
	if target >= 0:
		e.target = target
	e.status_id = status
	e.args = args
	e.timing = timing
	e.pre_consume = pre_consume
	if kind >= 0:
		e.kind = kind
	else:
		e.kind = e.semantic_kind()
	e.note = note if not note.is_empty() else handler_note(handler, amount, status, args)
	return e


## 简易效果的默认文案（保证预览/图鉴/策划案都准确）

static func handler_note(handler: String, amount: int, status: String, args: Dictionary) -> String:
	match handler:
		"block_temp": return "获得 %d 点临时格挡" % amount
		"block_persist": return "获得 %d 点持久盾" % amount
		"guard_reduce": return "本回合每次受伤 -%d" % amount
		"ability_armor_plating": return "每回合获得 %d 点格挡，格挡被击穿则碎裂" % amount
		"ability_guard_inject": return "下次敌方塞字减少 %d 个" % amount
		"damage": return "造成 %d 点伤害" % amount
		"overdo": return "造成 %d 伤，并重演本场之前所有【过分】的伤害" % amount
		"replay_word": return "把上一个词用过的字放回盘面"
		"manual_draw_next": return "下回合补字 -%d，但可从字袋定向选字（随机落地）" % amount
		"ability_warm_heart": return "本场：热度 +1=回 1 血，-1=扣 1 血"
		"guard_halve": return "本回合受伤减半（向上取整再 -1）"
		"ability_strong_heart": return "本场：每回合开始回复 2 + 已触发心力层数的生命"
		"collect_own": return "选盘面牌回袋，每枚回 1 血"
		"cold_heart": return "本回合伤害翻倍；2 回合不能获得防御"
		"cleanse_status": return "清除自身全部负面状态"
		"return_enemy": return "移除字盘上一枚敌方实体字"
		"damage_all": return "对所有敌人造成 %d 点伤害" % amount
		"draw_random": return "随机补 %d 字" % amount
		"draw_penalty_next": return "下一次正常补字 -%d" % amount
		"draw_bonus_next": return "下回合多抽 %d 字" % amount
		"heal": return "回复 %d 点生命" % amount
		"energy": return "获得 %d 点储能" % amount
		"heat": return "热度 %+d" % amount if amount != 0 else "热度不变"
		"heat_clear": return "清空当前热度"
		"gold": return "获得 %d 铜钱" % amount
		"gold": return "获得 %d 点铜钱" % amount
		"apply_status_self": return "获得状态【%s】×%d" % [status_name(status), max(1, amount)]
		"apply_status_enemy": return "使敌人获得【%s】×%d" % [status_name(status), max(1, amount)]
		"remove_enemy_block": return "移除敌人全部护盾"
		"cleanse_all": return "清除当前字盘的全部污染（所有权不变）"
		"cleanse_adjacent": return "净化目标及其四邻的污染"
		"gravity": return "全盘按列向下重力"
		"gravity_left": return "全盘按行向左重力"
		"gravity_right": return "全盘按行向右重力"
		"rotate_2x2": return "顺时转旋转所选 2×2 区域"
		"destroy_2x2": return "摧毁所选 2×2，每摧毁 1 字造成 %d 伤" % amount
		"recover_consumed": return "从弃字堆回收本回合消耗的 1 枚字到袋顶"
		"replay_last_attack": return "重演上一个即时攻击词的效果"
		"shield_smash": return "造成 %d 伤并消耗全部持久盾（每 2 点额外 3 伤）" % amount
		"counter": return "预留 %d 层反击" % max(1, amount)
		"conditional_draw_after_attack": return "若此前已有即时攻击则补 %d 字" % amount
		"conditional_draw_half_hp": return "低于半血补 %d 字，否则补 %d 字" % [int(args.get("low", amount)), int(args.get("high", 1))]
		"break_shield_damage": return "造成 %d 伤；拆盾效率×2；击碎护盾再补 1 字" % amount
		"permanent_damage_reduction": return "本局永久：每次实际生命伤害 -%d" % amount
		"transform_board": return "随机揭示 %d 枚实体字，选 1 枚替换盘面指定字" % int(args.get("reveal", 5))
		"split_grow": return "删除一个盘面字，四周生长可组词临时字"
		"empower_glyph": return "选择一个字，本场它被打出时额外触发单字效果"
		"refine_remove": return "热度 -%d、铜钱 +%d，并移出一张牌" % [int(args.get("heat", 3)), int(args.get("gold", 4))]
		"fuse_cards": return "选两张相邻己方牌融合为一格（本场不可拆）"
		"refine_layer": return "选两枚同字原实体，第一枚本场每次入盘恢复 2 次额外使用，第二枚回袋"
		"gild_glyph": return "选一枚字袋实体永久镀金；每次单字或组词打出+1铜钱"
		"precision_place": return "支付 %d 铜钱，把弃字堆一枚字放进指定空格" % amount
		"recast_board": return "把盘面上已有的字全部重新替换"
		"recast_copy": return "从弃字堆选一张，把临时复制放进指定空格"
		"repeat_last": return "复制上一手成功出字的末字为临时副本，不能复制【再】本身"
		"reverse_line": return "选一行或一列，倒转其 4 格（含空格/叠层）"
		"merge_flow": return "揭示字袋 1 枚 + 弃字堆 1 枚，放入两个相邻空格"
		"hard_stop": return "清空热度并移除未打出的灼热【热】；立即结束出字"
		"repeat_word": return "每回合第一次多字词再执行一次"
		_:
			return handler

static func status_name(id: String) -> String:
	match id:
		"strength": return "力量"
		"vulnerable": return "易伤"
		"next_bonus": return "热力强化"
		"next_double": return "超强"
		"next_extra": return "超载"
		"burn": return "灼烧"
		"poison": return "中毒"
		"heart_corrosion": return "心蚀"
		_: return id

static func word_effects(word: String) -> Array:
	if word == "复利": return [e("gold", 2), e("draw_random", 1)]
	if BALANCE_SPECS.has(word):
		var spec: Dictionary = BALANCE_SPECS[word]
		return [e(spec.handler, spec.amount, spec.target, "", spec.desc, spec.args, -1, spec.timing)]
	# 按《完整词效总账》的“最近讨论效果方向”实现；未收敛的返回空数组（=待定）。
	var T := EffectDataS.Target
	match word:
		# 防反
		"防御": return [e("block_temp", 10)]
		"防护": return [e("ability_prevent_interference", 1, -1, "", "本场持续：抵消下一次敌人对字盘的干扰（注入/塞字）", {}, -1, "persistent")]
		"护甲": return [e("ability_convert_block", 50, -1, "", "回合结束把一半剩余临挡转为持久盾", {"percent": 50}, -1, "persistent")]
		"护盾": return [e("block_persist", 6)]
		"重甲": return [e("block_persist", 12), e("draw_penalty_next", 1)]
		"反击": return [e("counter", 3, -1, "", "预留反击；敌人整次行动后把剩余临挡转为伤害并 +3/层", {}, -1, "delayed")]
		"盾击": return [e("shield_smash", 4, T.ENEMY, "", "造成 4 伤并消耗全部持久盾，每 2 点额外 3 伤", {"per": 2, "bonus": 3})]
		"回防": return [e("block_temp", 8), e("conditional_draw_after_attack", 1)]
		"破防": return [e("apply_status_enemy", 2, T.ENEMY, "vulnerable")]
		"破甲": return [e("remove_enemy_block")]
		"击破": return [e("break_shield_damage", 8, T.ENEMY, "", "造成 8 伤；拆盾效率×2；击碎护盾再补 1 字", {"mult": 2, "draw": 1})]
		"防御力": return [e("permanent_damage_reduction", 1, -1, "", "首次组出后本局永久每次实际生命伤害 -1", {}, -1, "persistent")]
		"反超": return [e("conditional_draw_half_hp", 4, -1, "", "低于半血补 4 字，否则补 1 字", {"low": 4, "high": 1})]
		# 连携
		"连击": return [e("replay_last_attack", 0, -1, "", "重演上一个即时攻击词的效果", {}, -1, "immediate")]
		"重击": return [e("gravity_damage", 6, T.ENEMY, "", "6 伤 + 重力移动的每枚字块 2 伤", {"per": 2})]
		"合击": return [e("ability_shared_attack", 0, -1, "", "进入结阵：之后打出的词只登记不结算，点「发动」一起结算；多词可共享同一枚【击】", {}, -1, "persistent")]
		"回击": return [e("damage", 7), e("conditional_draw_after_attack", 1)]
		"强力": return [e("apply_status_self", 2, T.SELF, "strength")]
		"超强": return [e("apply_status_self", 1, T.SELF, "next_double")]
		"重合": return [e("merge_duplicates", 0, T.BOARD_TILE, "", "汇聚同字：保留 1 实体并获得同数量临时层，其余回字袋")]
		# 流转
		"回流": return [e("draw_random", 4)]
		"回收": return [e("recover_consumed", 1, T.DISCARD_GLYPH)]
		"回转": return [e("rotate_2x2", 0, T.BOARD_2X2)]
		"流转": return [e("ability_flow", 2, -1, "", "本回合每打出 2 种不同多字词补 2 字", {}, -1, "persistent")]
		"清洗": return [e("cleanse_all", 0, T.BOARD, "", "清除当前字盘所有污染标签（所有权不变）")]
		"复合": return [e("ability_compound_next", 1, -1, "", "下一次≥3字词保留 1 枚用过的字为临时层", {}, -1, "next_word")]
		# 蓄放
		"蓄电": return [e("energy_around_tail", 1, -1, "", "基础 +1；词尾电周围每个己方四邻字再 +1 储能", {})]
		"充电": return [e("energy", 3)]
		"充能": return [e("energy", 1), e("draw_random", 2)]
		"放电": return [e("energy_discharge", 4, T.ENEMY, "", "清空全部储能，每点造成一段 4 伤电击", {})]
		"充放电": return [e("energy_discharge", 4, T.ENEMY, "", "消耗全部储能：每点造成 4 伤；每命中一段，下回合储能 +2", {"refund": 2})]
		# 热暴
		"过载": return [e("draw_random", 6), e("heat", 3)]
		"超载": return [e("apply_status_self", 1, T.SELF, "next_extra"), e("heat", 3)]
		"加速": return [e("ability_accel", 1, -1, "", "本回合每次打出多字词额外补 1 字并热度 +1", {}, -1, "persistent")]
		"急速": return [e("ability_rapid_next", 4, -1, "", "下一次多字词结算后在其空格补至多 4 字并升温 2", {"heat": 2}, -1, "next_word")]
		"冷却": return [e("heat", -4)]
		"清热": return [e("heat_cleanse", 2, -1, "", "热度 -2 并清除灼热污染")] 
		"热流": return [e("heat_to_damage_flow", 2, T.ENEMY, "", "按本回合补字数最多降 4 热，每实际降 1 热造成 2 伤", {"max": 4})]
		"火爆": return [e("heat_burst", 8, T.ENEMY, "", "消耗全部热度，造成 8 + 4×热度伤害", {"per": 4})]
		"爆破": return [e("destroy_2x2", 4, T.BOARD_2X2, "", "摧毁 2×2 区域（含自己），每摧毁 1 字造成 4 伤", {}, -1, "immediate", true)]
		"加热": return [e("heat", 5)]
		"急冷": return [e("heat_clear", 0), e("draw_penalty_next", 1)]
		"电流过载": return [e("ability_electric_overload", 3, -1, "", "本战每次溢热：生成灼热热字、储能 +1、对敌 3 伤", {}, -1, "persistent")]
		"超速": return [e("ability_double_draw_next", 4, -1, "", "本回合下一次补字翻倍，最多额外 4 字；每额外 1 字升温 1", {}, -1, "next_word")]
		# 经济
		"金币": return [e("gold", 3)]
		"投币": return [e("spend_gold_damage", 5, T.ENEMY, "", "支付最多 3 铜钱，每铜钱造成 5 伤", {"max": 3})]
		"收购": return [e("capture_glyph", 4, T.ENEMY_GLYPH, "", "支付 4 铜钱，净化并永久收编一枚敌方实体字", {})]
		"复利投资": return [e("gild_glyph", 0, -1, "", WordDescriptionsS.TEXT[word], {"cost": 0}), e("gold", 3)]
		# ---- 蓄放进阶 ----
		"放热": return [e("energy_to_heat_damage", 2, T.ENEMY, "", "消耗全部储能：转为热度并对敌每点 2 伤", {"per": 2})]
		"热能": return [e("heat_to_energy", 1, -1, "", "当前热度转为等量储能")]
		"电流": return [e("flow_energy_or_draw", 2, -1, "", "本回合已补字则储能 +2，否则补 2 字", {})]
		# ---- 普通铜钱 / 镀金 ----
		"投资": return [e("gild_glyph", 3, -1, "", WordDescriptionsS.TEXT[word], {"cost": 3})]
		"利息": return [e("gold_percent_damage", 10, T.ENEMY, "", WordDescriptionsS.TEXT["利息"])]
		"炼金": return [e("gold", 3), e("draw_random", 1)]
		"纯金": return [e("gold", 3)]
		"合金": return [e("alloy", 6, -1, "", "获得 6 持久盾与 2 铜钱", {"gold": 2})]
		"铸币": return [e("mint", 2, -1, "", "获得 2 铜钱，并在原格生成一枚临时【币】", {"gold": 2})]
		"再投资": return [e("gild_glyph", 3, -1, "", WordDescriptionsS.TEXT[word], {"cost": 3}), e("draw_random", 2)]
		"重金": return [e("bounty", 12, T.ENEMY, "", "支付 5 铜钱悬赏，本回合击杀返 12，否则本金不返", {"cost": 5})]
		# ---- 热暴 P3 ----
		"爆冷": return [e("cold_snap", 4, T.ENEMY, "", "4 伤 + 上回合每失 1 生命额外 2 伤，清空热度", {"per": 2})]
		"停火": return [e("ceasefire", 1, -1, "", "本回合未造成敌伤则免疫敌方攻击", {}, -1, "persistent")]
		"放火": return [e("ignite", 3, T.ENEMY, "", "敌方接下来 2 次行动各受 3+施放时热度 伤", {})]
		# ---- 连携 ----
		"电击": return [e("electric_strike", 6, T.ENEMY, "", "造成 6 伤 + 2×储能", {"per": 2})]
		"火力": return [e("fire_power", 6, T.ENEMY, "", "造成 6 伤 + 2×热度", {"per": 2})]
		"合力": return [e("joint_force", 6, -1, "", "获得 6 临挡与 2 储能", {"energy": 2})]
		# ---- 流转 P3 ----
		"清流": return [e("clear_flow", 2, -1, "", "净化全部灼热并补 2 字", {})]
		# ---- 空间新增词 ----
		"重力": return [e("ability_gravity_always", 1, -1, "", "本战每次有效出字后自动全盘向下重力", {}, -1, "persistent")]
		"停电": return [e("blackout", 0, -1, "", "彩蛋：停电，屏幕变黑；拖动连出【开灯】才能恢复", {})]
		"重铸": return [e("recast_board", 0, -1, "", "把盘面上已有的字全部重新替换（己方字回袋重抽，敌方/临时字清除）", {})]
		"再铸": return [e("recast_three", 0, -1, "", "选择三个不同的非固定盘面字（不含施词字），替换为随机临时字（不一定在牌组里）", {})]
		"反转": return [e("reverse_line", 0, -1, "", "选择一整行或一整列，倒转其 4 格（含空格与完整叠层）", {})]
		"合流": return [e("merge_flow", 0, -1, "", "揭示字袋 1 枚 + 弃字堆指定 1 枚，按任选顺序放入两个相邻空格；无相邻空格则不移动", {})]
		"急停": return [e("hard_stop", 0, -1, "", "清空热度并移除本回合溢热生成的灼热【热】（字袋/弃字堆/盘面），立即结束出字阶段", {})]
		"重复": return [e("repeat_word", 0, -1, "", "开启后每回合第一次有效多字词再执行一次其即时效果（不重复消耗字；需支付的照常再付）", {}, -1, "persistent")]
		"防火": return [e("fireproof", 0, -1, "", "本场持续：自己打出的灼热【热】不再扣血（仍占字袋、不被自动净化）", {}, -1, "persistent")]
		"防爆": return [e("blastproof", 0, -1, "", "本场持续：被爆破/爆炸摧毁的己方实体字改为回字袋，每救回 1 枚 +1 持久盾", {}, -1, "persistent")]
		"合资": return [e("joint_funding", 0, -1, "", "本场持续：支付铜钱发动词效时可用 2 储能抵 1 铜钱，允许混合支付", {}, -1, "persistent")]
		"分利": return [e("profit_share", 0, -1, "", "本回合剩余时间，每当实际获得铜钱就额外获得等量储能", {})]
		"停息": return [e("suspend", 0, -1, "", "立即结束出字阶段：清零全部热度，每 1 热度换 2 持久盾；敌人正常行动", {})]
		# ---- 盘面改造（设计负责人直接定义）----
		"转化": return [e("transform_board", 5, T.BOARD_TILE, "", "随机揭示 5 枚实体字，选 1 枚，把一个盘面字定向改成它", {"reveal": 5})]
		"分化": return [e("split_grow", 4, T.BOARD_TILE, "", "删除一个盘面字，在其上下左右的空格各生长一枚可组词的临时字（打出即消耗，不进字袋）", {"max": 4})]
		"强化": return [e("empower_glyph", 0, -1, "", "选择字袋中一个字；本场它被打出时（单字或成词）额外触发其单字效果", {})]
		"炼化": return [e("refine_remove", 3, -1, "", "热度 -3、获得 4 铜钱，并指定一张牌在本场战斗移出循环", {"heat": 3, "gold": 4})]
		"精力": return [e("vigor", 0, -1, "", "本回合每打出一种不同的多字词，下回合基础补字 +1", {}, -1, "persistent")]
	return []
