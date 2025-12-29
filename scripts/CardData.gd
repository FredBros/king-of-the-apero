class_name CardData
extends Resource

enum CardType {
	MOVE,
	ATTACK,
	THROW
}

@export var type: CardType
@export var value: int = 1
@export var title: String = "Card"
@export var description: String = ""
@export var icon: Texture2D