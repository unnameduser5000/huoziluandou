extends Control
## All modal roots, including directly added and nested dialogs, cover the HUD.
## Keep this on the dialog itself so callers cannot omit the shared layer rule.
const MODAL_Z_INDEX := 100


func _enter_tree() -> void:
	z_index = maxi(z_index, MODAL_Z_INDEX)
