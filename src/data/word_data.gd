@tool
extends Resource
class_name WordData
## 一个“词”。玩家在盘面上把相邻的字按顺序连起来，匹配到 WordData 就触发效果。
##
## V0.2 Word Data Contract：每个词都保存设计来源与实现状态，便于和《完整词效总账》
## 逐条对号，不会因为没实现就“失踪”。改词只需改 .tres。

@export_group("词面")
@export var id: String = ""
@export var word: String = ""              ## 展示用，例如“击破”
@export var glyphs: Array[String] = []     ## 按顺序排列的组成字
@export var pinyin: String = ""
@export_multiline var description: String = ""   ## 运行时会由 BattleText.WORDS 覆盖；改说明请改 src/data/battle_text.gd
@export var tags: Array[String] = []
@export var allow_reversed: bool = false
@export_range(0, 4) var rarity: int = 1

@export_group("效果")
@export var effects: Array[EffectData] = []

@export_group("V0.2 交接字段")
## 防反 / 连携 / 流转 / 蓄放 / 热暴 / 经济 / 夺字 / 淬炼 / 空间
@export var group: String = ""
## 总账里的设计阶段（如“已完成逐组第一轮讨论”“P23初稿；未完成分组复审”）
@export_multiline var design_stage: String = ""
## 总账里的“最近讨论效果方向”原文
@export_multiline var effect_summary: String = ""
## 主效果处理器 id（未定稿时为空，不得悄悄套通用伤害）
@export var effect_handler_id: String = ""
@export var requires_target: int = 0        ## EffectData.Target
## immediate / delayed / next_word / persistent
@export var timing: String = "immediate"
@export var p25_implemented: bool = false
@export_multiline var implementation_delta: String = ""
## P1·重点机制 / P2·已试运行 / P3·补全词效 / P4·待复审
@export var priority: String = ""
@export_multiline var test_cases: String = ""
## 是否已经有可用效果（未定稿词为 false，可打出但无效果，需 UI 提示）
@export var implemented: bool = false
## 是否需要特殊交互（空=普通；"reveal_pick_board"=揭示 N 枚选 1 再点盘面）
@export var interaction: String = ""


func length() -> int:
	return glyphs.size()

## 预览、图鉴与能力提示共用整词说明；效果 note 仅用于单项效果的回退。
func describe() -> String:
	if not effect_summary.is_empty():
		return effect_summary
	if not description.is_empty():
		return description
	var parts: PackedStringArray = []
	for effect in effects:
		parts.append(effect.describe())
	return "；".join(parts)


func glyph_string() -> String:
	var s := ""
	for g in glyphs:
		s += g
	return s
