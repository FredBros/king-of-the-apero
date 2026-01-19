extends Node

signal player_connected(user_id: String)
signal player_disconnected(user_id: String)
signal connection_successful
signal connection_failed
signal server_disconnected
signal match_hosted(match_id: String)
signal game_message_received(data: Dictionary)

const PORT = 8910
const DEFAULT_SERVER_IP = "127.0.0.1" # Localhost
const GAME_SCENE_PATH = "res://scenes/Arena.tscn" # TODO: Verify this is the correct path to your game scene!
const LOBBY_SCENE_PATH = "res://scenes/Lobby.tscn" # TODO: Verify the path to your Lobby/Main scene

# Op Codes for Nakama Match State
enum OpCode {
	GAME_ACTION = 1
}

var current_match_id: String = ""
var match_presences: Dictionary = {} # userID -> presence data
var self_user_id: String = ""

func _ready() -> void:
	# Listen to NakamaManager to know when a match is found
	if NakamaManager:
		NakamaManager.match_created.connect(_on_match_created)
		NakamaManager.nakama_ready.connect(_on_nakama_ready)
		
		if NakamaManager.socket:
			_connect_socket_signals()

func _on_nakama_ready() -> void:
	_connect_socket_signals()

func _connect_socket_signals() -> void:
	var socket = NakamaManager.get_socket()
	if not socket.received_match_presence.is_connected(_on_match_presence):
		socket.received_match_presence.connect(_on_match_presence)
	if not socket.received_match_state.is_connected(_on_match_state):
		socket.received_match_state.connect(_on_match_state)
	
	# Ensure self_user_id is set as soon as possible to filter out self-presence events
	if NakamaManager.session:
		self_user_id = NakamaManager.session.user_id

func host_game() -> void:
	# Host creates the match on Nakama
	NakamaManager.create_match()

func join_game(match_id: String) -> void:
	print("⏳ Joining match manually: ", match_id)
	
	# We use the manual join from NakamaManager to avoid the "Dot vs Token" bug in the SDK
	var result = await NakamaManager.join_match_manually(match_id)
	
	if result.is_empty():
		connection_failed.emit()
		return
	
	current_match_id = match_id
	self_user_id = result.self.user_id
	
	print("✅ Match Joined! ID: ", current_match_id)
	print("👤 Self ID: ", self_user_id)
	
	# Initialize presences
	match_presences.clear()
	for presence in result.presences:
		if presence.user_id == self_user_id: continue
		match_presences[presence.user_id] = presence
		player_connected.emit(presence.user_id)
		
	connection_successful.emit()

func _on_match_created(match_id: String) -> void:
	current_match_id = match_id
	# We emit a signal so Lobby can display the ID to share
	print("📢 Match ID to share: ", match_id)
	match_hosted.emit(match_id)
	
	# Host joins their own match logic (manual)
	join_game(match_id)

func _on_match_presence(p_event: NakamaRTAPI.MatchPresenceEvent) -> void:
	if p_event.match_id != current_match_id:
		return
		
	# Safety check: Ensure self_user_id is set
	if self_user_id.is_empty() and NakamaManager.session:
		self_user_id = NakamaManager.session.user_id
		
	for presence in p_event.joins:
		if presence.user_id == self_user_id: continue
		print("👋 Player Joined: ", presence.username)
		match_presences[presence.user_id] = presence
		player_connected.emit(presence.user_id)
		
	for presence in p_event.leaves:
		print("👋 Player Left: ", presence.username)
		match_presences.erase(presence.user_id)
		player_disconnected.emit(presence.user_id)

func _on_match_state(p_state: NakamaRTAPI.MatchData) -> void:
	if p_state.match_id != current_match_id:
		return
		
	# Filter out own messages to prevent reflection/double execution
	if p_state.presence and p_state.presence.user_id == self_user_id:
		return
		
	var json_str = p_state.data
	var json = JSON.new()
	var error = json.parse(json_str)
	if error == OK:
		var data = json.data
		# Inject sender ID into data for logic verification
		if p_state.presence:
			data["_sender_id"] = p_state.presence.user_id
		_handle_network_message(data)
	else:
		printerr("❌ Failed to parse match state JSON")

func send_message(data: Dictionary) -> void:
	if current_match_id.is_empty(): return
	var socket = NakamaManager.get_socket()
	var json_str = JSON.stringify(data)
	# OpCode 1 for all game actions
	socket.send_match_state_async(current_match_id, OpCode.GAME_ACTION, json_str)

func _handle_network_message(data: Dictionary) -> void:
	if not data.has("type"): return
	
	match data.type:
		"START_GAME":
			print("🎮 Received START_GAME command.")
			get_tree().change_scene_to_file(GAME_SCENE_PATH)
		_:
			game_message_received.emit(data)

func start_game() -> void:
	# Send Start Game message to everyone
	var msg = {"type": "START_GAME"}
	send_message(msg)
	# Also start locally
	get_tree().change_scene_to_file(GAME_SCENE_PATH)

func return_to_lobby() -> void:
	if not current_match_id.is_empty():
		var socket = NakamaManager.get_socket()
		if socket:
			socket.leave_match_async(current_match_id)
	current_match_id = ""
	match_presences.clear()
	get_tree().change_scene_to_file(LOBBY_SCENE_PATH)