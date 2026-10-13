extends Node

var started: bool = false
var current_tick: int

var clientids: Array[int]
var entityid_to_controllable_map := {} # tracking possession of controllable object by entity id
var entity_states: EntityStateList
var input_log: InputLog

func start() -> void:
	current_tick = 0
	started = true
	
	clientids = []
	entity_states = EntityStateList.new(current_tick)
	input_log = InputLog.new()
	multiplayer.peer_packet.connect(on_client_to_server_packet)

# --------------------------------- Server loop --------------------------------------------

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	if started == false:
		return
		
	send_spawn_entity_requests()
	send_despawn_entity_requests()
	if current_tick % 6 == 0:
		perform_input_actions_locally()
		input_log.set_last_confirmed_tick(current_tick+1)
		serialize_and_export_entity_states()
	current_tick += 1

func send_spawn_entity_requests():
	pass
	
func send_despawn_entity_requests():
	pass

func perform_input_actions_locally():
	var latest_cycle_tick = input_log.last_confirmed_tick
	for i in range(latest_cycle_tick, current_tick+1):
		var current_tick_inputs = input_log.get_inputs_for_tick(i)
		for input in current_tick_inputs:
			var input_name = input.input_name
			entityid_to_controllable_map[input.peer_id].handle_timestamped_input(input)
			
		for entity_id in entityid_to_controllable_map:
			entityid_to_controllable_map[entity_id].process_physics(1.0 / Engine.physics_ticks_per_second)
	
func serialize_and_export_entity_states():
	var entity_state_list = EntityStateList.new(current_tick)
	for entityid in entityid_to_controllable_map:
		var entity_state = entityid_to_controllable_map[entityid].pack_to_entitystate()
		entity_state_list.add_entity(entity_state)
	var server_state_buffer_packet := StreamPeerBuffer.new()
	server_state_buffer_packet.put_u8(PacketType.PacketType.SERVER_SNAPSHOT)
	var serialized_entity_state_pba = entity_state_list.serialize()
	server_state_buffer_packet.put_data(serialized_entity_state_pba)
	var sm := multiplayer as SceneMultiplayer
	for client_peerid in clientids:
		sm.send_bytes(server_state_buffer_packet.data_array, client_peerid, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, 1)  # to client peers, channel 1
	
# -------------------------- Callbacks -----------------------------------------------------------
	
func on_client_to_server_packet(sender_id: int, packet: PackedByteArray) -> void: # helper wired in to receive packets
	if packet.size() < 1:
		push_warning("Empty packet from peer %d" % sender_id)
		return
		
	var buf := StreamPeerBuffer.new()
	buf.data_array = packet
	var packet_type: PacketType.PacketType = buf.get_u8()
	if packet_type != PacketType.PacketType.INPUT_BATCH:
		return
	
	var decoded_input_packet := InputLog.decode_tick(buf.data_array.slice(1))
	decoded_input_packet["peer_id"] = sender_id
	var packet_tick = decoded_input_packet.tick
	for input in decoded_input_packet.inputs:
		input_log.add_input_to_tick(packet_tick, input)
	
