class_name GridManager
extends Node3D

signal game_over(winner_name: String)

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
@export var cell_size: float = 2.0 # Each cell is 2x2 meters

# Offset to center the grid in the world (0,0,0)
var board_offset: Vector3

func _ready() -> void:
	_calculate_offset()
	# Debug: Print the world position of the first cell (0,0)
	print("Grid initialized. Cell (0,0) is at World Pos: ", grid_to_world(Vector2i(0, 0)))
	_create_debug_grid()
	_spawn_debug_wrestler()

func _unhandled_input(event: InputEvent) -> void:
	# Handle mouse click on the grid
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_grid_click(event.position)

# Called by the Game Loop/UI when a card is selected
func on_card_selected(card: CardData) -> void:
	current_card = card
	print("GridManager received card: ", card.title)

func _handle_grid_click(mouse_pos: Vector2) -> void:
	if not active_wrestler or not current_card:
		return
		
	var clicked_cell = _get_cell_under_mouse(mouse_pos)
	if not is_valid_cell(clicked_cell):
		return
		
	print("Clicked cell: ", clicked_cell)
	
	# Logic based on card type
	if current_card.type == CardData.CardType.MOVE:
		# Calculate Manhattan distance (grid steps)
		var diff = (clicked_cell - active_wrestler.grid_position).abs()
		var distance = diff.x + diff.y
		
		if distance <= current_card.value:
			active_wrestler.move_to_grid_position(clicked_cell)
			# Optional: Consume card / Deselect
		else:
			print("Too far! Max distance: ", current_card.value)
			
	elif current_card.type == CardData.CardType.ATTACK:
		var target = _get_wrestler_at(clicked_cell)
		if target and target != active_wrestler:
			# Check range (Attack is usually adjacent, distance = 1)
			var diff = (clicked_cell - active_wrestler.grid_position).abs()
			if (diff.x + diff.y) == 1:
				target.take_damage(current_card.value)
				
	elif current_card.type == CardData.CardType.THROW:
		var target = _get_wrestler_at(clicked_cell)
		if target and target != active_wrestler:
			# Check range (Throw is usually adjacent)
			var diff = (clicked_cell - active_wrestler.grid_position).abs()
			if (diff.x + diff.y) == 1:
				# Push direction: From Attacker TO Target
				var direction = (clicked_cell - active_wrestler.grid_position)
				var push_dest = clicked_cell + (direction * current_card.value) # Push X cells away
				target.push_to(push_dest)

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

# Create visual meshes for the grid (Debug purpose)
func _create_debug_grid() -> void:
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var grid_pos = Vector2i(x, y)
			var world_pos = grid_to_world(grid_pos)
			
			var cell_visual = MeshInstance3D.new()
			var mesh = PlaneMesh.new()
			# Make it slightly smaller than cell_size to see gaps between cells
			mesh.size = Vector2(cell_size * 0.95, cell_size * 0.95)
			
			cell_visual.mesh = mesh
			cell_visual.position = world_pos
			
			add_child(cell_visual)

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
	add_child(wrestler_instance)
	
	# Place it on a starting cell, e.g., (2, 2)
	var start_pos = Vector2i(2, 2)
	wrestler_instance.set_initial_position(start_pos, self)
	wrestler_instance.name = "Player"
	
	# Spawn a Dummy Opponent
	var dummy = wrestler_scene.instantiate()
	wrestlers.append(dummy)
	add_child(dummy)
	dummy.set_initial_position(Vector2i(2, 3), self)
	dummy.name = "Dummy"
	
	# Connect signals
	wrestler_instance.died.connect(_on_wrestler_died)
	dummy.died.connect(_on_wrestler_died)

func _on_wrestler_died(w: Wrestler) -> void:
	print("GAME OVER! ", w.name, " has been eliminated!")
	w.queue_free()
	wrestlers.erase(w)
	
	# Simple win condition: Last man standing
	if wrestlers.size() == 1:
		game_over.emit(wrestlers[0].name)