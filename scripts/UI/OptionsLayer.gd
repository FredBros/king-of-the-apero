extends Control

@onready var back_button: Button = %BackButton

# SFX Controls
@onready var sfx_container: HBoxContainer = %SFXVolume
@onready var sfx_minus: TextureButton = sfx_container.get_node("MinusButton")
@onready var sfx_plus: TextureButton = sfx_container.get_node("PlusButton")
@onready var sfx_mute: TextureButton = sfx_container.get_node("MuteButton")
@onready var sfx_progress: ProgressBar = sfx_container.get_node("ProgressBarPanel/ProgressBar")

# Music Controls
@onready var music_container: HBoxContainer = %MusicVolume
@onready var music_minus: TextureButton = music_container.get_node("MinusButton")
@onready var music_plus: TextureButton = music_container.get_node("PlusButton")
@onready var music_mute: TextureButton = music_container.get_node("MuteButton")
@onready var music_progress: ProgressBar = music_container.get_node("ProgressBarPanel/ProgressBar")

const BUS_SFX_NAME = "SFX"
const BUS_MUSIC_NAME = "Music"
const VOLUME_STEP = 10.0

func _ready() -> void:
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
		_setup_button_feedback(back_button)
	
	# Setup SFX
	_setup_volume_controls(sfx_minus, sfx_plus, sfx_mute, sfx_progress, BUS_SFX_NAME)
	
	# Setup Music (Même si pas encore de musique, la mécanique sera prête)
	_setup_volume_controls(music_minus, music_plus, music_mute, music_progress, BUS_MUSIC_NAME)

func _setup_volume_controls(minus: BaseButton, plus: BaseButton, mute: BaseButton, progress: ProgressBar, bus_name: String) -> void:
	# Initialisation de la valeur visuelle depuis l'AudioServer
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx != -1:
		var is_muted = AudioServer.is_bus_mute(bus_idx)
		var db = AudioServer.get_bus_volume_db(bus_idx)
		if is_muted:
			progress.value = 0
		else:
			progress.value = db_to_linear(db) * 100.0
		_update_mute_visual(mute, is_muted)
	else:
		# Valeur par défaut si le bus n'existe pas encore
		printerr("OptionsLayer: Audio Bus '", bus_name, "' not found. UI running in mock mode.")
		progress.value = 50.0

	# Connexions des signaux
	# On passe le bouton mute à _change_volume pour mettre à jour son visuel si on unmute automatiquement
	minus.pressed.connect(func(): _change_volume(progress, mute, bus_name, -VOLUME_STEP))
	plus.pressed.connect(func(): _change_volume(progress, mute, bus_name, VOLUME_STEP))
	mute.pressed.connect(func(): _toggle_mute(mute, progress, bus_name))
	
	# Feedback visuel (Juicy) sur les TextureButtons
	_setup_button_feedback(minus)
	_setup_button_feedback(plus)
	_setup_button_feedback(mute)

func _change_volume(progress: ProgressBar, mute_btn: BaseButton, bus_name: String, amount: float) -> void:
	var new_val = clamp(progress.value + amount, 0, 100)
	progress.value = new_val
	
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx != -1:
		# Conversion 0-100 -> dB (Logarithmique pour l'audio)
		var linear = new_val / 100.0
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(linear))
		
		# Si on change le volume, on unmute automatiquement si c'était muté
		if AudioServer.is_bus_mute(bus_idx):
			AudioServer.set_bus_mute(bus_idx, false)
			_update_mute_visual(mute_btn, false)
	else:
		# Mock behavior: Unmute visual if volume changes
		_update_mute_visual(mute_btn, false)

func _toggle_mute(btn: BaseButton, progress: ProgressBar, bus_name: String) -> void:
	var bus_idx = AudioServer.get_bus_index(bus_name)
	var is_muted = false
	
	if bus_idx != -1:
		is_muted = not AudioServer.is_bus_mute(bus_idx)
		AudioServer.set_bus_mute(bus_idx, is_muted)
	else:
		# Mock toggle based on current visual state
		is_muted = (btn.modulate.a > 0.9) # Was 1.0 (Unmuted) -> Become Muted
	
	_update_mute_visual(btn, is_muted)
	
	if is_muted:
		progress.value = 0
	else:
		if bus_idx != -1:
			var db = AudioServer.get_bus_volume_db(bus_idx)
			progress.value = db_to_linear(db) * 100.0
		else:
			progress.value = 50.0 # Default restore for mock

func _update_mute_visual(btn: BaseButton, is_muted: bool) -> void:
	# On réduit l'opacité du bouton mute s'il est actif
	btn.modulate.a = 0.5 if is_muted else 1.0

func _on_back_pressed() -> void:
	hide()

func _setup_button_feedback(btn: Control) -> void:
	if not btn: return
	
	# On centre le pivot pour que le scale se fasse depuis le milieu
	btn.pivot_offset = btn.size / 2
	btn.resized.connect(func(): btn.pivot_offset = btn.size / 2)
	
	if btn is BaseButton:
		# Effet d'enfoncement (Squash)
		btn.button_down.connect(func():
			var tween = create_tween()
			tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.tween_property(btn, "scale", Vector2(0.95, 0.95), 0.1)
		)
		
		# Effet de relâchement avec rebond (Stretch & Bounce)
		btn.button_up.connect(func():
			var tween = create_tween()
			tween.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.3).from(Vector2(1.05, 1.05))
		)
