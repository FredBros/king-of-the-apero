class_name PlayerInfo
extends Control

# References to UI elements (to be assigned in Inspector)
@export var name_label: Label
@export var health_label: Label

func setup(wrestler_name: String, max_hp: int) -> void:
	if name_label:
		name_label.text = wrestler_name
	update_health(max_hp, max_hp)

func update_health(current: int, _max: int) -> void:
	if health_label:
		health_label.text = str(current)