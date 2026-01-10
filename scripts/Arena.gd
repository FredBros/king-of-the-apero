extends Node3D

@onready var grid_manager: GridManager = $GridManager
@onready var game_ui: GameUI = $GameUI
@onready var game_manager: GameManager = $GameManager
@onready var deck_manager: DeckManager = $DeckManager

# Track loaded players to prevent race conditions
var _players_loaded: int = 0

func _ready() -> void:
	# Connect the UI signal to the GridManager
	if game_ui and grid_manager:
		game_ui.card_selected.connect(grid_manager.on_card_selected)
		grid_manager.game_over.connect(func(winner_name):
			game_ui.show_game_over(winner_name)
			game_manager.is_game_active = false
		)
		
	# Handle Disconnections (Win by forfeit)
	NetworkManager.player_disconnected.connect(func(id):
		if game_manager.is_game_active:
			print("Opponent disconnected! You win.")
			# In a 1v1, if the other disconnects, the remaining player wins.
			game_ui.show_game_over("Opponent Disconnected")
			game_manager.is_game_active = false
		
		# If opponent leaves (during game or after), restart is impossible
		game_ui.disable_restart_button()
	)
	
	NetworkManager.server_disconnected.connect(func():
		game_ui.disable_restart_button()
	)
		
	# Setup Game Manager
	if game_manager:
		# Inject dependency into GridManager
		grid_manager.game_manager = game_manager
		
		# Connect UI End Turn button
		game_ui.end_turn_pressed.connect(game_manager.end_turn)
		game_ui.card_discard_requested.connect(game_manager.discard_hand_card)
		
		# Connect Game Manager signals to UI
		game_manager.turn_started.connect(func(player_name):
			game_ui.update_turn_info(player_name)
			_update_ui_player_positions()
		)
		
		# Connect Card Discarding to GridManager (to clear highlights)
		game_manager.card_discarded.connect(grid_manager.on_card_discarded)
		
		# Connect Game Manager to Grid Manager (to sync active wrestler)
		game_manager.turn_started.connect(func(player_name):
			grid_manager.set_active_wrestler(game_manager.get_active_wrestler())
			
			# Determine whose hand to show
			var hand_owner = ""
			
			# Check for Hotseat (Server with no clients)
			if multiplayer.is_server() and multiplayer.get_peers().size() == 0:
				hand_owner = player_name # Show active player
			else:
				# Networked: Find local player name
				var my_id = multiplayer.get_unique_id()
				for name in game_manager.player_peer_ids:
					if game_manager.player_peer_ids[name] == my_id:
						hand_owner = name
						break
			
			# Refresh Hand UI
			game_ui.clear_hand()
			if hand_owner != "":
				var hand = game_manager.get_player_hand(hand_owner)
				for card in hand:
					game_ui.add_card_to_hand(card)
		)
		
		# Handshake: Wait for all players to load the scene before initializing
		if multiplayer.is_server():
			_players_loaded += 1 # Server is loaded
			_check_start_game()
		else:
			game_manager.initialize(grid_manager.wrestlers, deck_manager)
			notify_server_scene_loaded.rpc_id(1)
		
		# Connect Health Signals
		for w in grid_manager.wrestlers:
			# We bind the wrestler instance so UI knows WHO changed health
			w.health_changed.connect(game_ui.on_wrestler_health_changed.bind(w))

func _update_ui_player_positions() -> void:
	var active = game_manager.get_active_wrestler()
	var opponent = null
	
	# Find the opponent (Simple 1v1 logic)
	for w in grid_manager.wrestlers:
		if w != active:
			opponent = w
			break
			
	game_ui.update_player_info(active, opponent)

@rpc("any_peer", "call_remote", "reliable")
func notify_server_scene_loaded() -> void:
	if multiplayer.is_server():
		_players_loaded += 1
		_check_start_game()

func _check_start_game() -> void:
	var expected = multiplayer.get_peers().size() + 1
	if _players_loaded >= expected:
		print("All players loaded. Starting game logic.")
		game_manager.initialize(grid_manager.wrestlers, deck_manager)