class_name WrestlerData
extends Resource

@export var id: String = "wrestler_id"
@export var display_name: String = "Wrestler"
@export var max_health: int = 10
@export var model_scene: PackedScene

@export_group("Sounds")
@export var sound_punch: AudioStream
@export var sound_name: AudioStream
@export var sound_hurt: AudioStream
@export var sound_defeat: AudioStream
