class_name EndTurnButton
extends TextureButton

signal end_turn_pressed

@export var player_turn_texture: Texture2D
@export var opponent_turn_texture: Texture2D

@onready var shadow: TextureRect = $Shadow

var is_my_turn: bool = false
var bobbing_tween: Tween
var original_y_pos: float

func _ready() -> void:
	pressed.connect(_on_pressed)
	original_y_pos = position.y
	# The initial state will be set by GameUI when the first turn starts.

func set_player_turn(is_turn: bool, skip_animation: bool = false) -> void:
	# Avoid re-animating if state is the same
	if is_my_turn == is_turn and not skip_animation:
		return

	is_my_turn = is_turn
	disabled = not is_my_turn

	var new_texture = player_turn_texture if is_my_turn else opponent_turn_texture
	
	if skip_animation:
		texture_normal = new_texture
		_update_visual_state()
	else:
		_play_flip_animation(new_texture)

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

func _play_flip_animation(new_texture: Texture2D) -> void:
	if bobbing_tween and bobbing_tween.is_running():
		bobbing_tween.kill()

	var tween = create_tween().set_parallel()
	
	# Part 1: Flatten and Jump
	tween.tween_property(self , "scale:x", 0.0, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(self , "position:y", original_y_pos - 20, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if shadow:
		tween.tween_property(shadow, "modulate:a", 0.2, 0.2)
		tween.tween_property(shadow, "scale", Vector2(0.8, 0.8), 0.2)

	await tween.finished

	# Mid-point: Swap texture and update state
	texture_normal = new_texture
	_update_visual_state()

	# Part 2: Un-flatten and Land
	var tween2 = create_tween().set_parallel()
	tween2.tween_property(self , "scale:x", 1.0, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween2.tween_property(self , "position:y", original_y_pos, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if shadow:
		tween2.tween_property(shadow, "modulate:a", 0.4, 0.2) # Shadow is never fully opaque
		tween2.tween_property(shadow, "scale", Vector2(1.0, 1.0), 0.2)

func _start_bobbing() -> void:
	bobbing_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	bobbing_tween.tween_property(self , "position:y", original_y_pos - 8, 1.2)
	bobbing_tween.tween_property(self , "position:y", original_y_pos, 1.2)

func _on_pressed() -> void:
	if not disabled:
		end_turn_pressed.emit()
