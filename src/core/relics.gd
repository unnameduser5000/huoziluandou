extends RefCounted
class_name Relics
## 遗物（第一批）：常驻被动，跨战斗生效；按获得顺序记录在 GameState.relics。
## 设计来源：docs/遗物设计清单_2026-10-15.md。本批只接入规则已确认、或可按清单建议取默认值的条目；
## 默认取值与未定项见 docs/遗物接入说明_第一批.md。
##
## 与印章的分工：印章管地图（视野、首领），遗物管战斗；两者互不占位。
## 战斗侧所有钩子都只读 BattleState.relics（开战时从 GameState 复制），测试可直接改它。

## id -> [名称, 说明, 是否需要绑定一枚字]
## 名称以活字印刷作坊里的器物和字为主，少数带一点地府色彩；内部 id 不变（存档、测试都用 id）
const DEFS := {
	"strike": ["刻刀", "带【击】的单字、词，每段攻击伤害 +2", false],
	"breach": ["蚀刻", "每场开局，所有敌人获得 2 层易伤", false],
	"slab": ["压字石", "选一枚字：它在盘面上始终下落；本场额外使用 5 次，用尽后本场移出", true],
	"press": ["对开版", "字盘变为 5×5；开局多补 4 枚字", false],
	"sleep": ["安神香", "休息处治疗额外 +20", false],
	"clean": ["净版布", "回合补字后，若盘面没有污染字，多补 1 枚", false],
	"wheel": ["转轮架", "每回合按 上、下、左、右 轮流让全盘下落", false],
	"powerbank": ["蓄电瓶", "每场开局获得 4 储能", false],
	"fireman": ["火种", "拾取时获得 4 枚【火】", false],
	"fertilizer": ["蔓生墨", "选一枚字：本场它变为临时字，每回合结束向四邻空格繁殖临时字", true],
	"skyfire": ["天火", "打出【流火】时，额外对敌人造成 50 点伤害", false],
	"blitz": ["急就章", "每场第一回合结束后，敌人跳过这一次行动", false],
	"egg": ["字种", "每赢 4 场战斗，获得 1 枚字", false],
	"buckler": ["铜护板", "每场开局获得 4 持久盾", false],
	"barrier": ["纸屏风", "每场开局获得 10 临时格挡（第一回合有效）", false],
	"empty_case": ["空铅盒", "回合结束时，每有一整行为空，获得 2 持久盾", false],
	"stay_wax": ["留字蜡", "打出的字有 5% 概率留在原位", false],
	"amber": ["朱砂印泥", "溢出的治疗量转为持久盾", false],
	"ghost_hand": ["补字鬼手", "每场前 3 枚实际打出的字立即补位", false],
	"cracked_bottle": ["裂墨瓶", "获得的储能翻倍；每回合结束清空储能", false],
	"rotting_fruit": ["褪墨", "每场开局随机一枚字本场变为临时字", false],
	"chaos_dice": ["乱文骨骰", "拾取时重铸字袋：所有字替换为随机字，并额外补 3 枚", false],
	"black_water": ["黑水墨", "事件中封存幽都黑水；部分井、墨、渡口事件出现额外选项", false],
	"life_lantern": ["命灯", "借来的寿火；连续事件中可抵挡一次反噬", false],
	"life_debt": ["寿契", "记着未还的寿债；持有期间，讨债事件可能找上门", false],
	# ---- 第二批（清单其余条目，默认取值见 docs/遗物接入说明_第二批.md）
	"chain": ["连字环", "每次出字后全盘下落；每场开局自动打出盘上已连成的词，补字后接着找，直到连不出（要选目标、要付费的词留给你）", false],
	"question": ["问字签", "每场开局从 3 枚能配词的字里挑 1 枚，作为本场临时字落到盘上", false],
	"goldleaf": ["泥金笔", "拾取时选两枚字，永久镀金", false],
	"moon": ["月字模", "每场开局盘上多一枚临时【月】：它在场时，每次出字后其他字向它聚拢；打出【月】再聚拢一次；下回合消失", false],
	"slot": ["叠字钱", "可以连出三枚相连的相同字，获得 50 铜钱", false],
	"death": ["判官笔", "拾取时获得 1 枚【死】；敌人生命首次降到一半以下时，获得 4 层易伤", false],
	"ruin": ["生死簿", "拾取时获得 1 枚【亡】；每场战斗被击败时，以 20% 最大生命复活一次", false],
	"rubbing": ["复字拓片", "拾取时选一枚字复制，保留镀金和强化", false],
	"midas": ["金字碑", "所有己方字永久镀金，之后拿到的也镀金；一场战斗累计赚到 20 铜钱时，你化为金像，立即死去", false],
	"monkey": ["许愿笺", "拾取时许一个愿：从 3 个有代价的愿望里选 1 个", false],
	"palindrome": ["反字模", "二字词可以倒着连出，发动原词效果；正着本身成词时按正着算", false],
	"binding": ["串字绳", "同一行最左和最右两格视作相邻，可以跨边连词", false],
	"proof": ["校勘尺", "本场每净化 2 枚污染字，随机补 1 字", false],
	# ---- 补充
	"vial": ["还魂墨", "每场开局回复 2 气血", false],
}
## 拾取时要从字袋挑字的遗物：[动作, 挑几枚]。绑定类（压字石、蔓生墨）另见 DEFS 第三项。
const PICK := {"goldleaf": ["gild", 2], "rubbing": ["copy", 1]}
## 许愿笺的愿望：id -> [名称, 说明]
const WISHES := {
	"endless_glyph": ["千字同文", "选一个字：字袋全部变成它，之后拿到的字也都是它；它每场额外使用 +2"],
	"endless_gold": ["点石成金", "获得遗物「金字碑」"],
	"endless_guard": ["固若金汤", "生命上限变为 1；每场开局获得 2 倍于失去上限的持久盾"],
	"endless_life": ["生生不息", "每场开局回复 99 生命，溢出的部分反噬为对自己的伤害"],
}
const WISH_SHOWN := 3
## 档次：1 常见 / 2 少见 / 3 稀有。中赏最多2档，大赏包含3档。
const TIER := {
	"strike": 2, "breach": 2, "slab": 3, "press": 3, "sleep": 1, "clean": 1, "wheel": 2, "powerbank": 1,
	"fireman": 1, "fertilizer": 3, "skyfire": 2, "blitz": 2, "egg": 2, "buckler": 1, "barrier": 1, "empty_case": 2, "stay_wax": 2, "amber": 3, "ghost_hand": 2, "cracked_bottle": 2, "rotting_fruit": 2, "chaos_dice": 3, "black_water": 2, "life_lantern": 2, "life_debt": 2,
	"chain": 3, "question": 2, "goldleaf": 2, "moon": 2, "slot": 2, "death": 1, "ruin": 1, "rubbing": 1,
	"midas": 3, "monkey": 3, "palindrome": 2, "binding": 2, "proof": 1,
	"vial": 1,
}
const PRICE := {1: 35, 2: 50, 3: 70}
const EGG_EVERY := 4
const WHEEL_DIRS := ["up", "down", "left", "right"]
const WHEEL_TEXT := {"up": "上", "down": "下", "left": "左", "right": "右"}
## 事件遗物池：只能由事件发放，不进入商店、许愿、普通奖励等普通遗物池。
const EVENT_ONLY := ["black_water", "life_lantern", "life_debt", "death", "ruin"]
## 效果和配套事件还没做的遗物：不进任何池、不进图鉴；定义保留，旧存档里有也不报错
const HIDDEN := ["black_water", "life_lantern"]
## 一局只生效一次的拾取效果：卖掉再买、再从事件拿到都不重复给（字、重铸、挑字、许愿）
const ONCE_PICKUP := ["fireman", "chaos_dice", "death", "ruin", "goldleaf", "rubbing", "monkey"]
## 连字环不自动打的词效：花铜钱、花储能、买字一类（"要付费的词留给你"）
const CHAIN_PAID_HANDLERS := ["spend_gold_damage", "bounty", "buyback", "buy_bag_solo", "energy_discharge",
	"energy_to_bonus", "energy_to_heat_block", "energy_to_heat_damage", "solo_release"]


static func name_of(id: String) -> String:
	return DEFS[id][0] if DEFS.has(id) else id


static func desc_of(id: String) -> String:
	return BattleBalance.relic_description(id, DEFS[id][1]) if DEFS.has(id) else ""


static func needs_bind(id: String) -> bool:
	return DEFS.has(id) and bool(DEFS[id][2])


static func text(id: String) -> String:
	return "「%s」%s" % [name_of(id), desc_of(id)]


## 普通遗物池：不含事件专属遗物。商店、许愿、普通奖励都从这里取。
static func normal_pool() -> Array:
	return DEFS.keys().filter(func(id): return not EVENT_ONLY.has(id) and not HIDDEN.has(id))


## 图鉴等展示用：去掉还没做完的隐藏遗物
static func visible_ids() -> Array:
	return DEFS.keys().filter(func(id): return not HIDDEN.has(id))


static func is_hidden(id: String) -> bool:
	return HIDDEN.has(id)


## 事件遗物池：只给事件使用；事件可以显式指定，也可用 roll_event_choices。
static func event_pool() -> Array:
	return EVENT_ONLY.filter(func(id): return DEFS.has(id) and not HIDDEN.has(id))


static func is_event_relic(id: String) -> bool:
	return EVENT_ONLY.has(id)


## 还没拥有的遗物里随机挑 n 个；pool 默认普通池，事件要用事件池必须显式传入。
static func roll_choices(owned: Array, rng: RandomNumberGenerator, n := 1, pool := "normal") -> Array:
	var ids: Array = event_pool() if pool == "event" else normal_pool()
	ids = ids.filter(func(id): return not owned.has(id))
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = ids[i]
		ids[i] = ids[j]
		ids[j] = tmp
	return ids.slice(0, mini(n, ids.size()))


## 事件遗物随机池的便捷入口；一般事件给普通遗物时仍用 roll_choices 的默认池。
static func roll_event_choices(owned: Array, rng: RandomNumberGenerator, n := 1) -> Array:
	return roll_choices(owned, rng, n, "event")


static func price(id: String) -> int:
	return PRICE[TIER.get(id, 2)]


static func sell_price(id: String) -> int:
	return int(price(id) / 2)


static func board_size(rules: BattleRules, relics: Array) -> int:
	return maxi(rules.board_size, BattleBalance.i("press_board", 5)) if relics.has("press") else rules.board_size


static func opening_draw(rules: BattleRules, relics: Array) -> int:
	return rules.opening_draw + (BattleBalance.i("press_draw", 4) if relics.has("press") else 0)


## 洗袋之前：蔓生墨母本换成本场临时字；压字石记下绑定的实体。
static func prepare_deck(b: BattleState) -> void:
	if b.relics.has("slab"):
		var inst := _bag_inst(b, int(b.relic_binds.get("slab", -1)))
		if inst != null:
			b.slab_uid = inst.uid
			b.slab_uses = BattleBalance.i("slab_uses", 5)
	if b.relics.has("fertilizer"):
		var src := _bag_inst(b, int(b.relic_binds.get("fertilizer", -1)))
		if src != null and src.uid != b.slab_uid:
			# 永久实体留在 GameState.deck，本场只用它的临时字，打完不会丢字
			var copy := src.clone()
			copy.temporary = true
			copy.temporary_uses = 0
			copy.pinned = false
			b.bag[b.bag.find(src)] = copy
			b.temp_chars.append(copy)
			b.breeders[copy.uid] = true
	if b.relics.has("rotting_fruit"):
		var candidates: Array = b.bag.filter(func(c): return c.is_player_owned() and not c.temporary and c.uid != b.slab_uid)
		if not candidates.is_empty():
			var picked: CharInstance = candidates[b.rng.randi_range(0, candidates.size() - 1)]
			# 同样保留永久实体，只用本场的临时字
			var fruit := picked.clone()
			fruit.temporary = true
			fruit.temporary_uses = 0
			fruit.pinned = false
			fruit.pinned_exhausted = false
			b.bag[b.bag.find(picked)] = fruit
			b.fruit_uid = picked.uid
			b.temp_chars.append(fruit)
	# 许愿笺·千字同文：许愿的字每场额外使用 +2
	var wish_glyph := wish_glyph_id()
	if not wish_glyph.is_empty():
		for inst in b.bag:
			if inst.id() == wish_glyph:
				inst.temporary_uses += BattleBalance.i("wish_glyph_uses", 2)


static func _bag_inst(b: BattleState, uid: int) -> CharInstance:
	if uid < 0:
		return null
	for inst in b.bag:
		if inst.uid == uid:
			return inst
	return null


## 第一回合开始（开局补字、begin_player_turn 之后）
static func on_battle_start(b: BattleState) -> void:
	if b.relics.has("barrier"):
		b.player.add_block(BattleBalance.i("barrier_block", 10))
		b._log("纸屏风：临时格挡 +%d" % BattleBalance.i("barrier_block", 10))
	if b.relics.has("buckler"):
		b.player.add_persistent_block(BattleBalance.i("buckler_block", 4))
		b._log("铜护板：持久盾 +%d" % BattleBalance.i("buckler_block", 4))
	if b.relics.has("vial"):
		var healed := b.heal_player(BattleBalance.i("vial_heal", 2))
		b._log("还魂墨：回复 %d 气血" % healed)
	if b.relics.has("powerbank"):
		b.add_energy(BattleBalance.i("powerbank_energy", 4))
		b._log("蓄电瓶：储能 +%d" % BattleBalance.i("powerbank_energy", 4))
	if b.relics.has("breach"):
		for e in b.alive_enemies():
			e.add_status("vulnerable", BattleBalance.i("breach_stacks", 2))
		b._log("蚀刻：敌人获得 %d 层易伤" % BattleBalance.i("breach_stacks", 2))
	if b.relics.has("blitz"):
		b.blitz_turn = 1
		b._log("急就章：第一回合结束后，敌人跳过这一次行动")
	_battle_start_batch2(b)
	# 第一回合也按获得顺序发动一次重力（开局补字不走 begin_player_turn 的补字分支）
	apply_gravity_relics(b)
	run_chain(b)


## 普通回合补字之后（第一回合不调用）
static func after_turn_draw(b: BattleState) -> void:
	if b.relics.has("clean") and not board_dirty(b):
		if b.draw_to_board(BattleBalance.i("clean_draw", 1)) > 0:
			b._log("净版布：盘面没有污染字，多补 %d 枚" % BattleBalance.i("clean_draw", 1))


## 回合结束：空铅盒按整行空置数给持久盾。
static func on_player_turn_end(b: BattleState) -> void:
	if not b.relics.has("empty_case"):
		return
	var empty_rows := 0
	for y in b.board.size:
		var empty := true
		for x in b.board.size:
			if b.board.get_cell(x, y) != null:
				empty = false
				break
		if empty:
			empty_rows += 1
	if empty_rows <= 0:
		return
	var before := b.player.persistent_block
	b.player.add_persistent_block(empty_rows * 2)
	var gain := b.player.persistent_block - before
	if gain > 0:  # 冷心等不能获得格挡时不报
		b._log("空铅盒：%d 行空置，持久盾 +%d" % [empty_rows, gain])


static func board_dirty(b: BattleState) -> bool:
	for c in b.board.cells:
		if c != null and (not c.pollutions.is_empty() or (c.data != null and c.data.is_pollution)):
			return true
	return false


## 重力类遗物：同一时点按获得顺序依次发动，各自结算一次
static func apply_gravity_relics(b: BattleState) -> void:
	for id in b.relics:
		match id:
			"wheel":
				var dir: String = WHEEL_DIRS[b.wheel_step % WHEEL_DIRS.size()]
				b.wheel_step += 1
				match dir:
					"up": BattleOps.apply_gravity_up(b)
					"down": b.apply_gravity()
					"left": b.apply_gravity_left()
					"right": b.apply_gravity_right()
				b._log("转轮架：全盘向%s压" % WHEEL_TEXT[dir])
			"slab":
				slab_fall(b)
			"chain":
				b.apply_gravity()


## 石板：只有绑定的那一枚往下落，落到本列最低的连续空格
static func slab_fall(b: BattleState) -> void:
	if b.slab_uid < 0:
		return
	var idx := -1
	for i in b.board.cells.size():
		var c: CharInstance = b.board.cells[i]
		if c != null and c.uid == b.slab_uid:
			idx = i
			break
	if idx < 0:
		return
	var inst: CharInstance = b.board.cells[idx]
	if inst.pinned:
		return
	var n := b.board.size
	var x := idx % n
	var y := idx / n
	var ny := y
	while ny + 1 < n and b.board.get_cell(x, ny + 1) == null:
		ny += 1
	if ny != y:
		b.board.set_cell(x, y, null)
		b.board.set_cell(x, ny, inst)


## 消耗石板时调用：还有额外次数就留在原格；用尽后本场移出循环。返回 item.kind
static func consume_slab(b: BattleState, inst: CharInstance) -> String:
	if b.slab_uses > 0:
		b.slab_uses -= 1
		b._log("压字石：【%s】留在盘上（额外次数还剩 %d）" % [inst.glyph(), b.slab_uses])
		return "layer"
	b._log("压字石：【%s】次数用尽，本场移出" % inst.glyph())
	return "exhausted"


## 留字蜡：普通永久字被打出后，5% 概率留在原位。
static func stay_wax(b: BattleState, inst: CharInstance) -> bool:
	if not b.relics.has("stay_wax") or inst == null:
		return false
	if not inst.is_player_owned() or inst.temporary or inst.is_enemy_owned():
		return false
	return b.rng.randf() < 0.05


## 补字鬼手：前 3 枚实际消耗的字立即补位。
static func on_cards_consumed(b: BattleState, consumed: Array) -> void:
	if not b.relics.has("ghost_hand") or b.magic_hand_left <= 0:
		return
	var refill := 0
	for item in consumed:
		if b.magic_hand_left <= 0:
			break
		if bool(item.get("shared", false)):
			continue
		if str(item.get("kind", "")) != "real":
			continue
		var inst: CharInstance = item.get("inst")
		if inst == null or not inst.is_player_owned() or inst.temporary:
			continue
		b.magic_hand_left -= 1
		refill += 1
	if refill > 0:
		var n := b.draw_to_board(refill)
		b.magic_hand_left += refill - n  # 字袋空了没补上的不算次数
		if n > 0:
			b._log("补字鬼手：补 %d 字（本场还剩 %d 次）" % [n, b.magic_hand_left])


## 回合结束（敌人行动前）：繁殖字向四邻空格生成临时字；新生的下回合才繁殖
static func breed(b: BattleState) -> void:
	if b.breeders.is_empty():
		return
	var n := b.board.size
	var parents: Array = []
	for i in b.board.cells.size():
		var c: CharInstance = b.board.cells[i]
		if c != null and b.breeders.has(c.uid):
			parents.append(i)
	var born := 0
	for i in parents:
		var parent: CharInstance = b.board.cells[i]
		var x: int = i % n
		var y: int = i / n
		for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var p: Vector2i = Vector2i(x, y) + d
			if p.x < 0 or p.y < 0 or p.x >= n or p.y >= n or b.board.get_cell(p.x, p.y) != null:
				continue
			var child := CharInstance.new(parent.data)
			child.owner = CharInstance.Owner.PLAYER
			child.temporary = true
			b.board.set_cell(p.x, p.y, child)
			b.temp_chars.append(child)
			b.breeders[child.uid] = true
			born += 1
	if born > 0:
		b._log("蔓生墨：繁殖出 %d 枚临时【%s】" % [born, b.board.cells[parents[0]].glyph() if b.board.cells[parents[0]] != null else ""])


## 一次出字是否带【击】（单字【击】或词里含【击】）
static func play_has_strike(glyphs: Array) -> bool:
	return glyphs.has("击")


static func strike_bonus(b: BattleState, target: Combatant) -> int:
	return BattleBalance.i("strike_damage", 2) if b.strike_active and b.relics.has("strike") and target != null and not target.is_player else 0


## 判官笔：敌人生命**首次**降到一半以下时，追加易伤（每个敌人每场一次）
static func on_enemy_wounded(b: BattleState, e: Combatant) -> void:
	if e == null or e.is_player or not e.is_alive() or not b.relics.has("death"):
		return
	if e.hp * 2 > e.max_hp:
		return
	if bool(e.status_data.get("judge_brush", false)):
		return
	e.status_data["judge_brush"] = true
	var stacks := BattleBalance.i("judge_brush_vulnerable", 4)
	e.add_status("vulnerable", stacks)
	b._log("判官笔：【%s】跌破半血，获得 %d 层易伤" % [e.display_name, stacks])


## 流火结算后
static func on_wash_heat(b: BattleState, target: Combatant) -> Array:
	if not b.relics.has("skyfire"):
		return []
	var e := target if target != null and not target.is_player and target.is_alive() else b.first_alive_enemy()
	if e == null:
		return []
	var real := b.deal_damage(e, BattleBalance.i("skyfire_damage", 50), false)
	b._log("天火：对%s造成 %d 伤害" % [e.display_name, real])
	return ["天火：造成 %d 伤害" % real]


# ---------------------------------------------------------------- 战外钩子

static func rest_bonus() -> int:
	return BattleBalance.i("sleep_heal", 20) if GameState.relics.has("sleep") else 0


## 拾取效果（绑定类在 GameState.bind_relic 里另外处理）
static func on_pickup(id: String) -> void:
	if ONCE_PICKUP.has(id):
		# 一局只给一次：卖掉再买 / 再从事件拿到不重复给；挑字类同时不再弹挑字面板
		if GameState.relic_counters.get(id + "_claimed", false):
			GameState.relic_counters[id + "_repeat"] = true
			return
		GameState.relic_counters[id + "_claimed"] = true
		GameState.relic_counters.erase(id + "_repeat")
	match id:
		"fireman":
			for i in BattleBalance.i("fireman_count", 4):
				_grant_glyph("火", "火种")
		"chaos_dice":
			_rebuild_deck_chaos()
		"death":
			_grant_glyph("死", name_of("death"))
		"ruin":
			_grant_glyph("亡", name_of("ruin"))
		"midas":
			for inst in GameState.deck:
				midas_gild(inst)


## 拾取后还要玩家挑字 / 许愿的遗物
static func needs_setup(id: String) -> bool:
	if id == "monkey":
		return GameState.has_relic("monkey") and not GameState.relic_counters.has("monkey")
	return GameState.has_relic(id) and not pick_spec(id).is_empty() and not pick_candidates(id).is_empty()


## 事件、宝藏等没经过 RelicRewardFlow 的入手：记下来，等能弹窗的界面补上挑字 / 许愿（随存档保存）
static func queue_setup(id: String) -> void:
	if not needs_setup(id):
		return
	var pending: Array = GameState.relic_counters.get("_pending_setup", [])
	if not pending.has(id):
		pending.append(id)
	GameState.relic_counters["_pending_setup"] = pending


## 取出下一件待补挑字 / 许愿的遗物；已经不需要的直接跳过
static func next_pending_setup() -> String:
	var pending: Array = GameState.relic_counters.get("_pending_setup", [])
	while not pending.is_empty():
		var id := str(pending.pop_front())
		if needs_setup(id):
			GameState.relic_counters["_pending_setup"] = pending
			return id
	GameState.relic_counters.erase("_pending_setup")
	return ""


## 看一眼还有没有待补的（不取出）
static func next_pending_peek() -> String:
	for id in GameState.relic_counters.get("_pending_setup", []):
		if needs_setup(str(id)):
			return str(id)
	return ""


static func clear_pending_setup(id: String) -> void:
	var pending: Array = GameState.relic_counters.get("_pending_setup", [])
	pending.erase(id)
	if pending.is_empty():
		GameState.relic_counters.erase("_pending_setup")


## 拾取效果已经在本局给过、这次重复拿到：不再挑字 / 许愿
static func is_repeat_pickup(id: String) -> bool:
	return bool(GameState.relic_counters.get(id + "_repeat", false))


## 金字碑镀金：记下是它镀的，失去金字碑时只退这些
static func midas_gild(inst: CharInstance) -> void:
	if inst.gilded:
		return
	inst.gilded = true
	var uids: Array = GameState.relic_counters.get("midas_gilded", [])
	uids.append(inst.uid)
	GameState.relic_counters["midas_gilded"] = uids


## 失去遗物时撤销持续效果（GameState.remove_relic 在清计数之前调用）
static func on_remove(id: String) -> void:
	match id:
		"midas":
			var uids: Array = GameState.relic_counters.get("midas_gilded", [])
			for inst in GameState.deck:
				if uids.has(inst.uid):
					inst.gilded = false
			GameState.relic_counters.erase("midas_gilded")
			EventBus.deck_changed.emit()


## 乱文骨骰：字袋全部换成随机字，并在原数量上多补 3 枚。
## 旧的实体 uid 会消失，因此绑定类遗物需要重新绑到新字上。
static func _rebuild_deck_chaos() -> void:
	var pool: Array = []
	for cd: CharacterData in Database.characters.values():
		if cd.is_pollution or cd.pending_design or cd.tags.has("enemy") or cd.tags.has("event") or cd.tags.has("彩蛋"):
			continue
		pool.append(cd)
	if pool.is_empty():
		return
	var old_count := GameState.deck.size()
	var bind_ids: Array = GameState.relics.filter(func(id): return needs_bind(id))
	GameState.deck.clear()
	for _i in old_count + 3:
		var cd: CharacterData = pool[GameState.rng.randi_range(0, pool.size() - 1)]
		# 走正常的拿字规则：千字同文改字形、金字碑镀金
		GameState.deck.append(GameState.new_deck_inst(cd))
	GameState.relic_binds.clear()
	for id in bind_ids:
		for inst: CharInstance in GameState.deck:
			if GameState.bind_relic(str(id), inst.id()):
				break
	EventBus.deck_changed.emit()


## 战斗胜利后
static func on_battle_won() -> void:
	if not GameState.relics.has("egg"):
		return
	var n := int(GameState.relic_counters.get("egg", 0)) + 1
	GameState.relic_counters["egg"] = n
	if n % BattleBalance.i("egg_interval", 4) == 0:
		var g := ""
		if GameState.expedition != null:
			g = GameState.expedition.roll_glyph(1, false, GameState.expedition.relic_rng)
		else:
			var pool: Array = Database.characters.values().filter(func(cd): return not cd.is_pollution and not cd.pending_design and cd.rarity <= 2 and not cd.tags.has("enemy") and not cd.tags.has("event") and not cd.tags.has("彩蛋"))
			if not pool.is_empty():
				g = pool[GameState.rng.randi_range(0, pool.size() - 1)].glyph
		if not g.is_empty():
			_grant_glyph(g, "字种")


static func _grant_glyph(g: String, why: String) -> void:
	if GameState.expedition != null:
		GameState.expedition.gain_glyph(g, why)
	else:
		GameState.add_character(Database.get_character_by_glyph(g))


# ---------------------------------------------------------------- 第二批：战斗钩子

## 自动出词不碰的词：会让自己死掉的彩蛋词
const CHAIN_SKIP := ["死亡"]
const CHAIN_MAX := 30


## 开局：盾、回血类先结算，再放【月】、准备问字签
static func _battle_start_batch2(b: BattleState) -> void:
	var wish: Dictionary = GameState.relic_counters.get("monkey", {}) if b.relics.has("monkey") else {}
	match str(wish.get("wish", "")):
		"endless_guard":
			var guard := int(wish.get("guard", 0))
			if guard > 0:
				b.player.add_persistent_block(guard)
				b._log(WISHES.endless_guard[0] + "：持久盾 +%d" % guard)
		"endless_life":
			var amount := BattleBalance.i("wish_life_heal", 99)
			var healed := b.heal_player(amount)
			var overflow := amount - healed
			# 朱砂印泥已经把溢出转成盾；没有朱砂印泥才反噬
			if overflow > 0 and not b.relics.has("amber"):
				var lost := b.player.take_damage(overflow)
				b._log(WISHES.endless_life[0] + "：回复 %d，溢出 %d 反噬，实际失去 %d 生命" % [healed, overflow, lost])
			else:
				b._log(WISHES.endless_life[0] + "：回复 %d 生命" % healed)
	if b.relics.has("moon"):
		_place_moon(b)
	if b.relics.has("question"):
		b.question_choices = question_options(b)
	if b.relics.has("binding"):
		b.board.wrap_rows = true


## 每次成功出字后（含自动出词）：重力类遗物按获得顺序，再向【月】聚拢
static func after_play(b: BattleState) -> void:
	var changed := false
	for id in b.relics:
		match id:
			"slab":
				slab_fall(b)
				changed = true
			"chain":
				b.apply_gravity()
				changed = true
	var moon := moon_pos(b)
	if moon.x >= 0:
		var moved := b.converge_to(moon)
		if moved > 0:
			changed = true
			b._log(name_of("moon") + "：%d 枚字向【月】聚拢" % moved)
	if changed:
		for e in b.alive_enemies():
			EnemyMechanics.update_targets(b, e)


## 回合开局补字之前：上回合的【月】消失
static func on_turn_start(b: BattleState) -> void:
	if b.moon_uid < 0 or b.turn <= b.moon_turn:
		return
	for i in b.board.cells.size():
		var c: CharInstance = b.board.cells[i]
		if c != null and c.uid == b.moon_uid:
			b.board.cells[i] = null
			b.temp_chars.erase(c)
			b._log(name_of("moon") + "：【月】消失")
	b.moon_uid = -1


## 金字碑：本场累计收入达到 20 铜钱就化为金像
static func on_gold_earned(b: BattleState) -> void:
	if b.relics.has("midas") and b.player.is_alive() and b.gold_earned >= BattleBalance.i("midas_gold", 20):
		b.player.hp = 0
		b._log(name_of("midas") + "：本场已赚 %d 铜钱，你化为了金像" % b.gold_earned)


## 校勘尺：本场每净化 2 枚污染字，随机补 1 字
static func on_cleansed(b: BattleState, count: int) -> void:
	if count <= 0 or not b.relics.has("proof"):
		return
	b.cleansed_count += count
	var need := BattleBalance.i("proof_every", 2)
	while b.cleansed_count >= need:
		if b.draw_to_board(1) <= 0:
			return  # 字袋空了：攒着的净化数留到下次能补的时候
		b.cleansed_count -= need
		b._log(name_of("proof") + "：净化满 %d 枚，补 1 字" % need)


## 查不到词时的遗物补充：反字模（二字倒连）、叠字钱（三枚相同字）
static func fallback_word(b: BattleState, glyphs: Array) -> WordData:
	if glyphs.size() == 2 and b.relics.has("palindrome"):
		var reversed := Database.get_word_by_glyphs([glyphs[1], glyphs[0]])
		if reversed != null:
			return reversed
	if glyphs.size() == 3 and b.relics.has("slot") and glyphs[0] == glyphs[1] and glyphs[1] == glyphs[2]:
		return slot_word(glyphs[0])
	return null


static func slot_word(glyph: String) -> WordData:
	var gold := BattleBalance.i("slot_gold", 50)
	var eff := EffectData.new()
	eff.kind = EffectData.Kind.GAIN_GOLD
	eff.handler = "gold"
	eff.amount = gold
	eff.note = "获得 %d 铜钱" % gold
	var w := WordData.new()
	w.id = "relic_slot"
	w.word = glyph.repeat(3)
	var gs: Array[String] = [glyph, glyph, glyph]
	w.glyphs = gs
	w.description = name_of("slot") + "：三连【%s】，获得 %d 铜钱" % [glyph, gold]
	w.effect_summary = w.description
	var list: Array[EffectData] = [eff]
	w.effects = list
	w.effect_handler_id = "gold"
	w.implemented = true
	return w


# ---- 月

static func _place_moon(b: BattleState) -> void:
	var cd := Database.get_character_by_glyph("月")
	var empties: Array = b.board.empty_indices()
	if cd == null or empties.is_empty():
		return
	var inst := CharInstance.new(cd)
	inst.owner = CharInstance.Owner.PLAYER
	inst.temporary = true
	var pos: Vector2i = empties[b.rng.randi_range(0, empties.size() - 1)]
	b.board.set_xy(pos, inst)
	b.temp_chars.append(inst)
	b.moon_uid = inst.uid
	b.moon_turn = b.turn
	b._log(name_of("moon") + "：盘上出现一枚【月】")


static func moon_pos(b: BattleState) -> Vector2i:
	if b.moon_uid < 0:
		return Vector2i(-1, -1)
	for i in b.board.cells.size():
		var c: CharInstance = b.board.cells[i]
		if c != null and c.uid == b.moon_uid:
			return b.board.to_xy(i)
	return Vector2i(-1, -1)


# ---- 问字签

## 三枚候选：优先能和盘上字组成二字词的字
static func question_options(b: BattleState) -> Array:
	var allowed := {}
	for cd in Database.characters.values():
		if not cd.is_pollution and not cd.pending_design and not cd.tags.has("enemy") and not cd.tags.has("彩蛋") and cd.rarity <= 3:
			allowed[cd.glyph] = true
	var on_board := {}
	for c in b.board.cells:
		if c != null:
			on_board[c.glyph()] = true
	var fits: Array = []
	for w in Database.words.values():
		if not w.implemented or w.glyphs.size() != 2:
			continue
		for i in 2:
			var other: String = w.glyphs[1 - i]
			if on_board.has(w.glyphs[i]) and allowed.has(other) and not fits.has(other):
				fits.append(other)
	var rest: Array = allowed.keys().filter(func(g): return not fits.has(g))
	var out: Array = []
	for list in [fits, rest]:
		while out.size() < 3 and not list.is_empty():
			out.append(list.pop_at(b.rng.randi_range(0, list.size() - 1)))
	return out


## 选中的字作为本场临时字落到随机空格；盘满就放到袋顶，下一次补字先出它
static func take_question(b: BattleState, glyph: String) -> bool:
	if not b.question_choices.has(glyph):
		return false
	b.question_choices.clear()
	var inst := CharInstance.new(Database.get_character_by_glyph(glyph))
	inst.owner = CharInstance.Owner.PLAYER
	inst.temporary = true
	b.temp_chars.append(inst)
	var empties: Array = b.board.empty_indices()
	if empties.is_empty():
		b.bag.push_back(inst)
	else:
		b.board.set_xy(empties[b.rng.randi_range(0, empties.size() - 1)], inst)
	b._log(name_of("question") + "：本场加入临时【%s】" % glyph)
	return true


# ---- 连字环

## 开局自动出词：长词优先，同长按左上起点；每打一个，补回腾空的格子再找
static func run_chain(b: BattleState) -> void:
	if not b.relics.has("chain"):
		return
	for step in CHAIN_MAX:
		if b.formation_mode:
			return  # 合击队列里的词要玩家自己接着结算
		var found := chain_words(b)
		if found.is_empty():
			return
		found.sort_custom(func(x, y):
			if x.path.size() != y.path.size():
				return x.path.size() > y.path.size()
			return b.board.from_xy(x.path[0]) < b.board.from_xy(y.path[0]))
		var played := false
		var empty_before: int = b.board.empty_indices().size()
		for f in found:
			if b.try_play(f.path).get("ok", false):
				b._log(name_of("chain") + "：自动打出【%s】" % f.word.word)
				played = true
				break
		if not played or b.is_over():
			return
		var refill: int = b.board.empty_indices().size() - empty_before
		if refill > 0:
			b.draw_to_board(refill)


## 盘上当前能自动打出的词：[{word, path}]，同一个词只留一条路径
static func chain_words(b: BattleState) -> Array:
	var trie := {}
	for w in Database.words.values():
		if not _chain_ok(w):
			continue
		var node: Dictionary = trie
		for g in w.glyphs:
			if not node.has(g):
				node[g] = {}
			node = node[g]
		node["#"] = w
	var found: Array = []
	var seen := {}
	for i in b.board.cells.size():
		var c: CharInstance = b.board.cells[i]
		if c != null and trie.has(c.glyph()):
			_chain_dfs(b, [b.board.to_xy(i)], trie[c.glyph()], found, seen)
	return found


## 要选目标、要付费、要额外交互的词不自动打
static func _chain_ok(w: WordData) -> bool:
	if not w.implemented or w.glyphs.size() < 2 or CHAIN_SKIP.has(w.word) or not w.interaction.is_empty():
		return false
	if not BattleState.has_required_target(w.requires_target, {}):
		return false
	for eff in w.effects:
		if eff.args.keys().any(func(k): return str(k).contains("cost")) or CHAIN_PAID_HANDLERS.has(eff.handler):
			return false
		if eff.handler == "ability_shared_attack":
			return false  # 合击会把后面的词排进队列而不结算
		if eff.target in [EffectData.Target.BOARD_TILE, EffectData.Target.BOARD_ROW, EffectData.Target.BOARD_2X2, EffectData.Target.BOARD_3X3, EffectData.Target.EMPTY_TILE, EffectData.Target.DISCARD_GLYPH, EffectData.Target.BAG_GLYPH, EffectData.Target.ENEMY_GLYPH]:
			return false
	return true


static func _chain_dfs(b: BattleState, path: Array, node: Dictionary, found: Array, seen: Dictionary) -> void:
	if node.has("#") and not seen.has(node["#"].id):
		seen[node["#"].id] = true
		found.append({"word": node["#"], "path": path.duplicate()})
	for nxt in b.board.path_extensions(path):
		if path.has(nxt) or not b.board.in_bounds(nxt.x, nxt.y):
			continue
		var c: CharInstance = b.board.get_xy(nxt)
		if c == null or not node.has(c.glyph()) or not b.board.valid_path(path + [nxt]):
			continue
		_chain_dfs(b, path + [nxt], node[c.glyph()], found, seen)


# ---------------------------------------------------------------- 第二批：战外

## 拾取时要挑字的遗物：返回 [动作, 枚数]；不需要时为空
static func pick_spec(id: String) -> Array:
	return [] if is_repeat_pickup(id) else PICK.get(id, [])


## 泥金笔 / 复字拓片：对字袋里一枚该字形的永久实体执行动作；镀金跳过已镀金的
static func apply_pick(id: String, glyph_id: String) -> bool:
	var spec := pick_spec(id)
	if spec.is_empty():
		return false
	for inst in GameState.deck:
		if inst.id() != glyph_id or inst.temporary:
			continue
		match str(spec[0]):
			"gild":
				if inst.gilded:
					continue
				inst.gilded = true
				return true
			"copy":
				var copy: CharInstance = inst.clone()
				copy.temporary = false
				copy.temporary_uses = 0
				copy.pinned = false
				GameState.deck.append(copy)
				EventBus.deck_changed.emit()
				return true
	return false


## 字袋里还能被该遗物挑中的字形 -> 枚数
static func pick_candidates(id: String) -> Dictionary:
	var spec := pick_spec(id)
	var out := {}
	for inst in GameState.deck:
		if inst.temporary or (not spec.is_empty() and spec[0] == "gild" and inst.gilded):
			continue
		out[inst.id()] = int(out.get(inst.id(), 0)) + 1
	return out


## 许愿笺：可许的愿望（已有金字碑就不出「点石成金」），随机给 3 个
static func wish_options(rng: RandomNumberGenerator) -> Array:
	var pool: Array = WISHES.keys().filter(func(w): return w != "endless_gold" or not GameState.has_relic("midas"))
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	return pool.slice(0, mini(WISH_SHOWN, pool.size()))


static func wish_text(wish: String) -> String:
	return "「%s」%s" % [WISHES[wish][0], WISHES[wish][1]] if WISHES.has(wish) else ""


## 许愿（一张愿帖只许一次）；用不完的字要带上选中的字形 id
static func grant_wish(wish: String, glyph_id := "") -> bool:
	if not GameState.has_relic("monkey") or not WISHES.has(wish) or GameState.relic_counters.has("monkey"):
		return false
	var record := {"wish": wish}
	match wish:
		"endless_glyph":
			var cd := Database.get_character(glyph_id)
			if cd == null:
				return false
			record["glyph"] = cd.id
			for inst in GameState.deck:
				inst.data = cd
				inst.fusion.clear()
			EventBus.deck_changed.emit()
		"endless_gold":
			GameState.relic_counters["monkey"] = record
			GameState.add_relic("midas")
			return true
		"endless_guard":
			var lost := maxi(0, GameState.player_max_hp - 1)
			record["guard"] = lost * BattleBalance.i("wish_guard_mult", 2)
			GameState.player_max_hp = 1
			GameState.player_hp = 1
			EventBus.hp_changed.emit(GameState.player_hp, GameState.player_max_hp)
	GameState.relic_counters["monkey"] = record
	return true


static func wish_glyph_id() -> String:
	if not GameState.relics.has("monkey"):
		return ""
	return str(GameState.relic_counters.get("monkey", {}).get("glyph", ""))


## 之后拿到的字：千字同文把它换成许愿的字
static func redirect_glyph(cd: CharacterData) -> CharacterData:
	if cd == null or cd.is_pollution:
		return cd  # 污染字照样是污染字，不会被许愿洗白
	var id := wish_glyph_id()
	if id.is_empty() or Database.get_character(id) == null:
		return cd
	return Database.get_character(id)
