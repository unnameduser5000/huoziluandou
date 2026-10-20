extends RefCounted
class_name BattleState
signal enemy_acting(enemy: Combatant, move: EnemyMoveData)
## 单场战斗的完整逻辑状态（V0.2）。
## UI 只读取它并渲染；EffectHandlers 通过它公开的方法改状态。

var rules: BattleRules
var player: Combatant
var enemies: Array = []        ## Array[Combatant]
var board: BoardState
var bag: Array = []            ## 抽字袋
var discard: Array = []        ## 弃字堆
var turn: int = 0
var log: Array[String] = []
var rng := RandomNumberGenerator.new()
var visual_rng := RandomNumberGenerator.new()   ## 仅特效/台词，不消耗战斗 RNG

# --- 本场持续能力 / 下一词标记 ---
var abilities: Dictionary = {}
# --- 每回合统计 ---
var words_played_this_turn: Array = []
var attack_words_this_turn: int = 0
var drawn_this_turn: int = 0
var consumed_this_turn: Array = []
var next_draw_penalty: int = 0
var manual_draw_pending: int = 0   ## 精心：本回合待玩家从字袋定向选字的枚数
var base_draw_penalty: int = 0
var last_attack_word: WordData = null
var last_attack_glyphs: Array = []
var last_attack_effects: Array = []
var last_attack_target: int = 0
var last_attack_target_data: Dictionary = {}
var last_attack_path: Array = []
# --- 本场临时/收编 ---
var temp_chars: Array = []      ## 敌人注入 + 自我灼热，战后清理
var captured_chars: Array = []  ## 收购得到的实体字，战后加入永久字袋
var damage_taken_last_turn: int = 0
var damage_taken_this_turn: int = 0
var damage_dealt_this_turn: int = 0
var gold_earned: int = 0
var gold_earned_this_turn: int = 0 ## 利：本回合实际获得过铜钱，不受随后支出影响
var zero_effect_count: int = 0
var pending_place: CharInstance = null
var pending_choice: Dictionary = {} ## 多阶段选字的施词身份快照
var pending_reveal: Array = []   ## 转化等：已从字袋取出待选的实体字
var reconnect_pending: Array = [] ## 重连：暂存原实体与原格 [{inst, pos, return_turn}]
var empowered_glyphs: Dictionary = {}   ## 强化：本场额外触发单字效果的字
var removed_this_battle: Array = []     ## 炼化：本场移出循环的牌
var pierce_once := false                ## 墨途远征「重击」：本场第一次攻击无视护盾
var ruin_revived := false               ## 生死簿：本场已经用过的复活（每场一次）
var enemy_skip_turns := 0               ## 墨途远征「停火」：敌方跳过的行动次数
## 遗物（src/core/relics.gd）：开战时从 GameState 复制，按获得顺序
var relics: Array = []
var relic_binds: Dictionary = {}        ## 遗物 id -> 永久实体 uid
var wheel_step := 0                     ## 转轮架：已转过几次
var blitz_turn := 0                     ## 急就章：这一回合结束时敌人跳过行动（0 = 不跳）
var slab_uid := -1                      ## 压字石绑定的实体
var slab_uses := 0                      ## 压字石本场剩余额外次数
var magic_hand_left := 3                ## 补字鬼手：本场还能补位的字数
var fruit_uid := -1                      ## 褪墨：本场被替换为临时副本的永久实体
var moon_uid := -1                      ## 月字模：本场那枚【月】
var moon_turn := 0                      ## 月字模：放下它的回合，下回合消失
var cleansed_count := 0                 ## 校勘尺：攒着的净化数
var question_choices: Array = []        ## 问字签：开局待选的三枚字（选完清空）
var breeders: Dictionary = {}           ## 蔓生墨：有繁殖资格的临时字 uid
var strike_active := false              ## 打击增强：当前出字带【击】
var bounty_paid: bool = false
var bounty_reward: int = 0
var words_played_all: Array = []
signal play_resolving(play: Dictionary)
var last_played_glyphs: Array = []   ## 上一个出字的字形序列（供【再】重复）
var last_played_word: WordData = null  ## 上一个打出的词（供【回放】）
var last_played_effects: Array = []
var last_played_consumed: Array = []   ## 上一个词用过的字+原格 [{inst, pos}]（供【回放】放回盘面）
var rapid_cells: Array = []              ## 急速：打出“急速”时占用的格子（下次多字词优先回填）
var blackout_requested: bool = false   ## 停电彩蛋：请求黑屏
var end_turn_requested: bool = false    ## 急停：请求立即结束出字阶段
var repeat_armed: bool = false          ## 重复：本回合第一次多字词是否可重演
var formation_mode: bool = false        ## 合击：结阵（只登记不结算）
var formation_queue: Array = []         ## 已登记待结算的词
var reserved_cells: Array = []          ## 结阵中已被占用（锁定）的非【击】格
var repeat_rotate_tile: Vector2i = Vector2i(-1, -1)  ## 转速：连续旋转的 2×2 锚点
var repeat_rotate_count: int = 0
var last_energy_spent: int = 0          ## 复电：上一条储能消耗词的花费
var last_energy_refunded: int = 0       ## 同笔消费的已退款额（含单字复）
var last_energy_half_claimed: bool = false
var strengthen_plays: int = 0          ## 加强：本场实际出词次数，不由效果重演递增
var serial_words: int = 0             ## 连载：本场有效出词次数（允许重复词）
var temporary_heat_capacity: int = 0   ## 载：只撤销本回合额外增加的热容
var flow_speed_rows: Dictionary = {}    ## 流速：行号 -> 本回合剩余补词次数，重复施放累加
var last_shift_row: int = -1             ## 电力：最近一次行位移
var last_shift_dir: int = 0
var _energy_regen_last_turn: int = -1    ## 回能：每回合最多发放一次，重施只刷新持续时间
var overdo_count: int = 0                ## 过分：本场已打出【过分】的次数（伤害随次数递增）
var _attack_sequence_depth := 0
var _attack_sequence_bonus: Dictionary = {}
var _resolving_play := false
var monster_net_energy := 0
var monster_paid := false
var monster_entered: Dictionary = {}
var _energy_spend_turn := -1
var achievement: RefCounted = null

func _init(p_rules: BattleRules) -> void:
	rules = p_rules
	board = BoardState.new(p_rules.board_size)

func start(deck: Array, enemy_datas: Array, seed_value: int = -1, track_achievements := false) -> void:
	GameState.battle_sequence += 1
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	visual_rng.seed = rng.seed ^ 0x9E3779B9
	bag.clear()
	discard.clear()
	temp_chars.clear()
	captured_chars.clear()
	abilities.clear()
	empowered_glyphs.clear()
	removed_this_battle.clear()
	pierce_once = false
	ruin_revived = false
	enemy_skip_turns = 0
	blackout_requested = false
	end_turn_requested = false
	overdo_count = 0
	strengthen_plays = 0
	serial_words = 0
	last_energy_spent = 0
	last_energy_refunded = 0
	last_energy_half_claimed = false
	repeat_armed = false
	formation_mode = false
	formation_queue.clear()
	reserved_cells.clear()
	last_played_glyphs.clear()
	last_played_consumed.clear()
	last_played_word = null
	last_played_effects.clear()
	last_attack_word = null
	last_attack_effects.clear()
	last_attack_glyphs.clear()
	last_attack_target_data.clear()
	last_attack_path.clear()
	words_played_all.clear()
	pending_reveal.clear()
	pending_choice.clear()
	reconnect_pending.clear()
	gold_earned = 0
	gold_earned_this_turn = 0
	damage_taken_this_turn = 0
	damage_taken_last_turn = 0
	base_draw_penalty = 0
	next_draw_penalty = 0
	manual_draw_pending = 0
	flow_speed_rows.clear()
	temporary_heat_capacity = 0
	_energy_regen_last_turn = -1
	rapid_cells.clear()
	_attack_sequence_depth = 0
	_attack_sequence_bonus.clear()
	_resolving_play = false
	relics = GameState.relics.duplicate()
	relic_binds = GameState.relic_binds.duplicate()
	wheel_step = 0
	blitz_turn = 0
	slab_uid = -1
	slab_uses = 0
	magic_hand_left = 3
	fruit_uid = -1
	moon_uid = -1
	moon_turn = 0
	cleansed_count = 0
	question_choices.clear()
	breeders.clear()
	strike_active = false
	board = BoardState.new(Relics.board_size(rules, relics))
	for c in deck:
		c.owner = CharInstance.Owner.PLAYER
		c.temporary_uses = 0
		c.fusion.clear()
		c.pinned = false
		c.pinned_exhausted = false
		c.refined = false
		bag.append(c)
	Relics.prepare_deck(self)
	_shuffle(bag)
	player = Combatant.new("玩家", GameState.player_max_hp, true)
	player.hp = GameState.player_hp
	player.permanent_damage_reduction = GameState.permanent_damage_reduction
	player.heat_capacity = rules.heat_capacity
	enemies.clear()
	for ed in enemy_datas:
		var e := Combatant.new(ed.name, ed.max_hp, false)
		e.enemy_data = ed
		e.add_block(ed.initial_block)
		enemies.append(e)
	turn = 0
	achievement = Achievements.watch_battle(self) if track_achievements else null
	draw_to_board(Relics.opening_draw(rules, relics))
	begin_player_turn(false, false)
	Relics.on_battle_start(self)
	EnemyMechanics.begin_phase(self)

func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

func alive_enemies() -> Array:
	return enemies.filter(func(e): return e.is_alive())

func first_alive_enemy() -> Combatant:
	for e in enemies:
		if e.is_alive():
			return e
	return null

func is_over() -> bool:
	_check_revive()
	return not player.is_alive() or first_alive_enemy() == null

## 反死亡：本局存着的复活机会，倒下时满血站起来（也能抵消死亡、金像这类特殊死亡）
## 生死簿：每场战斗一次，倒下时以「遗物参数·生死簿：复活保留生命百分比」复活（先用本场的，留住反死亡次数）
func _check_revive() -> void:
	if player == null or player.is_alive():
		return
	if relics.has("ruin") and not ruin_revived:
		ruin_revived = true
		var percent := BattleBalance.i("ruin_revive_percent", 20)
		player.hp = maxi(1, int(round(player.max_hp * percent / 100.0)))
		_log("生死簿：以 %d 气血复活" % player.hp)
		return
	if GameState.revive_charges <= 0:
		return
	GameState.revive_charges -= 1
	player.hp = player.max_hp
	_log("反死亡：满血复活")

func is_victory() -> bool:
	_check_revive()
	return player.is_alive() and first_alive_enemy() == null


# ---------------------------------------------------------------- 补字

func remove_from_battle_glyph(glyph: String) -> CharInstance:
	if glyph.is_empty():
		return null
	for arr in [bag, discard]:
		for i in arr.size():
			var inst: CharInstance = arr[i]
			if inst.glyph() == glyph:
				arr.remove_at(i)
				removed_this_battle.append(inst)
				return inst
	for i in board.cells.size():
		var c: CharInstance = board.cells[i]
		if c != null and not c.pinned and c.glyph() == glyph and c.is_player_owned():
			board.cells[i] = null
			removed_this_battle.append(c)
			return c
	return null


## 本场还在循环中的牌（字袋 + 弃字堆）的字形计数，供炼化选牌。

## 消耗记录是历史；只允许回收仍在弃字堆的己方实体。
func recoverable_consumed() -> Array:
	return consumed_this_turn.filter(func(inst): return inst.is_player_owned() and not inst.temporary and discard.has(inst) and not board.cells.has(inst) and not bag.has(inst))


func recoverable_card(target: Dictionary) -> CharInstance:
	if target.has("discard_uid"):
		for inst in recoverable_consumed():
			if inst.uid == int(target.discard_uid):
				return inst
		return null
	var index := int(target.get("discard_index", consumed_this_turn.size() - 1))
	if index < 0 or index >= consumed_this_turn.size():
		return null
	var inst: CharInstance = consumed_this_turn[index]
	return inst if recoverable_consumed().has(inst) else null


## 统一真实补字统计与超速；额外字只有成功落盘才升温。
func record_draw(count: int, requested: int = -1, excluded: Array = []) -> int:
	if count <= 0:
		return 0
	drawn_this_turn += count
	if not has_ability("next_double_draw"):
		return count
	var bonus := mini(requested if requested >= 0 else count, ability_value("next_double_draw"))
	abilities.erase("next_double_draw")
	var extra := BattleOps.draw_to_board(self, bonus, excluded)
	if extra > 0:
		add_heat(extra * BattleBalance.i("double_draw_heat", 1))
		_log("超速：额外补 %d 字，热度 +%d" % [extra, extra * BattleBalance.i("double_draw_heat", 1)])
	return count + extra
## 热心：热度变化时同步生命（每 +1 回 1 血，每 -1 扣 1 血）。
func _warm_heart_sync(old_heat: int) -> void:
	if not has_ability("warm_heart"):
		return
	var delta: int = player.heat - old_heat
	if delta == 0:
		return
	if delta > 0:
		var warm_heal := delta * BattleBalance.i("warm_heal", 1) * passive_multiplier("热心")
		heal_player(warm_heal)
		_log("热心：热度 +%d，回复 %d 生命" % [delta, warm_heal])
	else:
		var real := player.take_damage(-delta * BattleBalance.i("warm_damage", 1))
		_log("热心：热度 %d，失去 %d 生命" % [delta, real])


## 统一清空热度（含热心）。
func clear_heat() -> void:
	add_heat(-player.heat)


func add_heat(amount: int) -> int:
	var old_heat := player.heat
	var ret := _add_heat_inner(amount)
	_warm_heart_sync(old_heat)
	if achievement != null:
		achievement.cooled(maxi(0, old_heat - player.heat))
		achievement.sample()
	return ret


func _add_heat_inner(amount: int) -> int:
	# 过冷：下一次获得的热度改为持久盾，且不生成过热污染
	if amount > 0 and has_ability("next_heat_to_block"):
		var mult := ability_value("next_heat_to_block", BattleBalance.i("overcool_mult", 2))
		abilities.erase("next_heat_to_block")
		player.add_persistent_block(amount * mult)
		_log("过冷：%d 点热度转为 %d 持久盾" % [amount, amount * mult])
		return player.heat
	player.add_heat(amount)
	if amount > 0 and player.heat > player.heat_capacity:
		var overflow: int = player.heat - player.heat_capacity
		# 只在“主动升温超过上限”时结算一次溢出（对应当前热量的超出量）
		var already: int = int(abilities.get("_overflow_paid", 0))
		var new_overflow: int = max(0, overflow - already)
		abilities["_overflow_paid"] = overflow
		# 蓄冷：抵消本应生成的污染【热】
		if new_overflow > 0 and has_ability("overheat_shield"):
			var saved := mini(ability_value("overheat_shield", BattleBalance.i("overheat_block_cap", 4)), new_overflow)
			new_overflow -= saved
			abilities.erase("overheat_shield")
			_log("蓄冷：抵消 %d 点过热污染" % saved)
		if new_overflow > 0:
			spawn_scorch_into_bag(new_overflow)
			if has_ability("heat_pollution_damage"):
				var fire_damage := BattleBalance.i("overheat_damage", 5) * ability_value("heat_pollution_damage") * new_overflow * passive_multiplier("火热", first_alive_enemy() != null)
				deal_damage(first_alive_enemy(), fire_damage, false)
				_log("火热：%d 枚污染【热】造成 %d 伤" % [new_overflow, fire_damage])
			if has_ability("electric_overload"):
				var overload_mult := ability_value("electric_overload") * passive_multiplier("电流过载")
				add_energy(BattleBalance.i("overload_energy", 1) * new_overflow * overload_mult)
				deal_damage(first_alive_enemy(), BattleBalance.i("overload_damage", 3) * new_overflow * overload_mult, false)
				_log("电流过载：溢热 %d，储能 +%d，造成 %d 伤" % [new_overflow, BattleBalance.i("overload_energy", 1) * new_overflow * overload_mult, BattleBalance.i("overload_damage", 3) * new_overflow * overload_mult])
			if has_ability("heat_overload_bonus"):
				abilities["next_draw_bonus"] = int(abilities.get("next_draw_bonus", 0)) + ability_value("heat_overload_bonus", 2) * passive_multiplier("过热")
				abilities.erase("heat_overload_bonus")  # 每回合首次
			_log("过热：向字袋塞入 %d 枚灼热【热】" % new_overflow)
	if amount <= 0:
		abilities["_overflow_paid"] = mini(ability_value("_overflow_paid"), maxi(0, player.heat - player.heat_capacity))
	return player.heat

## refund = 返还已花掉的储能：不吃裂墨瓶翻倍，免得返还比花掉的还多
func add_energy(amount: int, refund := false) -> void:
	if refund:
		player.add_energy(amount)
		return
	if amount > 0 and has_ability("energy_gain_once"):
		var bonus := ability_value("energy_gain_once")
		abilities.erase("energy_gain_once")
		amount += bonus
		_log("能：本次额外获得 %d 储能" % bonus)
	if amount > 0 and relics.has("cracked_bottle"):
		amount *= 2
		_log("裂墨瓶：本次储能翻倍（+%d）" % amount)
	player.add_energy(amount)
	if achievement != null: achievement.sample()


## 玩家治疗；朱砂印泥把溢出部分转成持久盾。
func heal_player(amount: int) -> int:
	var value := maxi(0, amount)
	var before := player.hp
	player.heal(value)
	var healed := player.hp - before
	if relics.has("amber") and value > healed:
		var shield_before := player.persistent_block
		player.add_persistent_block(value - healed)
		var gained := player.persistent_block - shield_before
		if gained > 0:  # 冷心等不能获得格挡时什么也不给，也不报
			_log("朱砂印泥：溢出治疗 %d 转为持久盾" % gained)
	return healed


## 消耗储能（电能：每累计消耗 2 点，随机空格生成临时【电】）
func spend_energy(amount: int) -> void:
	var spent := mini(maxi(amount, 0), player.energy)
	if spent <= 0:
		return
	player.energy -= spent
	if achievement != null: achievement.spent_energy(spent)
	monster_net_energy += spent
	_energy_spend_turn = turn
	last_energy_spent = spent
	last_energy_refunded = 0
	last_energy_half_claimed = false
	if has_ability("electric_material"):
		abilities["_energy_spent"] = int(abilities.get("_energy_spent", 0)) + spent
		while int(abilities.get("_energy_spent", 0)) >= BattleBalance.i("energy_spawn_step", 2):
			abilities["_energy_spent"] = int(abilities["_energy_spent"]) - BattleBalance.i("energy_spawn_step", 2)
			_spawn_temp_dian()
	if has_ability("energy_refund_once"):
		var refund := mini(spent, ability_value("energy_refund_once"))
		abilities.erase("energy_refund_once")
		add_energy(refund, true)
		last_energy_refunded += refund
		if _energy_spend_turn == turn:
			monster_net_energy -= refund
		_log("复：本次实际消耗 %d 储能，返还 %d（仅一次）" % [spent, refund])

func refund_half_energy() -> int:
	if last_energy_spent <= 0 or last_energy_half_claimed:
		return 0
	last_energy_half_claimed = true
	var refund := maxi(0, int(ceil(last_energy_spent / BattleBalance.f("refund_divisor", 2.0))) - last_energy_refunded)
	last_energy_refunded += refund
	if _energy_spend_turn == turn:
		monster_net_energy -= refund
	add_energy(refund, true)
	return refund

## 只有离开盘面后重新补入才刷新精炼；普通移动始终使用 board.set_xy。
## 把刚打出的格子按原顺序补回（来源仍是字袋）；返回实际补了几枚。
func refill_played_cells(consumed: Array, count: int) -> int:
	if count <= 0:
		return 0
	var targets: Array = []
	var seen := {}
	for item in consumed:
		var pos: Vector2i = item.pos
		if item.kind != "real" or item.get("shared", false) or seen.has(pos):
			continue
		if board.get_xy(pos) != null:
			continue
		seen[pos] = true
		targets.append(pos)
	var placed := 0
	for pos in targets:
		if placed >= count:
			break
		ensure_bag()
		if bag.is_empty():
			break
		place_from_pool(pos, bag.pop_back())
		placed += 1
	if placed > 0:
		record_draw(placed, targets.size())
	return placed


func place_from_pool(pos: Vector2i, inst: CharInstance, counts_for_monster := true) -> void:
	if inst.refined and not inst.temporary and not board.cells.has(inst):
		inst.temporary_uses = maxi(inst.temporary_uses, BattleBalance.i("refined_layers", 2))
	board.set_xy(pos, inst)
	if counts_for_monster and inst.is_player_owned() and not inst.temporary:
		monster_entered[inst.uid] = true

## 超能力只消耗于实际能够产生收益的持续能力，不被普通出词空耗。
## 超能力：本回合内所有能力收益结算两遍（不消耗，回合结束清空；能力启用时的入场数值不翻倍）
func passive_multiplier(label: String, has_reward: bool = true) -> int:
	if not has_reward or not has_ability("double_next"):
		return 1
	_log("超能力：%s收益结算两遍" % label)
	return BattleBalance.i("passive_multiplier", 2)


func _spawn_temp_dian() -> void:
	var empties: Array = board.empty_indices()
	if empties.is_empty():
		return
	var cd: CharacterData = Database.get_character_by_glyph("电")
	if cd == null:
		return
	var count := ability_value("electric_material") * passive_multiplier("电能")
	for i in count:
		empties = board.empty_indices()
		if empties.is_empty():
			break
		var inst := CharInstance.new(cd)
		inst.temporary = true
		var pos: Vector2i = empties[rng.randi_range(0, empties.size() - 1)]
		board.set_xy(pos, inst)
		temp_chars.append(inst)
		_log("电能：消耗储能，随机空格生成临时【电】")


## 战内获得铜钱（受安全阀限制）。返回实际获得。

func earn_gold(amount: int) -> int:
	var allowed: int = amount
	# gold_cap_per_battle <= 0 表示本场铜钱收入不限
	if rules.gold_cap_per_battle > 0 and gold_earned + amount > rules.gold_cap_per_battle:
		allowed = max(0, rules.gold_cap_per_battle - gold_earned)
	gold_earned += allowed
	gold_earned_this_turn += maxi(0, allowed)
	GameState.add_gold(allowed)
	if allowed > 0 and has_ability("profit_share"):
		var energy_gain := BattleBalance.i("profit_energy", 1) * allowed * passive_multiplier("分利")
		add_energy(energy_gain)
		_log("分利：获得 %d 铜钱，同时储能 +%d" % [allowed, energy_gain])
	Relics.on_gold_earned(self)
	return allowed


# ---------------------------------------------------------------- 能力

func has_ability(id: String) -> bool:
	return abilities.has(id)

func enable_ability(id: String, value: int = 1) -> void:
	abilities[id] = value
	if id == "next_diagonal":
		board.diagonal_steps_allowed = value
	elif id == "next_gap":
		board.gap_steps_allowed = 1
	elif id == "next_free_word":
		board.free_word_link = true

## 累计收益与启用开关分开处理，避免重复施放覆盖，也避免已累加值再次翻倍。
func add_ability(id: String, amount: int = 1) -> void:
	enable_ability(id, ability_value(id) + amount)

func ability_value(id: String, default_value: int = 0) -> int:
	return int(abilities.get(id, default_value))

## 加只增大后续单字的首项直接收益；不修改共享资源、费用或持续标记。
func take_solo_gain_bonus(ctx: Dictionary) -> int:
	if not has_ability("solo_gain_once") or ctx.get("word") != null or (ctx.get("glyphs", []) as Array).size() != 1:
		return 0
	for item in ctx.get("consumed", []):
		if item.inst.word_only:
			return 0
	var bonus := ability_value("solo_gain_once")
	abilities.erase("solo_gain_once")
	_log("加：本次单字首项直接收益 +%d（仅一次）" % bonus)
	return bonus


# ---------------------------------------------------------------- 伤害

## 多段/群体攻击共享“下一次攻击”强化，按段应用，整次攻击只消费一次。
func begin_attack_sequence() -> void:
	if _attack_sequence_depth == 0 and achievement != null: achievement.attack_begin()
	_attack_sequence_depth += 1


func end_attack_sequence() -> void:
	_attack_sequence_depth = maxi(0, _attack_sequence_depth - 1)
	if _attack_sequence_depth == 0:
		if achievement != null: achievement.attack_end()
		_attack_sequence_bonus.clear()


func _take_attack_bonus() -> Dictionary:
	var bonus := {"base": player.status_stacks("next_bonus"),
		"double": player.status_stacks("next_double") > 0,
		"energy": ability_value("next_energy_bonus"), "serial": ability_value("next_serial_bonus"),
		"heat": player.heat * ability_value("next_overfire_per", 3) if has_ability("next_overfire") else 0}
	if bonus.double:
		player.add_status("next_double", -1)
	if bonus.base > 0:
		player.add_status("next_bonus", -int(bonus.base))
	for key in ["next_energy_bonus", "next_serial_bonus", "next_overfire", "next_overfire_per"]:
		abilities.erase(key)
	return bonus

func deal_damage(target: Combatant, amount: int, is_attack: bool = true) -> int:
	if target == null or amount <= 0:
		return 0
	var dmg := amount
	if is_attack:
		var bonus: Dictionary
		if _attack_sequence_depth > 0:
			if _attack_sequence_bonus.is_empty():
				_attack_sequence_bonus = _take_attack_bonus()
			bonus = _attack_sequence_bonus
		else:
			bonus = _take_attack_bonus()
		dmg += BattleBalance.i("strength_per_stack", 1) * (player.status_stacks("strength") + player.turn_strength)
		dmg += Relics.strike_bonus(self, target)
		dmg += int(bonus.base)
		if bonus.double:
			dmg *= BattleBalance.i("double_attack_mult", 2)
		dmg += int(bonus.energy) + int(bonus.serial) + int(bonus.heat)
		# 过火仅在整次攻击的首段追加；热力、蓄力仍按每段追加。
		bonus.heat = 0
		# 力只加在下一次攻击的首个伤害段，不随多段/群体攻击重复加成。
		if has_ability("force_once"):
			dmg += ability_value("force_once")
			abilities.erase("force_once")
		if player.turn_damage_double:
			dmg *= BattleBalance.i("cold_attack_mult", 2)  # 冷心：本回合伤害翻倍
		if has_ability("split_mind") and not target.is_player:
			target = player   # 精分：自己的攻击也打自己
	var before_hp := target.hp
	var before_shield := target.block + target.persistent_block
	var real := 0
	if is_attack and pierce_once and not target.is_player:
		# 重击（墨途远征词谱）：本场第一次攻击无视护盾
		pierce_once = false
		var saved := [target.block, target.persistent_block]
		target.block = 0
		target.persistent_block = 0
		real = target.take_damage(dmg)
		target.block = saved[0]
		target.persistent_block = saved[1]
		_log("重击：这一击无视护盾")
	else:
		real = target.take_damage(dmg)
	if is_attack and achievement != null: achievement.attack_hit(target, before_hp, before_shield, _attack_sequence_depth > 0)
	if not target.is_player:
		damage_dealt_this_turn += real
		# 爆金：敌方受攻击时按配置获得铜钱，记录实际入账（护盾全挡也算）。
		if is_attack and target.status_stacks("gold_burst") > 0:
			var earned := earn_gold(BattleBalance.i("bounty_on_hit", 1))
			_log("爆金：%s 受击，获得 %d 铜钱" % [target.display_name, earned])
		Relics.on_enemy_wounded(self, target)
		_check_bounty()
	return real

func _check_bounty() -> void:
	if bounty_paid and first_alive_enemy() == null:
		bounty_paid = false
		GameState.add_gold(bounty_reward)
		# 悬赏不受本场收入上限限制，但算本场收入（金字碑按它判定化金）
		gold_earned += maxi(0, bounty_reward)
		gold_earned_this_turn += maxi(0, bounty_reward)
		_log("重金：悬赏达成，获得 %d 铜钱" % bounty_reward)
		Relics.on_gold_earned(self)


# ---------------------------------------------------------------- 出字

func can_play() -> bool:
	return not end_turn_requested   # 无固定出字次数上限，但急停/停息后不能继续出字


## target: {tile: Vector2i} / {discard_index:int} / {enemy_glyph:Vector2i}

func play_options(path: Array) -> Dictionary:
	return EffectTargets.options(self, path)


func prepare_interaction(path: Array) -> Dictionary:
	return EffectTargets.prepare(self, path)


func inspect_play(path: Array, target: Dictionary = {}) -> Dictionary:
	return PlayRequest.inspect(self, path, target)


func try_play(path: Array, target: Dictionary = {}) -> Dictionary:
	var result := inspect_play(path, target)
	if not result.ok:
		return result
	target = result.target
	var word: WordData = result.word
	var glyphs: Array = result.glyphs
	var activates := _word_activates_formation(word)
	if formation_mode or activates:
		if activates:
			formation_mode = true
			_log("合击：进入结阵（之后打出的词（含合击本身）只登记，点「发动」一起结算）")
		return _queue_play(path, target, word, glyphs)
	var executed := _execute_prepared_play(_prepare_play(path, target, word, glyphs), {})
	if pending_reveal.is_empty():
		pending_choice.clear()
	return executed


## 遗物包一层：打击增强按本次出字是否带【击】；出字后压字石下落
func _execute_prepared_play(play: Dictionary, shared: Dictionary) -> Dictionary:
	if achievement != null: achievement.begin_play(play)
	var prev := strike_active
	strike_active = Relics.play_has_strike(play.glyphs)
	var result := _execute_prepared_play_core(play, shared)
	strike_active = prev
	if achievement != null: achievement.finish_play(bool(result.get("ok", false)))
	if result.get("ok", false):
		Relics.after_play(self)
	return result


static func has_required_target(kind: int, target: Dictionary) -> bool:
	match kind:
		EffectData.Target.NONE, EffectData.Target.SELF, EffectData.Target.BOARD, EffectData.Target.ALL_ENEMIES:
			return true
		EffectData.Target.BOARD_TILE, EffectData.Target.BOARD_2X2, EffectData.Target.BOARD_3X3, EffectData.Target.EMPTY_TILE:
			return target.has("tile")
		EffectData.Target.BOARD_ROW:
			return target.has("row")
		EffectData.Target.DISCARD_GLYPH:
			return target.has("discard_uid") or target.has("discard_index") or target.has("place_uid")
		EffectData.Target.ENEMY_GLYPH:
			return target.has("enemy_glyph") or target.has("tile")
		EffectData.Target.ENEMY:
			return target.has("target_index")
		EffectData.Target.BAG_GLYPH:
			return target.has("bag_uid")
	return not target.is_empty()


## 保存登记时的实体身份，后续改盘/补字不会把新牌误当成结阵材料。
func _prepare_play(path: Array, target: Dictionary, word: WordData, glyphs: Array) -> Dictionary:

	# 采集消耗前的盘面信息（供蓄电等读取）
	var tail_neighbors_own := 0
	if path.size() > 0:
		var tail: Vector2i = path[path.size() - 1]
		for n in board.neighbors(tail):
			var c: CharInstance = board.get_xy(n)
			if c != null and c.is_player_owned() and not path.has(n):
				tail_neighbors_own += 1

	# 效果列表（先算出来，便于把“先结算”的效果提前）
	var effects: Array = []
	if word != null:
		effects = word.effects
	else:
		var peek2: CharInstance = board.get_xy(path[0])
		if peek2 != null and peek2.data != null and not peek2.word_only:
			effects = peek2.data.solo_effects
			if peek2.data.solo_handler == "replace_self":
				effects = [_synthetic("replace_self", 1, EffectData.Target.SELF)]
	var instances: Array = []
	for pos in path:
		instances.append(board.get_xy(pos))
	var suspend_targets: Array = []
	if effects.any(func(e): return e.handler == "suspend_three"):
		for pos in target.get("cells", []):
			suspend_targets.append(board.get_xy(pos))
	return {"path": path.duplicate(), "target": target.duplicate(), "word": word,
		"glyphs": glyphs.duplicate(), "effects": effects.duplicate(), "instances": instances,
		"tail_neighbors_own": tail_neighbors_own, "suspend_targets": suspend_targets,
		"uses_gap": path_uses_gap(path) and not board.free_word_link,
		"uses_free_word": board.free_word_link}

func path_uses_gap(path: Array) -> bool:
	for i in range(1, path.size()):
		if board.is_gap_step(path[i - 1], path[i]):
			return true
	return false


## 普通出词和结阵共用效果、污染、自动能力和快照流程；结阵仅共享消耗记录。
func _execute_prepared_play_core(play: Dictionary, shared: Dictionary) -> Dictionary:
	# 结阵中每条登记词各自持有揭示字，避免下一次选字覆盖上一条队列。
	var owns_reveal := play.has("revealed")
	if owns_reveal:
		pending_reveal = (play.revealed as Array).duplicate()
	var result := _execute_play_inner(play, shared)
	if owns_reveal:
		if not pending_reveal.is_empty():
			return_pending_reveal()
		play.erase("revealed")
	if pending_reveal.is_empty():
		pending_choice.clear()
	return result


func _execute_play_inner(play: Dictionary, shared: Dictionary) -> Dictionary:
	# 只读表现通知：普通出字与结阵各词都报告自己的字、效果和目标。
	play_resolving.emit(play)
	var path: Array = play.path
	var target: Dictionary = play.target
	var word: WordData = play.word
	var glyphs: Array = play.glyphs
	var effects: Array = play.effects
	var path_insts: Array = play.instances
	var tail_neighbors_own: int = int(play.tail_neighbors_own)
	var result := {"ok": true, "word": word, "glyphs": glyphs, "solo": glyphs.size() == 1,
		"reason": "", "need_target": -1, "messages": [], "zero_effect": false,
		"not_implemented": word != null and not word.implemented}
	var unavailable := path_insts.any(func(inst): return reconnect_pending.any(func(item): return item.inst == inst))
	var suspend_targets: Array = play.get("suspend_targets", [])
	if bool(play.get("uses_free_word", false)) and not has_ability("next_free_word"):
		result.ok = false
		result.reason = "流利：机会已被前一个词消耗"
		return result
	for inst in path_insts:
		if inst.pinned and inst.pinned_exhausted and not shared.has(inst.uid):
			result.ok = false
			result.reason = "精铸：该固定字本回合已使用"
			return result
	for eff in effects:
		var target_reason := EffectRegistry.validate(eff, self, path, target)
		if not target_reason.is_empty():
			result.ok = false
			result.reason = target_reason
			return result
	if bool(play.get("uses_gap", false)) and (not has_ability("next_gap") or not path_uses_gap(path)):
		result.ok = false
		result.reason = "超：跨空格机会已被前一个词消耗"
		return result
	if unavailable or (effects.any(func(e): return e.handler == "suspend_three") and not EffectHandlersActions.valid_suspend_targets(self, suspend_targets)):
		result.ok = false
		result.reason = "所用字已被重连移出棋盘" if unavailable else "重连：所选实体已离开棋盘或被固定，请重新选择"
		result.messages.append(result.reason)
		_log(result.reason)
		return result
	if word == null and effects.any(func(e): return e.handler == "solo_release") and bool(target.get("release_energy", false)) and player.energy < BattleBalance.i("release_cost", 1):
		result.ok = false
		result.reason = "放：结算时储能不足，保留原字"
		_log(result.reason)
		return result
	if word == null and effects.any(func(e): return e.handler == "throw_neighbor") and target.has("tile"):
		var throw_reason := validate_solo_throw(path_insts[0], path[0], target)
		if not throw_reason.is_empty():
			result.ok = false
			result.reason = throw_reason
			_log(throw_reason)
			return result
	if word == null and effects.any(func(e): return e.handler in ["precision_draw", "buy_bag_solo"]):
		var bag_reason := validate_solo_bag(path_insts[0], path[0], target)
		if not bag_reason.is_empty():
			result.ok = false
			result.reason = bag_reason
			return result
	var linked_draw := ability_value("link_draw_once") if word != null and word.length() >= 2 else 0
	if linked_draw > 0:
		abilities.erase("link_draw_once")
	var combine_charge := ability_value("combine_word_once") if word != null and word.length() >= 2 else 0
	var speed_charge := ability_value("speed_word_once") if word != null and word.length() >= 2 else 0
	if combine_charge > 0:
		abilities.erase("combine_word_once")
	if speed_charge > 0:
		abilities.erase("speed_word_once")
	var discard_only: bool = word == null and not path_insts.is_empty() and path_insts[0].word_only
	var repeat_copy := word != null and has_ability("repeat_zero")
	if repeat_copy:
		abilities.erase("repeat_zero")
	var refill_was_active := has_ability("auto_refill")
	if word != null and effects.any(func(e): return e.handler == "strength_growing"):
		strengthen_plays += 1
	var compound_armed := word != null and word.length() >= BattleBalance.i("long_word_threshold", 3) and has_ability("next_compound")
	if compound_armed:
		abilities.erase("next_compound")
	var copy_armed := word != null and word.length() >= BattleBalance.i("long_word_threshold", 3) and has_ability("next_copy_layer")
	if copy_armed:
		abilities.erase("next_copy_layer")
	var pre: Array = []
	var post: Array = []
	for e in effects:
		if e.pre_consume:
			pre.append(e)
		else:
			post.append(e)

	for enemy in enemies: enemy.largest_hp_hit = 0
	var monster_eligible := monster_entered.duplicate()
	var ctx0 := {
		"battle": self,
		"source": player,
		"glyphs": glyphs,
		"target": target,
		"target_index": int(target.get("target_index", 0)),
		"word": word,
		"path": path,
		"tail_neighbors_own": tail_neighbors_own,
		"consumed": [],
	}
	var pre_msgs: Array = []
	_resolving_play = true
	if not pre.is_empty():
		pre_msgs = EffectResolver.resolve_all(pre, ctx0)

	# 消耗
	var consumed := _consume_path(path, path_insts, shared)

	result.ok = true
	result.word = word
	result.solo = glyphs.size() == 1
	result.not_implemented = word != null and not word.implemented
	result.messages.append_array(pre_msgs)
	for pm in pre_msgs:
		_log(pm)

	# 污染代价
	var pollution_msgs := _apply_pollution(consumed)
	result.messages.append_array(pollution_msgs)
	if compound_armed:
		_keep_compound_layer(consumed, target)
	# 补字鬼手在【复合】留层之后再补，免得把腾出的格子先占掉
	Relics.on_cards_consumed(self, consumed)

	var ctx := {
		"battle": self,
		"source": player,
		"glyphs": glyphs,
		"target": target,
		"target_index": int(target.get("target_index", 0)),
		"word": word,
		"path": path,
		"tail_neighbors_own": tail_neighbors_own,
		"consumed": consumed,
		"suspend_targets": suspend_targets,
		"strengthen_gain": strengthen_plays,
	}
	last_shift_row = -1
	last_shift_dir = 0
	# 「下一次」类标记：在本词结算「之前」消费（消费的是上一个词设的），
	# 使本次结算里新设的标记留给下一个多字词。
	_apply_next_word_flags(word)
	if word != null and word.length() >= 2 and player.status_stacks("next_extra") > 0:
		player.add_status("next_extra", -1)
		var extra_effects := EffectResolver.instant_effects(effects)
		if not extra_effects.is_empty():
			var nex := EffectResolver.resolve_all(extra_effects, ctx)
			for nm in nex:
				result.messages.append(nm)
				_log("超载：%s" % nm)
	var msgs := EffectResolver.resolve_all(post, ctx)
	result.messages.append_array(msgs)
	for m in msgs:
		_log(m)

	# 重复：本回合第一次有效多字词，再执行一次其即时效果（不重复消耗字）
	if word != null and word.length() >= 2 and has_ability("repeat") and repeat_armed:
		repeat_armed = false
		var rep_msgs := EffectResolver.resolve_all(EffectResolver.instant_effects(effects, true), ctx)
		for rm in rep_msgs:
			result.messages.append(rm)
			_log("重复：%s" % rm)

	# 强化逐字形触发，融合牌的附带字也参与；目标型单字默认使用该字原格。
	if not empowered_glyphs.is_empty():
		for c in consumed:
			var inst_e: CharInstance = c.inst
			if discard_only:
				continue
			for glyph in inst_e.glyph_list():
				if not empowered_glyphs.has(glyph):
					continue
				var cd: CharacterData = Database.get_character_by_glyph(glyph)
				if cd == null:
					continue
				var solo: Array = cd.solo_effects
				if cd.solo_handler == "replace_self":
					solo = [_synthetic("replace_self", 1, EffectData.Target.SELF)]
				var solo_target := target.duplicate()
				if not solo_target.has("tile"):
					solo_target["tile"] = c.pos
				var solo_ctx := {"battle": self, "source": player, "glyphs": [glyph],
					"path": [c.pos], "consumed": [c], "target": solo_target,
					"target_index": int(target.get("target_index", 0)), "word": word}
				var solo_msgs := EffectResolver.resolve_all(solo, solo_ctx)
				for sm in solo_msgs:
					result.messages.append(sm)
					_log("强化【%s】：%s" % [glyph, sm])
	if copy_armed:
		_keep_energy_layers(consumed)

	# 镀金按实体每次有效打出结算，单字与组词均可；弃字不触发。
	if not discard_only:
		for c in consumed:
			var inst_g: CharInstance = c.inst
			var gild_gain := earn_gold(BattleBalance.i("gild_gold", 1)) if inst_g.gilded else 0
			if gild_gain > 0:
				if achievement != null: achievement.emit_metrics([{"metric": "gild_gold", "amount": gild_gain}])
				result.messages.append("镀金：【%s】+%d 铜钱" % [inst_g.glyph(), gild_gain])
				_log("镀金：【%s】+%d 铜钱" % [inst_g.glyph(), gild_gain])

	# 心力：每打出一颗【心】，叠加一层心力
	if has_ability("heart_power") and not discard_only:
		for c in consumed:
			var inst_h: CharInstance = c.inst
			if inst_h.glyph() == "心":
				var heart_gain := BattleBalance.i("heart_per_use", 1) * passive_multiplier("心力")
				player.heart_power += heart_gain
				result.messages.append("心力：+%d 层（当前 %d）" % [heart_gain, player.heart_power])
				_log("心力：+%d 层（当前 %d）" % [heart_gain, player.heart_power])

	if repeat_copy:
		EffectHandlersActions.scatter_word_copy(self, word.glyphs)

	# 记录 / 持续能力触发
	if word != null:
		words_played_this_turn.append(word.id)
		if has_ability("vigor"):
			var distinct: Dictionary = {}
			for wid in words_played_this_turn:
				distinct[wid] = true
			abilities["vigor_next"] = distinct.size() * passive_multiplier("精力")
		if _replays_attack(word):
			# 连击重演了一个攻击词（可能是上回合的）：本回合算打出过攻击词，【回防】等条件能接上；
			# 但不改写「上一个攻击词」，免得下一次连击重演的是连击自己
			attack_words_this_turn += 1
		elif _is_attack_word(word):
			attack_words_this_turn += 1
			last_attack_word = word
			last_attack_glyphs = glyphs.duplicate()
			last_attack_effects = effects.duplicate()
			last_attack_target = int(target.get("target_index", 0))
			last_attack_target_data = target.duplicate()
			last_attack_path = path.duplicate()
		if not end_turn_requested:
			_trigger_on_word_abilities(word, consumed)
		EventBus.word_played.emit(word, _join(glyphs))
	else:
		var first2: CharInstance = consumed[0].inst if not consumed.is_empty() else null
		if first2 != null and first2.data != null:
			EventBus.character_played.emit(first2.data)

	# 重力（持续能力）：每次有效出字后自动全盘向下重力（含打出「重力」当次）
	if has_ability("gravity_always") and not end_turn_requested:
		apply_gravity()
		_log("重力：全盘下落")

	# 充电过热：此后每次出字后立即补满盘面
	if has_ability("auto_refill") and not end_turn_requested:
		var filled := draw_to_board(board.size * board.size)
		if filled > 0:
			if refill_was_active:
				add_heat(filled * BattleBalance.i("refill_heat", 1))
			_log("充电过热：立即补位 %d 枚" % filled)

	if effects.is_empty():
		result.zero_effect = true
		zero_effect_count += 1

	_refill_flow_rows(word, consumed)
	if combine_charge > 0:
		player.add_block(BattleBalance.i("combine_block", 2) * combine_charge)
		add_energy(BattleBalance.i("combine_energy", 1) * combine_charge)
		var combine_message := "合：成词后获得 %d 临时格挡、%d 储能" % [BattleBalance.i("combine_block", 2) * combine_charge, BattleBalance.i("combine_energy", 1) * combine_charge]
		result.messages.append(combine_message)
		_log(combine_message)
	if speed_charge > 0:
		var speed_actual := draw_to_board(BattleBalance.i("speed_draw", 2) * speed_charge)
		add_heat(BattleBalance.i("speed_heat", 1) * speed_charge)
		var speed_message := "速：成词后补 %d 字、热度 +%d" % [speed_actual, BattleBalance.i("speed_heat", 1) * speed_charge]
		result.messages.append(speed_message)
		_log(speed_message)
	if linked_draw > 0:
		var linked_actual := draw_to_board(linked_draw)
		var linked_message := "连：成词后补 %d 字" % linked_actual
		result.messages.append(linked_message)
		_log(linked_message)
	# 电力：本词若位移了行列，可消耗 1 储能额外位移一次
	if has_ability("instant_power") and last_shift_row >= 0 and player.energy >= BattleBalance.i("copy_layer_cost", 1):
		spend_energy(BattleBalance.i("copy_layer_cost", 1))
		var esr := last_shift_row
		var esd := last_shift_dir
		BattleOps.shift_row(self, esr, esd)
		_log("电力：消耗 1 储能，额外位移第 %d 行" % (esr + 1))
	last_shift_row = -1
	last_shift_dir = 0
	last_played_glyphs = glyphs.duplicate()
	if word != null and word.word == "急速":
		rapid_cells = path.duplicate()
	if word != null:
		last_played_word = word
		last_played_effects = effects.duplicate()
		last_played_consumed.clear()
		for i in path.size():
			if i < path_insts.size():
				last_played_consumed.append({"inst": path_insts[i], "pos": path[i], "kind": consumed[i].kind})
	EnemyMechanics.on_play(self, word, path_insts, consumed, monster_eligible)
	_resolving_play = false
	return result


func _keep_compound_layer(consumed: Array, target: Dictionary) -> void:
	var chosen_uid := int(target.get("compound_uid", -1))
	for item in consumed:
		var inst: CharInstance = item.inst
		if chosen_uid >= 0 and inst.uid != chosen_uid:
			continue
		var pos: Vector2i = item.pos
		if item.kind in ["layer", "pinned"] or board.get_xy(pos) != null:
			continue
		var copy := inst.clone()
		copy.owner = CharInstance.Owner.PLAYER
		copy.temporary = true
		copy.pinned = false
		copy.temporary_uses = 0
		board.set_xy(pos, copy)
		temp_chars.append(copy)
		_log("复合：在原格保留临时【%s】" % "".join(copy.glyph_list()))
		return


## 一次出词在每个生效行至多扣一次；先完成所有原格补字，再结算超速额外补字。
func _refill_flow_rows(word: WordData, consumed: Array) -> void:
	restore_reconnect_tiles()
	if word == null or word.length() < 2 or word.word == "流速" or flow_speed_rows.is_empty() or end_turn_requested:
		return
	var targets: Array = []
	var seen := {}
	for item in consumed:
		var pos: Vector2i = item.pos
		if item.kind != "real" or item.get("shared", false) or seen.has(pos):
			continue
		if int(flow_speed_rows.get(pos.y, 0)) <= 0 or board.get_xy(pos) != null:
			continue
		seen[pos] = true
		targets.append(pos)
	var refilled := {}
	for pos in targets:
		ensure_bag()
		if bag.is_empty():
			break
		place_from_pool(pos, bag.pop_back())
		refilled[pos.y] = int(refilled.get(pos.y, 0)) + 1
	var placed := 0
	for row in refilled:
		placed += int(refilled[row])
		var remaining := int(flow_speed_rows[row]) - 1
		if remaining > 0:
			flow_speed_rows[row] = remaining
		else:
			flow_speed_rows.erase(row)
		_log("流速：第 %d 行原地补回 %d 枚，剩余 %d 词" % [int(row) + 1, int(refilled[row]), remaining])
	record_draw(placed, targets.size())

## 重连在到期回合返回原实体；满盘保留待回，后续腾位或补字时优先归还。
func restore_reconnect_tiles() -> int:
	var due: Array = reconnect_pending.filter(func(item): return int(item.return_turn) <= turn)
	var restored := 0
	# 先处理全部原格，避免先返还的字抢走后返还字的空原格。
	for item in due:
		var pos: Vector2i = item.pos
		if board.in_bounds(pos.x, pos.y) and board.get_xy(pos) == null:
			place_from_pool(pos, item.inst, false)
			reconnect_pending.erase(item)
			restored += 1
	for item in due:
		if not reconnect_pending.has(item):
			continue
		var empties := board.empty_indices()
		if empties.is_empty():
			break
		place_from_pool(empties[0], item.inst, false)
		reconnect_pending.erase(item)
		restored += 1
	if restored > 0:
		_log("重连：%d 枚原实体返回棋盘" % restored)
	return restored

## 回能含施放当回合；重施刷新后续回合，同回合不会再次发放。
func activate_energy_regen(duration: int = 3) -> int:
	var remaining := maxi(0, duration - 1)
	if remaining > 0:
		enable_ability("energy_regen", remaining)
	else:
		abilities.erase("energy_regen")
	add_energy(BattleBalance.i("energy_regen", 2))
	_energy_regen_last_turn = turn
	return BattleBalance.i("energy_regen", 2)

func _tick_energy_regen() -> void:
	var remaining := ability_value("energy_regen")
	if remaining <= 0 or _energy_regen_last_turn == turn:
		return
	add_energy(BattleBalance.i("energy_regen", 2))
	_energy_regen_last_turn = turn
	remaining -= 1
	if remaining > 0:
		enable_ability("energy_regen", remaining)
	else:
		abilities.erase("energy_regen")
	_log("回能：储能 +%d，后续剩余 %d 回合" % [BattleBalance.i("energy_regen", 2), remaining])

func _keep_energy_layers(consumed: Array) -> void:
	var kept := 0
	for item in consumed:
		if player.energy < BattleBalance.i("copy_layer_cost", 1):
			break
		if item.kind in ["pinned", "layer"] or board.get_xy(item.pos) != null:
			continue
		var copy: CharInstance = item.inst.clone()
		copy.owner = CharInstance.Owner.PLAYER
		copy.temporary = true
		copy.pinned = false
		copy.temporary_uses = 0
		board.set_xy(item.pos, copy)
		temp_chars.append(copy)
		spend_energy(BattleBalance.i("copy_layer_cost", 1))
		kept += 1
	if kept > 0:
		_log("超能：保留 %d 个临时复制层" % kept)

func solo_target_cells(inst: CharInstance, origin: Vector2i) -> Array:
	return EffectTargets.solo_target_cells(self, inst, origin)

static func is_refinable_junk(inst: CharInstance) -> bool:
	if inst == null or inst.pinned:
		return false
	if inst.is_enemy_owned() or inst.temporary:
		return true
	return inst.owner == CharInstance.Owner.SELF_GENERATED and (not inst.pollutions.is_empty() or (inst.data != null and inst.data.is_pollution))

func solo_throw_destinations(inst: CharInstance, origin: Vector2i) -> Array:
	return EffectTargets.solo_throw_destinations(self, inst, origin)

func validate_solo_throw(inst: CharInstance, origin: Vector2i, target: Dictionary) -> String:
	return EffectTargets.validate_solo_throw(self, inst, origin, target)

func _solo_requires_target(cd: CharacterData, path: Array = []) -> int:
	return EffectTargets.solo_requires_target(self, cd, path)

func solo_bag_candidates(source: CharInstance, handler_override: String = "") -> Array:
	return EffectTargets.solo_bag_candidates(self, source, handler_override)

func validate_solo_bag(source: CharInstance, origin: Vector2i, target: Dictionary) -> String:
	return EffectTargets.validate_solo_bag(self, source, origin, target)

func _synthetic(handler: String, amount: int, target_kind: int) -> EffectData:
	var e := EffectData.new()
	e.handler = handler
	e.amount = amount
	e.target = target_kind
	return e

func _is_attack_word(word: WordData) -> bool:
	if word == null:
		return false
	for e in word.effects:
		if e.is_attack():
			return true
	return false


## 这个词是否带【连击】式重演，且确实有攻击词可重演
func _replays_attack(word: WordData) -> bool:
	if word == null or last_attack_word == null or last_attack_effects.is_empty():
		return false
	for e in word.effects:
		if e.handler == "replay_last_attack":
			return true
	return false


## 流连：每层留字概率；层数由【流连】叠加，最多 2 层。
func linger_chance() -> float:
	return mini(100, ability_value("linger_chance", 1) * BattleBalance.i("linger_percent", 25)) / 100.0


## 消耗一个路径；返回 [{inst, kind}]，kind = real / layer / pinned / retained。

func _consume_path(path: Array, expected: Array, shared: Dictionary) -> Array:
	var out: Array = []
	for i in path.size():
		var pos: Vector2i = path[i]
		var inst: CharInstance = expected[i] if not expected.is_empty() else board.get_xy(pos)
		if inst == null:
			continue
		if shared.has(inst.uid):
			var reused: Dictionary = shared[inst.uid].duplicate()
			reused["shared"] = true
			reused["pos"] = pos
			out.append(reused)
			continue
		var item := {"inst": inst, "pos": pos, "kind": "real", "shared": false}
		var physical_index := board.cells.find(inst)
		# pre_consume 效果已搬走/摧毁原牌，保留出词信息，但不消耗它原格的新牌。
		if physical_index < 0:
			if discard.has(inst) and not consumed_this_turn.has(inst):
				consumed_this_turn.append(inst)
			shared[inst.uid] = item
			out.append(item)
			continue
		var slab_kind := ""
		if inst.pinned:
			inst.pinned_exhausted = true
			item.kind = "pinned"
		elif inst.temporary_uses > 0:
			inst.temporary_uses -= 1
			if achievement != null: achievement.extra_use()
			item.kind = "layer"
		elif inst.uid == slab_uid:
			slab_kind = Relics.consume_slab(self, inst)
		if slab_kind == "layer":
			item.kind = "layer"
		elif slab_kind == "exhausted":
			# 压字石：次数用尽，本场移出循环（回收、回放都拿不回来），下场恢复
			removed_this_battle.append(inst)
			board.cells[physical_index] = null
		elif item.kind in ["pinned", "layer"]:
			pass
		elif Relics.stay_wax(self, inst):
			item.kind = "retained"
			_log("留字蜡：保留原位【%s】" % "".join(inst.glyph_list()))
		elif has_ability("linger_chance") and rng.randf() < linger_chance():
			item.kind = "retained"
			_log("流连：保留原位【%s】" % "".join(inst.glyph_list()))
		else:
			if inst.is_enemy_owned() or inst.temporary:
				temp_chars.erase(inst)
			else:
				discard.append(inst)
				if not consumed_this_turn.has(inst):
					consumed_this_turn.append(inst)
			board.cells[physical_index] = null
		shared[inst.uid] = item
		out.append(item)
	return out

func _apply_pollution(consumed: Array) -> Array:
	var msgs: Array = []
	for c in consumed:
		if c.get("shared", false):
			continue
		var inst: CharInstance = c.inst
		for pid in inst.pollutions:
			var pd: PollutionData = Database.get_pollution(pid)
			if pd == null:
				continue
			if pd.hp_loss_on_play > 0:
				if has_ability("fireproof") and inst.glyph() == "热":
					msgs.append("防火：【热】的污染不再扣血")
				else:
					var real := player.take_damage(pd.hp_loss_on_play)
					msgs.append("污染【%s】：失去 %d 生命" % [pd.name, real])
			if pd.draw_penalty_on_play > 0:
				next_draw_penalty += pd.draw_penalty_on_play
				msgs.append("污染【%s】：下次补字 -%d" % [pd.name, pd.draw_penalty_on_play])
	return msgs

func _join(glyphs: Array) -> String:
	var s := ""
	for g in glyphs:
		s += str(g)
	return s


# ---------------------------------------------------------------- 持续能力 / 每回合

func _trigger_on_word_abilities(word: WordData, consumed: Array = []) -> void:
	if word == null:
		return
	if has_ability("accel"):
		var mult := passive_multiplier("加速", board.free_count() > 0 and not (bag.is_empty() and discard.is_empty()))
		var n := draw_to_board(BattleBalance.i("accel_draw", 1) * mult)
		add_heat(BattleBalance.i("rotate_heat", 1))
		_log("加速：补 %d 字，热度 +1" % n)
	if has_ability("flow"):
		var distinct := {}
		for id in words_played_this_turn:
			distinct[id] = true
		var earned: int = int(distinct.size() / BattleBalance.i("flow_interval", 2))
		var claimed := ability_value("_flow_claimed")
		if earned > claimed:
			abilities["_flow_claimed"] = earned
			var mult := passive_multiplier("流转", board.free_count() > 0 and not (bag.is_empty() and discard.is_empty()))
			var n2 := draw_to_board(ability_value("flow", 2) * (earned - claimed) * mult)
			_log("流转：补 %d 字" % n2)
	if has_ability("serial"):
		serial_words += 1
		if serial_words % BattleBalance.i("serial_interval", 3) == 0:
			var sb := ability_value("serial", 6) * passive_multiplier("连载")
			abilities["next_serial_bonus"] = ability_value("next_serial_bonus") + sb
			_log("连载：累计 %d 次出词，下一次攻击每段 +%d" % [serial_words, sb])
	if has_ability("longword_draw") and word.length() >= BattleBalance.i("long_word_threshold", 3):
		var mult := passive_multiplier("能力")
		var want := ability_value("longword_draw") * BattleBalance.i("longword_draw", 3) * mult
		var back := refill_played_cells(consumed, want)
		_log("能力：打出 %d 字词，原位补 %d 字" % [word.length(), back])

func _apply_next_word_flags(word: WordData) -> void:
	if word == null:
		return
	# 只对“多字词”生效的下一词标记
	if word.length() < 2:
		return
	if ability_value("next_rapid") > 0:
		var total := ability_value("next_rapid")
		var placed := 0
		# 先补 2 字到「急速」打出的原格（若仍为空）
		var fixed := mini(BattleBalance.i("rapid_return", 2), rapid_cells.size())
		for i in fixed:
			if placed >= total:
				break
			var pos: Vector2i = rapid_cells[i]
			if board.get_xy(pos) != null:
				continue
			if BattleOps.draw_one_to(self, pos) != null:
				placed += 1
		var n := placed + draw_to_board(total - placed)
		add_heat(int(abilities.get("next_rapid_heat", 0)))
		_log("急速：补 %d 字（其中 %d 字回原格）" % [n, placed])
		rapid_cells = []
		abilities.erase("next_rapid")
		abilities.erase("next_rapid_heat")
	if ability_value("next_draw_bonus") > 0:
		var n3 := draw_to_board(ability_value("next_draw_bonus"))
		_log("过热：额外补 %d 字" % n3)
		abilities.erase("next_draw_bonus")
	if ability_value("next_diagonal") > 0:
		abilities.erase("next_diagonal")
		board.diagonal_steps_allowed = 0
	if has_ability("next_gap"):
		abilities.erase("next_gap")
		board.gap_steps_allowed = 0
	if has_ability("next_free_word"):
		abilities.erase("next_free_word")
		board.free_word_link = false

func begin_player_turn(draw: bool = true, open_monster_tasks: bool = true) -> void:
	turn += 1
	abilities.erase("double_next")
	if temporary_heat_capacity > 0:
		player.heat_capacity -= temporary_heat_capacity
		_log("载：本回合临时热容到期，撤销 %d" % temporary_heat_capacity)
		temporary_heat_capacity = 0
	formation_mode = false
	formation_queue.clear()
	reserved_cells.clear()
	player.clear_block()
	player.turn_damage_reduction = 0
	player.turn_strength = 0
	player.turn_damage_halve = false
	player.turn_damage_double = false
	if player.no_block_turns > 0:
		player.no_block_turns -= 1
		if player.no_block_turns == 0:
			_log("冷心：恢复获得防御")
	player.block_broken = false
	if has_ability("armor_plating"):
		player.add_block(BattleBalance.i("armor_turn_block", 1))
	if has_ability("block_next_turn"):
		var next_block := ability_value("block_next_turn")
		abilities.erase("block_next_turn")
		player.add_block(next_block)
		_log("甲：下回合格挡 +%d（仅此次）" % next_block)
	# 强心：每回合回复已触发的心力层数
	if has_ability("strong_heart"):
		var healing := BattleBalance.i("strong_heart_base", 2) + BattleBalance.i("heart_trigger_heal", 1) * player.heart_power_triggered
		heal_player(healing)
		_log("强心：回复 %d 生命（基础 2，已触发心力 %d 层）" % [healing, player.heart_power_triggered])
	words_played_this_turn.clear()
	attack_words_this_turn = 0
	drawn_this_turn = 0
	consumed_this_turn.clear()
	flow_speed_rows.clear()
	last_shift_row = -1
	last_shift_dir = 0
	damage_dealt_this_turn = 0
	gold_earned_this_turn = 0
	damage_taken_this_turn = 0
	bounty_paid = false
	bounty_reward = 0
	abilities.erase("_repeat_used")
	abilities.erase("solo_gain_once")
	for id in ["accel", "flow", "ceasefire", "repeat_zero", "vigor", "_flow_claimed", "linger_chance", "energy_gain_once", "link_draw_once", "payment_discount_once", "retaliate_once", "combine_word_once", "speed_word_once", "energy_refund_once"]:
		abilities.erase(id)
	if has_ability("heat_overload_bonus_armed"):
		enable_ability("heat_overload_bonus", ability_value("heat_overload_bonus_armed"))
	for inst in board.cells:
		if inst != null:
			inst.pinned_exhausted = false
	if has_ability("energy_next_turn"):
		var next_energy := ability_value("energy_next_turn")
		abilities.erase("energy_next_turn")
		add_energy(next_energy)
		_log("蓄：开局获得 %d 储能（仅此次）" % next_energy)
	_tick_energy_regen()
	board.diagonal_steps_allowed = 0
	board.gap_steps_allowed = 0
	board.free_word_link = false
	# 每回合重置“下一词”类标记（持续能力与 _overflow_paid 保留）
	for k in abilities.keys():
		if str(k).begins_with("next_") and k not in ["next_energy_bonus", "next_serial_bonus"]:
			abilities.erase(k)
	restore_reconnect_tiles()
	Relics.on_turn_start(self)
	if draw:
		var vigor := ability_value("vigor_next")
		abilities.erase("vigor_next")
		var amount: int = max(0, rules.turn_draw - base_draw_penalty - next_draw_penalty) + vigor
		next_draw_penalty = 0
		if vigor > 0:
			_log("精力：本回合基础补字 +%d" % vigor)
		if has_ability("manual_draw"):
			abilities.erase("manual_draw")
			manual_draw_pending = amount
			_log("精心：本回合补 %d 枚，改为从字袋定向选字（随机落地）" % amount)
		else:
			draw_to_board(amount)
		if manual_draw_pending <= 0:
			_after_turn_draw()
	abilities.erase("split_mind")
	abilities.erase("profit_share")
	abilities.erase("inject_bounty")
	abilities.erase("gold_to_shield")
	abilities.erase("double_next")
	repeat_armed = has_ability("repeat")
	_tick_player_statuses()
	monster_net_energy = 0
	monster_paid = false
	monster_entered.clear()
	if open_monster_tasks:
		EnemyMechanics.begin_phase(self)
	# 易伤的层数表示剩余回合；敌方与玩家都在新回合开始时衰减。
	for enemy in enemies:
		_decay_turn_statuses(enemy, ["vulnerable"])
	_log("—— 第 %d 回合 ——" % turn)
	EventBus.turn_ended.emit(turn)

## 基础补字真正落盘后统一结算；精心等待玩家选字时不能提前判污染或移动字盘。
func _after_turn_draw() -> void:
	if has_ability("gravity_always"):
		apply_gravity()
		_log("重力：回合开局下落")
	Relics.after_turn_draw(self)
	Relics.apply_gravity_relics(self)


func _tick_player_statuses() -> void:
	var poison := player.status_stacks("poison")
	if poison > 0:
		var real := player.take_damage(poison * BattleBalance.i("poison_per_stack", 1))
		_log("中毒：失去 %d 生命" % real)
	# 再生：按层数回复生命，然后每回合固定衰减 1 层
	var regen := player.status_stacks("regen")
	if regen > 0:
		var before := player.hp
		heal_player(regen * BattleBalance.i("regen_per_stack", 1))
		var healed := player.hp - before
		if healed > 0:
			_log("再生：回复 %d 生命" % healed)
		else:
			_log("再生：生命已满，未回复")
	_decay_turn_statuses(player, ["vulnerable", "poison", "regen"])

func _decay_turn_statuses(unit: Combatant, ids: Array) -> void:
	for sid in ids:
		var stacks := unit.status_stacks(sid)
		if stacks > 0:
			var sd: StatusData = Database.get_status(sid)
			if sd != null and sd.decay_per_turn > 0:
				unit.add_status(sid, -mini(stacks, sd.decay_per_turn))

func end_player_turn() -> void:
	# 结阵未发动：自动结算，避免丢掉已登记的牌
	if formation_mode and not formation_queue.is_empty():
		resolve_formation()
	end_turn_requested = false
	# 裂墨瓶：先清空本回合剩下的储能，蓄能 / 蓄热这一刻新加的留到下回合
	if relics.has("cracked_bottle") and player.energy > 0:
		var cleared := player.energy
		player.energy = 0
		_log("裂墨瓶：回合结束清空 %d 储能" % cleared)
	# 蓄能：回合结束若仍有可用多字词留在盘上
	if has_ability("energy_idle") and _has_any_word_on_board():
		var gained := ability_value("energy_idle", 2) * passive_multiplier("蓄能")
		add_energy(gained)
		_log("蓄能：储能 +%d" % gained)

	# 蓄热：回合结束热度 -2，每点转 1 储能（本词专享的"降温"，非全局自然冷却）
	if has_ability("heat_to_energy"):
		var cooled := mini(BattleBalance.i("stored_heat_cool", 2), player.heat)
		if cooled > 0:
			add_heat(-cooled)
			var gained := BattleBalance.i("stored_heat_energy", 1) * cooled * passive_multiplier("蓄热")
			add_energy(gained)
			_log("蓄热：热度 -%d，储能 +%d" % [cooled, gained])

	# 空铅盒：回合结束、敌人行动前，按空行给持久盾
	Relics.on_player_turn_end(self)
	# 蔓生墨：回合结束、敌人行动前繁殖
	Relics.breed(self)
	EnemyMechanics.replicate_glyphs(self)
	_log("玩家结束回合")
	var blitz := blitz_turn > 0 and turn == blitz_turn
	for e in enemies:
		if not e.is_alive():
			continue
		# 急就章：所有敌人跳过这一次行动（意图顺延）；任务判定、灼烧等照常结算
		_enemy_act(e, false, blitz)
		if not player.is_alive():
			break
	EnemyMechanics.replicate_glyphs(self)
	EnemyMechanics.release_dead(self)
	if blitz:
		blitz_turn = 0
	abilities.erase("retaliate_once") # 未遇到敌方攻击时也在本回合结束失效。

	# 持续能力：护甲（把部分临挡转持久盾）
	if has_ability("convert_block") and player.block > 0:
		var pct := ability_value("convert_block", 50)
		var conv: int = int(floor(player.block * pct / 100.0))
		conv *= passive_multiplier("护甲", conv > 0)
		player.add_persistent_block(conv)
		if conv > 0:
			_log("护甲：将 %d 点临挡转为持久盾" % conv)

	# 后置结算：反击
	if player.is_alive():
		_resolve_counter()
	# 甲：格挡被击穿则护甲碎裂
	if has_ability("armor_plating") and player.block_broken:
		abilities.erase("armor_plating")
		_log("甲：格挡被击穿，护甲碎裂")
	# 临时格挡默认敌行动后清除
	player.clear_block()
	damage_taken_last_turn = damage_taken_this_turn

	if player.is_alive() and not is_over():
		begin_player_turn(true)

func _resolve_counter() -> void:
	var stacks := ability_value("counter")
	if stacks <= 0:
		return
	var dmg: int = player.block + BattleBalance.i("counter_per_stack", 3) * stacks
	var target := first_alive_enemy()
	if target != null and dmg > 0:
		var real := target.take_damage(dmg)
		_log("反击：造成 %d 伤害" % real)
	abilities.erase("counter")

## opening=true：开场突袭 / 首领先手，不消耗「停火」
## skip_move=true（急就章）：只跳过这一招本身，行动前后的机制判定和灼烧 / 心蚀照常
func _enemy_act(e: Combatant, opening := false, skip_move := false) -> void:
	var ed: EnemyData = e.enemy_data
	if ed == null or ed.moves.is_empty():
		return
	if not opening and not skip_move and enemy_skip_turns > 0:  # 急就章那回合不消耗停火
		enemy_skip_turns -= 1
		e.move_index += 1
		_log("停火：%s 这一回合不攻击" % e.display_name)
		return
	var mv: EnemyMoveData = current_intent(e)
	EnemyMechanics.before_action(self, e, mv)
	if not e.is_alive() or not player.is_alive():
		EnemyMechanics.release_dead(self)
		return
	if skip_move:
		# 急就章只推迟行动，灼烧在“本该行动的时点”照常结算
		_tick_burn_before_action(e)
		if not e.is_alive():
			EnemyMechanics.release_dead(self)
			return
		e.move_index += 1
		_log("急就章：%s 这一回合不行动" % e.display_name)
		EnemyMechanics.after_action(self, e, mv)
		_tick_after_action(e)
		return
	_tick_burn_before_action(e)
	if not e.is_alive():
		EnemyMechanics.release_dead(self)
		return
	enemy_acting.emit(e, mv)
	e.move_index += 1
	var immune := has_ability("ceasefire") and damage_dealt_this_turn <= 0
	var split := has_ability("split_mind")
	match mv.kind:
		EnemyMoveData.Kind.ATTACK, EnemyMoveData.Kind.MULTI:
			var hits: int = mv.hits if mv.kind == EnemyMoveData.Kind.MULTI else 1
			for i in hits:
				var dmg := mv.damage + e.status_stacks("strength")
				if immune:
					dmg = 0
				if split:
					var real_s := e.take_damage(max(0, dmg))
					_log("精分：%s 攻击了自己，造成 %d 伤害" % [e.display_name, real_s])
				else:
					var before := player.hp
					var real := player.take_damage(max(0, dmg))
					damage_taken_this_turn += (before - player.hp)
					if immune:
						_log("停火：免疫 %s 的攻击" % e.display_name)
					else:
						_log("%s 攻击，造成 %d 伤害" % [e.display_name, real])
		EnemyMoveData.Kind.BLOCK:
			e.add_block(mv.block)
			_log("%s 获得 %d 护盾" % [e.display_name, mv.block])
		EnemyMoveData.Kind.ATTACK_BLOCK:
			e.add_block(mv.block)
			if split:
				var real_sb := e.take_damage(max(0, mv.damage))
				_log("精分：%s 攻击了自己 %d" % [e.display_name, real_sb])
			else:
				var before2 := player.hp
				var real2 := player.take_damage(0 if immune else max(0, mv.damage))
				damage_taken_this_turn += (before2 - player.hp)
				_log("%s 攻击 %d 并获得 %d 护盾" % [e.display_name, real2, mv.block])
		EnemyMoveData.Kind.BUFF:
			e.add_status(mv.status_id, mv.status_stacks)
		EnemyMoveData.Kind.DEBUFF:
			player.add_status(mv.status_id, mv.status_stacks)
			_log("%s 施加减益 %s" % [e.display_name, mv.status_id])
		EnemyMoveData.Kind.INJECT:
			var n := EnemyMechanics.inject_move(self, e, mv)
			_log("%s 注入 %d 个污染字" % [e.display_name, n])
		EnemyMoveData.Kind.SPECIAL:
			EnemyMechanics.special(self, e, mv)

	if mv.kind != EnemyMoveData.Kind.INJECT and mv.inject_count > 0 and player.is_alive() and e.is_alive():
		var n := EnemyMechanics.inject_move(self, e, mv)
		_log("%s 注入 %d 个【%s】" % [e.display_name, n, mv.inject_glyph])
	EnemyMechanics.after_action(self, e, mv)

	# 反只回应攻击自己的敌人；等完整多段行动结束，向该攻击者结算一次。
	if not split and mv.kind in [EnemyMoveData.Kind.ATTACK, EnemyMoveData.Kind.MULTI, EnemyMoveData.Kind.ATTACK_BLOCK] and has_ability("retaliate_once") and player.is_alive():
		var retaliation := ability_value("retaliate_once")
		abilities.erase("retaliate_once")
		if e.is_alive():
			var reflected := deal_damage(e, retaliation, false)
			_log("反：%s 攻击行动结束，反击 %d 伤害" % [e.display_name, reflected])
	_tick_after_action(e)


## 灼烧：每层在敌人行动【前】按当前热度掉血，然后掉 1 层（可叠加）
func _tick_burn_before_action(e: Combatant) -> void:
	if e == null or not e.is_alive() or e.status_stacks("burn") <= 0:
		return
	var bd: int = maxi(0, player.heat * BattleBalance.i("burn_heat_mult", 2))
	var real_b := e.take_damage(bd)
	if achievement != null and not e.is_alive(): achievement.emit_metrics([{"metric": "burn_kills", "amount": 1}])
	e.add_status("burn", -1)
	_log("灼烧：%s 行动前受到 %d 伤害" % [e.display_name, real_b])
	damage_dealt_this_turn += real_b
	Relics.on_enemy_wounded(self, e)
	_check_bounty()


## 敌方每次行动后的持续伤害（心蚀）
func _tick_after_action(e: Combatant) -> void:
	# 心蚀：敌方每次行动后扣等量层数的血（不衰减）
	if e.is_alive() and e.status_stacks("heart_corrosion") > 0:
		var hc := e.status_stacks("heart_corrosion")
		var real_hc := e.take_damage(hc * BattleBalance.i("corrosion_per_stack", 1))
		_log("心蚀：对 %s 造成 %d 伤害" % [e.display_name, real_hc])
		damage_dealt_this_turn += real_hc
		Relics.on_enemy_wounded(self, e)
		_check_bounty()


# ---------------------------------------------------------------- 盘面操作（供 handler 调用）

func current_intent(e: Combatant) -> EnemyMoveData:
	if e.enemy_data == null or e.enemy_data.moves.is_empty():
		return null
	return EnemyMechanics.preview(self, e)

func _log(text: String) -> void:
	var clean := RecentLog.line(text)
	if clean.is_empty(): return
	RecentLog.append(log, clean)
	EventBus.log_message.emit(clean)


## 战斗结束，把盘面/弃字堆中的己方与自我污染字归还永久字袋；敌方字清除。

func collect_back(owner_deck: Array) -> void:
	pass

var _spawn_pool: Array = []   ## 【分化】生长的字池缓存（BattleOps 使用）

# ---------------------------------------------------------------- 合击·结阵
func _word_activates_formation(w: WordData) -> bool:
	if w == null:
		return false
	for e in w.effects:
		if e.handler == "ability_shared_attack":
			return true
	return false


func begin_formation() -> void:
	formation_mode = true
	if formation_queue.is_empty():
		_log("合击：进入结阵（之后打出的词只登记，点「发动」一起结算）")


func _queue_play(path: Array, target: Dictionary, word: WordData, glyphs: Array) -> Dictionary:
	var res := {"ok": false, "word": word, "glyphs": glyphs, "solo": glyphs.size() == 1,
		"queued": true, "reason": "", "messages": [], "zero_effect": false,
		"not_implemented": word != null and not word.implemented}
	# 锁定的字不能再用（【击】除外，可共享）
	for p in path:
		if reserved_cells.has(p):
			res.queued = false
			res.reason = "该字已用于本次结阵"
			return res
	for pos in path:
		var inst: CharInstance = board.get_xy(pos)
		if inst != null and inst.glyph() != "击" and not reserved_cells.has(pos):
			reserved_cells.append(pos)
	var prepared := _prepare_play(path, target, word, glyphs)
	if word != null and EffectTargets.REVEALS.has(EffectTargets.interaction_of(word)):
		prepared["revealed"] = pending_reveal.duplicate()
		pending_reveal.clear()
		pending_choice.clear()
	formation_queue.append(prepared)
	if word != null and word.length() >= 2:
		# 下一次组词的斜连预算由首个登记词占用，不能给多个队列词重复使用。
		board.diagonal_steps_allowed = 0
		board.gap_steps_allowed = 0
		board.free_word_link = false
	res.ok = true
	var label: String = word.word if word != null else str(glyphs[0])
	res.messages = ["结阵登记：" + label]
	_log("结阵登记：" + label)
	return res


func resolve_formation() -> void:
	if not pending_reveal.is_empty():
		_log("请先完成或取消当前选字")
		return
	if formation_queue.is_empty():
		formation_mode = false
		reserved_cells.clear()
		return
	var queue := formation_queue.duplicate()
	formation_queue.clear()
	_log("—— 发动结阵（%d）——" % queue.size())
	var shared: Dictionary = {}
	for item in queue:
		_execute_prepared_play(item, shared)
		if not player.is_alive() or end_turn_requested:
			break
	for item in queue:
		for card in item.get("revealed", []):
			bag.append(card)
		item.erase("revealed")
	formation_queue.clear()
	reserved_cells.clear()
	formation_mode = false
	_log("结阵结算完毕")


# ---------------------------------------------------------------- 转发到 BattleOps（保持外部 API 不变）

func draw_to_board(count: int, excluded: Array = []) -> int:
	return BattleOps.draw_to_board(self, count, excluded)


## 精心：把玩家从字袋定向选中的字形，随机放入盘面空格。
func place_manual_draw(glyphs: Array) -> int:
	restore_reconnect_tiles()
	var quota := manual_draw_pending
	if quota <= 0:
		return 0
	manual_draw_pending = 0
	ensure_bag()
	var placed := 0
	for g in glyphs.slice(0, quota):
		var empties: Array = board.empty_indices()
		if empties.is_empty():
			break
		var found: CharInstance = null
		for i in range(bag.size() - 1, -1, -1):
			if bag[i].glyph() == str(g):
				found = bag[i]
				bag.remove_at(i)
				break
		if found == null:
			continue
		var pos: Vector2i = empties[rng.randi_range(0, empties.size() - 1)]
		place_from_pool(pos, found)
		placed += 1
	var chosen := placed
	# 放弃定向选择或字袋中已无该字时，用随机补字完成剩余额度。
	for i in quota - placed:
		if not _draw_one():
			break
		placed += 1
	var total := record_draw(placed, quota)
	_log("精心：定向放入 %d 枚字，随机补 %d 枚（随机落地）" % [chosen, total - chosen])
	_after_turn_draw()
	return total

func _draw_one() -> bool:
	return BattleOps._draw_one(self)

func draw_one_to(pos: Vector2i) -> CharInstance:
	return BattleOps.draw_one_to(self, pos)

func ensure_bag() -> void:
	return BattleOps.ensure_bag(self)

func reveal_from_bag(count: int) -> Array:
	return BattleOps.reveal_from_bag(self, count)

func return_pending_reveal() -> void:
	BattleOps.return_pending_reveal(self)
	pending_choice.clear()

func take_revealed(uid: int) -> CharInstance:
	return BattleOps.take_revealed(self, uid)

func inject_enemy_glyphs(count: int, pollution_id: String, fixed_glyph := "", source_id := -1) -> int:
	if count > 0 and has_ability("prevent_interference"):
		abilities.erase("prevent_interference")
		_log("防护：抵消本次敌方盘面干扰")
		return 0
	# 护：抵消一部分塞字（一次性，按层数消耗）
	if has_ability("guard_inject"):
		var reduced := mini(count, ability_value("guard_inject", 1))
		if reduced > 0:
			count -= reduced
			var v := ability_value("guard_inject", 1) - reduced
			if v <= 0:
				abilities.erase("guard_inject")
			else:
				abilities["guard_inject"] = v
			_log("护：抵消 %d 枚塞字" % reduced)
	var n: int = BattleOps.inject_enemy_glyphs(self, count, pollution_id, fixed_glyph, source_id)
	if n > 0 and has_ability("inject_bounty"):
		var g := earn_gold(n * BattleBalance.i("inject_bounty", 2))
		_log("加收：敌人注入 %d 枚，获得 %d 铜钱" % [n, g])
	return n

func spawn_scorch_into_bag(count: int) -> int:
	return BattleOps.spawn_scorch_into_bag(self, count)

func discard_instances() -> Array:
	return BattleOps.discard_instances(self)

func take_from_discard_by_uid(uid: int) -> CharInstance:
	return BattleOps.take_from_discard_by_uid(self, uid)

func get_discard_by_uid(uid: int) -> CharInstance:
	return BattleOps.get_discard_by_uid(self, uid)

func battle_card_counts() -> Dictionary:
	return BattleOps.battle_card_counts(self)

func apply_gravity() -> void:
	return BattleOps.apply_gravity(self)

func apply_gravity_left() -> void:
	return BattleOps.apply_gravity_left(self)

func apply_gravity_right() -> void:
	return BattleOps.apply_gravity_right(self)

func apply_gravity_count() -> int:
	return BattleOps.apply_gravity_count(self)

func rotate_2x2(top_left: Vector2i) -> void:
	return BattleOps.rotate_2x2(self, top_left)


## 转速：连续旋转（首次 + 后续「发动」）
func start_repeat_rotate(tile: Vector2i) -> void:
	repeat_rotate_tile = tile
	repeat_rotate_count = 0
	do_repeat_rotate()


func do_repeat_rotate() -> int:
	if repeat_rotate_tile.x < 0 or repeat_rotate_count >= BattleBalance.i("rotate_limit", 3):
		return repeat_rotate_count
	rotate_2x2(repeat_rotate_tile)
	repeat_rotate_count += 1
	if repeat_rotate_count >= BattleBalance.i("rotate_heat_start", 2):
		add_heat(BattleBalance.i("rotate_heat", 1))
	_log("转速：旋转一次（%d/3）" % repeat_rotate_count)
	return repeat_rotate_count


func end_repeat_rotate() -> void:
	repeat_rotate_tile = Vector2i(-1, -1)
	repeat_rotate_count = 0

func shift_row(row: int, dir: int) -> void:
	last_shift_row = row
	last_shift_dir = dir
	return BattleOps.shift_row(self, row, dir)

func rotate_3x3(anchor: Vector2i, dir: int) -> void:
	return BattleOps.rotate_3x3(self, anchor, dir)

func swap_cells(a: Vector2i, c: Vector2i) -> void:
	return BattleOps.swap_cells(self, a, c)

func destroy_2x2(top_left: Vector2i) -> int:
	return BattleOps.destroy_2x2(self, top_left)

func clear_board() -> int:
	return BattleOps.clear_board(self)

func converge_to(anchor: Vector2i) -> int:
	return BattleOps.converge_to(self, anchor)

## 盘上已经不带任何污染的字数（校勘尺按"洗干净了几枚"计）
func _clean_count() -> int:
	return board.cells.filter(func(c): return c != null and c.pollutions.is_empty()).size()


func cleanse_board() -> int:
	var n := BattleOps.cleanse_board(self)
	Relics.on_cleansed(self, n)
	return n

func cleanse_scorch() -> int:
	var before := _clean_count()
	var n := BattleOps.cleanse_scorch(self)
	# 校勘尺只算真正洗干净的字：还带着别的污染不算
	Relics.on_cleansed(self, _clean_count() - before)
	return n

## 问字签：玩家从三枚里挑一枚
func take_question(glyph: String) -> bool:
	return Relics.take_question(self, glyph)

func spawn_word_neighbors(center: Vector2i, max_count: int = 4, center_glyph: String = "") -> Array:
	return BattleOps.spawn_word_neighbors(self, center, max_count, center_glyph)

func create_temp_glyph(glyph: String) -> CharInstance:
	return BattleOps.create_temp_glyph(self, glyph)

func _pick_word_glyph_for(cell: Vector2i, center: Vector2i, center_glyph: String = "") -> String:
	return BattleOps._pick_word_glyph_for(self, cell, center, center_glyph)

func _spawn_pool_pick() -> String:
	return BattleOps._spawn_pool_pick(self)

func fuse_cards(p1: Vector2i, p2: Vector2i) -> Dictionary:
	var result := BattleOps.fuse_cards(self, p1, p2)
	if achievement != null and result.ok: achievement.emit_metrics([{"metric": "fusion_success", "amount": 1}])
	return result

func refine_pair(p1: Vector2i, p2: Vector2i) -> Dictionary:
	var result := BattleOps.refine_pair(self, p1, p2)
	if achievement != null and result.ok: achievement.emit_metrics([{"metric": "refine_uses", "amount": 1}])
	return result

func remove_scorch_in_circulation() -> int:
	return BattleOps.remove_scorch_in_circulation(self)

func has_adjacent_empty_pair() -> bool:
	return BattleOps.has_adjacent_empty_pair(self)

func _has_any_word_on_board() -> bool:
	return BattleOps._has_any_word_on_board(self)
