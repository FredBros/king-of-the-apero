class_name WrestlerData
extends Resource

@export var id: String = "wrestler_id"
@export var display_name: String = "Wrestler"
@export var max_health: int = 10
@export var combo_token: int = 4
@export var allow_tier_zero: bool = false
@export var allow_tier_five: bool = false
@export var portrait: Texture2D
@export var sprite: Texture2D
@export var color: Color
@export var badge: Texture2D

@export_group("Combo")
@export var combo_effects: Array[ComboEffect] = []
@export var combo_handler: ComboHandler = null

## Clés de traduction (translations.csv) pour le tooltip de présentation du
## personnage (CharacterSelect + tooltip in-game). combo_attack_keys /
## combo_move_keys : une clé par position de combo, index 0 = init (0 étoile).
@export_group("Description")
@export var intro_key: String = "CHAR_DEFAULT_INTRO"
@export var combo_attack_keys: Array[String] = [
	"CHAR_DEFAULT_COMBO_ATTACK_0", "CHAR_DEFAULT_COMBO_ATTACK_1",
	"CHAR_DEFAULT_COMBO_ATTACK_2", "CHAR_DEFAULT_COMBO_ATTACK_3",
]
@export var combo_move_keys: Array[String] = [
	"CHAR_DEFAULT_COMBO_MOVE_0", "CHAR_DEFAULT_COMBO_MOVE_1",
	"CHAR_DEFAULT_COMBO_MOVE_2", "CHAR_DEFAULT_COMBO_MOVE_3",
]
@export var passive_key: String = "CHAR_DEFAULT_PASSIVE"
@export var ulti_key: String = "CHAR_DEFAULT_ULTI"
@export var strengths_key: String = "CHAR_DEFAULT_STRENGTHS"
@export var weaknesses_key: String = "CHAR_DEFAULT_WEAKNESSES"

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
