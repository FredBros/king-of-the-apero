class_name NetworkSync
extends Node

## Seul module autorisé à appeler NetworkManager.send_message().
## Seul module qui connaît la correspondance nom_joueur <-> peer_id.

var player_peer_ids: Dictionary = {}
var is_hotseat: bool = false

## Flag pour éviter les boucles réseau (ex: SYNC_HEALTH reçu → health_changed → SYNC_HEALTH renvoyé)
var is_network_syncing: bool = false

func setup_hotseat() -> void:
	is_hotseat = true
	player_peer_ids = {
		"Player 1": "hotseat_p1",
		"Player 2": "hotseat_p2"
	}

func setup_network() -> void:
	is_hotseat = false
	player_peer_ids.clear()
	var all_ids: Array = [NetworkManager.self_user_id]
	for uid in NetworkManager.match_presences:
		all_ids.append(uid)
	all_ids.sort()
	if all_ids.size() > 0: player_peer_ids["Player 1"] = all_ids[0]
	if all_ids.size() > 1: player_peer_ids["Player 2"] = all_ids[1]
	else: player_peer_ids["Player 2"] = all_ids[0]

## Point d'entrée unique pour envoyer un message réseau.
func send(data: Dictionary) -> void:
	if not is_hotseat:
		NetworkManager.send_message(data)

## Vrai si le client local est l'hôte (Player 1 / pseudo-host P2P).
func am_i_host() -> bool:
	if is_hotseat: return true
	return NetworkManager.self_user_id == player_peer_ids.get("Player 1", "")

## Retourne le nom du joueur local ("Player 1" ou "Player 2").
func get_my_name() -> String:
	if is_hotseat: return "Player 1"
	var my_id = NetworkManager.self_user_id
	for pname in player_peer_ids:
		if player_peer_ids[pname] == my_id:
			return pname
	return ""

func get_name_for_id(peer_id) -> String:
	if peer_id == null: return ""
	for pname in player_peer_ids:
		if player_peer_ids[pname] == peer_id:
			return pname
	return ""

func get_id_for_name(pname: String):
	return player_peer_ids.get(pname)

## Vérifie que sender_id correspond bien au joueur player_name (sécurité anti-triche réseau).
func is_sender(sender_id: String, player_name: String) -> bool:
	return player_peer_ids.get(player_name, "") == sender_id
