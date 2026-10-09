extends Node

var started: bool = false
var current_tick: int

func start(_current_tick: int = 0) -> void:
	current_tick = _current_tick
	started = true

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	if started == false:
		return
	current_tick += 1
