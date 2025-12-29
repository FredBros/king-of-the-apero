class_name GameUI
extends CanvasLayer

signal card_selected(card_data: CardData)

@export var card_ui_scene: PackedScene
@onready var hand_container: HBoxContainer = $HandContainer
@onready var game_over_container: CenterContainer = $GameOverContainer
@onready var winner_label: Label = $GameOverContainer/Panel/MarginContainer/VBoxContainer/WinnerLabel

var selected_card_ui: CardUI

func _ready() -> void:
	# Create 3 dummy cards for testing immediately
	_create_dummy_hand()

func _on_restart_button_pressed() -> void:
	# Reload the current scene to restart
	get_tree().reload_current_scene()

func _create_dummy_hand() -> void:
	var dummy_data = [
		_create_card_data(CardData.CardType.MOVE, 1, "Step"),
		_create_card_data(CardData.CardType.ATTACK, 3, "Punch"),
		_create_card_data(CardData.CardType.THROW, 2, "Suplex")
	]
	
	for data in dummy_data:
		var card = card_ui_scene.instantiate()
		hand_container.add_child(card)
		card.setup(data)
		card.clicked.connect(_on_card_clicked)
		
	# Connect restart button manually since we added it via code/tscn edit
	var restart_btn = $GameOverContainer/Panel/MarginContainer/VBoxContainer/RestartButton
	restart_btn.pressed.connect(_on_restart_button_pressed)

func _create_card_data(type: CardData.CardType, value: int, title: String) -> CardData:
	var card = CardData.new()
	card.type = type
	card.value = value
	card.title = title
	return card

func _on_card_clicked(card_ui: CardUI) -> void:
	if selected_card_ui and selected_card_ui != card_ui:
		selected_card_ui.set_selected(false)
	
	selected_card_ui = card_ui
	selected_card_ui.set_selected(true)
	card_selected.emit(card_ui.card_data)

func show_game_over(winner_name: String) -> void:
	winner_label.text = winner_name + " WINS!"
	game_over_container.show()