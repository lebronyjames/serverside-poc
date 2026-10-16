class_name PrefabIdMap

enum Archetype { PLAYER }

const SCENES: Dictionary[Archetype, PackedScene] = {
	Archetype.PLAYER: preload("res://Prefabs/Player.tscn")
}

static func instantiate(archetype: int) -> Node:
	var scene: PackedScene = SCENES.get(archetype)
	if scene == null:
		push_error("Unknown archetype %d" % archetype)  # also covers untrusted wire data
		return null
	return scene.instantiate()
