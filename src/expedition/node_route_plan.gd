extends RefCounted
## Build the routes first, then assign encounters. Never consumes gameplay RNG.
const COLUMNS := 15
const LANES := 5
const PATHS := 6
const MIN_NODES := 46
const MAX_NODES := 64
const FIRST_SPECIAL_ROW := 5 # Elites and random rest sites start at stop six.
# Spire-style room bag. Use the A1+ elite density to retain elite route choices.
const ROOM_SHARES := {"shop":.05, "rest":.12, "elite":.128, "event":.22}


static func generate(seed_value: int, act: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("node-route:%d:%d:v2" % [seed_value, act])
	var graph := {}
	var ordered: Array = []
	var fitted := false
	for layout_attempt in 32:
		graph = _routes(seed_value, act, rng)
		if graph.rooms.size() < MIN_NODES or graph.rooms.size() > MAX_NODES or not _has_choices(graph): continue
		ordered = graph.rooms.keys()
		ordered.sort_custom(func(a, b):
			var left: Dictionary = graph.rooms[a]
			var right: Dictionary = graph.rooms[b]
			return left.row < right.row if left.row != right.row else left.lane < right.lane)
		var sorted_rooms := {}
		for id: String in ordered: sorted_rooms[id] = graph.rooms[id]
		graph.rooms = sorted_rooms
		fitted = true
		break
	if not fitted:
		return {"rooms":{}, "generation_error":"未能生成连通的分叉路线，请重新开始冒险。"}
	_encounters(graph, ordered, rng)
	for id: String in ordered:
		var spec: Dictionary = graph.rooms[id]
		spec.number = ordered.find(id) + 1
		spec.name = {"start":"入狱", "boss":"幕末首领"}.get(spec.kind, "%02d · %s" % [spec.row + 1, _label(spec.kind)])
		spec.content_seed = rng.randi_range(1, 1 << 30)
		spec.jitter = rng.randf_range(-.17, .17) if spec.row in range(1, COLUMNS - 1) else 0.0
		spec.offset_x = rng.randf_range(-.10, .10) if spec.row in range(1, COLUMNS - 1) else 0.0
	return graph


static func _routes(seed_value: int, act: int, rng: RandomNumberGenerator) -> Dictionary:
	var graph := {"schema":1, "layout_kind":"node_graph", "layout_version":2,
		"encounter_version":4, "seed":seed_value, "act":act, "lane_count":LANES, "rooms":{}, "edges":[], "groups":[], "start":"start", "boss":"boss"}
	_add(graph, "start", -1, (LANES - 1) * .5)
	var starts: Array = [rng.randi_range(0, 1), 2, rng.randi_range(3, 4)]
	if rng.randf() < .45:
		var remaining: Array = range(LANES).filter(func(lane): return not starts.has(lane))
		starts.append(remaining[rng.randi_range(0, remaining.size() - 1)])
	for path in PATHS:
		var lane: int = starts[path] if path < starts.size() else starts[rng.randi_range(0, starts.size() - 1)]
		var previous := "start"
		for column in COLUMNS:
			if column > 0:
				var candidates: Array = []
				var weights: Array = []
				for next_lane in range(maxi(0, lane - 1), mini(LANES - 1, lane + 1) + 1):
					var target := _id(column, next_lane)
					if _crosses_lane(graph, previous, column, next_lane): continue
					candidates.append(next_lane)
					var weight := 1.15 if next_lane == lane else 1.0
					if graph.rooms.has(target): weight *= 1.1
					if graph.rooms[previous].next.has(target): weight *= .35
					weights.append(weight)
				lane = candidates[_weighted_index(weights, rng)]
			var id := _id(column, lane)
			if not graph.rooms.has(id): _add(graph, id, column, lane)
			_link(graph, previous, id)
			previous = id
	_add(graph, "boss", COLUMNS, (LANES - 1) * .5)
	for id: String in graph.rooms:
		if graph.rooms[id].row == COLUMNS - 1: _link(graph, id, "boss")
	return graph


static func _encounters(graph: Dictionary, ordered: Array, rng: RandomNumberGenerator) -> void:
	# Prepare all types together, rather than spending events first and filling
	# the rest with combat. No per-route event, combat or elite-count targets.
	var unassigned: Array = []
	var quota_basis := 0
	for id: String in ordered:
		var spec: Dictionary = graph.rooms[id]
		spec.kind = ""
		# Match the reference count: connected map nodes except the penultimate
		# stop. Entry/boss are separate from the fifteen playable map columns.
		if spec.row >= 0 and spec.row < COLUMNS and spec.row != COLUMNS - 2: quota_basis += 1
		if id == graph.start: spec.kind = "start"
		elif id == graph.boss: spec.kind = "boss"
		elif spec.row == 0: spec.kind = "battle"
		elif spec.row == 8: spec.kind = "treasure"
		elif spec.row == COLUMNS - 1: spec.kind = "rest"
		else: unassigned.append(id)
	var bag: Array = []
	var quotas := {}
	for kind: String in ROOM_SHARES:
		quotas[kind] = roundi(quota_basis * ROOM_SHARES[kind])
		for count in quotas[kind]: bag.append(kind)
	while bag.size() < unassigned.size(): bag.append("battle")
	_shuffle(bag, rng)
	var defaulted: Array = []
	for id: String in unassigned:
		var chosen := -1
		for index in bag.size():
			if _can_assign(graph, id, bag[index]): chosen = index; break
		if chosen >= 0: graph.rooms[id].kind = bag.pop_at(chosen)
		else: defaulted.append(id)
	# Only an unfillable slot falls back to ordinary combat. It does not turn
	# a whole column into a service, event or elite and does not reroll paths.
	for id: String in defaulted: graph.rooms[id].kind = "battle"
	var unused := {}
	for kind: String in bag: unused[kind] = int(unused.get(kind, 0)) + 1
	graph["room_quotas"] = quotas
	graph["quota_basis"] = quota_basis
	graph["unplaced_rooms"] = unused
	graph["defaulted_rooms"] = defaulted


static func _can_assign(graph: Dictionary, id: String, kind: String) -> bool:
	var row: int = graph.rooms[id].row
	if kind in ["elite", "rest"] and row < FIRST_SPECIAL_ROW: return false
	if kind == "rest" and row >= COLUMNS - 2: return false
	if kind in ["elite", "rest", "shop", "treasure"] and _neighbour_kind(graph, id, kind, false): return false
	return not _sibling_kind(graph, id, kind)


static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for index in range(items.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var saved = items[index]
		items[index] = items[other]; items[other] = saved


static func _sibling_kind(graph: Dictionary, id: String, kind: String) -> bool:
	for parent: String in graph.rooms[id].previous:
		for sibling: String in graph.rooms[parent].next:
			if sibling != id and graph.rooms[sibling].get("kind", "") == kind: return true
	return false


static func _has_choices(graph: Dictionary) -> bool:
	# Every playable route gets at least four choices, including its entry branch.
	var minimum := {"start":0}
	for row in range(-1, COLUMNS):
		for id: String in graph.rooms:
			var spec: Dictionary = graph.rooms[id]
			if spec.row != row: continue
			var count: int = minimum[id] + int(spec.next.size() > 1)
			for target: String in spec.next: minimum[target] = mini(int(minimum.get(target, COLUMNS)), count)
	return int(minimum[graph.boss]) >= 4


static func _neighbour_kind(graph: Dictionary, id: String, kind: String, include_next := true) -> bool:
	var ids: Array = graph.rooms[id].previous.duplicate()
	if include_next: ids.append_array(graph.rooms[id].next)
	return ids.any(func(other): return graph.rooms[other].get("kind", "") == kind)


static func _weighted_index(weights: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for weight: float in weights: total += weight
	var roll := rng.randf() * total
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0: return i
	return weights.size() - 1


static func _id(column: int, lane: int) -> String:
	return "r%02d_%d" % [column + 1, lane]


static func _add(graph: Dictionary, id: String, column: int, lane: float) -> void:
	graph.rooms[id] = {"id":id, "row":column, "lane":lane, "next":[], "previous":[]}


static func _label(kind: String) -> String:
	return {"battle":"战斗", "elite":"精英", "event":"奇遇", "rest":"休息", "shop":"字肆", "treasure":"宝藏"}.get(kind, kind)


static func _crosses_lane(graph: Dictionary, from: String, column: int, lane: float) -> bool:
	for edge: Dictionary in graph.edges:
		if graph.rooms[edge.to].row != column: continue
		if (graph.rooms[from].lane - graph.rooms[edge.from].lane) * (lane - graph.rooms[edge.to].lane) < 0: return true
	return false


static func _crosses(graph: Dictionary, from: String, to: String) -> bool:
	return _crosses_lane(graph, from, int(graph.rooms[to].row), float(graph.rooms[to].lane))


static func _link(graph: Dictionary, from: String, to: String) -> void:
	if graph.rooms[from].next.has(to): return
	graph.rooms[from].next.append(to); graph.rooms[to].previous.append(from)
	graph.edges.append({"id":from + ">" + to, "from":from, "to":to})
