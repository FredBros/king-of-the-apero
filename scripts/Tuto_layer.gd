extends CanvasLayer

@onready var tutorial_overlay: Control = %TutorialOverlay
@onready var tutorial_close_button: Button = %TutorialCloseButton
@onready var remote_pause_overlay: Control = %RemotePauseOverlay

@onready var title_label: Label = %TutorialOverlay.get_node("ChalkPanel/MarginContainer/VBoxContainer/HBoxContainer/Label")
@onready var rules_label: RichTextLabel = %TutorialOverlay.get_node("ChalkPanel/MarginContainer/VBoxContainer/ScrollContainer/VBoxContainer/RulesLabel")
@onready var pause_label: Label = %RemotePauseOverlay.get_node("Label")

var game_manager: GameManager

const UI_SOUND_COMPONENT_SCENE = preload("res://scenes/Components/UISoundComponent.tscn")
const CHALK_TIC_SOUND = preload("res://assets/Sounds/UI/chalk_tic.wav")

var ui_sound: UISoundComponent

func _ready() -> void:
	update_text()

	# Find GameManager in the scene tree
	game_manager = get_tree().root.find_child("GameManager", true, false)
	
	ui_sound = UI_SOUND_COMPONENT_SCENE.instantiate()
	add_child(ui_sound)
	
	tutorial_close_button.pressed.connect(_toggle_tutorial.bind(false))
	_setup_button_feedback(tutorial_close_button)
	
	tutorial_overlay.visible = false
	remote_pause_overlay.visible = false

func _toggle_tutorial(show: bool) -> void:
	tutorial_overlay.visible = show
	
	if game_manager and game_manager.has_method("request_pause"):
		game_manager.request_pause(show)

func update_text() -> void:
	title_label.text = tr("TUTO_TITLE")
	rules_label.text = tr("TUTO_MAIN_TEXT")
	pause_label.text = tr("TUTO_PAUSE_TEXT")

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		if is_node_ready():
			update_text()

# --- Public API for Menu usage ---

func open_tutorial() -> void:
	_toggle_tutorial(true)

func _setup_button_feedback(btn: Button) -> void:
	if not btn: return
	
	btn.pivot_offset = btn.size / 2
	btn.resized.connect(func(): btn.pivot_offset = btn.size / 2)
	
	btn.button_down.connect(func():
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(btn, "scale", Vector2(0.95, 0.95), 0.1)
		if ui_sound: ui_sound.play_varied(CHALK_TIC_SOUND)
	)
	
	btn.button_up.connect(func():
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.3).from(Vector2(1.05, 1.05))
	)
