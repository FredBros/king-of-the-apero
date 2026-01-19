extends Control

# Assign these in the inspector after creating the scene
@export var host_button: Button
@export var join_button: Button
@export var ip_input: LineEdit
@export var status_label: Label
var start_game_timer: Timer

# Port par défaut (doit correspondre à celui dans NetworkManager)
const DEFAULT_PORT = 7000
const DEFAULT_IP = "127.0.0.1"

func _ready() -> void:
	if host_button: host_button.pressed.connect(_on_host_pressed)
	if join_button: join_button.pressed.connect(_on_join_pressed)
	
	# UI Setup for Host/Join
	if host_button: host_button.text = "CREATE MATCH"
	if join_button: join_button.text = "JOIN MATCH"
	
	# Désactiver le bouton tant que Nakama n'est pas prêt
	if NakamaManager.socket == null:
		if join_button: join_button.disabled = true
		if status_label: status_label.text = "Connecting to Online Services..."
		NakamaManager.nakama_ready.connect(_on_nakama_ready)
	
	# Placeholder for Match ID
	if ip_input:
		ip_input.placeholder_text = "Enter Match ID here..."
	
	# Connect to NetworkManager signals
	# Note: NetworkManager is an Autoload, so we can access it globally
	NetworkManager.connection_successful.connect(_on_connection_success)
	NetworkManager.connection_failed.connect(_on_connection_fail)
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.match_hosted.connect(_on_match_hosted)
	
	# Timer to check for game start conditions periodically
	start_game_timer = Timer.new()
	start_game_timer.wait_time = 1.0
	start_game_timer.timeout.connect(_check_start_game)
	add_child(start_game_timer)

func _on_host_pressed() -> void:
	if status_label: status_label.text = "Creating Match..."
	NetworkManager.host_game()
	_disable_buttons()

func _on_join_pressed() -> void:
	var match_id = ip_input.text.strip_edges()
	if match_id.is_empty():
		if status_label: status_label.text = "Please enter a Match ID."
		return
		
	if status_label: status_label.text = "Joining Match..."
	
	# On rejoint directement l'ID
	NetworkManager.join_game(match_id)
	_disable_buttons()

func _on_nakama_ready() -> void:
	if join_button: join_button.disabled = false
	if status_label: status_label.text = "Online Services Ready."

func _on_connection_success() -> void:
	if status_label: status_label.text = "Connected! Waiting for game..."
	# Check immediately if we already have peers (e.g. late join or bridge already synced)
	start_game_timer.start() # Start polling
	_check_start_game()

func _on_match_hosted(match_id: String) -> void:
	# Le Host reçoit l'ID réel ici. On l'affiche pour qu'il puisse le partager.
	if status_label: status_label.text = "Match Created! Share the Code below."
	if ip_input:
		ip_input.text = match_id
		ip_input.editable = false # On verrouille pour montrer que c'est un output

func _on_connection_fail() -> void:
	if status_label: status_label.text = "Connection Failed."
	_enable_buttons()
	start_game_timer.stop()

func _on_player_connected(id: int) -> void:
	if status_label: status_label.text = "Player " + str(id) + " connected."
	_check_start_game()

func _check_start_game() -> void:
	# Logic to start the game when 2 players are ready (Self + 1 Opponent)
	var peers = multiplayer.get_peers()
	print("DEBUG: Checking start game. Peers count: ", peers.size())
	if peers.size() >= 1:
		print("Enough players! Can start game logic here.")
		start_game_timer.stop()
		NetworkManager.start_game()

func _disable_buttons() -> void:
	if host_button: host_button.disabled = true
	if join_button: join_button.disabled = true

func _enable_buttons() -> void:
	if host_button: host_button.disabled = false
	if join_button: join_button.disabled = false