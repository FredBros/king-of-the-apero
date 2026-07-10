class_name CardData
extends Resource

enum CardType {
	MOVE,
	ATTACK,
	THROW
}

enum MovePattern {
	ORTHOGONAL, # Pique / Coeur
	DIAGONAL, # Trefle / Carreau
	OMNI # Joker
}

@export var type: CardType
@export var pattern: MovePattern = MovePattern.ORTHOGONAL
@export var tier: int = 1
@export var title: String = "Card"
@export var suit: String = ""
@export var symbol: String = ""
@export var rank_label: String = ""
@export var description: String = ""
@export var icon: Texture2D

# Static helpers for Network Serialization
static func serialize(card: CardData) -> Dictionary:
	if not card: return {}
	return {
		"type": int(card.type),
		"tier": card.tier,
		"title": card.title,
		"suit": card.suit,
		"pattern": int(card.pattern)
	}

static func deserialize(data: Dictionary) -> CardData:
	if data.is_empty(): return null
	var card = CardData.new()
	card.type = int(data.type)
	card.tier = int(data.tier)
	card.title = data.title
	card.suit = data.suit
	card.pattern = int(data.pattern)
	return card