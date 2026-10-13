class_name EntitySpawnRequest
extends Resource

var entity_id: int
var target_prefab_id: int
var owner_peer_id: int
var entity_state: EntityState


func _init(
	_entity_id: int,
	_target_prefab_id: int,
	_owner_peer_id: int,
	_entity_state: EntityState
) -> void:
	entity_id = _entity_id
	target_prefab_id = _target_prefab_id
	owner_peer_id = _owner_peer_id
	entity_state = _entity_state


func serialize() -> PackedByteArray:
	if entity_state == null:
		push_error("EntitySpawnRequest has a null entity state.")
		return PackedByteArray()

	var entity_state_data := entity_state.serialize()
	if entity_state_data.is_empty():
		push_error("Failed to serialize EntitySpawnRequest entity state.")
		return PackedByteArray()

	var buffer := StreamPeerBuffer.new()
	buffer.put_32(entity_id)
	buffer.put_32(target_prefab_id)
	buffer.put_32(owner_peer_id)
	buffer.put_data(entity_state_data)
	return buffer.data_array


static func deserialize(data: PackedByteArray) -> EntitySpawnRequest:
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = data
	var request := deserialize_from_buffer(buffer)
	if request == null:
		return null
	if buffer.get_available_bytes() != 0:
		push_error("EntitySpawnRequest packet contains unexpected trailing data.")
		return null

	return request


static func deserialize_from_buffer(buffer: StreamPeerBuffer) -> EntitySpawnRequest:
	if buffer.get_available_bytes() < 12:
		push_error("EntitySpawnRequest is too short for its header.")
		return null

	var entity_id := buffer.get_32()
	var target_prefab_id := buffer.get_32()
	var owner_peer_id := buffer.get_32()
	var entity_state := EntityState.deserialize_from_buffer(buffer)
	if entity_state == null:
		return null

	return EntitySpawnRequest.new(
		entity_id,
		target_prefab_id,
		owner_peer_id,
		entity_state
	)
