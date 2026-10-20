extends RefCounted
## Keep shared meshes alive without a resource -> its own script -> resource cycle.
const Geometry := preload("res://src/ui/object_stage/counter_geometry.gd")
const PATH := "res://assets/object_stage/counter_geometry.res"
static var _cache: Resource
static var _loading := false


static func warm(tree: SceneTree) -> void:
	if _cache != null or _loading: return
	_loading = ResourceLoader.load_threaded_request(PATH) == OK
	if not _loading: return
	while _loading and ResourceLoader.load_threaded_get_status(PATH) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await tree.process_frame
	if _loading: get_geometry()


static func get_geometry() -> Resource:
	if _cache == null:
		_cache = ResourceLoader.load_threaded_get(PATH) if _loading else load(PATH)
		_loading = false
	return _cache
