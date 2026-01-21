class_name Wrestler
extends Node3D

signal died(wrestler: Wrestler)
signal health_changed(current: int, max: int)

@export var max_health: int = 10
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
	
	# Initial placement is local only, no RPC needed (spawn is deterministic or handled elsewhere)
	_perform_move(pos)

# Moves the wrestler to a new grid position (instantly for now)
func move_to_grid_position(new_pos: Vector2i) -> void:
	_perform_move(new_pos)

func _perform_move(new_pos: Vector2i) -> void:
	# Logique de mouvement (exécutée chez tout le monde)
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
func attack(target: Wrestler, is_remote: bool = false) -> void:
	_play_anim("Punch")
	
	# Wait for the "impact" moment of the animation (approx 0.2s - 0.4s usually)
	# Ideally, use AnimationPlayer method track, but a timer is fine for POC
	await get_tree().create_timer(0.3).timeout
	
	# Damage logic is now handled by GameManager via initiate_attack_sequence -> ATTACK_RESULT
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

func block() -> void:
	_play_anim("Block")
	await get_tree().create_timer(0.5).timeout
	_play_anim("Idle")

# Update health from network authority (handles UI sync and animations)
func set_network_health(value: int) -> void:
	var previous_health = current_health
	current_health = value
	health_changed.emit(current_health, max_health)
	
	if current_health < previous_health:
		if current_health <= 0:
			_play_anim("KO")
			died.emit(self)
		else:
			_play_anim("Hurt")
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
	# Local visual update immediately
	_perform_look_at(target_pos)

func _perform_look_at(target_pos: Vector3) -> void:
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

func show_floating_text(text: String, color: Color) -> void:
	var label = Label3D.new()
	label.text = text
	label.modulate = color
	label.font_size = 128
	label.pixel_size = 0.004 # Ajuste la taille dans le monde 3D
	label.outline_render_priority = 0
	label.outline_modulate = Color.BLACK
	label.outline_size = 32
	label.uppercase = true
	label.no_depth_test = true # Toujours visible (au-dessus des modèles)
	
	add_child(label)
	label.position = Vector3(0, 2.5, 0) # Au-dessus de la tête
	
	# Orientation "Pseudo 3D" (Regarde la caméra mais avec un angle stylé)
	var camera = get_viewport().get_camera_3d()
	if camera:
		# On aligne la rotation sur celle de la caméra (Billboard manuel plus stable que look_at)
		label.global_rotation = camera.global_rotation
		# Ajout du "biais" (Tilt)
		label.rotate_y(deg_to_rad(-15))
		label.rotate_x(deg_to_rad(-10))
	else:
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	
	# Animation Pop & Float
	label.scale = Vector3.ZERO
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", label.position.y + 1.0, 1.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(1.0)
	tween.chain().tween_callback(label.queue_free)