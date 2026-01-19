class_name GameManager
extends Node

signal turn_started(player_name: String)
signal card_drawn(card: CardData)
signal card_discarded(card: CardData)
signal turn_ended

@export var hand_size_limit: int = 5
@export var cards_drawn_per_turn: int = 2

var deck_manager: DeckManager

var players: Array[Wrestler] = []
# Dictionary to store hand for each player: { player_name: [CardData] }
var player_hands: Dictionary = {}
var active_player_index: int = 0
var is_game_active: bool = false

# Mapping des noms de joueurs vers les IDs réseau (Peer ID)
var player_peer_ids: Dictionary = {}

func initialize(wrestlers_list: Array[Wrestler], deck_mgr: DeckManager) -> void:
	players = wrestlers_list
	deck_manager = deck_mgr
	active_player_index = 0 # Player 1 starts
	is_game_active = true
	
	# Configuration des IDs réseau
	player_peer_ids.clear()
	
	# Logique P2P Déterministe : On récupère tous les IDs et on les trie.
	# Tout le monde aura la même liste triée, donc tout le monde sera d'accord sur qui est J1 et J2.
	var all_peers = multiplayer.get_peers()
	all_peers.append(multiplayer.get_unique_id())
	all_peers.sort()
	
	# Assignation : Le plus petit ID est le Joueur 1 (Pseudo-Host)
	if all_peers.size() > 0: player_peer_ids[players[0].name] = all_peers[0]
	if all_peers.size() > 1: player_peer_ids[players[1].name] = all_peers[1]
	else: player_peer_ids[players[1].name] = all_peers[0] # Fallback Solo/Debug

	# Est-ce que je suis le "Pseudo-Host" (Joueur 1) ?
	var am_i_host = (multiplayer.get_unique_id() == player_peer_ids[players[0].name])

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
	
	# Synchroniser le début du tour chez tout le monde
	sync_turn_update.rpc(current_player.name)
	
	# Le serveur gère la pioche
	# En P2P, c'est le Pseudo-Host (Joueur 1) qui gère ça
	if multiplayer.get_unique_id() == player_peer_ids[players[0].name]:
		_draw_turn_cards(current_player.name)

func end_turn() -> void:
	if not is_game_active: return
	
	# Si on n'est pas le Pseudo-Host (J1), on demande à J1 de finir le tour
	var host_id = player_peer_ids[players[0].name]
	if multiplayer.get_unique_id() != host_id:
		request_end_turn.rpc_id(host_id)
		return
		
	# Logique Serveur
	if is_local_player_active():
		_server_process_end_turn()

# Returns true if an action was successfully consumed
func try_use_action() -> bool:
	if not is_game_active: return false
	return is_local_player_active()

# Vérifie si le joueur local est celui dont c'est le tour
func is_local_player_active() -> bool:
	if players.is_empty(): return false
	var current_player_name = players[active_player_index].name
	var active_id = player_peer_ids.get(current_player_name, -1)
	return active_id == multiplayer.get_unique_id()

func get_active_wrestler() -> Wrestler:
	if players.is_empty(): return null
	if active_player_index >= players.size(): return null
	return players[active_player_index]

func use_card(card: CardData) -> bool:
	if try_use_action():
		# Si on n'est pas le Host, on envoie la requête au Host
		var host_id = player_peer_ids[players[0].name]
		if multiplayer.get_unique_id() != host_id:
			request_play_card.rpc_id(host_id, _serialize_card(card))
			# On retourne true pour que l'UI locale soit réactive (Optimistic UI)
			# On retire la carte de notre main locale pour qu'elle ne revienne pas au refresh
			var my_name = _get_my_player_name()
			_remove_card_from_hand(my_name, card)
			
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
		if multiplayer.get_unique_id() != host_id:
			request_discard_card.rpc_id(host_id, _serialize_card(card))
			var my_name = _get_my_player_name()
			_remove_card_from_hand(my_name, card)
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
	var my_id = multiplayer.get_unique_id()
	
	# Si c'est pour moi (Host/Local)
	if target_id == my_id:
		card_drawn.emit(card)
	else:
		# Sinon on envoie la carte au client concerné via RPC
		client_receive_card.rpc_id(target_id, _serialize_card(card))

func _remove_card_from_hand(player_name: String, card: CardData) -> bool:
	if player_hands.has(player_name):
		# On doit trouver la carte correspondante dans la main (comparaison par valeur car instances différentes réseau)
		var hand = player_hands[player_name]
		for c in hand:
			# Simplification : On compare uniquement le titre qui est unique (ex: "X 10", "+ K", "JOKER")
			# Cela évite les erreurs de typage sur value/suit ou les problèmes de float
			if c.title == card.title:
				hand.erase(c)
				return true
	
	print("DEBUG: Failed to remove card '", card.title, "' from hand of ", player_name)
	# Debug approfondi pour voir ce qu'il y a dans la main
	var hand_debug = []
	if player_hands.has(player_name):
		for c in player_hands[player_name]: hand_debug.append(c.title)
	print("DEBUG: Hand content: ", hand_debug)
	return false

# --- RPCs & Network Logic ---

@rpc("authority", "call_local", "reliable")
func sync_turn_update(player_name: String) -> void:
	print("Sync Turn: ", player_name)
	# Met à jour l'index localement pour que l'UI sache qui joue
	for i in range(players.size()):
		if players[i].name == player_name:
			active_player_index = i
			break
	turn_started.emit(player_name)

@rpc("authority", "call_remote", "reliable")
func client_receive_card(card_data_dict: Dictionary) -> void:
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
	var my_id = multiplayer.get_unique_id()
	for name in player_peer_ids:
		if player_peer_ids[name] == my_id:
			return name
	return ""

@rpc("any_peer", "call_remote", "reliable")
func request_end_turn() -> void:
	# Sécurité : Vérifier que c'est bien le tour du joueur qui demande
	var sender_id = multiplayer.get_remote_sender_id()
	var current_player_name = players[active_player_index].name
	
	if player_peer_ids[current_player_name] == sender_id:
		_server_process_end_turn()

func _server_process_end_turn() -> void:
	print("Turn End Processed")
	turn_ended.emit()
	active_player_index = (active_player_index + 1) % players.size()
	_start_turn()

@rpc("any_peer", "call_remote", "reliable")
func request_play_card(card_dict: Dictionary) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	var current_player_name = players[active_player_index].name
	
	if player_peer_ids[current_player_name] == sender_id:
		var card = _deserialize_card(card_dict)
		server_process_use_card(card)

@rpc("any_peer", "call_remote", "reliable")
func request_discard_card(card_dict: Dictionary) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	var current_player_name = players[active_player_index].name
	
	if player_peer_ids[current_player_name] == sender_id:
		var card = _deserialize_card(card_dict)
		server_process_discard_card(card)

func server_process_use_card(card: CardData) -> void:
	var current_player_name = players[active_player_index].name
	
	# On ne consomme la carte que si on arrive vraiment à l'enlever de la main
	if not _remove_card_from_hand(current_player_name, card):
		printerr("Server: Card '", card.title, "' not found in hand. Forcing consumption to fix desync.")
		if player_hands.has(current_player_name) and not player_hands[current_player_name].is_empty():
			var removed = player_hands[current_player_name].pop_front()
			print("Server: Force removed '", removed.title, "' to maintain hand count.")
	
	# Dans tous les cas (succès ou desync), on valide la consommation car l'action (Mvt/Attaque) a eu lieu.
	deck_manager.discard_card(card)
	# Informer tout le monde qu'une carte a été jouée (pour l'historique/anim et nettoyage client)
	sync_card_played.rpc(_serialize_card(card), current_player_name)

func server_process_discard_card(card: CardData) -> void:
	var current_player_name = players[active_player_index].name
	
	# Même logique robuste que pour use_card
	if not _remove_card_from_hand(current_player_name, card):
		printerr("Server: Discarded card '", card.title, "' not found in hand. Forcing consumption.")
		if player_hands.has(current_player_name) and not player_hands[current_player_name].is_empty():
			var removed = player_hands[current_player_name].pop_front()
			print("Server: Force removed '", removed.title, "' to maintain hand count.")
	
	deck_manager.discard_card(card)
	# On réutilise sync_card_played car l'effet est le même (retrait de main + signal discard)
	# Si on voulait une anim différente pour la défausse, on créerait un sync_card_discarded
	sync_card_played.rpc(_serialize_card(card), current_player_name)

@rpc("authority", "call_local", "reliable")
func sync_card_played(card_dict: Dictionary, player_name: String) -> void:
	var card = _deserialize_card(card_dict)
	_remove_card_from_hand(player_name, card)
	card_discarded.emit(card)

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