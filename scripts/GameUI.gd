class_name GameUI
extends CanvasLayer

signal card_selected(card_data: CardData)
signal card_discard_requested(card_data: CardData)
signal card_dropped_on_world(card_data: CardData, screen_position: Vector2)
signal end_turn_pressed
signal reaction_selected(card_data: CardData)
signal reaction_skipped

@export var top_player_info: PlayerInfo
@export var bottom_player_info: PlayerInfo

var active_wrestler_ref: Wrestler
var opponent_wrestler_ref: Wrestler

@export var card_ui_scene: PackedScene
@onready var hand_container: HBoxContainer = $HandContainer
@onready var game_over_container: CenterContainer = $GameOverContainer
@onready var winner_label: Label = $GameOverContainer/Panel/MarginContainer/VBoxContainer/WinnerLabel

@onready var turn_label: Label = $TurnInfoContainer/VBoxContainer/TurnLabel

var selected_card_ui: CardUI

# Reaction UI Elements
var reaction_timer: Timer
var pass_button: Button
var opponent_card_display: CardUI
var is_reaction_phase: bool = false

# Drop Zone for Push mechanic
var drop_zone: DropZone

var game_manager_ref

func _ready() -> void:
	# Connect restart button manually since we added it via code/tscn edit
	var restart_btn = $GameOverContainer/Panel/MarginContainer/VBoxContainer/RestartButton
	restart_btn.pressed.connect(_on_restart_button_pressed)
	
	# Connect quit button manually
	var quit_btn = $GameOverContainer/Panel/MarginContainer/VBoxContainer/QuitButton
	quit_btn.pressed.connect(_on_quit_button_pressed)
	
	# Connect end turn button manually
	var end_turn_btn = $EndTurnButton
	end_turn_btn.pressed.connect(_on_end_turn_button_pressed)
	
	# Connexion dynamique au GameManager
	# On cherche le GameManager dans la scène (il devrait être un frère ou un parent)
	var game_manager = get_tree().root.find_child("GameManager", true, false)
	game_manager_ref = game_manager
	if game_manager:
		if not game_manager.card_drawn.is_connected(add_card_to_hand):
			game_manager.card_drawn.connect(add_card_to_hand)
		if not game_manager.card_discarded.is_connected(remove_card_from_hand):
			game_manager.card_discarded.connect(remove_card_from_hand)
	else:
		printerr("GameUI: GameManager not found!")
	
	# Setup Drop Zone for Drag & Drop (Push)
	drop_zone = DropZone.new()
	add_child(drop_zone)
	move_child(drop_zone, 0) # Ensure it's behind everything else
	drop_zone.card_dropped.connect(_on_card_dropped_on_zone)
	
	_setup_reaction_ui()

func _setup_reaction_ui() -> void:
	# 1. Timer
	reaction_timer = Timer.new()
	reaction_timer.wait_time = 3.0 # 3 secondes pour réagir
	reaction_timer.one_shot = true
	reaction_timer.timeout.connect(_on_reaction_timeout)
	add_child(reaction_timer)
	
	# 2. Pass Button (Croix Rouge)
	pass_button = Button.new()
	pass_button.text = "✖" # Caractère croix
	pass_button.add_theme_font_size_override("font_size", 40)
	pass_button.add_theme_color_override("font_color", Color.RED)
	pass_button.flat = true
	pass_button.hide()
	pass_button.pressed.connect(_on_pass_button_pressed)
	# Positionner en bas à droite ou au centre
	pass_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	pass_button.position.y -= 150 # Remonter un peu au dessus de la main
	add_child(pass_button)
	
	# 3. Opponent Card Display Placeholder
	# On l'instanciera à la volée ou on garde une ref vide

func _input(event: InputEvent) -> void:
	# Si on clique n'importe où ailleurs pendant la phase de réaction -> Pass
	if is_reaction_phase and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# On vérifie si on a cliqué sur une carte ou le bouton pass
		# Si l'event n'a pas été consommé par l'UI (CardUI), c'est un clic dans le vide
		# Note: Godot propage l'input. Une façon simple est de vérifier si on survole une carte.
		# Pour ce POC, on va supposer que si on arrive ici, c'est que ce n'est pas une carte.
		# Mais attention, _input voit tout.
		# Mieux : On utilise un grand bouton invisible en fond ?
		# Ou simplement : Si on clique sur le GridManager (3D), ça trigger le pass.
		pass

# --- Reaction Logic ---

func _on_end_turn_button_pressed() -> void:
	end_turn_pressed.emit()

func _on_restart_button_pressed() -> void:
	# Request a rematch (reload scene keeping connection)
	# NetworkManager.request_rematch() # TODO: Re-implement rematch logic with JSON messages
	pass

func _on_quit_button_pressed() -> void:
	# Return to lobby properly closing connection
	NetworkManager.return_to_lobby()

func update_turn_info(player_name: String) -> void:
	turn_label.text = player_name + "'s Turn"

func _on_card_dropped_on_zone(card_data: CardData, pos: Vector2) -> void:
	card_dropped_on_world.emit(card_data, pos)

func add_card_to_hand(card_data: CardData) -> void:
	print("DEBUG UI: Adding card ", card_data.title, " to hand.")
	var card = card_ui_scene.instantiate()
	hand_container.add_child(card)
	card.setup(card_data)
	card.clicked.connect(_on_card_clicked)
	card.discard_requested.connect(_on_card_discard_requested)
	card.drag_started.connect(_on_card_drag_started)
	card.drag_ended.connect(_on_card_drag_ended)
	card.swipe_pending.connect(_on_card_swipe_pending)
	card.swipe_committed.connect(_on_card_swipe_committed)
	card.selection_canceled.connect(_on_card_selection_canceled)

func remove_card_from_hand(card_data: CardData) -> void:
	for child in hand_container.get_children():
		# Comparaison par valeur (car les instances diffèrent via RPC)
		if child is CardUI and child.card_data.title == card_data.title and \
		   child.card_data.value == card_data.value and child.card_data.suit == card_data.suit:
			child.queue_free()
			if selected_card_ui == child:
				selected_card_ui = null
			break

func clear_hand() -> void:
	for child in hand_container.get_children():
		child.queue_free()
	selected_card_ui = null

func _create_card_data(type: CardData.CardType, value: int, title: String) -> CardData:
	var card = CardData.new()
	card.type = type
	card.value = value
	card.title = title
	return card

func _on_card_clicked(card_ui: CardUI) -> void:
	if is_reaction_phase:
		# En phase de réaction, cliquer sur une carte valide la joue comme contre
		# On vérifie si elle est candidate (scale > 1.0 est un hack, mieux vaut un flag sur CardUI, mais ici on check visuel)
		if card_ui.scale.x > 1.1:
			_end_reaction_phase()
			reaction_selected.emit(card_ui.card_data)
		return

	if selected_card_ui and selected_card_ui != card_ui:
		selected_card_ui.set_selected(false)
	
	selected_card_ui = card_ui
	selected_card_ui.set_selected(true)
	card_selected.emit(card_ui.card_data)

func _on_card_selection_canceled(card_ui: CardUI) -> void:
	if selected_card_ui == card_ui:
		selected_card_ui.set_selected(false)
		selected_card_ui = null
		# Notify GridManager to clear highlights
		card_selected.emit(null)

func start_reaction_request(attack_card: CardData, valid_cards: Array[CardData]) -> void:
	is_reaction_phase = true
	
	# 1. Afficher la carte adverse
	if opponent_card_display: opponent_card_display.queue_free()
	opponent_card_display = card_ui_scene.instantiate()
	add_child(opponent_card_display)
	opponent_card_display.setup(attack_card)
	# Positionner en haut au centre
	opponent_card_display.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	opponent_card_display.position.y += 20
	opponent_card_display.scale = Vector2(1.2, 1.2)
	
	# 2. Mettre en valeur la main
	for child in hand_container.get_children():
		if child is CardUI:
			var is_valid = false
			for valid in valid_cards:
				# Comparaison par titre (unique)
				if valid.title == child.card_data.title:
					is_valid = true
					break
			child.set_reaction_candidate(is_valid)
	
	# 3. UI Controls
	pass_button.show()
	reaction_timer.start()
	print("⚠️ REACTION PHASE STARTED - 3 Seconds!")

func _on_reaction_timeout() -> void:
	if is_reaction_phase:
		print("⌛ Reaction Timeout")
		_on_pass_button_pressed()

func _on_pass_button_pressed() -> void:
	_end_reaction_phase()
	reaction_skipped.emit()

func _end_reaction_phase() -> void:
	is_reaction_phase = false
	pass_button.hide()
	reaction_timer.stop()
	if opponent_card_display:
		opponent_card_display.queue_free()
		opponent_card_display = null
	
	# Reset hand visuals
	for child in hand_container.get_children():
		if child is CardUI:
			child.set_reaction_candidate(false)
			# On remet la couleur normale (car set_reaction_candidate(false) grise tout par défaut dans notre implémentation)
			child.modulate = child.base_color

func _on_card_discard_requested(card_ui: CardUI) -> void:
	card_discard_requested.emit(card_ui.card_data)

func show_game_over(winner_name: String) -> void:
	winner_label.text = winner_name + " WINS!"
	game_over_container.show()

func disable_restart_button() -> void:
	var restart_btn = $GameOverContainer/Panel/MarginContainer/VBoxContainer/RestartButton
	if restart_btn:
		restart_btn.disabled = true
		restart_btn.text = "OPPONENT LEFT"


# Met à jour les infos des joueurs (Hotseat : Actif en bas, Adversaire en haut)
func update_player_info(active: Wrestler, opponent: Wrestler) -> void:
	active_wrestler_ref = active
	opponent_wrestler_ref = opponent
	
	if bottom_player_info and active:
		bottom_player_info.setup(active.name, active.max_health)
		bottom_player_info.update_health(active.current_health, active.max_health)
	
	if top_player_info and opponent:
		top_player_info.setup(opponent.name, opponent.max_health)
		top_player_info.update_health(opponent.current_health, opponent.max_health)

# Callback appelé quand un catcheur change de PV
func on_wrestler_health_changed(current: int, max_hp: int, wrestler: Wrestler) -> void:
	if wrestler == active_wrestler_ref and bottom_player_info:
		bottom_player_info.update_health(current, max_hp)
	elif wrestler == opponent_wrestler_ref and top_player_info:
		top_player_info.update_health(current, max_hp)

func _on_card_drag_started(card_data: CardData) -> void:
	if game_manager_ref:
		game_manager_ref.set_wrestler_collisions(true)

func _on_card_drag_ended() -> void:
	if game_manager_ref:
		game_manager_ref.set_wrestler_collisions(false)

func _on_card_swipe_pending(card_ui: CardUI, offset: Vector2) -> void:
	if game_manager_ref:
		game_manager_ref.preview_swipe(card_ui.card_data, offset)

func _on_card_swipe_committed(card_ui: CardUI, offset: Vector2, global_pos: Vector2) -> void:
	if game_manager_ref:
		game_manager_ref.commit_swipe(card_ui.card_data, offset, global_pos)