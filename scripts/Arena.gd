extends Node3D

@onready var grid_manager: GridManager = $GridManager
@onready var game_ui: GameUI = $GameUI
@onready var game_manager: GameManager = $GameManager
@onready var camera_pivot: Node3D = $CameraPivot
@onready var deck_manager: DeckManager = $DeckManager

@export_group("UI - Tutorial")
@export var help_button: Button
@export var tutorial_overlay: Control
@export var tutorial_close_button: Button
@export var remote_pause_overlay: Control

@onready var loading_curtain = $LoadingCurtain
@onready var fight_image = $FightLayer/FightImage
const FIGHT_SOUND = preload("res://assets/Sounds/Voices/fight.wav")
const UI_SOUND_COMPONENT_SCENE = preload("res://scenes/Components/UISoundComponent.tscn")
var sound_component

var is_remote_paused: bool = false

func _ready() -> void:
	# Connect the UI signal to the GridManager
	if game_ui and grid_manager:
		game_ui.card_selected.connect(grid_manager.on_card_selected)
		game_ui.card_dropped_on_world.connect(grid_manager.on_card_dropped_on_world)
		grid_manager.game_over.connect(func(winner_name):
			game_ui.show_game_over(winner_name)
			game_manager.is_game_active = false
		)
		
	# Handle Disconnections (Win by forfeit)
	NetworkManager.player_disconnected.connect(func(id):
		if game_manager.is_game_active:
			print("Opponent disconnected! You win.")
			# In a 1v1, if the other disconnects, the remaining player wins.
			game_ui.show_game_over("Opponent Disconnected")
			game_manager.is_game_active = false
		
		# If opponent leaves (during game or after), restart is impossible
		game_ui.disable_restart_button()
	)
	
	NetworkManager.server_disconnected.connect(func():
		game_ui.disable_restart_button()
	)
		
	# Setup Game Manager
	if game_manager:
		# Inject dependency into GridManager
		grid_manager.game_manager = game_manager
		game_manager.grid_manager = grid_manager
		
		# Connect UI End Turn button with visual reset
		game_ui.end_turn_pressed.connect(game_manager.end_turn)
		
		# Connect Game Manager signals to UI
		game_manager.turn_started.connect(func(player_name):
			game_ui.update_turn_info(player_name)
		)
		
		game_manager.game_paused.connect(_on_remote_game_paused)
		
		game_manager.game_over.connect(func(winner_name):
			game_ui.show_game_over(winner_name)
			game_manager.is_game_active = false
		)
		
		# Connect Card Discarding to GridManager (to clear highlights)
		game_manager.card_discarded.connect(grid_manager.on_card_discarded)
		
		# Connect Reaction UI
		game_manager.reaction_phase_started.connect(game_ui.start_reaction_request)
		game_ui.reaction_selected.connect(game_manager.on_reaction_selected)
		game_ui.reaction_skipped.connect(game_manager.on_reaction_skipped)
		
		# Connect Game Manager to Grid Manager (to sync active wrestler)
		game_manager.turn_started.connect(func(player_name):
			grid_manager.set_active_wrestler(game_manager.get_active_wrestler())

			_update_hand_display(player_name)
			call_deferred("_check_hand_playability")
		)
		
		game_manager.refresh_hand_requested.connect(func(player_name):
			_update_hand_display(player_name)
		)
		
		# Connect Health Signals
		# This is now done after spawning, to ensure wrestlers exist.
		grid_manager.wrestlers_spawned.connect(_on_wrestlers_spawned)
		
		# Initialize Game Manager network part. Game state init will be triggered by character selection.
		game_manager.initialize_network(deck_manager)
		
		_setup_player_camera_view()

	# Adjust camera for Portrait Mode (Zoom In)
	var camera = get_viewport().get_camera_3d()
	if camera and camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		camera.fov = 50.0
		
	# Setup Tutorial UI from editor nodes
	if help_button:
		help_button.pressed.connect(_toggle_tutorial.bind(true))
	if tutorial_close_button:
		tutorial_close_button.pressed.connect(_toggle_tutorial.bind(false))
	
	if tutorial_overlay:
		tutorial_overlay.visible = false
	if remote_pause_overlay:
		remote_pause_overlay.visible = false
		
	# Initialisation Audio
	sound_component = UI_SOUND_COMPONENT_SCENE.instantiate()
	add_child(sound_component)
	
	# Initialisation Visuelle
	if fight_image:
		fight_image.scale = Vector2.ZERO
		# On ne lance PLUS la séquence ici. On attend que le VersusScreen nous le dise.
		# _play_fight_sequence()
	else:
		printerr("Arena: Fight Image NOT found! Check if FightLayer/FightImage exists in Arena.tscn")

func _check_hand_playability() -> void:
	print("Arena: Checking hand playability...")
	
	if not game_manager.is_game_active:
		return

	# Check only if it's our turn to avoid calculations for the opponent
	if game_manager.is_local_player_active():
		var playable_cards = game_manager.get_playable_cards_in_hand()
		game_ui.update_cards_playability(playable_cards)

func _update_hand_display(player_name: String) -> void:
	# In hotseat mode, we refresh the hand to show the specific player's cards.
	# In network mode, we usually rely on signals, but sometimes a full refresh is needed (e.g. restart).
	var is_local = false
	if game_manager.has_method("_get_my_player_name"):
		is_local = (player_name == game_manager._get_my_player_name())
	
	if game_manager.is_in_hotseat_mode() or is_local:
		game_ui.clear_hand()
		var hand = game_manager.get_player_hand(player_name)
		for card in hand:
			game_ui.add_card_to_hand(card)

func _setup_player_camera_view() -> void:
	if not game_manager: return
	
	var my_name = game_manager._get_my_player_name()
	
	# Player 1 spawns at Top (Negative Z), so needs rotation to be at Bottom
	if my_name == "Player 1":
		if camera_pivot:
			print("I am Player 1. Rotating camera.")
			camera_pivot.rotate_y(PI)

func _on_wrestlers_spawned(wrestlers: Array[Wrestler]) -> void:
	# Connect Health Signals now that wrestlers exist
	for w in wrestlers:
		# We bind the wrestler instance so UI knows WHO changed health
		w.health_changed.connect(game_ui.on_wrestler_health_changed.bind(w))
		
		# Network Sync: When health changes locally, notify others
		w.health_changed.connect(func(current, _max):
			if not game_manager.is_network_syncing:
				game_manager.send_health_update(w.name, current)
		)
		w.action_completed.connect(_check_hand_playability)
	
	# Set UI perspectives (local player at bottom)
	_update_ui_player_perspectives()

func _update_ui_player_perspectives() -> void:
	if not game_manager or not game_ui: return
	
	var my_name = game_manager._get_my_player_name()
	var local_wrestler = null
	var remote_wrestler = null
	
	for w in grid_manager.wrestlers:
		if w.name == my_name:
			local_wrestler = w
		else:
			remote_wrestler = w
			
	if local_wrestler and remote_wrestler:
		game_ui.set_player_perspectives(local_wrestler, remote_wrestler)

func _toggle_tutorial(show: bool) -> void:
	if tutorial_overlay:
		tutorial_overlay.visible = show
	
	if game_manager:
		game_manager.send_pause_state(show)
		
	_update_pause_state()

func _on_remote_game_paused(paused: bool, _initiator: String) -> void:
	is_remote_paused = paused
	_update_pause_state()

func _update_pause_state() -> void:
	if not tutorial_overlay: return
	
	var local_paused = tutorial_overlay.visible
	
	# Show remote overlay only if we are paused remotely AND not looking at our own tutorial
	if remote_pause_overlay:
		remote_pause_overlay.visible = is_remote_paused and not local_paused
	
	var should_pause = local_paused or is_remote_paused
	get_tree().paused = should_pause
	
	if help_button:
		help_button.visible = not should_pause

# Appelée par le VersusScreen quand il a fini son animation
func start_fight_sequence() -> void:
	print("Arena: Starting Fight Sequence (Triggered by VersusScreen)")
	
	# On lève le rideau pour révéler l'arène
	if loading_curtain and loading_curtain.visible:
		var tween = create_tween()
		tween.tween_property(loading_curtain, "modulate:a", 0.0, 0.5)
		tween.tween_callback(func(): loading_curtain.visible = false)
	
	_play_fight_sequence()

func _play_fight_sequence() -> void:
	print("Arena: Playing Fight Sequence Animation")
	var tween = create_tween()
	# Petit délai pour laisser le temps à la scène de s'afficher proprement
	tween.tween_interval(0.5)
	
	# Son
	tween.tween_callback(func():
		if sound_component:
			sound_component.play_varied(FIGHT_SOUND)
	)
	
	if fight_image:
		# Apparition Pop
		tween.tween_property(fight_image, "scale", Vector2(2.25, 2.25), 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(fight_image, "scale", Vector2(1.5, 1.5), 0.2)
		
		# Pause
		tween.tween_interval(0.5)
		
		# Disparition
		tween.tween_property(fight_image, "scale", Vector2.ZERO, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)