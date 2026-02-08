# On retire le class_name pour éviter le conflit "hides global script class"
# class_name SoundPoolComponent
extends Node3D

@export var pool_size: int = 5 # Suffisant pour gérer Impact + Cri + Ambiance simultanés

const SOUND_COMPONENT_SCENE = preload("res://scenes/Components/SoundComponent.tscn")

var _pool: Array = []
var _current_index: int = 0

func _ready() -> void:
	# On instancie le pool de lecteurs audio
	for i in range(pool_size):
		var player = SOUND_COMPONENT_SCENE.instantiate()
		add_child(player)
		_pool.append(player)

func play_varied(stream: AudioStream, volume_offset: float = 0.0) -> void:
	if not stream or _pool.is_empty():
		return
	
	var player = _pool[_current_index]
	# On joue le son sur le lecteur disponible (ou le plus ancien)
	if player.has_method("play_varied"):
		player.play_varied(stream)
		if volume_offset != 0.0:
			player.volume_db += volume_offset
	
	_current_index = (_current_index + 1) % _pool.size()

func play_random(streams: Array, volume_offset: float = 0.0) -> void:
	if streams.is_empty(): return
	play_varied(streams.pick_random(), volume_offset)