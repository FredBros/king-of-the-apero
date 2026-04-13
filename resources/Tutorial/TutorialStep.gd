class_name TutorialStep
extends Resource

@export_category("General")
@export var step_id: String = "unique_step_id"
@export var text_key: String = "TUTO_TEXT_KEY"

@export_group("Display Options")
## Noms ou identifiants des éléments UI à cibler (ex: ["Player1Health", "Player2Health"]).
## Le chef d'orchestre (Tutorial.gd) se chargera de trouver les vrais Nodes à partir de ces noms.
@export var target_ui_names: Array[String] = []
@export var pauses_game: bool = false

## Si vrai, le jeu ne lancera pas le tuto suivant tant que le joueur n'aura pas fait une action (jouer, jeter, passer son tour).
@export var wait_for_action_after: bool = false

@export_group("Media (Optional)")
@export var media_textures: Array[Texture2D] = []
@export var video_stream: VideoStream = null

@export_group("Triggers")
## Dictionnaire définissant quand déclencher ce tuto.
## Exemples de clés possibles (que Tutorial.gd lira) :
## - "is_player_turn": true
## - "has_move_card": true
## - "turn_number": 1
@export var trigger_conditions: Dictionary = {}
