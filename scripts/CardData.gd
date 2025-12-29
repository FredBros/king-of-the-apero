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
@export var value: int = 1
@export var title: String = "Card"
@export var suit: String = ""
@export var rank_label: String = ""
@export var description: String = ""
@export var icon: Texture2D