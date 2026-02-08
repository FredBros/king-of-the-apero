# Version UI (Non-Spatiale) du SoundComponent
# class_name UISoundComponent
extends AudioStreamPlayer

@export var pitch_min: float = 0.9
@export var pitch_max: float = 1.1
@export var volume_variance_db: float = 2.0

func _ready() -> void:
	# S'assurer que la polyphonie est activée
	if max_polyphony < 2:
		max_polyphony = 5

func play_varied(stream_to_play: AudioStream) -> void:
	if not stream_to_play:
		return
	
	stream = stream_to_play
	
	# Variation aléatoire
	pitch_scale = randf_range(pitch_min, pitch_max)
	volume_db = randf_range(-volume_variance_db, volume_variance_db)
	
	play()