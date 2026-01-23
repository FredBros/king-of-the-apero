class_name DropZone
extends Control

signal card_dropped(card_data: CardData, position: Vector2)

func _init() -> void:
	# Make sure this control covers the area but lets clicks pass through
	# so we can still click on the grid for normal actions
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	# We only accept CardData (and specifically Attack cards for Push)
	return data is CardData and (data.type == CardData.CardType.ATTACK or data.suit == "Joker")

func _drop_data(at_position: Vector2, data: Variant) -> void:
	card_dropped.emit(data, at_position)
