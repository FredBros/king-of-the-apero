class_name DeckManager
extends Node

var draw_pile: Array[CardData] = []
var discard_pile: Array[CardData] = []

func initialize_deck() -> void:
	draw_pile.clear()
	discard_pile.clear()
	_create_standard_deck()
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

func _create_standard_deck() -> void:
	var suits = ["Spades", "Clubs", "Hearts", "Diamonds"]
	
	for suit in suits:
		for rank in range(1, 14):
			var card = CardData.new()
			card.value = rank
			card.suit = suit
			
			match suit:
				"Spades": card.symbol = "X" # Diagonal (ASCII)
				"Clubs": card.symbol = "+" # Orthogonal (ASCII)
				"Hearts": card.symbol = "X" # Diagonal (ASCII)
				"Diamonds": card.symbol = "+" # Orthogonal (ASCII)
			
			# Set Rank Label
			if rank == 1: card.rank_label = "A"
			elif rank == 11: card.rank_label = "J"
			elif rank == 12: card.rank_label = "Q"
			elif rank == 13: card.rank_label = "K"
			else: card.rank_label = str(rank)
			
			card.title = card.symbol + " " + card.rank_label
			
			match suit:
				"Spades": # Pique (Noir) -> Move Diagonal
					card.type = CardData.CardType.MOVE
					card.pattern = CardData.MovePattern.DIAGONAL
				"Clubs": # Trefle (Noir) -> Move Orthogonal
					card.type = CardData.CardType.MOVE
					card.pattern = CardData.MovePattern.ORTHOGONAL
				"Hearts": # Coeur (Rouge) -> Attack Diagonal
					card.type = CardData.CardType.ATTACK
					card.pattern = CardData.MovePattern.DIAGONAL
				"Diamonds": # Carreau (Rouge) -> Attack Orthogonal
					card.type = CardData.CardType.ATTACK
					card.pattern = CardData.MovePattern.ORTHOGONAL
			
			draw_pile.append(card)
			
	# Add 2 Jokers
	for i in range(2):
		var card = CardData.new()
		card.type = CardData.CardType.MOVE
		card.pattern = CardData.MovePattern.OMNI
		card.value = 1
		card.title = "JOKER"
		card.suit = "Joker"
		card.symbol = "*"
		draw_pile.append(card)

func _create_card(type: CardData.CardType, value: int, title: String) -> CardData:
	var card = CardData.new()
	card.type = type
	card.value = value
	card.title = title
	return card