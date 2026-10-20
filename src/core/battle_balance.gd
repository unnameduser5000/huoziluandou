extends RefCounted
class_name BattleBalance
## 策划 Excel 的唯一战斗配置。结构与枚举不开放，只校验并覆盖数值。
const SCHEMA_PATH := "res://data/balance/battle_schema.json"
static var config_path := "res://data/balance/battle.json"
static var schema: Dictionary = {}
static var payload: Dictionary = {}
static var values: Dictionary = {}
static var warning := ""
static var _resources: Dictionary = {}
static var _bindings: Dictionary = {}

static func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK: return null
	return parser.data

static func load_configuration() -> void:
	schema = _read(SCHEMA_PATH) if _read(SCHEMA_PATH) is Dictionary else {}
	payload = {}; values = {}; _resources = {}; _bindings = {}; warning = ""
	if schema.is_empty():
		warning = "无法读取战斗数值默认表"; return
	for r in schema.resources: _resources[r.path] = r
	for key in schema.params:
		var param: Dictionary = schema.params[key]
		values[key] = param.default
		if param.has("resource"):
			if not _bindings.has(param.resource): _bindings[param.resource] = []
			_bindings[param.resource].append(key)
	var candidate: Variant = _read(config_path)
	warning = validate(candidate)
	if warning.is_empty(): payload = candidate
	else:
		warning = "战斗数值配置未应用，使用默认值：" + warning
		payload = {"version": schema.version, "contract": schema.contract, "tables": {}}
		for spec in schema.sheets: payload.tables[spec.name] = spec.rows
	for spec in schema.sheets:
		if spec.get("parameter_table", false):
			for row in payload.tables[spec.name]: values[row[0]] = row[3]

static func validate(candidate: Variant) -> String:
	if not candidate is Dictionary or candidate.get("version") != schema.get("version") or candidate.get("contract") != schema.get("contract"): return "版本或参数契约不匹配"
	if not candidate.get("tables") is Dictionary or candidate.tables.size() != schema.sheets.size(): return "配置表不完整"
	for spec in schema.sheets:
		if not candidate.tables.get(spec.name) is Array: return "缺少表 " + spec.name
		var expected := {}; var seen := {}
		for row in spec.rows: expected[_key(row, spec.key)] = row
		for row in candidate.tables[spec.name]:
			if not row is Array or row.size() != spec.columns.size(): return spec.name + " 列数错误"
			var key := _key(row, spec.key)
			if not expected.has(key) or seen.has(key): return spec.name + " 未知或重复ID " + key
			seen[key] = true
			for index in row.size():
				var col: Dictionary = spec.columns[index]
				var editable := bool(col.editable)
				if spec.has("editable_by_key"): editable = editable and spec.editable_by_key[key].any(func(i): return int(i) == index)
				var value: Variant = row[index]
				if not editable:
					if value != expected[key][index]: return spec.name + " 标识或说明列被修改 " + key
					continue
				if not (value is int or value is float) or not is_finite(float(value)): return spec.name + " 必须填写有限数值 " + key
				var low: float = float(col.min); var high: float = float(col.max)
				var integer := true
				if spec.get("parameter_table", false):
					var meta: Dictionary = schema.params[row[0]]
					low = float(meta.min); high = float(meta.max); integer = bool(meta.integer)
				elif spec.name == "机制参数":
					low = float(expected[key][5]); high = float(expected[key][6])
				if (integer and value != floor(value)) or value < low or value > high: return spec.name + " 数值类型或范围错误 " + key
		if seen.size() != expected.size(): return spec.name + " 缺少记录"
	return ""

static func _key(row: Array, cols: Array) -> String:
	var parts: Array[String] = []
	for index in cols:
		var v: Variant = row[int(index)]
		parts.append(str(int(v)) if v is float and v == floor(v) else str(v))
	return "/".join(parts)

static func i(id: String, fallback: int) -> int:
	if schema.is_empty(): load_configuration()
	return int(values.get("core/" + id, fallback))

static func f(id: String, fallback: float) -> float:
	if schema.is_empty(): load_configuration()
	return float(values.get("core/" + id, fallback))

static func enemy_payload() -> Dictionary:
	if schema.is_empty(): load_configuration()
	var result := {"version": schema.get("enemy_version", 2), "tables": {}}
	for name in ["怪物", "行动", "机制参数", "污染"]:
		if not payload.get("tables", {}).has(name): return {}
		result.tables[name] = payload.tables[name]
	return result

static func apply_resource(original: Resource) -> Resource:
	if schema.is_empty(): load_configuration()
	var path := original.resource_path
	if not _resources.has(path): return original
	var result: Resource = original.duplicate(true)
	var info: Dictionary = _resources[path]
	for id in _bindings.get(path, []):
		var meta: Dictionary = schema.params[id]
		var cursor: Variant = result
		for n in meta.property.size() - 1:
			var part: Variant = meta.property[n]
			cursor = cursor[int(part)] if part is float or part is int else cursor.get(str(part))
		var field: Variant = meta.property.back()
		var number: Variant = int(values[id]) if meta.integer else float(values[id])
		if cursor is Resource: cursor.set(str(field), number)
		else: cursor[int(field) if field is float or field is int else str(field)] = number
	# Starter entries carry CharacterData references too; bind those to the same tuned resource data.
	if result is StarterDeckData:
		# 条目可能已被前面的绑定改写（内联/引用两种来源），只处理两侧都存在的条目
		for n in mini(result.entries.size(), original.entries.size()):
			var src_entry = original.entries[n]
			if src_entry != null and src_entry.character != null:
				result.entries[n].character = apply_resource(src_entry.character)
	var pairs: Array = []; var changes: Array[String] = []
	for id in _bindings.get(path, []):
		var meta: Dictionary = schema.params[id]
		pairs.append([meta.default, values[id]])
		if values[id] != meta.default: changes.append(meta.label + "=" + str(values[id]))
	var handlers: Array = []
	for eff in info.get("effects", []): handlers.append(eff.handler)
	var status_keys := {"vulnerable": ["vulnerable_mult"], "strength": ["strength_per_stack"], "counter": ["counter_per_stack"], "regen": ["regen_per_stack"], "heart_corrosion": ["corrosion_per_stack"]}
	for meta in schema.core_params:
		if meta.handlers.any(func(h): return handlers.any(func(actual): return actual == h or actual.ends_with("_" + h))) or status_keys.get(info.id, []).has(meta.id):
			pairs.append([meta.default, values.get("core/" + meta.id, meta.default)])
			if values.get("core/" + meta.id, meta.default) != meta.default: changes.append(meta.label + "=" + str(values["core/" + meta.id]))
	if not changes.is_empty():
		var description := _rewrite(info.description, pairs) + "\n当前配置：" + "；".join(changes)
		result.set("description", description)
		if result is WordData: result.effect_summary = description
		result.set_meta("balance_changed", true)
	return result

static func _rewrite(text: String, pairs: Array) -> String:
	var replacements := {}
	for pair in pairs:
		if float(pair[0]) == 0: continue
		var key := str(float(pair[0]))
		if not replacements.has(key): replacements[key] = []
		if not replacements[key].has(float(pair[1])): replacements[key].append(float(pair[1]))
	var regex := RegEx.new(); regex.compile("(?<![0-9])[-+]?[0-9]+(?:\\.[0-9]+)?")
	var matches := regex.search_all(text)
	for index in range(matches.size() - 1, -1, -1):
		var found: RegExMatch = matches[index]
		var old := float(found.get_string()); var options: Array = replacements.get(str(old), [])
		if options.is_empty() or (options.size() == 1 and options[0] == old): continue
		var value: String = str(int(options[0])) if options.size() == 1 and options[0] == floor(options[0]) else (str(options[0]) if options.size() == 1 else "〔见当前配置〕")
		text = text.substr(0, found.get_start()) + value + text.substr(found.get_end())
	return text

static func relic_description(id: String, description: String) -> String:
	if schema.is_empty(): load_configuration()
	var pairs: Array = []; var changes: Array[String] = []
	for meta in schema.core_params:
		if meta.group != "遗物参数" or not str(meta.id).begins_with(id + "_"): continue
		var value: Variant = values.get("core/" + meta.id, meta.default)
		pairs.append([meta.default, value])
		if value != meta.default: changes.append(meta.label + "=" + str(value))
	return description if changes.is_empty() else _rewrite(description, pairs) + "\n当前配置：" + "；".join(changes)


static func fixed_text(text: String, handler: String, eff: EffectData = null) -> String:
	if schema.is_empty(): load_configuration()
	var pairs: Array = []
	for meta in schema.core_params:
		if meta.handlers.any(func(h): return handler == h or handler.ends_with("_" + h)):
			pairs.append([meta.default, values.get("core/" + meta.id, meta.default)])
	if eff != null and not eff.note.is_empty():
		for info in schema.resources:
			for original in info.get("effects", []):
				if original.handler != handler or original.note != eff.note: continue
				pairs.append([original.amount, eff.amount])
				for key in original.args:
					if original.args[key] is int or original.args[key] is float:
						pairs.append([original.args[key], eff.args.get(key, original.args[key])])
	return _rewrite(text, pairs)
