class_name EndTurnButton
extends TextureButton

signal end_turn_pressed

# res://assets/UI/Btn/end_turn.png : 5 frames de 20x20 sur une ligne.
# 1: face "End Turn" (mon tour) - 2: face "Wait" (tour adverse) - 3,4,5: frames de rotation.
const SPRITESHEET = preload("res://assets/UI/Btn/end_turn.png")
const FRAME_SIZE = 20
const FRAME_END_TURN_SIDE = 0
const FRAME_WAIT_SIDE = 1
const FRAMES_END_TURN_TO_WAIT = [2, 3, 4]
const FRAMES_WAIT_TO_END_TURN = [4, 3, 2]
const FRAME_DURATION = 0.08

@onready var shadow: TextureRect = $Shadow

var is_my_turn: bool = false
var bobbing_tween: Tween
var original_y_pos: float
var shadow_rest_position: Vector2

func _ready() -> void:
	pressed.connect(_on_pressed)
	original_y_pos = position.y
	if shadow:
		shadow_rest_position = shadow.position
	_set_frame(FRAME_WAIT_SIDE)
	# The initial state will be set by GameUI when the first turn starts.

# Le jeton "flotte" (monte/descend), mais l'ombre doit rester au sol : sa position locale
# compense exactement la montée du parent (+height en Y), et se décale en plus vers la
# droite (+height * 0.5) pour simuler une lumière venant du haut-gauche de l'écran.
func _shadow_position_for_height(height: float) -> Vector2:
	return shadow_rest_position + Vector2(height * 0.5, height)

func _get_frame(index: int) -> AtlasTexture:
	var atlas = AtlasTexture.new()
	atlas.atlas = SPRITESHEET
	atlas.region = Rect2(index * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
	return atlas

# L'ombre réutilise exactement la même frame que le jeton (silhouette, pas un blob rond) :
# modulate = Color(0,0,0,a) sur Shadow écrase les couleurs du sprite à 0, ne laissant que sa
# forme (le carré à coins arrondis) teintée en noir semi-transparent.
func _set_frame(index: int) -> void:
	var frame = _get_frame(index)
	texture_normal = frame
	if shadow:
		shadow.texture = frame

func set_player_turn(is_turn: bool, skip_animation: bool = false) -> void:
	# Avoid re-animating if state is the same
	if is_my_turn == is_turn and not skip_animation:
		return

	is_my_turn = is_turn
	disabled = not is_my_turn

	if skip_animation:
		_set_frame(FRAME_END_TURN_SIDE if is_my_turn else FRAME_WAIT_SIDE)
		_update_visual_state()
	else:
		_play_flip_animation(is_my_turn)

func _update_visual_state() -> void:
	if is_my_turn:
		modulate = Color.WHITE
		_start_bobbing()
	else:
		modulate = Color(0.7, 0.7, 0.7, 1.0) # Darken
		if bobbing_tween and bobbing_tween.is_running():
			bobbing_tween.kill()
		# Reset position in case bobbing was interrupted
		position.y = original_y_pos
		if shadow:
			shadow.position = shadow_rest_position

func _play_flip_animation(is_turn: bool) -> void:
	if bobbing_tween and bobbing_tween.is_running():
		bobbing_tween.kill()

	var rotation_frames = FRAMES_WAIT_TO_END_TURN if is_turn else FRAMES_END_TURN_TO_WAIT
	var final_frame = FRAME_END_TURN_SIDE if is_turn else FRAME_WAIT_SIDE

	# Part 1: Jump
	var tween = create_tween().set_parallel()
	tween.tween_property(self , "position:y", original_y_pos - 20, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if shadow:
		tween.tween_property(shadow, "modulate:a", 0.2, 0.2)
		tween.tween_property(shadow, "scale", Vector2(0.8, 0.8), 0.2)
		tween.tween_property(shadow, "position", _shadow_position_for_height(20), 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Rotation : on joue les frames intermédiaires pendant le saut
	for frame_index in rotation_frames:
		_set_frame(frame_index)
		await get_tree().create_timer(FRAME_DURATION).timeout

	# Fin de rotation : on se pose sur la face finale et on met à jour l'état
	_set_frame(final_frame)
	_update_visual_state()

	# Part 2: Land
	var tween2 = create_tween().set_parallel()
	tween2.tween_property(self , "position:y", original_y_pos, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if shadow:
		tween2.tween_property(shadow, "modulate:a", 0.4, 0.2) # Shadow is never fully opaque
		tween2.tween_property(shadow, "scale", Vector2(1.0, 1.0), 0.2)
		tween2.tween_property(shadow, "position", shadow_rest_position, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _start_bobbing() -> void:
	# set_player_turn peut être appelé plusieurs fois de suite avec skip_animation=true (ex: au
	# lancement du match) ; sans ce kill, l'ancien tween continue de tourner en tâche de fond et
	# se bat frame par frame avec le nouveau sur "position:y", donnant l'impression que le jeton
	# ne bouge plus du tout.
	if bobbing_tween and bobbing_tween.is_running():
		bobbing_tween.kill()

	bobbing_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	bobbing_tween.tween_property(self , "position:y", original_y_pos - 8, 1.2)
	if shadow:
		bobbing_tween.parallel().tween_property(shadow, "position", _shadow_position_for_height(8), 1.2)
	bobbing_tween.tween_property(self , "position:y", original_y_pos, 1.2)
	if shadow:
		bobbing_tween.parallel().tween_property(shadow, "position", shadow_rest_position, 1.2)

func _on_pressed() -> void:
	if not disabled:
		end_turn_pressed.emit()
