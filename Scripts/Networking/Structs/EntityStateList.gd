class_name EntityStateList
extends Resource

var current_tick: int
var number_of_entities: int
var entities: Array[EntityState] = []


func _init(_current_tick: int = 0) -> void:
	current_tick = _current_tick
	number_of_entities = 0


func add_entity(entity_state: EntityState) -> void:
	entities.append(entity_state)
	number_of_entities = entities.size()


func serialize() -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	number_of_entities = entities.size()
	buffer.put_u32(current_tick)
	buffer.put_u32(number_of_entities)

	for entity_state in entities:
		if entity_state == null:
			push_error("EntityStateList contains a null entity state.")
			return PackedByteArray()
		var entity_data := entity_state.serialize()
		if entity_data.is_empty():
			push_error("Failed to serialize EntityState %d." % entity_state.entity_id)
			return PackedByteArray()
		buffer.put_data(entity_data)

	return buffer.data_array

func clear() -> void:
	number_of_entities = 0
	entities.clear()

static func deserialize(data: PackedByteArray) -> EntityStateList:
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = data
	if buffer.get_available_bytes() < 8:
		push_error("EntityStateList packet is too short for its header.")
		return null

	var tick := buffer.get_u32()
	var entity_count := buffer.get_u32()
	if entity_count > buffer.get_available_bytes() / 8:
		push_error("EntityStateList packet is too short for its entities.")
		return null

	var state_list := EntityStateList.new(tick)
	for _i in range(entity_count):
		var entity_state := EntityState.deserialize_from_buffer(buffer)
		if entity_state == null:
			return null
		state_list.entities.append(entity_state)

	if buffer.get_available_bytes() != 0:
		push_error("EntityStateList packet contains unexpected trailing data.")
		return null

	state_list.number_of_entities = state_list.entities.size()
	return state_list
