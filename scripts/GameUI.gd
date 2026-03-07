class_name GameUI
extends CanvasLayer

signal card_selected(card_data: CardData)
signal card_dropped_on_world(card_data: CardData, screen_position: Vector2)
signal end_turn_pressed
signal reaction_selected(card_data: CardData)
signal reaction_skipped

@export var top_player_info: PlayerInfo
@export var bottom_player_info: PlayerInfo

const VERSUS_SCREEN_SCENE = preload("res://scenes/UI/VersusScreen.tscn")
const OPTION_TUTO_LAYER_SCENE = preload("res://scenes/UI/Tuto_layer.tscn")
const OPTIONS_LAYER_SCENE = preload("res://scenes/UI/OptionsLayer.tscn")

var local_wrestler_ref: Wrestler
var remote_wrestler_ref: Wrestler

@export var card_ui_scene: PackedScene
@export var opponent_hand_container: HBoxContainer
@export var smoke_puff_scene: PackedScene
@export var slap_sound: AudioStream
@onready var hand_container: HBoxContainer = $PanelContainer/HandContainer
@onready var slap_anchor: Control = $SlapAnchor
@onready var opponent_slap_anchor: Control = $OpponentSlapAnchor
@onready var game_over_container: CenterContainer = $GameOverContainer
@onready var winner_label: Label = $GameOverContainer/ChalkPanel/MarginContainer/VBoxContainer/WinnerLabel
@onready var slap_sound_player: UISoundComponent = $SlapSoundPlayer
@onready var help_button: Button = %HelpButton
@onready var options_button: Button = %OptionsButton

@onready var turn_label: Label = $TurnInfoContainer/VBoxContainer/TurnLabel

var selected_card_ui: CardUI

# Reaction UI Elements
var current_versus_screen: Control
var reaction_timer: Timer
var pass_button: Button
var opponent_card_display: CardUI
var is_reaction_phase: bool = false
var tuto_layer_instance: CanvasLayer
var options_layer_instance: Control

# Drop Zone for Push mechanic
@onready var end_turn_button = $EndTurnButton
var drop_zone: DropZone

# Discard Zone Visual (Red strip at bottom)
@onready var discard_zone_visual: ColorRect = $DiscardZone

const CARD_BACK_TEXTURE = preload("res://assets/Cards/card_back.png")
const CHALK_TIC_SOUND = preload("res://assets/Sounds/UI/chalk_tic.wav")
const ARROW_TEXTURE = preload("res://assets/UI/Icons/Arrow.png")

# Drag Feedback Colors
const COLOR_ARROW_INACTIVE = Color(0.6, 0.6, 0.6, 0.8) # Gris transparent
const COLOR_ARROW_ATTACK = Color("#a22633") # Rouge
const COLOR_ARROW_MOVE = Color("#262b44") # Noir/Bleu

var drag_arrows_root: Control
var drag_arrows: Dictionary = {} # {Vector2.UP: Polygon2D, ...}

var game_manager_ref

func _ready() -> void:
	# Force la visibilité (au cas où décoché dans l'éditeur) et cache l'écran de fin
	visible = true
	game_over_container.hide()
	
	# Connect restart button manually since we added it via code/tscn edit
	var restart_btn = $GameOverContainer/ChalkPanel/MarginContainer/VBoxContainer/RestartButtonPanel/RestartButton
	restart_btn.pressed.connect(_on_restart_button_pressed)
	_setup_button_feedback(restart_btn)
	
	# Connect quit button manually
	var quit_btn = $GameOverContainer/ChalkPanel/MarginContainer/VBoxContainer/QuitButtonPanel/QuitButton
	quit_btn.pressed.connect(_on_quit_button_pressed)
	_setup_button_feedback(quit_btn)
	
	# Connect CTA button manually
	var cta_btn = $GameOverContainer/ChalkPanel/MarginContainer/VBoxContainer/TextureButton
	if cta_btn:
		cta_btn.pressed.connect(_on_cta_button_pressed)
	
	# Connect help button
	if help_button:
		help_button.pressed.connect(_on_help_button_pressed)
		_setup_button_feedback(help_button)
	
	# Connect options button
	if options_button:
		options_button.pressed.connect(_on_options_button_pressed)
		_setup_button_feedback(options_button)
	
	# Connect end turn button manually
	end_turn_button.end_turn_pressed.connect(_on_end_turn_button_pressed)
	
	if hand_container:
		hand_container.alignment = BoxContainer.ALIGNMENT_CENTER
	
	# Connexion dynamique au GameManager
	# On cherche le GameManager dans la scène (il devrait être un frère ou un parent)
	var game_manager = get_tree().root.find_child("GameManager", true, false)
	game_manager_ref = game_manager
	if game_manager:
		if not game_manager.card_drawn.is_connected(add_card_to_hand):
			game_manager.card_drawn.connect(add_card_to_hand)
		if not game_manager.card_discarded.is_connected(remove_card_from_hand):
			game_manager.card_discarded.connect(remove_card_from_hand)
		if not game_manager.game_restarted.is_connected(_on_game_restarted):
			game_manager.game_restarted.connect(_on_game_restarted)
		if not game_manager.rematch_update.is_connected(_on_rematch_update):
			game_manager.rematch_update.connect(_on_rematch_update)
		if not game_manager.versus_screen_requested.is_connected(_on_versus_screen_requested):
			game_manager.versus_screen_requested.connect(_on_versus_screen_requested)
		if not game_manager.opponent_skipped_versus.is_connected(_on_opponent_skipped_versus):
			game_manager.opponent_skipped_versus.connect(_on_opponent_skipped_versus)
		if not game_manager.player_hand_counts_updated.is_connected(_on_player_hand_counts_updated):
			game_manager.player_hand_counts_updated.connect(_on_player_hand_counts_updated)
		if not game_manager.card_played_visual.is_connected(_on_card_played_visual):
			game_manager.card_played_visual.connect(_on_card_played_visual)
	else:
		printerr("GameUI: GameManager not found!")
	
	# Setup Drop Zone for Drag & Drop (Push)
	drop_zone = DropZone.new()
	add_child(drop_zone)
	move_child(drop_zone, 0) # Ensure it's behind everything else
	drop_zone.card_dropped.connect(_on_card_dropped_on_zone)
	
	# Instantiate Option/Tuto Layer
	tuto_layer_instance = OPTION_TUTO_LAYER_SCENE.instantiate()
	add_child(tuto_layer_instance)
	
	# Instantiate Options Layer
	options_layer_instance = OPTIONS_LAYER_SCENE.instantiate()
	add_child(options_layer_instance)
	options_layer_instance.hide()
	
	_setup_reaction_ui()
	_setup_drag_feedback()

func _on_help_button_pressed() -> void:
	if tuto_layer_instance and tuto_layer_instance.has_method("open_tutorial"):
		tuto_layer_instance.open_tutorial()

func _on_options_button_pressed() -> void:
	if options_layer_instance:
		options_layer_instance.show()

func _start_help_button_pulse() -> void:
	var rules_hint = $TopRightContainer/RulesHintPanel
	if not help_button: return
	
	# Ensure pivot is centered
	help_button.pivot_offset = help_button.size / 2
	
	var tween = create_tween()
	tween.set_loops(4) # 4 seconds total (0.5s * 2 * 4)
	
	# Up: Scale 1.2, Red
	tween.tween_property(help_button, "scale", Vector2(1.2, 1.2), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(help_button, "modulate", Color(1, 0.2, 0.2), 0.5)
	
	# Down: Scale 1.0, White
	tween.tween_property(help_button, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(help_button, "modulate", Color.WHITE, 0.5)
	
	tween.finished.connect(func():
		if rules_hint:
			rules_hint.hide()
	)

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

func _setup_drag_feedback() -> void:
	# Création d'un conteneur pour les flèches
	drag_arrows_root = Control.new()
	drag_arrows_root.name = "DragArrowsOverlay"
	drag_arrows_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_arrows_root.z_index = 100 # Au dessus des cartes
	drag_arrows_root.hide()
	add_child(drag_arrows_root)
	
	# Définition des directions (Ortho + Diag)
	var directions = {
		# Orthogonal
		Vector2.UP: - 90,
		Vector2.RIGHT: 0,
		Vector2.DOWN: 90,
		Vector2.LEFT: 180,
		# Diagonal
		Vector2(1, -1): - 45, # Haut-Droite
		Vector2(1, 1): 45, # Bas-Droite
		Vector2(-1, 1): 135, # Bas-Gauche
		Vector2(-1, -1): - 135 # Haut-Gauche
	}
	
	# Création des polygones (Triangles)
	var offset_dist = 50.0 # Distance par rapport au centre de la carte
	var tex_size = ARROW_TEXTURE.get_size()
	
	for dir in directions:
		var arrow = TextureRect.new()
		arrow.texture = ARROW_TEXTURE
		arrow.modulate = COLOR_ARROW_INACTIVE
		arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		arrow.size = tex_size
		arrow.pivot_offset = tex_size / 2.0
		arrow.scale = Vector2(0.5, 0.5) # Réduction de 50%

		# Distance augmentée de 50% pour les diagonales
		var current_offset = offset_dist
		if dir.x != 0 and dir.y != 0:
			current_offset = offset_dist * 1.5

		# Positionnement et Rotation
		arrow.position = (dir.normalized() * current_offset) - (tex_size / 2.0)
		arrow.rotation_degrees = directions[dir]
		
		drag_arrows_root.add_child(arrow)
		drag_arrows[dir] = arrow

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
	if game_manager_ref:
		game_manager_ref.request_restart()
		# Visual feedback
		var btn = $GameOverContainer/ChalkPanel/MarginContainer/VBoxContainer/RestartButtonPanel/RestartButton
		if btn:
			btn.disabled = true
			btn.text = "WAITING FOR OPPONENT..."

func _on_quit_button_pressed() -> void:
	# Return to lobby properly closing connection
	NetworkManager.return_to_lobby()

func _on_cta_button_pressed() -> void:
	OS.shell_open("https://trankil.itch.io/folklore-on-tap")

func update_turn_info(player_name: String, skip_anim: bool = false) -> void:
	var is_my_turn = false
	if game_manager_ref:
		is_my_turn = game_manager_ref.is_local_player_active()
	
	turn_label.text = "YOUR TURN" if is_my_turn else "OPPONENT'S TURN"
	end_turn_button.set_player_turn(is_my_turn, skip_anim)
	_update_discard_zone_visibility()

func _on_game_restarted() -> void:
	game_over_container.hide()
	clear_hand()
	# The scene is reloaded on restart, so UI state is reset automatically.

func _on_rematch_update(current: int, total: int) -> void:
	# Si l'adversaire a voté avant nous, on peut afficher un message
	var btn = $GameOverContainer/ChalkPanel/MarginContainer/VBoxContainer/RestartButtonPanel/RestartButton
	if btn and not btn.disabled:
		btn.text = "OPPONENT WANTS REMATCH!"

func _on_card_dropped_on_zone(card_data: CardData, pos: Vector2) -> void:
	card_dropped_on_world.emit(card_data, pos)

func add_card_to_hand(card_data: CardData) -> void:
	if not card_ui_scene:
		printerr("GameUI: card_ui_scene is not assigned!")
		return

	print("DEBUG UI: Adding card ", card_data.title, " to hand.")
	var card = card_ui_scene.instantiate()
	
	# Wrap in CenterContainer to isolate scale transformations from HBoxContainer layout
	var wrapper = CenterContainer.new()
	wrapper.custom_minimum_size = Vector2(120, 120) # Force size for HBoxContainer
	wrapper.mouse_filter = Control.MOUSE_FILTER_PASS
	hand_container.add_child(wrapper)
	wrapper.add_child(card)
	
	# Ensure wrapper is cleaned up when card is destroyed (e.g. after animation)
	card.tree_exited.connect(func(): if is_instance_valid(wrapper): wrapper.queue_free())
	
	card.setup(card_data)
	card.clicked.connect(_on_card_clicked)
	# On bind 'card' pour récupérer l'instance UI lors du drag start
	card.drag_started.connect(_on_card_drag_started.bind(card))
	card.drag_ended.connect(_on_card_drag_ended)
	card.swipe_pending.connect(_on_card_swipe_pending)
	card.swipe_committed.connect(_on_card_swipe_committed)
	card.selection_canceled.connect(_on_card_selection_canceled)

func remove_card_from_hand(card_data: CardData) -> void:
	for wrapper in hand_container.get_children():
		var child = wrapper.get_child(0) if wrapper.get_child_count() > 0 else null
		# Comparaison par valeur (car les instances diffèrent via RPC)
		if child is CardUI and child.card_data.title == card_data.title and \
		   child.card_data.value == card_data.value and child.card_data.suit == card_data.suit:
			# Si la carte est déjà en train de se détruire (animation locale), on la laisse finir
			if not child.is_destroying:
				wrapper.queue_free()
				
				if selected_card_ui == child:
					selected_card_ui = null
				break

func clear_hand() -> void:
	for child in hand_container.get_children():
		child.queue_free()
	selected_card_ui = null

func update_opponent_hand_visuals(count: int) -> void:
	if not opponent_hand_container: return
	
	# Vider la main actuelle
	for child in opponent_hand_container.get_children():
		child.queue_free()
	
	# Remplir avec des dos de cartes
	for i in range(count):
		var card_back = TextureRect.new()
		card_back.texture = CARD_BACK_TEXTURE
		card_back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card_back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card_back.custom_minimum_size = Vector2(120, 120) # Même taille de base que CardUI
		opponent_hand_container.add_child(card_back)

func _on_player_hand_counts_updated(counts: Dictionary) -> void:
	if remote_wrestler_ref and counts.has(remote_wrestler_ref.name):
		update_opponent_hand_visuals(counts[remote_wrestler_ref.name])

func _on_card_played_visual(player_name: String, card_data: CardData, is_use: bool) -> void:
	# On ignore nos propres actions (déjà animées par le drag & drop)
	# On ignore aussi en Hotseat car les deux joueurs partagent la main du bas
	if not game_manager_ref or game_manager_ref.enable_hotseat_mode: return
	if player_name == game_manager_ref._get_my_player_name(): return
	
	if is_use:
		_animate_opponent_slap(card_data)
	else:
		# TODO: Animation de défausse adverse (fade out simple ?)
		pass

func _animate_opponent_slap(card_data: CardData) -> void:
	if not card_ui_scene: return
	
	var card = card_ui_scene.instantiate()
	add_child(card)
	card.setup(card_data)
	
	# Position de départ : Centre de la main adverse (Haut de l'écran)
	var start_pos = Vector2.ZERO
	if opponent_hand_container:
		start_pos = opponent_hand_container.global_position + (opponent_hand_container.size / 2.0) - (card.size / 2.0)
	card.global_position = start_pos
	
	# Cible : OpponentSlapAnchor (Haut du ring)
	var target_pos = opponent_slap_anchor.global_position if opponent_slap_anchor else (get_viewport().get_visible_rect().size / 2.0)
	
	# Effets d'impact (Même logique que le joueur)
	var is_attack_card = (card_data.type == CardData.CardType.ATTACK)
	
	card.impact_occurred.connect(func():
		if smoke_puff_scene:
			var puff = smoke_puff_scene.instantiate()
			add_child(puff)
			puff.z_index = 10
			puff.setup(target_pos)
			if is_attack_card:
				puff.modulate = Color(1.0, 0.8, 0.8)
		
		if slap_sound_player and slap_sound:
			slap_sound_player.play_varied(slap_sound)
		
		_trigger_screen_shake()
	)
	
	card.animate_slap(target_pos)

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
	if game_manager_ref:
		game_manager_ref.set_wrestler_collisions(false)
	
	if drag_arrows_root:
		drag_arrows_root.hide()
	
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
	for wrapper in hand_container.get_children():
		var child = wrapper.get_child(0) if wrapper.get_child_count() > 0 else null
		if child is CardUI:
			var is_valid = false
			for valid in valid_cards:
				# Comparaison par titre (unique)
				if valid.title == child.card_data.title:
					is_valid = true
					break
			child.set_reaction_candidate(is_valid)
			child.set_playable(is_valid) # Assure que les non-candidates soient grisées/réduites
	
	# 3. UI Controls
	pass_button.show()
	reaction_timer.start()
	print("⚠️ REACTION PHASE STARTED - 3 Seconds!")

func _on_reaction_timeout() -> void:
	if is_reaction_phase:
		print("⌛ Reaction Timeout")
		_on_pass_button_pressed()

func _on_pass_button_pressed() -> void:
	if not is_reaction_phase: return
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
	for wrapper in hand_container.get_children():
		var child = wrapper.get_child(0) if wrapper.get_child_count() > 0 else null
		if child is CardUI:
			child.set_reaction_candidate(false)

func update_cards_playability(playable_cards: Array[CardData]) -> void:
	var playable_keys = []
	for card in playable_cards:
		playable_keys.append(card.title + "_" + card.suit)

	for wrapper in hand_container.get_children():
		var card_ui = wrapper.get_child(0) if wrapper.get_child_count() > 0 else null
		if card_ui is CardUI:
			var key = card_ui.card_data.title + "_" + card_ui.card_data.suit
			var is_playable = key in playable_keys
			
			card_ui.set_playable(is_playable)

func show_game_over(winner_name: String) -> void:
	if winner_name == "DRAW":
		winner_label.text = "IT'S A DRAW!"
	else:
		winner_label.text = winner_name + " WINS!"
	game_over_container.show()

func disable_restart_button() -> void:
	var restart_btn = $GameOverContainer/ChalkPanel/MarginContainer/VBoxContainer/RestartButtonPanel/RestartButton
	if restart_btn:
		restart_btn.disabled = true
		restart_btn.text = "OPPONENT LEFT"


# Met à jour les infos des joueurs (Hotseat : Actif en bas, Adversaire en haut)
func set_player_perspectives(local_player: Wrestler, remote_player: Wrestler) -> void:
	local_wrestler_ref = local_player
	remote_wrestler_ref = remote_player
	
	if bottom_player_info and local_player:
		bottom_player_info.setup(local_player.wrestler_data)
		bottom_player_info.update_health(local_player.current_health, local_player.max_health)
	
	if top_player_info and remote_player:
		top_player_info.setup(remote_player.wrestler_data)
		top_player_info.update_health(remote_player.current_health, remote_player.max_health)
		
		# Force update hand visuals if counts exist (in case of reconnect/reload)
		if game_manager_ref and game_manager_ref.player_hand_counts.has(remote_player.name):
			update_opponent_hand_visuals(game_manager_ref.player_hand_counts[remote_player.name])

# Callback appelé quand un catcheur change de PV
func on_wrestler_health_changed(current: int, max_hp: int, wrestler: Wrestler) -> void:
	if wrestler == local_wrestler_ref and bottom_player_info:
		bottom_player_info.update_health(current, max_hp)
	elif wrestler == remote_wrestler_ref and top_player_info:
		top_player_info.update_health(current, max_hp)
	# Fallback: Name match (Robustness against reference mismatch)
	elif local_wrestler_ref and wrestler.name == local_wrestler_ref.name and bottom_player_info:
		bottom_player_info.update_health(current, max_hp)
	elif remote_wrestler_ref and wrestler.name == remote_wrestler_ref.name and top_player_info:
		top_player_info.update_health(current, max_hp)

func _on_card_drag_started(card_data: CardData, card_ui: CardUI = null) -> void:
	if game_manager_ref:
		game_manager_ref.set_wrestler_collisions(true)
	
	# Affichage des flèches autour de la position d'origine
	if card_ui and drag_arrows_root:
		# Pas de flèches pour les attaques (cartes rouges), sauf si c'est un Joker
		if card_data.type == CardData.CardType.ATTACK and card_data.suit != "Joker":
			return
		
		# Les flèches sont positionnées sur la carte elle-même
		drag_arrows_root.global_position = card_ui.get_global_rect().get_center()
		
		# Reset des couleurs et visibilité selon le pattern
		var is_joker = (card_data.suit == "Joker")
		var is_diagonal = (card_data.pattern == CardData.MovePattern.DIAGONAL)
		
		for dir in drag_arrows:
			var arrow = drag_arrows[dir]
			arrow.modulate = COLOR_ARROW_INACTIVE
			
			if is_joker:
				arrow.visible = true
			else:
				# On affiche seulement les flèches correspondantes au pattern
				var is_arrow_diag = (dir.x != 0 and dir.y != 0)
				arrow.visible = (is_diagonal == is_arrow_diag)
		
		drag_arrows_root.show()

func _on_card_drag_ended() -> void:
	if game_manager_ref:
		game_manager_ref.set_wrestler_collisions(false)
	
	if drag_arrows_root:
		drag_arrows_root.hide()

func _on_card_swipe_pending(card_ui: CardUI, offset: Vector2) -> void:
	# Check Discard Zone Hover
	if discard_zone_visual and discard_zone_visual.visible:
		var card_center = card_ui.get_global_rect().get_center()
		if discard_zone_visual.get_global_rect().has_point(card_center):
			card_ui.set_discard_hover_state(true)
		else:
			card_ui.set_discard_hover_state(false)

	var is_push_hovering = false
	if game_manager_ref:
		is_push_hovering = game_manager_ref.preview_swipe(card_ui.card_data, offset)
	
	# Met à jour la visibilité de l'icône "kick" sur la carte
	card_ui.set_push_hover_state(is_push_hovering)
	
	# Mise à jour des flèches directionnelles
	if drag_arrows_root and drag_arrows_root.visible:
		# Faire suivre les flèches à la carte
		drag_arrows_root.global_position = card_ui.get_global_rect().get_center()
		
		var active_color = COLOR_ARROW_ATTACK if card_ui.card_data.type == CardData.CardType.ATTACK else COLOR_ARROW_MOVE
		var threshold = 20.0 # Seuil de détection
		
		# Reset rapide
		for arrow in drag_arrows.values():
			if arrow.visible:
				arrow.modulate = COLOR_ARROW_INACTIVE
			
		if offset.length() > threshold:
			var is_joker = (card_ui.card_data.suit == "Joker")
			var is_diagonal = (card_ui.card_data.pattern == CardData.MovePattern.DIAGONAL)
			
			if is_joker:
				# Logique Joker (8 directions)
				var best_dir = Vector2.ZERO
				var max_dot = -2.0
				var normalized_offset = offset.normalized()
				
				for dir in drag_arrows:
					var dot = normalized_offset.dot(dir.normalized())
					if dot > max_dot:
						max_dot = dot
						best_dir = dir
				
				if best_dir != Vector2.ZERO and drag_arrows.has(best_dir):
					drag_arrows[best_dir].modulate = active_color
			elif is_diagonal:
				# Logique Diagonale
				var dir_x = 1 if offset.x > 0 else -1
				var dir_y = 1 if offset.y > 0 else -1
				var key = Vector2(dir_x, dir_y)
				if drag_arrows.has(key):
					drag_arrows[key].modulate = active_color
			else:
				# Logique Orthogonale
				var abs_x = abs(offset.x)
				var abs_y = abs(offset.y)
				
				if abs_x > abs_y:
					# Horizontal
					drag_arrows[Vector2.RIGHT if offset.x > 0 else Vector2.LEFT].modulate = active_color
				else:
					# Vertical
					drag_arrows[Vector2.DOWN if offset.y > 0 else Vector2.UP].modulate = active_color

func _on_card_swipe_committed(card_ui: CardUI, offset: Vector2, global_pos: Vector2) -> void:
	# Check Discard Zone
	if discard_zone_visual and discard_zone_visual.visible and discard_zone_visual.get_global_rect().has_point(global_pos):
		card_ui.animate_destruction()
		if game_manager_ref:
			game_manager_ref.discard_hand_card(card_ui.card_data)
		if drag_arrows_root: drag_arrows_root.hide()
		return
	
	# Stop shake if dropped elsewhere
	card_ui.set_discard_hover_state(false)

	if game_manager_ref:
		# Prevent premature destruction by remove_card_from_hand signal
		card_ui.is_destroying = true
		
		if drag_arrows_root: drag_arrows_root.hide()
		
		if game_manager_ref.commit_swipe(card_ui.card_data, offset, global_pos):
			# Positionner sur le SlapAnchor (centre bas de l'écran)
			var target_pos = slap_anchor.global_position if slap_anchor else (card_ui.global_position + (card_ui.size / 2.0))
			
			# Capture data needed for the lambda to avoid accessing potentially freed card_ui
			var is_attack_card = (card_ui.card_data.type == CardData.CardType.ATTACK)
			
			# Connect to impact signal for sync
			card_ui.impact_occurred.connect(func():
				if smoke_puff_scene:
					var puff = smoke_puff_scene.instantiate()
					add_child(puff)
					puff.z_index = 10 # Ensure it's below the card (Z=20)
					puff.setup(target_pos)
					if is_attack_card:
						puff.modulate = Color(1.0, 0.8, 0.8)
				
				if slap_sound_player and slap_sound:
					slap_sound_player.play_varied(slap_sound)
				
				_trigger_screen_shake()
			)
			
			# --- SLAP EFFECT ---
			# Start animation
			card_ui.animate_slap(target_pos)
		else:
			# Revert flag if action failed
			card_ui.is_destroying = false
			if drag_arrows_root: drag_arrows_root.hide()

func _trigger_screen_shake() -> void:
	var tween = create_tween()
	# Secousse rapide de l'interface (CanvasLayer offset)
	var intensity = 10.0
	for i in range(5):
		var rand_offset = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
		tween.tween_property(self , "offset", rand_offset, 0.05)
		intensity *= 0.8 # Amortissement
	
	# Retour à la normale
	tween.tween_property(self , "offset", Vector2.ZERO, 0.05)

func _update_discard_zone_visibility() -> void:
	if discard_zone_visual and game_manager_ref:
		discard_zone_visual.visible = game_manager_ref.is_local_player_active()

func _on_versus_screen_requested(local_data: WrestlerData, remote_data: WrestlerData) -> void:
	if current_versus_screen:
		current_versus_screen.queue_free()
	
	if tuto_layer_instance:
		tuto_layer_instance.hide()
	
	# Masquer l'arène 3D (le parent) pour éviter le "flash" visuel avant l'écran Versus
	if get_parent() is Node3D:
		get_parent().visible = false
	
	current_versus_screen = VERSUS_SCREEN_SCENE.instantiate()
	add_child(current_versus_screen)
	current_versus_screen.setup(local_data, remote_data)
	
	current_versus_screen.skip_pressed.connect(func():
		if game_manager_ref: game_manager_ref.send_skip_versus()
	)
	current_versus_screen.finished.connect(_on_versus_screen_finished)

func _on_opponent_skipped_versus() -> void:
	if current_versus_screen and current_versus_screen.has_method("set_opponent_skipped"):
		current_versus_screen.set_opponent_skipped()

func _on_versus_screen_finished() -> void:
	if current_versus_screen:
		current_versus_screen.queue_free()
		current_versus_screen = null
	
	# Réafficher l'arène 3D maintenant que le Versus est terminé
	if get_parent() is Node3D:
		get_parent().visible = true
	
	if tuto_layer_instance:
		tuto_layer_instance.show()
	
	if game_manager_ref:
		game_manager_ref.start_match_after_versus()
		
		# Force initial UI update (without animation) to ensure correct state for non-starting players
		if not game_manager_ref.players.is_empty():
			var current_player_name = game_manager_ref.players[game_manager_ref.active_player_index].name
			update_turn_info(current_player_name, true)
	
	# On lance l'animation du bouton d'aide maintenant que le combat commence vraiment
	_start_help_button_pulse()

func _setup_button_feedback(btn: Button) -> void:
	if not btn: return
	
	# On centre le pivot pour que le scale se fasse depuis le milieu
	# On le fait au démarrage et à chaque redimensionnement
	btn.pivot_offset = btn.size / 2
	btn.resized.connect(func(): btn.pivot_offset = btn.size / 2)
	
	# Effet d'enfoncement (Squash)
	btn.button_down.connect(func():
		btn.pivot_offset = btn.size / 2
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(btn, "scale", Vector2(0.95, 0.95), 0.1)
		if slap_sound_player: slap_sound_player.play_varied(CHALK_TIC_SOUND)
	)
	
	# Effet de relâchement avec rebond (Stretch & Bounce)
	btn.button_up.connect(func():
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.3).from(Vector2(1.05, 1.05))
	)
