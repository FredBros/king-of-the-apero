class_name DeckManager
extends Node

var draw_pile: Array[CardData] = []
var discard_pile: Array[CardData] = []

func initialize_deck() -> void:
	draw_pile.clear()
	discard_pile.clear()
	_create_test_deck()
	shuffle_deck()

func shuffle_deck() -> void:
	draw_pile.shuffle()
	print("Deck shuffled. Count: ", draw_pile.size())

func draw_card() -> CardData:
	if draw_pile.is_empty():
		if discard_pile.is_empty():
			print("No cards left in deck or discard!")
			return null
		else:
			print("Reshuffling discard pile into deck...")
			draw_pile = discard_pile.duplicate()
			discard_pile.clear()
			shuffle_deck()
	
	return draw_pile.pop_back()

func discard_card(card: CardData) -> void:
	discard_pile.append(card)

func _create_test_deck() -> void:
	# Create a simple balanced deck for testing
	for i in range(10):
		draw_pile.append(_create_card(CardData.CardType.MOVE, 1, "Step"))
		draw_pile.append(_create_card(CardData.CardType.MOVE, 2, "Run"))
	
	for i in range(6):
		draw_pile.append(_create_card(CardData.CardType.ATTACK, 2, "Punch"))
		
	for i in range(4):
		draw_pile.append(_create_card(CardData.CardType.THROW, 2, "Suplex"))

func _create_card(type: CardData.CardType, value: int, title: String) -> CardData:
	var card = CardData.new()
	card.type = type
	card.value = value
	card.title = title
	return card