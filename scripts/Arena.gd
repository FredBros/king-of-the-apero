extends Node3D

@onready var grid_manager: GridManager = $GridManager
@onready var game_ui: GameUI = $GameUI

func _ready() -> void:
	# Connect the UI signal to the GridManager
	if game_ui and grid_manager:
		game_ui.card_selected.connect(grid_manager.on_card_selected)
		grid_manager.game_over.connect(game_ui.show_game_over)