extends Node

const Archetype = PrefabIdMap.Archetype

var started: bool = false
var current_tick: int

var clientids: Array[int]
var entityid_to_controllable_map := {} # tracking possession of controllable object by entity id
var entity_states: EntityStateList
var input_log: InputLog

var entity_spawn_requests: Array[EntitySpawnRequest]
var entity_despawn_requests: Array[EntityDespawnRequest]

func start() -> void:
	current_tick = 0
	started = true
	
	clientids = []
	entity_states = EntityStateList.new(current_tick)
	input_log = InputLog.new()
	entity_spawn_requests = []
	entity_despawn_requests = []
	multiplayer.peer_packet.connect(on_client_to_server_packet)

# --------------------------------- Server loop --------------------------------------------

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	if started == false:
		return
		
	if current_tick % 6 == 0:
		perform_input_actions_locally()
		input_log.set_last_confirmed_tick(current_tick+1)
		serialize_and_export_entity_states()
	current_tick += 1

func perform_input_actions_locally():
	var latest_cycle_tick = input_log.last_confirmed_tick
	for i in range(latest_cycle_tick, current_tick+1):
		var current_tick_inputs = input_log.get_inputs_for_tick(i)
		for input in current_tick_inputs:
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
	for client_peerid in clientids:
		send_reliable_packet_to_client(client_peerid, server_state_buffer_packet)
	
# -------------------------- Callbacks -----------------------------------------------------------
	
func on_client_to_server_packet(sender_id: int, packet: PackedByteArray) -> void: # helper wired in to receive packets
	if packet.size() < 1:
		push_warning("Empty packet from peer %d" % sender_id)
		return
		
	var buf := StreamPeerBuffer.new()
	buf.data_array = packet
	var packet_type: PacketType.PacketType = buf.get_u8()
	if packet_type == PacketType.PacketType.INPUT_BATCH:
		var decoded_input_packet := InputLog.decode_tick(buf.data_array.slice(1))
		decoded_input_packet["peer_id"] = sender_id
		var packet_tick = decoded_input_packet.tick
		for input in decoded_input_packet.inputs:
			input_log.add_input_to_tick(packet_tick, input)
	elif packet_type == PacketType.PacketType.CLIENT_INIT:
		on_client_connect(sender_id)
	
func on_client_connect(sender_id: int):
	clientids.append(sender_id)
	for entityid in entityid_to_controllable_map: # spawn entities already present
		var archetype = entityid_to_controllable_map[entityid].ARCHETYPE
		var owner_peerid = entityid_to_controllable_map[entityid].owner_peerid
		var entity_state = entityid_to_controllable_map[entityid].pack_to_entitystate()
		var entity_spawn_request = EntitySpawnRequest.new(entityid, archetype, owner_peerid, entity_state)
		send_spawn_entity_request(sender_id, entity_spawn_request)
	
	var spawn_state = EntityStateConstructors.player_state(sender_id, Vector3(0, 3, 0), Vector3(0, 0, 0), Vector3(0, 0, 0), Vector3(0, 0, 0))
	spawn_entity(sender_id, sender_id, Archetype.PLAYER, spawn_state)
	
# ------------------------- Externally called logical helpers ---------------------------------

func spawn_entity(entity_id: int, owner_peerid: int, archetype: Archetype, starting_entitystate: EntityState = null):
	var entity = PrefabIdMap.instantiate(archetype)
	get_tree().root.add_child(entity)
	if (starting_entitystate != null):
		entity.apply_entitystate(starting_entitystate)
	var entity_state = entity.pack_to_entitystate()
	var entity_spawn_request = EntitySpawnRequest.new(entity_id, Archetype.PLAYER, owner_peerid, entity_state)
	entityid_to_controllable_map[entity_id] = entity
	for client_peerid in clientids:
		send_spawn_entity_request(client_peerid, entity_spawn_request)

func send_spawn_entity_request(client_peerid: int, request: EntitySpawnRequest):
	var serialized_bytes = request.serialize()
	
	var spawn_buffer := StreamPeerBuffer.new()
	spawn_buffer.put_u8(PacketType.PacketType.SPAWN_ENTITY)
	spawn_buffer.put_data(serialized_bytes)
	send_reliable_packet_to_client(client_peerid, spawn_buffer)
	
func send_despawn_entity_requests(client_peerid: int, request: EntityDespawnRequest):
	var serialized_bytes = request.serialize()
	
	var despawn_buffer := StreamPeerBuffer.new()
	despawn_buffer.put_u8(PacketType.PacketType.DESPAWN_ENTTIY)
	despawn_buffer.put_data(serialized_bytes)
	send_reliable_packet_to_client(client_peerid, despawn_buffer)

func send_unreliable_packet_to_client(client_peerid: int, buffer: StreamPeerBuffer):
	var sm := multiplayer as SceneMultiplayer
	sm.send_bytes(buffer.data_array, client_peerid, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, 1)  # to client peers, channel 1
	
func send_reliable_packet_to_client(client_peerid: int, buffer: StreamPeerBuffer):
	var sm := multiplayer as SceneMultiplayer
	sm.send_bytes(buffer.data_array, client_peerid, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 1)  # to client peers, channel 1
