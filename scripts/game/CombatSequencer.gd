class_name CombatSequencer
extends Node

## Gère toute la séquence attaque → réaction → résultat.
## Seul module autorisé à appeler wrestler.take_damage().

signal reaction_phase_started(attack_card: CardData, valid_cards: Array[CardData])
signal defender_hand_refresh_needed(player_name: String)
signal combat_round_resolved

var can_dodge: bool = false

var _net: NetworkSync
var _hand: HandManager
var _grid  # non typé pour éviter la dépendance cyclique
var _players: Array[Wrestler] = []

var pending_attack_context: Dictionary = {}
var pending_defense_context: Dictionary = {}
var is_waiting_for_reaction: bool = false

func setup(net: NetworkSync, hand: HandManager, grid_manager_ref) -> void:
	_net = net
	_hand = hand
	_grid = grid_manager_ref

func set_players(wrestlers: Array[Wrestler]) -> void:
	_players = wrestlers

# --- API publique (appelée par GridManager via GameManager) ---

func initiate_attack_sequence(target: Wrestler, attack_card: CardData, is_push: bool, attacker_name: String = "") -> void:
	if is_waiting_for_reaction:
		print("⚠️ CombatSequencer: attaque déjà en cours, ignorée.")
		return
	pending_attack_context = {
		"target_name": target.name,
		"attack_card": attack_card,
		"is_push": is_push
	}
	is_waiting_for_reaction = true
	print("⚔️ Attaque initiée contre ", target.name)
	var target_id = _net.get_id_for_name(target.name)
	if _net.is_hotseat:
		var attacker_id = _net.get_id_for_name(attacker_name)
		_handle_request_attack({
			"target_id": target_id,
			"attacker_card": CardData.serialize(attack_card),
			"_sender_id": attacker_id,
			"is_push": is_push
		})
	else:
		_net.send({
			"type": "REQUEST_ATTACK",
			"attacker_card": CardData.serialize(attack_card),
			"target_id": target_id,
			"is_push": is_push
		})

## Appelé par GameUI quand le défenseur choisit une carte de réaction.
func on_reaction_selected(reaction_card: CardData) -> void:
	print("🛡️ Réaction choisie: ", reaction_card.title)
	var attack_card = pending_defense_context.get("attack_card")
	if attack_card and reaction_card.suit == attack_card.suit:
		# BLOCAGE
		_hand.consume_card(_net.get_my_name(), reaction_card, true)
		_send_attack_result(true, reaction_card, false)
	else:
		# ESQUIVE : le mouvement se fait d'abord via GridManager
		if _grid:
			var my_wrestler = _get_wrestler_by_name(_net.get_my_name())
			if my_wrestler:
				_grid.enter_dodge_mode(reaction_card, my_wrestler)

## Appelé par GridManager quand le mouvement d'esquive est complété.
func on_dodge_complete(card: CardData) -> void:
	print("🛡️ Esquive complétée.")
	_hand.consume_card(_net.get_my_name(), card, true)
	_send_attack_result(false, card, true)

## Appelé quand le défenseur n'a pas de réaction valide ou passe.
func on_reaction_skipped() -> void:
	print("🛡️ Réaction ignorée.")
	_send_attack_result(false, null, false)

## Retourne les cartes de la main qui peuvent bloquer/esquiver l'attaque.
func get_valid_reaction_cards(attack_card: CardData, hand: Array) -> Array[CardData]:
	var valid: Array[CardData] = []
	for card in hand:
		if card.tier <= attack_card.tier and card.suit != "Joker":
			continue
		var ok = false
		if card.suit == attack_card.suit:
			ok = true  # Blocage
		if can_dodge and (card.type == CardData.CardType.MOVE or card.suit == "Joker"):
			if attack_card.pattern == CardData.MovePattern.ORTHOGONAL and card.pattern == CardData.MovePattern.DIAGONAL:
				ok = true
			elif attack_card.pattern == CardData.MovePattern.DIAGONAL and card.pattern == CardData.MovePattern.ORTHOGONAL:
				ok = true
		if ok:
			valid.append(card)
	return valid

# --- Handlers réseau (appelés par le router dans GameManager) ---

func on_net_request_attack(data: Dictionary) -> void:
	if not _net.is_hotseat and data["target_id"] != NetworkManager.self_user_id:
		return
	if not pending_defense_context.is_empty():
		print("⚠️ CombatSequencer: déjà en défense, REQUEST_ATTACK ignoré.")
		return
	_handle_request_attack(data)

func on_net_attack_result(data: Dictionary) -> void:
	# Filtre echo : ignorer si on est le défenseur qui a envoyé ce résultat
	if not _net.is_hotseat and data.get("_sender_id") == NetworkManager.self_user_id:
		return
	_handle_attack_result(data)

func on_net_sync_push(data: Dictionary) -> void:
	var target = _get_wrestler_by_name(data.get("target_name", ""))
	if target:
		target.push_to(Vector2i(data["x"], data["y"]))

# --- Privé ---

func _handle_request_attack(data: Dictionary) -> void:
	var attack_card = CardData.deserialize(data["attacker_card"])
	pending_defense_context = {
		"attacker_id": data.get("_sender_id"),
		"target_id": data["target_id"],
		"attack_card": attack_card,
		"is_push": data.get("is_push", false)
	}
	is_waiting_for_reaction = true
	var defender_name = _net.get_name_for_id(data["target_id"])
	if _net.is_hotseat:
		defender_hand_refresh_needed.emit(defender_name)
	var defender_hand = _hand.get_hand(defender_name)
	var valid = get_valid_reaction_cards(attack_card, defender_hand)
	if valid.is_empty():
		print("🛡️ Aucune carte de réaction valide. Dégâts automatiques.")
		_send_attack_result(false, null, false)
	else:
		print("🛡️ Opportunité de réaction (", valid.size(), " cartes valides).")
		reaction_phase_started.emit(attack_card, valid)

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
	pending_defense_context.clear()
	if _net.is_hotseat:
		_handle_attack_result(msg)
	else:
		_net.send(msg)
		_handle_attack_result(msg)

func _handle_attack_result(data: Dictionary) -> void:
	# Sécurité défenseur : évite le double traitement
	if not _net.is_hotseat and data.get("target_id") == NetworkManager.self_user_id:
		if pending_defense_context.is_empty() and not is_waiting_for_reaction:
			print("⚠️ ATTACK_RESULT dupliqué ignoré (côté défenseur).")
			return
		pending_defense_context.clear()

	is_waiting_for_reaction = false
	if _net.is_hotseat:
		combat_round_resolved.emit()

	var attacker = _get_wrestler_by_id(data.get("attacker_id"))
	var target = _get_wrestler_by_id(data.get("target_id"))
	if not attacker or not target: return

	var is_blocked = data.get("is_blocked", false)
	var is_dodged = data.get("is_dodged", false)
	var is_hit = not is_blocked and not is_dodged
	var is_push = bool(data.get("is_push", false))

	if is_blocked:
		print("🛡️ Attaque bloquée !")
		target.show_floating_text("BLOCKED!", Color(1.0, 0.6, 0.0))
	elif is_dodged:
		print("💨 Attaque esquivée !")
		target.show_floating_text("DODGED!", Color(0.0, 0.8, 1.0))
		if target.has_method("play_dodge_sound"):
			target.play_dodge_sound()

	# L'attaquant frappe (dans le vide si bloqué/esquivé)
	attacker.attack(target, is_hit, is_push)

	if is_hit:
		var is_initiator = not pending_attack_context.is_empty()
		# Sécurité attaquant : évite le double traitement
		if not _net.is_hotseat and not is_initiator and _is_local_player(attacker):
			print("⚠️ ATTACK_RESULT dupliqué ignoré (côté attaquant).")
			return
		if is_initiator:
			var is_push_attack = pending_attack_context.get("is_push", false)
			pending_attack_context.clear()
			if is_push_attack:
				_apply_push(attacker, target)
			else:
				await get_tree().create_timer(0.3).timeout
				target.take_damage(1)

func _apply_push(attacker: Wrestler, target: Wrestler) -> void:
	var direction = (target.grid_position - attacker.grid_position).clamp(Vector2i(-1, -1), Vector2i(1, 1))
	var dest = target.grid_position + direction
	print("💨 Poussée de ", target.name, " vers ", dest)
	if _grid and not _grid.is_valid_cell(dest):
		target.take_damage(2)  # Ring Out
	target.push_to(dest)
	_net.send({
		"type": "SYNC_PUSH",
		"target_name": target.name,
		"x": dest.x,
		"y": dest.y
	})

func _get_wrestler_by_id(peer_id) -> Wrestler:
	if peer_id == null: return null
	var pname = _net.get_name_for_id(peer_id)
	return _get_wrestler_by_name(pname)

func _get_wrestler_by_name(pname: String) -> Wrestler:
	for w in _players:
		if w.name == pname: return w
	return null

func _get_active_name() -> String:
	# Utilisé uniquement en hotseat pour simuler l'attaquant
	for w in _players:
		if w: return w.name
	return ""

func _is_local_player(wrestler: Wrestler) -> bool:
	return _net.get_my_name() == wrestler.name
