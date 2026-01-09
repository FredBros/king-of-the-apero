extends Node3D

@onready var grid_manager: GridManager = $GridManager
@onready var game_ui: GameUI = $GameUI
@onready var game_manager: GameManager = $GameManager
@onready var deck_manager: DeckManager = $DeckManager

func _ready() -> void:
	# Connect the UI signal to the GridManager
	if game_ui and grid_manager:
		game_ui.card_selected.connect(grid_manager.on_card_selected)
		grid_manager.game_over.connect(func(winner_name):
			game_ui.show_game_over(winner_name)
			game_manager.is_game_active = false
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
		
		# Connect Card Drawing/Discarding to UI
		game_manager.card_drawn.connect(game_ui.add_card_to_hand)
		game_manager.card_discarded.connect(game_ui.remove_card_from_hand)
		game_manager.card_discarded.connect(grid_manager.on_card_discarded)
		
		# Connect Game Manager to Grid Manager (to sync active wrestler)
		game_manager.turn_started.connect(func(player_name):
			grid_manager.set_active_wrestler(game_manager.get_active_wrestler())
			
			# Refresh Hand UI for the new player
			game_ui.clear_hand()
			var hand = game_manager.get_player_hand(player_name)
			for card in hand:
				game_ui.add_card_to_hand(card)
		)
		
		# Start the game logic (GridManager has already spawned wrestlers in its _ready)
		game_manager.initialize(grid_manager.wrestlers, deck_manager)
		
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