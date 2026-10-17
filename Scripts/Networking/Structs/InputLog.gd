class_name InputLog
extends Resource

const InputName = TimestampedInput.InputName

var input_list: Dictionary
# The first tick not yet confirmed; lower ticks have already been simulated.
var last_confirmed_tick: int

func _init():
	input_list = {}
	last_confirmed_tick = 0


func set_last_confirmed_tick(server_tick: int):
	if server_tick <= last_confirmed_tick:
		return

	for tick in range(last_confirmed_tick, server_tick):
		input_list.erase(tick)

	last_confirmed_tick = server_tick


func add_input_to_tick(current_tick: int, input: TimestampedInput):
	# Don't buffer inputs the server has already confirmed.
	if current_tick < last_confirmed_tick:
		print("Stale input rejected: Tick " + str(current_tick) + " versus " + str(last_confirmed_tick))
		return


	if not input_list.has(current_tick):
		input_list[current_tick] = []

	input_list[current_tick].append(input)


func get_inputs_for_tick(tick: int) -> Array:
	if not input_list.has(tick):
		return []

	return input_list[tick]
	
static func encode_tick(tick: int, peer_id: int, inputs: Array) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u32(tick)
	buf.put_u32(peer_id)
	buf.put_u8(inputs.size())

	for input: TimestampedInput in inputs:
		buf.put_u8(input.input_name)   # enum as u8
		buf.put_u32(input.entity_id)
		buf.put_float(input.vec2.x)
		buf.put_float(input.vec2.y)
		buf.put_float(input.vec3.x)
		buf.put_float(input.vec3.y)
		buf.put_float(input.vec3.z)
		buf.put_u8(1 if input.bool_ else 0)
		buf.put_float(input.float_)

	return buf.data_array


static func decode_tick(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	var tick := buf.get_u32()
	var peer_id := buf.get_u32()
	var count := buf.get_u8()

	var inputs: Array[TimestampedInput] = []
	for i in count:
		var input_name: InputName = buf.get_u8()
		var entity_id: int = buf.get_u32()
		var input := TimestampedInput.new(input_name, peer_id, entity_id, tick)
		input.vec2 = Vector2(buf.get_float(), buf.get_float())
		input.vec3 = Vector3(buf.get_float(), buf.get_float(), buf.get_float())
		input.bool_ = buf.get_u8() == 1
		input.float_ = buf.get_float()
		inputs.append(input)

	return { "tick": tick, "peer_id": peer_id, "inputs": inputs }
