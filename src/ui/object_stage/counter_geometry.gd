extends Resource
## Offline-built meshes shared by each counter; contains no run or stock state.
@export var shop: PackedScene
@export var relics: Dictionary[String, PackedScene] = {}
@export var tokens: Array[PackedScene] = []
@export var service: PackedScene
