extends Control

# Assign these in the inspector after creating the scene
@export var host_button: Button
@export var join_button: Button
@export var ip_input: LineEdit
@export var status_label: Label

func _ready() -> void:
	if host_button: host_button.pressed.connect(_on_host_pressed)
	if join_button: join_button.pressed.connect(_on_join_pressed)
	
	# Connect to NetworkManager signals
	# Note: NetworkManager is an Autoload, so we can access it globally
	NetworkManager.connection_successful.connect(_on_connection_success)
	NetworkManager.connection_failed.connect(_on_connection_fail)
	NetworkManager.player_connected.connect(_on_player_connected)

func _on_host_pressed() -> void:
	if status_label: status_label.text = "Starting Server..."
	NetworkManager.host_game()
	_disable_buttons()

func _on_join_pressed() -> void:
	if status_label: status_label.text = "Connecting..."
	var ip = ""
	if ip_input: ip = ip_input.text
	NetworkManager.join_game(ip)
	_disable_buttons()

func _on_connection_success() -> void:
	if status_label: status_label.text = "Connected! Waiting for game..."

func _on_connection_fail() -> void:
	if status_label: status_label.text = "Connection Failed."
	_enable_buttons()

func _on_player_connected(id: int) -> void:
	if status_label: status_label.text = "Player " + str(id) + " connected."
	
	# TODO: Logic to start the game when 2 players are ready
	if multiplayer.is_server() and multiplayer.get_peers().size() >= 1:
		print("Enough players! Can start game logic here.")
		NetworkManager.start_game()

func _disable_buttons() -> void:
	if host_button: host_button.disabled = true
	if join_button: join_button.disabled = true

func _enable_buttons() -> void:
	if host_button: host_button.disabled = false
	if join_button: join_button.disabled = false