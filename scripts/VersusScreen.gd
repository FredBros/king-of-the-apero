extends Control

signal finished
signal skip_pressed

@onready var top_spawn = $VBoxContainer/TopContainer/SubViewport/TopScene/SpawnPoint
@onready var bottom_spawn = $VBoxContainer/BottomContainer/SubViewport/BottomScene/SpawnPoint
@onready var vs_image = $VSImage
@onready var skip_label = $SkipLabel

const VERSUS_SOUND = preload("res://assets/Sounds/Voices/versus.wav")
const UI_SOUND_COMPONENT_SCENE = preload("res://scenes/Components/UISoundComponent.tscn")

var sound_component

var local_skipped: bool = false
var remote_skipped: bool = false
var time_elapsed: float = 0.0
var duration: float = 3.0
var is_finished: bool = false

func _ready() -> void:
	# Instanciation du composant son UI
	sound_component = UI_SOUND_COMPONENT_SCENE.instantiate()
	add_child(sound_component)
	
	# État initial
	vs_image.scale = Vector2.ZERO
	skip_label.modulate.a = 0.0
	
	# Fade in du label "Tap to Skip" après un court délai
	var tween = create_tween()
	tween.tween_property(skip_label, "modulate:a", 1.0, 0.5).set_delay(1.0)

# Appelé par le GameManager pour initialiser la scène
func setup(local_wrestler_data: WrestlerData, remote_wrestler_data: WrestlerData) -> void:
	var current_delay = 0.0
	
	# 1. Instancier le modèle du haut
	_spawn_model(local_wrestler_data, top_spawn, current_delay)
	
	# Calcul durée étape 1 (Son ou min 0.8s pour l'anim visuelle)
	var t1 = 0.8
	if local_wrestler_data and local_wrestler_data.sound_name:
		t1 = max(local_wrestler_data.sound_name.get_length(), 0.8)
	current_delay += t1
	
	# 2. Lancer la séquence VS
	_start_intro_sequence(current_delay)
	
	# Calcul durée étape 2 (Son VS ou min 0.5s)
	var t2 = max(VERSUS_SOUND.get_length(), 0.5)
	current_delay += t2
	
	# 3. Instancier le modèle du bas
	_spawn_model(remote_wrestler_data, bottom_spawn, current_delay)
	
	# Mise à jour de la durée totale de la scène (Délai accumulé + Durée dernier son + Buffer)
	var t3 = 0.8
	if remote_wrestler_data and remote_wrestler_data.sound_name:
		t3 = max(remote_wrestler_data.sound_name.get_length(), 0.8)
	
	duration = current_delay + t3 + 1.0

func _spawn_model(data: WrestlerData, parent: Node3D, delay: float = 0.0) -> void:
	if not data or not data.model_scene:
		return
		
	var model = data.model_scene.instantiate()
	parent.add_child(model)
	
	# Gestion Animation (Flex > Idle)
	var anim_player = model.find_child("AnimationPlayer", true, false)
	if anim_player:
		if anim_player.has_animation("Flex"):
			anim_player.play("Flex")
		elif anim_player.has_animation("Idle"):
			anim_player.play("Idle")
	
	# Animation d'apparition (Zoom In)
	model.scale = Vector3.ZERO
	var tween = create_tween()
	if delay > 0:
		tween.tween_interval(delay)
	
	# Jouer le son d'annonce du personnage
	if data.sound_name:
		tween.tween_callback(func():
			sound_component.play_varied(data.sound_name)
		)
		
	tween.tween_property(model, "scale", Vector3.ONE, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _start_intro_sequence(delay: float = 0.0) -> void:
	# Animation VS (Flashy Bump)
	var tween = create_tween()
	if delay > 0:
		tween.tween_interval(delay)
		
	tween.tween_callback(func():
		sound_component.play_varied(VERSUS_SOUND)
	)
	# Zoom In rapide (Overshoot)
	tween.tween_property(vs_image, "scale", Vector2(1.5, 1.5), 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	# Retour taille normale
	tween.tween_property(vs_image, "scale", Vector2(1.0, 1.0), 0.2)

func _process(delta: float) -> void:
	if is_finished: return
	
	time_elapsed += delta
	if time_elapsed >= duration:
		_finish()

func _input(event: InputEvent) -> void:
	if is_finished: return
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not local_skipped:
			_on_local_skip()

func _on_local_skip() -> void:
	local_skipped = true
	skip_label.text = "Waiting for opponent..."
	skip_pressed.emit() # Prévenir le GameManager pour envoyer l'info au réseau
	_check_skip_condition()

# Appelé par le GameManager quand l'adversaire a skippé
func set_opponent_skipped() -> void:
	remote_skipped = true
	_check_skip_condition()

func _check_skip_condition() -> void:
	# Si les deux ont skippé, on termine immédiatement
	if local_skipped and remote_skipped:
		_finish()

func _finish() -> void:
	if is_finished: return
	is_finished = true
	finished.emit()
	# L'animation de sortie ou la destruction sera gérée par le parent (GameManager/Arena)
	queue_free()