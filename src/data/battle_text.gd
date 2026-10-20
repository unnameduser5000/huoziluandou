extends RefCounted
class_name BattleText
## 玩家可见文案的**唯一生效来源**；`Database.reload()` 会把这里的文本写回每个词，
## 覆盖 `resources/words/*.tres` 与 `WordDescriptions` 的 `TEXT` 里同名字段。
##
## - `WORDS`：完整说明（图鉴 / 悬浮 / 预览）
## - `SHORT`：精简说明（`BattleText.word(word, true)`，窄屏与摘要用）
## - `CHARACTERS`：单字说明
## 数值一律用占位符 `{a0}`、`{p0_xxx}`、`{c_xxx}`，不要写死数字，否则改数值表后会与实机不符。

const WORDS := {
	"停息": "清空所有热度，获得「热度×{c_heat_block_mult}」点持久盾。结束你的回合。",
	"停火": "本回合结束时，若敌人没有实际掉血，则免疫敌方攻击（被护盾挡光也算没掉血）。",
	"死亡": "【？？？】",
	"反死亡": "【？？？】",
	"甲流": "【？？？】",
	"停电": "【？？？】",
	"充放电": "消耗全部储能：每点造成{a0}伤；每命中一段，下回合储能+{p0_refund}。",
	"充电": "获得{a0}储能。",
	"充电过热": "获得{p0_energy}储能、{p0_heat}热度。本场每次打出后补满盘面；之后每补1字，热度+{c_refill_heat}。",
	"充能": "获得{a0}储能，补{a1}字。",
	"再投资": "支付{p0_cost}铜钱，为字袋中1枚未镀金的字永久镀金，再补{a1}字。",
	"再铸": "选择本词以外{c_recast_target_count}枚未固定的字，换成随机临时字（新字不限于你的字袋）。",
	"冷心": "本回合攻击伤害×{c_cold_attack_mult}。本回合和下一回合都不能获得新的格挡或持久盾。",
	"冷热": "清空热度，每消耗1热度获得{c_heat_block_mult}持久盾。",
	"击破": "造成{a0}伤害，对护盾伤害×{p0_mult}。击破护盾后补{p0_draw}字。",
	"分利": "本回合每获得1铜钱，同时获得{c_profit_energy}储能。",
	"分化": "删除1枚未固定的字，在它上下左右的空格生成可组词的临时字。",
	"分心": "补{a0}字，造成{a1}伤害，获得{a2}持久盾，回复{a3}生命。",
	"分流": "移除至多{c_divert_limit}枚未固定的敌方字、临时字或自生污染字。不清除其他字上的污染。",
	"利息": "对目标造成当前总铜钱的{a0}%基础伤害。",
	"加强": "本场第N次打出【加强】，获得N层力量。",
	"加急": "立即补{c_next_bonus_draw}字。",
	"加收": "本回合敌人每成功塞入1字，获得{c_inject_bounty}铜钱。",
	"加热": "热度+{a0}。",
	"加速": "本回合每打出一个词，补{c_accel_draw}字、热度+{c_rotate_heat}（含本词）。",
	"化合": "选择2枚相邻、未固定的己方字，融合为同一字块，本场不能拆开。",
	"反击": "获得{a0}层反击。",
	"反复": "本回合下一个词打出后，复制它的每个字，随机放入空格成为临时字。",
	"反超": "生命低于上限的1/{c_hp_half_divisor}时补{p0_low}字，否则补{p0_high}字。",
	"反转": "选择一行或一列，将整行列倒序，空格也算。有固定字时不能选择。",
	"右击": "造成{a0}伤害，再将选中行向右移 1 格。",
	"右转": "将选中的3×3区域顺时针旋转90°。",
	"合击": "进入结阵：先选好要打出的词，再点「发动」依次生效。多个词可以共用同一枚【击】。",
	"合力": "获得{a0}临时格挡、{p0_energy}储能。",
	"合流": "从字袋顶部取1字，再从弃字堆选1枚己方原字，放进2个相邻空格。空格不足时不生效。",
	"合资": "本场支付铜钱时，每{c_joint_energy_cost}储能抵1铜钱，不足部分用铜钱支付。",
	"合金": "获得{a0}持久盾、{p0_gold}铜钱。",
	"回击": "造成{a0}伤害。本回合此前打出过攻击词时，再补{a1}字。",
	"回复": "获得{a0}层再生。",
	"回心": "回复{a0}生命，补{a1}字。",
	"回收": "从弃字堆取回本回合用掉的1枚己方原字，放到字袋顶部。",
	"回放": "取回上一词用掉、且仍在字袋或弃字堆的己方原字。优先放回原位，原位被占则放入空格。",
	"回流": "补{a0}字。",
	"回能": "立刻获得{c_energy_regen}储能；之后{regen_later}个回合开局各再获得{c_energy_regen}储能。",
	"回购": "支付{c_buy_cost}铜钱，从弃字堆选1枚己方原字放入指定空格，获得{c_buyback_layer}次额外使用。",
	"回转": "将选中的2×2区域顺时针旋转90°。",
	"回防": "获得{a0}临时格挡。本回合此前打出过攻击词时，再补{a1}字。",
	"复利": "获得{a0}铜钱，补{a1}字。",
	"复利投资": "为字袋中1枚未镀金的字永久镀金，获得{a1}铜钱。{fee}",
	"复合": "本回合下一个至少{c_long_word_threshold}字的词打出后，选其中1枚用掉的字，在原位留下临时字。",
	"复电": "返还最近一次消耗储能的1/{c_refund_divisor}，扣除已返还的部分；每笔只能退一次。",
	"左击": "造成{a0}伤害，再将选中行向左移 1 格。",
	"左右": "交换同一行的2个格子，允许选择空格。固定字不能移动。",
	"左转": "将选中的3×3区域逆时针旋转90°。",
	"开灯": "【？？？】",
	"强力": "获得{a0}层力量。",
	"强化": "选择一种字。本场打出该字时，额外发动一次单字效果，组词也生效。",
	"强心": "本场回合开始时回复{c_strong_heart_base}生命；心力每挡过1次致命伤，再多回复{c_heart_trigger_heal}生命。",
	"心力": "本场每打出1枚【心】，获得{c_heart_per_use}层心力。打出【心力】时也生效。",
	"心急": "补满盘面。下回合少补{a1}字。",
	"心蚀": "使目标获得{a0}层心蚀。",
	"心连心": "双方的当前生命、生命上限分别取平均。你的新生命上限保留到本局结束。",
	"急停": "清空热度，并把本场生成的灼热【热】从盘面、字袋、弃字堆中全部清掉。结束你的回合。",
	"急冷": "清空热度。下次正常补字减少{a1}字。",
	"急流": "选择一行或一列：未固定的己方原字回到字袋，再向该行列补入相同数量的字。",
	"急转": "交换选中的2格，热度+{a1}。固定字不能移动。",
	"急速": "本回合下一个词：先原地补{rapid_back}字，再额外补{rapid_extra}字，热度+{p0_heat}。",
	"投币": "支付至多{p0_max}铜钱，造成支付额×{a0}伤害。",
	"投放": "支付{c_buy_cost}铜钱，从字袋顶部{c_deploy_choices}字中选1字放入空格，获得{c_buyback_layer}次额外使用。",
	"投资": "支付{p0_cost}铜钱，为字袋中1枚未镀金的字永久镀金。",
	"护甲": "本场所有敌人行动后，将剩余临时格挡的{p0_percent}%转为额外的持久盾。",
	"护盾": "获得{a0}持久盾。",
	"收回": "将1枚未固定的己方原字放回字袋顶部，再从弃字堆选1枚原字填入它原来的格子。",
	"收复": "从弃字堆选至多2枚己方原字，放入2个相邻空格。",
	"收心": "将任意数量未固定的己方原字放回字袋，每枚回复{c_collect_heal}生命。可以不选。",
	"收息": "本回合每次花铜钱发动效果，同时获得等量持久盾。",
	"收放": "将1枚未固定的字移到空格，融合字整块移动，不交换其他字。",
	"收购": "支付{a0}铜钱，清除1枚敌方字的污染，并永久加入你的字袋。",
	"放回": "从弃字堆选1枚己方原字，放入指定空格。",
	"放心": "本回合先用护盾挡伤害，剩余伤害÷{c_guard_divisor}后再减{c_guard_flat}，最低为0。",
	"放火": "使目标获得{c_burn_layers}层灼烧。灼烧：敌人行动前失去「当前热度×{c_burn_heat_mult}」生命，每回合掉 1 层。",
	"放热": "消耗全部储能，获得等量热度，并造成消耗储能×{p0_per}伤害。",
	"放电": "消耗全部储能，每点造成1段{a0}伤害。目标死亡后，剩余攻击转向下一个敌人。",
	"流利": "本回合下一个词可以选用盘面任意位置的字，无需相邻。同一字块只能使用一次。",
	"流火": "将盘面所有【热】洗回字袋，再降低{c_wash_heat}热度。",
	"流转": "本回合每打出{c_flow_interval}种不同的词，补{a0}字。【流转】也计数，重复词不计。",
	"流连": "本回合每枚打出的字有{c_linger_percent}%概率留在原位；最多叠到{linger_max}%（2 层）。",
	"流速": "选择一行。本回合该行组词后，向用字空出的原格补字，可生效{a0}次。",
	"清心": "清除玩家身上的全部负面状态。不清除字块污染或怪物标记。",
	"清洗": "清除盘面所有字的污染，字的归属不变。不解除怪物标记。",
	"清流": "清除盘面所有灼热污染，再补{a0}字。",
	"清热": "热度−{a0}，清除盘面所有灼热标签。",
	"火力": "造成{a0}+当前热度×{p0_per}伤害。",
	"火化": "【？？？】",
	"火急": "从字袋取至多2字，逐枚选择空格放入，热度+{a1}。",
	"火热": "本场每因溢热新增1枚灼热【热】，对敌人造成{c_overheat_damage}非攻击伤害。",
	"火爆": "消耗全部热度，造成{a0}+消耗热度×{p0_per}伤害。",
	"火电": "清空热度，每{c_fire_electric_divisor}热度换1储能，余数舍去，并造成{c_fire_electric_damage}伤害。",
	"火速": "从字袋补至盘面有{c_fill_board_target}字；每补1字，热度+1。",
	"炼化": "热度-{p0_heat}，获得{p0_gold}铜钱。选择一种字，从本场移出1枚，战后归还。",
	"炼金": "获得{a0}铜钱，补{a1}字。",
	"热力": "清空热度，每消耗1热度，使下一次攻击每段伤害+{p0_per}。",
	"热心": "本场每增加1热度回复{c_warm_heal}生命；每降低1热度受到{c_warm_damage}伤害，可被护盾或减伤抵挡。",
	"热流": "按本回合补字数降低热度，最多降{p0_max}；每降低1热度，造成{a0}伤害。",
	"热能": "将全部热度转为等量储能。",
	"爆冷": "造成{a0}+上回合失去生命×{p0_per}伤害，并清空热度。",
	"爆破": "摧毁选中2×2区域内的字，包括本词；每摧毁1字，造成{a0}伤害。",
	"爆金币": "使目标获得爆金，再造成{p1_hits}段伤害，每段{a1}。",
	"电击": "造成{a0}+当前储能×{p0_per}伤害。",
	"电力": "本场：打出【左击】【右击】后，自动花{c_copy_layer_cost}储能，把那行再移 1 格。",
	"电流": "本回合补过字时获得{a0}储能，否则补{a0}字。",
	"电流过载": "本场每因溢热新增1枚灼热【热】，获得{c_overload_energy}储能，对敌人造成{c_overload_damage}非攻击伤害。",
	"电热": "消耗全部储能，每点转为1热度和{c_energy_heat_block_mult}临时格挡。",
	"电能": "本场每累计消耗{c_energy_spawn_step}储能，在空格生成1枚临时【电】。",
	"盾击": "消耗全部持久盾，造成{a0}伤害；每消耗{p0_per}持久盾，伤害再+{p0_bonus}，不足部分不计。",
	"盾反": "获得{a0}持久盾、{a1}层反击。",
	"破甲": "移除目标的全部临时格挡和持久盾。",
	"破防": "使目标获得{a0}层易伤。",
	"精分": "【？？？】",
	"精力": "本回合每打出一种不同的词，下回合多补1字。【精力】也计数，重复词不计。",
	"精心": "下回合少补{a0}字，但可以自己从字袋选字，随机放入空格。",
	"精炼": "选择2枚相同、未固定的己方原字：第一枚获得精炼效果，第二枚回到字袋。",
	"精金": "为字袋中1枚未镀金的字永久镀金。",
	"精铸": "固定1枚己方原字。本场每回合可用一次，用后留在原格；不能移动或替换。",
	"能力": "本场：每打出 {c_long_word_threshold} 字及以上的词，在原位补 {c_longword_draw} 字。",
	"蓄冷": "本场下次溢热时，少生成至多{c_overheat_block_cap}枚灼热【热】。触发后失效，剩余额度不保留。",
	"蓄力": "消耗全部储能，每点使下一次攻击每段伤害+{p0_per}。",
	"蓄热": "本场回合结束时降低至多{c_stored_heat_cool}热度；每降低1热度，获得{c_stored_heat_energy}储能。",
	"蓄电": "获得{a0}储能。词尾【电】上下左右每有1枚未参与本词的己方字，再获得{c_tail_energy_mult}储能。",
	"蓄能": "立即获得{c_immediate_idle_energy}储能。本场回合结束时，盘面还有可打出的词则获得{a0}储能。",
	"资金": "获得{a0}铜钱。",
	"超强": "获得{a0}层超强增幅（×{c_double_attack_mult}）。",
	"超能": "本回合下一个至少{c_long_word_threshold}字的词，每付{c_copy_layer_cost}储能，在1个空出的格子留下临时字。",
	"超能力": "本回合所有能力收益×{c_passive_multiplier}；消耗不翻倍。",
	"超载": "热度+{a1}；下一个组词（2 字及以上）的效果再结算一次。",
	"超速": "本回合下次补字翻倍，最多额外补{a0}字；每额外补1字，热度+{c_double_draw_heat}。",
	"超重": "清空盘面，每清掉1字造成{a0}伤害。己方原字进弃字堆，敌方字和临时字消失。",
	"转化": "从字袋顶部{p0_reveal}枚原字中选1字，替换盘上1枚未固定的字。其余字回袋。",
	"转速": "旋转选中的2×2区域，本次最多旋转{c_rotate_limit}次。从第{c_rotate_heat_start}次起，每次热度+{c_rotate_heat}。",
	"过冷": "清空热度。本回合下次增加热度时，改为每点获得{c_overcool_mult}持久盾。",
	"过分": "造成{a0}×本场【过分】生效次数的伤害。",
	"过火": "热度+{p0_heat}。本回合下一次攻击，额外造成攻击时热度×{p0_per}伤害。",
	"过热": "本场每回合首次溢热后，本回合下一个词额外补{a0}字；再打一次不刷新。",
	"过载": "补{a0}字，热度+{a1}。",
	"连击": "再结算一次上一个攻击词的效果，费用照付。",
	"连载": "本场每打出{c_serial_interval}个词，下一次攻击每段伤害+{p0_bonus}。重复词也计数，【连载】也计数。",
	"重击": "造成{a0}伤害，每枚因本词重力移动的字再加{p0_per}伤害。",
	"重力": "本场：每次打出后，盘面字向下填补空格。",
	"重合": "选1枚未固定的己方字，将盘上相同字块合并到该格，可用次数相加。",
	"重回": "将本回合此前最近用掉的至多{a0}枚己方原字放到字袋顶部，不包括本词。",
	"重复": "本场从下回合起，每回合第一个组词（2 字及以上）的效果再结算一次。",
	"重心": "选1字为中心，其他未固定字向它聚拢，直到不能再靠近。",
	"重甲": "获得{a0}持久盾。下次正常补字减少{a1}枚。",
	"重载": "本场热容+{a0}，下回合少补{p0_draw_penalty}字。",
	"重连": "将本词之外{c_recast_target_count}枚未固定的字暂时移出，下回合返回原位。",
	"重金": "支付{p0_cost}铜钱。若本回合击败全部敌人，获得{a0}铜钱；未完成不退款。",
	"重铸": "未固定的己方原字回袋，敌方字和临时字消失，再补相同数量的字。固定字留在原位。",
	"金币": "获得{a0}铜钱。",
	"铸币": "获得{a0}铜钱，在词尾原位生成1枚【币】；【币】可反复使用，战后移除。",
	"防反": "获得{a0}临时格挡、{a1}层反击。",
	"防御": "获得{a0}临时格挡。",
	"防御力": "本局从下一场战斗起，每次受伤减少{a0}伤害。只在首次打出时生效。",
	"防护": "本场下次敌人塞字时，取消整批塞字。触发后失效。",
	"防火": "本场打出带灼热污染的【热】不再扣除灼热伤害。",
	"防爆": "本场己方原字被摧毁时改为回袋，每救回1字获得{c_blastproof_block}持久盾。"
}

const SHORT := {
	"充放电": "耗尽储能：每点造成{a0}伤，命中一段下回合储能+{p0_refund}。",
	"充电过热": "获得{p0_energy}储能、{p0_heat}热度。本场自动补满，每补1字升温{c_refill_heat}。",
	"再投资": "支付{p0_cost}铜钱，永久镀金1字，补{a1}字。",
	"再铸": "选择另外{c_recast_target_count}枚未固定的字，换成随机临时字。",
	"分化": "删除1字，在周围空格生成可组词的临时字。",
	"分流": "移除至多{c_divert_limit}枚未固定的敌方字或临时杂字。",
	"加强": "本场第N次打出，获得N层力量。",
	"反复": "本回合下一个词的各字生成临时字，随机放入空格。",
	"合击": "进入结阵，可让多个词共用【击】，点「发动」一起打出。",
	"回放": "取回上一词用掉的己方原字，优先放回原位。",
	"回购": "支付{c_buy_cost}铜钱，取回1字放入空格，额外使用+{c_buyback_layer}。",
	"复利投资": "永久镀金1字，获得{a1}铜钱。{fee}",
	"复合": "下一个至少{c_long_word_threshold}字的词，保留其中1字的临时字。",
	"急停": "清空热度，清掉本场生成的灼热【热】。结束你的回合。",
	"急速": "本回合下一个词：先原地补{rapid_back}字，再额外补{rapid_extra}字，热度+{p0_heat}。",
	"投放": "支付{c_buy_cost}铜钱，从袋顶{c_deploy_choices}字中选1字放入空格，额外使用+{c_buyback_layer}。",
	"放火": "使目标获得{c_burn_layers}层灼烧：敌人行动前失去当前热度×{c_burn_heat_mult} 生命，每回合掉 1 层。",
	"流速": "本回合选中行组词后原位补字，还可生效{a0}次。",
	"火热": "本场溢热每生成1枚灼热【热】，对敌人造成{c_overheat_damage}非攻击伤害。",
	"电力": "本场：打出【左击】【右击】后再花{c_copy_layer_cost}储能，多移 1 格。",
	"超强": "获得{a0}层超强增幅（×{c_double_attack_mult}）。",
	"超能": "下一个至少{c_long_word_threshold}字的词，每花{c_copy_layer_cost}储能保留1枚临时字。",
	"超能力": "本回合所有能力收益×{c_passive_multiplier}。",
	"超载": "热度+{a1}；下一个词的效果再结算一次。",
	"过热": "本场每回合首次溢热后，下一个词额外补{a0}字。",
	"连载": "本场每打出{c_serial_interval}个词，下次攻击每段伤害+{p0_bonus}。",
	"重复": "本场从下回合起，每回合第一个词的效果再结算一次。",
	"重连": "暂时移出另外{c_recast_target_count}字，下回合返回原位。"
}

static func _number(value: Variant) -> String:
	if value is int or value is float:
		return str(int(value)) if float(value) == floor(float(value)) else str(value)
	return str(value)

static func _values(effects: Array) -> Dictionary:
	if BattleBalance.schema.is_empty(): BattleBalance.load_configuration()
	var params := {}
	for meta in BattleBalance.schema.core_params:
		params["c_" + str(meta.id)] = _number(BattleBalance.values.get("core/" + str(meta.id), meta.default))
	for i in effects.size():
		var effect: EffectData = effects[i]
		params["a%d" % i] = str(effect.amount)
		for key in effect.args: params["p%d_%s" % [i, key]] = _number(effect.args[key])
		if effect.handler == "counter" and effect.amount == 0: params["a%d" % i] = "1"
		if effect.handler == "damage_multi": params["p%d_hits" % i] = str(maxi(1, int(effect.args.get("hits", 1))))
	return params

static func word(word_data: WordData, concise := false) -> String:
	if not WORDS.has(word_data.word):
		return word_data.effect_summary if not word_data.effect_summary.is_empty() else word_data.description
	var params := _values(word_data.effects)
	params.regen_later = str(maxi(0, word_data.effects[0].amount - 1)) if word_data.word == "回能" else "0"
	params.regen_total = str(maxi(1, word_data.effects[0].amount)) if word_data.word == "回能" else "0"
	params.linger_max = str(mini(100, BattleBalance.i("linger_percent", 25) * BattleBalance.i("linger_layers_max", 2))) if word_data.word == "流连" else "0"
	if word_data.word == "急速":
		params.rapid_back = str(BattleBalance.i("rapid_return", 2))
		params.rapid_extra = str(maxi(0, int(word_data.effects[0].amount) - BattleBalance.i("rapid_return", 2)))
	var cost := int(word_data.effects[0].args.get("cost", 0)) if not word_data.effects.is_empty() else 0
	params.fee = "支付%d铜钱。" % cost if cost > 0 else ""
	var template: String = SHORT.get(word_data.word, WORDS[word_data.word]) if concise else WORDS[word_data.word]
	var result := template.format(params)
	var bonuses: Array[String] = []
	var labels := {"damage": "伤害", "damage_multi": "每段伤害", "heal": "回复生命", "block_temp": "临时格挡", "block_persist": "持久盾", "energy": "储能", "gold": "铜钱", "heat": "热度", "draw_random": "补字数"}
	for effect in word_data.effects:
		if effect.amount_per_extra_glyph == 0: continue
		var label: String = labels.get(effect.handler, "")
		if effect.handler in ["apply_status_self", "apply_status_enemy"]:
			var status := Database.get_status(effect.status_id)
			label = status.name + "层数" if status != null else "状态层数"
		if not label.is_empty(): bonuses.append("%s%+d" % [label, effect.amount_per_extra_glyph])
	if not bonuses.is_empty(): result += "长词有额外加成。" if concise else "超过2字后，每多1字：" + "、".join(bonuses) + "。"
	return result

const CHARACTERS := {
	"chu": "选择1个空格安放本字。本场固定，每回合可用一次，不受移动影响。",
	"contract": "受到{a0}伤害，下一次正常补字减少{a1}字。",
	"debt": "受到{a0}伤害。",
	"oblivion": "下一次正常补字减少{a0}字。",
	"bao": "造成{a0}伤害，热度+{a1}。",
	"bi": "本回合下一次打出时，铜钱费用减少{a0}，最低为0。只生效一次。",
	"chao": "本回合下一个词可以跨过1个横向或竖向空格，不能跨过有字的格子。",
	"chong": "获得{a0}储能，下回合多补{a1}字。",
	"dian": "获得{a0}储能。",
	"dun": "获得{a0}持久盾。",
	"fan": "本回合下次受到敌方攻击后，对攻击者造成{a0}伤害。被护盾全挡也生效，多段攻击只生效一次。",
	"fang": "获得{a0}临时格挡。",
	"fang2": "造成{a0}伤害；也可花{c_release_cost}储能，改为造成{c_release_damage}伤害。",
	"fen": "复制相邻己方字块的首字，放在本字原位。复制的字仅供组词，用后消失，不继承强化。",
	"fu": "本回合下次消耗储能时返还至多{a0}点，不超过消耗量。只生效一次。",
	"gou": "支付{c_buy_cost}铜钱，从字袋选1枚己方原字放入本字原位。",
	"guo": "可单打腾出空格；组词连线时，也可以穿过【过】连接其他字。",
	"he": "本回合下一个词打出后，获得{c_combine_block}临时格挡、{c_combine_energy}储能。",
	"hu": "下次敌人塞字时，少塞{a0}字。触发后失效。",
	"hua": "花{heat_cost}热度，获得{a0}储能。热度不足时只弃掉本字。",
	"hui": "在本字原位随机换入1字。",
	"huo": "热度+{a0}。",
	"ji": "造成{a0}伤害。",
	"ji2": "补{a0}字，热度+{a1}。不会补回本次打出的字块。",
	"jia": "下回合开始时，获得{a0}临时格挡。",
	"jia2": "本回合下一枚单打字的首项伤害、格挡、治疗或储能+{a0}，不增加费用或热度。",
	"jin": "获得{a0}铜钱。",
	"jing": "查看字袋顶部{c_precision_choices}字，选1字放入本字原位。其余留在字袋；空袋时只弃字。",
	"leng": "热度{a0}。",
	"li": "下一次攻击的首段伤害+{a0}。",
	"li2": "本回合已获得过铜钱时，再获得{a0}铜钱；否则无效果。",
	"lian": "本回合下一个词打出后，补{a0}字。",
	"lian2": "移除相邻1枚未固定的敌方字、临时字或自生污染字，获得{c_refine_junk_gold}铜钱，热度+{c_refine_junk_heat}。",
	"liu": "下回合多补{a0}字。",
	"neng": "本回合下次获得储能时，额外获得{a0}点。",
	"po": "先移除目标至多{p0_shield}护盾，再造成{a0}伤害。",
	"pollution": "没有单字效果，可单打腾出空格。",
	"qiang": "本回合攻击的每段伤害+{a0}。",
	"qing": "清除相邻1字的1种污染。不改变归属，不解除怪物标记。",
	"re": "热度+{a0}。",
	"shi": "造成{a0}伤害。",
	"shou": "补{a0}字，不会补回本次打出的字块。",
	"su": "本回合下一个词打出后，补{c_speed_draw}字，热度+{c_speed_heat}。",
	"ting": "热度-{a0}，立即结束回合，敌人照常行动。",
	"tou": "支付{c_throw_cost}铜钱，将相邻1枚未固定的字移到指定空格。",
	"xi": "清除相邻1字的全部污染。不改变归属，不解除怪物标记。",
	"xi2": "热度-{a0}。本回合尚未让敌人掉血时，回复{c_rest_heal}生命。",
	"xin": "回复{a0}生命。",
	"xu": "下回合开始时，获得{a0}储能。",
	"you": "每行字向右填补空格，相对顺序不变，固定字不动。",
	"yu": "下次受到伤害时减少{a0}点，触发后失效。",
	"zai": "本回合热容+{a0}，下回合恢复；热度不变。",
	"zai2": "将上一手打出的最后1字复制为临时字，优先放在原位，被占则找空格。不能复制【再】。",
	"zhang": "获得{a0}临时格挡。",
	"zhong": "每列字向下填补空格，相对顺序不变，固定字不动。",
	"zhu": "将相邻1枚未固定的己方原字放回字袋，原位随机换入另一字块。没有替换字时保留原字。",
	"zhuan": "将相邻1枚未固定的字移到本字空出的格子。",
	"zi": "获得{a0}铜钱。",
	"zuo": "每行字向左填补空格，相对顺序不变，固定字不动。",
	"ai": "没有单字效果，可单打腾出空格。",
	"deng": "【？？？】",
	"gu": "【？？？】",
	"hui2": "【？？？】",
	"hui3": "没有单字效果，可单打腾出空格。",
	"kai": "【？？？】",
	"si": "【？？？】",
	"wang": "【？？？】",
	"yue": "【？？？】"
}

static func character(data: CharacterData) -> String:
	if not CHARACTERS.has(data.id): return data.description
	var params := _values(data.solo_effects)
	params.heat_cost = str(int(data.solo_effects[0].args.get("heat_cost", 2))) if not data.solo_effects.is_empty() else "2"
	return str(CHARACTERS[data.id]).format(params)

static func clean(text: String) -> String:
	var replacements := {
		"金币": "铜钱",
		"本词以外": "本词之外",
		"临挡": "临时格挡",
		"超强翻倍": "超强增幅",
		"正价支付": "付费",
		"本阶段储能净消费": "本回合已消耗储能（扣除退款）",
		"落地": "放入空格",
		"成词": "组词"
	}
	for old in replacements: text = text.replace(old, replacements[old])
	var ids := RegEx.new()
	ids.compile("#[0-9]+")
	return ids.sub(text, "", true)


static func enemy_move(move: EnemyMoveData) -> String:
	match move.kind:
		EnemyMoveData.Kind.ATTACK: return "造成%d伤害。" % move.damage
		EnemyMoveData.Kind.MULTI: return "攻击%d次，每次%d伤害。" % [move.hits, move.damage]
		EnemyMoveData.Kind.BLOCK: return "获得%d临时格挡。" % move.block
		EnemyMoveData.Kind.ATTACK_BLOCK: return "造成%d伤害，获得%d临时格挡。" % [move.damage, move.block]
		EnemyMoveData.Kind.BUFF, EnemyMoveData.Kind.DEBUFF:
			var status := Database.get_status(move.status_id)
			return "%s获得%d层%s。" % ["玩家" if move.kind == EnemyMoveData.Kind.DEBUFF else "敌人", move.status_stacks, status.name if status != null else "状态"]
		EnemyMoveData.Kind.INJECT: return "向空格塞入%d枚%s。" % [move.inject_count, "【%s】" % move.inject_glyph if not move.inject_glyph.is_empty() else "随机字"]
	return {"gravity": "将每行字向左靠拢。", "rotate": "将中央2×2顺时针旋转。", "swallow": "吞入弃字堆的1枚己方原字。", "flip": "标记同一行的2枚字。", "bomb_mark": "预告爆破位置并补充格挡。", "wait": "本次不攻击，准备下一次行动。"}.get(move.mechanic_action, move.title)
