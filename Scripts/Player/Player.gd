extends CharacterBody3D

signal client_request_movement

const InputName = TimestampedInput.InputName
const ARCHETYPE = PrefabIdMap.Archetype.PLAYER

enum Mode { Server, Client, RemoteClient }

@export var SPEED: float = 5.0
@export var JUMP_VELOCITY = 4.5
@export var sensitivity: float = 0.002


@export var head: Node3D
@export var camera: Camera3D

var entity_id: int
var owner_peerid: int

var latest_input_dir: Vector2
var latest_velocity: Vector3

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass
	
func start_object():
	if multiplayer.get_unique_id() == owner_peerid:
		camera.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		
	if owner_peerid == null:
		owner_peerid = 1
		
	latest_input_dir = Vector2.ZERO
	latest_velocity = Vector3.ZERO

func process_physics(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	
	# deceleration is needed
	velocity.x = move_toward(velocity.x, latest_velocity.x, 5)
	velocity.z = move_toward(velocity.z, latest_velocity.z, 5)
		
	move_and_slide()

func handle_timestamped_input(input: TimestampedInput):
	if input.peer_id != owner_peerid and input.peer_id != 1: # reject input from packet that is not from server or owner
		return
	
	var input_name = input.input_name
	var vec2 = input.vec2
	
	if input_name == InputName.JUMP and is_on_floor():
		velocity.y += JUMP_VELOCITY
		
	if input_name == InputName.MOUSELOOK:
		rotate_y(-vec2.x * sensitivity)
		head.rotate_x(-vec2.y * sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-75), deg_to_rad(75))		

	if input_name == InputName.WALK:
		var input_dir = Vector3(vec2.x, 0, vec2.y)
		latest_velocity = (transform.basis * input_dir).normalized() * SPEED # if the player changes rotation, then walk dir needs to be relative to global basis of player
		
func pack_to_entitystate():
	var new_entitystate = EntityState.new(entity_id)
	new_entitystate.set_vec3(global_position)
	new_entitystate.set_vec3(global_rotation)
	new_entitystate.set_vec3(head.global_rotation)
	new_entitystate.set_vec3(velocity)
	
	return new_entitystate

func apply_entitystate(entity_state: EntityState):
	global_position = entity_state.vec3_values[0]
	global_rotation = entity_state.vec3_values[1]
	head.global_rotation = entity_state.vec3_values[2]
	velocity = entity_state.vec3_values[3]
	move_and_slide()
