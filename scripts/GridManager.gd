class_name GridManager
extends Node2D

signal game_over(winner_name: String)
signal wrestlers_spawned(wrestlers: Array[Wrestler])

# Reference to the Game Manager (injected by Arena)
var game_manager: # Untyped to avoid cyclic dependency
	set(value):
		game_manager = value
		if game_manager:
			if not game_manager.grid_action_received.is_connected(_on_grid_action_received):
				game_manager.grid_action_received.connect(_on_grid_action_received)

# Scene reference for the wrestler pawn. We'll link this in the editor.
@export var wrestler_scene: PackedScene

# Reference to the currently active wrestler for testing inputs
var active_wrestler: Wrestler

# List of all wrestlers on board
var wrestlers: Array[Wrestler] = []

# The card currently selected by the player
var current_card: CardData

# Grid configuration
@export var grid_size: Vector2i = Vector2i(6, 6) # 6x6 grid
@export var cell_size: float = 16.0 # Each cell is one 16x16 tile (unscaled)

# When true, mirrors the grid<->world mapping so the local player always ends up
# near the bottom of the screen (replaces the old "rotate the 3D camera" trick).
# Repositions any already-spawned wrestlers on change, since Arena may set this
# before or after spawn_wrestlers() depending on hotseat vs. networked timing.
@export var perspective_flip: bool = false:
	set(value):
		perspective_flip = value
		for w in wrestlers:
			w.position = grid_to_world(w.grid_position)

# Chance that a crack overlay is drawn on top of a base tile (purely cosmetic, no gameplay impact)
@export var crack_chance: float = 0.5

const RING_TILESET = preload("res://assets/Ring/ring_tileset.tres")

# Offset to center the grid in the world (0,0)
var board_offset: Vector2

# Validation and Highlighting
var valid_cells: Array[Vector2i] = []
var highlight_instances: Array[Sprite2D] = []
var highlight_color_move := Color(0.4, 0.6, 1.0, 0.5) # Blue transparent
var highlight_color_attack := Color(1.0, 0.4, 0.4, 0.5) # Red transparent
var active_indicator: Sprite2D
var swipe_highlight: Sprite2D

var _highlight_texture: ImageTexture

var is_dodging: bool = false
var dodging_wrestler: Wrestler

# Conteneur dédié aux catcheurs avec Y-sort activé : celui qui est visuellement plus bas
# à l'écran se dessine devant l'autre (illusion de profondeur en top-down).
var wrestlers_container: Node2D

func _ready() -> void:
	_calculate_offset()
	_init_active_indicator()
	_init_swipe_highlight()
	_init_wrestlers_container()
	# Debug: Print the world position of the first cell (0,0)
	print("Grid initialized. Cell (0,0) is at World Pos: ", grid_to_world(Vector2i(0, 0)))
	_build_ring_visuals()

func _init_wrestlers_container() -> void:
	wrestlers_container = Node2D.new()
	wrestlers_container.name = "Wrestlers"
	wrestlers_container.y_sort_enabled = true
	add_child(wrestlers_container)

func _unhandled_input(event: InputEvent) -> void:
	# Handle mouse click on the grid
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_grid_click(event.position)

# Called by the Game Loop/UI when a card is selected
func on_card_selected(card: CardData) -> void:
	current_card = card
	if not card:
		_clear_highlights()
		return

	print("GridManager received card: ", card.title)

	# Empêcher l'affichage des déplacements si ce n'est pas notre tour
	if game_manager and not game_manager.is_local_player_active():
		return

	_calculate_valid_cells()
	_update_highlights()

func on_card_discarded(card: CardData) -> void:
	if current_card == card:
		_clear_highlights()
		current_card = null

func on_card_dropped_on_world(card: CardData, screen_pos: Vector2) -> void:
	# Handle Push Mechanic (Drag & Drop)
	if not active_wrestler: return
	if game_manager and not game_manager.is_local_player_active(): return

	var clicked_cell = _get_cell_under_mouse(screen_pos)
	var target = _get_wrestler_at(clicked_cell)

	# 1. PUSH LOGIC (Drop sur un adversaire)
	if target and target != active_wrestler:
		# Check Range (Must be adjacent)
		var diff = (target.grid_position - active_wrestler.grid_position).abs()
		var is_valid_range = false
		if card.suit == "Joker":
			if max(diff.x, diff.y) == 1: is_valid_range = true
		elif card.pattern == CardData.MovePattern.ORTHOGONAL:
			if diff.x + diff.y == 1: is_valid_range = true
		elif card.pattern == CardData.MovePattern.DIAGONAL:
			if diff.x == 1 and diff.y == 1: is_valid_range = true

		if is_valid_range:
			print("Initiating Push Attack on ", target.name)
			active_wrestler.look_at_target(grid_to_world(clicked_cell))
			_consume_card(card, false)
			game_manager.initiate_attack_sequence(target, card, true) # is_push = true
			return
		else:
			print("Target out of range for Push")
			return

	# 2. SWIPE LOGIC (Drop dans le vide -> Attaque Standard)
	# On cherche une cible valide automatiquement
	var valid_targets = _find_valid_targets_for_attack(active_wrestler, card)

	if valid_targets.size() == 1:
		var auto_target = valid_targets[0]
		print("Swipe Attack (Auto-Target) on ", auto_target.name)
		active_wrestler.look_at_target(grid_to_world(auto_target.grid_position))
		_consume_card(card, false)
		game_manager.initiate_attack_sequence(auto_target, card, false) # is_push = false
	elif valid_targets.size() > 1:
		print("Swipe Ambiguous: Multiple targets. Please select card then click target.")
		# Optionnel : Sélectionner la carte pour montrer les cibles
		on_card_selected(card)
	else:
		print("Swipe Failed: No targets in range.")

func _find_valid_targets_for_attack(attacker: Wrestler, card: CardData) -> Array[Wrestler]:
	var targets: Array[Wrestler] = []
	var is_joker = card.suit == "Joker"

	for w in wrestlers:
		if w == attacker: continue

		var diff = (w.grid_position - attacker.grid_position).abs()
		var is_valid_pos = false

		if is_joker:
			if max(diff.x, diff.y) == 1: is_valid_pos = true
		elif card.pattern == CardData.MovePattern.ORTHOGONAL:
			if diff.x + diff.y == 1: is_valid_pos = true
		elif card.pattern == CardData.MovePattern.DIAGONAL:
			if diff.x == 1 and diff.y == 1: is_valid_pos = true

		if is_valid_pos:
			targets.append(w)

	return targets

# Called by GameManager when turn changes
func set_active_wrestler(wrestler: Wrestler) -> void:
	active_wrestler = wrestler
	_clear_highlights()
	current_card = null
	_update_active_indicator()

func _get_highlight_texture() -> ImageTexture:
	if not _highlight_texture:
		var img = Image.create(int(cell_size), int(cell_size), false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_highlight_texture = ImageTexture.create_from_image(img)
	return _highlight_texture

func _init_active_indicator() -> void:
	active_indicator = Sprite2D.new()
	active_indicator.texture = _get_highlight_texture()
	active_indicator.modulate = Color(0.2, 1.0, 0.2, 0.6) # Green transparent
	# z_index=0 (défaut) : reste au-dessus des tuiles (dessinées avant), mais en-dessous du
	# sprite du catcheur puisque celui-ci passe à z_index=1 (cf. Wrestler._setup_outline_shader).

func _init_swipe_highlight() -> void:
	swipe_highlight = Sprite2D.new()
	swipe_highlight.texture = _get_highlight_texture()
	swipe_highlight.modulate = Color(1.0, 1.0, 0.0, 0.6) # Yellow/Gold
	swipe_highlight.z_index = 1
	add_child(swipe_highlight)
	swipe_highlight.hide()

func _update_active_indicator() -> void:
	if not active_indicator: return

	if active_indicator.get_parent():
		active_indicator.get_parent().remove_child(active_indicator)

	if active_wrestler:
		active_wrestler.add_child(active_indicator)
		active_indicator.position = Vector2.ZERO

func _handle_grid_click(screen_pos: Vector2) -> void:
	var actor = _get_acting_wrestler()
	if not actor or not current_card:
		return

	# Empêcher l'input si ce n'est pas notre tour, SAUF si on est en train d'esquiver
	if game_manager and not game_manager.is_local_player_active() and not is_dodging:
		return

	var clicked_cell = _get_cell_under_mouse(screen_pos)

	if not is_valid_cell(clicked_cell):
		return

	print("Clicked cell: ", clicked_cell)

	# Strict Validation: Check if the cell is in the pre-calculated valid list
	if not clicked_cell in valid_cells:
		print("Invalid move/target!")
		return

	# Capture card locally because _execute_action -> _consume_card sets current_card to null
	var card_to_play = current_card

	# Send to network FIRST to ensure order (GridAction before Health Update)
	var action_data = {
		"x": clicked_cell.x,
		"y": clicked_cell.y,
		"card": CardData.serialize(card_to_play),
		"player_name": actor.name # On précise QUI bouge
	}
	game_manager.send_grid_action(action_data)

	# Execute locally
	_execute_action(clicked_cell, card_to_play, false, actor.name)

	# Si on était en mode esquive, on notifie la fin
	if is_dodging:
		is_dodging = false
		dodging_wrestler = null
		if game_manager:
			game_manager.on_dodge_complete(card_to_play)

	# Cleanup local
	_clear_highlights()
	if swipe_highlight: swipe_highlight.hide()
	current_card = null

func _on_grid_action_received(data: Dictionary) -> void:
	print("DEBUG: Grid action received: ", data)
	var cell = Vector2i(data.x, data.y)
	var card = CardData.deserialize(data.card)
	var player_name = data.get("player_name", "")
	_execute_action(cell, card, true, player_name) # is_remote = true

func _execute_action(clicked_cell: Vector2i, card: CardData, is_remote: bool = false, actor_name: String = "") -> void:
	var actor = active_wrestler
	if actor_name != "":
		actor = _get_wrestler_by_name(actor_name)

	if not actor: return

	var is_joker = card.suit == "Joker"
	var target = _get_wrestler_at(clicked_cell)

	# Logic based on card type
	if target:
		if card.type == CardData.CardType.ATTACK or is_joker:
			# On ne fait face à la cible que pour une attaque (un déplacement ne doit pas
			# faire flip le sprite vers la case de destination : cf. feedback utilisateur)
			actor.look_at_target(grid_to_world(clicked_cell))
			_consume_card(card, is_remote)
			if not is_remote:
				game_manager.initiate_attack_sequence(target, card, false)
		elif card.type == CardData.CardType.MOVE:
			# push_and_follow (combo 4) : MOVE vers la case de l'adversaire
			var prev_pos = actor.grid_position
			actor.move_to_grid_position(clicked_cell)
			_consume_card(card, is_remote)
			if not is_remote and game_manager:
				# get_current : après _consume_card, combo_position est déjà avancé — l'effet correspond à la carte jouée
				var effect = game_manager.get_current_combo_effect()
				if effect and effect.push_and_follow:
					var push_dir = (clicked_cell - prev_pos).sign()
					game_manager.apply_combo_push(actor, target, push_dir, effect.push_damage, true)
	elif card.type == CardData.CardType.MOVE or is_joker:
		actor.move_to_grid_position(clicked_cell)
		_consume_card(card, is_remote)

func _calculate_valid_cells() -> void:
	valid_cells.clear()
	var actor = _get_acting_wrestler()
	if not actor or not current_card:
		return

	var is_joker = current_card.suit == "Joker"

	# free_direction / push_follow : prédit la prochaine position de combo (carte pas encore jouée).
	var free_direction := false
	var push_and_follow := false
	# get_next : carte pas encore jouée — prédit l'effet de la prochaine position combo pour les highlights
	if game_manager and not is_dodging:
		var effect = game_manager.get_next_combo_effect()
		if effect:
			free_direction = effect.free_direction
			push_and_follow = effect.push_and_follow

	if current_card.type == CardData.CardType.MOVE or is_joker:
		# Check all cells within range
		var range_val = 1
		for x in range(-range_val, range_val + 1):
			for y in range(-range_val, range_val + 1):
				var offset = Vector2i(x, y)
				var target_pos = actor.grid_position + offset

				if not is_valid_cell(target_pos): continue

				# Check Pattern (Orthogonal vs Diagonal)
				var valid_pattern = false
				if is_joker or free_direction:
					valid_pattern = true
				elif current_card.pattern == CardData.MovePattern.ORTHOGONAL:
					if offset.x == 0 or offset.y == 0: valid_pattern = true
				elif current_card.pattern == CardData.MovePattern.DIAGONAL:
					if abs(offset.x) == abs(offset.y): valid_pattern = true

				if not valid_pattern: continue

				var diff = offset.abs()

				# Distance Check (Range 1)
				var valid_dist = false
				if is_joker or free_direction:
					if diff.x <= 1 and diff.y <= 1 and (diff.x + diff.y > 0): valid_dist = true
				elif current_card.pattern == CardData.MovePattern.ORTHOGONAL:
					if diff.x + diff.y == 1: valid_dist = true
				elif current_card.pattern == CardData.MovePattern.DIAGONAL:
					if diff.x == 1 and diff.y == 1: valid_dist = true

				if valid_dist:
					var wrestler_at_pos = _get_wrestler_at(target_pos)
					if wrestler_at_pos == null:
						valid_cells.append(target_pos)
					elif push_and_follow and wrestler_at_pos != actor:
						# Case occupée par l'adversaire : valide si la poussée a où aller
						var push_dir = (target_pos - actor.grid_position).sign()
						if is_valid_cell(target_pos + push_dir):
							valid_cells.append(target_pos)

	if current_card.type == CardData.CardType.ATTACK or is_joker:
		# Check all opponents
		for w in wrestlers:
			if w == actor: continue

			var diff = (w.grid_position - actor.grid_position).abs()

			# Attack range is 1 (Adjacent)
			# But we must check pattern
			var is_valid_pos = false

			if is_joker:
				if max(diff.x, diff.y) == 1: is_valid_pos = true
			elif current_card.pattern == CardData.MovePattern.ORTHOGONAL:
				# Distance 1 Manhattan is always orthogonal
				if diff.x + diff.y == 1: is_valid_pos = true
			elif current_card.pattern == CardData.MovePattern.DIAGONAL:
				# Diagonal adjacent means dx=1 and dy=1 (Manhattan=2)
				if diff.x == 1 and diff.y == 1: is_valid_pos = true

			if is_valid_pos:
				valid_cells.append(w.grid_position)

func _update_highlights() -> void:
	_clear_highlights()

	for cell in valid_cells:
		var color = highlight_color_move
		if _get_wrestler_at(cell) != null:
			color = highlight_color_attack

		var sprite = Sprite2D.new()
		sprite.texture = _get_highlight_texture()
		sprite.modulate = color
		sprite.position = grid_to_world(cell)
		add_child(sprite)
		highlight_instances.append(sprite)

func _clear_highlights() -> void:
	for inst in highlight_instances:
		inst.queue_free()
	highlight_instances.clear()
	if swipe_highlight: swipe_highlight.hide()

func _consume_card(card: CardData, is_remote: bool = false) -> void:
	if is_remote: return

	if game_manager:
		game_manager.use_card(card)

	_clear_highlights()
	if swipe_highlight: swipe_highlight.hide()
	current_card = null

func enter_dodge_mode(card: CardData, wrestler: Wrestler) -> void:
	print("GridManager: Entering Dodge Mode with ", card.title, " for ", wrestler.name)
	is_dodging = true
	dodging_wrestler = wrestler
	current_card = card
	# Recalculer les cases valides pour ce mouvement d'esquive
	_calculate_valid_cells()
	_update_highlights()

# Converts a screen/viewport position (as given by input events or Control global positions)
# into world position, honoring the Camera2D transform (position/zoom).
func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos

func _world_to_screen(world_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos

func _get_cell_under_mouse(screen_pos: Vector2) -> Vector2i:
	return world_to_grid(_screen_to_world(screen_pos))

func _get_acting_wrestler() -> Wrestler:
	if is_dodging and dodging_wrestler:
		return dodging_wrestler
	return active_wrestler

func _get_wrestler_by_name(w_name: String) -> Wrestler:
	for w in wrestlers:
		if w.name == w_name:
			return w
	return null

# Helper to find a wrestler on a specific cell
func _get_wrestler_at(pos: Vector2i) -> Wrestler:
	for w in wrestlers:
		if w.grid_position == pos:
			return w
	return null

func _calculate_offset() -> void:
	# Calculate total dimensions
	var total_width = grid_size.x * cell_size
	var total_height = grid_size.y * cell_size

	# We want to center the grid around (0,0).
	board_offset = Vector2(
		- (total_width / 2.0) + (cell_size / 2.0),
		- (total_height / 2.0) + (cell_size / 2.0)
	)

# Converts Grid Coordinates (x, y) to World 2D Coordinates
func grid_to_world(grid_pos: Vector2i) -> Vector2:
	var effective_pos = grid_pos
	if perspective_flip:
		effective_pos = (grid_size - Vector2i(1, 1)) - grid_pos

	return Vector2(effective_pos.x * cell_size, effective_pos.y * cell_size) + board_offset

# Converts World 2D Coordinates to Grid Coordinates (x, y)
func world_to_grid(world_pos: Vector2) -> Vector2i:
	var local_pos = world_pos - board_offset

	var x = round(local_pos.x / cell_size)
	var y = round(local_pos.y / cell_size)

	var grid_pos = Vector2i(int(x), int(y))
	if perspective_flip:
		grid_pos = (grid_size - Vector2i(1, 1)) - grid_pos
	return grid_pos

# Check if a grid position is valid
func is_valid_cell(grid_pos: Vector2i) -> bool:
	return (grid_pos.x >= 0 and grid_pos.x < grid_size.x) and \
		   (grid_pos.y >= 0 and grid_pos.y < grid_size.y)

# Builds the 2D ring visuals: two TileMapLayers (base dalles + random crack overlay).
# Random per-cell tile choice is purely cosmetic (no gameplay impact), so it is not network-synced.
# Random 90° rotations (0/90/180/270), encoded as flip+transpose bit combos so no
# extra alternative tiles need to be authored in the TileSet.
const CRACK_ROTATIONS := [
	0,
	TileSetAtlasSource.TRANSFORM_TRANSPOSE | TileSetAtlasSource.TRANSFORM_FLIP_H,
	TileSetAtlasSource.TRANSFORM_FLIP_H | TileSetAtlasSource.TRANSFORM_FLIP_V,
	TileSetAtlasSource.TRANSFORM_TRANSPOSE | TileSetAtlasSource.TRANSFORM_FLIP_V,
]

func _build_ring_visuals() -> void:
	var layer_position = board_offset - Vector2(cell_size, cell_size) / 2.0

	var ring_base := TileMapLayer.new()
	ring_base.name = "RingBase"
	ring_base.tile_set = RING_TILESET
	ring_base.position = layer_position
	add_child(ring_base)
	move_child(ring_base, 0)

	var ring_cracks := TileMapLayer.new()
	ring_cracks.name = "RingCracks"
	ring_cracks.tile_set = RING_TILESET
	ring_cracks.position = layer_position
	add_child(ring_cracks)
	move_child(ring_cracks, 1)

	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var cell = Vector2i(x, y)
			var base_id = randi() % 4
			ring_base.set_cell(cell, 0, Vector2i(base_id, 0))
			if randf() < crack_chance:
				var crack_id = randi() % 4
				var crack_transform = CRACK_ROTATIONS[randi() % CRACK_ROTATIONS.size()]
				ring_cracks.set_cell(cell, 0, Vector2i(crack_id, 1), crack_transform)

func spawn_wrestlers(p1_data: WrestlerData, p2_data: WrestlerData) -> void:
	if not wrestler_scene:
		printerr("Wrestler scene not set in GridManager inspector.")
		return

	# Clear any previous wrestlers if any (for rematch)
	for w in wrestlers:
		w.queue_free()
	wrestlers.clear()

	# Spawn Player 1
	var p1 = wrestler_scene.instantiate()
	p1.name = "Player 1" # Nommer AVANT d'ajouter à l'arbre pour éviter les conflits RPC
	wrestlers_container.add_child(p1)
	p1.initialize(p1_data)
	wrestlers.append(p1)

	# Place it on a starting cell (Top-Left Corner)
	var p1_start_pos = Vector2i(0, 0)
	p1.set_initial_position(p1_start_pos, self )

	# Spawn a Dummy Opponent
	var p2 = wrestler_scene.instantiate()
	p2.name = "Player 2" # Nommer AVANT d'ajouter à l'arbre
	wrestlers_container.add_child(p2)
	p2.initialize(p2_data)
	wrestlers.append(p2)

	# Place it on opposite corner (Bottom-Right)
	p2.set_initial_position(grid_size - Vector2i(1, 1), self )

	# Connect signals
	p1.died.connect(_on_wrestler_died)
	p2.died.connect(_on_wrestler_died)

	# Set active wrestler for the first turn (will be updated by GameManager)
	active_wrestler = p1

	wrestlers_spawned.emit(wrestlers)

func _on_wrestler_died(w: Wrestler) -> void:
	print("GAME OVER! ", w.name, " has been eliminated!")
	# We don't destroy the object so we can see the KO animation/body
	# w.queue_free()
	wrestlers.erase(w)

	# Simple win condition: Last man standing
	if wrestlers.size() == 1:
		game_over.emit(wrestlers[0].name)

func reset_wrestlers() -> void:
	_clear_highlights()
	current_card = null
	is_dodging = false
	dodging_wrestler = null

	for i in range(wrestlers.size()):
		var w = wrestlers[i]
		w.reset_state()

		var start_pos = Vector2i(0, 0)
		if i == 1:
			start_pos = grid_size - Vector2i(1, 1)

		w.set_initial_position(start_pos, self )

func set_wrestler_collisions(enabled: bool) -> void:
	for w in wrestlers:
		w.set_collision_enabled(enabled)

func handle_swipe_preview(card: CardData, screen_offset: Vector2) -> bool:
	var is_push_hover = false

	# Check for Push Hover (Mouse over opponent with Attack card)
	if active_wrestler and not is_dodging and (card.type == CardData.CardType.ATTACK or card.suit == "Joker"):
		var target = _get_wrestler_at(_get_cell_under_mouse(get_viewport().get_mouse_position()))
		if target and target != active_wrestler:
			var diff = (target.grid_position - active_wrestler.grid_position).abs()
			var is_valid_range = false
			if card.suit == "Joker":
				if max(diff.x, diff.y) == 1: is_valid_range = true
			elif card.pattern == CardData.MovePattern.ORTHOGONAL:
				if diff.x + diff.y == 1: is_valid_range = true
			elif card.pattern == CardData.MovePattern.DIAGONAL:
				if diff.x == 1 and diff.y == 1: is_valid_range = true

			if is_valid_range:
				is_push_hover = true

	# Le highlight jaune directionnel ne s'applique qu'aux déplacements (et Jokers, comme les
	# flèches de swipe dans GameUI) : une attaque classique se joue par survol direct, pas par
	# direction, donc pas de highlight jaune qui viendrait cacher le rouge de la cible valide.
	var show_directional_highlight = card.type != CardData.CardType.ATTACK or card.suit == "Joker"

	if screen_offset.length() < 10.0 or not show_directional_highlight:
		swipe_highlight.hide()
		return is_push_hover

	var target_cell = _get_swipe_target_cell(card, screen_offset)
	if target_cell != Vector2i(-1, -1):
		swipe_highlight.show()
		swipe_highlight.position = grid_to_world(target_cell)
	else:
		swipe_highlight.hide()

	return is_push_hover

func handle_swipe_commit(card: CardData, screen_offset: Vector2, global_pos: Vector2) -> bool:
	swipe_highlight.hide()

	# 1. Check for Push (Drop on Wrestler) - Only for Attack/Joker
	if not is_dodging and (card.type == CardData.CardType.ATTACK or card.suit == "Joker"):
		var target = _get_wrestler_at(_get_cell_under_mouse(global_pos))
		if target and target != active_wrestler:
			# Check Range (Must be adjacent)
			var diff = (target.grid_position - active_wrestler.grid_position).abs()
			var is_valid_range = false
			if card.suit == "Joker":
				if max(diff.x, diff.y) == 1: is_valid_range = true
			elif card.pattern == CardData.MovePattern.ORTHOGONAL:
				if diff.x + diff.y == 1: is_valid_range = true
			elif card.pattern == CardData.MovePattern.DIAGONAL:
				if diff.x == 1 and diff.y == 1: is_valid_range = true

			if is_valid_range:
				print("Initiating Push Attack on ", target.name)
				active_wrestler.look_at_target(grid_to_world(target.grid_position))
				_consume_card(card, false)
				game_manager.initiate_attack_sequence(target, card, true) # is_push = true
				return true

	# 2. Directional Logic (Swipe)
	var target_cell = _get_swipe_target_cell(card, screen_offset)

	# FIX: Auto-target for Attack cards if only one target exists (Relaxed Swipe)
	# This allows "throwing" the card to attack without precise directional aiming if there's only one choice.
	if target_cell == Vector2i(-1, -1) and card.type == CardData.CardType.ATTACK:
		if valid_cells.size() == 1:
			target_cell = valid_cells[0]
			print("Swipe Auto-Targeting: ", target_cell)

	if target_cell != Vector2i(-1, -1):
		# Simulate a click on that cell
		if current_card == card:
			var actor = _get_acting_wrestler()

			var action_data = {
				"x": target_cell.x,
				"y": target_cell.y,
				"card": CardData.serialize(card),
				"player_name": actor.name
			}
			game_manager.send_grid_action(action_data)
			_execute_action(target_cell, card, false, actor.name)

			if is_dodging:
				is_dodging = false
				dodging_wrestler = null
				if game_manager:
					game_manager.on_dodge_complete(card)

			_clear_highlights()
			current_card = null
			return true

	return false

func _get_swipe_target_cell(_card: CardData, screen_offset: Vector2) -> Vector2i:
	var actor = _get_acting_wrestler()
	if not actor: return Vector2i(-1, -1)

	# On projette la position du catcheur sur l'écran pour avoir l'origine du vecteur
	var origin_world = grid_to_world(actor.grid_position)
	var origin_screen = _world_to_screen(origin_world)

	var best_cell = Vector2i(-1, -1)
	var max_dot = 0.5 # Seuil de tolérance (cône de direction)

	for cell in valid_cells:
		var cell_world = grid_to_world(cell)
		var cell_screen = _world_to_screen(cell_world)
		var dir = (cell_screen - origin_screen).normalized()
		var dot = dir.dot(screen_offset.normalized())

		if dot > max_dot:
			max_dot = dot
			best_cell = cell

	return best_cell
