class_name HandManager
extends Node

## Seul module autorisé à lire/écrire player_hands.
## Toute modification de main passe obligatoirement par ce module.

signal card_drawn(card: CardData)
signal card_discarded(card: CardData)
signal card_played_visual(player_name: String, card: CardData, is_use: bool)
signal deck_count_updated(count: int)
signal player_hand_counts_updated(counts: Dictionary)
signal deck_empty_detected

const HAND_SIZE_LIMIT = 5
const CARDS_DRAWN_PER_TURN = 2

var _net: NetworkSync
var _deck: DeckManager

var _hands: Dictionary = {}       # { player_name: Array[CardData] }
var _hand_counts: Dictionary = {} # { player_name: int }
var _active_player_name: String = ""

func setup(deck: DeckManager, net: NetworkSync) -> void:
	_deck = deck
	_net = net

## Indique au HandManager quel joueur est actif (utilisé en mode hotseat pour filtrer card_drawn).
func set_active_player(player_name: String) -> void:
	_active_player_name = player_name

## Appelé une seule fois en début de partie par l'hôte.
## Distribue les cartes initiales via le même mécanisme que les tirages de tour :
## RECEIVE_CARD pour les joueurs distants, card_drawn pour le joueur local.
func initialize_hands(player_names: Array) -> void:
	_hands.clear()
	_hand_counts.clear()
	for pname in player_names:
		_hands[pname] = []
	for pname in player_names:
		while _hands[pname].size() < HAND_SIZE_LIMIT:
			var card = _deck.draw_card()
			if not card: break
			_hands[pname].append(card)
			_on_card_drawn_for(pname, card)
	_sync_deck_count()

## Pioche les cartes de début de tour pour player_name. Appelé uniquement par l'hôte.
func draw_turn_cards(player_name: String) -> void:
	if not _hands.has(player_name):
		_hands[player_name] = []
	var hand = _hands[player_name]
	var amount = mini(CARDS_DRAWN_PER_TURN, HAND_SIZE_LIMIT - hand.size())
	for i in range(amount):
		var card = _deck.draw_card()
		if not card:
			deck_empty_detected.emit()
			return
		hand.append(card)
		_on_card_drawn_for(player_name, card)
	_sync_deck_count()

## Consomme une carte de la main du joueur (jouée ou défaussée). Single writer pour les mains.
func consume_card(player_name: String, card: CardData, is_use: bool) -> void:
	if not _remove_from_hand(player_name, card):
		printerr("HandManager: '", card.title, "' introuvable dans la main de ", player_name, ". Force-remove.")
		if _hands.has(player_name) and not _hands[player_name].is_empty():
			_hands[player_name].pop_front()
	_deck.discard_card(card)
	_update_count(player_name, -1)
	card_discarded.emit(card)
	card_played_visual.emit(player_name, card, is_use)
	_net.send({
		"type": "SYNC_CARD_PLAYED",
		"card": CardData.serialize(card),
		"player_name": player_name,
		"is_use": is_use
	})

## Retrait optimiste côté client non-hôte (avant confirmation serveur).
## NE touche pas au deck ni n'envoie de message réseau.
func remove_for_optimistic_ui(player_name: String, card: CardData, is_use: bool) -> void:
	_remove_from_hand(player_name, card)
	_update_count(player_name, -1)
	card_discarded.emit(card)
	card_played_visual.emit(player_name, card, is_use)

func get_counts() -> Dictionary:
	return _hand_counts

func get_hand(player_name: String) -> Array:
	return _hands.get(player_name, [])

func get_playable_cards(active_wrestler: Wrestler, opponent: Wrestler) -> Array[CardData]:
	var result: Array[CardData] = []
	var hand = get_hand(active_wrestler.name)
	if not opponent:
		for c in hand:
			if c.type != CardData.CardType.ATTACK: result.append(c)
		return result
	var d = opponent.grid_position - active_wrestler.grid_position
	for c in hand:
		if c.type != CardData.CardType.ATTACK:
			result.append(c)
		else:
			var dx = abs(d.x); var dy = abs(d.y)
			var ok = false
			if c.pattern == CardData.MovePattern.ORTHOGONAL: ok = (dx + dy == 1)
			elif c.pattern == CardData.MovePattern.DIAGONAL: ok = (dx == 1 and dy == 1)
			elif c.suit == "Joker": ok = (dx <= 1 and dy <= 1 and not (dx == 0 and dy == 0))
			if ok: result.append(c)
	return result

# --- Handlers réseau (appelés par le router dans GameManager) ---

func on_net_receive_card(card_dict: Dictionary) -> void:
	var card = CardData.deserialize(card_dict)
	var my_name = _net.get_my_name()
	if not _hands.has(my_name):
		_hands[my_name] = []
	_hands[my_name].append(card)
	_update_count(my_name, 1)
	card_drawn.emit(card)

func on_net_sync_draw(player_name: String) -> void:
	_update_count(player_name, 1)

func on_net_sync_card_played(card_dict: Dictionary, player_name: String, is_use: bool) -> void:
	var card = CardData.deserialize(card_dict)
	_remove_from_hand(player_name, card)
	_update_count(player_name, -1)
	card_discarded.emit(card)
	card_played_visual.emit(player_name, card, is_use)

func on_net_sync_deck_count(count: int) -> void:
	deck_count_updated.emit(count)

## Hôte : valide et exécute la demande de jeu de carte du client.
func on_net_request_play_card(sender_id: String, card_dict: Dictionary, current_player_name: String) -> void:
	if not _net.is_sender(sender_id, current_player_name):
		return
	var card = CardData.deserialize(card_dict)
	consume_card(current_player_name, card, true)

## Hôte : valide et exécute la demande de défausse du client.
func on_net_request_discard_card(sender_id: String, card_dict: Dictionary, current_player_name: String) -> void:
	if not _net.is_sender(sender_id, current_player_name):
		return
	var card = CardData.deserialize(card_dict)
	consume_card(current_player_name, card, false)

# --- Privé ---

func _on_card_drawn_for(player_name: String, card: CardData) -> void:
	_update_count(player_name, 1)
	if _net.is_hotseat:
		if player_name == _active_player_name:
			card_drawn.emit(card)
		return
	# Mode réseau : l'hôte distribue les cartes
	var target_id = _net.get_id_for_name(player_name)
	if target_id == NetworkManager.self_user_id:
		card_drawn.emit(card)
		_net.send({"type": "SYNC_DRAW", "player_name": player_name})
	else:
		_net.send({
			"type": "RECEIVE_CARD",
			"target_id": target_id,
			"card": CardData.serialize(card)
		})

func _remove_from_hand(player_name: String, card: CardData) -> bool:
	var hand = _hands.get(player_name, [])
	for c in hand:
		if c.title == card.title and c.suit == card.suit:
			hand.erase(c)
			return true
	if not hand.is_empty():
		printerr("HandManager: '", card.title, "' (", card.suit, ") introuvable dans ", player_name)
	return false

func _update_count(player_name: String, delta: int) -> void:
	if not _hand_counts.has(player_name):
		_hand_counts[player_name] = 0
	_hand_counts[player_name] = maxi(0, _hand_counts[player_name] + delta)
	player_hand_counts_updated.emit(_hand_counts)

func _sync_deck_count() -> void:
	if not _deck: return
	var count = _deck.draw_pile.size()
	deck_count_updated.emit(count)
	if _net.am_i_host() and not _net.is_hotseat:
		_net.send({"type": "SYNC_DECK_COUNT", "count": count})
