class_name Wrestler
extends CharacterBody3D

signal died(wrestler: Wrestler)
signal health_changed(current: int, max: int)
signal action_completed
signal ejected

@export var max_health: int = 10
var current_health: int
var grid_position: Vector2i = Vector2i.ZERO
@export var wrestler_data: WrestlerData

@export_group("Animation Names")
@export var anim_idle: String = "Idle"
@export var anim_walk: String = "Walk"
@export var anim_punch: String = "Punch"
@export var anim_punch_hit: String = "Punch_Hit" # Variation avec event
@export var anim_hurt: String = "Hurt"
@export var anim_ko: String = "KO"
@export var anim_block: String = "Block"

# The AnimationPlayer must be assigned in the Inspector or found dynamically
@export var animation_player: AnimationPlayer

const FLOATING_FONT = preload("res://assets/fonts/Bangers-Regular.ttf")

# Reference to the grid manager to convert grid pos to world pos
var grid_manager: GridManager
var is_ejected: bool = false

var is_busy: bool = false
var combat_target: Wrestler
var trigger_hurt_on_hit: bool = false

@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	set_collision_enabled(false)
	if wrestler_data:
		initialize(wrestler_data)

func _process(delta: float) -> void:
	if not is_busy and not is_ejected and current_health > 0:
		_face_opponent(delta)

func _face_opponent(delta: float) -> void:
	if not grid_manager: return
	var opponent = null
	for w in grid_manager.wrestlers:
		if w != self:
			opponent = w
			break
	
	if opponent:
		var target_pos = opponent.global_position
		target_pos.y = global_position.y
		
		# Smooth rotation
		var current_quat = global_transform.basis.get_rotation_quaternion()
		var target_transform = global_transform.looking_at(target_pos, Vector3.UP)
		target_transform = target_transform.rotated_local(Vector3.UP, PI) # Model fix
		var target_quat = target_transform.basis.get_rotation_quaternion()
		
		var new_quat = current_quat.slerp(target_quat, 5.0 * delta)
		global_transform.basis = Basis(new_quat)

# Initialize the wrestler from data (Model, Stats)
func initialize(data: WrestlerData) -> void:
	# 1. Stats
	max_health = data.max_health
	current_health = max_health
	
	# 2. Visuals (Instantiate Model)
	if data.model_scene:
		var model_instance = data.model_scene.instantiate()
		add_child(model_instance)
		
		# 3. Animation Connection
		# We look for the AnimationPlayer inside the new model
		animation_player = model_instance.find_child("AnimationPlayer", true, false)
		
		# 4. Connect Animation Events (Relay from Model)
		if model_instance.has_signal("hit_triggered"):
			model_instance.hit_triggered.connect(on_hit_frame)

# Sets the initial position of the wrestler
func set_initial_position(pos: Vector2i, manager: GridManager) -> void:
	grid_manager = manager
	current_health = max_health
	health_changed.emit(current_health, max_health)
	
	# Auto-detect AnimationPlayer if not assigned manually
	if not animation_player:
		animation_player = find_child("AnimationPlayer", true, false)
	
	_play_anim(anim_idle)
	
	# Initial placement is local only, no RPC needed (spawn is deterministic or handled elsewhere)
	_perform_move(pos)

# Moves the wrestler to a new grid position (instantly for now)
func move_to_grid_position(new_pos: Vector2i) -> void:
	_perform_move(new_pos)

func _perform_move(new_pos: Vector2i) -> void:
	# Logique de mouvement (exécutée chez tout le monde)
	is_busy = true
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
	_play_anim(anim_walk)
	var tween = create_tween()
	tween.tween_property(self , "position", target_world_pos, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func():
		_play_anim(anim_idle)
		is_busy = false
		print(name, " move action completed.")
		action_completed.emit()
	)

# Perform an attack on a target wrestler
func attack(target: Wrestler, will_hit: bool = false) -> void:
	is_busy = true
	combat_target = target
	trigger_hurt_on_hit = will_hit
	
	# Prefer the custom animation with events if it exists
	if animation_player and animation_player.has_animation(anim_punch_hit):
		_play_anim(anim_punch_hit)
	else:
		_play_anim(anim_punch)
	
	# Fallback timer (slightly longer to allow anim event to fire)
	await get_tree().create_timer(0.8).timeout
	
	_play_anim(anim_idle)
	is_busy = false
	action_completed.emit()
	combat_target = null
	trigger_hurt_on_hit = false

# Called by AnimationPlayer via Method Track during "Punch"
func on_hit_frame() -> void:
	if trigger_hurt_on_hit and combat_target:
		combat_target.play_hurt_animation()
		trigger_hurt_on_hit = false

func play_hurt_animation() -> void:
	perform_hurt_sequence()

# Apply damage to the wrestler
func take_damage(amount: int, skip_anim: bool = false) -> void:
	current_health -= amount
	health_changed.emit(current_health, max_health)
	show_floating_text("-" + str(amount) + " HP", Color.RED)
	print(name, " took ", amount, " damage. HP: ", current_health)
	
	if current_health <= 0:
		is_busy = true
		print("Wrestler died. Attempting to play 'KO' animation.")
		_play_anim(anim_ko)
		died.emit(self )
	else:
		if not skip_anim:
			perform_hurt_sequence()

func perform_hurt_sequence() -> void:
	is_busy = true
	_play_anim(anim_hurt)
	# Wait for Hurt animation to finish roughly
	await get_tree().create_timer(0.5).timeout
	if not is_ejected and current_health > 0:
		_play_anim(anim_idle)
		is_busy = false
		action_completed.emit()

func block() -> void:
	is_busy = true
	_play_anim(anim_block)
	await get_tree().create_timer(0.5).timeout
	_play_anim(anim_idle)
	is_busy = false
	action_completed.emit()

# Update health from network authority (handles UI sync and animations)
func set_network_health(value: int) -> void:
	var previous_health = current_health
	current_health = value
	health_changed.emit(current_health, max_health)
	
	if current_health <= 0:
		if previous_health > 0:
			_play_anim(anim_ko)
		died.emit(self )
	elif current_health < previous_health:
		_play_anim(anim_hurt)
		await get_tree().create_timer(0.5).timeout
		_play_anim(anim_idle)

# Force move the wrestler (can push out of bounds)
func push_to(new_pos: Vector2i) -> void:
	is_busy = true
	var old_pos = grid_position
	grid_position = new_pos
	var target_world_pos = grid_manager.grid_to_world(grid_position)
	
	# Check if ejected
	if not grid_manager.is_valid_cell(grid_position):
		print(name, " EJECTED!")
		is_ejected = true
		ejected.emit()
		
		# Visuals: Keep on ground level for now
		
		var tween = create_tween()
		tween.tween_property(self , "position", target_world_pos, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_callback(func(): _play_anim(anim_ko))
		
		# Recovery Sequence (4 seconds later)
		get_tree().create_timer(4.0).timeout.connect(func(): _recover_from_ejection(old_pos))
	else:
		var tween = create_tween()
		tween.tween_property(self , "position", target_world_pos, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_callback(func():
			is_busy = false
			action_completed.emit()
		)

func _recover_from_ejection(original_pos: Vector2i) -> void:
	is_ejected = false
	# If dead, do not recover
	if current_health <= 0: return
	
	var return_pos = original_pos
	
	# Check if original position is occupied
	var occupant = grid_manager._get_wrestler_at(return_pos)
	if occupant and occupant != self:
		# Find a valid adjacent cell (fallback)
		var offsets = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
		for offset in offsets:
			var neighbor = original_pos + offset
			if grid_manager.is_valid_cell(neighbor) and grid_manager._get_wrestler_at(neighbor) == null:
				return_pos = neighbor
				break
	
	grid_position = return_pos
	position = grid_manager.grid_to_world(grid_position)
	_play_anim(anim_idle)
	is_busy = false
	action_completed.emit()

func reset_state() -> void:
	is_ejected = false
	is_busy = false
	_play_anim(anim_idle)

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
	label.font = FLOATING_FONT
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

func set_collision_enabled(enabled: bool) -> void:
	if collision_shape:
		collision_shape.disabled = not enabled