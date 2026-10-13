class_name TimestampedInput
extends Resource

enum InputName { WALK, JUMP, MOUSELOOK }

var input_name: InputName
var peer_id: int
var entity_id: int
var tick: int

var vec2: Vector2
var vec3: Vector3
var bool_: bool
var float_: float

func _init(_input_name: InputName, _peer_id: int, _entity_id: int, _tick: int):
	input_name = _input_name
	peer_id = _peer_id
	entity_id = _entity_id
	tick = _tick

	vec2 = Vector2.ZERO
	vec3 = Vector3.ZERO
	bool_ = false
	float_ = 0.0

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
