extends BoardView
## BoardView reads native touch globally, before the UI mask sees it.
## Keep the lesson's input restriction at the board boundary as well.
var allowed_cells: Array = []


func _on_tile_pressed(pos: Vector2i) -> void:
	if allowed_cells.has(pos): super._on_tile_pressed(pos)


func _extend_path(pos: Vector2i) -> void:
	if allowed_cells.has(pos): super._extend_path(pos)
