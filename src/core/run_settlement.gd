extends RefCounted
class_name RunSettlement
## A score snapshot contains only plain values, never live battle/run references.
const NODE_POINTS := 100
const KILL_POINTS := 30
const RELIC_POINTS := 40
const GOLD_POINTS := 5
const GOLD_CAP := 300
const ACT_POINTS := 500


static func calculate(completed_progress: int, defeated_enemies: int, pressure_points: int, relic_count: int, remaining_gold: int, completed_acts: int = 0) -> Dictionary:
	var progress := maxi(0, completed_progress)
	var kills := maxi(0, defeated_enemies)
	var relics := maxi(0, relic_count)
	var gold := maxi(0, remaining_gold)
	var acts := maxi(0, completed_acts)
	var rows := [
		{"label": "行旅足迹", "detail": "%d 处 × %d" % [progress, NODE_POINTS], "score": progress * NODE_POINTS},
		{"label": "破关", "detail": "%d 幕 × %d" % [acts, ACT_POINTS], "score": acts * ACT_POINTS},
		{"label": "末战击倒", "detail": "%d 名 × %d" % [kills, KILL_POINTS], "score": kills * KILL_POINTS},
		{"label": "末战攻坚", "detail": "按敌方气血削减比例", "score": clampi(pressure_points, 0, 150)},
		{"label": "收集遗物", "detail": "%d 件 × %d" % [relics, RELIC_POINTS], "score": relics * RELIC_POINTS},
		{"label": "剩余铜钱", "detail": "%d 枚 × %d · 上限 %d" % [gold, GOLD_POINTS, GOLD_CAP], "score": mini(GOLD_CAP, gold * GOLD_POINTS)},
	]
	var total := 0
	for row in rows:
		total += int(row.score)
	return {"rows": rows, "total": total}


static func from_run(battle: BattleState, node: MapNodeData, expedition: Expedition = null, elite_branch: bool = false) -> Dictionary:
	var progress := GameState.visited.size()
	var completed_acts := maxi(0, GameState.act_index - 1)
	var kind := "普通战"
	var pressure_cap := 30
	if elite_branch or (node != null and node.type == MapNodeData.Type.ELITE):
		kind = "精英"
		pressure_cap = 75
	elif node != null and node.type == MapNodeData.Type.BOSS:
		kind = "首领"
		pressure_cap = 150
	if expedition != null:
		var locations := {}
		for key in GameState.visited:
			if str(key).begins_with("ex:"): locations[key] = true
		for key in expedition.taken:
			locations["ex:%d:site:%s" % [expedition.act, key]] = true
		for key in expedition.amb_done:
			locations["ex:%d:ambush:%s" % [expedition.act, key]] = true
		progress = locations.size()
		completed_acts = maxi(0, expedition.act - 1) + (1 if expedition.boss_down else 0)
	var defeated := 0
	var max_health := 0
	var lost_health := 0
	if battle != null:
		for enemy in battle.enemies:
			if not enemy.is_alive(): defeated += 1
			max_health += maxi(0, enemy.max_hp)
			lost_health += clampi(enemy.max_hp - enemy.hp, 0, enemy.max_hp)
	var pressure := int(floor(float(lost_health) / maxf(1, max_health) * pressure_cap))
	var result := calculate(progress, defeated, pressure, GameState.relics.size(), GameState.gold, completed_acts)
	result.rows[0].detail = "%d 处 × %d · 已完成地点" % [progress, NODE_POINTS] if expedition != null else "%d 节点 × %d" % [progress, NODE_POINTS]
	result.rows[3].detail = "%s · %d/%d × %d" % [kind, lost_health, max_health, pressure_cap]
	result["mode"] = "墨途远征" if expedition != null else "经典冒险"
	result["location"] = "第 %d 幕 · %s" % [expedition.act if expedition != null else GameState.act_index, node.title if node != null else "未竟之途"]
	return result
