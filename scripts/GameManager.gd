class_name GameManager
extends Node

signal turn_started(player_name: String)
signal card_drawn(card: CardData)
signal card_discarded(card: CardData)
signal turn_ended
signal reaction_phase_started(attack_card: CardData, valid_cards: Array[CardData])
signal grid_action_received(data: Dictionary)
signal game_restarted
signal rematch_update(current_votes: int, total_required: int)
signal refresh_hand_requested(player_name: String)
signal game_over(winner_name: String)
signal game_paused(paused: bool, initiator_name: String)
signal versus_screen_requested(local_data: WrestlerData, remote_data: WrestlerData)
signal opponent_skipped_versus
signal player_hand_counts_updated(counts: Dictionary)
signal card_played_visual(player_name: String, card: CardData, is_use: bool)

@export var hand_size_limit: int = 5
@export var cards_drawn_per_turn: int = 2
@export var character_pool: Array[WrestlerData]
@export var enable_hotseat_mode: bool = false
@export var can_dodge: bool = false

var deck_manager: DeckManager

var players: Array[Wrestler] = []
# Dictionary to store hand for each player: { player_name: [CardData] }
var player_hands: Dictionary = {}
var player_hand_counts: Dictionary = {} # { player_name: int } - Track hand size for UI sync
var active_player_index: int = 0
var is_game_active: bool = false

# Reference to GridManager (injected by Arena)
var grid_manager

# Mapping des noms de joueurs vers les IDs réseau (Peer ID)
var player_peer_ids: Dictionary = {}

# Flag pour éviter les boucles infinies de signaux (Network -> Local -> Network)
var is_network_syncing: bool = false

# Context pour stocker l'attaque en cours côté attaquant
var pending_attack_context: Dictionary = {}
var pending_defense_context: Dictionary = {}
var is_waiting_for_reaction: bool = false
var has_acted_this_turn: bool = false
var rematch_votes: Dictionary = {}

func _ready() -> void:
	# Listen for network messages
	NetworkManager.game_message_received.connect(_on_network_message)

func is_in_hotseat_mode() -> bool:
	return enable_hotseat_mode

func initialize_network(deck_mgr: DeckManager) -> void:
	deck_manager = deck_mgr
	
	if enable_hotseat_mode:
		_setup_hotseat_game()
	else:
		_setup_network_game()

func _setup_hotseat_game() -> void:
	print("--- LAUNCHING IN HOTSEAT MODE ---")
	player_peer_ids.clear()
	player_peer_ids["Player 1"] = "hotseat_p1"
	player_peer_ids["Player 2"] = "hotseat_p2"
	
	# In hotseat, we are always the host.
	_server_select_and_sync_characters()

func _setup_network_game() -> void:
		# Configuration des IDs réseau
		player_peer_ids.clear()
		
		# Logique P2P Déterministe : On récupère tous les IDs et on les trie.
		# Tout le monde aura la même liste triée, donc tout le monde sera d'accord sur qui est J1 et J2.
		var all_ids = [NetworkManager.self_user_id]
		for uid in NetworkManager.match_presences:
			all_ids.append(uid)
		all_ids.sort()
		
		# Assignation : Le plus petit ID est le Joueur 1 (Pseudo-Host)
		if all_ids.size() > 0: player_peer_ids["Player 1"] = all_ids[0]
		if all_ids.size() > 1: player_peer_ids["Player 2"] = all_ids[1]
		else: player_peer_ids["Player 2"] = all_ids[0] # Fallback Solo/Debug

		# Est-ce que je suis le "Pseudo-Host" (Joueur 1) ?
		var am_i_host = (NetworkManager.self_user_id == player_peer_ids["Player 1"])

		# Le Host choisit les personnages et le notifie
		if am_i_host:
			# FIX: Petit délai pour laisser le temps aux clients de recharger leur scène avant de recevoir la synchro
			get_tree().create_timer(1.0).timeout.connect(_server_select_and_sync_characters)

func initialize_game_state() -> void:
	if not grid_manager or grid_manager.wrestlers.is_empty():
		printerr("Cannot initialize game state: wrestlers not spawned yet.")
		return

	players = grid_manager.wrestlers
	active_player_index = 0 # Player 1 starts
	is_game_active = true
	player_hand_counts.clear()
	
	# Est-ce que je suis le "Pseudo-Host" (Joueur 1) ?
	var am_i_host = false
	if enable_hotseat_mode:
		am_i_host = true
	elif not players.is_empty():
		var p1_name = players[0].name
		if player_peer_ids.has(p1_name):
			am_i_host = (NetworkManager.self_user_id == player_peer_ids[p1_name])

	if am_i_host:
		# Le "Host" gère le deck et la distribution
		deck_manager.initialize_deck()
		
		# Initial setup: Fill hands to limit for all players
		for player in players:
			_draw_up_to_limit(player.name)
			
		_start_turn()

func _server_select_and_sync_characters():
	if character_pool.size() < 2:
		printerr("Character pool needs at least 2 characters!")
		return

	character_pool.shuffle()
	var p1_data = character_pool[0]
	var p2_data = character_pool[1]

	# We need to send resource paths, not the objects themselves
	var p1_path = p1_data.resource_path
	var p2_path = p2_data.resource_path

	if enable_hotseat_mode:
		# Apply locally
		_handle_character_selection(p1_path, p2_path)
	else:
		# Sync with others
		NetworkManager.send_message({
			"type": "SYNC_CHARACTERS",
			"p1_path": p1_path,
			"p2_path": p2_path
		})
		# Apply locally for the host
		_handle_character_selection(p1_path, p2_path)

func _start_turn() -> void:
	var current_player = players[active_player_index]
	print("Turn Start: ", current_player.name)
	
	has_acted_this_turn = false
	# Synchroniser le début du tour chez tout le monde (Local + Réseau)
	_handle_sync_turn(current_player.name)
	if not enable_hotseat_mode:
		NetworkManager.send_message({
			"type": "SYNC_TURN",
			"player_name": current_player.name
		})
	
	# En P2P, c'est le Pseudo-Host (Joueur 1) qui gère la pioche
	if enable_hotseat_mode or NetworkManager.self_user_id == player_peer_ids[players[0].name]:
		_draw_turn_cards(current_player.name)

func end_turn() -> void:
	if not is_game_active: return
	
	if is_waiting_for_reaction:
		print("⚠️ Cannot end turn while waiting for reaction.")
		return
	
	# En mode Hotseat, on exécute directement la logique serveur.
	if enable_hotseat_mode:
		_server_process_end_turn()
		return
		
	# Si on n'est pas le Pseudo-Host (J1), on demande à J1 de finir le tour
	var host_id = player_peer_ids[players[0].name]
	if NetworkManager.self_user_id != host_id:
		NetworkManager.send_message({
			"type": "REQUEST_END_TURN"
		})
		return
		
	# Logique Serveur
	if is_local_player_active():
		_server_process_end_turn()

# Returns true if an action was successfully consumed
func try_use_action() -> bool:
	if not is_game_active: return false
	if is_waiting_for_reaction:
		print("⚠️ Action blocked: Waiting for opponent reaction.")
		return false
		
	return is_local_player_active()

# Vérifie si le joueur local est celui dont c'est le tour
func is_local_player_active() -> bool:
	if enable_hotseat_mode:
		return true
		
	if players.is_empty(): return false
	var current_player_name = players[active_player_index].name
	var active_id = player_peer_ids.get(current_player_name, -1)
	return active_id == NetworkManager.self_user_id

func get_active_wrestler() -> Wrestler:
	if players.is_empty(): return null
	if active_player_index >= players.size(): return null
	return players[active_player_index]

func use_card(card: CardData) -> bool:
	if try_use_action():
		# Si on n'est pas le Host, on envoie la requête au Host
		if enable_hotseat_mode:
			server_process_use_card(card)
			return true
			
		var host_id = player_peer_ids[players[0].name]
		if NetworkManager.self_user_id != host_id:
			NetworkManager.send_message({
				"type": "REQUEST_PLAY_CARD",
				"card": CardData.serialize(card)
			})
			# On retourne true pour que l'UI locale soit réactive (Optimistic UI)
			# On retire la carte de notre main locale pour qu'elle ne revienne pas au refresh
			var my_name = _get_my_player_name()
			_remove_card_from_hand(my_name, card)
			_update_hand_count(my_name, -1)
			
			# FIX: Mettre à jour l'UI locale immédiatement (Optimistic UI)
			card_discarded.emit(card)
			
			# Idéalement, on attendrait la confirmation, mais pour ce POC c'est ok.
			return true
		
		# Logique Serveur (ou Local)
		server_process_use_card(card)
		return true
	return false

func discard_hand_card(card: CardData) -> void:
	if not is_game_active: return
	
	if try_use_action():
		# Si on n'est pas le Host, on envoie la requête au Host
		if enable_hotseat_mode:
			server_process_discard_card(card)
			return
			
		var host_id = player_peer_ids[players[0].name]
		if NetworkManager.self_user_id != host_id:
			NetworkManager.send_message({
				"type": "REQUEST_DISCARD_CARD",
				"card": CardData.serialize(card)
			})
			var my_name = _get_my_player_name()
			_remove_card_from_hand(my_name, card)
			_update_hand_count(my_name, -1)
			
			# FIX: Mettre à jour l'UI locale immédiatement (Optimistic UI)
			card_discarded.emit(card)
			return

		# Logique Serveur (ou Local)
		server_process_discard_card(card)

func get_playable_cards_in_hand() -> Array[CardData]:
	var playable_cards: Array[CardData] = []
	
	var active_wrestler = get_active_wrestler()
	if not active_wrestler: return []
	
	print("GM: Calculating playable cards for ", active_wrestler.name, " at ", active_wrestler.grid_position)

	var opponent = null
	for p in players:
		if p != active_wrestler:
			opponent = p
			break
	
	var hand = get_player_hand(active_wrestler.name)
	
	# If no opponent, only non-attack cards are playable
	if not opponent:
		for card in hand:
			if card.type != CardData.CardType.ATTACK:
				playable_cards.append(card)
		return playable_cards

	var distance_v = opponent.grid_position - active_wrestler.grid_position
	print("GM: Opponent relative distance: ", distance_v)
	
	for card in hand:
		if card.type != CardData.CardType.ATTACK:
			playable_cards.append(card)
		else:
			var is_playable = false
			var dx = abs(distance_v.x)
			var dy = abs(distance_v.y)

			if card.pattern == CardData.MovePattern.ORTHOGONAL:
				if dx + dy == 1:
					is_playable = true
			elif card.pattern == CardData.MovePattern.DIAGONAL:
				if dx == 1 and dy == 1:
					is_playable = true
			elif card.suit == "Joker": # Joker attack is range 1 any direction
				if dx <= 1 and dy <= 1 and not (dx == 0 and dy == 0):
					is_playable = true
			
			if is_playable:
				playable_cards.append(card)
				print("GM: Card ", card.title, " ", card.suit, " is PLAYABLE")
			else:
				print("GM: Card ", card.title, " ", card.suit, " is NOT playable")
	
	return playable_cards

func get_player_hand(player_name: String) -> Array:
	return player_hands.get(player_name, [])

# Used for initialization (fill hand to 5)
func _draw_up_to_limit(player_name: String) -> void:
	if not player_hands.has(player_name):
		player_hands[player_name] = []
	
	var current_hand = player_hands[player_name]
	while current_hand.size() < hand_size_limit:
		var new_card = deck_manager.draw_card()
		if new_card:
			current_hand.append(new_card)
			_notify_card_drawn(player_name, new_card)
		else:
			break # Deck empty

# Used for turn start (draw max 2, up to limit)
func _draw_turn_cards(player_name: String) -> void:
	if not player_hands.has(player_name):
		player_hands[player_name] = []
		
	var current_hand = player_hands[player_name]
	var space_in_hand = hand_size_limit - current_hand.size()
	var amount_to_draw = min(cards_drawn_per_turn, space_in_hand)
	
	for i in range(amount_to_draw):
		var new_card = deck_manager.draw_card()
		if new_card:
			current_hand.append(new_card)
			_notify_card_drawn(player_name, new_card)
		else:
			_handle_deck_empty_game_over()
			break

func _notify_card_drawn(player_name: String, card: CardData) -> void:
	_update_hand_count(player_name, 1)
	
	if enable_hotseat_mode:
		# In hotseat, the UI always reflects the active player's hand.
		# We only need to emit the signal if the card is for the currently active player.
		if player_name == players[active_player_index].name:
			card_drawn.emit(card)
		return
		
	var target_id = player_peer_ids.get(player_name)
	var my_id = NetworkManager.self_user_id
	
	# Si c'est pour moi (Host/Local)
	if target_id == my_id:
		card_drawn.emit(card)
		# Notify others that I drew (without showing card)
		NetworkManager.send_message({
			"type": "SYNC_DRAW",
			"player_name": player_name
		})
	else:
		# Sinon on envoie la carte au client concerné via Message
		# Note: On broadcast, mais le client filtrera si ce n'est pas pour lui
		NetworkManager.send_message({
			"type": "RECEIVE_CARD",
			"target_id": target_id,
			"card": CardData.serialize(card)
		})

func _handle_deck_empty_game_over() -> void:
	if not is_game_active: return
	is_game_active = false
	print("Deck empty! Calculating winner based on HP.")
	
	var p1 = players[0]
	var p2 = players[1]
	var winner_name = "DRAW"
	
	if p1.current_health > p2.current_health:
		winner_name = p1.name
	elif p2.current_health > p1.current_health:
		winner_name = p2.name
		
	game_over.emit(winner_name)
	
	if not enable_hotseat_mode:
		NetworkManager.send_message({
			"type": "GAME_OVER_DECK_EMPTY",
			"winner": winner_name
		})

func _remove_card_from_hand(player_name: String, card: CardData) -> bool:
	if player_hands.has(player_name):
		# On doit trouver la carte correspondante dans la main (comparaison par valeur car instances différentes réseau)
		var hand = player_hands[player_name]
		
		# Fix: Si la main est vide, c'est probablement un écho réseau ou une double suppression. On ignore.
		if hand.is_empty():
			return false
			
		for c in hand:
			# Simplification : On compare uniquement le titre qui est unique (ex: "X 10", "+ K", "JOKER")
			# Cela évite les erreurs de typage sur value/suit ou les problèmes de float
			if c.title == card.title and c.suit == card.suit:
				hand.erase(c)
				return true
	
	# Si on arrive ici, c'est que la carte n'est pas trouvée.
	# On loggue seulement si la main n'était pas vide (vrai problème de desync)
	if player_hands.has(player_name) and not player_hands[player_name].is_empty():
		print("DEBUG: Failed to remove card '", card.title, "' from hand of ", player_name)
		# Debug approfondi pour voir ce qu'il y a dans la main
		var hand_debug = []
		if player_hands.has(player_name):
			for c in player_hands[player_name]: hand_debug.append(c.title)
		print("DEBUG: Hand content: ", hand_debug)
	return false

func _update_hand_count(player_name: String, delta: int) -> void:
	if not player_hand_counts.has(player_name):
		player_hand_counts[player_name] = 0
	player_hand_counts[player_name] += delta
	# Prevent negative counts
	if player_hand_counts[player_name] < 0:
		player_hand_counts[player_name] = 0
	player_hand_counts_updated.emit(player_hand_counts)

# --- RPCs & Network Logic ---

func _on_network_message(data: Dictionary) -> void:
	if enable_hotseat_mode: return
	
	match data["type"]:
		"SYNC_TURN":
			_handle_sync_turn(data["player_name"])
		"SYNC_DRAW":
			_update_hand_count(data["player_name"], 1)
		"RECEIVE_CARD":
			var target_id = data["target_id"]
			# Update hand count for target
			for p_name in player_peer_ids:
				if player_peer_ids[p_name] == target_id:
					_update_hand_count(p_name, 1)
					break
			# Check if this card is for me
			if data["target_id"] == NetworkManager.self_user_id:
				_handle_receive_card(data.get("card", {}))
		"REQUEST_END_TURN":
			_handle_request_end_turn(data.get("_sender_id", ""))
		"REQUEST_PLAY_CARD":
			_handle_request_play_card(data.get("_sender_id", ""), data.get("card", {}))
		"REQUEST_DISCARD_CARD":
			_handle_request_discard_card(data.get("_sender_id", ""), data.get("card", {}))
		"SYNC_CARD_PLAYED":
			# Fix Echo: On ignore si c'est notre propre carte (car déjà supprimée localement)
			if data["player_name"] != _get_my_player_name():
				_update_hand_count(data["player_name"], -1)
				_handle_sync_card_played(data.get("card", {}), data["player_name"], data.get("is_use", true))
		"SYNC_GRID_ACTION":
			grid_action_received.emit(data["action_data"])
		"SYNC_HEALTH":
			_handle_sync_health(data["player_name"], data["value"])
		"REQUEST_ATTACK":
			_handle_request_attack(data)
		"ATTACK_RESULT":
			# Fix Echo: On ignore si c'est nous qui avons envoyé le résultat (en tant que défenseur)
			if data.get("_sender_id") != NetworkManager.self_user_id:
				_handle_attack_result(data)
		"SYNC_PUSH":
			_handle_sync_push(data)
		"SYNC_FLOATING_TEXT":
			_handle_sync_floating_text(data["player_name"], data["text"], data["color"])
		"REQUEST_RESTART_VOTE":
			_handle_rematch_vote(data["player_name"])
		"SYNC_CHARACTERS":
			_handle_character_selection(data["p1_path"], data["p2_path"])
		"GAME_OVER_DECK_EMPTY":
			is_game_active = false
			game_over.emit(data["winner"])
		"SYNC_PAUSE":
			game_paused.emit(data["paused"], data["player_name"])
		"SYNC_SKIP_VERSUS":
			opponent_skipped_versus.emit()

func _handle_sync_turn(player_name: String) -> void:
	print("Sync Turn: ", player_name)
	# Met à jour l'index localement pour que l'UI sache qui joue
	for i in range(players.size()):
		if players[i].name == player_name:
			active_player_index = i
			break
	turn_started.emit(player_name)

func _handle_receive_card(card_data_dict: Dictionary) -> void:
	print("Client received card RPC")
	var card = CardData.deserialize(card_data_dict)
	# On l'ajoute à notre main locale (pour l'UI)
	var my_name = _get_my_player_name()
	if not my_name.is_empty():
		if not player_hands.has(my_name):
			player_hands[my_name] = []
		player_hands[my_name].append(card)
	
	card_drawn.emit(card)

func _get_my_player_name() -> String:
	if enable_hotseat_mode:
		# In hotseat, "me" is always Player 1 for a stable camera/UI perspective.
		return "Player 1"
		
	var my_id = NetworkManager.self_user_id
	for name in player_peer_ids:
		if player_peer_ids[name] == my_id:
			return name
	return ""

func _handle_request_end_turn(sender_id: String) -> void:
	# Sécurité : Vérifier que c'est bien le tour du joueur qui demande
	var current_player_name = players[active_player_index].name
	
	if player_peer_ids[current_player_name] == sender_id:
		_server_process_end_turn()

func _server_process_end_turn() -> void:
	if not has_acted_this_turn:
		var current_player = players[active_player_index]
		print("🍅 AFK Penalty! ", current_player.name, " loses 1 HP.")
		send_floating_text(current_player.name, "AFK PENALTY!", Color(1.0, 0.5, 0.0))
		current_player.take_damage(1)

	print("Turn End Processed")
	turn_ended.emit()
	active_player_index = (active_player_index + 1) % players.size()
	_start_turn()

func _handle_request_play_card(sender_id: String, card_dict: Dictionary) -> void:
	var current_player_name = players[active_player_index].name
	if player_peer_ids.get(current_player_name) == sender_id:
		var card = CardData.deserialize(card_dict)
		server_process_use_card(card)

func _handle_request_discard_card(sender_id: String, card_dict: Dictionary) -> void:
	var current_player_name = players[active_player_index].name
	if player_peer_ids.get(current_player_name) == sender_id:
		var card = CardData.deserialize(card_dict)
		server_process_discard_card(card)

func server_process_use_card(card: CardData) -> void:
	var current_player_name = players[active_player_index].name
	has_acted_this_turn = true
	
	# On ne consomme la carte que si on arrive vraiment à l'enlever de la main
	if not _remove_card_from_hand(current_player_name, card):
		printerr("Server: Card '", card.title, "' not found in hand. Forcing consumption to fix desync.")
		if player_hands.has(current_player_name) and not player_hands[current_player_name].is_empty():
			var removed = player_hands[current_player_name].pop_front()
			print("Server: Force removed '", removed.title, "' to maintain hand count.")
	
	# Dans tous les cas (succès ou desync), on valide la consommation car l'action (Mvt/Attaque) a eu lieu.
	deck_manager.discard_card(card)
	_update_hand_count(current_player_name, -1)
	# Informer tout le monde qu'une carte a été jouée (pour l'historique/anim et nettoyage client)
	card_discarded.emit(card)
	card_played_visual.emit(current_player_name, card, true)
	if not enable_hotseat_mode:
		# FIX: On émet juste le signal localement au lieu de rappeler _handle_sync_card_played (qui tenterait de supprimer la carte une 2ème fois)
		NetworkManager.send_message({
			"type": "SYNC_CARD_PLAYED",
			"card": CardData.serialize(card),
			"player_name": current_player_name,
			"is_use": true
		})

func server_process_discard_card(card: CardData) -> void:
	var current_player_name = players[active_player_index].name
	has_acted_this_turn = true
	
	# Même logique robuste que pour use_card
	if not _remove_card_from_hand(current_player_name, card):
		printerr("Server: Discarded card '", card.title, "' not found in hand. Forcing consumption.")
		if player_hands.has(current_player_name) and not player_hands[current_player_name].is_empty():
			var removed = player_hands[current_player_name].pop_front()
			print("Server: Force removed '", removed.title, "' to maintain hand count.")
	
	deck_manager.discard_card(card)
	_update_hand_count(current_player_name, -1)
	card_discarded.emit(card)
	card_played_visual.emit(current_player_name, card, false)
	if not enable_hotseat_mode:
		# On réutilise sync_card_played car l'effet est le même (retrait de main + signal discard)
		# FIX: Idem, on évite la double suppression
		NetworkManager.send_message({
			"type": "SYNC_CARD_PLAYED",
			"card": CardData.serialize(card),
			"player_name": current_player_name,
			"is_use": false
		})

func _handle_sync_card_played(card_dict: Dictionary, player_name: String, is_use: bool = true) -> void:
	var card = CardData.deserialize(card_dict)
	_remove_card_from_hand(player_name, card)
	card_discarded.emit(card)
	card_played_visual.emit(player_name, card, is_use)

func send_pause_state(paused: bool) -> void:
	if enable_hotseat_mode: return
	
	var my_name = _get_my_player_name()
	NetworkManager.send_message({
		"type": "SYNC_PAUSE",
		"paused": paused,
		"player_name": my_name
	})

# --- Generic Grid/Health Sync ---

func send_grid_action(action_data: Dictionary) -> void:
	if enable_hotseat_mode: return
	# À appeler depuis GridManager pour synchroniser un mouvement/attaque
	NetworkManager.send_message({
		"type": "SYNC_GRID_ACTION",
		"action_data": action_data
	})

func send_health_update(wrestler_name: String, new_health: int) -> void:
	if enable_hotseat_mode: return
	NetworkManager.send_message({
		"type": "SYNC_HEALTH",
		"player_name": wrestler_name,
		"value": new_health
	})

func _handle_sync_health(player_name: String, value: int) -> void:
	# On active le flag pour ne pas renvoyer le signal health_changed au réseau
	is_network_syncing = true
	
	for p in players:
		if p.name == player_name:
			p.set_network_health(value)
			print("Sync Health: ", player_name, " -> ", value)
			break
			
	is_network_syncing = false

func send_floating_text(wrestler_name: String, text: String, color: Color) -> void:
	# Show locally
	for p in players:
		if p.name == wrestler_name:
			p.show_floating_text(text, color)
			break
	
	if not enable_hotseat_mode:
		# Send to network
		NetworkManager.send_message({
			"type": "SYNC_FLOATING_TEXT",
			"player_name": wrestler_name,
			"text": text,
			"color": color.to_html()
		})

func _handle_sync_floating_text(player_name: String, text: String, color_html: String) -> void:
	var color = Color.from_string(color_html, Color.WHITE)
	for p in players:
		if p.name == player_name:
			p.show_floating_text(text, color)
			break

func _handle_character_selection(p1_path: String, p2_path: String):
	if grid_manager:
		var p1_res = load(p1_path)
		var p2_res = load(p2_path)
		if p1_res and p2_res:
			print("Characters selected: P1 is ", p1_res.display_name, ", P2 is ", p2_res.display_name)
			# Now we tell the grid manager to spawn them, which will then trigger game state init
			grid_manager.spawn_wrestlers(p1_res, p2_res)
			
			# Determine Local vs Remote for Versus Screen
			var local_data = p1_res
			var remote_data = p2_res
			
			if _get_my_player_name() == "Player 2":
				local_data = p2_res
				remote_data = p1_res
				
			# Trigger Versus Screen instead of immediate init
			versus_screen_requested.emit(local_data, remote_data)
		else:
			printerr("Failed to load character resources from paths: ", p1_path, ", ", p2_path)

func request_restart() -> void:
	var my_name = _get_my_player_name()
	# Avoid double voting
	if rematch_votes.has(my_name): return
	
	# Register local vote
	_handle_rematch_vote(my_name)
	
	if not enable_hotseat_mode:
		NetworkManager.send_message({
			"type": "REQUEST_RESTART_VOTE",
			"player_name": my_name
		})

func _handle_rematch_vote(player_name: String) -> void:
	if not rematch_votes.has(player_name):
		rematch_votes[player_name] = true
		print("🔄 Rematch vote from: ", player_name)
		
		# Check condition: Votes >= Connected Players (Self + Network Peers)
		var required_votes = 2 if enable_hotseat_mode else NetworkManager.match_presences.size() + 1
		
		if rematch_votes.size() >= required_votes:
			_handle_restart_game()
		else:
			rematch_update.emit(rematch_votes.size(), required_votes)

func _handle_restart_game() -> void:
	print("🔄 Restarting Game (Hard Reset)...")
	# Hard Reset : On recharge la scène complète.
	# Cela détruit l'instance actuelle de GameManager et en crée une nouvelle.
	# NetworkManager (Autoload) reste vivant et garde la connexion.
	get_tree().change_scene_to_file("res://scenes/Arena.tscn")

func start_match_after_versus() -> void:
	initialize_game_state()

func send_skip_versus() -> void:
	if enable_hotseat_mode:
		opponent_skipped_versus.emit() # Simulate instant skip in hotseat
		return

	NetworkManager.send_message({
		"type": "SYNC_SKIP_VERSUS"
	})

# --- Attack / Reaction Sequence ---

func initiate_attack_sequence(target_wrestler: Wrestler, attack_card: CardData, is_push: bool = false) -> void:
	# Appelé par GridManager quand le joueur local attaque
	if is_waiting_for_reaction:
		print("⚠️ Attack already in progress. Ignoring duplicate initiation.")
		return

	var target_name = target_wrestler.name
	var target_id = player_peer_ids.get(target_name)
	
	# On stocke le contexte pour savoir qui taper quand la réponse reviendra
	pending_attack_context = {
		"target_name": target_name,
		"attack_card": attack_card,
		"is_push": is_push
	}
	is_waiting_for_reaction = true
	
	print("⚔️ Attack Sequence Initiated against ", target_name)
	if enable_hotseat_mode:
		# Loopback for Hotseat: Simulate receiving the request immediately
		var mock_data = {
			"target_id": target_id,
			"attacker_card": CardData.serialize(attack_card),
			"_sender_id": player_peer_ids[players[active_player_index].name]
		}
		_handle_request_attack(mock_data)
	else:
		NetworkManager.send_message({
			"type": "REQUEST_ATTACK",
			"attacker_card": CardData.serialize(attack_card),
			"target_id": target_id,
			"is_push": is_push
		})

func _handle_request_attack(data: Dictionary) -> void:
	# Suis-je la cible ?
	if not enable_hotseat_mode and data["target_id"] != NetworkManager.self_user_id:
		return
		
	if not pending_defense_context.is_empty():
		print("⚠️ Already defending. Ignoring duplicate REQUEST_ATTACK.")
		return
		
	var attack_card = CardData.deserialize(data["attacker_card"])
	
	# Store context for the response (who is attacking me?)
	pending_defense_context = {
		"attacker_id": data.get("_sender_id"),
		"target_id": data["target_id"],
		"attack_card": attack_card,
		"is_push": data.get("is_push", false)
	}
	
	# Identify defender name from target_id
	var target_id = data["target_id"]
	var defender_name = ""
	for name in player_peer_ids:
		if player_peer_ids[name] == target_id:
			defender_name = name
			break
	
	# In Hotseat, switch UI to defender's hand
	if enable_hotseat_mode:
		refresh_hand_requested.emit(defender_name)
	
	var defender_hand = get_player_hand(defender_name)
	
	var valid_cards = get_valid_reaction_cards(attack_card, defender_hand)
	
	if valid_cards.is_empty():
		print("🛡️ No valid reaction cards. Auto-taking damage.")
		_send_attack_result(false, null, false)
	else:
		print("🛡️ Reaction opportunity! Valid cards: ", valid_cards.size())
		reaction_phase_started.emit(attack_card, valid_cards)

func on_reaction_selected(reaction_card: CardData) -> void:
	print("🛡️ Player chose to block with: ", reaction_card.title)
	
	var attack_card = pending_defense_context.get("attack_card")
	
	# Distinction Blocage vs Esquive
	if attack_card and reaction_card.suit == attack_card.suit:
		# --- BLOCAGE (Même couleur) ---
		_consume_reaction_card(reaction_card)
		_send_attack_result(true, reaction_card, false)
	else:
		# --- ESQUIVE (Mouvement) ---
		# On ne consomme pas encore la carte, on passe en mode déplacement
		if grid_manager:
			var my_name = _get_my_player_name()
			var my_wrestler = null
			for w in players:
				if w.name == my_name:
					my_wrestler = w
					break
			if my_wrestler:
				grid_manager.enter_dodge_mode(reaction_card, my_wrestler)

func on_dodge_complete(card: CardData) -> void:
	print("🛡️ Dodge move complete.")
	_consume_reaction_card(card)
	_send_attack_result(false, card, true) # blocked=false, dodged=true

func _consume_reaction_card(card: CardData) -> void:
	var my_name = _get_my_player_name()
	_remove_card_from_hand(my_name, card)
	_update_hand_count(my_name, -1)
	deck_manager.discard_card(card)
	card_discarded.emit(card)
	
	if not enable_hotseat_mode:
		NetworkManager.send_message({
			"type": "SYNC_CARD_PLAYED",
			"card": CardData.serialize(card),
			"player_name": my_name
		})

func on_reaction_skipped() -> void:
	print("🛡️ Player skipped reaction.")
	_send_attack_result(false, null, false)

func _send_attack_result(blocked: bool, block_card: CardData, dodged: bool) -> void:
	var msg = {
		"type": "ATTACK_RESULT",
		"is_blocked": blocked,
		"is_dodged": dodged,
		"attacker_id": pending_defense_context.get("attacker_id"),
		"target_id": pending_defense_context.get("target_id"),
		"is_push": pending_defense_context.get("is_push", false)
	}
	if block_card: msg["block_card"] = CardData.serialize(block_card)
	
	if enable_hotseat_mode:
		_handle_attack_result(msg)
	else:
		NetworkManager.send_message(msg)
		# FIX: Handle local visual update because NetworkManager filters echo
		_handle_attack_result(msg)

func _handle_attack_result(data: Dictionary) -> void:
	# Safety for Defender: Prevent double processing (Double Damage Fix)
	if not enable_hotseat_mode and data.get("target_id") == NetworkManager.self_user_id:
		if pending_defense_context.is_empty() and not is_waiting_for_reaction:
			print("⚠️ Duplicate ATTACK_RESULT ignored on Defender.")
			return
		pending_defense_context.clear()

	is_waiting_for_reaction = false
	
	# In Hotseat, switch UI back to active player (attacker)
	if enable_hotseat_mode:
		refresh_hand_requested.emit(players[active_player_index].name)
	
	if data.get("is_blocked", false):
		print("🛡️ Attack was BLOCKED!")
		var target = _get_wrestler_by_peer_id(data.get("target_id"))
		if target: target.show_floating_text("BLOCKED!", Color(1.0, 0.6, 0.0)) # Orange
	elif data.get("is_dodged", false):
		print("💨 Attack was DODGED!")
		var target = _get_wrestler_by_peer_id(data.get("target_id"))
		if target:
			target.show_floating_text("DODGED!", Color(0.0, 0.8, 1.0)) # Cyan
			if target.has_method("play_dodge_sound"):
				target.play_dodge_sound()
	else:
		print("💥 Attack CONNECTED!")
		
	# Trigger Animation (Visuals)
	var attacker = _get_wrestler_by_peer_id(data.get("attacker_id"))
	var target = _get_wrestler_by_peer_id(data.get("target_id"))
	
	if attacker and target:
		# Check if we are the attacker who initiated this (Context exists)
		var is_initiator = not pending_attack_context.is_empty()
		
		# Safety: Prevent double processing on Attacker (Double Damage Fix)
		if is_local_player_active() and not is_initiator:
			print("⚠️ Duplicate ATTACK_RESULT ignored on Attacker.")
			return

		# Determine if hit
		var is_blocked = data.get("is_blocked", false)
		var is_dodged = data.get("is_dodged", false)
		var is_hit = not is_blocked and not is_dodged
		var is_push = bool(data.get("is_push", false))
		
		# L'attaquant frappe toujours (dans le vide si esquivé/bloqué)
		attacker.attack(target, is_hit, is_push)
		
		# Animation du défenseur
		if is_blocked:
			target.block()
		elif is_dodged:
			# Le défenseur a déjà bougé via SYNC_GRID_ACTION, pas d'anim spécifique ici (Run déjà joué)
			pass
		else:
			# Dégâts réels ou Poussée
			# FIX: Use is_initiator to ensure we consume the context if it exists, regardless of turn state
			if is_initiator:
				if pending_attack_context.has("target_name"):
					var target_name = pending_attack_context["target_name"]
					var is_push_attack = pending_attack_context.get("is_push", false)
					
					for w in players:
						if w.name == target_name:
							if is_push_attack:
								_apply_push(attacker, w)
							else:
								# Damage is now applied via the animation event on the attacker's side
								pass
							break
				pending_attack_context.clear()
			else:
				# Pour les clients passifs, take_damage joue l'anim Hurt
				# Mais take_damage applique aussi les dégâts locaux, ce qui est géré par SYNC_HEALTH normalement.
				# Cependant, pour l'animation Hurt immédiate, on peut laisser faire le sync ou forcer l'anim.
				# Le sync health arrivera juste après.
				pass
		
func _apply_push(attacker: Wrestler, target: Wrestler) -> void:
	# Calculer la direction de la poussée
	var direction = target.grid_position - attacker.grid_position
	# Normaliser pour avoir 1 case (même en diagonale)
	direction = direction.clamp(Vector2i(-1, -1), Vector2i(1, 1))
	
	var dest_cell = target.grid_position + direction
	
	print("💨 Pushing ", target.name, " to ", dest_cell)
	
	# Check Ejection (Ring Out)
	if grid_manager and not grid_manager.is_valid_cell(dest_cell):
		# Apply Ring Out Damage
		target.take_damage(2)
	
	# Appliquer localement
	target.push_to(dest_cell)
	
	if not enable_hotseat_mode:
		# Synchroniser
		NetworkManager.send_message({
			"type": "SYNC_PUSH",
			"target_name": target.name,
			"x": dest_cell.x,
			"y": dest_cell.y
		})

func _handle_sync_push(data: Dictionary) -> void:
	var target_name = data.get("target_name")
	var dest = Vector2i(data["x"], data["y"])
	
	for w in players:
		if w.name == target_name:
			w.push_to(dest)
			break

func _get_wrestler_by_peer_id(peer_id: String) -> Wrestler:
	if peer_id == null: return null
	for player_name in player_peer_ids:
		if player_peer_ids[player_name] == peer_id:
			for w in players:
				if w.name == player_name:
					return w
	return null

# --- Reaction Logic Helpers ---

func get_valid_reaction_cards(attack_card: CardData, hand: Array) -> Array[CardData]:
	var valid_cards: Array[CardData] = []
	
	for card in hand:
		# On ne peut pas réagir avec une carte Attaque (sauf si règle spéciale, mais PRD dit Blocage/Esquive)
		# PRD: "Jouer une carte de la même couleur (Blocage) ou Mouvement Opposé (Esquive)"
		# Condition de base : Valeur strictement supérieure
		if card.value <= attack_card.value and card.suit != "Joker":
			continue
			
		var is_valid = false
		
		# 1. BLOCAGE (Même Enseigne/Symbole)
		# Règle : Pour bloquer, il faut exactement la même enseigne (Coeur vs Coeur, Carreau vs Carreau)
		# Cela garantit que + bloque + et X bloque X.
		if card.suit == attack_card.suit:
			is_valid = true # Blocage
			
		# 2. ESQUIVE (Mouvement Opposé)
		# Attaque Ortho (Carreau/Trèfle?) -> Esquive Diag (Pique/Coeur?)
		# Vérifions les patterns définis dans DeckManager
		if can_dodge and (card.type == CardData.CardType.MOVE or card.suit == "Joker"):
			if attack_card.pattern == CardData.MovePattern.ORTHOGONAL and card.pattern == CardData.MovePattern.DIAGONAL:
				is_valid = true
			elif attack_card.pattern == CardData.MovePattern.DIAGONAL and card.pattern == CardData.MovePattern.ORTHOGONAL:
				is_valid = true
				
		if is_valid:
			valid_cards.append(card)
			
	return valid_cards
	
func set_wrestler_collisions(enabled: bool) -> void:
	if grid_manager:
		grid_manager.set_wrestler_collisions(enabled)

func preview_swipe(card: CardData, screen_offset: Vector2) -> bool:
	if grid_manager and (is_local_player_active() or not pending_defense_context.is_empty()):
		# NOTE: La fonction handle_swipe_preview dans GridManager doit maintenant retourner un booléen.
		return grid_manager.handle_swipe_preview(card, screen_offset)
	return false

func commit_swipe(card: CardData, screen_offset: Vector2, global_pos: Vector2) -> bool:
	if grid_manager and (is_local_player_active() or not pending_defense_context.is_empty()):
		return grid_manager.handle_swipe_commit(card, screen_offset, global_pos)
	return false
