extends RefCounted
## 远征事件内容目录。事件文案、插图、选项与效果都在这里维护；效果执行见 EventEffects。
##
## 庭院模式按 `acts` 过滤事件池，并在同一局内尽量避开已经出现过的事件。
## 每个事件固定三个选项：主要收益、替代/风险收益、无代价离开，便于玩家快速判断。
## `tags` 只用于内容检索与文档，不参与结算。

const EVENTS := [
	# ---------------------------------------------------------------- 第一幕起即可出现
	{
		"id": "ink_pool",
		"illustration": "res://assets/events/ink_pool.png",
		"title": "墨池遗字",
		"body": "北海之外，传说有幽都之山，黑水从山腹流出，沿着看不见的沟壑进入园中。\n池底的字一沉一浮，偶尔露出一笔，像玄狐的尾巴扫过水面。",
		"acts": [1, 2],
		"tags": ["resource", "risk", "character"],
		"options": [
			{"text": "探手取字（失去 8 气血，获得一枚字）", "primary": true, "effects": [
				{"type": "damage", "amount": 8},
				{"type": "gain_character", "min_rarity": 0, "max_rarity": 2},
			]},
			{"text": "掬一捧墨（获得 18 铜钱）", "effects": [{"type": "gold", "amount": 18}]},
			{"text": "静观而退", "effects": []},
		],
	},
	{
		"id": "broken_stele",
		"illustration": "res://assets/events/broken_stele.png",
		"title": "断碑",
		"body": "半截石碑立在荒径，碑面被雨水磨出一道深痕。\n泥里半掩着半页残簿，只余“姓名”和“归处”两栏。",
		"acts": [1, 2, 3],
		"tags": ["character", "gold", "risk"],
		"options": [
			{"text": "拓下残字（获得一枚稀有字）", "primary": true, "effects": [
				{"type": "gain_character", "min_rarity": 2, "max_rarity": 4},
			]},
			{"text": "敲下碑角（失去 5 气血，获得 25 铜钱）", "effects": [
				{"type": "gold", "amount": 25},
				{"type": "damage", "amount": 5},
			]},
			{"text": "拾起残簿（获得遗物「生死簿」）", "requires": {"type": "lacks_relic", "relic": "ruin"}, "effects": [
				{"type": "gain_relic", "relic": "ruin"},
			]},
		],
	},
	{
		"id": "old_bookshop",
		"illustration": "res://assets/events/old_bookshop.png",
		"title": "旧书肆",
		"body": "书肆后面立着一座小小的惜字塔。塔口的字纸灰还是温的，灰里偶尔露出半个没有烧完的字。\n老板的位置只剩一盏将熄的灯。",
		"acts": [1, 2, 3],
		"tags": ["removal", "heal", "gold"],
		"options": [
			{"text": "撕下一页（删掉字袋中一枚字）", "primary": true, "effects": [
				{"type": "remove_character", "count": 1},
			]},
			{"text": "诵读静心（回复 18 点气血）", "effects": [{"type": "heal", "amount": 18}]},
			{"text": "顺手牵金（获得 14 铜钱）", "effects": [{"type": "gold", "amount": 14}]},
		],
	},
	{
		"id": "lantern_pages",
		"illustration": "res://assets/events/lantern_pages_v1.png",
		"illustration_style": "scene",
		"title": "灯下拾页",
		"body": "廊下的灯没有灯油，却一直亮着。灯光像烛龙睁开的一只眼，替这座庭院按住黑夜。\n风把几页残纸翻到光亮里，纸上还有未干的字。",
		"acts": [1, 2],
		"tags": ["heal", "character", "gold"],
		"options": [
			{"text": "凑近读页（回复 12 气血）", "effects": [{"type": "heal", "amount": 12}]},
			{"text": "抽一页带走（失去 4 气血，获得一枚字）", "primary": true, "effects": [
				{"type": "damage", "amount": 4},
				{"type": "gain_character", "min_rarity": 0, "max_rarity": 1},
			]},
			{"text": "掐灯取芯（获得 12 铜钱）", "effects": [{"type": "gold", "amount": 12}]},
		],
	},
	{
		"id": "well_echo",
		"illustration": "res://assets/events/well_echo_v1.png",
		"illustration_style": "scene",
		"title": "井中回声",
		"body": "井底没有水声。\n极深处自有一道干枯的嗓子在念：“不及黄泉，无相见也。”每念一遍，井壁上的湿痕便向上爬一寸。",
		"acts": [1, 2],
		"tags": ["heal", "curse", "gold"],
		"options": [
			{"text": "俯身听声（回复 15 气血）", "effects": [{"type": "heal", "amount": 15}]},
			{"text": "吊起井中物（获得 26 铜钱和一枚【债】字）", "primary": true, "effects": [
				{"type": "gold", "amount": 26},
				{"type": "gain_pollution", "character": "debt", "count": 1},
			]},
			{"text": "转身离开", "effects": []},
		],
	},
	{
		"id": "foundation_stone",
		"illustration": "res://assets/events/foundation_stone_v1.png",
		"illustration_style": "scene",
		"title": "础石留字",
		"body": "“山云蒸，柱础润。”旧础半埋在荒径。\n础面刻着“石敢当，镇百鬼，压灾殃”，字痕深得像替整座园子压住了什么。",
		"acts": [1, 2, 3],
		"tags": ["special", "character", "space", "risk"],
		"weight": 1.0,
		"options": [
			{"text": "撬起础石（失去 8 气血，获得【础】）", "primary": true, "effects": [
				{"type": "damage", "amount": 8},
				{"type": "gain_character", "glyph": "础"},
			]},
			{"text": "拓下石纹（获得 20 铜钱）", "effects": [{"type": "gold", "amount": 20}]},
			{"text": "倚础避祟（回复 12 气血）", "effects": [{"type": "heal", "amount": 12}]},
		],
	},
	{
		"id": "borrow_life",
		"illustration": "res://assets/events/borrow_life_v1.png",
		"illustration_style": "scene",
		"title": "借寿",
		"body": "门外立着一位青衫客，怀抱无芯暗灯，隔缝递来一张素白寿契。\n“借几日阳寿，先暖一暖身子。日后自有人来取。”",
		"acts": [1, 2, 3],
		"tags": ["life", "debt", "heal", "relic"],
		"weight": 1.0,
		"options": [
			{"text": "借八日阳寿（回复 8 气血，寿债 +8）", "primary": true, "effects": [{"type": "borrow_life", "amount": 8}]},
			{"text": "借十六日阳寿（回复 16 气血，寿债 +16）", "effects": [{"type": "borrow_life", "amount": 16}]},
			{"text": "不借", "effects": []},
		],
	},
	{
		"id": "debt_collector",
		"illustration": "res://assets/events/debt_collector_v1.png",
		"illustration_style": "scene",
		"title": "讨债",
		"body": "门外立着持旧契的人。\n契上朱笔只写着你的名字，寿数一栏已被墨涂死。\n他抬手叩门：“无寿可支，便拿命来抵。”",
		"allow_leave": false,
		"acts": [1, 2, 3],
		"tags": ["life", "debt", "curse"],
		"weight": 5.0,
		"requires": {"type": "has_relic", "relic": "life_debt"},
		"options": [
			{"text": "以气血偿还（失去 {debt} 气血；不足部分按 2:1 折算为最大气血）", "primary": true, "effects": [{"type": "repay_life_hp"}]},
			{"text": "以寿命偿还（最大气血 -{debt_max}）", "effects": [{"type": "repay_life_max_hp"}]},
			{"text": "赖账（寿债 +8，获得一枚【债】字）", "effects": [{"type": "refuse_debt", "amount": 8}, {"type": "gain_pollution", "character": "debt", "count": 1}]},
		],
	},
	{
		"id": "mossy_steps",
		"illustration": "res://assets/events/mossy_steps_v1.png",
		"illustration_style": "scene",
		"title": "苔阶残局",
		"body": "石阶上的残局依着青苔裂痕布就，棋子是几枚磨平了棱角的旧活字。\n最后一着悬在边上未落，像是下到险处，执子的人忽然听见谁在叫他的名字。",
		"acts": [1],
		"tags": ["character", "gold"],
		"options": [
			{"text": "收走棋子（获得一枚字）", "primary": true, "effects": [
				{"type": "gain_character", "min_rarity": 0, "max_rarity": 1},
			]},
			{"text": "拂乱棋局（获得 14 铜钱）", "effects": [{"type": "gold", "amount": 14}]},
			{"text": "原样离开", "effects": []},
		],
	},
	{
		"id": "rain_corridor",
		"illustration": "res://assets/events/rain_corridor_v1.png",
		"illustration_style": "scene",
		"title": "雨打空廊",
		"body": "冷雨穿过空廊，檐下摊着一函湿透的字纸。\n墨迹被水冲成细蛇，纸页却仍微微发热。",
		"acts": [1, 2],
		"tags": ["heal", "character", "risk"],
		"options": [
			{"text": "避雨等停（回复 20% 气血）", "effects": [{"type": "heal_percent", "amount": 20}]},
			{"text": "冒雨抢字（失去 6 气血，获得一枚较稀有的字）", "primary": true, "effects": [
				{"type": "damage", "amount": 6},
				{"type": "gain_character", "min_rarity": 1, "max_rarity": 3},
			]},
			{"text": "捡起廊下铜钱（获得 9 铜钱）", "effects": [{"type": "gold", "amount": 9}]},
		],
	},
	{
		"id": "pine_roots",
		"illustration": "res://assets/events/pine_roots_v1.png",
		"illustration_style": "scene",
		"title": "松根埋字",
		"body": "老松的根须下露出一角木活字，像被谁匆忙埋下。\n土里还有另一枚，旁边留着一截已经发黑的香根。",
		"acts": [1, 2],
		"tags": ["character", "risk"],
		"options": [
			{"text": "刨根取字（失去 7 气血，获得两枚字）", "primary": true, "effects": [
				{"type": "damage", "amount": 7},
				{"type": "gain_character", "min_rarity": 0, "max_rarity": 1, "count": 2},
			]},
			{"text": "折一段松枝（获得 12 铜钱）", "effects": [{"type": "gold", "amount": 12}]},
			{"text": "让字留在土里", "effects": []},
		],
	},
	{
		"id": "angler_pool",
		"illustration": "res://assets/events/angler_pool_v1.png",
		"illustration_style": "scene",
		"title": "池边钓叟",
		"body": "池边坐着一位钓叟，蓑笠覆面，浮子一动不动。\n鱼篓里只有水声，水声里偶尔混进一声很远的哭。",
		"acts": [1, 2, 3],
		"tags": ["gold", "heal", "risk"],
		"options": [
			{"text": "替他守竿（失去 5 气血，获得 18 铜钱）", "primary": true, "effects": [
				{"type": "damage", "amount": 5},
				{"type": "gold", "amount": 18},
			]},
			{"text": "听他说鱼（回复 14 气血）", "effects": [{"type": "heal", "amount": 14}]},
			{"text": "看一会便走", "effects": []},
		],
	},
	{
		"id": "stone_table_score",
		"illustration": "res://assets/events/stone_table_score_v1.png",
		"illustration_style": "scene",
		"title": "石桌残谱",
		"body": "石桌上摊着半卷曲谱，字迹被落叶盖了大半。\n尾调断处，压着一枚铜铸的“息”字，像谁把最后一口气留在了纸上。",
		"acts": [1, 2],
		"tags": ["character", "heal", "gold"],
		"options": [
			{"text": "记下谱中字（获得【息】）", "primary": true, "effects": [
				{"type": "gain_character", "glyph": "息"},
			]},
			{"text": "在石凳上歇息（回复 16 气血）", "effects": [{"type": "heal", "amount": 16}]},
			{"text": "扫开落叶（获得 6 铜钱）", "effects": [{"type": "gold", "amount": 6}]},
		],
	},
	{
		"id": "kite_in_tree",
		"illustration": "res://assets/events/kite_in_tree_v1.png",
		"illustration_style": "scene",
		"title": "纸鸢挂树",
		"body": "一只纸鸢挂在松枝上，牵线上系着一枚小字。\n风一吹，纸鸢便转向北方，像在替看不见的门引路。",
		"acts": [1, 2],
		"tags": ["character", "risk", "gold"],
		"options": [
			{"text": "爬树去取（失去 6 气血，获得一枚字）", "primary": true, "effects": [
				{"type": "damage", "amount": 6},
				{"type": "gain_character", "min_rarity": 1, "max_rarity": 3},
			]},
			{"text": "扯线拽下（获得 10 铜钱）", "effects": [{"type": "gold", "amount": 10}]},
			{"text": "看它挂着", "effects": []},
		],
	},
	{
		"id": "old_gardener",
		"illustration": "res://assets/events/old_gardener_v1.png",
		"illustration_style": "scene",
		"title": "老园丁",
		"body": "老园丁在池边修剪枯枝，说这园子会记住每一个来过的人。\n他的剪子没有声音，剪下的枝条却一根根落进看不见的水里。",
		"acts": [1, 2, 3],
		"tags": ["heal", "gold", "max_hp"],
		"options": [
			{"text": "帮他搬石（失去 6 气血，获得 16 铜钱）", "primary": true, "effects": [
				{"type": "damage", "amount": 6},
				{"type": "gold", "amount": 16},
			]},
			{"text": "讨一碗茶（回复 25% 气血）", "effects": [{"type": "heal_percent", "amount": 25}]},
			{"text": "听他讲园中旧事（最大气血 +10）", "effects": [
				{"type": "max_hp", "amount": 10},
			]},
		],
	},
	# ---------------------------------------------------------------- 第二幕起
	{
		"id": "old_inkstone",
		"illustration": "res://assets/events/old_inkstone_v1.png",
		"illustration_style": "scene",
		"title": "旧砚生苔",
		"body": "废弃的砚台里积着雨水，苔色沿砚池爬了一圈。\n池底沉着一点未化的墨，墨面映出的不是你的脸，而是一只闭着的眼睛。",
		"acts": [2, 3],
		"tags": ["character", "gold", "heal"],
		"options": [
			{"text": "研开残墨（失去 6 气血，获得一枚稀有字）", "primary": true, "effects": [
				{"type": "damage", "amount": 6},
				{"type": "gain_character", "min_rarity": 2, "max_rarity": 3},
			]},
			{"text": "刮下苔衣（获得 22 铜钱）", "effects": [{"type": "gold", "amount": 22}]},
			{"text": "舀水净砚（回复 18 气血）", "effects": [{"type": "heal", "amount": 18}]},
		],
	},
	{
		"id": "ferry_no_boat",
		"illustration": "res://assets/events/ferry_no_boat_v1.png",
		"illustration_style": "scene",
		"title": "渡口无舟",
		"body": "渡口的木桩还系着断绳，对岸的字碑在雾里只剩轮廓。\n浊水泛黄，河面上不见一舟一木，唯余两岸空对的石墩。",
		"acts": [2, 3],
		"tags": ["character", "risk", "gold"],
		"options": [
			{"text": "泅水过去（失去 10 气血，获得一枚稀有字）", "primary": true, "effects": [
				{"type": "damage", "amount": 10},
				{"type": "gain_character", "min_rarity": 2, "max_rarity": 4},
			]},
			{"text": "拆下渡板（获得 20 铜钱）", "effects": [{"type": "gold", "amount": 20}]},
			{"text": "沿岸绕行", "effects": []},
		],
	},
	{
		"id": "lost_type_case",
		"illustration": "res://assets/events/lost_type_case_v1.png",
		"illustration_style": "scene",
		"title": "无主字匣",
		"body": "廊下放着一只无主字匣，锁扣已经锈死。\n里面传出字块轻碰的声音，像许多人在黑暗中互相报着名字。",
		"acts": [2, 3],
		"tags": ["character", "gold", "heal"],
		"options": [
			{"text": "撬开字匣（失去 5 气血，获得两枚字）", "primary": true, "effects": [
				{"type": "damage", "amount": 5},
				{"type": "gain_character", "min_rarity": 0, "max_rarity": 2, "count": 2},
			]},
			{"text": "整个卖给行商（获得 25 铜钱）", "effects": [{"type": "gold", "amount": 25}]},
			{"text": "交给守园人（回复 12 气血）", "effects": [{"type": "heal", "amount": 12}]},
		],
	},
	{
		"id": "rubbing_worker",
		"illustration": "res://assets/events/rubbing_worker_v1.png",
		"illustration_style": "scene",
		"title": "破碑拓工",
		"body": "一个拓工蹲在破碑前，纸上的字比碑上多出一行。\n他没有抬头，只把多出来的那一行压在手掌底下。",
		"acts": [2, 3],
		"tags": ["gold", "character", "heal"],
		"options": [
			{"text": "帮他拓字（失去 5 气血，获得 20 铜钱）", "primary": true, "effects": [
				{"type": "damage", "amount": 5},
				{"type": "gold", "amount": 20},
			]},
			{"text": "买下多余那行（失去 4 气血，获得一枚稀有字）", "effects": [
				{"type": "damage", "amount": 4},
				{"type": "gain_character", "min_rarity": 2, "max_rarity": 3},
			]},
			{"text": "帮他压纸（回复 10 气血）", "effects": [{"type": "heal", "amount": 10}]},
		],
	},
	{
		"id": "floating_lantern",
		"illustration": "res://assets/events/floating_lantern_v1.png",
		"illustration_style": "scene",
		"title": "墨池浮灯",
		"body": "一盏纸灯漂在墨池上，灯芯是半枚烧焦的字。\n灯影一灭，庭院便像闭上了眼；灯影再亮，池面已经换了一个季节。",
		"acts": [2, 3],
		"tags": ["heal", "gold", "max_hp"],
		"options": [
			{"text": "捞起纸灯（最大气血 -4，回复 20 气血）", "primary": true, "effects": [
				{"type": "max_hp", "amount": -4},
				{"type": "heal", "amount": 20},
			]},
			{"text": "取灯油（获得 18 铜钱）", "effects": [{"type": "gold", "amount": 18}]},
			{"text": "任它漂远（回复 10 气血）", "effects": [{"type": "heal", "amount": 10}]},
		],
	},
	# ---------------------------------------------------------------- 第三幕
	{
		"id": "night_knock",
		"illustration": "res://assets/events/night_knock_v1.png",
		"illustration_style": "scene",
		"title": "夜半敲门",
		"body": "夜半，门被敲了三下。门缝里塞进一枚湿冷的字和一张折成三角的符牒。\n符上写着“奉城隍命，追亡人”，名字那一笔被水洇开了。",
		"acts": [3],
		"tags": ["curse", "character", "gold"],
		"options": [
			{"text": "开门迎客（获得一枚稀有字和一枚【忘】字）", "primary": true, "effects": [
				{"type": "gain_character", "min_rarity": 2, "max_rarity": 4},
				{"type": "gain_pollution", "character": "oblivion", "count": 1},
			]},
			{"text": "闭门不出（回复 15 气血）", "effects": [{"type": "heal", "amount": 15}]},
			{"text": "收下那支勾魂笔（获得遗物「判官笔」）", "requires": {"type": "lacks_relic", "relic": "death"}, "effects": [
				{"type": "gain_relic", "relic": "death"},
			]},
		],
	},
	{
		"id": "niche_offering",
		"illustration": "res://assets/events/niche_offering_v1.png",
		"illustration_style": "scene",
		"title": "碑后小龛",
		"body": "断碑背后有个小龛，供着一枚发亮的铜钱和半截香。\n香灰下压着一本薄簿，翻开的那页写着你的名字；“罪由”一栏还是空白。",
		"acts": [2, 3],
		"tags": ["curse", "gold", "heal"],
		"options": [
			{"text": "取走供钱（获得 24 铜钱和一枚【契】字）", "primary": true, "effects": [
				{"type": "gold", "amount": 24},
				{"type": "gain_pollution", "character": "contract", "count": 1},
			]},
			{"text": "续上一炷香（回复 20 气血）", "effects": [{"type": "heal", "amount": 20}]},
			{"text": "合掌退开", "effects": []},
		],
	},
	# ---------------------------------------------------------------- 遗物事件第一批
	{
		"id": "jade_case",
		"illustration": "res://assets/events/jade_case_v1.png",
		"illustration_style": "scene",
		"title": "韫椟待贾",
		"body": "“有美玉于斯，韫椟而藏诸？求善贾而沽诸？”\n旧库梁上悬着一只木椟，椟里传出玉声，像有人在里面轻轻叩门。",
		"acts": [1, 2],
		"tags": ["relic", "gold", "risk"],
		"weight": 0.8,
		"options": [
			{"text": "试椟（支付 8 铜钱）", "append": "玉声近了。", "primary": true, "requires": {"type": "gold_at_least", "amount": 8}, "effects": [{"type": "spend_gold", "amount": 8}], "goto": "one"},
			{"text": "请出椟中玉（支付 25 铜钱，50% 得遗物）", "append": "玉声近了。", "requires": {"type": "gold_at_least", "amount": 25}, "effects": [{"type": "spend_gold", "amount": 25}], "goto": "two"},
			{"text": "韫椟而藏（回复 8 气血）", "effects": [{"type": "heal", "amount": 8}]},
		],
		"nodes": {
			"start": {
				"body": "“有美玉于斯，韫椟而藏诸？求善贾而沽诸？”\n旧库梁上悬着一只木椟，椟里传出玉声，像有人在里面轻轻叩门。",
				"options": [
					{"text": "试椟（支付 8 铜钱）", "append": "玉声近了。", "primary": true, "requires": {"type": "gold_at_least", "amount": 8}, "effects": [{"type": "spend_gold", "amount": 8}], "goto": "one"},
					{"text": "请出椟中玉（支付 25 铜钱，50% 得遗物）", "append": "玉声近了。", "requires": {"type": "gold_at_least", "amount": 25}, "effects": [{"type": "spend_gold", "amount": 25}], "goto": "two"},
					{"text": "韫椟而藏（回复 8 气血）", "effects": [{"type": "heal", "amount": 8}]},
				],
			},
			"one": {
				"body": "玉声已经抵住椟盖，椟缝里漏出一线温光。\n再投一次，玉声会更近；现在开椟，只有四分之一的机会。",
				"options": [
					{"text": "再投（支付 15 铜钱，成功率升到 50%）", "append": "玉声近了。", "primary": true, "requires": {"type": "gold_at_least", "amount": 15}, "effects": [{"type": "spend_gold", "amount": 15}], "goto": "two"},
					{"text": "开椟（25% 得随机普通遗物）", "effects": [{"type": "gain_relic", "relic": "random", "chance": 0.25, "fallback_gold": 10}]},
					{"text": "收手（获得 5 铜钱）", "effects": [{"type": "gold", "amount": 5}]},
				],
			},
			"two": {
				"body": "椟盖已经发热，玉声不再叩门，改为在椟中缓慢地转。\n再投一次，玉声会更近；现在开椟，机会一半。",
				"options": [
					{"text": "再投（支付 18 铜钱，成功率升到 75%）", "append": "玉声近了。", "primary": true, "requires": {"type": "gold_at_least", "amount": 18}, "effects": [{"type": "spend_gold", "amount": 18}], "goto": "three"},
					{"text": "开椟（50% 得随机普通遗物）", "effects": [{"type": "gain_relic", "relic": "random", "chance": 0.5, "fallback_gold": 15}]},
					{"text": "收手（获得 8 铜钱）", "effects": [{"type": "gold", "amount": 8}]},
				],
			},
			"three": {
				"body": "锁扣自己弹开一线，玉光从缝里照到你脸上。\n再投一次，椟中玉就会自己出来；现在开椟，机会已有四分之三。",
				"options": [
					{"text": "再投（支付 25 铜钱，成功率升到 100%）", "append": "玉声近了。", "primary": true, "requires": {"type": "gold_at_least", "amount": 25}, "effects": [{"type": "spend_gold", "amount": 25}], "goto": "four"},
					{"text": "开椟（75% 得随机普通遗物）", "effects": [{"type": "gain_relic", "relic": "random", "chance": 0.75, "fallback_gold": 20}]},
					{"text": "收手（获得 12 铜钱）", "effects": [{"type": "gold", "amount": 12}]},
				],
			},
			"four": {
				"body": "椟盖无声地滑开，玉光把整间旧库照成一片温白。\n这一次不必再赌，玉已经在椟口。",
				"options": [
					{"text": "开椟（获得一件随机普通遗物）", "primary": true, "effects": [{"type": "gain_relic", "relic": "random", "chance": 1.0, "fallback_gold": 40}]},
					{"text": "收手（获得 15 铜钱）", "effects": [{"type": "gold", "amount": 15}]},
					{"text": "把椟供回梁上（回复 10 气血）", "effects": [{"type": "heal", "amount": 10}]},
				],
			},
		},
	},
	{
		"id": "buy_case",
		"illustration": "res://assets/events/buy_case_v1.png",
		"illustration_style": "scene",
		"title": "买椟还珠",
		"body": "“楚人有卖其珠于郑者，为木兰之柜，薰以桂椒，缀以珠玉。”\n摊主将空椟推至案前，沉香未散：“识珠者早已携珠去，椟留至今，只候明眼人。”",
		"acts": [1, 2, 3],
		"tags": ["relic", "character", "gold"],
		"weight": 0.6,
		"options": [
			{"text": "买椟（失去 6 气血，获得一件随机普通遗物）", "primary": true, "effects": [
				{"type": "damage", "amount": 6},
				{"type": "gain_relic", "relic": "random", "fallback_gold": 35},
			]},
			{"text": "还珠（获得一枚稀有字）", "effects": [{"type": "gain_character", "min_rarity": 2, "max_rarity": 4}]},
			{"text": "卖椟（获得 22 铜钱）", "effects": [{"type": "gold", "amount": 22}]},
		],
	},
	{
		"id": "carry_jade",
		"illustration": "res://assets/events/carry_jade_v1.png",
		"illustration_style": "scene",
		"title": "怀璧其罪",
		"body": "“匹夫无罪，怀璧其罪。”\n废祠供着一块无主璧，璧上血沁未干。守祠人悄立暗处，不阻不拦，只把这八个字又念了一遍。",
		"acts": [2, 3],
		"tags": ["relic", "curse", "risk"],
		"weight": 0.7,
		"options": [
			{"text": "怀璧而走（获得随机普通遗物与 1 枚【债】字）", "primary": true, "effects": [
				{"type": "if", "condition": {"type": "has_normal_relic_choice"}, "then": [
					{"type": "gain_relic", "relic": "random"},
					{"type": "gain_pollution", "character": "debt", "count": 1},
				], "else": [{"type": "gold", "amount": 30}]},
			]},
			{"text": "碎璧（失去 5 气血，获得 28 铜钱）", "effects": [
				{"type": "damage", "amount": 5},
				{"type": "gold", "amount": 28},
			]},
			{"text": "拜而不取（回复 12 气血）", "effects": [{"type": "heal", "amount": 12}]},
		],
	},
	{
		"id": "snatch_gold",
		"illustration": "res://assets/events/snatch_gold_v1.png",
		"illustration_style": "scene",
		"title": "齐人攫金",
		"body": "“取金之时，不见人，徒见金。”\n闹市里有人捧着空匣而立。过路客人都说里面空无一物，唯有你走近时，瞧见匣底正沉沉泛着赤金的光。",
		"acts": [2, 3],
		"tags": ["relic", "curse", "gold"],
		"weight": 0.7,
		"options": [
			{"text": "攫金（最大气血 -3，获得随机普通遗物）", "primary": true, "effects": [
				{"type": "if", "condition": {"type": "has_normal_relic_choice"}, "then": [
					{"type": "max_hp", "amount": -3},
					{"type": "gain_relic", "relic": "random"},
				], "else": [{"type": "gold", "amount": 30}]},
			]},
			{"text": "报官（获得 24 铜钱）", "effects": [{"type": "gold", "amount": 24}]},
			{"text": "掩目而过（回复 8 气血）", "effects": [{"type": "heal", "amount": 8}]},
		],
	},
	{
		"id": "bed_censer",
		"illustration": "res://assets/events/bed_censer_v1.png",
		"illustration_style": "scene",
		"title": "被中香炉",
		"body": "“长安巧工丁缓者……又作卧褥香炉，一名被中香炉。”\n旧箱里滚出一只小香炉，炉身还温着。炉盖内刻着一行小字：安魂。",
		"acts": [1, 2],
		"tags": ["relic", "heal"],
		"weight": 0.6,
		"options": [
			{"text": "取炉（失去 6 气血，获得【安神香】）", "primary": true, "requires": {"type": "lacks_relic", "relic": "sleep"}, "effects": [
				{"type": "damage", "amount": 6},
				{"type": "gain_relic", "relic": "sleep"},
			]},
			{"text": "闻香（回复 14 气血）", "effects": [{"type": "heal", "amount": 14}]},
			{"text": "卖炉（获得 24 铜钱）", "effects": [{"type": "gold", "amount": 24}]},
		],
	},
	# ---------------------------------------------------------------- 删字与净化第一批
	{
		"id": "trim_words",
		"illustration": "res://assets/events/trim_words_v1.png",
		"illustration_style": "scene",
		"title": "裁字",
		"body": "“规范本体谓之镕，剪截浮词谓之裁。”\n廊下坐着一位校书人，俯首默坐，正翻检你散落案头的字块。\n他手握极薄的小刀，刀尖翻飞，只剔繁芜字骨，不伤分毫皮肉。",
		"acts": [2, 3],
		"tags": ["deletion", "character", "risk"],
		"weight": 0.8,
		"options": [
			{"text": "裁去一字（删掉字袋中一枚字）", "primary": true, "effects": [
				{"type": "remove_character", "count": 1},
			]},
			{"text": "裁去两字（删 2 枚字，失去 5 气血，获得一枚稀有字）", "effects": [
				{"type": "remove_character", "count": 2},
				{"type": "damage", "amount": 5},
				{"type": "gain_character", "min_rarity": 2, "max_rarity": 4},
			]},
			{"text": "合上字袋（回复 8 气血）", "effects": [{"type": "heal", "amount": 8}]},
		],
	},
	{
		"id": "delete_poems",
		"illustration": "res://assets/events/delete_poems_v1.png",
		"illustration_style": "scene",
		"title": "删诗",
		"body": "“古者诗三千馀篇，及至孔子，去其重，取可施于礼义。”\n废书院堆积残简三千，卷首虫蚀俱尽。残灰中坐着一个持笔人，只留下还能读的句子。",
		"acts": [2, 3],
		"tags": ["deletion", "max_hp"],
		"weight": 0.6,
		"options": [
			{"text": "删去两枚字（删 2 枚字，最大气血 +6）", "primary": true, "effects": [
				{"type": "remove_character", "count": 2},
				{"type": "max_hp", "amount": 6},
			]},
			{"text": "删去一枚字（删 1 枚字，获得 20 铜钱）", "effects": [
				{"type": "remove_character", "count": 1},
				{"type": "gold", "amount": 20},
			]},
			{"text": "不删（回复 10 气血）", "effects": [{"type": "heal", "amount": 10}]},
		],
	},
	{
		"id": "return_brush",
		"illustration": "res://assets/events/return_brush_v1.png",
		"illustration_style": "scene",
		"title": "还笔",
		"body": "“吾有笔在卿处多年，可以见还。”\n梦中有人立于榻前，青衫悬腕，索要一管五色笔。\n惊醒摸向怀中，掌心果然攥着一枚从未见过的古字，冷如生铁。",
		"acts": [2, 3],
		"tags": ["deletion", "relic", "risk"],
		"weight": 0.5,
		"options": [
			{"text": "还笔（删一枚稀有字，获得一件随机普通遗物）", "primary": true, "requires": {"type": "has_character_min_rarity", "amount": 2}, "effects": [
				{"type": "remove_character", "count": 1, "min_rarity": 2, "max_rarity": 4},
				{"type": "gain_relic", "relic": "random", "fallback_gold": 35},
			]},
			{"text": "不还（获得 1 枚【忘】字）", "effects": [
				{"type": "gain_pollution", "character": "oblivion", "count": 1},
			]},
			{"text": "以墨代笔（失去 10 气血，保留那枚字）", "effects": [{"type": "damage", "amount": 10}]},
		],
	},
	{
		"id": "ink_wash",
		"illustration": "res://assets/events/ink_wash_v1.png",
		"illustration_style": "scene",
		"title": "浣墨",
		"body": "“濯淖污泥之中，蝉蜕于浊秽。”\n池水黑得像一方旧砚。\n水面无风自裂，一枚浸透血垢的旧木字沉入池中，墨污竟如蜕皮般一层层化散开去。",
		"acts": [1, 2, 3],
		"tags": ["purify", "pollution", "heal"],
		"weight": 0.8,
		"options": [
			{"text": "浣污染字（失去 4 气血，清除 1 枚污染字）", "primary": true, "requires": {"type": "pollution_count_at_least", "amount": 1}, "effects": [
				{"type": "damage", "amount": 4},
				{"type": "remove_pollution", "count": 1},
			]},
			{"text": "浣污染字（失去 8 气血，清除 2 枚污染字）", "requires": {"type": "pollution_count_at_least", "amount": 2}, "effects": [
				{"type": "damage", "amount": 8},
				{"type": "remove_pollution", "count": 2},
			]},
			{"text": "掬水自饮（回复 12 气血）", "effects": [{"type": "heal", "amount": 12}]},
		],
	},
	{
		"id": "purge_mirror",
		"illustration": "res://assets/events/purge_mirror_v1.png",
		"illustration_style": "scene",
		"title": "涤除",
		"body": "“涤除玄览，能无疵乎？”\n庭中平放着一面照骨的水镜。\n镜面不映人影，倒照出案头洗尽铅华的澄澈字迹。镜边搁着一只粗陶空碗，碗底干涸的裂纹形如四字：以血洗镜。",
		"acts": [2, 3],
		"tags": ["purify", "pollution", "max_hp", "risk"],
		"weight": 0.4,
		"options": [
			{"text": "涤除污染字（最大气血 -3，清除全部污染字）", "primary": true, "requires": {"type": "pollution_count_at_least", "amount": 2}, "effects": [
				{"type": "remove_pollution", "count": 99},
				{"type": "max_hp", "amount": -3},
			]},
			{"text": "只照一照（清除 1 枚污染字）", "requires": {"type": "pollution_count_at_least", "amount": 1}, "effects": [
				{"type": "remove_pollution", "count": 1},
			]},
			{"text": "退开（回复 10 气血）", "effects": [{"type": "heal", "amount": 10}]},
		],
	},
	{
		"id": "xuanji_board",
		"illustration": "res://assets/events/xuanji_board_v1.png",
		"illustration_style": "scene",
		"title": "璇玑拾字",
		"body": "“织锦为回文旋图诗以赠滔，宛转循环以读之，词甚凄惋。”\n廊下挂着一幅未收的锦，锦上字字相连，像一场没有下完的棋。你伸手，锦线便自己亮了一条路。",
		"acts": [2, 3],
		"tags": ["character", "minigame"],
		"weight": 0.5,
		"options": [
			{"text": "循线读字（进入璇玑字盘，选一个词；获得词中的字）", "primary": true, "board": true, "effects": []},
			{"text": "把锦留在原处（离开）", "effects": []},
			{"text": "不拆此锦（离开）", "effects": []},
		],
	},
	{
		"id": "lantern_riddle",
		"illustration": "res://assets/events/lantern_riddle_v1.png",
		"illustration_style": "scene",
		"title": "无字灯",
		"body": "“谜也者，回互其辞，使昏迷也。”\n廊下悬着三盏无字素灯，灯腹各隐一道谜骨。\n灯影憧憧，暗语待射。射中哪一盏，哪一盏便随你走。",
		"acts": [1, 2, 3],
		"tags": ["character", "riddle", "game"],
		"weight": 0.6,
		"options": [
			{"text": "“表里如一”（打一字）", "effects": []},
			{"text": "“千里相逢”（打一字）", "effects": []},
			{"text": "“斜月三星洞”（打一字）", "effects": []},
		],
	},
	{
		"id": "chaos_dice",
		"illustration": "res://assets/events/chaos_dice_v1.png",
		"illustration_style": "scene",
		"title": "乱文骨骰",
		"body": "“成枭而牟，呼五白些。”\n庭中落着一枚骨骰，六面都是字，没有一面是数。它自己滚到你脚边，停在“乱”字上。",
		"acts": [2, 3],
		"tags": ["relic", "chaos", "risk"],
		"weight": 0.5,
		"options": [
			{"text": "拾起骨骰（获得【乱文骨骰】，字袋全部重铸）", "primary": true, "requires": {"type": "lacks_relic", "relic": "chaos_dice"}, "effects": [
				{"type": "gain_relic", "relic": "chaos_dice"},
			]},
			{"text": "踢回草丛（获得 20 铜钱）", "effects": [{"type": "gold", "amount": 20}]},
			{"text": "绕开它（回复 10 气血）", "effects": [{"type": "heal", "amount": 10}]},
		],
	},
	{
		"id": "battle_relic",
		"illustration": "res://assets/events/battle_relic_v1.png",
		"illustration_style": "scene",
		"title": "死地取器",
		"body": "“投之亡地然后存，陷之死地然后生。”\n庭院尽头站着一个披甲的字影，脚边压着一件旧器。长刃当道：胜者得器，败者留命。",
		"allow_leave": false,
		"acts": [2, 3],
		"tags": ["relic", "battle", "risk"],
		"weight": 0.5,
		"options": [
			{"text": "拔剑应战（进入战斗；胜后获得随机普通遗物）", "primary": true, "spawn": "battle", "spawn_relic": "random", "effects": []},
			{"text": "以血换器（失去 12 气血，获得随机普通遗物）", "effects": [
				{"type": "damage", "amount": 12},
				{"type": "gain_relic", "relic": "random", "fallback_gold": 35},
			]},
			{"text": "以金换器（失去 30 铜钱，获得随机普通遗物）", "requires": {"type": "gold_at_least", "amount": 30}, "effects": [
				{"type": "spend_gold", "amount": 30},
				{"type": "gain_relic", "relic": "random", "fallback_gold": 35},
			]},
		],
	},
	{
		"id": "shefu",
		"illustration": "res://assets/events/shefu_v1.png",
		"illustration_style": "scene",
		"title": "射覆",
		"body": "“上尝使诸数家射覆，置守宫盂下，射之。”\n石桌上倒扣着三只陶碗，碗下各压着一样东西。覆局既定，一人一念，只许揭其一。",
		"acts": [1, 2, 3],
		"tags": ["game", "character"],
		"weight": 0.6,
		"options": [
			{"text": "揭开左边的碗", "effects": []},
			{"text": "揭开中间的碗", "effects": []},
			{"text": "揭开右边的碗", "effects": []},
		],
	},
]

## 旧版自由探索的「谜」面板，使用独立的地图语境与结算流程。
const MYSTERY_EVENTS := [
	{"title": "残页", "text": "墨渍里夹着半页旧谱。", "a": "撕下来（气血 −6，得一枚稀有字）", "b": "不碰它"},
	{"title": "污墨", "text": "一砚发臭的墨，摊主说能换钱。", "a": "收下（❖ +18，字袋混进 1 枚污染字）", "b": "走开"},
	{"title": "雾中灯", "text": "远处有人提灯。", "a": "跟上去（耗 2 步，地图迷雾散开一大片）", "b": "不跟"},
]


static var _registry: Array = []
static var _loaded := false


static func registered_events() -> Array:
	if _loaded: return _registry
	_registry = EVENTS.duplicate(true); _loaded = true
	var directory := "res://assets/events/definitions"
	var files := DirAccess.get_files_at(directory) if DirAccess.dir_exists_absolute(directory) else PackedStringArray()
	files.sort()
	for file in files:
		var name := file.trim_suffix(".remap")
		if not name.ends_with(".tres") and not name.ends_with(".res"): continue
		register_file(directory.path_join(name))
	return _registry


static func register_file(path: String) -> bool:
	if not ResourceLoader.exists(path): return false
	var resource = load(path)
	if resource==null or not resource.get("event") is Dictionary: return false
	return register(resource.event)


static func register(event: Dictionary) -> bool:
	if not _loaded: registered_events()
	var id := str(event.get("id",""))
	if id.is_empty() or _registry.any(func(item):return str(item.id)==id): return false
	if str(event.get("title","")).is_empty() or event.get("options",[]).size()!=3: return false
	_registry.append(event.duplicate(true))
	return true
