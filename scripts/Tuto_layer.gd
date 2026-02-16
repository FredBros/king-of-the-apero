extends CanvasLayer

@onready var help_button: Button = %HelpButton
@onready var tutorial_overlay: Control = %TutorialOverlay
@onready var tutorial_close_button: Button = %TutorialCloseButton
@onready var remote_pause_overlay: Control = %RemotePauseOverlay

var game_manager: GameManager
var is_remote_paused: bool = false

func _ready() -> void:
	# Find GameManager in the scene tree
	game_manager = get_tree().root.find_child("GameManager", true, false)
	
	if game_manager:
		game_manager.game_paused.connect(_on_remote_game_paused)
	
	help_button.pressed.connect(_toggle_tutorial.bind(true))
	tutorial_close_button.pressed.connect(_toggle_tutorial.bind(false))
	
	tutorial_overlay.visible = false
	remote_pause_overlay.visible = false

func _toggle_tutorial(show: bool) -> void:
	tutorial_overlay.visible = show
	
	if game_manager:
		game_manager.send_pause_state(show)
		
	_update_pause_state()

func _on_remote_game_paused(paused: bool, _initiator: String) -> void:
	is_remote_paused = paused
	_update_pause_state()

func _update_pause_state() -> void:
	var local_paused = tutorial_overlay.visible
	
	# Show remote overlay only if we are paused remotely AND not looking at our own tutorial
	remote_pause_overlay.visible = is_remote_paused and not local_paused
	
	var should_pause = local_paused or is_remote_paused
	get_tree().paused = should_pause
	
	help_button.visible = not should_pause

# --- Public API for Menu usage ---

func open_tutorial() -> void:
	_toggle_tutorial(true)

func hide_help_button() -> void:
	if help_button: help_button.hide()
