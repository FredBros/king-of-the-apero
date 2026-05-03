extends Control

const CTA_URL = "https://trankil.itch.io/folklore-on-tap"
const UI_SOUND_COMPONENT_SCENE = preload("res://scenes/Components/UISoundComponent.tscn")
const CHALK_TIC_SOUND = preload("res://assets/Sounds/UI/chalk_tic.wav")

@onready var button: TextureButton = $TextureButton
var ui_sound: UISoundComponent

func _ready() -> void:
	ui_sound = UI_SOUND_COMPONENT_SCENE.instantiate()
	add_child(ui_sound)

	if button:
		button.pressed.connect(_on_pressed)
		_setup_button_feedback(button)

func _on_pressed() -> void:
	OS.shell_open(CTA_URL)

func _setup_button_feedback(btn: BaseButton) -> void:
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
