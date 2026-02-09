class_name PlayerInfo
extends Control

# References to UI elements (to be assigned in Inspector)
@export var health_gauge: TextureProgressBar
@export var health_gauge_ghost: TextureProgressBar
@export var portrait_rect: TextureRect
@export var health_label: Label

var _current_hp: int = 0
var _max_hp: int = 0
var _tween: Tween
var _ghost_tween: Tween

func setup(data: WrestlerData) -> void:
	print("PlayerInfo: setup called for ", data.display_name if data else "null")
	if not data: return
	
	_max_hp = data.max_health
	# On initialise la vie logique à 0, comme la jauge visuelle, pour un état de départ cohérent.
	_current_hp = 0
	
	if portrait_rect and data.portrait:
		portrait_rect.texture = data.portrait
		
		# Animation d'apparition du Portrait (Pop)
		var container = portrait_rect.get_parent()
		if container is Control:
			var size = container.size
			if size == Vector2.ZERO:
				size = container.custom_minimum_size
			container.pivot_offset = size / 2
			container.scale = Vector2.ZERO
			
			var tween = create_tween()
			tween.tween_property(container, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	
	if health_gauge:
		health_gauge.max_value = _max_hp
		print("PlayerInfo: HealthGauge max_value set to ", _max_hp)
		health_gauge.value = 0 # On part de 0 pour l'animation de remplissage
	
	if health_gauge_ghost:
		health_gauge_ghost.max_value = _max_hp
		health_gauge_ghost.value = 0
	
	if health_label:
		health_label.text = str(_max_hp)

func update_health(current: int, _max: int) -> void:
	# On vérifie si c'est la première fois qu'on remplit la jauge
	var is_initial_fill = (_current_hp == 0 and current > 0)
	var is_damage = (current < _current_hp)
	
	_current_hp = current
	
	if health_label:
		health_label.text = str(current)
		
	if not health_gauge:
		return

	if is_damage:
		_play_damage_feedback()
		# La barre principale descend instantanément
		health_gauge.value = float(current)
		
		# La barre fantôme suit avec un délai et une animation
		if health_gauge_ghost:
			if _ghost_tween and _ghost_tween.is_running():
				_ghost_tween.kill()
			_ghost_tween = create_tween()
			_ghost_tween.tween_interval(0.4) # Délai pour voir l'écart
			_ghost_tween.tween_property(health_gauge_ghost, "value", float(current), 0.3).set_trans(Tween.TRANS_SINE)
	else: # Cas du soin ou du remplissage initial
		if _tween and _tween.is_running():
			_tween.kill()
		_tween = create_tween()
		
		var duration = 1.0 if is_initial_fill else 0.5
		if is_initial_fill:
			_tween.tween_interval(0.3)
		
		_tween.tween_property(health_gauge, "value", float(current), duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if health_gauge_ghost:
			_tween.tween_property(health_gauge_ghost, "value", float(current), duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _play_damage_feedback() -> void:
	# 1. Flash Blanc sur la jauge
	var flash_tween = create_tween()
	health_gauge.tint_progress = Color.WHITE
	flash_tween.tween_property(health_gauge, "tint_progress", Color("a22633"), 0.3)
	
	# 2. Screen Shake localisé (sur le Control racine)
	var shake_tween = create_tween()
	var original_pos = Vector2.ZERO # Position locale relative
	for i in range(5):
		var offset = Vector2(randf_range(-5, 5), randf_range(-5, 5))
		shake_tween.tween_property(self , "position", position + offset, 0.05)
	shake_tween.tween_property(self , "position", position, 0.05)