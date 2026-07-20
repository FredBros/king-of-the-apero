extends Control

signal finished
signal skip_pressed

@onready var vs_image = $VSImage
@onready var skip_label = $SkipLabel

@onready var top_stack: VBoxContainer = %TopStack
@onready var top_sprite: TextureRect = %TopSprite
@onready var top_badge: TextureRect = %TopBadge
@onready var bottom_stack: VBoxContainer = %BottomStack
@onready var bottom_sprite: TextureRect = %BottomSprite
@onready var bottom_badge: TextureRect = %BottomBadge

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
	top_stack.scale = Vector2.ZERO
	bottom_stack.scale = Vector2.ZERO
	
	# NETTOYAGE : On supprime l'image Fight si elle traîne encore dans cette scène par erreur
	if has_node("FightImage"):
		get_node("FightImage").queue_free()
		print("VersusScreen: Ghost 'FightImage' removed.")
	
	# Fade in du label "Tap to Skip" après un court délai
	var tween = create_tween()
	tween.tween_property(skip_label, "modulate:a", 1.0, 0.5).set_delay(1.0)

# Appelé par le GameManager pour initialiser la scène
func setup(local_wrestler_data: WrestlerData, remote_wrestler_data: WrestlerData) -> void:
	var current_delay = 0.0
	
	# 1. Instancier le modèle du haut
	_spawn_model(local_wrestler_data, current_delay, top_sprite, top_badge, top_stack)
	
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
	_spawn_model(remote_wrestler_data, current_delay, bottom_sprite, bottom_badge, bottom_stack)
	
	# Calcul durée étape 3
	var t3 = 0.8
	if remote_wrestler_data and remote_wrestler_data.sound_name:
		t3 = max(remote_wrestler_data.sound_name.get_length(), 0.8)
	current_delay += t3
	
	# Mise à jour de la durée totale
	duration = current_delay + 1.0

func _spawn_model(data: WrestlerData, delay: float = 0.0, sprite_rect: TextureRect = null, badge_rect: TextureRect = null, stack: Control = null) -> void:
	if not data:
		return

	var tween = create_tween()
	if delay > 0:
		tween.tween_interval(delay)

	tween.tween_callback(func():
		if sprite_rect:
			sprite_rect.texture = data.sprite
		if badge_rect:
			badge_rect.texture = data.badge
		if data.sound_name:
			sound_component.play_varied(data.sound_name)
	)

	# Pop élastique du sprite+badge, synchronisé avec la voix (mêmes constantes que vs_image)
	if stack:
		tween.tween_property(stack, "scale", Vector2(1.5, 1.5), 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(stack, "scale", Vector2(1.0, 1.0), 0.2)

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