extends Node

signal map_loaded

var enet_peer: MultiplayerPeer

var PORT = 9999
var PINGER_PORT = 9998
var IP_ADDRESS = '127.0.0.1'

var server_properties := {}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

func start_server(map_path: String):
	enet_peer = ENetMultiplayerPeer.new()
	enet_peer.create_server(PORT)
	multiplayer.multiplayer_peer = enet_peer
	InfoPinger.start(PINGER_PORT, { "map_path": map_path })
	load_map(map_path)
	ServerLoop.start()

func join_server(username, session_id):
	multiplayer.connected_to_server.connect(client_callback.bind())
	enet_peer = ENetMultiplayerPeer.new()
	enet_peer.create_client(IP_ADDRESS, PORT)
	multiplayer.multiplayer_peer = enet_peer

func client_callback():
	var rtt_start = Time.get_ticks_msec()
	var server_metadata = await ping_server_info(IP_ADDRESS, PINGER_PORT)
	var rtt_end = Time.get_ticks_msec()
	var rtt = rtt_end - rtt_start
	var rtt_ticks = ceil(float(rtt) * Engine.physics_ticks_per_second / 1000.0)
	if server_metadata == {}:
		return
	var map_path = server_metadata["map_path"]
	var current_tick = server_metadata["current_tick"] 
	load_map(map_path)
	ClientLoop.start(multiplayer.get_unique_id(), current_tick + rtt_ticks * 2)

# ------------------------------ Helpers -------------------------------------------

func ping_server_info(address: String, port: int) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 5.0
	add_child(http)
	if http.request("http://%s:%d/" % [address, port]) != OK:
		http.queue_free()
		return {}
	var res = await http.request_completed   # [result, code, headers, body]
	http.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		return {}
	var data = JSON.parse_string(res[3].get_string_from_utf8())
	return data if data is Dictionary else {}

func load_map(map_path: String) -> void:
	var current_map_scene = load(map_path)
	var current_map = current_map_scene.instantiate()
	add_child(current_map)
	map_loaded.emit()
