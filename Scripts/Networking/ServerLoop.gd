extends Node

var started: bool = false
var current_tick: int

func start() -> void:
	current_tick = 0
	started = true

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	if started == false:
		return
	current_tick += 1
