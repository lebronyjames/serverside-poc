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

var next_target_state: EntityState
var last_confirmed_tick: int

var entity_id: int
var owner_peerid: int

var latest_input_dir: Vector2
var latest_velocity: Vector3
var grounded: bool # synced floor state, is_on_floor() is not reliable right after a snapshot teleport

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# floor snapping depends on CharacterBody3D's internal on_floor from the previous move_and_slide,
	# which isn't networked and is stale after a snapshot rewind. Without it, floor detection only
	# depends on position and velocity, so client replays match the server.
	floor_snap_length = 0.0
	
func _unhandled_input(event: InputEvent) -> void: # capture mouse inputs
	if multiplayer.get_unique_id() != owner_peerid:
		return
	
	if event is InputEventMouseMotion:
		var vec2_input = event.relative
		var mouse_input = TimestampedInput.new(InputName.MOUSELOOK, owner_peerid, entity_id, ClientLoop.current_tick)
		mouse_input.vec2 = vec2_input
		ClientLoop.add_input_to_tick(mouse_input)
	
func capture_keyboard_inputs(delta: float, current_tick: int):
	if multiplayer.get_unique_id() != owner_peerid:
		return
		
	if Input.is_action_just_pressed("jump"):
		var jump_input = TimestampedInput.new(InputName.JUMP, owner_peerid, entity_id, current_tick)
		ClientLoop.add_input_to_tick(jump_input)

	var input_dir := Input.get_vector("left", "right", "forward", "backward")
	var movement_input = TimestampedInput.new(InputName.WALK, owner_peerid, entity_id, current_tick)
	movement_input.vec2 = input_dir
	ClientLoop.add_input_to_tick(movement_input)
	
func start_object():
	if multiplayer.get_unique_id() == owner_peerid:
		camera.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		
	if owner_peerid == null:
		owner_peerid = 1
		
	latest_input_dir = Vector2.ZERO
	latest_velocity = Vector3.ZERO

func process_physics(delta: float) -> void:
	# always apply gravity so move_and_slide finds the floor by contact every tick (velocity.y is zeroed on landing)
	velocity += get_gravity() * delta

	# deceleration is needed
	velocity.x = move_toward(velocity.x, latest_velocity.x, 5)
	velocity.z = move_toward(velocity.z, latest_velocity.z, 5)

	move_and_slide()
	grounded = is_on_floor()

func process_interpolation(delta: float) -> void:
	if next_target_state == null:
		return
		
	if ClientLoop.current_tick - last_confirmed_tick > ServerLoop.SERVER_UPDATE_PER_PACKETS:
		apply_entitystate(next_target_state)
	
	var lerp_weight = 1.0 / ServerLoop.SERVER_UPDATE_PER_PACKETS
	
	var target_position = next_target_state.vec3_values[0]
	var target_rotation = next_target_state.vec3_values[1]
	var target_head_rotation = next_target_state.vec3_values[2]
	
	global_position = global_position.lerp(target_position, lerp_weight)
	global_rotation = global_rotation.lerp(target_rotation, lerp_weight)
	head.global_rotation = head.global_rotation.lerp(target_head_rotation, lerp_weight)
	
func handle_timestamped_input(input: TimestampedInput):
	if input.peer_id != owner_peerid and input.peer_id != 1: # reject input from packet that is not from server or owner
		return
	
	var input_name = input.input_name
	var vec2 = input.vec2
	
	if input_name == InputName.JUMP and grounded:
		velocity.y = JUMP_VELOCITY
		
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
	new_entitystate.set_vec3(latest_velocity)
	new_entitystate.set_bool(grounded)

	return new_entitystate

func apply_entitystate(entity_state: EntityState): # Apply to snap entity into state
	global_position = entity_state.vec3_values[0]
	global_rotation = entity_state.vec3_values[1]
	head.global_rotation = entity_state.vec3_values[2]
	velocity = entity_state.vec3_values[3]
	latest_velocity = entity_state.vec3_values[4]
	grounded = entity_state.bool_values[0]

func cache_entitystate(entity_state: EntityState, confirmed_tick: int): # cache entity state
	next_target_state = entity_state
	last_confirmed_tick = confirmed_tick
