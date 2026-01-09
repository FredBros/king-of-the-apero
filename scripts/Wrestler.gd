class_name Wrestler
extends Node3D

signal died(wrestler: Wrestler)
signal health_changed(current: int, max: int)

@export var max_health: int = 2
var current_health: int
var grid_position: Vector2i = Vector2i.ZERO

# The AnimationPlayer must be assigned in the Inspector or found dynamically
@export var animation_player: AnimationPlayer

# Reference to the grid manager to convert grid pos to world pos
var grid_manager: GridManager

# Sets the initial position of the wrestler
func set_initial_position(pos: Vector2i, manager: GridManager) -> void:
	grid_manager = manager
	current_health = max_health
	health_changed.emit(current_health, max_health)
	
	# Auto-detect AnimationPlayer if not assigned manually
	if not animation_player:
		animation_player = find_child("AnimationPlayer", true, false)
	
	_play_anim("Idle")
	
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
	
	# Animate the movement
	_play_anim("Walk")
	var tween = create_tween()
	tween.tween_property(self, "position", target_world_pos, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func(): _play_anim("Idle"))

# Perform an attack on a target wrestler
func attack(target: Wrestler) -> void:
	_play_anim("Punch")
	
	# Wait for the "impact" moment of the animation (approx 0.2s - 0.4s usually)
	# Ideally, use AnimationPlayer method track, but a timer is fine for POC
	await get_tree().create_timer(0.3).timeout
	
	if target:
		target.take_damage(1)
	
	# Wait for animation to finish before going back to Idle (if not looped)
	await get_tree().create_timer(0.5).timeout
	_play_anim("Idle")

# Apply damage to the wrestler
func take_damage(amount: int) -> void:
	current_health -= amount
	health_changed.emit(current_health, max_health)
	print(name, " took ", amount, " damage. HP: ", current_health)
	
	if current_health <= 0:
		print("Wrestler died. Attempting to play 'KO' animation.")
		_play_anim("KO")
		died.emit(self)
	else:
		_play_anim("Hurt")
		# Wait for Hurt animation to finish roughly
		await get_tree().create_timer(0.5).timeout
		_play_anim("Idle")

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
		pass
		
	var tween = create_tween()
	tween.tween_property(self, "position", target_world_pos, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Rotate the wrestler to face a target position (keeping Y axis upright)
func look_at_target(target_pos: Vector3) -> void:
	var look_pos = target_pos
	look_pos.y = global_position.y
	look_at(look_pos, Vector3.UP)
	rotate_y(PI) # Rotate 180 degrees because the model faces +Z (Backwards)

func _play_anim(anim_name: String) -> void:
	if animation_player:
		if animation_player.has_animation(anim_name):
			animation_player.play(anim_name, 0.2) # 0.2s blend time for smooth transitions
		else:
			printerr("Animation not found: '", anim_name, "'. Available animations: ", animation_player.get_animation_list())