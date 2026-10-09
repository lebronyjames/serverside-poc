extends Control

signal on_join_game
signal on_start_game
 
@export var username: LineEdit
@export var session_id: LineEdit

@export var join_game: Button
@export var start_host: Button
@export var quit_game: Button


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	join_game.pressed.connect(join_game_func)
	start_host.pressed.connect(start_host_func)
	quit_game.pressed.connect(quit_game_func)
	NetworkManager.map_loaded.connect(close_menu, CONNECT_ONE_SHOT)

func join_game_func():
	NetworkManager.join_server(username.text, session_id.text)
	
func start_host_func():
	NetworkManager.start_server("res://Scenes/MainMap.tscn")

func quit_game_func():
	get_tree().quit()

func close_menu():
	hide()
