class_name TurnManager
extends Node

## Gère la séquence des tours : début, fin, pioche, pénalité AFK.
## Seul module autorisé à avancer active_player_index.

signal turn_started(player_name: String)
signal turn_ended
signal afk_penalty_triggered(player_name: String)

var _net: NetworkSync
var _hand: HandManager
var _players: Array[Wrestler] = []

var active_player_index: int = 0
var has_acted_this_turn: bool = false
var is_game_active: bool = false

func setup(net: NetworkSync, hand: HandManager) -> void:
	_net = net
	_hand = hand

func set_players(wrestlers: Array[Wrestler]) -> void:
	_players = wrestlers

## Lance la première séquence de jeu après spawn des wrestlers.
func start_game() -> void:
	is_game_active = true
	active_player_index = 0
	_start_turn()

## Appelé par le bouton "End Turn" (via GameManager).
func end_turn() -> void:
	if not is_game_active: return
	if _net.is_hotseat:
		_server_process_end_turn()
		return
	var host_id = _net.get_id_for_name(_players[0].name)
	if NetworkManager.self_user_id != host_id:
		_net.send({"type": "REQUEST_END_TURN"})
		return
	if is_local_player_active():
		_server_process_end_turn()

## Vrai si c'est au joueur local de jouer.
func is_local_player_active() -> bool:
	if not _net: return false
	if _net.is_hotseat: return true
	if _players.is_empty(): return false
	var current_name = _players[active_player_index].name
	return _net.get_id_for_name(current_name) == NetworkManager.self_user_id

func get_active_wrestler() -> Wrestler:
	if _players.is_empty() or active_player_index >= _players.size(): return null
	return _players[active_player_index]

func get_active_player_name() -> String:
	var w = get_active_wrestler()
	return w.name if w else ""

# --- Handlers réseau (appelés par le router dans GameManager) ---

func on_net_sync_turn(player_name: String) -> void:
	is_game_active = true
	_handle_sync_turn(player_name)

func on_net_request_end_turn(sender_id: String) -> void:
	if _net.is_sender(sender_id, get_active_player_name()):
		_server_process_end_turn()

# --- Privé ---

func _start_turn() -> void:
	has_acted_this_turn = false
	var current = _players[active_player_index]
	print("TurnManager: Début du tour — ", current.name)
	_handle_sync_turn(current.name)
	_net.send({"type": "SYNC_TURN", "player_name": current.name})
	if _net.am_i_host():
		_hand.set_active_player(current.name)
		_hand.draw_turn_cards(current.name)

func _handle_sync_turn(player_name: String) -> void:
	for i in range(_players.size()):
		if _players[i].name == player_name:
			active_player_index = i
			break
	turn_started.emit(player_name)

func _server_process_end_turn() -> void:
	if not has_acted_this_turn:
		print("🍅 AFK Penalty: ", get_active_player_name())
		afk_penalty_triggered.emit(get_active_player_name())
	turn_ended.emit()
	active_player_index = (active_player_index + 1) % _players.size()
	_start_turn()
