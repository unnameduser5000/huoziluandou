extends RefCounted
## Minimal adapter for saved encounter content; no navigation grid or 3D assembly.
var rooms := {}
var site := {"generation":{"kind":"node_graph", "version":1}}
var walk_step := 1.0
var grid_origin := Vector2.ZERO
var compact: RefCounted = null
var error := ""


func build(graph: Dictionary) -> bool:
	rooms.clear()
	if graph.has("generation_error"):
		error = str(graph.generation_error)
		return false
	site.generation.version = int(graph.get("layout_version", 1))
	var depths := {str(graph.start):-1}
	var queue: Array = [graph.start]
	var cursor := 0
	while cursor < queue.size():
		var id: String = queue[cursor]; cursor += 1
		for target: String in graph.rooms[id].next:
			var depth: int = int(depths[id]) + 1
			if depth > int(depths.get(target, -1)):
				depths[target] = depth
				queue.append(target)
	var columns := {}
	for id: String in graph.rooms:
		var spec: Dictionary = graph.rooms[id]
		var column := int(depths.get(id, spec.get("row", 0)))
		if not columns.has(column): columns[column] = []
		columns[column].append(id)
	for column: int in columns:
		var ids: Array = columns[column]
		for i in ids.size():
			var id: String = ids[i]
			var spec: Dictionary = graph.rooms[id]
			var lane := float(spec.get("lane", 1.5 + (i - (ids.size() - 1) * .5)))
			rooms[id] = {"name":str(spec.get("name", spec.kind)), "column":column,
				"lane":lane, "stand_cell":Vector2i(column, roundi(lane)), "kind":spec.kind}
	return not rooms.is_empty() and rooms.has(graph.start) and rooms.has(graph.boss)
