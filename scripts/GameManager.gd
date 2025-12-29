class_name GameManager
extends Node

signal turn_started(player_name: String)
signal card_drawn(card: CardData)
signal card_discarded(card: CardData)
signal turn_ended

@export var hand_size_limit: int = 5
@export var cards_drawn_per_turn: int = 2

var deck_manager: DeckManager

var players: Array[Wrestler] = []
# Dictionary to store hand for each player: { player_name: [CardData] }
var player_hands: Dictionary = {}
var active_player_index: int = 0
var is_game_active: bool = false

func initialize(wrestlers_list: Array[Wrestler], deck_mgr: DeckManager) -> void:
	players = wrestlers_list
	deck_manager = deck_mgr
	active_player_index = 0 # Player 1 starts
	is_game_active = true
	deck_manager.initialize_deck()
	
	# Initial setup: Fill hands to limit for all players
	for player in players:
		_draw_up_to_limit(player.name)
		
	_start_turn()

func _start_turn() -> void:
	var current_player = players[active_player_index]
	print("Turn Start: ", current_player.name)
	turn_started.emit(current_player.name)
	_draw_turn_cards(current_player.name)

func end_turn() -> void:
	if not is_game_active: return
	
	print("Turn End")
	turn_ended.emit()
	
	# Switch player
	active_player_index = (active_player_index + 1) % players.size()
	_start_turn()

# Returns true if an action was successfully consumed
func try_use_action() -> bool:
	return is_game_active

func get_active_wrestler() -> Wrestler:
	if players.is_empty(): return null
	if active_player_index >= players.size(): return null
	return players[active_player_index]

func use_card(card: CardData) -> bool:
	if try_use_action():
		var current_player_name = players[active_player_index].name
		_remove_card_from_hand(current_player_name, card)
		deck_manager.discard_card(card)
		card_discarded.emit(card)
		return true
	return false

func discard_hand_card(card: CardData) -> void:
	if not is_game_active: return
	var current_player_name = players[active_player_index].name
	_remove_card_from_hand(current_player_name, card)
	deck_manager.discard_card(card)
	card_discarded.emit(card)

func get_player_hand(player_name: String) -> Array:
	return player_hands.get(player_name, [])

# Used for initialization (fill hand to 5)
func _draw_up_to_limit(player_name: String) -> void:
	if not player_hands.has(player_name):
		player_hands[player_name] = []
	
	var current_hand = player_hands[player_name]
	while current_hand.size() < hand_size_limit:
		var new_card = deck_manager.draw_card()
		if new_card:
			current_hand.append(new_card)
			card_drawn.emit(new_card)
		else:
			break # Deck empty

# Used for turn start (draw max 2, up to limit)
func _draw_turn_cards(player_name: String) -> void:
	if not player_hands.has(player_name):
		player_hands[player_name] = []
		
	var current_hand = player_hands[player_name]
	var space_in_hand = hand_size_limit - current_hand.size()
	var amount_to_draw = min(cards_drawn_per_turn, space_in_hand)
	
	for i in range(amount_to_draw):
		var new_card = deck_manager.draw_card()
		if new_card:
			current_hand.append(new_card)
			card_drawn.emit(new_card)
		else:
			break

func _remove_card_from_hand(player_name: String, card: CardData) -> void:
	if player_hands.has(player_name):
		player_hands[player_name].erase(card)