class_name EntityState
extends Resource

enum FieldType { VECTOR3, VECTOR2, BOOL, INT, FLOAT }

var entity_id: int
var field_types: Array[int] = []
var vec3_values: Array[Vector3] = []
var vec2_values: Array[Vector2] = []
var bool_values: Array[bool] = []
var int_values: Array[int] = []
var float_values: Array[float] = []


func _init(_entity_id: int) -> void:
	entity_id = _entity_id


func set_vec3(value: Vector3) -> void:
	field_types.append(FieldType.VECTOR3)
	vec3_values.append(value)


func set_vec2(value: Vector2) -> void:
	field_types.append(FieldType.VECTOR2)
	vec2_values.append(value)


func set_bool(value: bool) -> void:
	field_types.append(FieldType.BOOL)
	bool_values.append(value)


func set_int(value: int) -> void:
	field_types.append(FieldType.INT)
	int_values.append(value)


func set_float(value: float) -> void:
	field_types.append(FieldType.FLOAT)
	float_values.append(value)


func serialize() -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.put_32(entity_id)
	buffer.put_u32(field_types.size())

	var vec3_index := 0
	var vec2_index := 0
	var bool_index := 0
	var int_index := 0
	var float_index := 0

	for field_type in field_types:
		match field_type:
			FieldType.VECTOR3:
				if vec3_index >= vec3_values.size():
					push_error("EntityState %d is missing a Vector3 value." % entity_id)
					return PackedByteArray()
				var vec3_value := vec3_values[vec3_index]
				buffer.put_u8(FieldType.VECTOR3)
				buffer.put_float(vec3_value.x)
				buffer.put_float(vec3_value.y)
				buffer.put_float(vec3_value.z)
				vec3_index += 1
			FieldType.VECTOR2:
				if vec2_index >= vec2_values.size():
					push_error("EntityState %d is missing a Vector2 value." % entity_id)
					return PackedByteArray()
				var vec2_value := vec2_values[vec2_index]
				buffer.put_u8(FieldType.VECTOR2)
				buffer.put_float(vec2_value.x)
				buffer.put_float(vec2_value.y)
				vec2_index += 1
			FieldType.BOOL:
				if bool_index >= bool_values.size():
					push_error("EntityState %d is missing a bool value." % entity_id)
					return PackedByteArray()
				buffer.put_u8(FieldType.BOOL)
				buffer.put_u8(1 if bool_values[bool_index] else 0)
				bool_index += 1
			FieldType.INT:
				if int_index >= int_values.size():
					push_error("EntityState %d is missing an int value." % entity_id)
					return PackedByteArray()
				buffer.put_u8(FieldType.INT)
				buffer.put_32(int_values[int_index])
				int_index += 1
			FieldType.FLOAT:
				if float_index >= float_values.size():
					push_error("EntityState %d is missing a float value." % entity_id)
					return PackedByteArray()
				buffer.put_u8(FieldType.FLOAT)
				buffer.put_float(float_values[float_index])
				float_index += 1
			_:
				push_error("EntityState %d has unknown field type %d." % [entity_id, field_type])
				return PackedByteArray()

	if (
		vec3_index != vec3_values.size()
		or vec2_index != vec2_values.size()
		or bool_index != bool_values.size()
		or int_index != int_values.size()
		or float_index != float_values.size()
	):
		push_error("EntityState %d has values that are not listed in field_types." % entity_id)
		return PackedByteArray()
	
	return buffer.data_array


static func deserialize(data: PackedByteArray) -> EntityState:
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = data
	var state := deserialize_from_buffer(buffer)
	if state == null:
		return null
	if buffer.get_available_bytes() != 0:
		push_error("EntityState packet contains unexpected trailing data.")
		return null

	return state


static func deserialize_from_buffer(buffer: StreamPeerBuffer) -> EntityState:
	if buffer.get_available_bytes() < 8:
		push_error("EntityState packet is too short for its header.")
		return null

	var entity_id := buffer.get_32()
	var field_count := buffer.get_u32()
	if field_count > buffer.get_available_bytes():
		push_error("EntityState packet is too short for its field type tags.")
		return null

	var state := EntityState.new(entity_id)
	for _i in range(field_count):
		var field_type := buffer.get_u8()
		match field_type:
			FieldType.VECTOR3:
				if buffer.get_available_bytes() < 12:
					push_error("EntityState packet is too short for a Vector3 field.")
					return null
				state.field_types.append(FieldType.VECTOR3)
				state.vec3_values.append(Vector3(
					buffer.get_float(),
					buffer.get_float(),
					buffer.get_float()
				))
			FieldType.VECTOR2:
				if buffer.get_available_bytes() < 8:
					push_error("EntityState packet is too short for a Vector2 field.")
					return null
				state.field_types.append(FieldType.VECTOR2)
				state.vec2_values.append(Vector2(
					buffer.get_float(),
					buffer.get_float()
				))
			FieldType.BOOL:
				if buffer.get_available_bytes() < 1:
					push_error("EntityState packet is too short for a bool field.")
					return null
				var bool_value := buffer.get_u8()
				if bool_value > 1:
					push_error("EntityState packet contains an invalid bool value.")
					return null
				state.field_types.append(FieldType.BOOL)
				state.bool_values.append(bool_value == 1)
			FieldType.INT:
				if buffer.get_available_bytes() < 4:
					push_error("EntityState packet is too short for an int field.")
					return null
				state.field_types.append(FieldType.INT)
				state.int_values.append(buffer.get_32())
			FieldType.FLOAT:
				if buffer.get_available_bytes() < 4:
					push_error("EntityState packet is too short for a float field.")
					return null
				state.field_types.append(FieldType.FLOAT)
				state.float_values.append(buffer.get_float())
			_:
				push_error("EntityState packet contains unknown field type %d." % field_type)
				return null

	return state
