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

@export var hand_size_limit: int = 5
@export var cards_drawn_per_turn: int = 2

var deck_manager: DeckManager

var players: Array[Wrestler] = []
# Dictionary to store hand for each player: { player_name: [CardData] }
var player_hands: Dictionary = {}
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

func initialize(wrestlers_list: Array[Wrestler], deck_mgr: DeckManager) -> void:
	players = wrestlers_list
	deck_manager = deck_mgr
	active_player_index = 0 # Player 1 starts
	is_game_active = true
	
	# Configuration des IDs réseau
	player_peer_ids.clear()
	
	# Logique P2P Déterministe : On récupère tous les IDs et on les trie.
	# Tout le monde aura la même liste triée, donc tout le monde sera d'accord sur qui est J1 et J2.
	var all_ids = [NetworkManager.self_user_id]
	for uid in NetworkManager.match_presences:
		all_ids.append(uid)
	all_ids.sort()
	
	# Assignation : Le plus petit ID est le Joueur 1 (Pseudo-Host)
	if all_ids.size() > 0: player_peer_ids[players[0].name] = all_ids[0]
	if all_ids.size() > 1: player_peer_ids[players[1].name] = all_ids[1]
	else: player_peer_ids[players[1].name] = all_ids[0] # Fallback Solo/Debug

	# Est-ce que je suis le "Pseudo-Host" (Joueur 1) ?
	var am_i_host = (NetworkManager.self_user_id == player_peer_ids[players[0].name])

	if am_i_host:
		# Le "Host" gère le deck et la distribution
		deck_manager.initialize_deck()
		
		# Initial setup: Fill hands to limit for all players
		for player in players:
			_draw_up_to_limit(player.name)
			
		_start_turn()

func _start_turn() -> void:
	var current_player = players[active_player_index]
	print("Turn Start: ", current_player.name)
	
	has_acted_this_turn = false
	# Synchroniser le début du tour chez tout le monde (Local + Réseau)
	_handle_sync_turn(current_player.name)
	NetworkManager.send_message({
		"type": "SYNC_TURN",
		"player_name": current_player.name
	})
	
	# En P2P, c'est le Pseudo-Host (Joueur 1) qui gère la pioche
	if NetworkManager.self_user_id == player_peer_ids[players[0].name]:
		_draw_turn_cards(current_player.name)

func end_turn() -> void:
	if not is_game_active: return
	
	if is_waiting_for_reaction:
		print("⚠️ Cannot end turn while waiting for reaction.")
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
		var host_id = player_peer_ids[players[0].name]
		if NetworkManager.self_user_id != host_id:
			NetworkManager.send_message({
				"type": "REQUEST_PLAY_CARD",
				"card": _serialize_card(card)
			})
			# On retourne true pour que l'UI locale soit réactive (Optimistic UI)
			# On retire la carte de notre main locale pour qu'elle ne revienne pas au refresh
			var my_name = _get_my_player_name()
			_remove_card_from_hand(my_name, card)
			
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
		var host_id = player_peer_ids[players[0].name]
		if NetworkManager.self_user_id != host_id:
			NetworkManager.send_message({
				"type": "REQUEST_DISCARD_CARD",
				"card": _serialize_card(card)
			})
			var my_name = _get_my_player_name()
			_remove_card_from_hand(my_name, card)
			
			# FIX: Mettre à jour l'UI locale immédiatement (Optimistic UI)
			card_discarded.emit(card)
			return

		# Logique Serveur (ou Local)
		server_process_discard_card(card)

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
			break

func _notify_card_drawn(player_name: String, card: CardData) -> void:
	var target_id = player_peer_ids.get(player_name)
	var my_id = NetworkManager.self_user_id
	
	# Si c'est pour moi (Host/Local)
	if target_id == my_id:
		card_drawn.emit(card)
	else:
		# Sinon on envoie la carte au client concerné via Message
		# Note: On broadcast, mais le client filtrera si ce n'est pas pour lui
		NetworkManager.send_message({
			"type": "RECEIVE_CARD",
			"target_id": target_id,
			"card": _serialize_card(card)
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

# --- RPCs & Network Logic ---

func _on_network_message(data: Dictionary) -> void:
	match data.type:
		"SYNC_TURN":
			_handle_sync_turn(data.player_name)
		"RECEIVE_CARD":
			# Check if this card is for me
			if data.target_id == NetworkManager.self_user_id:
				_handle_receive_card(data.card)
		"REQUEST_END_TURN":
			_handle_request_end_turn(data.get("_sender_id", ""))
		"REQUEST_PLAY_CARD":
			_handle_request_play_card(data.get("_sender_id", ""), data.card)
		"REQUEST_DISCARD_CARD":
			_handle_request_discard_card(data.get("_sender_id", ""), data.card)
		"SYNC_CARD_PLAYED":
			# Fix Echo: On ignore si c'est notre propre carte (car déjà supprimée localement)
			if data.player_name != _get_my_player_name():
				_handle_sync_card_played(data.card, data.player_name)
		"SYNC_GRID_ACTION":
			grid_action_received.emit(data.action_data)
		"SYNC_HEALTH":
			_handle_sync_health(data.player_name, data.value)
		"REQUEST_ATTACK":
			_handle_request_attack(data)
		"ATTACK_RESULT":
			_handle_attack_result(data)
		"SYNC_PUSH":
			_handle_sync_push(data)
		"SYNC_FLOATING_TEXT":
			_handle_sync_floating_text(data.player_name, data.text, data.color)
		"REQUEST_RESTART_VOTE":
			_handle_rematch_vote(data.player_name)

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
	var card = _deserialize_card(card_data_dict)
	# On l'ajoute à notre main locale (pour l'UI)
	var my_name = _get_my_player_name()
	if not my_name.is_empty():
		if not player_hands.has(my_name):
			player_hands[my_name] = []
		player_hands[my_name].append(card)
	
	card_drawn.emit(card)

func _get_my_player_name() -> String:
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
	if player_peer_ids[current_player_name] == sender_id:
		var card = _deserialize_card(card_dict)
		server_process_use_card(card)

func _handle_request_discard_card(sender_id: String, card_dict: Dictionary) -> void:
	var current_player_name = players[active_player_index].name
	if player_peer_ids[current_player_name] == sender_id:
		var card = _deserialize_card(card_dict)
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
	# Informer tout le monde qu'une carte a été jouée (pour l'historique/anim et nettoyage client)
	# FIX: On émet juste le signal localement au lieu de rappeler _handle_sync_card_played (qui tenterait de supprimer la carte une 2ème fois)
	card_discarded.emit(card)
	NetworkManager.send_message({
		"type": "SYNC_CARD_PLAYED",
		"card": _serialize_card(card),
		"player_name": current_player_name
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
	# On réutilise sync_card_played car l'effet est le même (retrait de main + signal discard)
	# FIX: Idem, on évite la double suppression
	card_discarded.emit(card)
	NetworkManager.send_message({
		"type": "SYNC_CARD_PLAYED",
		"card": _serialize_card(card),
		"player_name": current_player_name
	})

func _handle_sync_card_played(card_dict: Dictionary, player_name: String) -> void:
	var card = _deserialize_card(card_dict)
	_remove_card_from_hand(player_name, card)
	card_discarded.emit(card)

# --- Generic Grid/Health Sync ---

func send_grid_action(action_data: Dictionary) -> void:
	# À appeler depuis GridManager pour synchroniser un mouvement/attaque
	NetworkManager.send_message({
		"type": "SYNC_GRID_ACTION",
		"action_data": action_data
	})

func send_health_update(wrestler_name: String, new_health: int) -> void:
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

func request_restart() -> void:
	var my_name = _get_my_player_name()
	# Avoid double voting
	if rematch_votes.has(my_name): return
	
	# Register local vote
	_handle_rematch_vote(my_name)
	
	NetworkManager.send_message({
		"type": "REQUEST_RESTART_VOTE",
		"player_name": my_name
	})

func _handle_rematch_vote(player_name: String) -> void:
	if not rematch_votes.has(player_name):
		rematch_votes[player_name] = true
		print("🔄 Rematch vote from: ", player_name)
		
		# Check condition: Votes >= Connected Players (Self + Network Peers)
		var required_votes = NetworkManager.match_presences.size() + 1
		
		if rematch_votes.size() >= required_votes:
			_handle_restart_game()
		else:
			rematch_update.emit(rematch_votes.size(), required_votes)

func _handle_restart_game() -> void:
	print("🔄 Restarting Game...")
	rematch_votes.clear()
	is_game_active = true
	active_player_index = 0 # Player 1 starts
	has_acted_this_turn = false
	pending_attack_context.clear()
	pending_defense_context.clear()
	is_waiting_for_reaction = false
	
	# Reset Deck
	deck_manager.initialize_deck()
	
	# Reset Hands
	player_hands.clear()
	
	# Reset Wrestlers
	if grid_manager:
		grid_manager.reset_wrestlers()
	
	game_restarted.emit()
	
	# Draw initial hands
	for player in players:
		_draw_up_to_limit(player.name)
		
	_start_turn()

# --- Attack / Reaction Sequence ---

func initiate_attack_sequence(target_wrestler: Wrestler, attack_card: CardData, is_push: bool = false) -> void:
	# Appelé par GridManager quand le joueur local attaque
	var target_name = target_wrestler.name
	var target_id = player_peer_ids.get(target_name)
	
	# On stocke le contexte pour savoir qui taper quand la réponse reviendra
	pending_attack_context = {
		"target_name": target_name,
		"attack_card": attack_card,
		"is_push": is_push
	}
	is_waiting_for_reaction = true
	
	NetworkManager.send_message({
		"type": "REQUEST_ATTACK",
		"attacker_card": _serialize_card(attack_card),
		"target_id": target_id,
		"is_push": is_push
	})
	print("⚔️ Attack Sequence Initiated against ", target_name)

func _handle_request_attack(data: Dictionary) -> void:
	# Suis-je la cible ?
	if data.target_id != NetworkManager.self_user_id:
		return
		
	var attack_card = _deserialize_card(data.attacker_card)
	
	# Store context for the response (who is attacking me?)
	pending_defense_context = {
		"attacker_id": data.get("_sender_id"),
		"target_id": NetworkManager.self_user_id,
		"attack_card": attack_card
	}
	
	var my_name = _get_my_player_name()
	var my_hand = get_player_hand(my_name)
	
	var valid_cards = get_valid_reaction_cards(attack_card, my_hand)
	
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
	deck_manager.discard_card(card)
	card_discarded.emit(card)
	
	NetworkManager.send_message({
		"type": "SYNC_CARD_PLAYED",
		"card": _serialize_card(card),
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
		"target_id": pending_defense_context.get("target_id")
	}
	if block_card: msg["block_card"] = _serialize_card(block_card)
	NetworkManager.send_message(msg)
	
	# FIX: Handle local visual update because NetworkManager filters echo
	_handle_attack_result(msg)

func _handle_attack_result(data: Dictionary) -> void:
	is_waiting_for_reaction = false
	
	if data.is_blocked:
		print("🛡️ Attack was BLOCKED!")
		var target = _get_wrestler_by_peer_id(data.get("target_id"))
		if target: target.show_floating_text("BLOCKED!", Color(1.0, 0.6, 0.0)) # Orange
	elif data.get("is_dodged"):
		print("💨 Attack was DODGED!")
		var target = _get_wrestler_by_peer_id(data.get("target_id"))
		if target: target.show_floating_text("DODGED!", Color(0.0, 0.8, 1.0)) # Cyan
	else:
		print("💥 Attack CONNECTED!")
		
	# Trigger Animation (Visuals)
	var attacker = _get_wrestler_by_peer_id(data.get("attacker_id"))
	var target = _get_wrestler_by_peer_id(data.get("target_id"))
	
	if attacker and target:
		# Determine if hit
		var is_hit = not data.is_blocked and not data.get("is_dodged")
		
		# L'attaquant frappe toujours (dans le vide si esquivé/bloqué)
		attacker.attack(target, is_hit)
		
		# Animation du défenseur
		if data.is_blocked:
			target.block()
		elif data.get("is_dodged"):
			# Le défenseur a déjà bougé via SYNC_GRID_ACTION, pas d'anim spécifique ici (Run déjà joué)
			pass
		else:
			# Dégâts réels ou Poussée
			if is_local_player_active():
				if pending_attack_context.has("target_name"):
					var target_name = pending_attack_context.target_name
					var is_push = pending_attack_context.get("is_push", false)
					
					for w in players:
						if w.name == target_name:
							if is_push:
								_apply_push(attacker, w)
							else:
								# Pass skip_anim = true because attacker.attack will trigger it via anim event
								w.take_damage(1, true)
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
	
	# Synchroniser
	NetworkManager.send_message({
		"type": "SYNC_PUSH",
		"target_name": target.name,
		"x": dest_cell.x,
		"y": dest_cell.y
	})

func _handle_sync_push(data: Dictionary) -> void:
	var target_name = data.get("target_name")
	var dest = Vector2i(data.x, data.y)
	
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
		if card.type == CardData.CardType.MOVE or card.suit == "Joker":
			if attack_card.pattern == CardData.MovePattern.ORTHOGONAL and card.pattern == CardData.MovePattern.DIAGONAL:
				is_valid = true
			elif attack_card.pattern == CardData.MovePattern.DIAGONAL and card.pattern == CardData.MovePattern.ORTHOGONAL:
				is_valid = true
				
		if is_valid:
			valid_cards.append(card)
			
	return valid_cards

# --- Helpers Serialization ---

func _serialize_card(card: CardData) -> Dictionary:
	return {
		"type": int(card.type),
		"value": card.value,
		"title": card.title,
		"suit": card.suit,
		"pattern": int(card.pattern)
	}

func _deserialize_card(data: Dictionary) -> CardData:
	var card = CardData.new()
	card.type = int(data.type) # Force int for Enum
	card.value = int(data.value) # Force int
	card.title = data.title
	card.suit = data.suit
	card.pattern = int(data.pattern) # Force int for Enum
	return card

func set_wrestler_collisions(enabled: bool) -> void:
	if grid_manager:
		grid_manager.set_wrestler_collisions(enabled)

func preview_swipe(card: CardData, screen_offset: Vector2) -> void:
	if grid_manager and (is_local_player_active() or not pending_defense_context.is_empty()):
		grid_manager.handle_swipe_preview(card, screen_offset)

func commit_swipe(card: CardData, screen_offset: Vector2, global_pos: Vector2) -> void:
	if grid_manager and (is_local_player_active() or not pending_defense_context.is_empty()):
		grid_manager.handle_swipe_commit(card, screen_offset, global_pos)