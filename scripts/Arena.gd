extends Node3D

@onready var grid_manager: GridManager = $GridManager
@onready var game_ui: GameUI = $GameUI
@onready var game_manager: GameManager = $GameManager
@onready var deck_manager: DeckManager = $DeckManager

func _ready() -> void:
	# Connect the UI signal to the GridManager
	if game_ui and grid_manager:
		game_ui.card_selected.connect(grid_manager.on_card_selected)
		game_ui.card_dropped_on_world.connect(grid_manager.on_card_dropped_on_world)
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
		game_manager.grid_manager = grid_manager
		
		# Connect UI End Turn button
		game_ui.end_turn_pressed.connect(game_manager.end_turn)
		
		# Connect Game Manager signals to UI
		game_manager.turn_started.connect(func(player_name):
			game_ui.update_turn_info(player_name)
			_update_ui_player_positions()
		)
		
		# Connect Card Discarding to GridManager (to clear highlights)
		game_manager.card_discarded.connect(grid_manager.on_card_discarded)
		
		# Connect Reaction UI
		game_manager.reaction_phase_started.connect(game_ui.start_reaction_request)
		game_ui.reaction_selected.connect(game_manager.on_reaction_selected)
		game_ui.reaction_skipped.connect(game_manager.on_reaction_skipped)
		
		# Connect Game Manager to Grid Manager (to sync active wrestler)
		game_manager.turn_started.connect(func(player_name):
			grid_manager.set_active_wrestler(game_manager.get_active_wrestler())
			
			# Determine whose hand to show
			var hand_owner = ""
			
			# Networked: Find local player name using Nakama ID
			var my_id = NetworkManager.self_user_id
			for name in game_manager.player_peer_ids:
				if game_manager.player_peer_ids[name] == my_id:
					hand_owner = name
					break
			
			# Refresh Hand UI for the active player
			# The initial hand is drawn by GameManager and signaled via card_drawn
			# This is mostly for subsequent turns to ensure UI is in sync.
			game_ui.clear_hand()
			if hand_owner != "":
				var hand = game_manager.get_player_hand(hand_owner)
				for card in hand:
					game_ui.add_card_to_hand(card)
		)
		
		# Initialize Game Manager network part. Game state init will be triggered by character selection.
		game_manager.initialize_network(deck_manager)
		
		# Connect Health Signals
		# This is now done after spawning, to ensure wrestlers exist.
		grid_manager.wrestlers_spawned.connect(_on_wrestlers_spawned)

	# Adjust camera for Portrait Mode (Zoom In)
	var camera = get_viewport().get_camera_3d()
	if camera and camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		camera.fov = 50.0

func _on_wrestlers_spawned(wrestlers: Array[Wrestler]) -> void:
	# Connect Health Signals now that wrestlers exist
	for w in wrestlers:
		# We bind the wrestler instance so UI knows WHO changed health
		w.health_changed.connect(game_ui.on_wrestler_health_changed.bind(w))
		
		# Network Sync: When health changes locally, notify others
		w.health_changed.connect(func(current, _max):
			if not game_manager.is_network_syncing:
				game_manager.send_health_update(w.name, current)
		)

func _update_ui_player_positions() -> void:
	var active = game_manager.get_active_wrestler()
	var opponent = null
	
	# Find the opponent (Simple 1v1 logic)
	for w in grid_manager.wrestlers:
		if w != active:
			opponent = w
			break
			
	game_ui.update_player_info(active, opponent)