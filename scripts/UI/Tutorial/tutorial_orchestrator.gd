class_name TutorialOrchestrator
extends Node

const TOOLTIP_SCENE = preload("res://scenes/UI/Tutorial/TutoTooltip.tscn")

@export var steps: Array[TutorialStep] = []

@export_group("Debug")
@export var debug_mode: bool = false

# Historique des tutos déjà vus
var _completed_steps: Array[String] = []

# Référence vers l'infobulle actuellement affichée (null si aucune)
var _current_tooltip: Node = null

# Références au jeu (à injecter depuis ton Arena)
var game_manager: Node = null
var ui_layer: Node = null

var _opponent_just_played: bool = false
var _player_just_drawn: bool = false
var _local_player_turn_count: int = 0
var _intro_finished: bool = false
var _waiting_for_action: bool = false
var _opponent_is_slapping: bool = false
var is_tutorial_enabled: bool = true

## Méthode d'initialisation appelée par Arena.gd
func setup(gm: Node, ui: Node) -> void:
	game_manager = gm
	ui_layer = ui
	
	# On s'abonne aux événements de GameManager pour réévaluer les tutos automatiquement
	if game_manager.has_signal("turn_started"):
		game_manager.turn_started.connect(_on_turn_started)
	if game_manager.has_signal("card_played_visual"):
		game_manager.card_played_visual.connect(_on_card_played)
	if game_manager.has_signal("card_drawn"):
		game_manager.card_drawn.connect(_on_card_drawn)
		
	# On déclenche le tuto descriptif de la carte au moment exact de l'impact (après le son)
	if ui_layer.has_signal("opponent_slap_impacted"):
		ui_layer.opponent_slap_impacted.connect(func():
			evaluate_tutorials()
		)
		
	# On attend la fin des animations visuelles (Slap) pour déclencher les tutos de réaction
	if ui_layer.has_signal("opponent_slap_finished"):
		ui_layer.opponent_slap_finished.connect(func():
			_opponent_is_slapping = false
			evaluate_tutorials()
		)
		
	# Si le jeu sort de pause (fin d'un menu ou tuto adverse), on vérifie si on a loupé un tuto
	if game_manager.has_signal("game_paused"):
		game_manager.game_paused.connect(func(is_paused: bool, _initiator: String):
			if not is_paused:
				get_tree().create_timer(0.1).timeout.connect(evaluate_tutorials)
		)

	# Charge la configuration de sauvegarde locale
	var config = ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		is_tutorial_enabled = config.get_value("game", "tutorial_enabled", true)

	# Évaluation initiale
	evaluate_tutorials()

## Fonction appelée par le jeu (quand on pioche, au début d'un tour, etc.)
func evaluate_tutorials() -> void:
	# On attend que le jeu ait réellement commencé (après le VersusScreen)
	if not is_instance_valid(game_manager) or not game_manager.is_game_active:
		return
		
	if not _intro_finished:
		return
		
	# Si le tutoriel est désactivé dans les options, on ignore.
	if not is_tutorial_enabled:
		return
		
	# On n'affiche rien si le jeu est DÉJÀ en pause globale (Menu, Aide, ou Adversaire en lecture...)
	if get_tree().paused:
		return
		
	# On attend que le joueur digère l'info s'il faut faire une pause entre deux tutos
	if _waiting_for_action:
		return
		
	# On n'affiche rien si un tuto est déjà en cours
	if _current_tooltip != null:
		return
		
	for step in steps:
		# Si déjà vu, on passe au suivant
		if _completed_steps.has(step.step_id):
			continue
			
		# Si les conditions ne sont pas remplies, on passe au suivant
		if not _are_conditions_met(step.trigger_conditions, step.step_id):
			continue
			
		# BINGO ! Toutes les conditions sont réunies, on lance ce tuto.
		_show_tutorial(step)
		break # On sort de la boucle, un seul tuto à la fois

## Appelée par l'Arène une fois l'animation de combat initiale (FIGHT!) terminée
func mark_intro_finished() -> void:
	_intro_finished = true
	evaluate_tutorials()

## Vérifie si TOUTES les conditions du dictionnaire sont remplies (avec logs)
func _are_conditions_met(conditions: Dictionary, step_id: String = "") -> bool:
	if conditions.is_empty():
		return true # Si pas de conditions, le tuto s'affiche par défaut (idéal pour le step_01)
		
	for key in conditions.keys():
		var expected_value = conditions[key]
		var actual_value = _check_single_condition(key)
		
		if actual_value != expected_value:
			if debug_mode:
				print("Tuto [", step_id, "] refusé : '", key, "' attendait ", expected_value, " mais a reçu ", actual_value)
			return false
			
	return true

func _on_turn_started(_player_name: String) -> void:
	if is_instance_valid(game_manager) and _player_name == game_manager._get_my_player_name():
		_local_player_turn_count += 1
		
	# On débloque l'attente à chaque changement de tour (pour ne pas bloquer les tutos du tour adverse)
	_waiting_for_action = false

	_opponent_just_played = false
	_player_just_drawn = false
	_opponent_is_slapping = false
	
	# On laisse un délai pour laisser le temps à la logique de pioche de se faire 
	# et à l'animation des cartes d'arriver en main avant de lancer un tuto.
	var tree = get_tree()
	if tree:
		tree.create_timer(0.6).timeout.connect(evaluate_tutorials)

func _on_card_played(player_name: String, _card: Resource, _is_use: bool) -> void:
	if player_name != game_manager._get_my_player_name():
		_opponent_just_played = true
		if _is_use:
			_opponent_is_slapping = true
			
		# Pour l'adversaire, on évalue la défausse de suite (pas d'impact visuel majeur)
		if not _is_use:
			evaluate_tutorials()
	else:
		# Le joueur local a fait une action (Jouer ou Défausser).
		# On lui laisse 1 seconde de répit pour admirer l'animation avant de relancer le tuto !
		var tree = get_tree()
		if tree:
			tree.create_timer(1.0).timeout.connect(func():
				_waiting_for_action = false
				evaluate_tutorials()
			)

func _on_card_drawn(_card: Resource) -> void:
	_player_just_drawn = true
	var tree = get_tree()
	if tree:
		tree.create_timer(0.6).timeout.connect(evaluate_tutorials)

## Le "Cerveau" : C'est ici qu'on fait le pont avec les vraies règles de ton jeu
func _check_single_condition(key: String) -> bool:
	if not is_instance_valid(game_manager):
		return false
		
	match key:
		"is_player_turn":
			if is_instance_valid(game_manager):
				var active_wrestler = game_manager.get_active_wrestler()
				if active_wrestler:
					# Compare précisément le perso actif avec notre "vrai" nom local
					return active_wrestler.name == game_manager._get_my_player_name()
			return false
			
		"has_move_card":
			# Cherche une carte "Noire" (Pique/Trèfle) dans la main complète du joueur
			return _has_card_matching(false, "black")
			
		"can_attack":
			# Cherche une carte "Rouge" (Cœur/Carreau) UNIQUEMENT parmi les cartes jouables
			return _has_card_matching(true, "red")
			
		"can_block":
			if _opponent_is_slapping:
				return false # On attend que la carte frappe la table avant de proposer le blocage
				
			# En mode réseau, seul l'attaquant attend la réaction. Le défenseur a juste un contexte.
			if not game_manager.pending_defense_context.is_empty():
				var ctx = game_manager.pending_defense_context
				var my_name = game_manager._get_my_player_name()
				var defender_id = ctx.get("target_id")
				
				var defender_name = ""
				for p_name in game_manager.player_peer_ids:
					if game_manager.player_peer_ids[p_name] == defender_id:
						defender_name = p_name
						break
						
				if defender_name == my_name or game_manager.enable_hotseat_mode:
					var attack_card = ctx.get("attack_card")
					# On cherche les cartes défensives dans la main du DÉFENSEUR
					var hand = game_manager.get_player_hand(defender_name)
					var valid_cards = game_manager.get_valid_reaction_cards(attack_card, hand)
					return valid_cards.size() > 0
			return false
			
		"opponent_has_played":
			return _opponent_just_played
			
		"is_start_of_game":
			return true # Sécurité générique pour les premiers tutos
			
		"is_first_turn":
			return _local_player_turn_count <= 1
			
		"just_drawn_card":
			return _player_just_drawn
			
		"has_attack_card":
			# Cherche une carte "Rouge" dans la main (même si on ne peut pas l'utiliser)
			return _has_card_matching(false, "red")
			
		_:
			push_warning("Tutorial - Trigger inconnu : ", key)
	return false


## Utilitaire pour scanner la main du joueur
func _has_card_matching(only_playable: bool, color_target: String) -> bool:
	var cards_to_check: Array = []
	
	if only_playable:
		if game_manager.has_method("get_playable_cards_in_hand"):
			cards_to_check = game_manager.get_playable_cards_in_hand()
	else:
		if game_manager.has_method("_get_my_player_name") and game_manager.has_method("get_player_hand"):
			var my_name = game_manager._get_my_player_name()
			cards_to_check = game_manager.get_player_hand(my_name)
			
	# On vérifie la couleur des cartes
	for card in cards_to_check:
		var suit = card.get("suit") # Exemple: "Spades", "Hearts", etc.
		if color_target == "red" and (suit == "Hearts" or suit == "Diamonds"):
			return true
		if color_target == "black" and (suit == "Spades" or suit == "Clubs"):
			return true
			
	return false


## Affiche l'infobulle
func _show_tutorial(step: TutorialStep) -> void:
	_completed_steps.append(step.step_id)
	
	_current_tooltip = TOOLTIP_SCENE.instantiate()
	
	if is_instance_valid(ui_layer):
		ui_layer.add_child(_current_tooltip) # On le place DANS l'UI pour pouvoir cliquer dessus !
	else:
		add_child(_current_tooltip)
	
	var target_node: Node = null
	
	# Recherche de l'élément UI à cibler pour positionner l'infobulle
	if is_instance_valid(ui_layer) and not step.target_ui_names.is_empty():
		for target_name in step.target_ui_names:
			target_node = ui_layer.find_child(target_name, true, false)
			if target_node:
				break
	
	# On donne les infos à l'infobulle avec la bonne méthode
	_current_tooltip.display_tooltip(
		step.step_id,
		step.text_key,
		target_node,
		step.pauses_game,
		step.media_textures,
		step.video_stream
	)
	
	# Écoute du bouton SKIP pour désactiver le tutoriel
	_current_tooltip.tutorial_skipped.connect(func():
		set_tutorial_enabled(false, false)
	)
	
	# Met le jeu en pause si l'étape l'exige
	if step.pauses_game:
		if is_instance_valid(game_manager) and game_manager.has_method("request_pause"):
			game_manager.request_pause(true)
		else:
			get_tree().paused = true
	
	# Si l'infobulle est fermée par le joueur, on nettoie notre référence
	_current_tooltip.tree_exited.connect(func():
		_current_tooltip = null
		var tree = get_tree()
		if tree:
			# On enlève la pause (au cas où elle était active)
			if step.pauses_game:
				if is_instance_valid(game_manager) and game_manager.has_method("request_pause"):
					game_manager.request_pause(false)
				else:
					tree.paused = false
			
			# Faut-il laisser le joueur respirer avant le prochain tuto ?
			if step.get("wait_for_action_after") == true:
				_waiting_for_action = true
			else:
				tree.create_timer(0.1).timeout.connect(evaluate_tutorials)
	)

func set_tutorial_enabled(enabled: bool, force_close: bool = true) -> void:
	is_tutorial_enabled = enabled
	var config = ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("game", "tutorial_enabled", enabled)
	config.save("user://settings.cfg")
	
	if not enabled and force_close:
		if is_instance_valid(_current_tooltip) and _current_tooltip.has_method("_close_tooltip"):
			_current_tooltip._close_tooltip()
