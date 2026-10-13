class_name EntityDespawnRequest
extends Resource

var entity_id: int


func _init(_entity_id: int) -> void:
	entity_id = _entity_id


func serialize() -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.put_32(entity_id)
	return buffer.data_array


static func deserialize(data: PackedByteArray) -> EntityDespawnRequest:
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = data
	if buffer.get_available_bytes() != 4:
		push_error("EntityDespawnRequest packet must contain exactly one entity ID.")
		return null
	return EntityDespawnRequest.new(buffer.get_32())
