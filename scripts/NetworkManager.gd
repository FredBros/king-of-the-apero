extends Node

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_successful
signal connection_failed
signal server_disconnected
signal match_hosted(match_id: String)

const PORT = 8910
const DEFAULT_SERVER_IP = "127.0.0.1" # Localhost
const GAME_SCENE_PATH = "res://scenes/Arena.tscn" # TODO: Verify this is the correct path to your game scene!
const LOBBY_SCENE_PATH = "res://scenes/Lobby.tscn" # TODO: Verify the path to your Lobby/Main scene

var current_match_id: String = ""
var match_presences: Dictionary = {} # userID -> presence data

func _ready() -> void:
	# TODO: Connect to Nakama Socket events (MatchData, MatchPresence)
	# Listen to NakamaManager to know when a match is found
	if NakamaManager:
		NakamaManager.match_created.connect(_on_match_created)
		# Note: For joining, we call join_nakama_match directly from Lobby with the ID

func host_game() -> void:
	# Host creates the match on Nakama
	NakamaManager.create_match()

func join_game(match_id: String) -> void:
	# Placeholder for manual join logic
	print("⏳ Joining match manually: ", match_id)
	# TODO: Implement socket.join_match_async(match_id) here

func _on_match_created(match_id: String) -> void:
	current_match_id = match_id
	# We emit a signal so Lobby can display the ID to share
	print("📢 Match ID to share: ", match_id)
	match_hosted.emit(match_id)
	
	# Host joins their own match logic (manual)
	join_game(match_id)

func start_game() -> void:
	# In P2P, anyone (usually the Host) can trigger the start.
	# We use RPC to tell everyone (including self) to load the scene.
	load_game_scene.rpc(GAME_SCENE_PATH)

@rpc("any_peer", "call_local", "reliable")
func load_game_scene(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

func return_to_lobby() -> void:
	# Close the connection cleanly
	# TODO: Leave match via socket
	get_tree().change_scene_to_file(LOBBY_SCENE_PATH)

@rpc("any_peer", "call_local", "reliable")
func request_rematch() -> void:
	if multiplayer.is_server():
		print("Rematch requested. Reloading game scene...")
		load_game_scene.rpc(GAME_SCENE_PATH)
	else:
		# Client requests rematch to server
		request_rematch.rpc_id(1)