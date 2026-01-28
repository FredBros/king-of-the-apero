class_name GridManager
extends Node3D

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
@export var cell_size: float = 1.5 # Each cell is 1.5x1.5 meter

# Offset to center the grid in the world (0,0,0)
var board_offset: Vector3

# Validation and Highlighting
var valid_cells: Array[Vector2i] = []
var highlight_instances: Array[MeshInstance3D] = []
var highlight_material_move: StandardMaterial3D
var highlight_material_attack: StandardMaterial3D
var active_indicator: MeshInstance3D
var swipe_highlight: MeshInstance3D

var is_dodging: bool = false
var dodging_wrestler: Wrestler

func _ready() -> void:
	_calculate_offset()
	_init_materials()
	_init_active_indicator()
	_init_swipe_highlight()
	# Debug: Print the world position of the first cell (0,0)
	print("Grid initialized. Cell (0,0) is at World Pos: ", grid_to_world(Vector2i(0, 0)))
	_create_arena_visuals()

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
	
	print("DEBUG: Drop detected at screen pos: ", screen_pos)
	
	# 1. Try to find wrestler via Physics Raycast first (Better for 3D objects with height)
	var target = _get_wrestler_under_mouse(screen_pos)
	if target:
		print("DEBUG: Raycast found wrestler: ", target.name)
	else:
		print("DEBUG: Raycast found NO wrestler.")
	
	var clicked_cell = Vector2i(-1, -1)
	
	# 2. Fallback to Grid Cell logic (Floor plane intersection)
	if not target:
		clicked_cell = _get_cell_under_mouse(screen_pos)
		print("DEBUG: Fallback to grid cell: ", clicked_cell)
		# Note: clicked_cell peut être invalide si on drop hors de la grille
		target = _get_wrestler_at(clicked_cell)
		if target: print("DEBUG: Found wrestler at cell via grid logic: ", target.name)
	else:
		clicked_cell = target.grid_position
	
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
			active_wrestler.look_at_target(to_global(grid_to_world(clicked_cell)))
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
		active_wrestler.look_at_target(to_global(grid_to_world(auto_target.grid_position)))
		_consume_card(card, false)
		game_manager.initiate_attack_sequence(auto_target, card, false) # is_push = false
	elif valid_targets.size() > 1:
		print("Swipe Ambiguous: Multiple targets. Please select card then click target.")
		# Optionnel : Sélectionner la carte pour montrer les cibles
		on_card_selected(card)
	else:
		print("Swipe Failed: No targets in range.")

func _get_wrestler_under_mouse(mouse_pos: Vector2) -> Wrestler:
	var space_state = get_world_3d().direct_space_state
	var camera = get_viewport().get_camera_3d()
	if not camera: return null
	
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	if result:
		print("DEBUG: Raycast hit object: ", result.collider.name)
		var collider = result.collider
		var node = collider
		# Walk up to find Wrestler
		while node:
			if node is Wrestler:
				return node
			node = node.get_parent()
			if node == self or node == get_tree().root: break
	return null

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

func _init_materials() -> void:
	highlight_material_move = StandardMaterial3D.new()
	highlight_material_move.albedo_color = Color(0.4, 0.6, 1.0, 0.5) # Blue transparent
	highlight_material_move.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	highlight_material_attack = StandardMaterial3D.new()
	highlight_material_attack.albedo_color = Color(1.0, 0.4, 0.4, 0.5) # Red transparent
	highlight_material_attack.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

func _init_active_indicator() -> void:
	active_indicator = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = cell_size * 0.35
	mesh.bottom_radius = cell_size * 0.35
	mesh.height = 0.05
	active_indicator.mesh = mesh
	active_indicator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 1.0, 0.2, 0.6) # Green transparent
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	active_indicator.material_override = material

func _init_swipe_highlight() -> void:
	swipe_highlight = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(cell_size * 0.9, cell_size * 0.9)
	swipe_highlight.mesh = plane
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 1.0, 0.0, 0.6) # Yellow/Gold
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	swipe_highlight.material_override = material
	add_child(swipe_highlight)
	swipe_highlight.hide()

func _update_active_indicator() -> void:
	if not active_indicator: return
	
	if active_indicator.get_parent():
		active_indicator.get_parent().remove_child(active_indicator)
		
	if active_wrestler:
		active_wrestler.add_child(active_indicator)
		# Wrestler pivot is at feet (Y=0). Place indicator slightly above floor.
		active_indicator.position = Vector3(0, 0.05, 0)

func _handle_grid_click(mouse_pos: Vector2) -> void:
	var actor = _get_acting_wrestler()
	if not actor or not current_card:
		return
		
	# Empêcher l'input si ce n'est pas notre tour, SAUF si on est en train d'esquiver
	if game_manager and not game_manager.is_local_player_active() and not is_dodging:
		return
		
	var clicked_cell = Vector2i(-1, -1)
	var wrestler_under_mouse = _get_wrestler_under_mouse(mouse_pos)
	if wrestler_under_mouse:
		clicked_cell = wrestler_under_mouse.grid_position
	else:
		clicked_cell = _get_cell_under_mouse(mouse_pos)
		
	if not is_valid_cell(clicked_cell):
		return
		
	print("Clicked cell: ", clicked_cell)
	
	# Strict Validation: Check if the cell is in the pre-calculated valid list
	if not clicked_cell in valid_cells:
		print("Invalid move/target!")
		return
	
	# Rotate wrestler towards target
	actor.look_at_target(to_global(grid_to_world(clicked_cell)))
	
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
	
	# Ensure rotation is synced from server to all clients
	actor.look_at_target(to_global(grid_to_world(clicked_cell)))
	
	# Logic based on card type
	if target:
		if card.type == CardData.CardType.ATTACK or is_joker:
			# Pass the network context down to the attack method.
			# Visuals are now deferred until reaction resolution (GameManager)
			# actor.attack(target, is_remote)
			_consume_card(card, is_remote)
			
			if not is_remote:
				game_manager.initiate_attack_sequence(target, card, false) # is_push = false (Standard Attack)
	elif card.type == CardData.CardType.MOVE or is_joker:
		actor.move_to_grid_position(clicked_cell)
		_consume_card(card, is_remote)

func _calculate_valid_cells() -> void:
	valid_cells.clear()
	var actor = _get_acting_wrestler()
	if not actor or not current_card:
		return
		
	var is_joker = current_card.suit == "Joker"
		
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
				if is_joker:
					valid_pattern = true
				elif current_card.pattern == CardData.MovePattern.ORTHOGONAL:
					if offset.x == 0 or offset.y == 0: valid_pattern = true
				elif current_card.pattern == CardData.MovePattern.DIAGONAL:
					if abs(offset.x) == abs(offset.y): valid_pattern = true
				
				if not valid_pattern: continue
				
				var diff = offset.abs()
				
				# Distance Check (Range 1)
				var valid_dist = false
				if is_joker:
					if diff.x <= 1 and diff.y <= 1 and (diff.x + diff.y > 0): valid_dist = true
				elif current_card.pattern == CardData.MovePattern.ORTHOGONAL:
					if diff.x + diff.y == 1: valid_dist = true
				elif current_card.pattern == CardData.MovePattern.DIAGONAL:
					if diff.x == 1 and diff.y == 1: valid_dist = true
				
				if valid_dist:
					# Move requires empty cell
					if _get_wrestler_at(target_pos) == null:
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
		var material = highlight_material_move
		if _get_wrestler_at(cell) != null:
			material = highlight_material_attack
			
		var mesh_inst = MeshInstance3D.new()
		var plane = PlaneMesh.new()
		plane.size = Vector2(cell_size * 0.9, cell_size * 0.9)
		mesh_inst.mesh = plane
		mesh_inst.material_override = material
		mesh_inst.position = grid_to_world(cell)
		mesh_inst.position.y = 0.1 # Slightly above ground to avoid z-fighting
		add_child(mesh_inst)
		highlight_instances.append(mesh_inst)

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

func _get_cell_under_mouse(mouse_pos: Vector2) -> Vector2i:
	var camera = get_viewport().get_camera_3d()
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	var plane = Plane(Vector3.UP, 0) # The floor is at Y=0
	
	var intersection = plane.intersects_ray(from, to)
	if intersection:
		return world_to_grid(intersection)
	return Vector2i(-1, -1)

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
	var total_depth = grid_size.y * cell_size
	
	# We want to center the grid around (0,0,0).
	# Start position (Top-Left) calculation:
	# X: -Width/2 + Half Cell (to center the pivot of the cell)
	# Z: -Depth/2 + Half Cell
	board_offset = Vector3(
		- (total_width / 2.0) + (cell_size / 2.0),
		0.0,
		- (total_depth / 2.0) + (cell_size / 2.0)
	)

# Converts Grid Coordinates (x, y) to World 3D Coordinates (x, 0, z)
func grid_to_world(grid_pos: Vector2i) -> Vector3:
	var x = grid_pos.x * cell_size
	var z = grid_pos.y * cell_size
	
	# Apply offset. Note: Grid Y maps to World Z.
	return Vector3(x, 0.0, z) + board_offset

# Converts World 3D Coordinates to Grid Coordinates (x, y)
func world_to_grid(world_pos: Vector3) -> Vector2i:
	var local_pos = world_pos - board_offset
	
	var x = round(local_pos.x / cell_size)
	var y = round(local_pos.z / cell_size)
	
	return Vector2i(int(x), int(y))

# Check if a grid position is valid
func is_valid_cell(grid_pos: Vector2i) -> bool:
	return (grid_pos.x >= 0 and grid_pos.x < grid_size.x) and \
		   (grid_pos.y >= 0 and grid_pos.y < grid_size.y)

# Create the 3D visuals for the Arena (Floor only)
func _create_arena_visuals() -> void:
	var total_width = grid_size.x * cell_size
	var total_depth = grid_size.y * cell_size
	var border_size = 1.0 # 1 meter border around the grid
	
	# 1. The Border (Base of the board)
	var border_mesh = BoxMesh.new()
	border_mesh.size = Vector3(total_width + (border_size * 2), 0.5, total_depth + (border_size * 2))
	
	var border_instance = MeshInstance3D.new()
	border_instance.mesh = border_mesh
	# Position: Center X/Z. Y is slightly lower so tiles sit on top.
	# Tiles will be at Y=0 (top surface). Border top should be slightly below or same level.
	# Let's put border center at Y = -0.26 (since height is 0.5, top is at -0.01) to avoid Z-fighting
	border_instance.position = Vector3(0, -0.26, 0)
	
	var border_mat = StandardMaterial3D.new()
	border_mat.albedo_color = Color(0.3, 0.2, 0.1) # Brown/Wood color
	border_instance.material_override = border_mat
	add_child(border_instance)
	
	# 2. The Tiles (Checkerboard)
	var tile_mat_1 = StandardMaterial3D.new()
	tile_mat_1.albedo_color = Color(0.4, 0.4, 0.4) # Grey
	
	var tile_mat_2 = StandardMaterial3D.new()
	tile_mat_2.albedo_color = Color(0.2, 0.2, 0.2) # Dark Grey
	
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var tile = MeshInstance3D.new()
			var mesh = BoxMesh.new()
			# Slightly smaller than cell_size to show gaps/grid lines
			mesh.size = Vector3(cell_size * 0.95, 0.1, cell_size * 0.95)
			tile.mesh = mesh
			
			# Position: Use grid_to_world logic.
			# Y position: Center at -0.05 so top surface is at 0.0
			tile.position = grid_to_world(Vector2i(x, y)) + Vector3(0, -0.05, 0)
			
			# Checkerboard pattern
			if (x + y) % 2 == 0:
				tile.material_override = tile_mat_1
			else:
				tile.material_override = tile_mat_2
				
			add_child(tile)

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
	add_child(p1)
	p1.initialize(p1_data)
	wrestlers.append(p1)
	
	# Place it on a starting cell (Top-Left Corner)
	var p1_start_pos = Vector2i(0, 0)
	p1.set_initial_position(p1_start_pos, self)
	
	# Spawn a Dummy Opponent
	var p2 = wrestler_scene.instantiate()
	p2.name = "Player 2" # Nommer AVANT d'ajouter à l'arbre
	add_child(p2)
	p2.initialize(p2_data)
	wrestlers.append(p2)
	
	# Place it on opposite corner (Bottom-Right)
	p2.set_initial_position(grid_size - Vector2i(1, 1), self)
	
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
			
		w.set_initial_position(start_pos, self)

func set_wrestler_collisions(enabled: bool) -> void:
	for w in wrestlers:
		w.set_collision_enabled(enabled)

func handle_swipe_preview(card: CardData, screen_offset: Vector2) -> void:
	if screen_offset.length() < 10.0:
		swipe_highlight.hide()
		return
		
	var target_cell = _get_swipe_target_cell(card, screen_offset)
	if target_cell != Vector2i(-1, -1):
		swipe_highlight.show()
		swipe_highlight.position = grid_to_world(target_cell)
		swipe_highlight.position.y = 0.15 # Above normal highlights
	else:
		swipe_highlight.hide()

func handle_swipe_commit(card: CardData, screen_offset: Vector2, global_pos: Vector2) -> void:
	swipe_highlight.hide()
	
	# 1. Check for Push (Drop on Wrestler) - Only for Attack/Joker
	if not is_dodging and (card.type == CardData.CardType.ATTACK or card.suit == "Joker"):
		var target = _get_wrestler_under_mouse(global_pos)
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
				active_wrestler.look_at_target(to_global(grid_to_world(target.grid_position)))
				_consume_card(card, false)
				game_manager.initiate_attack_sequence(target, card, true) # is_push = true
				return
	
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
			actor.look_at_target(to_global(grid_to_world(target_cell)))
			
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

func _get_swipe_target_cell(card: CardData, screen_offset: Vector2) -> Vector2i:
	var actor = _get_acting_wrestler()
	if not actor: return Vector2i(-1, -1)
	
	var camera = get_viewport().get_camera_3d()
	# On projette la position du catcheur sur l'écran pour avoir l'origine du vecteur
	var origin_world = grid_to_world(actor.grid_position)
	var origin_screen = camera.unproject_position(origin_world)
	
	var best_cell = Vector2i(-1, -1)
	var max_dot = 0.5 # Seuil de tolérance (cône de direction)
	
	for cell in valid_cells:
		var cell_world = grid_to_world(cell)
		var cell_screen = camera.unproject_position(cell_world)
		var dir = (cell_screen - origin_screen).normalized()
		var dot = dir.dot(screen_offset.normalized())
		
		if dot > max_dot:
			max_dot = dot
			best_cell = cell
			
	return best_cell