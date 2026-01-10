extends Node

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_successful
signal connection_failed
signal server_disconnected

const PORT = 8910
const DEFAULT_SERVER_IP = "127.0.0.1" # Localhost
const GAME_SCENE_PATH = "res://scenes/Arena.tscn" # TODO: Vérifie que c'est le bon chemin vers ta scène de jeu !
const LOBBY_SCENE_PATH = "res://scenes/Lobby.tscn" # TODO: Vérifie le chemin de ta scène Lobby/Main

var multiplayer_peer: WebSocketMultiplayerPeer

func _ready() -> void:
	# Connect signals from the high-level multiplayer API
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host_game() -> void:
	multiplayer_peer = WebSocketMultiplayerPeer.new()
	var error = multiplayer_peer.create_server(PORT)
	if error != OK:
		printerr("Failed to create server: ", error)
		return
		
	multiplayer.multiplayer_peer = multiplayer_peer
	print("Server started on port ", PORT)
	
	# Host is always ID 1. We emit it manually because peer_connected isn't emitted for self.
	player_connected.emit(1)

func join_game(address: String = "") -> void:
	multiplayer_peer = WebSocketMultiplayerPeer.new()
	if address.is_empty():
		address = DEFAULT_SERVER_IP
		
	# WebSocket URL format: ws://IP:PORT
	var url = "ws://" + address + ":" + str(PORT)
	var error = multiplayer_peer.create_client(url)
	if error != OK:
		printerr("Failed to create client: ", error)
		return
		
	multiplayer.multiplayer_peer = multiplayer_peer
	print("Connecting to server at ", url, "...")

func _on_peer_connected(id: int) -> void:
	print("Peer connected: ", id)
	player_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: ", id)
	player_disconnected.emit(id)

func _on_connected_to_server() -> void:
	print("Successfully connected to server!")
	connection_successful.emit()

func _on_connection_failed() -> void:
	printerr("Connection failed!")
	connection_failed.emit()

func _on_server_disconnected() -> void:
	print("Server disconnected!")
	server_disconnected.emit()
	multiplayer.multiplayer_peer = null

func start_game() -> void:
	# Seul le serveur peut lancer la partie
	if multiplayer.is_server():
		load_game_scene.rpc(GAME_SCENE_PATH)

@rpc("authority", "call_local", "reliable")
func load_game_scene(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

func return_to_lobby() -> void:
	# On ferme la connexion proprement
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	get_tree().change_scene_to_file(LOBBY_SCENE_PATH)

@rpc("any_peer", "call_local", "reliable")
func request_rematch() -> void:
	if multiplayer.is_server():
		print("Rematch requested. Reloading game scene...")
		load_game_scene.rpc(GAME_SCENE_PATH)
	else:
		# Client requests rematch to server
		request_rematch.rpc_id(1)