class_name GameManager
extends Node

# --- Signaux (proxies des sous-systèmes + signaux propres) ---
signal turn_started(player_name: String)
signal card_drawn(card: CardData)
signal card_discarded(card: CardData)
signal turn_ended
signal reaction_phase_started(attack_card: CardData, valid_cards: Array[CardData])
signal grid_action_received(data: Dictionary)
signal rematch_update(current_votes: int, total_required: int)
signal refresh_hand_requested(player_name: String)
signal game_over(winner_name: String)
signal game_paused(paused: bool, initiator_name: String)
signal versus_screen_requested(local_data: WrestlerData, remote_data: WrestlerData)
signal opponent_skipped_versus
signal player_hand_counts_updated(counts: Dictionary)
signal card_played_visual(player_name: String, card: CardData, is_use: bool)
signal combo_changed(position: int)
signal deck_count_updated(count: int)

@export var character_pool: Array[WrestlerData]
@export var enable_hotseat_mode: bool = false
@export var can_dodge: bool = false

# --- Sous-systèmes ---
var network_sync: NetworkSync
var hand_manager: HandManager
var turn_manager: TurnManager
var combat_sequencer: CombatSequencer

# --- Dépendances injectées par Arena ---
var deck_manager: DeckManager
var grid_manager  # non typé pour éviter la dépendance cyclique

# --- État ---
var players: Array[Wrestler] = []
var rematch_votes: Dictionary = {}
var players_in_pause: Array[String] = []
var is_intro_finished: bool = false

# Propriétés de compatibilité (Arena.gd et GameUI.gd y accèdent directement)
var is_game_active: bool:
	get: return turn_manager.is_game_active if turn_manager else false
	set(v):
		if turn_manager: turn_manager.is_game_active = v

var is_network_syncing: bool:
	get: return network_sync.is_network_syncing if network_sync else false

var player_hand_counts: Dictionary:
	get: return hand_manager.get_counts() if hand_manager else {}

var active_player_index: int:
	get: return turn_manager.active_player_index if turn_manager else 0

var pending_defense_context: Dictionary:
	get: return combat_sequencer.pending_defense_context if combat_sequencer else {}

var player_peer_ids: Dictionary:
	get: return network_sync.player_peer_ids if network_sync else {}

func _ready() -> void:
	_create_subsystems()
	NetworkManager.game_message_received.connect(_on_network_message)

func _create_subsystems() -> void:
	network_sync = NetworkSync.new()
	network_sync.name = "NetworkSync"
	add_child(network_sync)

	hand_manager = HandManager.new()
	hand_manager.name = "HandManager"
	add_child(hand_manager)

	turn_manager = TurnManager.new()
	turn_manager.name = "TurnManager"
	add_child(turn_manager)

	combat_sequencer = CombatSequencer.new()
	combat_sequencer.name = "CombatSequencer"
	combat_sequencer.can_dodge = can_dodge
	add_child(combat_sequencer)

func _wire_subsystems() -> void:
	# Proxies des signaux des sous-systèmes
	hand_manager.card_drawn.connect(card_drawn.emit)
	hand_manager.card_discarded.connect(card_discarded.emit)
	hand_manager.card_played_visual.connect(card_played_visual.emit)
	hand_manager.deck_count_updated.connect(deck_count_updated.emit)
	hand_manager.player_hand_counts_updated.connect(player_hand_counts_updated.emit)
	hand_manager.deck_empty_detected.connect(_on_deck_empty)

	turn_manager.turn_started.connect(turn_started.emit)
	turn_manager.turn_ended.connect(turn_ended.emit)
	turn_manager.afk_penalty_triggered.connect(_on_afk_penalty)
	turn_manager.combo_changed.connect(combo_changed.emit)

	hand_manager.card_played_visual.connect(_on_card_played_for_combo)

	combat_sequencer.reaction_phase_started.connect(reaction_phase_started.emit)
	combat_sequencer.defender_hand_refresh_needed.connect(refresh_hand_requested.emit)
	combat_sequencer.combat_round_resolved.connect(func():
		refresh_hand_requested.emit(turn_manager.get_active_player_name())
	)

# ============================================================
# INITIALISATION
# ============================================================

func initialize_network(deck_mgr: DeckManager) -> void:
	deck_manager = deck_mgr
	# Setup immédiat des sous-systèmes pour qu'ils soient prêts dès le VersusScreen
	hand_manager.setup(deck_manager, network_sync)
	turn_manager.setup(network_sync, hand_manager)
	combat_sequencer.setup(network_sync, hand_manager, grid_manager)
	combat_sequencer.can_dodge = can_dodge
	_wire_subsystems()

	if enable_hotseat_mode:
		network_sync.setup_hotseat()
		_server_select_and_sync_characters()
	else:
		network_sync.setup_network()
		_resolve_character_selections()

func initialize_game_state() -> void:
	if not grid_manager or grid_manager.wrestlers.is_empty():
		printerr("GameManager: wrestlers absents à l'initialisation.")
		return

	players = grid_manager.wrestlers
	turn_manager.set_players(players)
	combat_sequencer.set_players(players)

	if network_sync.am_i_host():
		deck_manager.initialize_deck()
		hand_manager.set_active_player(players[0].name)
		hand_manager.initialize_hands(players.map(func(w): return w.name))
		turn_manager.start_game()

func start_match_after_versus() -> void:
	initialize_game_state()

# ============================================================
# FAÇADE — API PUBLIQUE (Arena, GameUI, GridManager y accèdent)
# ============================================================

func is_in_hotseat_mode() -> bool:
	return enable_hotseat_mode

func get_my_name() -> String:
	return network_sync.get_my_name()

func is_local_player_active() -> bool:
	return turn_manager.is_local_player_active()

func get_active_wrestler() -> Wrestler:
	return turn_manager.get_active_wrestler()

func get_player_hand(player_name: String) -> Array:
	return hand_manager.get_hand(player_name)

func get_playable_cards_in_hand() -> Array[CardData]:
	var active = turn_manager.get_active_wrestler()
	if not active: return []
	var opponent: Wrestler = null
	for p in players:
		if p != active: opponent = p; break
	return hand_manager.get_playable_cards(active, opponent)

func end_turn() -> void:
	if not is_game_active: return
	if combat_sequencer.is_waiting_for_reaction:
		print("⚠️ Fin de tour bloquée : réaction en attente.")
		return
	turn_manager.end_turn()

func use_card(card: CardData) -> bool:
	if not is_game_active or not is_local_player_active(): return false
	if combat_sequencer.is_waiting_for_reaction: return false
	turn_manager.has_acted_this_turn = true
	var player_name = turn_manager.get_active_player_name()
	if enable_hotseat_mode:
		hand_manager.consume_card(player_name, card, true)
		return true
	if not network_sync.am_i_host():
		# Optimistic UI : retrait immédiat côté client avant confirmation serveur
		hand_manager.remove_for_optimistic_ui(player_name, card, true)
		network_sync.send({
			"type": "REQUEST_PLAY_CARD",
			"card": CardData.serialize(card)
		})
		return true
	hand_manager.consume_card(player_name, card, true)
	return true

func discard_hand_card(card: CardData) -> void:
	if not is_game_active or not is_local_player_active(): return
	turn_manager.has_acted_this_turn = true
	var player_name = turn_manager.get_active_player_name()
	if enable_hotseat_mode:
		hand_manager.consume_card(player_name, card, false)
		return
	if not network_sync.am_i_host():
		hand_manager.remove_for_optimistic_ui(player_name, card, false)
		network_sync.send({
			"type": "REQUEST_DISCARD_CARD",
			"card": CardData.serialize(card)
		})
		return
	hand_manager.consume_card(player_name, card, false)

func on_reaction_selected(card: CardData) -> void:
	combat_sequencer.on_reaction_selected(card)

func on_reaction_skipped() -> void:
	combat_sequencer.on_reaction_skipped()

func on_dodge_complete(card: CardData) -> void:
	combat_sequencer.on_dodge_complete(card)

func get_current_combo_effect() -> ComboEffect:
	return turn_manager.get_current_combo_effect()

func get_next_combo_effect() -> ComboEffect:
	return turn_manager.get_next_combo_effect()

func get_last_combo_tier() -> int:
	return turn_manager.get_last_combo_tier()

func initiate_attack_sequence(target: Wrestler, attack_card: CardData, is_push: bool = false) -> void:
	turn_manager.has_acted_this_turn = true
	var effect := turn_manager.get_current_combo_effect()
	combat_sequencer.initiate_attack_sequence(target, attack_card, is_push, turn_manager.get_active_player_name(), effect)

func apply_combo_push(attacker: Wrestler, target: Wrestler, push_direction: Vector2i, push_damage: int = 0, execute_immediately: bool = false) -> void:
	combat_sequencer.apply_combo_push(attacker, target, push_direction, push_damage, execute_immediately)

func send_grid_action(action_data: Dictionary) -> void:
	network_sync.send({"type": "SYNC_GRID_ACTION", "action_data": action_data})

func send_health_update(wrestler_name: String, new_health: int) -> void:
	network_sync.send({
		"type": "SYNC_HEALTH",
		"player_name": wrestler_name,
		"value": new_health
	})

func send_floating_text(wrestler_name: String, text: String, color: Color) -> void:
	for p in players:
		if p.name == wrestler_name:
			p.show_floating_text(text, color)
			break
	network_sync.send({
		"type": "SYNC_FLOATING_TEXT",
		"player_name": wrestler_name,
		"text": text,
		"color": color.to_html()
	})

func send_skip_versus() -> void:
	if enable_hotseat_mode:
		opponent_skipped_versus.emit()
		return
	network_sync.send({"type": "SYNC_SKIP_VERSUS"})

func preview_swipe(card: CardData, screen_offset: Vector2) -> bool:
	if grid_manager and (is_local_player_active() or not combat_sequencer.pending_defense_context.is_empty()):
		return grid_manager.handle_swipe_preview(card, screen_offset)
	return false

func commit_swipe(card: CardData, screen_offset: Vector2, global_pos: Vector2) -> bool:
	if grid_manager and (is_local_player_active() or not combat_sequencer.pending_defense_context.is_empty()):
		return grid_manager.handle_swipe_commit(card, screen_offset, global_pos)
	return false

func set_wrestler_collisions(enabled: bool) -> void:
	if grid_manager:
		grid_manager.set_wrestler_collisions(enabled)

func request_pause(wants_pause: bool) -> void:
	var my_name = network_sync.get_my_name()
	_handle_sync_pause(my_name, wants_pause)
	network_sync.send({"type": "SYNC_PAUSE", "paused": wants_pause, "player_name": my_name})

func request_restart() -> void:
	var my_name = network_sync.get_my_name()
	if rematch_votes.has(my_name): return
	_handle_rematch_vote(my_name)
	network_sync.send({"type": "REQUEST_RESTART_VOTE", "player_name": my_name})

func mark_intro_finished() -> void:
	is_intro_finished = true
	_apply_pause_state()

# ============================================================
# ROUTEUR RÉSEAU
# ============================================================

func _on_network_message(data: Dictionary) -> void:
	if enable_hotseat_mode: return
	match data["type"]:
		# --- HandManager ---
		"RECEIVE_CARD":
			if data["target_id"] == NetworkManager.self_user_id:
				hand_manager.on_net_receive_card(data.get("card", {}))
			else:
				var target_name = network_sync.get_name_for_id(data["target_id"])
				if not target_name.is_empty(): hand_manager.on_net_sync_draw(target_name)
		"SYNC_DRAW":
			hand_manager.on_net_sync_draw(data["player_name"])
		"SYNC_CARD_PLAYED":
			if data["player_name"] != network_sync.get_my_name():
				hand_manager.on_net_sync_card_played(data.get("card", {}), data["player_name"], data.get("is_use", true))
		"SYNC_DECK_COUNT":
			hand_manager.on_net_sync_deck_count(data.get("count", 0))
		"REQUEST_PLAY_CARD":
			var _sender = data.get("_sender_id", "")
			if network_sync.is_sender(_sender, turn_manager.get_active_player_name()):
				turn_manager.has_acted_this_turn = true
			hand_manager.on_net_request_play_card(_sender, data.get("card", {}), turn_manager.get_active_player_name())
		"REQUEST_DISCARD_CARD":
			var _sender = data.get("_sender_id", "")
			if network_sync.is_sender(_sender, turn_manager.get_active_player_name()):
				turn_manager.has_acted_this_turn = true
			hand_manager.on_net_request_discard_card(_sender, data.get("card", {}), turn_manager.get_active_player_name())
		# --- TurnManager ---
		"SYNC_TURN":
			turn_manager.on_net_sync_turn(data["player_name"])
		"REQUEST_END_TURN":
			turn_manager.on_net_request_end_turn(data.get("_sender_id", ""))
		# --- CombatSequencer ---
		"REQUEST_ATTACK":
			var _sender = data.get("_sender_id", "")
			if network_sync.is_sender(_sender, turn_manager.get_active_player_name()):
				turn_manager.has_acted_this_turn = true
			var net_effect := ComboEffect.new()
			net_effect.is_unblockable = data.get("combo_unblockable", false)
			net_effect.block_tier_bonus = int(data.get("combo_block_bonus", 0))
			combat_sequencer.on_net_request_attack(data, net_effect)
		"ATTACK_RESULT":
			combat_sequencer.on_net_attack_result(data)
		"SYNC_PUSH":
			combat_sequencer.on_net_sync_push(data)
		# --- GameManager (état global) ---
		"SYNC_GRID_ACTION":
			grid_action_received.emit(data["action_data"])
		"SYNC_HEALTH":
			_handle_sync_health(data["player_name"], data["value"])
		"SYNC_FLOATING_TEXT":
			_handle_sync_floating_text(data["player_name"], data["text"], data["color"])
		"SYNC_CHARACTERS":
			_handle_character_selection(data["p1_path"], data["p2_path"])
		"GAME_OVER_DECK_EMPTY":
			turn_manager.is_game_active = false
			game_over.emit(data["winner"])
		"REQUEST_RESTART_VOTE":
			_handle_rematch_vote(data["player_name"])
		"SYNC_PAUSE":
			_handle_sync_pause(data["player_name"], data["paused"])
		"SYNC_SKIP_VERSUS":
			opponent_skipped_versus.emit()

# ============================================================
# HANDLERS D'ÉTAT GLOBAL (restent dans GameManager)
# ============================================================

func _on_card_played_for_combo(player_name: String, card: CardData, is_use: bool) -> void:
	if not is_use: return
	if player_name != turn_manager.get_active_player_name(): return
	# En réseau, le signal arrive sur les 2 appareils via SYNC_CARD_PLAYED.
	# On ne compte le combo que si c'est notre carte (joueur local).
	if not network_sync.is_hotseat and player_name != network_sync.get_my_name(): return
	turn_manager.register_card_played(card)

func _on_afk_penalty(player_name: String) -> void:
	send_floating_text(player_name, "AFK PENALTY!", Color(1.0, 0.5, 0.0))
	for p in players:
		if p.name == player_name:
			p.take_damage(1, false, true)
			break

func _on_deck_empty() -> void:
	if not is_game_active: return
	turn_manager.is_game_active = false
	var p1 = players[0]; var p2 = players[1]
	var winner = "DRAW"
	if p1.current_health > p2.current_health: winner = p1.name
	elif p2.current_health > p1.current_health: winner = p2.name
	game_over.emit(winner)
	network_sync.send({"type": "GAME_OVER_DECK_EMPTY", "winner": winner})

func _handle_sync_health(player_name: String, value: int) -> void:
	network_sync.is_network_syncing = true
	for p in players:
		if p.name == player_name:
			p.set_network_health(value)
			break
	network_sync.is_network_syncing = false

func _handle_sync_floating_text(player_name: String, text: String, color_html: String) -> void:
	var color = Color.from_string(color_html, Color.WHITE)
	for p in players:
		if p.name == player_name:
			p.show_floating_text(text, color)
			break

func _handle_sync_pause(player_name: String, paused: bool) -> void:
	if paused and not players_in_pause.has(player_name):
		players_in_pause.append(player_name)
	elif not paused and players_in_pause.has(player_name):
		players_in_pause.erase(player_name)
	_apply_pause_state()

func _apply_pause_state() -> void:
	if not is_intro_finished: return
	var should_pause = not players_in_pause.is_empty()
	get_tree().paused = should_pause
	game_paused.emit(should_pause, "")

func _handle_rematch_vote(player_name: String) -> void:
	if rematch_votes.has(player_name): return
	rematch_votes[player_name] = true
	print("🔄 Vote rematch: ", player_name)
	var required = 2 if enable_hotseat_mode else NetworkManager.match_presences.size() + 1
	if rematch_votes.size() >= required:
		get_tree().change_scene_to_file("res://scenes/Arena.tscn")
	else:
		rematch_update.emit(rematch_votes.size(), required)

# ============================================================
# SÉLECTION DES PERSONNAGES
# ============================================================

func _resolve_character_selections() -> void:
	var p1_id = network_sync.get_id_for_name("Player 1")
	var p2_id = network_sync.get_id_for_name("Player 2")
	var p1_path: String = NetworkManager.character_selections.get(p1_id, "")
	var p2_path: String = NetworkManager.character_selections.get(p2_id, "")
	if p1_path.is_empty() or p2_path.is_empty():
		printerr("GameManager: sélection de personnage manquante (CharacterSelect non passé ?), fallback aléatoire.")
		_server_select_and_sync_characters()
		return
	_handle_character_selection(p1_path, p2_path)

func _server_select_and_sync_characters() -> void:
	if character_pool.size() < 2:
		printerr("GameManager: character_pool doit contenir au moins 2 personnages.")
		return
	character_pool.shuffle()
	var p1_path = character_pool[0].resource_path
	var p2_path = character_pool[1].resource_path
	if enable_hotseat_mode:
		_handle_character_selection(p1_path, p2_path)
	else:
		network_sync.send({"type": "SYNC_CHARACTERS", "p1_path": p1_path, "p2_path": p2_path})
		_handle_character_selection(p1_path, p2_path)

func _handle_character_selection(p1_path: String, p2_path: String) -> void:
	if not grid_manager: return
	var p1_res = load(p1_path)
	var p2_res = load(p2_path)
	if not p1_res or not p2_res:
		printerr("GameManager: échec du chargement des ressources personnages.")
		return
	print("Personnages sélectionnés: P1=", p1_res.display_name, " P2=", p2_res.display_name)
	grid_manager.spawn_wrestlers(p1_res, p2_res)
	var local = p1_res
	var remote = p2_res
	if network_sync.get_my_name() == "Player 2":
		local = p2_res; remote = p1_res
	versus_screen_requested.emit(local, remote)
