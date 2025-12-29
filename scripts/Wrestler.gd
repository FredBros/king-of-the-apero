class_name Wrestler
extends Node3D

signal died(wrestler: Wrestler)

@export var max_health: int = 10
var current_health: int
var grid_position: Vector2i = Vector2i.ZERO

# Reference to the grid manager to convert grid pos to world pos
var grid_manager: GridManager

# Sets the initial position of the wrestler
func set_initial_position(pos: Vector2i, manager: GridManager) -> void:
	grid_manager = manager
	current_health = max_health
	move_to_grid_position(pos)

# Moves the wrestler to a new grid position (instantly for now)
func move_to_grid_position(new_pos: Vector2i) -> void:
	if not grid_manager:
		printerr("GridManager not set for this wrestler!")
		return
	
	if not grid_manager.is_valid_cell(new_pos):
		printerr("Attempted to move wrestler to invalid cell: ", new_pos)
		return
		
	grid_position = new_pos
	# We use the grid manager to get the correct world coordinates
	var target_world_pos = grid_manager.grid_to_world(grid_position)
	# Add an offset on Y so it sits on top of the floor (capsule height is 2, pivot is at center)
	target_world_pos.y += 1.0
	
	# Animate the movement
	var tween = create_tween()
	tween.tween_property(self, "position", target_world_pos, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# Apply damage to the wrestler
func take_damage(amount: int) -> void:
	current_health -= amount
	print(name, " took ", amount, " damage. HP: ", current_health)
	if current_health <= 0:
		died.emit(self)

# Force move the wrestler (can push out of bounds)
func push_to(new_pos: Vector2i) -> void:
	grid_position = new_pos
	var target_world_pos = grid_manager.grid_to_world(grid_position)
	
	# Check if ejected
	if not grid_manager.is_valid_cell(grid_position):
		print(name, " EJECTED!")
		target_world_pos.y = -5.0 # Fall into the abyss
		died.emit(self)
	else:
		target_world_pos.y += 1.0
		
	var tween = create_tween()
	tween.tween_property(self, "position", target_world_pos, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)