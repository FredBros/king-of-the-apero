class_name WrestlerData
extends Resource

@export var id: String = "wrestler_id"
@export var display_name: String = "Wrestler"
@export var max_health: int = 10
@export var combo_token: int = 4
@export var allow_tier_zero: bool = false
@export var allow_tier_five: bool = false
@export var portrait: Texture2D
@export var model_scene: PackedScene


@export_group("Combo")
@export var combo_effects: Array[ComboEffect] = []
@export var combo_handler: ComboHandler = null

@export_group("Sounds")
@export var sound_punch: AudioStream
@export var sound_name: AudioStream
@export var sound_hurt: AudioStream
@export var sound_defeat: AudioStream
@export var sound_block: AudioStream
@export var sound_dodge: AudioStream
@export var sound_shooting_punch: AudioStream
@export var sound_fall_impact: AudioStream
@export var sound_death_rattle: AudioStream
@export var sound_pushed: AudioStream
