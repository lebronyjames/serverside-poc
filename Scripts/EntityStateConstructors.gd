extends Node

static func player_state(entity_id: int, position: Vector3, rotation: Vector3, head_rotation: Vector3, velocity: Vector3):
	var new_entitystate = EntityState.new(entity_id)
	new_entitystate.set_vec3(position)
	new_entitystate.set_vec3(rotation)
	new_entitystate.set_vec3(head_rotation)
	new_entitystate.set_vec3(velocity)
	new_entitystate.set_vec3(Vector3.ZERO) # latest_velocity
	new_entitystate.set_bool(false) # grounded

	return new_entitystate
