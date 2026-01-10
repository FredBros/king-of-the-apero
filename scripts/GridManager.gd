class_name GridManager
extends Node3D

signal game_over(winner_name: String)

# Reference to the Game Manager (injected by Arena)
var game_manager: GameManager

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
@export var cell_size: float = 1.0 # Each cell is 1x1 meter

# Offset to center the grid in the world (0,0,0)
var board_offset: Vector3

# Validation and Highlighting
var valid_cells: Array[Vector2i] = []
var highlight_instances: Array[MeshInstance3D] = []
var highlight_material_move: StandardMaterial3D
var highlight_material_attack: StandardMaterial3D
var active_indicator: MeshInstance3D

func _ready() -> void:
	_calculate_offset()
	_init_materials()
	_init_active_indicator()
	# Debug: Print the world position of the first cell (0,0)
	print("Grid initialized. Cell (0,0) is at World Pos: ", grid_to_world(Vector2i(0, 0)))
	_create_arena_visuals()
	_spawn_debug_wrestler()

func _unhandled_input(event: InputEvent) -> void:
	# Handle mouse click on the grid
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_grid_click(event.position)

# Called by the Game Loop/UI when a card is selected
func on_card_selected(card: CardData) -> void:
	current_card = card
	print("GridManager received card: ", card.title)
	_calculate_valid_cells()
	_update_highlights()

func on_card_discarded(card: CardData) -> void:
	if current_card == card:
		_clear_highlights()
		current_card = null

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

func _update_active_indicator() -> void:
	if not active_indicator: return
	
	if active_indicator.get_parent():
		active_indicator.get_parent().remove_child(active_indicator)
		
	if active_wrestler:
		active_wrestler.add_child(active_indicator)
		# Wrestler pivot is at feet (Y=0). Place indicator slightly above floor.
		active_indicator.position = Vector3(0, 0.05, 0)

func _handle_grid_click(mouse_pos: Vector2) -> void:
	if not active_wrestler or not current_card:
		return
		
	# Empêcher l'input si ce n'est pas notre tour
	if game_manager and not game_manager.is_local_player_active():
		return
		
	var clicked_cell = _get_cell_under_mouse(mouse_pos)
	if not is_valid_cell(clicked_cell):
		return
		
	print("Clicked cell: ", clicked_cell)
	
	# Strict Validation: Check if the cell is in the pre-calculated valid list
	if not clicked_cell in valid_cells:
		print("Invalid move/target!")
		return
	
	# Rotate wrestler towards target
	active_wrestler.look_at_target(to_global(grid_to_world(clicked_cell)))
	# Si on est Client, on envoie la requête au Serveur
	if not multiplayer.is_server():
		request_grid_action.rpc_id(1, clicked_cell, _serialize_card(current_card))
		# On nettoie localement pour l'UI (Optimistic UI ou simple cleanup)
		_clear_highlights()
		current_card = null
		return

	# Si on est Serveur (ou Local), on exécute
	_execute_action(clicked_cell, current_card)

@rpc("any_peer", "call_local", "reliable")
func request_grid_action(clicked_cell: Vector2i, card_data: Dictionary) -> void:
	# Seul le serveur traite cette demande
	if not multiplayer.is_server(): return
	
	var card = _deserialize_card(card_data)
	
	# Validation de sécurité : Est-ce bien le tour du joueur qui envoie la requête ?
	if game_manager:
		var sender_id = multiplayer.get_remote_sender_id()
		var current_player_name = game_manager.players[game_manager.active_player_index].name
		var active_id = game_manager.player_peer_ids.get(current_player_name, -1)
		
		if sender_id != active_id:
			printerr("Action rejetée : Le joueur ", sender_id, " a tenté de jouer pendant le tour de ", active_id)
			return
			
		active_wrestler = game_manager.get_active_wrestler()
	
	_execute_action(clicked_cell, card)

func _execute_action(clicked_cell: Vector2i, card: CardData) -> void:
	if not active_wrestler: return
	
	var is_joker = card.suit == "Joker"
	var target = _get_wrestler_at(clicked_cell)
	
	# Ensure rotation is synced from server to all clients
	active_wrestler.look_at_target(to_global(grid_to_world(clicked_cell)))
	
	# Logic based on card type
	if target:
		if card.type == CardData.CardType.ATTACK or is_joker:
			active_wrestler.attack(target)
			_consume_card(card)
	elif card.type == CardData.CardType.MOVE or is_joker:
		active_wrestler.move_to_grid_position(clicked_cell)
		_consume_card(card)

func _calculate_valid_cells() -> void:
	valid_cells.clear()
	if not active_wrestler or not current_card:
		return
		
	var is_joker = current_card.suit == "Joker"
		
	if current_card.type == CardData.CardType.MOVE or is_joker:
		# Check all cells within range
		var range_val = 1
		for x in range(-range_val, range_val + 1):
			for y in range(-range_val, range_val + 1):
				var offset = Vector2i(x, y)
				var target_pos = active_wrestler.grid_position + offset
				
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
			if w == active_wrestler: continue
			
			var diff = (w.grid_position - active_wrestler.grid_position).abs()
			
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

func _consume_card(card: CardData) -> void:
	if game_manager:
		if multiplayer.is_server():
			# Sur le serveur, on force le traitement car l'action a déjà été validée par request_grid_action
			game_manager.server_process_use_card(card)
		else:
			game_manager.use_card(card)
	_clear_highlights()
	current_card = null

func _get_cell_under_mouse(mouse_pos: Vector2) -> Vector2i:
	var camera = get_viewport().get_camera_3d()
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	var plane = Plane(Vector3.UP, 0) # The floor is at Y=0
	
	var intersection = plane.intersects_ray(from, to)
	if intersection:
		return world_to_grid(intersection)
	return Vector2i(-1, -1)

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

# Spawns a test wrestler on the grid
func _spawn_debug_wrestler() -> void:
	if not wrestler_scene:
		printerr("Wrestler scene not set in GridManager inspector.")
		return
		
	var wrestler_instance = wrestler_scene.instantiate()
	# Ensure it's a Wrestler node
	if not wrestler_instance is Wrestler:
		printerr("The provided scene is not a Wrestler.")
		return
		
	# Add it to the scene tree
	active_wrestler = wrestler_instance
	wrestlers.append(wrestler_instance)
	wrestler_instance.name = "Player" # Nommer AVANT d'ajouter à l'arbre pour éviter les conflits RPC
	add_child(wrestler_instance)
	
	# Place it on a starting cell (Top-Left Corner)
	var start_pos = Vector2i(0, 0)
	wrestler_instance.set_initial_position(start_pos, self)
	
	# Spawn a Dummy Opponent
	var dummy = wrestler_scene.instantiate()
	wrestlers.append(dummy)
	dummy.name = "Dummy" # Nommer AVANT d'ajouter à l'arbre
	add_child(dummy)
	# Place it on opposite corner (Bottom-Right)
	dummy.set_initial_position(grid_size - Vector2i(1, 1), self)
	
	# Connect signals
	wrestler_instance.died.connect(_on_wrestler_died)
	dummy.died.connect(_on_wrestler_died)

func _on_wrestler_died(w: Wrestler) -> void:
	print("GAME OVER! ", w.name, " has been eliminated!")
	# We don't destroy the object so we can see the KO animation/body
	# w.queue_free()
	wrestlers.erase(w)
	
	# Simple win condition: Last man standing
	if wrestlers.size() == 1:
		game_over.emit(wrestlers[0].name)

# --- Helpers Serialization (Dupliqué pour éviter les dépendances circulaires complexes) ---
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
	card.type = int(data.type)
	card.value = int(data.value)
	card.title = data.title
	card.suit = data.suit
	card.pattern = int(data.pattern)
	return card