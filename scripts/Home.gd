extends Control

@onready var play_button: Button = %PlayButton
@onready var options_button: Button = %OptionsButton
@onready var rules_button: Button = %RulesButton
@onready var quit_button: Button = %QuitButton

const LOBBY_SCENE_PATH = "res://scenes/Lobby.tscn"
const TUTO_LAYER_SCENE = preload("res://scenes/UI/Tuto_layer.tscn")
const OPTIONS_LAYER_SCENE = preload("res://scenes/UI/OptionsLayer.tscn")
const UI_SOUND_COMPONENT_SCENE = preload("res://scenes/Components/UISoundComponent.tscn")
const CHALK_TIC_SOUND = preload("res://assets/Sounds/UI/chalk_tic.wav")

var option_layer_instance: CanvasLayer
var options_menu_instance: Control
var ui_sound: UISoundComponent

func _ready() -> void:
	ui_sound = UI_SOUND_COMPONENT_SCENE.instantiate()
	add_child(ui_sound)

	play_button.pressed.connect(_on_play_pressed)
	options_button.pressed.connect(_on_options_pressed)
	rules_button.pressed.connect(_on_rules_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	
	_setup_button_feedback(play_button)
	_setup_button_feedback(options_button)
	_setup_button_feedback(rules_button)
	_setup_button_feedback(quit_button)

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE_PATH)

func _on_options_pressed() -> void:
	if not options_menu_instance:
		options_menu_instance = OPTIONS_LAYER_SCENE.instantiate()
		add_child(options_menu_instance)
	else:
		options_menu_instance.show()

func _on_rules_pressed() -> void:
	if not option_layer_instance:
		option_layer_instance = TUTO_LAYER_SCENE.instantiate()
		add_child(option_layer_instance)
		# Mode Menu : On cache le bouton flottant "?" qui ne sert à rien ici
		if option_layer_instance.has_method("hide_help_button"):
			option_layer_instance.hide_help_button()
	
	# On force l'ouverture immédiate du panneau
	if option_layer_instance.has_method("open_tutorial"):
		option_layer_instance.open_tutorial()

func _on_quit_pressed() -> void:
	get_tree().quit()

func _setup_button_feedback(btn: Button) -> void:
	if not btn: return
	
	# On centre le pivot pour que le scale se fasse depuis le milieu
	btn.pivot_offset = btn.size / 2
	btn.resized.connect(func(): btn.pivot_offset = btn.size / 2)
	
	# Effet d'enfoncement (Squash)
	btn.button_down.connect(func():
		btn.pivot_offset = btn.size / 2
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(btn, "scale", Vector2(0.95, 0.95), 0.1)
		if ui_sound: ui_sound.play_varied(CHALK_TIC_SOUND)
	)
	
	# Effet de relâchement avec rebond (Stretch & Bounce)
	btn.button_up.connect(func():
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.3).from(Vector2(1.05, 1.05))
	)
