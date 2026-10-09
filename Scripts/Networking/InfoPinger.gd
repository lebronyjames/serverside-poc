extends Node

var tcp := TCPServer.new()
var clients: Array[StreamPeerTCP] = []
var game_info := {}  # update whenever the map/player count changes

func start(port: int, _game_info: Dictionary) -> void:
	var err := tcp.listen(port)
	if err != OK:
		push_error("Info server failed to listen: %s" % error_string(err))
	game_info = _game_info

func _process(_delta: float) -> void:
	game_info["current_tick"] = ServerLoop.current_tick
	
	if !tcp.is_listening():
		return
	while tcp.is_connection_available():
		print("InfoServer: connection accepted")
		clients.append(tcp.take_connection())

	for c in clients.duplicate():
		c.poll()
		if c.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			clients.erase(c)
			continue
		if c.get_available_bytes() > 0:
			c.get_data(c.get_available_bytes())   # discard the request, we don't care what it says
			var body := JSON.stringify(game_info).to_utf8_buffer()
			var header := "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % body.size()
			c.put_data(header.to_utf8_buffer())
			c.put_data(body)
			c.disconnect_from_host()
			clients.erase(c)
