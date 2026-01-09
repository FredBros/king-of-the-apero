class_name GameUI
extends CanvasLayer

signal card_selected(card_data: CardData)
signal card_discard_requested(card_data: CardData)
signal end_turn_pressed

@export var top_player_info: PlayerInfo
@export var bottom_player_info: PlayerInfo

var active_wrestler_ref: Wrestler
var opponent_wrestler_ref: Wrestler

@export var card_ui_scene: PackedScene
@onready var hand_container: HBoxContainer = $HandContainer
@onready var game_over_container: CenterContainer = $GameOverContainer
@onready var winner_label: Label = $GameOverContainer/Panel/MarginContainer/VBoxContainer/WinnerLabel

@onready var turn_label: Label = $TurnInfoContainer/VBoxContainer/TurnLabel

var selected_card_ui: CardUI

func _ready() -> void:
	# Connect restart button manually since we added it via code/tscn edit
	var restart_btn = $GameOverContainer/Panel/MarginContainer/VBoxContainer/RestartButton
	restart_btn.pressed.connect(_on_restart_button_pressed)
	
	# Connect end turn button manually
	var end_turn_btn = $EndTurnButton
	end_turn_btn.pressed.connect(_on_end_turn_button_pressed)

func _on_end_turn_button_pressed() -> void:
	end_turn_pressed.emit()

func _on_restart_button_pressed() -> void:
	# Reload the current scene to restart
	get_tree().reload_current_scene()

func update_turn_info(player_name: String) -> void:
	turn_label.text = player_name + "'s Turn"

func add_card_to_hand(card_data: CardData) -> void:
	var card = card_ui_scene.instantiate()
	hand_container.add_child(card)
	card.setup(card_data)
	card.clicked.connect(_on_card_clicked)
	card.discard_requested.connect(_on_card_discard_requested)

func remove_card_from_hand(card_data: CardData) -> void:
	for child in hand_container.get_children():
		if child is CardUI and child.card_data == card_data:
			child.queue_free()
			if selected_card_ui == child:
				selected_card_ui = null
			break

func clear_hand() -> void:
	for child in hand_container.get_children():
		child.queue_free()
	selected_card_ui = null

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

func _on_card_discard_requested(card_ui: CardUI) -> void:
	card_discard_requested.emit(card_ui.card_data)

func show_game_over(winner_name: String) -> void:
	winner_label.text = winner_name + " WINS!"
	game_over_container.show()


# Met à jour les infos des joueurs (Hotseat : Actif en bas, Adversaire en haut)
func update_player_info(active: Wrestler, opponent: Wrestler) -> void:
	active_wrestler_ref = active
	opponent_wrestler_ref = opponent
	
	if bottom_player_info and active:
		bottom_player_info.setup(active.name, active.max_health)
		bottom_player_info.update_health(active.current_health, active.max_health)
	
	if top_player_info and opponent:
		top_player_info.setup(opponent.name, opponent.max_health)
		top_player_info.update_health(opponent.current_health, opponent.max_health)

# Callback appelé quand un catcheur change de PV
func on_wrestler_health_changed(current: int, max_hp: int, wrestler: Wrestler) -> void:
	if wrestler == active_wrestler_ref and bottom_player_info:
		bottom_player_info.update_health(current, max_hp)
	elif wrestler == opponent_wrestler_ref and top_player_info:
		top_player_info.update_health(current, max_hp)