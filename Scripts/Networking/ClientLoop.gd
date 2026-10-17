extends Node

const INPUT_BUFFER_TICKS = 3 # extra lead over rtt to absorb jitter

var spawnable_prefabs: Dictionary[int, PackedScene] = {}
var lockstep_timing: float

var peer_id: int

var started: bool = false
var current_tick: int
var current_rtt: int

var entityid_to_controllable_map := {} # tracking possession of controllable object by entity id
var owned_entities = []
var entity_states: EntityStateList
var input_log: InputLog


func start(_peer_id: int, _current_tick: int = 0) -> void:
	peer_id = _peer_id
	current_tick = _current_tick
	entity_states = EntityStateList.new(current_tick)
	input_log = InputLog.new()
	current_rtt = 0
	started = true
	lockstep_timing = 1.0 / Engine.physics_ticks_per_second
	multiplayer.peer_packet.connect(on_server_to_client_packet)
	send_client_init()

# --------------------------------- Client loop --------------------------------------------

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	if started == false:
		return

	apply_server_state()
	capture_keyboard_inputs(lockstep_timing)
	push_events_to_server()
	process_events_locally(lockstep_timing)
	process_physics_locally(lockstep_timing)
	interpolate_state(lockstep_timing)
	current_tick += 1

func apply_server_state():
	if entity_states.number_of_entities == 0:
		return

	update_rtt()
	var rtt_ticks = ceil(float(current_rtt) * Engine.physics_ticks_per_second / 1000.0)
	# inputs for current_tick must reach the server before it simulates that tick, so stay at least rtt + buffer ahead
	current_tick = max(entity_states.current_tick + rtt_ticks + INPUT_BUFFER_TICKS, current_tick) # we fast forward this if the client is very behind
	for entity_state in entity_states.entities:
		var entity_id = entity_state.entity_id
		if entity_id not in entityid_to_controllable_map:
			continue
			
		if entity_id in owned_entities: # Only to owned entities
			entityid_to_controllable_map[entity_id].apply_entitystate(entity_state)
		else:
			entityid_to_controllable_map[entity_id].cache_entitystate(entity_state, current_tick)
	
	input_log.set_last_confirmed_tick(entity_states.current_tick+1)
	
	# now apply local events later the confirmed window to keep self-owned entities relatively smooth
	# current_tick itself is excluded: it gets captured and simulated after this in _physics_process
	for tick in range(entity_states.current_tick+1, current_tick):
		var inputs = input_log.get_inputs_for_tick(tick)
		for input in inputs:
			var target_entity_id = input.entity_id
			entityid_to_controllable_map[target_entity_id].handle_timestamped_input(input)
			
		for entityid in entityid_to_controllable_map: # Process physics only for owned entities
			if entityid in owned_entities:
				entityid_to_controllable_map[entityid].process_physics(lockstep_timing)
			
	entity_states.clear()

func update_rtt():
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return
	var server_peer := enet.get_peer(1)
	if server_peer == null:
		return
	current_rtt = int(server_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))

func capture_keyboard_inputs(delta: float):
	for entityid in owned_entities:
		entityid_to_controllable_map[entityid].capture_keyboard_inputs(delta, current_tick)

func push_events_to_server():
	var current_tick_event_packet := StreamPeerBuffer.new()
	current_tick_event_packet.put_u8(PacketType.PacketType.INPUT_BATCH)
	var current_tick_inputs = input_log.get_inputs_for_tick(current_tick)
	if len(current_tick_inputs) == 0:
		return
	var encoded_tick_events = InputLog.encode_tick(current_tick, peer_id, current_tick_inputs)
	current_tick_event_packet.put_data(encoded_tick_events)
	send_reliable_packet_to_server(current_tick_event_packet)

func process_events_locally(delta):
	var current_tick_inputs = input_log.get_inputs_for_tick(current_tick)
	for input in current_tick_inputs:
		var target_entity_id = input.entity_id
		if entityid_to_controllable_map[target_entity_id] != null:
			entityid_to_controllable_map[target_entity_id].handle_timestamped_input(input)
		
func process_physics_locally(delta):
	for entityid in owned_entities:
		entityid_to_controllable_map[entityid].process_physics(delta)

func interpolate_state(delta):
	for entityid in entityid_to_controllable_map:
		var entity = entityid_to_controllable_map[entityid]
		if entity.owner_peerid != multiplayer.get_unique_id():
			entity.process_interpolation(delta)

# --------------------------- callbacks ----------------------------------------

func send_client_init():
	var packet := StreamPeerBuffer.new()
	packet.put_u8(PacketType.PacketType.CLIENT_INIT)
	send_reliable_packet_to_server(packet)

func add_input_to_tick(input: TimestampedInput):
	input_log.add_input_to_tick(input.tick, input)

func on_server_to_client_packet(sender_id: int, packet: PackedByteArray) -> void: # helper wired in to receive packet
	if sender_id != 1:
		return
	
	if packet.size() < 1:
		push_warning("Empty packet from peer %d" % sender_id)
		return
	
	var buf := StreamPeerBuffer.new()
	buf.data_array = packet
	var packet_type: PacketType.PacketType = buf.get_u8()
	match packet_type:
		PacketType.PacketType.SERVER_SNAPSHOT:
			accept_server_snapshot(buf)
		PacketType.PacketType.SPAWN_ENTITY:
			accept_entity_spawn_requests(buf)
		PacketType.PacketType.DESPAWN_ENTTIY:
			accept_enemy_despawn_requests(buf)

func accept_server_snapshot(buf: StreamPeerBuffer) -> void:
	var entity_state_list = EntityStateList.deserialize(buf.data_array.slice(buf.get_position()))
	if entity_state_list == null:
		return
	if entity_state_list.current_tick > entity_states.current_tick:
		entity_states = entity_state_list

func accept_entity_spawn_requests(buf: StreamPeerBuffer) -> void:
	if buf.get_available_bytes() < 1:
		push_error("Spawn entity packet is missing its request count.")
		return

	var request := EntitySpawnRequest.deserialize_from_buffer(buf)
	if request == null:
		return

	if buf.get_available_bytes() != 0:
		push_error("Spawn entity packet contains unexpected trailing data.")
		return

	if entityid_to_controllable_map.has(request.entity_id):
		return

	var new_entity = PrefabIdMap.instantiate(request.target_prefab_id)
	if new_entity == null:
		push_error("Failed to instantiate prefab %d for entity %d." % [request.target_prefab_id, request.entity_id])
		return
	new_entity.name = str(request.entity_id)
	new_entity.entity_id = request.entity_id
	new_entity.owner_peerid = request.owner_peerid
	get_tree().root.add_child(new_entity)
	new_entity.apply_entitystate(request.entity_state)
	new_entity.start_object()
	
	entityid_to_controllable_map[request.entity_id] = new_entity
	if request.owner_peerid == multiplayer.get_unique_id():
		owned_entities.append(request.entity_id)

func accept_enemy_despawn_requests(buf: StreamPeerBuffer) -> void:
	if buf.get_available_bytes() < 1:
		push_error("Despawn entity packet is missing its request count.")
		return

	var request_count := buf.get_u8()
	if buf.get_available_bytes() != request_count * 4:
		push_error("Despawn entity packet has an invalid payload size.")
		return

	var entity_ids: Array[int] = []
	for _i in range(request_count):
		var request := EntityDespawnRequest.deserialize(buf.data_array.slice(buf.get_position(), buf.get_position() + 4))
		if request == null:
			return
		entity_ids.append(request.entity_id)
		buf.seek(buf.get_position() + 4)

	for entity_id in entity_ids:
		if not entityid_to_controllable_map.has(entity_id):
			continue
		var entity = entityid_to_controllable_map[entity_id]
		entityid_to_controllable_map.erase(entity_id)
		owned_entities.erase(entity_id)
		if is_instance_valid(entity):
			entity.queue_free()

# ------------------------------ Network helpers -----------------------------------------------

func send_unreliable_packet_to_server(buffer: StreamPeerBuffer):
	var sm := multiplayer as SceneMultiplayer
	sm.send_bytes(buffer.data_array, 1, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, 1)  # to client peers, channel 1
	
func send_reliable_packet_to_server(buffer: StreamPeerBuffer):
	var sm := multiplayer as SceneMultiplayer
	sm.send_bytes(buffer.data_array, 1, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 1)  # to client peers, channel 1
	
