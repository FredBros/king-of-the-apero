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
const BLOOD_VFX = preload("res://scenes/BloodParticles.tscn")
const SOUND_POOL_SCENE = preload("res://scenes/Components/SoundPoolComponent.tscn")
const DEFAULT_SOUND_SHOOTING_PUNCH = preload("res://assets/Sounds/Punch/Voice/shoutingpunches_male_default.wav")
const DEFAULT_SOUND_PUNCH = preload("res://assets/Sounds/Punch/Impact/punch_default.mp3")
const DEFAULT_SOUND_HURT = preload("res://assets/Sounds/Hurt/hurt_default.ogg")
const DEFAULT_SOUND_BLOCK = preload("res://assets/Sounds/block/block_default.wav")
const DEFAULT_SOUND_PUSHED = preload("res://assets/Sounds/Push/pushed_defaults.wav")
const DEFAULT_SOUND_FALL_IMPACT = preload("res://assets/Sounds/KO/Fall Impact/346694__deleted_user_2104797__body-fall_02.wav")
const DEFAULT_SOUND_DEATH_RATTLE = preload("res://assets/Sounds/KO/Death Rattle/death_rattle_default.wav")

# Reference to the grid manager to convert grid pos to world pos
var grid_manager
var is_ejected: bool = false

var is_busy: bool = false
var combat_target: Wrestler
var trigger_hurt_on_hit: bool = false
# Assurez-vous que cette variable est bien présente
var current_attack_is_push: bool = false

@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var sound_pool
var _pending_push_callback: Callable

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
	# Setup Audio
	sound_pool = SOUND_POOL_SCENE.instantiate()
	add_child(sound_pool)
	
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
		if model_instance.has_signal("ko_impact_triggered"):
			model_instance.ko_impact_triggered.connect(on_ko_impact)

# Sets the initial position of the wrestler
func set_initial_position(pos: Vector2i, manager) -> void:
	grid_manager = manager
	reset_state() # On s'assure que le catcheur n'est plus "busy", "ejected" ou mort
	current_health = max_health
	health_changed.emit(current_health, max_health)
	
	# Auto-detect AnimationPlayer if not assigned manually
	if not animation_player:
		animation_player = find_child("AnimationPlayer", true, false)
	
	_play_anim(anim_idle)
	
	# FIX: Teleport directly instead of walking to avoid issues and visual weirdness during restart
	grid_position = pos
	if grid_manager:
		position = grid_manager.grid_to_world(grid_position)
		# Force orientation towards center/opponent immediately
		_face_opponent(1.0)

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
# La signature doit correspondre à l'appel dans GameManager (3 arguments)
func attack(target: Wrestler, will_hit: bool = false, is_push: bool = false) -> void:
	is_busy = true
	combat_target = target
	trigger_hurt_on_hit = will_hit
	current_attack_is_push = is_push
	
	# Son d'effort (Swing) au début de l'attaque
	_play_sound_or_default(wrestler_data.sound_shooting_punch, DEFAULT_SOUND_SHOOTING_PUNCH)
	
	# Prefer the custom animation with events if it exists
	if animation_player and animation_player.has_animation(anim_punch_hit):
		_play_anim(anim_punch_hit)
	else:
		_play_anim(anim_punch)
	
	# Fallback timer (slightly longer to allow anim event to fire)
	await get_tree().create_timer(0.8).timeout
	
	# Safety check: If the animation event didn't fire (e.g. missing track), trigger impact now
	if trigger_hurt_on_hit and combat_target:
		_play_sound_or_default(wrestler_data.sound_punch, DEFAULT_SOUND_PUNCH, -4.0)
		if current_attack_is_push:
			combat_target.execute_pending_push()
		combat_target.play_hurt_animation(not current_attack_is_push)
		trigger_hurt_on_hit = false
	
	_play_anim(anim_idle)
	is_busy = false
	action_completed.emit()
	combat_target = null
	trigger_hurt_on_hit = false
	current_attack_is_push = false

# Called by AnimationPlayer via Method Track during "Punch"
func on_hit_frame() -> void:
	if trigger_hurt_on_hit and combat_target:
		# Son d'impact (Punch) seulement si on touche
		_play_sound_or_default(wrestler_data.sound_punch, DEFAULT_SOUND_PUNCH, -4.0)
		if current_attack_is_push:
			combat_target.execute_pending_push()
		combat_target.play_hurt_animation(not current_attack_is_push)
		trigger_hurt_on_hit = false

func play_hurt_animation(spawn_blood: bool = true) -> void:
	_play_sound_or_default(wrestler_data.sound_hurt, DEFAULT_SOUND_HURT, -2.0)
	if spawn_blood:
		_spawn_blood_effect()
	perform_hurt_sequence()

# Apply damage to the wrestler
func take_damage(amount: int, skip_anim: bool = false) -> void:
	current_health -= amount
	health_changed.emit(current_health, max_health)
	show_floating_text("-" + str(amount) + " HP", Color.RED)
	print(name, " took ", amount, " damage. HP: ", current_health)
	
	if current_health <= 0:
		_spawn_blood_effect()
		is_busy = true
		# Son de "râle de mort" déplacé dans on_ko_impact
		print("Wrestler died. Attempting to play 'KO' animation.")
		_play_anim(anim_ko)
		died.emit(self )
	else:
		if not skip_anim:
			_spawn_blood_effect()
			_play_sound_or_default(wrestler_data.sound_hurt, DEFAULT_SOUND_HURT, -2.0)
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
	_play_sound_or_default(wrestler_data.sound_block, DEFAULT_SOUND_BLOCK)
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
		perform_hurt_sequence()

# Force move the wrestler (can push out of bounds)
func push_to(new_pos: Vector2i) -> void:
	is_busy = true
	var old_pos = grid_position
	grid_position = new_pos
	var target_world_pos = grid_manager.grid_to_world(grid_position)
	
	# On prépare la logique visuelle mais on ne l'exécute pas tout de suite.
	# Elle sera déclenchée par l'attaquant via execute_pending_push() au moment de l'impact (on_hit_frame).
	_pending_push_callback = func():
		# Check if ejected
		if not grid_manager.is_valid_cell(grid_position):
			print(name, " EJECTED!")
			is_ejected = true
			ejected.emit()
			
			# Visuals: Keep on ground level for now
			
			var tween = create_tween()
			_play_sound_or_default(wrestler_data.sound_pushed, DEFAULT_SOUND_PUSHED)
			tween.tween_property(self , "position", target_world_pos, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_callback(func(): _play_anim(anim_ko))
			
			# Recovery Sequence (4 seconds later)
			get_tree().create_timer(4.0).timeout.connect(func(): _recover_from_ejection(old_pos))
		else:
			var tween = create_tween()
			# Son de poussée (réception)
			_play_sound_or_default(wrestler_data.sound_hurt, DEFAULT_SOUND_HURT, -2.0)
			_play_sound_or_default(wrestler_data.sound_pushed, DEFAULT_SOUND_PUSHED)
			tween.tween_property(self , "position", target_world_pos, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_callback(func():
				is_busy = false
				action_completed.emit()
			)

func execute_pending_push() -> void:
	if _pending_push_callback:
		_pending_push_callback.call()
		_pending_push_callback = Callable()

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

func _play_sound(stream: AudioStream) -> void:
	if stream and sound_pool:
		sound_pool.play_varied(stream)

func _play_sound_or_default(stream: AudioStream, default_stream: AudioStream, volume_offset: float = 0.0) -> void:
	var stream_to_play = stream if stream else default_stream
	if stream_to_play and sound_pool:
		sound_pool.play_varied(stream_to_play, volume_offset)

# Appelé par l'AnimationPlayer via la piste "Call Method" dans l'animation KO
func on_ko_impact() -> void:
	_play_sound_or_default(wrestler_data.sound_fall_impact, DEFAULT_SOUND_FALL_IMPACT)
	_play_sound_or_default(wrestler_data.sound_death_rattle, DEFAULT_SOUND_DEATH_RATTLE)
	# Ici on pourrait aussi ajouter un Screen Shake via un signal vers l'Arena

# Appelé par le GameManager lors d'une esquive réussie
func play_dodge_sound() -> void:
	_play_sound(wrestler_data.sound_dodge)

func show_floating_text(text: String, color: Color) -> void:
	var label = Label3D.new()
	label.text = text
	label.font = FLOATING_FONT
	label.modulate = color
	label.font_size = 128
	label.pixel_size = 0.004 # Ajuste la taille dans le monde 3D
	label.outline_render_priority = 0
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

func _spawn_blood_effect() -> void:
	if BLOOD_VFX:
		var vfx = BLOOD_VFX.instantiate()
		if vfx:
			add_child(vfx)
			vfx.position = Vector3(0, 1.5, 0) # Hauteur approximative du torse

func set_collision_enabled(enabled: bool) -> void:
	if collision_shape:
		collision_shape.disabled = not enabled